-- CurrencyTrackerTab.lua
-- ============================================================
-- The "Currencies" tab button on CharacterFrame plus the
-- show / hide orchestration that coordinates the panel with
-- the default character-frame tabs and portrait.
-- ============================================================

local _, CT = ...

local Tab = {}
CT.Tab = Tab

local tabButton = nil
local subFrameHookInstalled = false
local lastSelectedCharacterTabIndex = nil

---------------------------------------------------------------------------
-- CharacterFrame helpers
---------------------------------------------------------------------------

local function DeselectDefaultCharacterTabs()
    for i = 1, 10 do
        local tab = _G["CharacterFrameTab" .. i]
        if not tab then
            break
        end

        PanelTemplates_DeselectTab(tab)
    end
end

local function RestoreDefaultCharacterTabHighlight()
    if not lastSelectedCharacterTabIndex then
        return
    end

    local tab = _G["CharacterFrameTab" .. lastSelectedCharacterTabIndex]
    if tab then
        PanelTemplates_SelectTab(tab)
    end
end

local function HideDefaultCharacterPanels()
    if PaperDollFrame then PaperDollFrame:Hide() end
    if ReputationFrame then ReputationFrame:Hide() end
    if SkillFrame then SkillFrame:Hide() end
    if PVPFrame then PVPFrame:Hide() end
end

local function ShowSelectedCharacterSubFrame()
    local frameName = nil

    if CharacterFrame and type(CHARACTERFRAME_SUBFRAMES) == "table" and type(PanelTemplates_GetSelectedTab) == "function" then
        local selectedTab = PanelTemplates_GetSelectedTab(CharacterFrame) or 1
        frameName = CHARACTERFRAME_SUBFRAMES[selectedTab]
    end

    if not frameName then
        frameName = "PaperDollFrame"
    end

    if not InCombatLockdown() and type(CharacterFrame_ShowSubFrame) == "function" then
        CharacterFrame_ShowSubFrame(frameName)
        return
    end

    local frame = _G[frameName]
    if frame then
        frame:Show()
    end
end

local function GetLastCharacterTab()
    local lastTab = nil
    for i = 1, 10 do
        local tab = _G["CharacterFrameTab" .. i]
        if tab then
            lastTab = tab
        else
            break
        end
    end

    return lastTab
end

---------------------------------------------------------------------------
-- Show / Hide currencies (orchestrates Panel + CharacterFrame state)
---------------------------------------------------------------------------

function Tab.ShowCurrencies()
    CT.Debug("ShowCurrenciesPanel called")
    if not CurrencyTrackerFrame or not CharacterFrame then
        CT.Debug("  Aborted: missing CurrencyTrackerFrame or CharacterFrame")
        return
    end

    if type(PanelTemplates_GetSelectedTab) == "function" then
        lastSelectedCharacterTabIndex = PanelTemplates_GetSelectedTab(CharacterFrame) or lastSelectedCharacterTabIndex or 1
    end

    DeselectDefaultCharacterTabs()
    HideDefaultCharacterPanels()

    CT.Panel.Show()

    if tabButton then
        PanelTemplates_SelectTab(tabButton)
    end
end

function Tab.HideCurrencies(restoreDefaultPanel)
    CT.Debug("HideCurrenciesPanel called (restore=" .. tostring(restoreDefaultPanel) .. ")")
    CT.Panel.Hide()

    if tabButton then
        PanelTemplates_DeselectTab(tabButton)
    end

    if restoreDefaultPanel and CharacterFrame and CharacterFrame:IsShown() then
        ShowSelectedCharacterSubFrame()
        RestoreDefaultCharacterTabHighlight()
    end
end

---------------------------------------------------------------------------
-- Init (called once during ADDON_LOADED)
---------------------------------------------------------------------------

function Tab.Init()
    if tabButton or not CharacterFrame then
        return
    end

    local tab = CreateFrame("Button", "CurrencyTrackerTab", CharacterFrame, "CharacterFrameTabButtonTemplate")
    tab:SetText("Currencies")

    local anchorTab = GetLastCharacterTab()
    if anchorTab then
        tab:SetPoint("LEFT", anchorTab, "RIGHT", -15, 0)
    else
        tab:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 60, -2)
    end

    if type(PanelTemplates_TabResize) == "function" then
        PanelTemplates_TabResize(tab, 0)
    end

    tab:SetScript("OnClick", function()
        if CT.Panel.IsShown() then
            Tab.HideCurrencies(true)
        else
            Tab.ShowCurrencies()
        end
    end)

    PanelTemplates_DeselectTab(tab)
    tabButton = tab

    if type(hooksecurefunc) == "function" and type(CharacterFrame_ShowSubFrame) == "function" and not subFrameHookInstalled then
        hooksecurefunc("CharacterFrame_ShowSubFrame", function(frameName)
            if frameName and frameName ~= "CurrencyTrackerFrame" then
                if type(PanelTemplates_GetSelectedTab) == "function" then
                    lastSelectedCharacterTabIndex = PanelTemplates_GetSelectedTab(CharacterFrame) or lastSelectedCharacterTabIndex
                end
                Tab.HideCurrencies(false)
            end
        end)
        subFrameHookInstalled = true
    end

    -- CharacterFrame hooks
    CharacterFrame:HookScript("OnHide", function()
        Tab.HideCurrencies(false)
    end)

    CharacterFrame:HookScript("OnShow", function()
        Tab.Init()
        CT.Panel.SyncLayout()
        CT.Panel.EnsureBackground()
        CT.Panel.EnsureScrollFrame()
        CT.Panel.UpdateRowLayout()
        CT.Panel.UpdateVersionText()

        if type(PanelTemplates_GetSelectedTab) == "function" and not CT.Panel.IsShown() then
            lastSelectedCharacterTabIndex = PanelTemplates_GetSelectedTab(CharacterFrame) or lastSelectedCharacterTabIndex
        end

        if CT.Panel.IsShown() then
            CT.Panel.BuildFlatList()
            CT.Panel.UpdateScroll()
        end
    end)
end
