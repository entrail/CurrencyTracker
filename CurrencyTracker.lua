local ADDON_NAME = ...
local ADDON_VERSION = "1.2.0"

CurrencyTrackerDB = CurrencyTrackerDB or {}
CurrencyTrackerCharDB = CurrencyTrackerCharDB or {}

local currenciesTab = nil
local subFrameHookInstalled = false
local lastSelectedCharacterTabIndex = nil
local rows = {}
local MAX_ROWS = 20
local NUM_ROWS = 10
local ROW_HEIGHT = 21
local HEADER_HEIGHT = 21
local ROW_SPACING = 1
local bankDataKnownThisSession = false
local autoDepositCheckbox = nil
local depositQueue = {}
local eventFrame

local function Debug(msg)
    if not CurrencyTrackerDB.debugEnabled then
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CurrencyTracker]|r " .. msg)
end

local function DebugAlways(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CurrencyTracker]|r " .. msg)
end

local function UpdateHeaderVersionText()
    if CurrencyTrackerFrameTitle then
        CurrencyTrackerFrameTitle:SetText("Currencies (" .. ADDON_VERSION .. ")")
    end
end

local function CreateFrameSafe(frameType, frameName, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, frameName, parent, template)
    if ok then
        return frame
    end

    return nil
end

local function WipeTable(t)
    local wipeFunc = wipe or table.wipe
    if type(wipeFunc) == "function" then
        wipeFunc(t)
        return
    end

    for k in pairs(t) do
        t[k] = nil
    end
end

local CURRENCIES = {
    {
        header = "Battleground",
        items = {
            { id = 20558, name = "Warsong Gulch Mark of Honor" },
            { id = 20559, name = "Arathi Basin Mark of Honor" },
            { id = 20560, name = "Alterac Valley Mark of Honor" },
            { id = 29024, name = "Eye of the Storm Mark of Honor" },
        },
    },
    {
        header = "Dungeon and Raids",
        items = {
            { id = 29434, name = "Badge of Justice" },
        },
    },
    {
        header = "Open World PvP",
        items = {
            { id = 26045, name = "Halaa Battle Token" },
            { id = 26044, name = "Halaa Research Token" },
            { id = 24581, name = "Mark of Thrallmar", faction = "Horde" },
            { id = 24579, name = "Mark of Honor Hold", faction = "Alliance" },
            { id = 28558, name = "Spirit Shard" },
        },
    },
}

local flatList = {}
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"


local function EnsureCountsDB()
    if type(CurrencyTrackerCharDB) ~= "table" then
        CurrencyTrackerCharDB = {}
    end

    if type(CurrencyTrackerCharDB.counts) ~= "table" then
        CurrencyTrackerCharDB.counts = {}
    end
end

local function SaveItemCounts(itemID, bagCount, bankCount)
    EnsureCountsDB()

    CurrencyTrackerCharDB.counts[itemID] = {
        bag = bagCount,
        bank = bankCount,
        total = bagCount + bankCount,
        updatedAt = time(),
    }

    return CurrencyTrackerCharDB.counts[itemID]
end

local function GetStoredCounts(itemID)
    EnsureCountsDB()
    local stored = CurrencyTrackerCharDB.counts[itemID]
    if not stored then
        return 0, 0
    end

    return stored.bag or 0, stored.bank or 0
end

local function CollectItemCounts(itemID)
    local bagCount = GetItemCount(itemID, false) or 0
    local totalWithBank = GetItemCount(itemID, true) or bagCount
    local bankFromAPI = totalWithBank - bagCount

    if bankFromAPI < 0 then
        bankFromAPI = 0
    end

    local _, storedBank = GetStoredCounts(itemID)
    local bankCount = bankFromAPI

    if not bankDataKnownThisSession and bankFromAPI == 0 and storedBank > 0 then
        bankCount = storedBank
        Debug("  Using stored bank count for id=" .. itemID .. ": " .. storedBank)
    end

    local itemName = GetItemInfo(itemID) or ("ID:" .. itemID)
    Debug("  Count: " .. itemName .. " bag=" .. bagCount .. " bank=" .. bankCount .. " total=" .. (bagCount + bankCount))
    return SaveItemCounts(itemID, bagCount, bankCount)
end

local function ShowItemTooltip(row, entry)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

    if entry.id then
        GameTooltip:SetHyperlink("item:" .. entry.id)
    else
        GameTooltip:SetText(entry.text or "Unknown Currency")
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("In Bags:", tostring(entry.bag or 0), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("In Bank:", tostring(entry.bank or 0), 1, 1, 1, 1, 1, 1)

    if not bankDataKnownThisSession then
        GameTooltip:AddLine("Bank data may be from your last bank visit.", 0.8, 0.8, 0.8, true)
    end

    GameTooltip:Show()
end
local function EnsureDB()
    if type(CurrencyTrackerDB) ~= "table" then
        CurrencyTrackerDB = {}
    end
    if CurrencyTrackerDB.debugEnabled == nil then
        CurrencyTrackerDB.debugEnabled = false
    end
end

local function EnsureCharDB()
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

local function IsCollapsed(header)
    return CurrencyTrackerCharDB and CurrencyTrackerCharDB.collapsed and CurrencyTrackerCharDB.collapsed[header] == true
end

local function GetAllTrackedItemIDs()
    local ids = {}
    local playerFaction = UnitFactionGroup("player")
    for _, category in ipairs(CURRENCIES) do
        for _, item in ipairs(category.items) do
            if not item.faction or item.faction == playerFaction then
                ids[item.id] = true
            end
        end
    end
    return ids
end

local function AutoDepositBadgesToBank()
    Debug("Bank opened - auto-deposit enabled: " .. tostring(CurrencyTrackerCharDB.autoDeposit))
    if not CurrencyTrackerCharDB.autoDeposit then
        Debug("Auto-deposit is DISABLED, skipping.")
        return
    end

    local trackedIDs = GetAllTrackedItemIDs()
    WipeTable(depositQueue)

    local trackedCount = 0
    for id in pairs(trackedIDs) do
        trackedCount = trackedCount + 1
        local name = GetItemInfo(id) or ("Unknown")
        Debug("  Tracking: " .. name .. " (id=" .. id .. ")")
    end
    Debug("Scanning bags for " .. trackedCount .. " tracked item IDs...")

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
        Debug("Using C_Container API")
    else
        Debug("Using legacy container API")
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
                    Debug("  FOUND: " .. itemName .. " (id=" .. itemID .. ") x" .. (countVal or "?") .. " in bag " .. bag .. " slot " .. slot)
                    foundIDs[itemID] = true
                    table.insert(depositQueue, { bag = bag, slot = slot, itemID = itemID, itemName = itemName, useFunc = useItem })
                end
            end
        end
        Debug("  Bag " .. bag .. ": " .. numSlots .. " slots, " .. occupied .. " occupied")
    end

    -- Report which tracked badges were NOT found in any bag
    for id in pairs(trackedIDs) do
        if not foundIDs[id] then
            local name = GetItemInfo(id) or ("Unknown")
            Debug("  NOT IN BAGS: " .. name .. " (id=" .. id .. ") - nothing to deposit for this badge")
        end
    end

    if #depositQueue == 0 then
        Debug("No tracked badges found in bags, nothing to deposit.")
        return
    end

    Debug("Queued " .. #depositQueue .. " item stack(s) for deposit.")

    local idx = 0
    local depositUseFunc = useItem
    local depositGetID = getItemID
    local function DepositNext()
        idx = idx + 1
        if idx > #depositQueue then
            Debug("Deposit queue complete.")
            return
        end
        local entry = depositQueue[idx]
        local currentID = depositGetID(entry.bag, entry.slot)
        if currentID and trackedIDs[currentID] then
            local name = GetItemInfo(currentID) or ("ID:" .. currentID)
            Debug("  Depositing: " .. name .. " from bag " .. entry.bag .. " slot " .. entry.slot)
            depositUseFunc(entry.bag, entry.slot)
        else
            Debug("  Skipped bag " .. entry.bag .. " slot " .. entry.slot .. " (item moved or gone, was " .. (entry.itemName or "?") .. ")")
        end
        C_Timer.After(0.15, DepositNext)
    end

    C_Timer.After(0.3, DepositNext)
end

local function BuildFlatList()
    WipeTable(flatList)

    local playerFaction = UnitFactionGroup("player")

    for _, category in ipairs(CURRENCIES) do
        table.insert(flatList, {
            isHeader = true,
            header = category.header,
            text = category.header,
        })

        if not IsCollapsed(category.header) then
            for _, item in ipairs(category.items) do
                if not item.faction or item.faction == playerFaction then
                    local counts = CollectItemCounts(item.id)
                    local icon = GetItemIcon(item.id)
                    local localizedName = GetItemInfo(item.id) or item.name

                    table.insert(flatList, {
                        isHeader = false,
                        id = item.id,
                        text = localizedName,
                        count = counts.total or 0,
                        bag = counts.bag or 0,
                        bank = counts.bank or 0,
                        icon = icon or ICON_FALLBACK,
                    })
                end
            end
        end
    end
end

local function ToggleHeader(header)
    if not header then
        return
    end

    CurrencyTrackerCharDB.collapsed[header] = not IsCollapsed(header)
    BuildFlatList()
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, CurrencyTrackerFrame)
    row:SetWidth(260)
    row:SetHeight(ROW_HEIGHT)

    if i == 1 then
        row:SetPoint("TOPLEFT", CurrencyTrackerScrollFrame, "TOPLEFT", 2, -2)
    else
        row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -ROW_SPACING)
    end

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.headerBG = row:CreateTexture(nil, "BACKGROUND")
    row.headerBG:SetAllPoints(row)
    row.headerBG:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.headerBG:SetVertexColor(0.21, 0.17, 0.08, 0.95)
    row.headerBG:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("RIGHT", -8, 0)
    row.icon:SetTexture(ICON_FALLBACK)
    row.icon:Hide()

    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.count:SetPoint("RIGHT", -28, 0)
    row.count:SetJustifyH("RIGHT")

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
        local entry = self.entry
        if entry and entry.isHeader then
            ToggleHeader(entry.header)
            CurrencyTracker_UpdateScroll()
        end
    end)

    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry or entry.isHeader then
            return
        end

        ShowItemTooltip(self, entry)
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function UpdateRowLayout()
    if not CurrencyTrackerScrollFrame then
        return
    end

    local rowPitch = ROW_HEIGHT + ROW_SPACING
    local height = CurrencyTrackerScrollFrame:GetHeight() or 0
    if height <= 0 then
        height = 200
    end
    NUM_ROWS = math.max(1, math.floor((height + ROW_SPACING) / rowPitch))
    NUM_ROWS = math.min(NUM_ROWS, MAX_ROWS)

    local scrollWidth = CurrencyTrackerScrollFrame:GetWidth() or 280
    if scrollWidth <= 0 then
        scrollWidth = 280
    end

    local rowWidth = math.max(120, scrollWidth - 24)
    for i = 1, #rows do
        local row = rows[i]
        row:SetWidth(rowWidth)
    end
end

function CurrencyTracker_UpdateScroll()
    local offset = 0
    if CurrencyTrackerScrollFrame and type(FauxScrollFrame_GetOffset) == "function" then
        offset = FauxScrollFrame_GetOffset(CurrencyTrackerScrollFrame) or 0
    end
    local total = #flatList

    for i = 1, MAX_ROWS do
        local row = rows[i]
        local index = i + offset

        if i <= NUM_ROWS and index <= total then
            local entry = flatList[index]
            row.entry = entry

            if entry.isHeader then
                local collapsed = IsCollapsed(entry.header)
                local prefix = collapsed and "+ " or "- "

                row:SetHeight(HEADER_HEIGHT)
                row.headerBG:Show()
                row.icon:Hide()
                row.text:SetFontObject("GameFontNormal")
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetText("|cffffff00" .. prefix .. entry.text .. "|r")
                row.count:SetTextColor(1, 1, 1)
                row.count:SetText("")
            else
                row:SetHeight(ROW_HEIGHT)
                row.headerBG:Hide()
                row.icon:Show()
                row.icon:SetTexture(entry.icon or ICON_FALLBACK)
                row.text:SetFontObject("GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetText(entry.text)

                if (entry.count or 0) == 0 then
                    row.count:SetTextColor(0.65, 0.65, 0.65)
                else
                    row.count:SetTextColor(1, 1, 1)
                end

                row.count:SetText(tostring(entry.count or 0))
            end

            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    if CurrencyTrackerScrollFrame and type(FauxScrollFrame_Update) == "function" then
        FauxScrollFrame_Update(CurrencyTrackerScrollFrame, total, NUM_ROWS, ROW_HEIGHT + ROW_SPACING)
    end
end

local function EnsureFrameBackground()
    if not CurrencyTrackerFrame then
        return
    end

    if CurrencyTrackerFrame.CurrencyTrackerBG then
        return
    end

    local bg = CurrencyTrackerFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetPoint("TOPLEFT", CurrencyTrackerFrame, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", CurrencyTrackerFrame, "BOTTOMRIGHT", 0, 0)
    bg:SetVertexColor(0.02, 0.02, 0.02, 0.62)
    CurrencyTrackerFrame.CurrencyTrackerBG = bg
end

local function EnsureInsetPanel()
    if not CurrencyTrackerFrame then
        return
    end

    if CurrencyTrackerFrame.ContentInset then
        return
    end

    local inset = CreateFrameSafe("Frame", nil, CurrencyTrackerFrame, "InsetFrameTemplate3")
    if not inset then
        inset = CreateFrameSafe("Frame", nil, CurrencyTrackerFrame, "InsetFrameTemplate")
    end
    if not inset then
        inset = CreateFrame("Frame", nil, CurrencyTrackerFrame)
    end

    inset:SetPoint("TOPLEFT", CurrencyTrackerFrame, "TOPLEFT", 10, -62)
    inset:SetPoint("BOTTOMRIGHT", CurrencyTrackerFrame, "BOTTOMRIGHT", -28, 36)
    inset:SetFrameLevel(CurrencyTrackerFrame:GetFrameLevel() + 1)

    if not inset.SetBackdrop then
        local borderColorR, borderColorG, borderColorB, borderAlpha = 0.75, 0.66, 0.40, 0.9
        local bgColorR, bgColorG, bgColorB, bgAlpha = 0.04, 0.04, 0.04, 0.82

        local fill = inset:CreateTexture(nil, "BACKGROUND")
        fill:SetTexture("Interface\\Buttons\\WHITE8x8")
        fill:SetAllPoints(inset)
        fill:SetVertexColor(bgColorR, bgColorG, bgColorB, bgAlpha)

        local top = inset:CreateTexture(nil, "BORDER")
        top:SetTexture("Interface\\Buttons\\WHITE8x8")
        top:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", inset, "TOPRIGHT", 0, 0)
        top:SetHeight(1)
        top:SetVertexColor(borderColorR, borderColorG, borderColorB, borderAlpha)

        local bottom = inset:CreateTexture(nil, "BORDER")
        bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        bottom:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(1)
        bottom:SetVertexColor(borderColorR, borderColorG, borderColorB, borderAlpha)

        local left = inset:CreateTexture(nil, "BORDER")
        left:SetTexture("Interface\\Buttons\\WHITE8x8")
        left:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 0, 0)
        left:SetWidth(1)
        left:SetVertexColor(borderColorR, borderColorG, borderColorB, borderAlpha)

        local right = inset:CreateTexture(nil, "BORDER")
        right:SetTexture("Interface\\Buttons\\WHITE8x8")
        right:SetPoint("TOPRIGHT", inset, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(1)
        right:SetVertexColor(borderColorR, borderColorG, borderColorB, borderAlpha)
    end

    CurrencyTrackerFrame.ContentInset = inset
end

local function EnsureScrollFrame()
    EnsureInsetPanel()

    local parent = CurrencyTrackerFrame.ContentInset or CurrencyTrackerFrame

    if not parent then
        return
    end

    if not CurrencyTrackerScrollFrame then
        local sf = CreateFrame("ScrollFrame", "CurrencyTrackerScrollFrame", parent, "FauxScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
        sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 6)
    else
        CurrencyTrackerScrollFrame:ClearAllPoints()
        CurrencyTrackerScrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
        CurrencyTrackerScrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 6)
    end
end

local function SyncFrameToCharacterLayout()
    if not CurrencyTrackerFrame then
        return
    end

    if ReputationFrame then
        CurrencyTrackerFrame:ClearAllPoints()
        CurrencyTrackerFrame:SetAllPoints(ReputationFrame)
    end
end

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

local function ShowCurrenciesPanel()
    Debug("ShowCurrenciesPanel called")
    if not CurrencyTrackerFrame or not CharacterFrame then
        Debug("  Aborted: missing CurrencyTrackerFrame or CharacterFrame")
        return
    end

    SyncFrameToCharacterLayout()

    if type(PanelTemplates_GetSelectedTab) == "function" then
        lastSelectedCharacterTabIndex = PanelTemplates_GetSelectedTab(CharacterFrame) or lastSelectedCharacterTabIndex or 1
    end

    DeselectDefaultCharacterTabs()
    HideDefaultCharacterPanels()

    EnsureInsetPanel()
    EnsureScrollFrame()

    for i = 1, MAX_ROWS do
        if not rows[i] then
            rows[i] = CreateRow(i)
        end
    end

    UpdateRowLayout()
    CurrencyTrackerFrame:Show()
    if currenciesTab then
        PanelTemplates_SelectTab(currenciesTab)
    end
    BuildFlatList()
    CurrencyTracker_UpdateScroll()

    if not autoDepositCheckbox then
        local cb = CreateFrame("CheckButton", "CurrencyTrackerAutoDepositCB", CurrencyTrackerFrame, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("BOTTOMLEFT", CurrencyTrackerFrame, "BOTTOMLEFT", 14, 8)
        cb:SetChecked(CurrencyTrackerCharDB.autoDeposit == true)
        cb:SetScript("OnClick", function(self)
            CurrencyTrackerCharDB.autoDeposit = self:GetChecked() == true
        end)

        local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        label:SetText("Auto-deposit badges to bank")
        autoDepositCheckbox = cb
    end

    autoDepositCheckbox:SetChecked(CurrencyTrackerCharDB.autoDeposit == true)
    autoDepositCheckbox:Show()
end

local function HideCurrenciesPanel(restoreDefaultPanel)
    Debug("HideCurrenciesPanel called (restore=" .. tostring(restoreDefaultPanel) .. ")")
    if CurrencyTrackerFrame then
        CurrencyTrackerFrame:Hide()
    end

    if currenciesTab then
        PanelTemplates_DeselectTab(currenciesTab)
    end

    if restoreDefaultPanel and CharacterFrame and CharacterFrame:IsShown() then
        ShowSelectedCharacterSubFrame()
        RestoreDefaultCharacterTabHighlight()
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

local function EnsureCurrenciesTab()
    if currenciesTab or not CharacterFrame then
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
        if CurrencyTrackerFrame and CurrencyTrackerFrame:IsShown() then
            HideCurrenciesPanel(true)
        else
            ShowCurrenciesPanel()
        end
    end)

    PanelTemplates_DeselectTab(tab)
    currenciesTab = tab

    if type(hooksecurefunc) == "function" and type(CharacterFrame_ShowSubFrame) == "function" and not subFrameHookInstalled then
        hooksecurefunc("CharacterFrame_ShowSubFrame", function(frameName)
            if frameName and frameName ~= "CurrencyTrackerFrame" then
                if type(PanelTemplates_GetSelectedTab) == "function" then
                    lastSelectedCharacterTabIndex = PanelTemplates_GetSelectedTab(CharacterFrame) or lastSelectedCharacterTabIndex
                end
                HideCurrenciesPanel(false)
            end
        end)
        subFrameHookInstalled = true
    end
end

-- Slash command to toggle debug mode
SLASH_CURRENCYTRACKERDEBUG1 = "/ctdebug"
SlashCmdList["CURRENCYTRACKERDEBUG"] = function()
    EnsureDB()
    CurrencyTrackerDB.debugEnabled = not CurrencyTrackerDB.debugEnabled
    if CurrencyTrackerDB.debugEnabled then
        DebugAlways("Debug mode |cff00ff00ENABLED|r. Type /ctdebug to disable.")
    else
        DebugAlways("Debug mode |cffff0000DISABLED|r. Type /ctdebug to enable.")
    end
end

-- Interface Options panel (Escape > Options > AddOns)
local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "CurrencyTrackerOptionsPanel", UIParent)
    panel.name = "CurrencyTracker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("CurrencyTracker v" .. ADDON_VERSION)

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
            DebugAlways("Debug mode |cff00ff00ENABLED|r")
        else
            DebugAlways("Debug mode |cffff0000DISABLED|r")
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
        if autoDepositCheckbox then
            autoDepositCheckbox:SetChecked(CurrencyTrackerCharDB.autoDeposit == true)
        end
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
        DebugAlways("Warning: Could not register options panel - no supported API found")
    end
end

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

eventFrame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        EnsureDB()
        EnsureCharDB()
        EnsureCountsDB()
        EnsureFrameBackground()
        SyncFrameToCharacterLayout()
        EnsureInsetPanel()
        EnsureScrollFrame()
        EnsureCurrenciesTab()
        UpdateHeaderVersionText()
        CreateOptionsPanel()
        DebugAlways("CurrencyTracker loaded. v" .. ADDON_VERSION .. " (debug " .. (CurrencyTrackerDB.debugEnabled and "ON" or "OFF") .. ", /ctdebug to toggle)")

        for i = 1, MAX_ROWS do
            if not rows[i] then
                rows[i] = CreateRow(i)
            end
        end

        CharacterFrame:HookScript("OnHide", function()
            HideCurrenciesPanel(false)
        end)

        CharacterFrame:HookScript("OnShow", function()
            EnsureCurrenciesTab()
            SyncFrameToCharacterLayout()
            EnsureInsetPanel()
            EnsureScrollFrame()
            UpdateRowLayout()

            if type(PanelTemplates_GetSelectedTab) == "function" and not CurrencyTrackerFrame:IsShown() then
                lastSelectedCharacterTabIndex = PanelTemplates_GetSelectedTab(CharacterFrame) or lastSelectedCharacterTabIndex
            end

            UpdateHeaderVersionText()
            if CurrencyTrackerFrame:IsShown() then
                BuildFlatList()
                CurrencyTracker_UpdateScroll()
            end
        end)
    elseif event == "PLAYER_LOGIN" then
        EnsureDB()
        EnsureCharDB()
        EnsureCountsDB()
        EnsureCurrenciesTab()
        Debug("PLAYER_LOGIN complete")
    elseif event == "BANKFRAME_OPENED" then
        Debug("Event: BANKFRAME_OPENED")
        bankDataKnownThisSession = true
        BuildFlatList()
        if CurrencyTrackerFrame and CurrencyTrackerFrame:IsShown() then
            CurrencyTracker_UpdateScroll()
        end
        AutoDepositBadgesToBank()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        Debug("Event: GET_ITEM_INFO_RECEIVED")
        BuildFlatList()
        if CurrencyTrackerFrame and CurrencyTrackerFrame:IsShown() then
            CurrencyTracker_UpdateScroll()
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED" then
        Debug("Event: " .. event)
        BuildFlatList()
        if CurrencyTrackerFrame and CurrencyTrackerFrame:IsShown() then
            CurrencyTracker_UpdateScroll()
        end
    end
end)
