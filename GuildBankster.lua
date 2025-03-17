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

local function gb_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff14a868GuildBankster:|r "..msg)
end

function getIDFromLink(link)
  local _,_,id = string.find(link,"item:(%d+)")
  return id
end

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
  GuildBank:SpoofGossip()
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
local gbankQueueFrame = CreateFrame("Frame")
gbankQueueFrame.wait_on = 0
gbankQueueFrame.actions = {
  print = "print",
  deposit = "deposit",
  withdrawSome = "withdrawSome",
  withdrawAll = "withdrawAll",
}

gbankQueueFrame:RegisterEvent("BAG_UPDATE")
gbankQueueFrame:SetScript("OnEvent", function ()
  gbankQueueFrame:ProgressQueue()
end)

function gbankQueueFrame:ProgressQueue()
  if not gbank_queue[1] then return end
  if gbankQueueFrame.wait_on > 0 then
    gbankQueueFrame.wait_on = gbankQueueFrame.wait_on - 1
    return
  end

  local action = table.remove(depositQueue, 1)
  if action.type == action.type == gbankQueueFrame.actions[print] then
    gb_print(action.args[1])
  end
  if action.type == gbankQueueFrame.actions[deposit] then
    GuildBankster:Deposit(unpack(action.args))
    gbankQueueFrame.wait_on = 1 -- 1 update
  end
  if action.type == gbankQueueFrame.actions[withdrawSome] then
    GuildBankster:Withdraw(unpack(action.args))
    gbankQueueFrame.wait_on = 2 -- 2 update
  end
  if action.type == gbankQueueFrame.actions[withdrawAll] then
    GuildBankster:Withdraw(unpack(action.args))
    gbankQueueFrame.wait_on = 1 -- 1 update
  end
end


depositFrame.lastTime = 0
depositFrame:SetScript("OnUpdate", function()
  this.lastTime = this.lastTime + arg1
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

-- Searches the simulated inventory for the given itemID and "consumes" up to 'amount'
-- Returns bag, slot, and the number of items that can be deposited from that slot.
local function FindAndConsume(inventory, itemID, amount)
  for bag = 0, NUM_BAG_SLOTS do
    local numSlots = GetContainerNumSlots(bag)
    for slot = 1, numSlots do
      local itemLink = GetContainerItemLink(bag, slot)
      if itemLink then
        local foundID = getIDFromLink(itemLink)
        if tonumber(foundID) == tonumber(itemID) and inventory[bag][slot] > 0 then
          local available = inventory[bag][slot]
          local toUse = math.min(available, amount)
          inventory[bag][slot] = available - toUse  -- "Consume" these items in our simulation.
          return bag, slot, toUse
        end
      end
    end
  end
  return nil, nil, 0
end

--------------------------------------------------
-- RESTOCK FUNCTION: QUEUE DEPOSIT ACTIONS
--------------------------------------------------
local function RestockBank()
  local inventoryState = BuildInventoryState()  -- snapshot of your inventory
  local missingItems = {}  -- table to record materials we couldn't fully restock

  table.insert(depositQueue, function()
    gb_print("Beginning Guildbank restock...")
  end)
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
                table.insert(depositQueue, function(ix)
                  -- partial removal requires use of specific bag slots
                  for bag = 0, NUM_BAG_SLOTS do
                    local numSlots = GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                      local itemLink = GetContainerItemLink(bag, slot)
                      if not itemLink then
                        GuildBankster:Withdraw(t, s, bag, slot, difference)
                        print("withdraw from "..t.." slot "..s.." "..difference)
                        return
                      end
                    end
                  end
                  gb_print("Tried to remove extra " .. GetItemInfo("item:"..item) .. " but had no empty bag space.")
                end)
                missing = 0
              end
            elseif current.count > 0 then
              -- slot is occupied with wrong item, remove it
              local t = tab
              local s = slot
              local c = current.count
              table.insert(depositQueue, function(ix)
                GuildBankster:Withdraw(t, s, 0, 0, c)
                print("withdrawall from "..t.." slot "..s.." "..c)
              end)
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
                table.insert(depositQueue, function(ix)
                  -- print(format("tab %i, slot %i, bag %i, inv_slot %i, depositing %i", t, s, b, i, m))
                  -- gb_print(string.rep(".", math.min(ix,20)))
                  GuildBankster:Deposit(t, s, b, i, m)
                end)
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
  table.insert(depositQueue, function()
    gb_print("Guildbank restock finished.")
  end)
  if next(missingItems) then
    table.insert(depositQueue, function()
      gb_print("The following could not be restocked due to insufficient inventory:")
      for itemID, count in pairs(missingItems) do
        gb_print(string.format("%d : %s", count, GetItemInfo("item:"..itemID)))
      end
    end)
  end
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
  RestockBank()
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
