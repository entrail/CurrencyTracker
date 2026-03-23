-- CurrencyTracker.lua
-- ============================================================
-- Main entry point: event handling, options panel, slash
-- commands, and initialisation glue that wires Panel + Tab.
-- ============================================================

local ADDON_NAME, CT = ...

CurrencyTrackerDB = CurrencyTrackerDB or {}
CurrencyTrackerCharDB = CurrencyTrackerCharDB or {}

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_CURRENCYTRACKERDEBUG1 = "/ctdebug"
SlashCmdList["CURRENCYTRACKERDEBUG"] = function()
    CT.EnsureDB()
    CurrencyTrackerDB.debugEnabled = not CurrencyTrackerDB.debugEnabled
    if CurrencyTrackerDB.debugEnabled then
        CT.DebugAlways("Debug mode |cff00ff00ENABLED|r. Type /ctdebug to disable.")
    else
        CT.DebugAlways("Debug mode |cffff0000DISABLED|r. Type /ctdebug to enable.")
    end
end

---------------------------------------------------------------------------
-- Interface Options panel (Escape > Options > AddOns)
---------------------------------------------------------------------------

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "CurrencyTrackerOptionsPanel", UIParent)
    panel.name = "CurrencyTracker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("CurrencyTracker v" .. CT.VERSION)

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Configure addon settings below.")

    local cbTemplate = "UICheckButtonTemplate"

    -- Debug checkbox
    local debugCB = CreateFrame("CheckButton", "CurrencyTrackerOptDebugCB", panel, cbTemplate)
    debugCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    debugCB:SetSize(26, 26)

    local debugLabel = debugCB:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    debugLabel:SetPoint("LEFT", debugCB, "RIGHT", 4, 1)
    debugLabel:SetText("Enable debug logging in chat")

    debugCB:SetChecked(CurrencyTrackerDB.debugEnabled == true)
    debugCB:SetScript("OnClick", function(self)
        CurrencyTrackerDB.debugEnabled = self:GetChecked() == true
        if CurrencyTrackerDB.debugEnabled then
            CT.DebugAlways("Debug mode |cff00ff00ENABLED|r")
        else
            CT.DebugAlways("Debug mode |cffff0000DISABLED|r")
        end
    end)

    local debugDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    debugDesc:SetPoint("TOPLEFT", debugCB, "BOTTOMLEFT", 26, -2)
    debugDesc:SetText("Prints detailed info about events, bag scans, and deposits to chat. Also available via /ctdebug")
    debugDesc:SetTextColor(0.6, 0.6, 0.6)
    debugDesc:SetWidth(380)
    debugDesc:SetJustifyH("LEFT")

    -- Auto-deposit checkbox
    local depositCB = CreateFrame("CheckButton", "CurrencyTrackerOptDepositCB", panel, cbTemplate)
    depositCB:SetPoint("TOPLEFT", debugDesc, "BOTTOMLEFT", -26, -16)
    depositCB:SetSize(26, 26)

    local depositLabel = depositCB:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    depositLabel:SetPoint("LEFT", depositCB, "RIGHT", 4, 1)
    depositLabel:SetText("Auto-deposit badges to bank on bank open")

    depositCB:SetChecked(CurrencyTrackerCharDB.autoDeposit == true)
    depositCB:SetScript("OnClick", function(self)
        CurrencyTrackerCharDB.autoDeposit = self:GetChecked() == true
        CT.Panel.SyncAutoDepositCheckbox()
    end)

    local depositDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    depositDesc:SetPoint("TOPLEFT", depositCB, "BOTTOMLEFT", 26, -2)
    depositDesc:SetText("Automatically moves all tracked currency items from bags to bank when the bank is opened. (Per-character setting)")
    depositDesc:SetTextColor(0.6, 0.6, 0.6)
    depositDesc:SetWidth(380)
    depositDesc:SetJustifyH("LEFT")

    -- Sync state when panel is shown
    panel:SetScript("OnShow", function()
        debugCB:SetChecked(CurrencyTrackerDB.debugEnabled == true)
        depositCB:SetChecked(CurrencyTrackerCharDB.autoDeposit == true)
    end)

    -- Register with whichever options API exists
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        if category then
            category.ID = panel.name
            Settings.RegisterAddOnCategory(category)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    else
        CT.DebugAlways("Warning: Could not register options panel - no supported API found")
    end
end

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
        CreateOptionsPanel()
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
