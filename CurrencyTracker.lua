-- CurrencyTracker.lua
-- ============================================================
-- Main entry point: event handling and initialisation glue
-- that wires Panel, Tab, and Settings together.
-- ============================================================

local ADDON_NAME, CT = ...

CurrencyTrackerDB = CurrencyTrackerDB or {}
CurrencyTrackerCharDB = CurrencyTrackerCharDB or {}

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

eventFrame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        CT.EnsureDB()
        CT.EnsureCharDB()
        CT.EnsureCountsDB()
        CT.Panel.Init()
        CT.Tab.Init()
        CT.Settings.Init()
        CT.DebugAlways("CurrencyTracker loaded. v" .. CT.VERSION .. " (debug " .. (CurrencyTrackerDB.debugEnabled and "ON" or "OFF") .. ", /ctdebug to toggle)")
    elseif event == "PLAYER_LOGIN" then
        CT.EnsureDB()
        CT.EnsureCharDB()
        CT.EnsureCountsDB()
        CT.Tab.Init()
        CT.Debug("PLAYER_LOGIN complete")
    elseif event == "BANKFRAME_OPENED" then
        CT.Debug("Event: BANKFRAME_OPENED")
        CT.bankDataKnownThisSession = true
        CT.Panel.BuildFlatList()
        if CT.Panel.IsShown() then
            CT.Panel.UpdateScroll()
        end
        CT.AutoDepositBadgesToBank()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        CT.Debug("Event: GET_ITEM_INFO_RECEIVED")
        CT.Panel.BuildFlatList()
        if CT.Panel.IsShown() then
            CT.Panel.UpdateScroll()
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED" then
        CT.Debug("Event: " .. event)
        CT.Panel.BuildFlatList()
        if CT.Panel.IsShown() then
            CT.Panel.UpdateScroll()
        end
    end
end)
