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

function GuildBankster:VARIABLES_LOADED()
  GuildBanksterDB = GuildBanksterDB or {}
end



GuildBankster:SetScript("OnEvent",function ()
  GuildBankster[event](this,arg1,arg2,arg3,arg4,arg6,arg7,arg8,arg9,arg10)
end)
GuildBankster:RegisterEvent("BANKFRAME_OPENED")
GuildBankster:RegisterEvent("GOSSIP_SHOW")
GuildBankster:RegisterEvent("BANKFRAME_CLOSED")
GuildBankster:RegisterEvent("VARIABLES_LOADED")
GuildBankster:RegisterEvent("BAG_UPDATE")

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
        CursorItem = { itemLink = itemLink, count = count > 0 and count or 1 }
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
-- DEPOSIT QUEUE: Process one deposit every 0.2 sec.
--------------------------------------------------
local depositQueue = {}
local depositFrame = CreateFrame("Frame")
depositFrame.lastTime = 0
depositFrame:SetScript("OnUpdate", function()
  this.lastTime = this.lastTime + arg1
  
  -- Check for restock timeout
  if GuildBankster.wait_on and GuildBankster.wait_on > 0 then
    if last_action_time > 0 and GetTime() - last_action_time > RESTOCK_TIMEOUT then
      -- Generate detailed diagnostic report
      gb_print("|cffff0000=== TIMEOUT DETECTED ===|r")
      gb_print("Operation: " .. (current_operation.type or "unknown"))
      if current_operation.itemID then
        local itemName = GetItemInfo("item:"..current_operation.itemID) or ("item:"..current_operation.itemID)
        gb_print("Item: " .. itemName .. " (ID: " .. current_operation.itemID .. ")")
      end
      if current_operation.amount then
        gb_print("Amount: " .. current_operation.amount)
      end
      if current_operation.from then
        gb_print("From: " .. current_operation.from)
      end
      if current_operation.to then
        gb_print("To: " .. current_operation.to)
      end
      gb_print("Expected " .. GuildBankster.wait_on .. " more BAG_UPDATE events")
      gb_print("Waited " .. string.format("%.1f", GetTime() - last_action_time) .. " seconds")
      gb_print("Forcing next job...")
      
      GuildBankster.wait_on = 0
      last_action_time = 0
      current_operation = {}
      GuildBankster:RestockBankster_NextJob()
    end
  end
  
  if this.lastTime >= 0.4 then
    this.lastTime = 0
    local size = table.getn(depositQueue)
    if size > 0 then
      local action = table.remove(depositQueue, 1)
      action(size)  -- Execute the deposit command.
    end
  end
end)

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

-- gbankQueueFrame:RegisterEvent("BAG_UPDATE")
-- gbankQueueFrame:SetScript("OnEvent", function ()
--   print("bag event")
--   if gbankQueueFrame.wait_on > 1 then
--     gbankQueueFrame.wait_on = gbankQueueFrame.wait_on - 1
--     print("waiting")
--   else
--     GuildBankster:ProgressQueue()
--   end
-- end)

-- function GuildBankster:BAG_UPDATE(which)
--   if self.wait_on > 1 then
--     self.wait_on = self.wait_on - 1
--     -- print("waiting")
--   else
--     self:ProgressQueue()
--   end
-- end

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
  gb_print("Starting diagnostic: " .. operation)
end

function GuildBankster:EndBagDiagnostic()
  if bag_update_diagnostic.active then
    gb_print(string.format("Operation '%s' triggered %d BAG_UPDATE events", 
      bag_update_diagnostic.operation, bag_update_diagnostic.count))
    bag_update_diagnostic.active = false
  end
end

function GuildBankster:TestBankToInventoryMoves()
  gb_print("Testing bank-to-inventory move patterns...")
  gb_print("Please manually test the following:")
  gb_print("1. /run GuildBankster:TestMove('full_to_empty') - then move full stack to empty slot")
  gb_print("2. /run GuildBankster:TestMove('partial_to_empty') - then move partial stack to empty slot")
  gb_print("3. /run GuildBankster:TestMove('partial_to_partial') - then move partial onto partial")
  gb_print("4. /run GuildBankster:TestMove('partial_to_full') - then move partial onto full")
  gb_print("5. /run GuildBankster:TestMove('split_to_empty') - then split stack to empty")
end

function GuildBankster:TestMove(moveType)
  self:StartBagDiagnostic(moveType)
  -- User performs the move manually
  -- Diagnostic will track BAG_UPDATE events
  -- After 5 seconds or manual call to EndBagDiagnostic, results are printed
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
  
  if self.wait_on and self.wait_on > 0 then
    self.wait_on = self.wait_on - 1
    if self.wait_on == 0 then
      current_operation = {}  -- Clear operation on success
      self:RestockBankster_NextJob()
    else
      -- Check for timeout - force continue if we've been waiting too long
      if last_action_time > 0 and GetTime() - last_action_time > RESTOCK_TIMEOUT then
        gb_print("Timeout detected, forcing next job...")
        self.wait_on = 0
        self:RestockBankster_NextJob()
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
    gb_print("Tried to remove extra " .. GetItemInfo("item:"..item) .. " but had no empty bag space.")
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


depositFrame.lastTime = 0
depositFrame:SetScript("OnUpdate", function()
  this.lastTime = this.lastTime + arg1
  
  -- Check for restock timeout
  if GuildBankster.wait_on and GuildBankster.wait_on > 0 then
    if last_action_time > 0 and GetTime() - last_action_time > RESTOCK_TIMEOUT then
      -- Generate detailed diagnostic report
      gb_print("|cffff0000=== TIMEOUT DETECTED ===|r")
      gb_print("Operation: " .. (current_operation.type or "unknown"))
      if current_operation.itemID then
        local itemName = GetItemInfo("item:"..current_operation.itemID) or ("item:"..current_operation.itemID)
        gb_print("Item: " .. itemName .. " (ID: " .. current_operation.itemID .. ")")
      end
      if current_operation.amount then
        gb_print("Amount: " .. current_operation.amount)
      end
      if current_operation.from then
        gb_print("From: " .. current_operation.from)
      end
      if current_operation.to then
        gb_print("To: " .. current_operation.to)
      end
      gb_print("Expected " .. GuildBankster.wait_on .. " more BAG_UPDATE events")
      gb_print("Waited " .. string.format("%.1f", GetTime() - last_action_time) .. " seconds")
      gb_print("Forcing next job...")
      
      GuildBankster.wait_on = 0
      last_action_time = 0
      current_operation = {}
      GuildBankster:RestockBankster_NextJob()
    end
  end
  
  if this.lastTime >= 0.4 then
    this.lastTime = 0
    local size = table.getn(depositQueue)
    if size > 0 then
      local action = table.remove(depositQueue, 1)
      action(size)  -- Execute the deposit command.
    end
  end
end)

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
        count = count > 0 and count or 1
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

local function FindInBag(itemID, amount)
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink and tonumber(getIDFromLink(itemLink)) == itemID then
        local _, count = GetContainerItemInfo(bag, slot)
        count = count > 0 and count or 1
        if count > 0 then
          return bag, slot, math.min(count, amount)
        end
      end
    end
  end
  return nil, nil, 0
end

local function FindInBank(itemID, amount)
  for i = 1, table.getn(bank_bag_ids) do
    local bag = bank_bag_ids[i]
    for slot = 1, GetContainerNumSlots(bag) do
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink and tonumber(getIDFromLink(itemLink)) == itemID then
        local _, count = GetContainerItemInfo(bag, slot)
        count = count > 0 and count or 1
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
        count = count > 0 and count or 1
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
              restock_jobs[job_i] = { tab=tab, slot=slot, itemID=itemID, need=want_count-have.count }
              job_i = job_i + 1
            end
          elseif have and have.count > 0 then
            -- Remove wrong item first
            restock_jobs[job_i] = { tab=tab, slot=slot, itemID=have.itemID, need=-have.count, isRemoval=true }
            job_i = job_i + 1
            -- Queue deposit after removal
            restock_jobs[job_i] = { tab=tab, slot=slot, itemID=itemID, need=want_count }
            job_i = job_i + 1
          else
            -- Empty slot, need full amount
            restock_jobs[job_i] = { tab=tab, slot=slot, itemID=itemID, need=want_count }
            job_i = job_i + 1
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
    return
  end

  if job.need > 0 then
    -- Try to find in bags
    local bag, slot, to_deposit = FindInBag(job.itemID, job.need)
    if bag then
      -- item found, switch to the tab we're working on if it's different from current
      if job.tab and GuildBank and GuildBank.currentTab ~= job.tab then
        GuildBankFrameTab_OnClick(job.tab)
      end

      -- Track operation for debugging
      current_operation = {
        type = "deposit",
        itemID = job.itemID,
        amount = to_deposit,
        from = "bag " .. bag .. " slot " .. slot,
        to = "guild bank tab " .. job.tab .. " slot " .. job.slot
      }
      
      last_action_time = GetTime()
      self.wait_on = 1
      self:Deposit(job.tab, job.slot, bag, slot, to_deposit)
      job.need = job.need - to_deposit
      if job.need <= 0 then
        -- Remove job from front of array (shift)
        for i = 1, table.getn(restock_jobs)-1 do
          restock_jobs[i] = restock_jobs[i+1]
        end
        restock_jobs[table.getn(restock_jobs)] = nil
      end
      return
    end
    -- Not in bags? Try to move from bank
    -- local bbag, bslot, can_move = FindStackInBank(job.itemID, job.need)
    local bbag, bslot, can_move = FindStackInBank(job.itemID, job.need)
    if bbag then
      local eb, es = FindEmptyBagSlot()
      if eb then
        -- Track operation for debugging
        current_operation = {
          type = "bank_to_bag_split",
          itemID = job.itemID,
          amount = can_move,
          from = "bank bag " .. bbag .. " slot " .. bslot,
          to = "inventory bag " .. eb .. " slot " .. es
        }
        
        last_action_time = GetTime()
        self.wait_on = 2
        SplitContainerItem(bbag, bslot, can_move)
        PickupContainerItem(eb, es)
        return
      else
        gb_print("No free bag space for item "..job.itemID)
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
    self.wait_on = 1
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
