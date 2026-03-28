-- CurrencyTrackerPanel.lua
-- ============================================================
-- Currencies panel UI: inset styling, scroll frame, row
-- creation, flat-list building, scroll updating, tooltips,
-- and the auto-deposit checkbox.
-- ============================================================

local _, CT = ...

local Panel = {}
CT.Panel = Panel

local MAX_ROWS = 20
local NUM_ROWS = 10
local ROW_HEIGHT = 21
local HEADER_HEIGHT = 21
local ROW_SPACING = 1

local rows = {}
local flatList = {}
local autoDepositCheckbox = nil

---------------------------------------------------------------------------
-- Helpers (panel-local)
---------------------------------------------------------------------------

local function IsCollapsed(header)
    return CurrencyTrackerCharDB and CurrencyTrackerCharDB.collapsed and CurrencyTrackerCharDB.collapsed[header] == true
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

    if not CT.bankDataKnownThisSession then
        GameTooltip:AddLine("Bank data may be from your last bank visit.", 0.8, 0.8, 0.8, true)
    end

    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Flat list
---------------------------------------------------------------------------

function Panel.BuildFlatList()
    CT.WipeTable(flatList)

    local playerFaction = UnitFactionGroup("player")

    for _, category in ipairs(CT.CURRENCIES) do
        table.insert(flatList, {
            isHeader = true,
            header = category.header,
            text = category.header,
        })

        if not IsCollapsed(category.header) then
            for _, item in ipairs(category.items) do
                if not item.faction or item.faction == playerFaction then
                    local counts = CT.CollectItemCounts(item.id)
                    local icon = GetItemIcon(item.id)
                    local localizedName = GetItemInfo(item.id) or item.name

                    table.insert(flatList, {
                        isHeader = false,
                        id = item.id,
                        text = localizedName,
                        count = counts.total or 0,
                        bag = counts.bag or 0,
                        bank = counts.bank or 0,
                        icon = icon or CT.ICON_FALLBACK,
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
    Panel.BuildFlatList()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function CreateRow(i)
    local row = CreateFrame("Button", nil, CurrencyTrackerFrame)
    row:SetWidth(260)
    row:SetHeight(ROW_HEIGHT)

    if i == 1 then
        row:SetPoint("TOPLEFT", CurrencyTrackerScrollFrame, "TOPLEFT", 0, 0)
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
    row.icon:SetTexture(CT.ICON_FALLBACK)
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
            Panel.UpdateScroll()
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

function Panel.EnsureRows()
    for i = 1, MAX_ROWS do
        if not rows[i] then
            rows[i] = CreateRow(i)
        end
    end
end

function Panel.UpdateRowLayout()
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
        rows[i]:SetWidth(rowWidth)
    end
end

---------------------------------------------------------------------------
-- Scroll update
---------------------------------------------------------------------------

function Panel.UpdateScroll()
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
                row.icon:SetTexture(entry.icon or CT.ICON_FALLBACK)
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

-- Backward-compatible global used by the FauxScrollFrame template
function CurrencyTracker_UpdateScroll()
    Panel.UpdateScroll()
end

---------------------------------------------------------------------------
-- Background (matching other CharacterFrame sub-panels)
---------------------------------------------------------------------------

function Panel.EnsureBackground()
    if not CurrencyTrackerFrame then
        return
    end

    if CurrencyTrackerFrame.bgApplied then
        return
    end

    -- Use the same four background textures as PaperDollFrame / ReputationFrame
    local bgTL = CurrencyTrackerFrame:CreateTexture(nil, "BORDER")
    bgTL:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft")
    bgTL:SetSize(256, 256)
    bgTL:SetPoint("TOPLEFT")

    local bgTR = CurrencyTrackerFrame:CreateTexture(nil, "BORDER")
    bgTR:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight")
    bgTR:SetSize(128, 256)
    bgTR:SetPoint("TOPRIGHT")

    local bgBL = CurrencyTrackerFrame:CreateTexture(nil, "BORDER")
    bgBL:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-General-BottomLeft")
    bgBL:SetSize(256, 256)
    bgBL:SetPoint("BOTTOMLEFT")

    local bgBR = CurrencyTrackerFrame:CreateTexture(nil, "BORDER")
    bgBR:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-General-BottomRight")
    bgBR:SetSize(128, 256)
    bgBR:SetPoint("BOTTOMRIGHT")

    CurrencyTrackerFrame.bgApplied = true

    -- Ensure title draws above the background textures
    if CurrencyTrackerFrameTitle then
        CurrencyTrackerFrameTitle:SetDrawLayer("OVERLAY")
    end
end

---------------------------------------------------------------------------
-- Scroll frame
---------------------------------------------------------------------------

function Panel.EnsureScrollFrame()
    Panel.EnsureBackground()

    if not CurrencyTrackerFrame then
        return
    end

    if not CurrencyTrackerScrollFrame then
        local sf = CreateFrame("ScrollFrame", "CurrencyTrackerScrollFrame", CurrencyTrackerFrame, "FauxScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", CurrencyTrackerFrame, "TOPLEFT", 22, -76)
        sf:SetPoint("BOTTOMRIGHT", CurrencyTrackerFrame, "BOTTOMRIGHT", -22, 96)
        sf:SetScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT + ROW_SPACING, CurrencyTracker_UpdateScroll)
        end)
    else
        CurrencyTrackerScrollFrame:SetParent(CurrencyTrackerFrame)
        CurrencyTrackerScrollFrame:ClearAllPoints()
        CurrencyTrackerScrollFrame:SetPoint("TOPLEFT", CurrencyTrackerFrame, "TOPLEFT", 22, -76)
        CurrencyTrackerScrollFrame:SetPoint("BOTTOMRIGHT", CurrencyTrackerFrame, "BOTTOMRIGHT", -22, 96)
        if not CurrencyTrackerScrollFrame.scrollScriptSet then
            CurrencyTrackerScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
                FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT + ROW_SPACING, CurrencyTracker_UpdateScroll)
            end)
            CurrencyTrackerScrollFrame.scrollScriptSet = true
        end
    end
end

---------------------------------------------------------------------------
-- Layout sync
---------------------------------------------------------------------------

function Panel.SyncLayout()
    if not CurrencyTrackerFrame or not CharacterFrame then
        return
    end

    CurrencyTrackerFrame:SetAllPoints(CharacterFrame)
end

function Panel.UpdateVersionText()
    if CurrencyTrackerFrameTitle then
        CurrencyTrackerFrameTitle:SetText("Currencies (" .. CT.VERSION .. ")")
    end
end

---------------------------------------------------------------------------
-- Auto-deposit checkbox
---------------------------------------------------------------------------

local function EnsureAutoDepositCheckbox()
    if autoDepositCheckbox then
        autoDepositCheckbox:SetChecked(CurrencyTrackerCharDB.autoDeposit == true)
        autoDepositCheckbox:Show()
        return
    end

    local cb = CreateFrame("CheckButton", "CurrencyTrackerAutoDepositCB", CurrencyTrackerFrame, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("BOTTOMLEFT", CurrencyTrackerFrame, "BOTTOMLEFT", 25, 85)
    cb:SetChecked(CurrencyTrackerCharDB.autoDeposit == true)
    cb:SetScript("OnClick", function(self)
        CurrencyTrackerCharDB.autoDeposit = self:GetChecked() == true
    end)

    local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    label:SetText("Auto-deposit badges to bank")
    autoDepositCheckbox = cb
end

function Panel.SyncAutoDepositCheckbox()
    if autoDepositCheckbox then
        autoDepositCheckbox:SetChecked(CurrencyTrackerCharDB.autoDeposit == true)
    end
end

---------------------------------------------------------------------------
-- Show / Hide / IsShown
---------------------------------------------------------------------------

function Panel.Show()
    if not CurrencyTrackerFrame then
        return
    end

    Panel.SyncLayout()
    Panel.EnsureBackground()
    Panel.EnsureScrollFrame()
    Panel.EnsureRows()
    Panel.UpdateRowLayout()
    CurrencyTrackerFrame:Show()
    Panel.BuildFlatList()
    Panel.UpdateScroll()
    EnsureAutoDepositCheckbox()
end

function Panel.Hide()
    if CurrencyTrackerFrame then
        CurrencyTrackerFrame:Hide()
    end
end

function Panel.IsShown()
    return CurrencyTrackerFrame and CurrencyTrackerFrame:IsShown()
end

---------------------------------------------------------------------------
-- Init (called once during ADDON_LOADED)
---------------------------------------------------------------------------

function Panel.Init()
    Panel.SyncLayout()
    Panel.EnsureBackground()
    Panel.EnsureScrollFrame()
    Panel.EnsureRows()
    Panel.UpdateVersionText()

    -- When Blizzard's ToggleCharacter shows our frame, run full setup
    if CurrencyTrackerFrame and not CurrencyTrackerFrame.onShowHooked then
        CurrencyTrackerFrame:HookScript("OnShow", function()
            Panel.SyncLayout()
            Panel.EnsureBackground()
            Panel.EnsureScrollFrame()
            Panel.EnsureRows()
            Panel.UpdateRowLayout()
            Panel.BuildFlatList()
            Panel.UpdateScroll()
            Panel.UpdateVersionText()
            EnsureAutoDepositCheckbox()
        end)
        CurrencyTrackerFrame.onShowHooked = true
    end
end
