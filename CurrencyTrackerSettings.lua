-- CurrencyTrackerSettings.lua
-- ============================================================
-- Interface Options panel (Escape > Options > AddOns) and
-- the /ctdebug slash command.
-- ============================================================

local _, CT = ...

local Settings = {}
CT.Settings = Settings

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
-- Interface Options panel
---------------------------------------------------------------------------

function Settings.Init()
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
    if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
        local category = _G.Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        if category then
            category.ID = panel.name
            _G.Settings.RegisterAddOnCategory(category)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    else
        CT.DebugAlways("Warning: Could not register options panel - no supported API found")
    end
end
