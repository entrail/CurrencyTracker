-- CurrencyTrackerTab.lua
-- ============================================================
-- The "Currencies" tab button on CharacterFrame.
-- Integrates with Blizzard's tab system via CHARACTERFRAME_SUBFRAMES
-- for native show/hide behavior and tab highlighting.
-- ============================================================

local _, CT = ...

local Tab = {}
CT.Tab = Tab

local tabButton = nil

---------------------------------------------------------------------------
-- Init (called during ADDON_LOADED and PLAYER_LOGIN)
---------------------------------------------------------------------------

function Tab.Init()
    if tabButton or not CharacterFrame then
        return
    end

    -- Determine new tab index
    local numTabs = (CharacterFrame.numTabs or 4) + 1

    -- Create tab with standard CharacterFrame naming so Blizzard's
    -- tab system recognises it for highlighting and layout.
    local tab = CreateFrame("Button", "CharacterFrameTab" .. numTabs, CharacterFrame, "CharacterFrameTabButtonTemplate")
    tab:SetText("Currencies")
    tab:SetID(numTabs)

    local prevTab = _G["CharacterFrameTab" .. (numTabs - 1)]
    if prevTab then
        tab:SetPoint("LEFT", prevTab, "RIGHT", -16, 0)
    else
        tab:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 60, -2)
    end

    PanelTemplates_SetNumTabs(CharacterFrame, numTabs)

    if type(PanelTemplates_TabResize) == "function" then
        PanelTemplates_TabResize(tab, 0)
    end

    tabButton = tab

    -- Register panel so CharacterFrame_ShowSubFrame hides/shows it
    -- alongside the default sub-frames automatically.
    tinsert(CHARACTERFRAME_SUBFRAMES, "CurrencyTrackerFrame")

    -- Hook the global CharacterFrameTab_OnClick so the template's
    -- built-in OnClick still fires (which calls PanelTemplates_SetTab
    -- for the raised-tab / hidden-border "connected" look).
    -- Using CharacterFrame_ShowSubFrame (not ToggleCharacter) so that
    -- re-clicking the same tab doesn't close the whole character menu.
    local origOnClick = CharacterFrameTab_OnClick
    CharacterFrameTab_OnClick = function(self, button)
        if self:GetID() == numTabs then
            CharacterFrame_ShowSubFrame("CurrencyTrackerFrame")
            PanelTemplates_SetTab(CharacterFrame, numTabs)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        else
            origOnClick(self, button)
        end
    end

    -- Ensure layout is up to date when CharacterFrame is shown
    CharacterFrame:HookScript("OnShow", function()
        Tab.Init()
        CT.Panel.SyncLayout()
        CT.Panel.EnsureBackground()
        CT.Panel.EnsureScrollFrame()
        CT.Panel.UpdateRowLayout()
        CT.Panel.UpdateVersionText()

        if CT.Panel.IsShown() then
            CT.Panel.BuildFlatList()
            CT.Panel.UpdateScroll()
        end
    end)
end
