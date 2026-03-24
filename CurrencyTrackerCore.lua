-- CurrencyTrackerCore.lua
-- ============================================================
-- Shared utilities, database helpers, currency grouping,
-- item-count tracking, and auto-deposit logic.
-- ============================================================

local _, CT = ...

CT.VERSION = "1.0.1"

-- Shared state
CT.bankDataKnownThisSession = false
CT.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"

---------------------------------------------------------------------------
-- Debug helpers
---------------------------------------------------------------------------

function CT.Debug(msg)
    if not CurrencyTrackerDB or not CurrencyTrackerDB.debugEnabled then
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CurrencyTracker]|r " .. msg)
end

function CT.DebugAlways(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CurrencyTracker]|r " .. msg)
end

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------

function CT.WipeTable(t)
    local wipeFunc = wipe or table.wipe
    if type(wipeFunc) == "function" then
        wipeFunc(t)
        return
    end

    for k in pairs(t) do
        t[k] = nil
    end
end

function CT.CreateFrameSafe(frameType, frameName, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, frameName, parent, template)
    if ok then
        return frame
    end

    return nil
end

---------------------------------------------------------------------------
-- Database initialisation
---------------------------------------------------------------------------

function CT.EnsureDB()
    if type(CurrencyTrackerDB) ~= "table" then
        CurrencyTrackerDB = {}
    end
    if CurrencyTrackerDB.debugEnabled == nil then
        CurrencyTrackerDB.debugEnabled = false
    end
end

function CT.EnsureCharDB()
    if type(CurrencyTrackerCharDB) ~= "table" then
        CurrencyTrackerCharDB = {}
    end

    if type(CurrencyTrackerCharDB.collapsed) ~= "table" then
        CurrencyTrackerCharDB.collapsed = {}
    end

    if CurrencyTrackerCharDB.autoDeposit == nil then
        CurrencyTrackerCharDB.autoDeposit = false
    end
end

function CT.EnsureCountsDB()
    if type(CurrencyTrackerCharDB) ~= "table" then
        CurrencyTrackerCharDB = {}
    end

    if type(CurrencyTrackerCharDB.counts) ~= "table" then
        CurrencyTrackerCharDB.counts = {}
    end
end

---------------------------------------------------------------------------
-- Build grouped CURRENCIES from flat CT.Items
---------------------------------------------------------------------------

CT.CURRENCIES = {}
do
    local categoryMap = {}
    local categoryOrder = {}
    for _, item in ipairs(CT.Items) do
        if not categoryMap[item.category] then
            categoryMap[item.category] = { header = item.category, items = {} }
            table.insert(categoryOrder, item.category)
        end
        table.insert(categoryMap[item.category].items, {
            id = item.id,
            name = item.name,
            faction = item.faction,
        })
    end
    for _, cat in ipairs(categoryOrder) do
        table.insert(CT.CURRENCIES, categoryMap[cat])
    end
end

---------------------------------------------------------------------------
-- Item count tracking
---------------------------------------------------------------------------

local function SaveItemCounts(itemID, bagCount, bankCount)
    CT.EnsureCountsDB()

    CurrencyTrackerCharDB.counts[itemID] = {
        bag = bagCount,
        bank = bankCount,
        total = bagCount + bankCount,
        updatedAt = time(),
    }

    return CurrencyTrackerCharDB.counts[itemID]
end

local function GetStoredCounts(itemID)
    CT.EnsureCountsDB()
    local stored = CurrencyTrackerCharDB.counts[itemID]
    if not stored then
        return 0, 0
    end

    return stored.bag or 0, stored.bank or 0
end

function CT.CollectItemCounts(itemID)
    local bagCount = GetItemCount(itemID, false) or 0
    local totalWithBank = GetItemCount(itemID, true) or bagCount
    local bankFromAPI = totalWithBank - bagCount

    if bankFromAPI < 0 then
        bankFromAPI = 0
    end

    local _, storedBank = GetStoredCounts(itemID)
    local bankCount = bankFromAPI

    if not CT.bankDataKnownThisSession and bankFromAPI == 0 and storedBank > 0 then
        bankCount = storedBank
        CT.Debug("  Using stored bank count for id=" .. itemID .. ": " .. storedBank)
    end

    local itemName = GetItemInfo(itemID) or ("ID:" .. itemID)
    CT.Debug("  Count: " .. itemName .. " bag=" .. bagCount .. " bank=" .. bankCount .. " total=" .. (bagCount + bankCount))
    return SaveItemCounts(itemID, bagCount, bankCount)
end

function CT.GetAllTrackedItemIDs()
    local ids = {}
    local playerFaction = UnitFactionGroup("player")
    for _, category in ipairs(CT.CURRENCIES) do
        for _, item in ipairs(category.items) do
            if not item.faction or item.faction == playerFaction then
                ids[item.id] = true
            end
        end
    end
    return ids
end

---------------------------------------------------------------------------
-- Auto-deposit to bank
---------------------------------------------------------------------------

function CT.AutoDepositBadgesToBank()
    CT.Debug("Bank opened - auto-deposit enabled: " .. tostring(CurrencyTrackerCharDB.autoDeposit))
    if not CurrencyTrackerCharDB.autoDeposit then
        CT.Debug("Auto-deposit is DISABLED, skipping.")
        return
    end

    local trackedIDs = CT.GetAllTrackedItemIDs()
    local depositQueue = {}

    local trackedCount = 0
    for id in pairs(trackedIDs) do
        trackedCount = trackedCount + 1
        local name = GetItemInfo(id) or ("Unknown")
        CT.Debug("  Tracking: " .. name .. " (id=" .. id .. ")")
    end
    CT.Debug("Scanning bags for " .. trackedCount .. " tracked item IDs...")

    -- Resolve container API (TBC Anniversary may use C_Container)
    local getNumSlots = GetContainerNumSlots
    local getItemID = GetContainerItemID
    local getItemInfo_container = GetContainerItemInfo
    local useItem = UseContainerItem

    if C_Container then
        getNumSlots = C_Container.GetContainerNumSlots or getNumSlots
        getItemID = C_Container.GetContainerItemID or getItemID
        getItemInfo_container = C_Container.GetContainerItemInfo or getItemInfo_container
        useItem = C_Container.UseContainerItem or useItem
        CT.Debug("Using C_Container API")
    else
        CT.Debug("Using legacy container API")
    end

    -- Scan all bags and record matches
    local foundIDs = {}
    for bag = 0, 4 do
        local numSlots = getNumSlots(bag)
        local occupied = 0
        for slot = 1, numSlots do
            local itemID = getItemID(bag, slot)
            if itemID then
                occupied = occupied + 1
                if trackedIDs[itemID] then
                    local itemName = GetItemInfo(itemID) or ("ID:" .. itemID)
                    local countVal
                    local info = getItemInfo_container(bag, slot)
                    if type(info) == "table" then
                        countVal = info.stackCount
                    else
                        local _, c = getItemInfo_container(bag, slot)
                        countVal = c
                    end
                    CT.Debug("  FOUND: " .. itemName .. " (id=" .. itemID .. ") x" .. (countVal or "?") .. " in bag " .. bag .. " slot " .. slot)
                    foundIDs[itemID] = true
                    table.insert(depositQueue, { bag = bag, slot = slot, itemID = itemID, itemName = itemName })
                end
            end
        end
        CT.Debug("  Bag " .. bag .. ": " .. numSlots .. " slots, " .. occupied .. " occupied")
    end

    -- Report which tracked badges were NOT found in any bag
    for id in pairs(trackedIDs) do
        if not foundIDs[id] then
            local name = GetItemInfo(id) or ("Unknown")
            CT.Debug("  NOT IN BAGS: " .. name .. " (id=" .. id .. ") - nothing to deposit for this badge")
        end
    end

    if #depositQueue == 0 then
        CT.Debug("No tracked badges found in bags, nothing to deposit.")
        return
    end

    CT.Debug("Queued " .. #depositQueue .. " item stack(s) for deposit.")

    local idx = 0
    local function DepositNext()
        idx = idx + 1
        if idx > #depositQueue then
            CT.Debug("Deposit queue complete.")
            return
        end
        local entry = depositQueue[idx]
        local currentID = getItemID(entry.bag, entry.slot)
        if currentID and trackedIDs[currentID] then
            local name = GetItemInfo(currentID) or ("ID:" .. currentID)
            CT.Debug("  Depositing: " .. name .. " from bag " .. entry.bag .. " slot " .. entry.slot)
            useItem(entry.bag, entry.slot)
        else
            CT.Debug("  Skipped bag " .. entry.bag .. " slot " .. entry.slot .. " (item moved or gone, was " .. (entry.itemName or "?") .. ")")
        end
        C_Timer.After(0.15, DepositNext)
    end

    C_Timer.After(0.3, DepositNext)
end
