--==============================================================================
-- GUILDBANKSTER: Template-based Guild Bank Management for Turtle WoW
--==============================================================================
-- File: GuildBankster.lua
-- Author: Weird Vibes Guild <Turtle WoW>
-- Version: 2.0
-- Created: 2024
-- 
-- Description:
--   A comprehensive addon that provides template-based guild bank management
--   and automated restocking capabilities for World of Warcraft 1.12 (Turtle WoW).
--
-- Features:
--   • Template System: Define what items should be stored in each guild bank slot
--   • Automated Restocking: Automatically restock from inventory and personal bank
--   • Per-Guild Settings: Settings are saved separately for each guild
--   • Visual Integration: Seamlessly integrates with Turtle WoW's guild bank UI
--   • Smart Consolidation: Intelligently combines and moves items for efficiency
--
-- Dependencies:
--   • Turtle WoW Guild Bank UI (TW_GUILDBANK)
--   • World of Warcraft 1.12 client
--
-- Usage:
--   1. Open guild bank and click "Templates" tab
--   2. Drag items to template slots to define desired layout
--   3. Right-click template tabs to activate/deactivate them  
--   4. Click "Restock" button to automatically fill active templates
--
-- License: MIT License - Free for use and modification
--==============================================================================

local _G = _G or getfenv(0)

--==============================================================================
-- NPC DATA: Vault Keepers and Banking NPCs
--==============================================================================
-- Purpose: Static data for NPC identification and location mapping
-- Used by: Event handlers for bank integration and gossip system
--==============================================================================

-- Vault keeper NPCs mapped to their cities (unused but kept for reference)
local vault_npcs = {
  ["Vault Keeper Faredin"] = "Darnassus",
  ["Vault Keeper Teller Plushner"] = "Stormwind",
  ["Vault Keeper Golgan"] = "Ironforge",
  -- ["Vault Keeper Lorien Cogmender"] = "Ironforge", ???

  ["Vault Keeper Are"] = "Orgrimmar",
  ["Vault Keeper Gewana"] = "Thunder Bluff",
  ["Vault Keeper Arthur"] = "Undercity",
}

local in_range_npc = {
  ["Koma"] = { name = "Koma", city = "Orgrimmar" },
  ["Chesmu"] = { name = "Chesmu", city = "Thunder Bluff" },
  ["Randolph Montague"] = { name = "Randolph Montague", city = "Undercity" },
  ["Idriana"] = { name = "Idriana", city = "Darnassus" },
  ["Garryeth"] = { name = "Garryeth", city = "Darnassus" },
  ["Lairn"] = { name = "Lairn", city = "Darnassus" },
  ["Caravan Kodo"] = { name = "Caravan Kodo", city = "any" },
  ["Forworn Mule"] = { name = "Forworn Mule", city = "any" },
}

--==============================================================================
-- CONFIGURATION & CONSTANTS  
--==============================================================================
-- Purpose: Centralized configuration values and game constants
-- Dependencies: None - these are the base configuration values
--==============================================================================

-- Core game constants
local MAX_TABS = 5
local MAX_SLOTS = 98
local MAX_RETRIES = 3
local RESTOCK_TIMEOUT = 2 -- seconds before forcing next job if stuck

-- Bank bag constants
local bank_bag_ids = {-1, 5, 6, 7, 8, 9, 10}
local ordered_bags = {0, 1, 2, 3, 4, -1, 5, 6, 7, 8, 9, 10}

--==============================================================================
-- STATE MANAGEMENT: Global Variables and Runtime State
--==============================================================================
-- Purpose: All mutable state variables organized by functional area
-- Dependencies: Constants (above) - uses MAX_TABS, MAX_SLOTS, etc.
-- Used by: All major systems throughout the addon
--==============================================================================
-- Restock variables (defined early so OnUpdate can access them)
local restock_jobs = {} -- Array of job tables; always shift after completion
local missing_totals = {} -- [itemID] = total_missing
local last_action_time = 0
local current_operation = {} -- Track current operation for debugging
local pre_operation_state = {} -- Track inventory state before operation
local operation_retry_count = 0

-- Continuation system state
local continuation_frame = CreateFrame("Frame")
local continuation_queue = {}
local continuation_active = false
local continuation_timeout_check = 0

-- Guild settings state
local CurrentGuildSettings = nil

-- Template state
local TemplateFrames = {}
local CurrentTemplateTab = nil  -- Start as nil so we can detect first entry
local TemplateMode = false
local HeldTemplateItem = nil

-- UI hook state
local GuildBankFrameTabTitle_SetText_Original = nil
local GuildBankFrame_OnShow_Original
local GuildBankFrame_OnHide_Original
local GuildBankFrameBottomTab_OnClick_Original
local GuildBankFrameTab_OnClick_Original

--==============================================================================
-- CORE UTILITIES: Helper Functions and WoW API Wrappers
--==============================================================================
-- Purpose: Essential utility functions used throughout the addon
-- Dependencies: State variables (above) for gb_print function
-- Used by: All major systems - these are the foundation functions
--==============================================================================

-- Function: gb_print
-- Purpose: Standardized addon message printing with consistent formatting  
-- Parameters: msg (string) - message to display in chat
-- Used by: All systems throughout addon for user communication
local function gb_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff14a868GuildBankster:|r "..msg)
end

-- Function: getIDFromLink  
-- Purpose: Extract numeric item ID from WoW item link string
-- Parameters: link (string) - WoW item link format "|Hitem:12345:...|h"
-- Returns: string - numeric item ID, or nil if parsing fails
-- Used by: All inventory and template systems for item identification
function getIDFromLink(link)
  local _, _, id = string.find(link, "item:(%d+)")
  return id
end

-- Function: GetItemIcon
-- Purpose: Get item texture path for vanilla WoW (extracts 9th return value from GetItemInfo)
-- Parameters: itemLink (string) - WoW item link  
-- Returns: string - texture path for item icon, or nil if item not found
-- Used by: Template system for displaying item icons in template slots
function GetItemIcon(itemLink)
    if not itemLink then return nil end
    local itemID = getIDFromLink(itemLink)
    if itemID then
        -- Vanilla GetItemInfo returns:
        -- itemName, itemLink, itemRarity, itemLevel, itemMinLevel,
        -- itemType, itemSubType, itemStackCount, itemTexture
        local itemName, link, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemTexture = GetItemInfo(itemID)
        return itemTexture
    end
    return nil
end

-- Function: ClearTemplateCursor
-- Purpose: Clear all cursor states (both template held items and guild bank cursor frames)
-- Used by: Template system when canceling operations or clearing cursor
local function ClearTemplateCursor()
    -- Clear template held item
    HeldTemplateItem = nil

    -- Hide guild bank cursor frames
    if GuildBank and GuildBank.cursorFrame then
        GuildBank.cursorFrame:Hide()
    end
    if GuildBankFrameCursorItemFrame then
        GuildBankFrameCursorItemFrame:Hide()
    end
    ClearCursor()
end

-- Function: IsItemBound
-- Purpose: Check if an item in a bag slot is bound (soulbound) using tooltip scanning
-- Parameters: bag (number), slot (number) - container and slot to check
-- Returns: boolean - true if item is bound, false otherwise
-- Used by: Template system to warn about bound items
local function IsItemBound(bag, slot)
  -- Create or reuse hidden tooltip for scanning
  local tooltip = getglobal("GuildBanksterBindTooltip")
  if not tooltip then
    tooltip = CreateFrame("GameTooltip", "GuildBanksterBindTooltip", nil, "GameTooltipTemplate")
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
  end

  -- Set tooltip to the bag item
  tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
  tooltip:SetBagItem(bag, slot)

  -- Scan tooltip text for binding keywords
  for i = 1, tooltip:NumLines() do
    local line = getglobal("GuildBanksterBindTooltipTextLeft" .. i)
    if line then
      local text = line:GetText()
      if text then
        -- Check for various binding texts
        if strfind(text, "Soulbound") or
          strfind(text, "Binds when picked up") then
          tooltip:Hide()
          return true
        end
      end
    end
  end

  tooltip:Hide()
  return false
end

-- Function: findGuildBankFrame
-- Purpose: Locate Turtle WoW's guild bank frame object by searching all frames
-- Returns: frame object - TW_GUILDBANK frame, or nil if not found  
-- Used by: Frame initialization during addon load
-- Note: Critical for integration with Turtle WoW's guild bank system
function findGuildBankFrame()
  local f = EnumerateFrames()
  while f do
    if f.prefix and f.prefix == "TW_GUILDBANK" then
      return f
    end
    f = EnumerateFrames(f)
  end
end

local function ScanGuildBank(tab)
  local items = {}
  for i=1,MAX_SLOTS do
    items[i] = GuildBank.items[tab][i] and { itemID = GuildBank.items[tab][i].itemID, count = GuildBank.items[tab][i].count }
  end
  return items
end

--==============================================================================
-- WOW INTEGRATION: Frame Management and Event Handlers  
--==============================================================================
-- Purpose: Core WoW client integration, frame setup, and event processing
-- Dependencies: Core utilities (above), NPC data, constants
-- Used by: Template system, restock engine, and UI integration
-- Entry Points: Event handlers (BANKFRAME_OPENED, GOSSIP_SHOW, etc.)
--==============================================================================

-- Function: SpoofGossip
-- Purpose: Programmatically opens guild bank by manipulating WoW UI panels
-- Dependencies: findGuildBankFrame utility function
-- Called by: BANKFRAME_OPENED event handler
function SpoofGossip()
  UIPanelWindows.GossipFrame.pushable = 99
  local centerFrame = (GetCenterFrame())
  HideUIPanel(centerFrame)
  ShowUIPanel(centerFrame)
  GuildBank.gossipOpen = true
  GossipFrame:SetAlpha(0)
  GossipFrame:EnableMouse(nil)
  if not GuildBank.ready then
    GuildBank:GetBankInfo()
  else
    GuildBankFrameTab_OnClick(1, true)
    GuildBankFrameBottomTab_OnClick(1)
    GuildBankFrame:Show()
  end
end

-- Provide GuildBank globally so other addons don't have to search for it
GuildBank = findGuildBankFrame()
GuildBankster = CreateFrame("Frame")

function GuildBankster:Deposit(tab,gbank_slot,bag,inv_slot,count)
  GuildBank:Send(format("DepositItem:%d:%d:%d:%d:%d",bag,inv_slot,tab,gbank_slot,count))
end

function GuildBankster:Withdraw(tab,gbank_slot,bag,inv_slot,count)
  GuildBank:Send(format("WithdrawItem:%d:%d:%d:%d:%d",tab,gbank_slot,bag,inv_slot,count))
end

local orig_GuildBankFrame_OnShow = GuildBankFrame_OnShow
function GBS_GuildBankFrame_OnShow(a,b,c,d,e,f)
  orig_GuildBankFrame_OnShow(a,b,c,d,e,f)

  if InventoryCounterDB then
    local counts = {}
    local count = 0
    for i = 1, MAX_TABS do
      for _, item in GuildBank.items[i] do
        counts[item.itemID] = item.count + (counts[item.itemID] or 0)
      end
    end
    for itemID,count in counts do
      local name = GetItemInfo("item:"..itemID)
      if name then
        InventoryCounterDB[GuildBank.guildInfo.name] = InventoryCounterDB[GuildBank.guildInfo.name] or { gbank = { [name] = 0, } }
        InventoryCounterDB[GuildBank.guildInfo.name]["gbank"][name] = count
      end
    end
  end
end
GuildBankFrame_OnShow = GBS_GuildBankFrame_OnShow

function GuildBankster:BANKFRAME_OPENED()
  local banker = UnitExists("npc") and in_range_npc[UnitName("npc")]
  if not banker or banker.city ~= GetRealZoneText() then return end
  GuildBankster.bank_open = true

  SpoofGossip()
end

function GuildBankster:BANKFRAME_CLOSED()
  GuildBankster.bank_open = false
  GuildBankFrameCloseButton_OnClick()
end

function GuildBankster:GOSSIP_SHOW()
  if UnitName("target") ~= "Koma" then return end
  -- open bank if it exists, hold ctrl to skip
  if IsControlKeyDown() then return end
  for i=1,NUMGOSSIPBUTTONS do
    local tex = getglobal("GossipTitleButton".. i  .. "GossipIcon"):GetTexture()
    if tex == "Interface\\GossipFrame\\bankerGossipIcon" then
      SelectGossipOption(i)
      break
    end
  end
end


function GuildBankster:VARIABLES_LOADED()
  GuildBanksterDB = GuildBanksterDB or {}
  -- Guild-specific initialization happens in GetGuildSettings() when needed
  gb_print("GuildBankster addon loaded")
end

GuildBankster:RegisterEvent("BANKFRAME_OPENED")
GuildBankster:RegisterEvent("GOSSIP_SHOW")
GuildBankster:RegisterEvent("BANKFRAME_CLOSED")
GuildBankster:RegisterEvent("VARIABLES_LOADED")
GuildBankster:RegisterEvent("BAG_UPDATE")
GuildBankster:SetScript("OnEvent",function ()
  GuildBankster[event](this,arg1,arg2,arg3,arg4,arg6,arg7,arg8,arg9,arg10)
end)

--==============================================================================
-- DATABASE & SETTINGS: Persistent Storage and Guild Management
--==============================================================================
-- Purpose: Per-guild settings storage, initialization, and management
-- Dependencies: Core utilities (gb_print), constants (MAX_TABS)
-- Used by: Template system, restock engine
-- Data Structure: GuildBanksterDB[guildName] = {templates, templateActiveStates}
--==============================================================================
GuildBanksterDB = GuildBanksterDB or {}

-- Current guild settings (set when guild bank frame shows)

-- Function: InitializeGuildSettings  
-- Purpose: Initialize per-guild settings storage when guild bank opens
-- Dependencies: GuildBank frame data, database system
-- Called by: GuildBankster_OnGuildBankShow hook
-- Cross-reference: See Template System (below) - consumes these settings
-- Cross-reference: See Restock Engine (below) - uses templateActiveStates
local function InitializeGuildSettings()
  local guildName = "DEFAULT"
  if GuildBank and GuildBank.guildInfo and GuildBank.guildInfo.name then
    guildName = GuildBank.guildInfo.name
  end

  if not GuildBanksterDB[guildName] then
    GuildBanksterDB[guildName] = {
      templates = {},
      templateActiveStates = {}
    }
    -- Initialize default active states (all inactive by default)
    for i = 1, MAX_TABS do
      GuildBanksterDB[guildName].templateActiveStates[i] = false
    end
  end

  CurrentGuildSettings = GuildBanksterDB[guildName]
  gb_print("Loaded settings for guild: " .. guildName)
end

--==============================================================================
-- TEMPLATE SYSTEM: UI Creation and Template Management
--==============================================================================
-- Purpose: Complete template system including UI creation, interaction handling,
--          and integration with Turtle WoW's guild bank interface
-- Dependencies: Database settings, state management, core utilities
-- Used by: Restock engine (reads template definitions)
-- Components: UI creation, event handling, display updates, state management
-- Entry Point: GuildBankster_TemplateTab_OnClick() when Templates tab clicked
--==============================================================================


-- SECTION: UI Creation Functions
-- Cross-reference: See UI Hooks (below) - these functions called during frame setup

-- Function: CreateTemplateTab  
-- Purpose: Create the "Templates" tab button and "Restock" button in guild bank UI
-- Returns: templateTab frame - the created template tab button
-- Called by: Hook initialization when guild bank frame exists
-- Cross-reference: See Restock Engine (below) - Restock button triggers RestockBankStepwise
local function CreateTemplateTab()
  if not GuildBankFrame then return end

  -- Create the Template tab button using the same template as other bottom tabs
  local templateTab = CreateFrame("Button", "GuildBankFrameBottomTab4", GuildBankFrame, "TWGuildFrameBottomTabButtonTemplate")
  templateTab:SetPoint("LEFT", GuildBankFrameBottomTab3, "RIGHT", -10, 0)
  templateTab:SetID(4)
  templateTab:SetText("Templates")

  -- Click handler
  templateTab:SetScript("OnClick", function()
    GuildBankster_TemplateTab_OnClick()
  end)

  -- Create Restock button using the same tab template style
  local restockButton = CreateFrame("Button", "GuildBankFrameRestockButton", GuildBankFrame, "GuildBankFrameTabIconButtonTemplate")
  restockButton:SetPoint("BOTTOMLEFT", "GuildBankFrame", "BOTTOMRIGHT", -3, 35)
  restockButton:SetText("Restock")
  restockButton:SetWidth(39)
  restockButton:SetHeight(39)

  restockButton:SetNormalTexture("Interface\\Glues\\CharacterCreate\\UI-RotationRight-Big-Up")
  restockButton:SetPushedTexture("Interface\\Glues\\CharacterCreate\\UI-RotationRight-Big-Down")

  -- Tooltip for restock button
  restockButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Restock Guild Bank", 1, 1, 1)
    GameTooltip:AddLine("Automatically restocks the guild bank based on your defined templates.", 0.8, 0.8, 0.8, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to restock items from your inventory and personal bank.", 0.7, 0.7, 0.7, 1)
    GameTooltip:Show()
  end)

  restockButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- Click handler for restock button
  restockButton:SetScript("OnClick", function()
    -- Switch back to main guild bank view
    if TemplateMode then
      -- Click on tab 1 (main view) bottom tab
      GuildBankFrameBottomTab_OnClick(1)
      GuildBankFrameTab_OnClick(1)
    end
    -- Start restock process
    GuildBankster:RestockBankStepwise()
  end)
  restockButton:SetScript("OnMouseUp", function()
    -- nop
  end)
  restockButton:Show()

  return templateTab
end

-- Create Template slots frame
local function CreateTemplateFrame()
  if not GuildBankFrame then return end

  local frame = CreateFrame("Frame", "GuildBankFrameTemplateSlots", GuildBankFrame)
  frame:SetAllPoints(GuildBankFrameSlots)
  frame:Hide()

  -- Add background textures to match the main slots frame
  for col = 1, 7 do
    local texture = frame:CreateTexture("GuildBankFrameTemplateBagCol" .. col, "BACKGROUND")
    texture:SetTexture("Interface\\GuildBankFrame\\UI-GuildBankFrame-Slots")
    texture:SetWidth(128)
    texture:SetHeight(512)

    if col == 1 then
      texture:SetPoint("TOPLEFT", frame, "TOPLEFT", -7, -7)
    else
      local prevTexture = _G["GuildBankFrameTemplateBagCol" .. (col-1)]
      texture:SetPoint("TOPLEFT", prevTexture, "TOPRIGHT", -25, 0)
    end
  end

  -- Create template slot buttons using the same template as guild bank items
  for slot = 1, MAX_SLOTS do
    local btn = CreateFrame("Button", "GuildBankTemplateSlot"..slot, frame, "GuildBankFrameItemButtonTemplate")

    -- Use the same positioning logic as the original guild bank items
    local i = slot
    local row = math.floor((i - 1) / 14)
    local col = math.mod(i - 1, 14)
    local separators = 0
    local separator = 0

    -- Calculate separators for column groups (pairs of columns)
    -- Columns are grouped: 0-1, 2-3, 4-5, 6-7, 8-9, 10-11, 12-13
    local groupSeparatorWidth = 3  -- Space between column groups
    local numGroups = math.floor(col / 2)  -- How many complete groups before this column
    -- local xOffset = col * 39  -- Base spacing for columns (39 pixels per column)
    local xOffset = col * 50  -- Base spacing for columns (39 pixels per column)

    -- Add separator space for each group boundary we've passed
    if col > 0 then
      xOffset = xOffset + numGroups * groupSeparatorWidth
    end

    -- Position the button
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset, -10 - row * 44)
    btn:SetID(slot)

    -- Store slot info
    btn.slotID = slot

    -- Override ALL event handlers to prevent guild bank interference
    btn:SetScript("OnClick", function()
      GuildBankster_TemplateSlot_OnClick(this)
    end)

    btn:SetScript("OnMouseUp", function()
      -- Also handle mouse up for placing held items after drag
      if HeldTemplateItem and arg1 == "LeftButton" then
        local template = CurrentGuildSettings.templates[CurrentTemplateTab]
        if template then
          template[this.slotID] = HeldTemplateItem
          GuildBankster_UpdateTemplateDisplay()
        end
      end
    end)

    btn:SetScript("OnEnter", function()
      GuildBankster_TemplateSlot_OnEnter(this)
    end)

    btn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Override drag handlers to prevent guild bank item movement
    btn:SetScript("OnDragStart", function()
      -- Handle template item drag the same way guild bank does
      local template = CurrentGuildSettings.templates[CurrentTemplateTab]
      if template and template[this.slotID] then
        -- Set held template item
        HeldTemplateItem = template[this.slotID]

        -- Show item on cursor like guild bank does
        local icon = GetItemIcon(template[this.slotID].itemLink)
        if icon and GuildBankFrameCursorItemFrameTexture then
          GuildBankFrameCursorItemFrameTexture:SetTexture(icon)
          -- Show the cursor frame the same way guild bank does
          if GuildBank and GuildBank.cursorFrame then
            GuildBank.cursorFrame:Show()
          elseif GuildBankFrameCursorItemFrame then
            GuildBankFrameCursorItemFrame:Show()
          end
        end
      end
    end)

    btn:SetScript("OnReceiveDrag", function()
      -- Handle template drop instead of guild bank drop
      GuildBankster_TemplateSlot_OnClick(this)
    end)

    -- Register for drag events like guild bank slots do
    btn:RegisterForDrag("LeftButton")

    -- Make sure button is visible and has proper size
    btn:Show()
    btn:Enable()

    TemplateFrames[slot] = btn
  end

  return frame
end

-- Update template title with current tab and active/inactive status
local function UpdateTemplateTitle(tabId)
  if CurrentGuildSettings and GuildBankFrameTabTitle and GuildBankFrameTabTitle_SetText_Original then
    local isActive = CurrentGuildSettings.templateActiveStates[tabId] or false
    local statusText = isActive and "|cFF00FF00 (Active)|r" or "|cFFFF0000 (Inactive)|r"
    GuildBankFrameTabTitle_SetText_Original(GuildBankFrameTabTitle, "Template " .. tabId .. statusText)
  end
end

-- Handle Template tab click
function GuildBankster_TemplateTab_OnClick()
  TemplateMode = true

  -- Hook the tab title SetText to prevent updates during template mode
  if GuildBankFrameTabTitle and not GuildBankFrameTabTitle_SetText_Original then
    GuildBankFrameTabTitle_SetText_Original = GuildBankFrameTabTitle.SetText
    GuildBankFrameTabTitle.SetText = function(self, text)
      -- Only allow our template text to be set
      if not TemplateMode then
        GuildBankFrameTabTitle_SetText_Original(self, text)
      end
    end
  end

  -- Set initial template tab to current guild bank tab if not set
  if not CurrentTemplateTab then
    CurrentTemplateTab = (GuildBank and GuildBank.currentTab) or 1
  end

  -- Hide all other content frames (same as original bottom tab system)
  if GuildBankFrameSlots then GuildBankFrameSlots:Hide() end
  if GuildBankFrameLog then GuildBankFrameLog:Hide() end
  if GuildBankFrameMoneyLog then GuildBankFrameMoneyLog:Hide() end

  -- Show template frame
  if not GuildBankFrameTemplateSlots then
    CreateTemplateFrame()
  end
  if GuildBankFrameTemplateSlots then
    GuildBankFrameTemplateSlots:Show()
  end

  -- Update tab appearance for template mode
  GuildBankster_UpdateTabsForTemplateMode()

  -- Enable guild bank tabs (same as tab 1) and register for right-click
  if GuildBank and GuildBank.tabs then
    for i = 1, GuildBank.tabs.numTabs do
      local tab = _G["GuildBankFrameTab" .. i]
      if tab then
        tab:Enable()
        SetDesaturation(tab:GetNormalTexture(), 0)
        -- Tabs are already registered for right-click by the original Turtle code
      end
    end
  end

  -- Update display
  GuildBankster_UpdateTemplateDisplay()

  -- Update bottom tab states (disable others, enable template tab)
  if GuildBankFrameBottomTab_Disable then
    GuildBankFrameBottomTab_Disable(GuildBankFrameBottomTab1)
    GuildBankFrameBottomTab_Disable(GuildBankFrameBottomTab2)
    GuildBankFrameBottomTab_Disable(GuildBankFrameBottomTab3)
  end
  if GuildBankFrameBottomTab_Enable then
    GuildBankFrameBottomTab_Enable(GuildBankFrameBottomTab4)
  end

  -- Simulate a click on the current template tab to update title and display
  if _G["GuildBankFrameTab" .. CurrentTemplateTab] then
    _G["GuildBankFrameTab" .. CurrentTemplateTab]:Click()
  end
end

-- Update guild bank tab appearance and tooltips for template mode
function GuildBankster_UpdateTabsForTemplateMode()
  if not TemplateMode or not CurrentGuildSettings then return end

  -- Update each tab's appearance and tooltip
  for i = 1, MAX_TABS do
    local tab = _G["GuildBankFrameTab" .. i]
    if tab then
      local isActive = CurrentGuildSettings.templateActiveStates[i] or false

      -- Store original OnEnter script if not already stored
      if not tab.originalOnEnter then
        tab.originalOnEnter = tab:GetScript("OnEnter")
      end

      -- Override OnEnter to show custom tooltip in template mode
      tab:SetScript("OnEnter", function()
        -- Get tab ID from the button itself
        local tabId = this:GetID()
        -- Get current active state dynamically
        local currentlyActive = CurrentGuildSettings and CurrentGuildSettings.templateActiveStates[tabId] or false
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText((this.tooltip or "Template " .. tabId) .. " (Template " .. tabId .. ")", 1, 1, 1, 1)
        GameTooltip:AddLine("Right-click to toggle template " .. (currentlyActive and "inactive" or "active"), 0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
      end)

      -- Grey out inactive templates
      if not isActive then
        tab:GetNormalTexture():SetVertexColor(0.5, 0.5, 0.5, 1.0)
        tab:GetPushedTexture():SetVertexColor(0.5, 0.5, 0.5, 1.0)
      else
        tab:GetNormalTexture():SetVertexColor(1.0, 1.0, 1.0, 1.0)
        tab:GetPushedTexture():SetVertexColor(1.0, 1.0, 1.0, 1.0)
      end
    end
  end
end

-- Restore guild bank tab appearance and tooltips when leaving template mode
function GuildBankster_RestoreTabsFromTemplateMode()
  for i = 1, MAX_TABS do
    local tab = _G["GuildBankFrameTab" .. i]
    if tab and tab.originalOnEnter then
      -- Restore original OnEnter script
      tab:SetScript("OnEnter", tab.originalOnEnter)

      -- Restore original colors
      tab:GetNormalTexture():SetVertexColor(1.0, 1.0, 1.0, 1.0)
      tab:GetPushedTexture():SetVertexColor(1.0, 1.0, 1.0, 1.0)

      -- Clear stored originals
      tab.originalOnEnter = nil
    end
  end
end

-- Update template display
function GuildBankster_UpdateTemplateDisplay()
  -- Initialize templates if needed
  if not CurrentGuildSettings then
    gb_print("Guild settings not initialized")
    return
  end

  if not CurrentGuildSettings.templates[CurrentTemplateTab] then
    CurrentGuildSettings.templates[CurrentTemplateTab] = {}
  end

  local template = CurrentGuildSettings.templates[CurrentTemplateTab]
  local isActive = CurrentGuildSettings.templateActiveStates[CurrentTemplateTab] or false

  for slot = 1, MAX_SLOTS do
    local btn = TemplateFrames[slot]
    if btn then
      local data = template[slot]
      if data then
        -- Get the icon texture element from the button template
        local iconTexture = _G[btn:GetName() .. "IconTexture"] or _G[btn:GetName() .. "Icon"]
        if not iconTexture then
          -- If template doesn't have named icon, try getting the first texture child
          iconTexture = btn:GetNormalTexture()
        end

        local icon = GetItemIcon(data.itemLink)
        if iconTexture and icon then
          iconTexture:SetTexture(icon)
          -- Ensure proper sizing for item icons
          iconTexture:SetTexCoord(0, 1, 0, 1)
          -- Grey out icons if template is inactive
          if isActive then
            SetDesaturation(iconTexture, 0) -- Normal colors
          else
            SetDesaturation(iconTexture, 1) -- Greyed out
          end
        elseif iconTexture then
          iconTexture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
          iconTexture:SetTexCoord(0, 1, 0, 1)
          if isActive then
            SetDesaturation(iconTexture, 0)
          else
            SetDesaturation(iconTexture, 1)
          end
        end

        -- Set count using the template's count fontstring
        local countText = _G[btn:GetName() .. "Count"]
        if countText then
          -- Show count for all items (including 1 if specified)
          if data.count and data.count > 1 then
            countText:SetText(data.count)
            countText:Show()
            -- Grey out count text if inactive
            if isActive then
              countText:SetTextColor(1, 1, 1) -- White
            else
              countText:SetTextColor(0.5, 0.5, 0.5) -- Grey
            end
          else
            countText:SetText("")
            countText:Hide()
          end
        end
      else
        -- Clear the icon
        local iconTexture = _G[btn:GetName() .. "IconTexture"] or _G[btn:GetName() .. "Icon"]
        if not iconTexture then
          iconTexture = btn:GetNormalTexture()
        end
        if iconTexture then
          iconTexture:SetTexture(nil)
        end

        local countText = _G[btn:GetName() .. "Count"]
        if countText then
          countText:SetText("")
          countText:Hide()
        end
      end
    end
  end

end

-- Handle template slot click
function GuildBankster_TemplateSlot_OnClick(self)
  if not self then return end
  local slot = self.slotID
  local button = arg1  -- Get which mouse button was clicked

  -- Initialize template if needed
  if not CurrentGuildSettings then
    return
  end
  if not CurrentGuildSettings.templates[CurrentTemplateTab] then
    CurrentGuildSettings.templates[CurrentTemplateTab] = {}
  end

  local template = CurrentGuildSettings.templates[CurrentTemplateTab]

  if button == "RightButton" then
    -- Right click: Clear the held item/cursor
    if HeldTemplateItem then
      ClearTemplateCursor()
    elseif template[slot] then
      -- If no held item, clear the slot
      template[slot] = nil
      GuildBankster_UpdateTemplateDisplay()
    end
  else
    -- Left click: Handle item placement and pickup
    if CursorHasItem() then
      -- Drop item from cursor into template slot (don't clear cursor)
      -- Use Turtle WoW's cursor tracking system

      local itemLink, count, itemID
      if GuildBank and GuildBank.cursorItem and GuildBank.cursorItem.from == "bag" then
        local bag = GuildBank.cursorItem.tab
        local slot = GuildBank.cursorItem.slot

        -- Get item link and count from the tracked source location
        local containerItemLink = GetContainerItemLink(bag, slot)
        if containerItemLink then
          itemLink = containerItemLink
          local texture, itemCount = GetContainerItemInfo(bag, slot)
          count = itemCount and (itemCount > 0 and itemCount or 1) or 1
          itemID = getIDFromLink(itemLink)

          -- Check if item is bound and warn user
          if IsItemBound(bag, slot) then
            local itemName = GetItemInfo(itemID) or "Unknown Item"
            gb_print("|cFFFF6600Warning:|r " .. itemName .. " is soulbound and cannot be shared with guild members.")
            ClearTemplateCursor()
            return
          end
        end
      end

      if not itemLink then
        gb_print("Unable to get cursor item information")
        return
      end

      template[slot] = {
        itemLink = itemLink,
        count = (count > 0 and count or 1),
        itemID = tonumber(itemID)
      }
      -- Don't clear cursor - allow multiple drops
      GuildBankster_UpdateTemplateDisplay()
    elseif HeldTemplateItem then
      -- Place held template item in this slot
      template[slot] = HeldTemplateItem
      -- Don't clear HeldTemplateItem - allow multiple placements
      GuildBankster_UpdateTemplateDisplay()
    elseif template[slot] then
      -- Pick up item from template slot
      HeldTemplateItem = template[slot]

      -- Show item on cursor like guild bank does
      local icon = GetItemIcon(template[slot].itemLink)
      if icon and GuildBankFrameCursorItemFrameTexture then
        GuildBankFrameCursorItemFrameTexture:SetTexture(icon)
        if GuildBank and GuildBank.cursorFrame then
          GuildBank.cursorFrame:Show()
        elseif GuildBankFrameCursorItemFrame then
          GuildBankFrameCursorItemFrame:Show()
        end
      end

      -- Don't remove from original slot - just copy it
    end
  end
end

-- Handle template slot hover
function GuildBankster_TemplateSlot_OnEnter(self)
  if not self then return end
  local slot = self.slotID

  local template = CurrentGuildSettings.templates[CurrentTemplateTab]
  if template and template[slot] then
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- Extract the item string without the full link format
    if template[slot].itemLink then
      local _, _, itemString = string.find(template[slot].itemLink, "|H(item:%d+:%d+:%d+:%d+)|h")
      if itemString then
        GameTooltip:SetHyperlink(itemString)
      end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Template Slot " .. slot, 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Left Click: Pick up item", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right Click on an item: Clear slot", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right Click with an item: Clear cursor", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  else
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Empty Template Slot " .. slot, 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Drop item to set template", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end
end

--==============================================================================
-- UI HOOKS & INTEGRATION: Guild Bank Frame Integration
--==============================================================================  
-- Purpose: Hooks into Turtle WoW's guild bank system to integrate template functionality
-- Dependencies: Template system (above), database settings, state management
-- Used by: Template system relies on these hooks to function properly
-- Integration Points: Frame show/hide, tab clicks, bottom tab system
--==============================================================================

-- Function: GuildBankster_OnGuildBankShow
-- Purpose: Initialize guild settings and refresh display when guild bank opens
-- Called by: Hooked GuildBankFrame_OnShow
local function GuildBankster_OnGuildBankShow(a,b,c,d,e,f)
  -- Initialize guild-specific settings
  InitializeGuildSettings()

  -- Template tab is now created at top level, no need to create here

  if GuildBank.currentTab ~= nil then
    for _, item in GuildBank.items[GuildBank.currentTab] do
      GuildBank:UpdateSlot(item.tab, item.slot, item, true)
    end
  end

  -- Call original if exists
  if GuildBankFrame_OnShow_Original then
    GuildBankFrame_OnShow_Original(a,b,c,d,e,f)
  end
end

-- Hook into guild bank frame hide
local function GuildBankster_OnGuildBankHide()

  -- Reset restock state
  if GuildBankster then
    GuildBankster:ResetRestock()
  end

  -- Close all bags
  CloseAllBags()

  -- Close bank frame if open
  if BankFrame and BankFrame:IsVisible() then
    CloseBankFrame()
  end

  -- Clear any held template items
  if HeldTemplateItem then
    HeldTemplateItem = nil
  end

  -- Hide guild bank cursor frame if showing
  if GuildBankFrameCursorItemFrame then
    GuildBankFrameCursorItemFrame:Hide()
  end

  -- Call original if exists
  if GuildBankFrame_OnHide_Original then
    GuildBankFrame_OnHide_Original()
  end
end

-- Hook the bottom tab system to handle template tab
local function GuildBankster_BottomTab_OnClick(id)
  if id == 4 then
    GuildBankster_TemplateTab_OnClick()
  else
    -- Reset template mode when other tabs are clicked
    TemplateMode = false
    if GuildBankFrameTemplateSlots then
      GuildBankFrameTemplateSlots:Hide()
    end
    -- Restore tab appearance when leaving template mode
    GuildBankster_RestoreTabsFromTemplateMode()

    -- Restore original tab title SetText function
    if GuildBankFrameTabTitle and GuildBankFrameTabTitle_SetText_Original then
      GuildBankFrameTabTitle.SetText = GuildBankFrameTabTitle_SetText_Original
      GuildBankFrameTabTitle_SetText_Original = nil
    end
    -- Call original function with proper context
    if GuildBankFrameBottomTab_OnClick_Original then
      local result = GuildBankFrameBottomTab_OnClick_Original(id)
      -- Make sure template tab is properly disabled when other tabs are active
      if GuildBankFrameBottomTab4 and GuildBankFrameBottomTab_Disable then
        GuildBankFrameBottomTab_Disable(GuildBankFrameBottomTab4)
      end
      return result
    end
  end
end

-- Hook the tab buttons to work with template mode
local function GuildBankster_Tab_OnClick(id)
  -- If not in template mode, don't handle any template functionality at all
  if not TemplateMode or not GuildBankFrameTemplateSlots or not GuildBankFrameTemplateSlots:IsVisible() then
    -- Call original function only
    if GuildBankFrameTab_OnClick_Original then
      GuildBankFrameTab_OnClick_Original(id)
    end
    return
  end

  -- We're in template mode, handle template functionality
  if arg1 == "RightButton" then
    -- Toggle active state for this template
    CurrentGuildSettings.templateActiveStates[id] = not CurrentGuildSettings.templateActiveStates[id]
    local coloredState = CurrentGuildSettings.templateActiveStates[id] and "|cFF00FF00active|r" or "|cFFFF0000inactive|r"
    local tabName = "Template " .. id
    if GuildBank and GuildBank.tabs and GuildBank.tabs.info and GuildBank.tabs.info[id] and GuildBank.tabs.info[id].name then
      tabName = GuildBank.tabs.info[id].name
    end
    gb_print("(" .. tabName .. ") template " .. coloredState)

    -- Update tab title if this is the current template
    if id == CurrentTemplateTab then
      UpdateTemplateTitle(id)
    end

    -- Update tab appearance and tooltip
    GuildBankster_UpdateTabsForTemplateMode()
    GuildBankster_UpdateTemplateDisplay()
    return
  end

  -- Left-click: switch templates
  -- Uncheck all tabs first (like the original does)
  for i = 1, MAX_TABS do
    local tab = _G["GuildBankFrameTab"..i]
    if tab then
      tab:SetChecked(false)
    end
  end

  -- Check the clicked tab
  local clickedTab = _G["GuildBankFrameTab"..id]
  if clickedTab then
    clickedTab:SetChecked(true)
  end

  CurrentTemplateTab = id

  -- Update tab title
  UpdateTemplateTitle(id)

  GuildBankster_UpdateTemplateDisplay()
end

-- Set up hooks immediately since Turtle guild bank loads before us
-- Store original functions before hooking
if GuildBankFrame then
  -- Create the Template tab immediately when addon loads
  CreateTemplateTab()

  GuildBankFrame_OnShow_Original = GuildBankFrame_OnShow
  GuildBankFrame_OnShow = GuildBankster_OnGuildBankShow

  GuildBankFrame_OnHide_Original = GuildBankFrame_OnHide
  GuildBankFrame_OnHide = GuildBankster_OnGuildBankHide
end

if GuildBankFrameBottomTab_OnClick then
  GuildBankFrameBottomTab_OnClick_Original = GuildBankFrameBottomTab_OnClick
  GuildBankFrameBottomTab_OnClick = GuildBankster_BottomTab_OnClick
end

if GuildBankFrameTab_OnClick then
  GuildBankFrameTab_OnClick_Original = GuildBankFrameTab_OnClick
  GuildBankFrameTab_OnClick = GuildBankster_Tab_OnClick
end

--==============================================================================
-- CONTINUATION SYSTEM: Event-Driven Processing Framework
--==============================================================================
-- Purpose: Asynchronous operation management with timeout handling and verification
-- Dependencies: State management, core utilities, constants (RESTOCK_TIMEOUT)  
-- Used by: Restock engine for managing complex multi-step operations
-- Components: Timeout detection, operation verification, queue management
-- Entry Point: BAG_UPDATE event handler triggers continuation processing
--==============================================================================

-- OnUpdate only for timeout checking
continuation_frame:SetScript("OnUpdate", function()
  continuation_timeout_check = continuation_timeout_check + arg1

  -- Check timeout every 0.1 seconds
  if continuation_timeout_check >= 0.1 then
    continuation_timeout_check = 0

    -- Check for continuation timeout
    if continuation_active and last_action_time > 0 then
      if GetTime() - last_action_time > RESTOCK_TIMEOUT + 1 then
        -- Operation timed out, reset and continue to next job
        continuation_active = false
        last_action_time = 0
        current_operation = {}
        if GuildBankster and GuildBankster.RestockBankster_NextJob then
          GuildBankster:RestockBankster_NextJob()
        end
      end
    end
  end
end)

-- Process continuation queue
function GuildBankster:ProcessContinuation()
  if continuation_active then return end

  local next_action = table.remove(continuation_queue, 1)
  if next_action then
    continuation_active = true
    next_action()
  end
end

-- Add action to continuation queue
function GuildBankster:QueueContinuation(action)
  table.insert(continuation_queue, action)
  -- Try to start immediately if nothing is running
  if not continuation_active then
    self:ProcessContinuation()
  end
end


-- Verify that expected inventory changes occurred
local function VerifyInventoryChange(operation, pre_state)
  if operation.type == "deposit" then
    -- Check if source slot lost the expected amount
    local currentLink = GetContainerItemLink(operation.source_bag, operation.source_slot)
    local currentCount = 0
    if currentLink then
      local _, count = GetContainerItemInfo(operation.source_bag, operation.source_slot)
      currentCount = count and (count > 0 and count or 1) or 0
    end

    local expectedChange = operation.amount
    local actualChange = pre_state.source_count - currentCount

    -- gb_print("Verify deposit: expected -" .. expectedChange .. ", actual -" .. actualChange)
    return actualChange >= expectedChange

  elseif operation.type == "bank_to_bag_split" then
    -- Check if destination bag received items
    local currentLink = GetContainerItemLink(operation.dest_bag, operation.dest_slot)
    local currentCount = 0
    if currentLink then
      local _, count = GetContainerItemInfo(operation.dest_bag, operation.dest_slot)
      currentCount = count and (count > 0 and count or 1) or 0
    end

    local expectedGain = operation.amount
    local actualGain = currentCount - pre_state.dest_count

    return actualGain >= expectedGain

  elseif operation.type == "stack_combination" then
    -- Check if source slot is empty and destination has more items
    local sourceLink = GetContainerItemLink(operation.source_bag, operation.source_slot)
    local sourceCount = 0
    if sourceLink then
      local _, count = GetContainerItemInfo(operation.source_bag, operation.source_slot)
      sourceCount = count and (count > 0 and count or 1) or 0
    end

    local destLink = GetContainerItemLink(operation.dest_bag, operation.dest_slot)
    local destCount = 0
    if destLink then
      local _, count = GetContainerItemInfo(operation.dest_bag, operation.dest_slot)
      destCount = count and (count > 0 and count or 1) or 0
    end

    -- Success means source is empty (or reduced) and dest has gained
    local sourceReduction = pre_state.source_count - sourceCount
    local destIncrease = destCount - pre_state.dest_count

    -- gb_print("Verify stack combination: source lost " .. sourceReduction .. ", dest gained " .. destIncrease)
    return sourceReduction > 0 and destIncrease > 0
  end

  return true -- Default to success for unknown operations
end

function GuildBankster:ResetRestock()
  continuation_active = false
  last_action_time = 0
  current_operation = {}
  for i = 1, table.getn(restock_jobs) do restock_jobs[i] = nil end
  for i = 1, table.getn(continuation_queue) do continuation_queue[i] = nil end
end

function GuildBankster:BAG_UPDATE(which)
  -- Continuation-based processing - check if operation completed successfully
  if continuation_active and current_operation.type and pre_operation_state then
    local success = VerifyInventoryChange(current_operation, pre_operation_state)

    if success then
      -- gb_print("Operation verified successfully")

      -- Clear operation state
      current_operation = {}
      pre_operation_state = {}
      operation_retry_count = 0
      continuation_active = false
      last_action_time = 0

      -- Process next restock job or show completion
      self:RestockBankster_NextJob()
    else
      -- Operation not complete yet, but check for timeout
      if last_action_time > 0 and GetTime() - last_action_time > RESTOCK_TIMEOUT then
        operation_retry_count = operation_retry_count + 1

        if operation_retry_count < MAX_RETRIES then
          -- Reset timeout and try again (the operation might still complete)
          last_action_time = GetTime()
        else

          -- Clear operation state and continue
          current_operation = {}
          pre_operation_state = {}
          operation_retry_count = 0
          continuation_active = false
          last_action_time = 0

          -- Process next job or show completion
          self:RestockBankster_NextJob()
        end
      end
    end
  end
end

--==============================================================================
-- INVENTORY MANAGEMENT: Bag Scanning and Item Location Services
--==============================================================================
-- Purpose: Comprehensive inventory management including bag scanning, bank interaction,
--          and intelligent item location and consolidation planning
-- Dependencies: Core utilities, constants (bank_bag_ids, ordered_bags)
-- Used by: Restock engine for item discovery and movement planning  
-- Components: Bag scanning, state capture, item finding, consolidation planning
-- See also: Restock engine (below) - primary consumer of these services
--==============================================================================

-- Rescan bags for current inventory state
local function RescanBags()
  local inventory = {}
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink then
        local itemID = tonumber(getIDFromLink(itemLink))
        local texture, itemCount = GetContainerItemInfo(bag, slot)
        itemCount = itemCount and (itemCount > 0 and itemCount or 1) or 0
        if itemID and itemCount then
          if not inventory[itemID] then
            inventory[itemID] = {}
          end
          table.insert(inventory[itemID], {
            bag = bag,
            slot = slot,
            count = itemCount,
            link = itemLink
          })
        end
      end
    end
  end
  return inventory
end

-- Capture inventory state for verification
local function CaptureInventoryState(operation)
  local state = {}
  if operation.type == "deposit" then
    -- Check source bag slot
    local itemLink = GetContainerItemLink(operation.source_bag, operation.source_slot)
    if itemLink then
      local _, itemCount = GetContainerItemInfo(operation.source_bag, operation.source_slot)
      state.source_count = itemCount and (itemCount > 0 and itemCount or 1) or 0
    else
      state.source_count = 0
    end
  elseif operation.type == "bank_to_bag_split" then
    -- Check both source bank slot and destination bag slot
    local bankLink = GetContainerItemLink(operation.source_bag, operation.source_slot)
    if bankLink then
      local _, bankCount = GetContainerItemInfo(operation.source_bag, operation.source_slot)
      state.source_count = bankCount and (bankCount > 0 and bankCount or 1) or 0
    else
      state.source_count = 0
    end

    local bagLink = GetContainerItemLink(operation.dest_bag, operation.dest_slot)
    if bagLink then
      local _, bagCount = GetContainerItemInfo(operation.dest_bag, operation.dest_slot)
      state.dest_count = bagCount and (bagCount > 0 and bagCount or 1) or 0
    else
      state.dest_count = 0
    end
  elseif operation.type == "stack_combination" then
    -- Check both source and destination slots
    local sourceLink = GetContainerItemLink(operation.source_bag, operation.source_slot)
    if sourceLink then
      local _, sourceCount = GetContainerItemInfo(operation.source_bag, operation.source_slot)
      state.source_count = sourceCount and (sourceCount > 0 and sourceCount or 1) or 0
    else
      state.source_count = 0
    end

    local destLink = GetContainerItemLink(operation.dest_bag, operation.dest_slot)
    if destLink then
      local _, destCount = GetContainerItemInfo(operation.dest_bag, operation.dest_slot)
      state.dest_count = destCount and (destCount > 0 and destCount or 1) or 0
    else
      state.dest_count = 0
    end
  end
  return state
end

local function FindInBag(itemID, amount)
  local inventory = RescanBags()
  if inventory[itemID] then
    -- Find the largest stack first
    local best_stack = nil
    for i, stack in ipairs(inventory[itemID]) do
      if not best_stack or stack.count > best_stack.count then
        best_stack = stack
      end
    end

    if best_stack then
      local take_amount = math.min(amount, best_stack.count)
      return best_stack.bag, best_stack.slot, take_amount
    end
  end
  return nil, nil, 0
end

-- Calculate total available items in bags and bank
local function CalculateAvailableItems(itemID)
  local bag_total = 0
  local bank_total = 0
  local bank_stacks = {}

  -- Check bags
  local inventory = RescanBags()
  if inventory[itemID] then
    for i, stack in ipairs(inventory[itemID]) do
      bag_total = bag_total + stack.count
    end
  end

  -- Check bank
  for i = 1, table.getn(bank_bag_ids) do
    local bag = bank_bag_ids[i]
    if bag then
      for slot = 1, GetContainerNumSlots(bag) do
        local itemLink = GetContainerItemLink(bag, slot)
        if itemLink and tonumber(getIDFromLink(itemLink)) == itemID then
          local _, count = GetContainerItemInfo(bag, slot)
          count = count and (count > 0 and count or 1) or 0
          bank_total = bank_total + count
          table.insert(bank_stacks, {bag = bag, slot = slot, count = count})
        end
      end
    end
  end

  -- Sort bank stacks by count (ascending - prefer taking from partial stacks first)
  table.sort(bank_stacks, function(a, b) return a.count < b.count end)

  return bag_total, bank_total, bank_stacks
end

-- Plan the most efficient way to fill a guild bank slot
local function PlanEfficientFill(itemID, needed_amount)
  local bag_total, bank_total, bank_stacks = CalculateAvailableItems(itemID)
  local total_available = bag_total + bank_total

  if total_available < needed_amount then
    return nil -- Not enough items
  end

  -- If we have enough in bags already, just deposit directly
  if bag_total >= needed_amount then
    return {type = "direct_deposit", amount = needed_amount}
  end

  -- We need to consolidate from bank + bags
  local need_from_bank = needed_amount - bag_total
  local consolidation_plan = {}
  local remaining_needed = need_from_bank

  -- Take from partial bank stacks first, then full stacks
  for i, stack in ipairs(bank_stacks) do
    if remaining_needed <= 0 then break end

    local take_amount = math.min(remaining_needed, stack.count)
    table.insert(consolidation_plan, {
      type = "withdraw_to_consolidate",
      bag = stack.bag,
      slot = stack.slot,
      amount = take_amount
    })
    remaining_needed = remaining_needed - take_amount
  end

  return {
    type = "consolidate_then_deposit",
    needed = needed_amount,
    bag_has = bag_total,
    bank_withdrawals = consolidation_plan
  }
end

local function FindInBank(itemID, amount)
  for i = 1, table.getn(bank_bag_ids) do
    local bag = bank_bag_ids[i]
    for slot = 1, GetContainerNumSlots(bag) do
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink and tonumber(getIDFromLink(itemLink)) == itemID then
        local _, count = GetContainerItemInfo(bag, slot)
        count = count and (count > 0 and count or 1) or 0
        if count > 0 then
          return bag, slot, math.min(count, amount)
        end
      end
    end
  end
  return nil, nil, 0
end

local function FindStackInBank(itemID, needed)
  local best_bag, best_slot, best_count
  for i = 1, table.getn(bank_bag_ids) do
    local bag = bank_bag_ids[i]
    for slot = 1, GetContainerNumSlots(bag) do
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink and tonumber(getIDFromLink(itemLink)) == itemID then
        local _, count = GetContainerItemInfo(bag, slot)
        count = count and (count > 0 and count or 1) or 0
        if count == needed then
          return bag, slot, count -- perfect match!
        elseif count > needed then
          -- Split off exactly what we need
          return bag, slot, needed
        elseif not best_count or count > best_count then
          best_bag, best_slot, best_count = bag, slot, count -- track largest partial
        end
      end
    end
  end
  if best_bag then
    return best_bag, best_slot, best_count
  end
  return nil, nil, 0
end

local function FindEmptyBagSlot()
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      if not GetContainerItemLink(bag, slot) then
        return bag, slot
      end
    end
  end
  return nil, nil
end

--==============================================================================
-- RESTOCK ENGINE: Automated Template-Based Guild Bank Restocking
--==============================================================================
-- Purpose: Core restocking functionality that automatically fills guild bank slots
--          based on active templates using items from inventory and personal bank
-- Dependencies: All above systems - templates, inventory management, continuation system
-- Components: Job planning, execution engine, consolidation logic, error handling
-- Entry Point: RestockBankStepwise() - called by Restock button click
-- Architecture: Two-phase system - job planning then stepwise execution
--==============================================================================

-- PHASE 1: Job Planning and Queueing
-- Function: RestockBankStepwise  
-- Purpose: Main entry point - analyzes templates vs current state and builds job queue
-- Called by: Restock button click handler in template system
function GuildBankster:RestockBankStepwise()
  print("Beginning Guildbank restock...")
  -- Clear previous jobs by nil'ing all values
  for i = 1, table.getn(restock_jobs) do restock_jobs[i] = nil end
  last_action_time = 0  -- Reset timeout tracking

  local job_i = 1
  for tab = 1, MAX_TABS do
    -- Check if template is active
    local isActive = CurrentGuildSettings.templateActiveStates[tab]
    if isActive then
      local desired_layout = CurrentGuildSettings.templates[tab]
      local current = ScanGuildBank(tab)
      for slot = 1, MAX_SLOTS do
        local want = desired_layout[slot]
        if want then
          local want_count = want.count
          local itemID = want.itemID
          local have = current[slot]
          if have and have.itemID == itemID then
            if have.count < want_count then
              local needed = want_count - have.count
              local fill_plan = PlanEfficientFill(itemID, needed)

              if fill_plan and fill_plan.type == "consolidate_then_deposit" then
                -- Add consolidation job
                restock_jobs[job_i] = {
                  tab=tab, slot=slot, itemID=itemID,
                  type="consolidation",
                  plan=fill_plan
                }
                job_i = job_i + 1
              else
                -- Direct deposit or not enough items
                restock_jobs[job_i] = { tab=tab, slot=slot, itemID=itemID, need=needed }
                job_i = job_i + 1
              end
            end
          elseif have and have.count > 0 then
            -- Remove wrong item first
            restock_jobs[job_i] = { tab=tab, slot=slot, itemID=have.itemID, need=-have.count, isRemoval=true }
            job_i = job_i + 1
            -- Queue efficient fill after removal
            local fill_plan = PlanEfficientFill(itemID, want_count)
            if fill_plan and fill_plan.type == "consolidate_then_deposit" then
              restock_jobs[job_i] = {
                tab=tab, slot=slot, itemID=itemID,
                type="consolidation",
                plan=fill_plan
              }
              job_i = job_i + 1
            else
              restock_jobs[job_i] = { tab=tab, slot=slot, itemID=itemID, need=want_count }
              job_i = job_i + 1
            end
          else
            -- Empty slot, need full amount
            local fill_plan = PlanEfficientFill(itemID, want_count)
            if fill_plan and fill_plan.type == "consolidate_then_deposit" then
              restock_jobs[job_i] = {
                tab=tab, slot=slot, itemID=itemID,
                type="consolidation",
                plan=fill_plan
              }
              job_i = job_i + 1
            else
              restock_jobs[job_i] = { tab=tab, slot=slot, itemID=itemID, need=want_count }
              job_i = job_i + 1
            end
          end
        end
      end
    end
  end

  GuildBankster:RestockBankster_NextJob()
end

-- PHASE 2: Job Execution Engine  
-- Function: RestockBankster_NextJob
-- Purpose: Processes job queue one item at a time using continuation system
-- Handles: Consolidation jobs, direct deposits, withdrawals, stack combinations
-- Called by: Continuation system after each operation completes
function GuildBankster:RestockBankster_NextJob()
  local job = restock_jobs[1]
  if not job then
    if next(missing_totals) then
      local lines = { "Insufficient inventory to stock:" }
      for itemID, count in pairs(missing_totals) do
        table.insert(lines, string.format("%d : %s", count, GetItemInfo("item:"..itemID) or ("item:"..itemID)))
      end
      for i = 1, table.getn(lines) do
        gb_print(lines[i])
      end
    else
      gb_print("Guildbank restock finished.")
    end
    -- clear for next run
    for k in pairs(missing_totals) do missing_totals[k] = nil end
    continuation_active = false  -- Clear continuation state when done
    return
  end


  -- Handle consolidation jobs
  if job.type == "consolidation" then
    local plan = job.plan

    if not job.consolidation_phase then
      -- Rescan bank to get fresh data for withdrawals
      local bag_total, bank_total, bank_stacks = CalculateAvailableItems(job.itemID)
      local need_from_bank = plan.needed - bag_total

      -- Rebuild withdrawal plan with fresh bank data
      plan.bank_withdrawals = {}
      local remaining_needed = need_from_bank
      for i, stack in ipairs(bank_stacks) do
        if remaining_needed <= 0 then break end
        local take_amount = math.min(remaining_needed, stack.count)
        table.insert(plan.bank_withdrawals, {
          bag = stack.bag,
          slot = stack.slot,
          amount = take_amount
        })
        remaining_needed = remaining_needed - take_amount
      end


      -- If no valid withdrawals found, skip directly to depositing what's in bags
      if table.getn(plan.bank_withdrawals) == 0 then
        job.consolidation_phase = "depositing"
      else
        job.consolidation_phase = "withdrawing"
        job.withdrawal_index = 1
      end
    end

    if job.consolidation_phase == "withdrawing" then
      -- Check if we have any withdrawals to process
      if table.getn(plan.bank_withdrawals) == 0 then
        job.consolidation_phase = "depositing"
        self:RestockBankster_NextJob()
        return
      end

      local withdrawal = plan.bank_withdrawals[job.withdrawal_index]
      if withdrawal then
        -- Track operation for debugging and verification
        current_operation = {
          type = "withdraw",
          itemID = job.itemID,
          amount = withdrawal.amount,
          source_bag = withdrawal.bag,
          source_slot = withdrawal.slot,
          from = "bank bag " .. withdrawal.bag .. " slot " .. withdrawal.slot,
          to = "inventory"
        }

        -- Capture pre-operation state for verification
        pre_operation_state = CaptureInventoryState(current_operation)
        operation_retry_count = 0


        last_action_time = GetTime()
        continuation_active = true

        -- Find empty bag slot for the withdrawn items
        local emptyBag, emptySlot = FindEmptyBagSlot()
        if emptyBag then
          -- Validate source slot has the expected item
          local sourceLink = GetContainerItemLink(withdrawal.bag, withdrawal.slot)
          local sourceItemID = sourceLink and tonumber(getIDFromLink(sourceLink))
          local _, sourceCount = GetContainerItemInfo(withdrawal.bag, withdrawal.slot)
          sourceCount = sourceCount and (sourceCount > 0 and sourceCount or 1) or 0

          -- Check if source slot is invalid
          if not sourceItemID or sourceItemID ~= job.itemID or not sourceCount or sourceCount < withdrawal.amount then
            -- Skip this withdrawal and try the next one
            job.withdrawal_index = job.withdrawal_index + 1
            if job.withdrawal_index > table.getn(plan.bank_withdrawals) then
              job.consolidation_phase = "depositing"
            end
            continuation_active = false
            self:RestockBankster_NextJob()
            return
          end

          -- Validate destination is truly empty
          local destLink = GetContainerItemLink(emptyBag, emptySlot)

          current_operation.dest_bag = emptyBag
          current_operation.dest_slot = emptySlot

          -- Update operation tracking for bank-to-bag move
          current_operation.type = "bank_to_bag_split"
          pre_operation_state = CaptureInventoryState(current_operation)

          SplitContainerItem(withdrawal.bag, withdrawal.slot, withdrawal.amount)
          PickupContainerItem(emptyBag, emptySlot)
        else
          -- Skip this withdrawal and try the next one
          job.withdrawal_index = job.withdrawal_index + 1
          if job.withdrawal_index > table.getn(plan.bank_withdrawals) then
            job.consolidation_phase = "depositing"
          end
          continuation_active = false
          self:RestockBankster_NextJob()
          return
        end

        job.withdrawal_index = job.withdrawal_index + 1
        if job.withdrawal_index > table.getn(plan.bank_withdrawals) then
          job.consolidation_phase = "stacking"
        end
        return
      end
    end

    if job.consolidation_phase == "stacking" then
      -- Find all stacks of this item in bags and combine them
      local inventory = RescanBags()
      if inventory[job.itemID] and table.getn(inventory[job.itemID]) > 1 then
        -- Sort stacks by count (largest first to be the target)
        table.sort(inventory[job.itemID], function(a, b) return a.count > b.count end)

        local target_stack = inventory[job.itemID][1]  -- Largest stack
        local source_stack = inventory[job.itemID][2]  -- Next stack to combine


        if target_stack and source_stack then
          -- Track operation for debugging and verification
          current_operation = {
            type = "stack_combination",
            itemID = job.itemID,
            amount = source_stack.count,
            source_bag = source_stack.bag,
            source_slot = source_stack.slot,
            dest_bag = target_stack.bag,
            dest_slot = target_stack.slot,
            from = "bag " .. source_stack.bag .. " slot " .. source_stack.slot,
            to = "bag " .. target_stack.bag .. " slot " .. target_stack.slot
          }

          -- Capture pre-operation state for verification
          pre_operation_state = CaptureInventoryState(current_operation)
          operation_retry_count = 0


          last_action_time = GetTime()
          continuation_active = true

          -- Pick up source stack and put it on target stack
          PickupContainerItem(source_stack.bag, source_stack.slot)
          PickupContainerItem(target_stack.bag, target_stack.slot)
          return
        end
      end

      -- No more stacking needed, move to depositing
      job.consolidation_phase = "depositing"
      -- Fall through to depositing phase
    end

    if job.consolidation_phase == "depositing" then
      -- Before depositing, ensure all items are consolidated into the largest stack possible
      local inventory = RescanBags()
      local stacks = inventory[job.itemID]
      if stacks and table.getn(stacks) > 1 then
        job.consolidation_phase = "stacking"
        self:RestockBankster_NextJob()
        return
      end

      -- All items should now be in one stack - find the largest available amount
      local inventory = RescanBags()
      local stacks = inventory[job.itemID]
      local bag, slot, to_deposit = nil, nil, 0

      if stacks and table.getn(stacks) > 0 then
        -- Sort to get the largest stack first
        table.sort(stacks, function(a, b) return a.count > b.count end)
        local largest_stack = stacks[1]
        bag, slot, to_deposit = largest_stack.bag, largest_stack.slot, largest_stack.count
      end

      if bag and to_deposit > 0 then
        -- item found for consolidation job - switch to the correct tab now that we have an item to place
        if job.tab and GuildBank and GuildBank.currentTab ~= job.tab then
          GuildBankFrameTab_OnClick(job.tab)
        end

        -- Deposit the full amount available (all items are now consolidated)
        local actual_amount = to_deposit
        -- Track operation for debugging and verification
        current_operation = {
          type = "deposit",
          itemID = job.itemID,
          amount = actual_amount,
          source_bag = bag,
          source_slot = slot,
          from = "bag " .. bag .. " slot " .. slot,
          to = "guild bank tab " .. job.tab .. " slot " .. job.slot
        }

        -- Capture pre-operation state for verification
        pre_operation_state = CaptureInventoryState(current_operation)
        operation_retry_count = 0



        last_action_time = GetTime()
        continuation_active = true
        self:Deposit(job.tab, job.slot, bag, slot, actual_amount)

        -- Consolidation job complete after depositing all available items
        -- Remove this job when complete
        for i = 1, table.getn(restock_jobs)-1 do
          restock_jobs[i] = restock_jobs[i+1]
        end
        restock_jobs[table.getn(restock_jobs)] = nil

        -- After successful completion, continue to next job if available
        if next(restock_jobs) then
          -- Don't set continuation_active to false here - let BAG_UPDATE handle it
        else
          gb_print("All restock jobs complete!")
          continuation_active = false
        end
        return
      else
        -- Remove failed job
        for i = 1, table.getn(restock_jobs)-1 do
          restock_jobs[i] = restock_jobs[i+1]
        end
        restock_jobs[table.getn(restock_jobs)] = nil

        -- Continue to next job if available
        if next(restock_jobs) then
          continuation_active = false
          self:RestockBankster_NextJob()
        else
          gb_print("All restock jobs complete!")
          continuation_active = false
        end
        return
      end
    end

    return
  end

  -- Only log non-consolidation jobs
  if job.type ~= "consolidation" then
    local itemName = GetItemInfo("item:"..job.itemID) or ("item:"..job.itemID)
  end

  if job.need and job.need > 0 then
    -- First check if we have multiple stacks that should be consolidated
    local inventory = RescanBags()
    local stacks = inventory[job.itemID]

    -- If we're in the middle of stacking, continue
    if job.stacking_for_deposit then
      if stacks and table.getn(stacks) > 1 then
        -- Get item info including max stack size
        local _, _, _, _, _, _, maxStack = GetItemInfo(job.itemID)
        if not maxStack then maxStack = 1 end

        -- Sort stacks by count (smallest first for consolidation)
        table.sort(stacks, function(a, b)
          if not a then return false end
          if not b then return true end
          return a.count < b.count
        end)

        -- Find a pair of stacks that can be combined
        local target_stack, source_stack = nil, nil
        for i = 1, table.getn(stacks) do
          for j = i + 1, table.getn(stacks) do
            if stacks[i].count + stacks[j].count <= maxStack then
              -- These two can be combined
              source_stack = stacks[i]
              target_stack = stacks[j]
              break
            end
          end
          if source_stack then break end
        end

        if target_stack and source_stack then
          -- Track operation for debugging and verification
          current_operation = {
            type = "stack_combination",
            itemID = job.itemID,
            amount = source_stack.count,
            source_bag = source_stack.bag,
            source_slot = source_stack.slot,
            dest_bag = target_stack.bag,
            dest_slot = target_stack.slot,
            from = "bag " .. source_stack.bag .. " slot " .. source_stack.slot,
            to = "bag " .. target_stack.bag .. " slot " .. target_stack.slot
          }

          -- Capture pre-operation state for verification
          pre_operation_state = CaptureInventoryState(current_operation)
          operation_retry_count = 0

          last_action_time = GetTime()
          continuation_active = true

          -- Pick up source stack and put it on target stack
          PickupContainerItem(source_stack.bag, source_stack.slot)
          PickupContainerItem(target_stack.bag, target_stack.slot)
          return
        end
      end
      -- Stacking complete, clear flag
      job.stacking_for_deposit = nil
    elseif stacks and table.getn(stacks) > 1 then
      -- Check if any stacks can actually be combined
      local _, _, _, _, _, _, maxStack = GetItemInfo(job.itemID)
      if not maxStack then maxStack = 1 end

      local can_combine = false
      for i = 1, table.getn(stacks) do
        for j = i + 1, table.getn(stacks) do
          if stacks[i].count + stacks[j].count <= maxStack then
            can_combine = true
            break
          end
        end
        if can_combine then break end
      end

      if can_combine then
        -- Start stacking process
        job.stacking_for_deposit = true
        -- Will handle stacking on next cycle
        self:RestockBankster_NextJob()
        return
      end
    end

    -- Now find the best stack to deposit from
    -- If we have multiple stacks but couldn't combine them (all full),
    -- prefer using a stack that exactly matches our need, or the smallest sufficient stack
    local bag, slot, to_deposit
    if stacks and table.getn(stacks) > 0 then
      -- Sort stacks by how well they match our need
      table.sort(stacks, function(a, b)
        -- Handle nil values
        if not a then return false end
        if not b then return true end

        local a_matches = (a.count == job.need)
        local b_matches = (b.count == job.need)

        -- Prefer exact matches
        if a_matches and not b_matches then return true end
        if b_matches and not a_matches then return false end

        -- Both match or neither match - check if both are sufficient
        local a_sufficient = a.count >= job.need
        local b_sufficient = b.count >= job.need

        -- If both sufficient, prefer smaller
        if a_sufficient and b_sufficient then
          return a.count < b.count
        end

        -- If only one is sufficient, prefer that one
        if a_sufficient and not b_sufficient then return true end
        if b_sufficient and not a_sufficient then return false end

        -- Neither sufficient - prefer larger
        return a.count > b.count
      end)

      local best_stack = stacks[1]
      if best_stack then
        bag = best_stack.bag
        slot = best_stack.slot
        to_deposit = math.min(best_stack.count, job.need)
      end
    else
      -- Fallback to original FindInBag
      bag, slot, to_deposit = FindInBag(job.itemID, job.need)
    end

    if bag then
      -- item found - switch to the correct tab now that we have an item to place
      if job.tab and GuildBank and GuildBank.currentTab ~= job.tab then
        GuildBankFrameTab_OnClick(job.tab)
      end

      -- Track operation for debugging and verification
      current_operation = {
        type = "deposit",
        itemID = job.itemID,
        amount = to_deposit,
        source_bag = bag,
        source_slot = slot,
        from = "bag " .. bag .. " slot " .. slot,
        to = "guild bank tab " .. job.tab .. " slot " .. job.slot
      }

      -- Capture pre-operation state for verification
      pre_operation_state = CaptureInventoryState(current_operation)
      operation_retry_count = 0


      last_action_time = GetTime()
      continuation_active = true  -- Mark as active
      self:Deposit(job.tab, job.slot, bag, slot, to_deposit)
      job.need = job.need - to_deposit
      if job.need <= 0 then
        -- Clear any stacking flags
        job.stacking_for_deposit = nil
        -- Remove job from front of array (shift)
        for i = 1, table.getn(restock_jobs)-1 do
          restock_jobs[i] = restock_jobs[i+1]
        end
        restock_jobs[table.getn(restock_jobs)] = nil
        -- The BAG_UPDATE will handle continuation, but we need to ensure completion check happens
      end
      return
    end
    -- Not in bags? Try to move from bank
    -- local bbag, bslot, can_move = FindStackInBank(job.itemID, job.need)
    local bbag, bslot, can_move = FindStackInBank(job.itemID, job.need)
    if bbag then
      local eb, es = FindEmptyBagSlot()
      if eb then
        -- Track operation for debugging and verification
        current_operation = {
          type = "bank_to_bag_split",
          itemID = job.itemID,
          amount = can_move,
          source_bag = bbag,
          source_slot = bslot,
          dest_bag = eb,
          dest_slot = es,
          from = "bank bag " .. bbag .. " slot " .. bslot,
          to = "inventory bag " .. eb .. " slot " .. es
        }

        -- Capture pre-operation state for verification
        pre_operation_state = CaptureInventoryState(current_operation)
        operation_retry_count = 0


        last_action_time = GetTime()
        continuation_active = true
        SplitContainerItem(bbag, bslot, can_move)
        PickupContainerItem(eb, es)
        return
      else
        for i = 1, table.getn(restock_jobs)-1 do
          restock_jobs[i] = restock_jobs[i+1]
        end
        restock_jobs[table.getn(restock_jobs)] = nil
        return
      end
    end
    missing_totals[job.itemID] = (missing_totals[job.itemID] or 0) + job.need
    for i = 1, table.getn(restock_jobs)-1 do
      restock_jobs[i] = restock_jobs[i+1]
    end
    restock_jobs[table.getn(restock_jobs)] = nil
    -- Continue immediately for next job since no BAG_UPDATE expected
    continuation_active = false
    self:RestockBankster_NextJob()
    return

  elseif (job.need < 0 or job.isRemoval) then
    -- Track operation for debugging
    current_operation = {
      type = "withdraw",
      itemID = job.itemID,
      amount = math.abs(job.need),
      from = "guild bank tab " .. job.tab .. " slot " .. job.slot,
      to = "inventory"
    }

    last_action_time = GetTime()
    continuation_active = true  -- Mark as active
    self:Withdraw(job.tab, job.slot, 0, 0, math.abs(job.need))
    for i = 1, table.getn(restock_jobs)-1 do
      restock_jobs[i] = restock_jobs[i+1]
    end
    restock_jobs[table.getn(restock_jobs)] = nil
    return
  else
    for i = 1, table.getn(restock_jobs)-1 do
      restock_jobs[i] = restock_jobs[i+1]
    end
    restock_jobs[table.getn(restock_jobs)] = nil
    return
  end
end

