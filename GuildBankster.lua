local _G = _G or getfenv(0)

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

-- Restock variables (defined early so OnUpdate can access them)
local restock_jobs = {} -- Array of job tables; always shift after completion
local missing_totals = {} -- [itemID] = total_missing
local last_action_time = 0
local RESTOCK_TIMEOUT = 5 -- seconds before forcing next job if stuck
local current_operation = {} -- Track current operation for debugging
local pre_operation_state = {} -- Track inventory state before operation
local operation_retry_count = 0
local MAX_RETRIES = 3

local function gb_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff14a868GuildBankster:|r "..msg)
end

function getIDFromLink(link)
  local _,_,id = string.find(link,"item:(%d+)")
  return id
end

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

GuildBank = findGuildBankFrame()
GuildBankster = CreateFrame("Frame")

function GuildBankster:Deposit(tab,gbank_slot,bag,inv_slot,count)
  GuildBank:Send(format("DepositItem:%d:%d:%d:%d:%d",bag,inv_slot,tab,gbank_slot,count))
end

function GuildBankster:Withdraw(tab,gbank_slot,bag,inv_slot,count)
  GuildBank:Send(format("WithdrawItem:%d:%d:%d:%d:%d",tab,gbank_slot,bag,inv_slot,count))
  -- GuildBank:Send("WithdrawItem:" .. frame.tab .. ":" .. frame.slot .. ":0:0:" .. frame.count)
end

function GuildBankster:IsBankContainer(bag)
  return bag < 0 or bag > 4
end

function GuildBankster:ApplyTemplate(template,tab,dry_run)
  
end


local MAX_TABS = 5
local MAX_SLOTS = 98

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


-- Find the frame object
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
  for i=1,98 do
    items[i] = GuildBank.items[tab][i] and { itemID = GuildBank.items[tab][i].itemID, count = GuildBank.items[tab][i].count }
  end
  return items
end

function GuildBankster:BANKFRAME_OPENED()
  local banker = UnitExists("npc") and in_range_npc[UnitName("npc")]
  if not banker or banker.city ~= GetRealZoneText() then return end
  -- if banker.city == GetRealZoneText() then 
  GuildBankster.bank_open = true
  -- only do this if in interact distance?
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

-- Initialize template data (called after VARIABLES_LOADED)
local function InitializeTemplateData()
  if not GuildBanksterDB then return end
  
  -- Initialize template storage if not exists
  if not GuildBanksterDB.templates then
    GuildBanksterDB.templates = {}
  end

  -- Initialize template active states if not exists
  if not GuildBanksterDB.templateActiveStates then
    GuildBanksterDB.templateActiveStates = {
      [1] = false, [2] = false, [3] = false, [4] = false, [5] = false, [6] = false
    }
  end
end

function GuildBankster:VARIABLES_LOADED()
  GuildBanksterDB = GuildBanksterDB or {}
  InitializeTemplateData()
end

GuildBankster:RegisterEvent("BANKFRAME_OPENED")
GuildBankster:RegisterEvent("GOSSIP_SHOW")
GuildBankster:RegisterEvent("BANKFRAME_CLOSED")
GuildBankster:RegisterEvent("VARIABLES_LOADED")
GuildBankster:RegisterEvent("BAG_UPDATE")
GuildBankster:SetScript("OnEvent",function ()
  GuildBankster[event](this,arg1,arg2,arg3,arg4,arg6,arg7,arg8,arg9,arg10)
end)

--------------------------------------------------
-- GLOBAL PERSISTENT DATABASE INITIALIZATION    --
--------------------------------------------------
GuildBanksterDB = GuildBanksterDB or {}

local function SaveGuildBanksterDB()
  GuildBanksterDB.layout = BankLayout
  GuildBanksterDB.ignoredTabs = ignoredTabs
end

-----------------------------------------
-- PLACEHOLDER FUNCTIONS FOR WOW 1.12  --
-----------------------------------------

-- Global variable to store the current item on the cursor.
local CursorItem = nil

-- Global variables for drag & drop within the mockup.
local DraggedItem = nil
local DraggedOrigin = nil

local oldContainerFrameItemButton_OnClick = ContainerFrameItemButton_OnClick
ContainerFrameItemButton_OnClick = function(button, ignoreModifiers,a4,a4,a5,a6,a7,a8,a9)
  -- execute original onclick
  local r = oldContainerFrameItemButton_OnClick(button, ignoreModifiers,a4,a4,a5,a6,a7,a8,a9)

  if button == "LeftButton" then
    local bag,slot = this:GetParent():GetID(), this:GetID()
    if bag and slot then
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink then
        -- GetContainerItemInfo returns multiple values; assume count is the second.
        local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
        CursorItem = { itemLink = itemLink, count = count and (count > 0 and count or 1) or 0 }
        return
      end
    end
    -- else
    CursorItem = nil
      -- GuildBank:ResetAction()
  end
  return r
end

-- Hook ClearCursor so that our stored CursorItem is cleared too.
local OldClearCursor = ClearCursor
function ClearCursor(a1,a2,a3)
  CursorItem = nil
  OldClearCursor(a1,a2,a3)
end

function GetCursorItemLink()
    if CursorItem then
        return CursorItem.itemLink
    end
    return nil
end

function GetCursorItemCount()
    if CursorItem then
        return CursorItem.count
    end
    return 0
end

-- function CursorHasItem()
    -- return CursorItem ~= nil
-- end

-- Extract the item ID from an itemLink.
function getIDFromLink(link)
    local _, _, id = string.find(link, "item:(%d+)")
    return id
end

-- GetItemIcon for vanilla WoW: returns the ninth value from GetItemInfo.
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

--------------------------------------------------
-- MOCK GUILD BANK LAYOUT UI (USING math.mod etc) --
--------------------------------------------------

-- Global tables for layout and ignored tabs.
BankLayout = {}    -- layout: BankLayout[tab][slot] = { itemLink, count, itemID }
ignoredTabs = {}   -- ignoredTabs[tab] = true/false

for tab = 1, 6 do
  BankLayout[tab] = {}
  for slot = 1, 98 do
    BankLayout[tab][slot] = nil
  end
  ignoredTabs[tab] = false
end

-- Create the main frame for the mock bank.
local MockGuildBankFrame = CreateFrame("Frame", "MockGuildBankFrame", UIParent)
MockGuildBankFrame:SetWidth(700)
MockGuildBankFrame:SetHeight(400)
MockGuildBankFrame:SetPoint("CENTER", UIParent)
-- MockGuildBankFrame:EnableMouse(true)
MockGuildBankFrame:SetMovable(true)

-- Background for visibility.
MockGuildBankFrame.bg = MockGuildBankFrame:CreateTexture(nil, "BACKGROUND")
MockGuildBankFrame.bg:SetAllPoints(true)
-- MockGuildBankFrame.bg:SetVertexColor(0, 0, 0, 0.5)

-- Table to hold the frames for each tab.
local tabFrames = {}

-- Create each bank tab frame (each with 98 slots, arranged in 7 rows of 14).
for tab = 1, 6 do
  local tabFrame = CreateFrame("Frame", "MockGuildBankTabFrame"..tab, MockGuildBankFrame)
  tabFrame:SetWidth(680)
  tabFrame:SetHeight(320)
  tabFrame:SetPoint("TOP", MockGuildBankFrame, "TOP", 0, -40)
  tabFrame.tabIndex = tab
  tabFrame.slots = {}
  if (tab ~= 1) then
    tabFrame:Hide()  -- Only show the first tab initially.
  end
  
  -- Create the 98 slot buttons.
  for slot = 1, 98 do
    local row = math.floor((slot - 1) / 14)
    local col = math.mod(slot - 1, 14)
    local btn = CreateFrame("Button", "MockGuildBankTab"..tab.."Slot"..slot, tabFrame, "ItemButtonTemplate")
    btn:SetWidth(40)
    btn:SetHeight(40)
    btn:SetPoint("TOPLEFT", tabFrame, "TOPLEFT", 5 + col * 38, -5 - row * 38)
    btn.slotIndex = slot
    btn.tabIndex = tab

    -- Create a texture to represent the slot’s content.
    btn.texture = btn:CreateTexture(nil, "ARTWORK")
    btn.texture:SetAllPoints(btn)
    -- btn.texture:SetVertexColor(0.2, 0.2, 0.2, 1)  -- Empty slot color.

    -- Create a font string to show the item count.
    btn.countText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    btn.countText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    
    -- Left-click deposits the cursor item into this slot.
    btn:SetScript("OnClick", function()
      if CursorHasItem() then
        local itemLink = GetCursorItemLink()
        local count = tonumber(GetCursorItemCount()) or 1
        local itemID = getIDFromLink(itemLink)
        BankLayout[this.tabIndex][this.slotIndex] = { itemLink = itemLink, count = (count > 0 and count or 1), itemID = tonumber(itemID) }
        this.countText:SetText(count)
        local icon = GetItemIcon(itemLink)
        if icon then
          this.texture:SetTexture(icon)
        end
        -- ClearCursor()
        SaveGuildBanksterDB()
      end
    end)
    
    -- Register for drag events.
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
      if BankLayout[this.tabIndex][this.slotIndex] then
        -- Store the dragged item and clear the slot.
        DraggedItem = BankLayout[this.tabIndex][this.slotIndex]
        DraggedOrigin = this
        BankLayout[this.tabIndex][this.slotIndex] = nil
        this.countText:SetText("")
        -- this.texture:SetVertexColor(0.2, 0.2, 0.2, 1)
        this.texture:SetTexture(nil)
        SaveGuildBanksterDB()
      end
    end)
    btn:SetScript("OnDragStop", function()
      local target = GetMouseFocus()
      if target then
        local slotFrame = target
        while slotFrame and not slotFrame.slotIndex do
          slotFrame = slotFrame:GetParent()
        end
        if slotFrame and slotFrame.slotIndex then
          if slotFrame == DraggedOrigin then
            -- Dropped back on original slot.
            BankLayout[DraggedOrigin.tabIndex][DraggedOrigin.slotIndex] = DraggedItem
            DraggedOrigin.countText:SetText(DraggedItem.count)
            local icon = GetItemIcon(DraggedItem.itemLink)
            if icon then
              DraggedOrigin.texture:SetTexture(icon)
            end
          elseif BankLayout[slotFrame.tabIndex][slotFrame.slotIndex] then
              -- Swap the items.
              local temp = BankLayout[slotFrame.tabIndex][slotFrame.slotIndex]
              BankLayout[slotFrame.tabIndex][slotFrame.slotIndex] = DraggedItem
              slotFrame.countText:SetText(DraggedItem.count)
              local icon = GetItemIcon(DraggedItem.itemLink)
              if icon then
                slotFrame.texture:SetTexture(icon)
              end
              BankLayout[DraggedOrigin.tabIndex][DraggedOrigin.slotIndex] = temp
              DraggedOrigin.countText:SetText(temp.count)
              local icon2 = GetItemIcon(temp.itemLink)
              if icon2 then
                DraggedOrigin.texture:SetTexture(icon2)
              end
          elseif DraggedItem then
              -- Place dragged item into target slot.
              BankLayout[slotFrame.tabIndex][slotFrame.slotIndex] = DraggedItem
              slotFrame.countText:SetText(DraggedItem.count)
              local icon = GetItemIcon(DraggedItem.itemLink)
              if icon then
                slotFrame.texture:SetTexture(icon)
              end
          end
          DraggedItem = nil
          DraggedOrigin = nil
          SaveGuildBanksterDB()
          return
        end
      end
      -- Dropped off a valid target; discard the dragged item.
      DraggedItem = nil
      DraggedOrigin = nil
      SaveGuildBanksterDB()
    end)
    
    tabFrame.slots[slot] = btn
  end
  
  tabFrames[tab] = tabFrame
end

--------------------------------------------------
-- TAB BUTTONS WITH RIGHT-CLICK TO TOGGLE IGNORED --
--------------------------------------------------

for tab = 1, 6 do
  local tabButton = CreateFrame("Button", "MockGuildBankTabButton"..tab, MockGuildBankFrame, "UIPanelButtonTemplate")
  tabButton:SetWidth(80)
  tabButton:SetHeight(25)
  tabButton:SetText("Tab " .. tab)
  tabButton:SetPoint("BOTTOMLEFT", MockGuildBankFrame, "BOTTOMLEFT", 5 + (tab - 1) * 85, 5)
  tabButton.tabIndex = tab
  tabButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  
  tabButton:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      -- Toggle ignored state.
      if ignoredTabs[this.tabIndex] then
         ignoredTabs[this.tabIndex] = false
         this:SetText("Tab " .. this.tabIndex)
      else
         ignoredTabs[this.tabIndex] = true
         this:SetText("Tab " .. this.tabIndex .. " (ignored)")
      end
      SaveGuildBanksterDB()
    else
      -- Left-click: switch to tab if not ignored.
      if not ignoredTabs[this.tabIndex] then
         for i = 1, 6 do
           if (i == this.tabIndex) then
              tabFrames[i]:Show()
           else
              tabFrames[i]:Hide()
           end
         end
      end
    end
  end)
end

--------------------------------------------------
-- Control buttons
--------------------------------------------------

-- button to drag frame with
local moveButton = CreateFrame("Button", "PrintBankLayoutButton", MockGuildBankFrame, "UIPanelButtonTemplate")
moveButton:SetWidth(100)
moveButton:SetHeight(25)
moveButton:SetText("Move")
moveButton:SetPoint("BOTTOMRIGHT", MockGuildBankFrame, "BOTTOMRIGHT", -5, 5)
moveButton:EnableMouse(true)
-- printButton:SetMovable(true)
moveButton:RegisterForDrag("LeftButton")
moveButton:SetScript("OnDragStart", function()
  this:GetParent():StartMoving()
end)
moveButton:SetScript("OnDragStop", function()
  this:GetParent():StopMovingOrSizing()
end)

local closeButton = CreateFrame("Button", "CloseBankLayoutButton", MockGuildBankFrame, "UIPanelButtonTemplate")
closeButton:SetWidth(100)
closeButton:SetHeight(25)
closeButton:SetText("CloseAll")
closeButton:SetPoint("BOTTOM", moveButton, "TOP", 0, 3)
closeButton:EnableMouse(true)
-- printButton:SetMovable(true)
-- printButton:RegisterForDrag("LeftButton")
closeButton:SetScript("OnClick", function()
  MockGuildBankFrame:Hide()
end)

--------------------------------------------------
-- LOAD SAVED DATA ON VARIABLES_LOADED EVENT    --
--------------------------------------------------
MockGuildBankFrame:SetScript("OnEvent", function ()
  MockGuildBankFrame[event](this, arg1, arg2, arg3, arg4, arg6, arg7, arg8, arg9, arg10)
end)
MockGuildBankFrame:RegisterEvent("VARIABLES_LOADED")

function MockGuildBankFrame:VARIABLES_LOADED()
  GuildBanksterDB = GuildBanksterDB or {}
  if GuildBanksterDB.layout then
    BankLayout = GuildBanksterDB.layout
    for tab = 1, 6 do
      local tabFrame = tabFrames[tab]
      for slot = 1, 98 do
        local btn = tabFrame.slots[slot]
        local data = BankLayout[tab][slot]
        if data then
          btn.countText:SetText(data.count)
          local icon = GetItemIcon(data.itemLink)
          if icon then
            btn.texture:SetTexture(icon)
          end
        else
          btn.countText:SetText("")
          -- btn.texture:SetVertexColor(0.2, 0.2, 0.2, 1)
          btn.texture:SetTexture(nil)
        end
      end
    end
  end
  if GuildBanksterDB.ignoredTabs then
    ignoredTabs = GuildBanksterDB.ignoredTabs
    for tab = 1, 6 do
      local tabButton = _G["MockGuildBankTabButton"..tab]
      if ignoredTabs[tab] then
        tabButton:SetText("Tab " .. tab .. " (ignored)")
      else
        tabButton:SetText("Tab " .. tab)
      end
    end
  end
  _G["HideBankButton"]:Click()
end

-- Finally, update the global database initially.
SaveGuildBanksterDB()

--------------------------------------------------
-- TEMPLATE INTEGRATION WITH GUILD BANK UI
--------------------------------------------------
local TemplateFrames = {}
local CurrentTemplateTab = 1
local TemplateMode = false

-- Function to import old template data from BankLayout
function GuildBankster_ImportOldTemplates()
  if not BankLayout then
    gb_print("No old template data found to import")
    return
  end
  
  if not GuildBanksterDB.templates then
    GuildBanksterDB.templates = {}
  end
  
  local importCount = 0
  for tab = 1, 6 do
    if BankLayout[tab] then
      if not GuildBanksterDB.templates[tab] then
        GuildBanksterDB.templates[tab] = {}
      end
      
      local slotCount = 0
      for slot = 1, 98 do
        if BankLayout[tab][slot] then
          -- Import the old data structure
          GuildBanksterDB.templates[tab][slot] = {
            itemLink = BankLayout[tab][slot].itemLink,
            count = BankLayout[tab][slot].count or 1,
            itemID = BankLayout[tab][slot].itemID or tonumber(getIDFromLink(BankLayout[tab][slot].itemLink))
          }
          slotCount = slotCount + 1
        end
      end
      
      if slotCount > 0 then
        gb_print("Imported " .. slotCount .. " items to template tab " .. tab)
        importCount = importCount + slotCount
      end
    end
  end
  
  if importCount > 0 then
    gb_print("Successfully imported " .. importCount .. " total items from old templates")
    SaveGuildBanksterDB()
  else
    gb_print("No items found to import")
  end
end

-- Create Template bottom tab button
local function CreateTemplateTab()
  if not GuildBankFrame then return end
  
  -- Create the Template tab button using the same template as other bottom tabs
  local templateTab = CreateFrame("Button", "GuildBankFrameBottomTab4", GuildBankFrame, "TWGuildFrameBottomTabButtonTemplate")
  -- templateTab:SetWidth(120)
  -- templateTab:SetHeightWidth(120)
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
    -- print("restok")
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
  
  -- Create 98 template slot buttons using the same template as guild bank items
  for slot = 1, 98 do
    local btn = CreateFrame("Button", "GuildBankTemplateSlot"..slot, frame, "GuildBankFrameItemButtonTemplate")
    if not btn then
      -- Fallback if template doesn't exist
      btn = CreateFrame("Button", "GuildBankTemplateSlot"..slot, frame)
      btn:SetWidth(37)
      btn:SetHeight(37)
      gb_print("Using fallback button creation for slot " .. slot)
    end
    
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
        local template = GuildBanksterDB.templates[CurrentTemplateTab]
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
      local template = GuildBanksterDB.templates[CurrentTemplateTab]
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
  
  gb_print("Created template slots frame")
  return frame
end

-- Handle Template tab click
function GuildBankster_TemplateTab_OnClick()
  TemplateMode = true
  
  -- Reset template tab to ensure clean state when entering template mode
  -- CurrentTemplateTab = 1
  
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
end

-- Update template display
function GuildBankster_UpdateTemplateDisplay()
  -- Initialize templates if needed
  if not GuildBanksterDB or not GuildBanksterDB.templates then
    if not GuildBanksterDB then return end
    GuildBanksterDB.templates = {}
  end
  
  if not GuildBanksterDB.templates[CurrentTemplateTab] then
    GuildBanksterDB.templates[CurrentTemplateTab] = {}
  end
  
  local template = GuildBanksterDB.templates[CurrentTemplateTab]
  local isActive = GuildBanksterDB.templateActiveStates and GuildBanksterDB.templateActiveStates[CurrentTemplateTab] or false
  
  for slot = 1, 98 do
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
  
  -- Update tab title to show active/inactive state
  if GuildBankFrameTabTitle then
    local statusText = isActive and " (Active)" or " (Inactive)"
    GuildBankFrameTabTitle:SetText("Template " .. CurrentTemplateTab .. statusText)
  end
end

-- Track what template item is being "held"
local HeldTemplateItem = nil

-- Handle template slot click
function GuildBankster_TemplateSlot_OnClick(self)
  if not self then return end
  local slot = self.slotID
  local button = arg1  -- Get which mouse button was clicked
  
  -- Initialize template if needed
  if not GuildBanksterDB or not GuildBanksterDB.templates then
    return
  end
  if not GuildBanksterDB.templates[CurrentTemplateTab] then
    GuildBanksterDB.templates[CurrentTemplateTab] = {}
  end
  
  local template = GuildBanksterDB.templates[CurrentTemplateTab]
  
  if button == "RightButton" then
    -- Right click: Clear the held item/cursor
    if HeldTemplateItem then
      HeldTemplateItem = nil
      -- Also hide the guild bank cursor if showing
      if GuildBank and GuildBank.cursorFrame then
        GuildBank.cursorFrame:Hide()
      end
      if GuildBankFrameCursorItemFrame then
        GuildBankFrameCursorItemFrame:Hide()
      end
    elseif template[slot] then
      -- If no held item, clear the slot
      template[slot] = nil
      GuildBankster_UpdateTemplateDisplay()
    end
  else
    -- Left click: Handle item placement and pickup
    if CursorHasItem() then
      -- Drop item from cursor into template slot (don't clear cursor)
      local itemLink = GetCursorItemLink()
      local count = tonumber(GetCursorItemCount()) or 1
      local itemID = getIDFromLink(itemLink)
      
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
  
  local template = GuildBanksterDB.templates[CurrentTemplateTab]
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

-- Hook function variables (declare first)
local GuildBankFrame_OnShow_Original
local GuildBankFrameBottomTab_OnClick_Original
local GuildBankFrameTab_OnClick_Original

-- Hook into guild bank frame show
local function GuildBankster_OnGuildBankShow(a,b,c,d,e,f)
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
    GuildBanksterDB.templateActiveStates[id] = not GuildBanksterDB.templateActiveStates[id]
    local state = GuildBanksterDB.templateActiveStates[id] and "active" or "inactive"
    gb_print("Template " .. id .. " is now " .. state)
    GuildBankster_UpdateTemplateDisplay()
    return
  end

  -- Left-click: switch templates
  -- Uncheck all tabs first (like the original does)
  for i = 1, 6 do
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
  GuildBankster_UpdateTemplateDisplay()
end

-- Set up hooks immediately since Turtle guild bank loads before us
-- Store original functions before hooking
if GuildBankFrame then
  -- Create the Template tab immediately when addon loads
  CreateTemplateTab()
  
  GuildBankFrame_OnShow_Original = GuildBankFrame_OnShow
  GuildBankFrame_OnShow = GuildBankster_OnGuildBankShow
end

if GuildBankFrameBottomTab_OnClick then
  GuildBankFrameBottomTab_OnClick_Original = GuildBankFrameBottomTab_OnClick
  GuildBankFrameBottomTab_OnClick = GuildBankster_BottomTab_OnClick
end

if GuildBankFrameTab_OnClick then
  GuildBankFrameTab_OnClick_Original = GuildBankFrameTab_OnClick
  GuildBankFrameTab_OnClick = GuildBankster_Tab_OnClick
end


-- Export function to apply template to actual bank
function GuildBankster_ApplyTemplateToBank()
  if not CurrentTemplateTab or not GuildBanksterDB.templates[CurrentTemplateTab] then
    gb_print("No template selected")
    return
  end
  
  -- Copy template to BankLayout for the restock system to use
  BankLayout[CurrentTemplateTab] = {}
  for slot = 1, 98 do
    if GuildBanksterDB.templates[CurrentTemplateTab][slot] then
      BankLayout[CurrentTemplateTab][slot] = GuildBanksterDB.templates[CurrentTemplateTab][slot]
    end
  end
  
  gb_print("Template " .. CurrentTemplateTab .. " ready for restocking")
end

-- Copy current guild bank tab to template
function GuildBankster_CopyBankToTemplate()
  if not CurrentTemplateTab then
    gb_print("No template tab selected")
    return
  end
  
  if not GuildBank or not GuildBank.currentTab then
    gb_print("Guild bank not available")
    return
  end
  
  local bankTab = GuildBank.currentTab
  if not GuildBank.tabs or not GuildBank.tabs[bankTab] then
    gb_print("Guild bank tab " .. bankTab .. " not available")
    return
  end
  
  -- Initialize template tab if needed
  if not GuildBanksterDB.templates[CurrentTemplateTab] then
    GuildBanksterDB.templates[CurrentTemplateTab] = {}
  end
  
  -- Copy items from guild bank to template
  local copiedCount = 0
  for slot = 1, 98 do
    local item = GuildBank.tabs[bankTab][slot]
    if item and item.link then
      local itemID = getIDFromLink(item.link)
      GuildBanksterDB.templates[CurrentTemplateTab][slot] = {
        itemLink = item.link,
        count = item.count or 1,
        itemID = tonumber(itemID)
      }
      copiedCount = copiedCount + 1
    else
      GuildBanksterDB.templates[CurrentTemplateTab][slot] = nil
    end
  end
  
  -- Update display if in template mode
  if TemplateMode then
    GuildBankster_UpdateTemplateDisplay()
  end
  
  gb_print("Copied " .. copiedCount .. " items from guild bank tab " .. bankTab .. " to template " .. CurrentTemplateTab)
end

-- Clear current template
function GuildBankster_ClearTemplate()
  if not CurrentTemplateTab then
    gb_print("No template tab selected")
    return
  end
  
  GuildBanksterDB.templates[CurrentTemplateTab] = {}
  
  -- Update display if in template mode
  if TemplateMode then
    GuildBankster_UpdateTemplateDisplay()
  end
  
  gb_print("Cleared template " .. CurrentTemplateTab)
end

--------------------------------------------------
-- HELPER: Find an item in your inventory by itemID.
--------------------------------------------------
local function FindItemInInventory(itemID)
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink then
        local foundID = getIDFromLink(itemLink)
        if tonumber(foundID) == tonumber(itemID) then
          return bag, slot
        end
      end
    end
  end
  return nil, nil
end

--------------------------------------------------
-- CONTINUATION SYSTEM: Event-driven processing
--------------------------------------------------
local continuation_frame = CreateFrame("Frame")
local continuation_queue = {}
local continuation_active = false
local continuation_timeout_check = 0

-- OnUpdate only for timeout checking
continuation_frame:SetScript("OnUpdate", function()
  continuation_timeout_check = continuation_timeout_check + arg1
  
  -- Check timeout every 0.1 seconds
  if continuation_timeout_check >= 0.1 then
    continuation_timeout_check = 0
    
    -- Check for restock timeout
    if GuildBankster.wait_on and GuildBankster.wait_on > 0 then
      if last_action_time > 0 and GetTime() - last_action_time > RESTOCK_TIMEOUT then
        -- Generate detailed diagnostic report
        
        GuildBankster.wait_on = 0
        last_action_time = 0
        current_operation = {}
        GuildBankster:RestockBankster_NextJob()
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

local gbank_queue = {}
-- local gbankQueueFrame = CreateFrame("Frame")
GuildBankster.wait_on = 0
GuildBankster.actions = {
  print = "print",
  deposit = "deposit",
  withdrawSome = "withdrawSome",
  withdrawAll = "withdrawAll",
  moveItems = "moveItems",
}

--------------------------------------------------
-- DIAGNOSTIC: Test BAG_UPDATE counts for different operations
--------------------------------------------------
local bag_update_diagnostic = {
  active = false,
  count = 0,
  operation = "",
  start_time = 0,
  timeout = 3, -- seconds to wait before resetting
}

function GuildBankster:StartBagDiagnostic(operation)
  bag_update_diagnostic.active = true
  bag_update_diagnostic.count = 0
  bag_update_diagnostic.operation = operation
  bag_update_diagnostic.start_time = GetTime()
end

function GuildBankster:EndBagDiagnostic()
  if bag_update_diagnostic.active then
    bag_update_diagnostic.active = false
  end
end

function GuildBankster:TestBankToInventoryMoves()
end

function GuildBankster:TestMove(moveType)
  self:StartBagDiagnostic(moveType)
  -- User performs the move manually
  -- Diagnostic will track BAG_UPDATE events
  -- After 5 seconds or manual call to EndBagDiagnostic, results are printed
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
  self.wait_on = 0
  continuation_active = false
  last_action_time = 0
  current_operation = {}
  for i = 1, table.getn(restock_jobs) do restock_jobs[i] = nil end
  for i = 1, table.getn(continuation_queue) do continuation_queue[i] = nil end
end

function GuildBankster:BAG_UPDATE(which)
  -- Track diagnostic events if active
  if bag_update_diagnostic.active then
    bag_update_diagnostic.count = bag_update_diagnostic.count + 1
    -- Auto-end diagnostic after timeout
    if GetTime() - bag_update_diagnostic.start_time > bag_update_diagnostic.timeout then
      self:EndBagDiagnostic()
    end
  end
  
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

function GuildBankster:ProgressQueue()
  if not gbank_queue[1] then
    -- print("non")
    return
  end

  local action = table.remove(gbank_queue, 1)

  print("try "..action.type)
  print(self.wait_on)

  if action.type == self.actions.print then
    for _,line in action.args do
      gb_print(line)
    end
    self:ProgressQueue()
  end
  if action.type == self.actions.deposit then
    -- print("deposit try")
    self.wait_on = 1 -- 1 update
    self:Deposit(unpack(action.args))
    return
  end
  if action.type == self.actions.withdrawSome then
    -- print("withdraw some")
    -- GuildBankster:Withdraw(unpack(action.args))
    local bank_tab = action.args[1]
    local bank_slot = action.args[2]
    local difference = action.args[3]

    -- partial removal requires use of specific bag slots
    for bag = 0, NUM_BAG_SLOTS do
      local numSlots = GetContainerNumSlots(bag)
      for slot = 1, numSlots do
        local itemLink = GetContainerItemLink(bag, slot)
        if not itemLink then
          self.wait_on = 2 -- 2 update
          self:Withdraw(bank_tab, bank_slot, bag, slot, difference)
          -- print("withdraw from "..bank_tab.." slot "..bank_slot.." "..difference)
          return
        end
      end
    end
    -- todo, combine these two removals, you should really need empty space for either case
    return
  end
  if action.type == self.actions.withdrawAll then
    -- print("withdraw all")
    self.wait_on = 1 -- 1 update
    self:Withdraw(unpack(action.args))
    return
  end
  if action.type == self.actions.moveItems then
    self.wait_on = 3 -- 3 updates
    local bag,slot,targetBag,targetSlot,count = unpack(action.args)
    
    SplitContainerItem(bag, slot,count)
    PickupContainerItem(targetBag, targetSlot)
  end
end

--------------------------------------------------
-- HELPER FUNCTIONS FOR INVENTORY SIMULATION
--------------------------------------------------

-- Build a snapshot of available counts in your bags.
local function BuildInventoryState()
  local state = {}
  for bag = 0, NUM_BAG_SLOTS do
    state[bag] = {}
    local numSlots = GetContainerNumSlots(bag)
    for slot = 1, numSlots do
      local _, count = GetContainerItemInfo(bag, slot)
      state[bag][slot] = count and (count > 0 and count or 1) or 0
    end
  end
  return state
end

-- Helper: Build combined inventory state including player bank
local bank_bag_ids = {-1, 5, 6, 7, 8, 9, 10}
local ordered_bags = {0, 1, 2, 3, 4, -1, 5, 6, 7, 8, 9, 10}

local function IsBankBag(bag)
  for _, bankBag in ipairs(bank_bag_ids) do
    if bag == bankBag then return true end
  end
  return false
end

local function BuildCombinedInventoryState()
  local state = {}
  for _, bag in ipairs(ordered_bags) do
    state[bag] = {}
    for slot = 1, GetContainerNumSlots(bag) do
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink then
        local itemID = tonumber(getIDFromLink(itemLink))
        local _, count = GetContainerItemInfo(bag, slot)
        count = count and (count > 0 and count or 1) or 0
        state[bag][slot] = { itemID = itemID, count = count }
      end
    end
  end
  return state
end

-- Queue moves from player bank to inventory
local function QueueMoveFromPlayerBankToInventory(itemID, amount, inventoryState)
  local moved = 0
  for _, bag in ipairs(bank_bag_ids) do
    for slot = 1, GetContainerNumSlots(bag) do
      local slotData = inventoryState[bag][slot]
      if slotData and slotData.itemID == itemID and slotData.count > 0 then
        local toMove = math.min(slotData.count, amount)
        for targetBag = 0, NUM_BAG_SLOTS do
          for targetSlot = 1, GetContainerNumSlots(targetBag) do
            if not inventoryState[targetBag][targetSlot] then
              table.insert(gbank_queue, {type = GuildBankster.actions.moveItems, args = {bag, slot, targetBag, targetSlot, toMove}})
              slotData.count = slotData.count - toMove
              if slotData.count <= 0 then
                inventoryState[bag][slot] = nil
              end
              inventoryState[targetBag][targetSlot] = {itemID = itemID, count = toMove}
              amount = amount - toMove
              moved = moved + toMove
              if amount <= 0 then return true, moved end
              break
            end
          end
          if amount <= 0 then break end
        end
      end
      if amount <= 0 then break end
    end
    if amount <= 0 then break end
  end
  return moved > 0, moved
end

local function FindAndConsume(inventory, itemID, amount)
  for _, bag in ipairs(ordered_bags) do
    if inventory[bag] then
      for slot, slotData in pairs(inventory[bag]) do
        if slotData.itemID == itemID and slotData.count > 0 then
          local toUse = math.min(slotData.count, amount)
          slotData.count = slotData.count - toUse
          if slotData.count <= 0 then
            inventory[bag][slot] = nil
          end
          return bag, slot, toUse
        end
      end
    end
  end
  return nil, nil, 0
end

-- Modified Restock function
local function RestockBankFromAllSources()
  local inventoryState = BuildCombinedInventoryState()
  local missingItems = {}

  table.insert(gbank_queue, { type = GuildBankster.actions.print, args = { "Beginning Guildbank restock from all sources..." } })

  for tab = 1, 6 do
    if not ignoredTabs[tab] then
      local currentItems = ScanGuildBank(tab)
      for slot = 1, 98 do
        local desired = BankLayout[tab][slot]
        if desired then
          local current = currentItems[slot]
          local missing = desired.count

          if current then
            if current.itemID == desired.itemID then
              missing = desired.count - current.count
              if missing < 0 then missing = 0 end
            elseif current.count > 0 then
              table.insert(gbank_queue, { type = GuildBankster.actions.withdrawAll, args = { tab, slot, 0, 0, current.count } })
            end
          end

          while missing > 0 do
            -- Try to find in non-bank bags FIRST
            local bag, inv_slot, depositCount = FindAndConsume(inventoryState, desired.itemID, missing)
            if bag and not IsBankBag(bag) then
              table.insert(gbank_queue, { type = GuildBankster.actions.deposit, args = { tab, slot, bag, inv_slot, depositCount } })
              missing = missing - depositCount
            else
              -- Now try to move from bank to inventory
              local moved_any, moved_count = QueueMoveFromPlayerBankToInventory(desired.itemID, missing, inventoryState)
              if moved_any then
                -- Wait for move to complete, then loop again.
                break
              else
                missingItems[desired.itemID] = (missingItems[desired.itemID] or 0) + missing
                break
              end
            end
          end
        end
      end
    end
  end

  
  if next(missingItems) then
    local lines = { "The following could not be restocked due to insufficient combined inventory:" }
    for itemID, count in pairs(missingItems) do
      table.insert(lines, string.format("%d : %s", count, GetItemInfo("item:"..itemID)))
    end
    table.insert(gbank_queue, { type = GuildBankster.actions.print, args = lines })
  else
    table.insert(gbank_queue, { type = GuildBankster.actions.print, args = { "Guildbank restock finished." } })
  end

  GuildBankster:ProgressQueue()
end

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

-- (1) Build restock jobs (call this on button)
function GuildBankster:RestockBankStepwise()
  print("Beginning Guildbank restock...")
  -- Clear previous jobs by nil'ing all values
  for i = 1, table.getn(restock_jobs) do restock_jobs[i] = nil end
  last_action_time = 0  -- Reset timeout tracking

  local job_i = 1
  for tab = 1, 6 do
    if not ignoredTabs[tab] then
      local desired_layout = BankLayout[tab]
      local current = ScanGuildBank(tab)
      for slot = 1, 98 do
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

-- (2) Stepwise dispatcher
function GuildBankster:RestockBankster_NextJob()
  local job = restock_jobs[1]
  if not job then
    if next(missing_totals) then
      local lines = { "The insufficient inventory to stock:" }
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
        
        
        -- Switch to correct tab if needed
        if job.tab and GuildBank and GuildBank.currentTab ~= job.tab then
          GuildBankFrameTab_OnClick(job.tab)
        end
        
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
      -- item found, switch to the tab we're working on if it's different from current
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

--------------------------------------------------
-- RESTOCK FUNCTION: QUEUE DEPOSIT ACTIONS
--------------------------------------------------
local function RestockBank()
  local inventoryState = BuildInventoryState()  -- snapshot of your inventory
  local missingItems = {}  -- table to record materials we couldn't fully restock

  table.insert(gbank_queue, { type = GuildBankster.actions.print, args = { "Beginning Guildbank restock..." } })
  for tab = 1, 6 do
    if not ignoredTabs[tab] then
      local currentItems = ScanGuildBank(tab)
      for slot = 1, 98 do
        local desired = BankLayout[tab][slot]
        if desired then
          local current = currentItems[slot]
          local missing = desired.count
          if current then
            if current.itemID == desired.itemID then
              missing = desired.count - current.count
              if missing < 0 then
                -- slot is occupied with wrong count, remove some
                local t = tab
                local s = slot
                local difference = -missing
                local item = current.itemID
                table.insert(gbank_queue, { type = GuildBankster.actions.withdrawSome, args = { t, s, difference } })
                missing = 0
              end
            elseif current.count > 0 then
              -- slot is occupied with wrong item, remove it
              local t = tab
              local s = slot
              local c = current.count
              table.insert(gbank_queue, { type = GuildBankster.actions.withdrawAll, args = { t, s, 0, 0, c } })
            end
          end
          if missing > 0 then
            -- Loop until we've queued deposits for the entire missing amount.
            while missing > 0 do
              local bag, inv_slot, depositCount = FindAndConsume(inventoryState, desired.itemID, missing)
              if bag and inv_slot and depositCount > 0 then
                -- Localize values for closure capture.
                local t = tab
                local s = slot
                local b = bag
                local i = inv_slot
                local m = depositCount
                table.insert(gbank_queue, { type = GuildBankster.actions.deposit, args = { t, s, b, i, m } })
                missing = missing - depositCount
              else
                -- No more inventory available for this item.
                missingItems[desired.itemID] = (missingItems[desired.itemID] or 0) + missing
                break
              end
            end
          end
        end
      end
    end
  end
  table.insert(gbank_queue, { type = GuildBankster.actions.print, args = { "Guildbank restock finished." } })
  if next(missingItems) then
    local lines = { "The following could not be restocked due to insufficient inventory:" }
    for itemID, count in pairs(missingItems) do
      table.insert(lines, string.format("%d : %s", count, GetItemInfo("item:"..itemID)))
    end
    table.insert(gbank_queue, { type = GuildBankster.actions.print, args = lines })
  end
  GuildBankster:ProgressQueue()
end

--------------------------------------------------
-- RESTOCK BUTTON: When pressed, trigger the RestockBank function.
--------------------------------------------------
local restockButton = CreateFrame("Button", "RestockBankButton", MockGuildBankFrame, "UIPanelButtonTemplate")
restockButton:SetWidth(100)
restockButton:SetHeight(25)
restockButton:SetText("Restock Bank")
restockButton:SetPoint("BOTTOM", MockGuildBankFrame, "BOTTOM", 0, 40)
restockButton:SetScript("OnClick", function()
  GuildBankster:RestockBankStepwise()
  -- RestockBankFromAllSources()
end)

--------------------------------------------------
-- HIDE BUTTON: When pressed, trigger the RestockBank function.
--------------------------------------------------
local hideButton = CreateFrame("Button", "HideBankButton", MockGuildBankFrame, "UIPanelButtonTemplate")
hideButton:SetWidth(100)
hideButton:SetHeight(25)
hideButton:SetText("Hide Templates")
hideButton:SetPoint("BOTTOM", MockGuildBankFrame, "BOTTOM", -100, 40)
hideButton:SetScript("OnClick", function()
  for i=1,6 do
    _G["MockGuildBankTabFrame"..i]:Hide()
  end
end)

-- stuff bank needs:
-- -- essence of air
-- -- bronze scarabs
-- -- LBS
-- essence of water

-- todo, make lc sheet tally names on items
-- todo, assing automation by placing peoples names and roles
-- todo, skybox upscales
-- tood, recheck health stone activation
-- todo kel addon doesn't shut off
-- todo, raid organizer needs work, including 20 man generic option
-- todo, cthun organizer needs work and autoexport
-- todo, automana should use tea if you don't have mana and just base it on hp
-- todo did I HS at all on emps?
-- todo make twthreat read version from .toc
-- luna, make clickcasting things auto-lowercase
-- todo, import roster from signup site to pull from for sheet
-- todo, raid maker should have an auto-restore-groups button that will change a group but restore to the quick-saved raid after ecounter end.
-- How though?
-- make cthun marker MUCH better
-- todo make a lib for managing external files and interacting/making streams --
