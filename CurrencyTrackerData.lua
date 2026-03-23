-- CurrencyTrackerData.lua
-- ============================================================
-- Central item registry for CurrencyTracker.
-- To track a new item, just add a line to the list below.
--
-- Fields:
--   id       = WoW item ID (required)
--   category = Display category / header text (required)
--   name     = English fallback name, shown when the client
--              cannot resolve the name from the item ID (required)
--   faction  = "Horde" or "Alliance" (optional, omit to show for both)
-- ============================================================

local _, CT = ...

CT.Items = {
    -- Battleground
    { id = 20558, category = "Battleground", name = "Warsong Gulch Mark of Honor" },
    { id = 20559, category = "Battleground", name = "Arathi Basin Mark of Honor" },
    { id = 20560, category = "Battleground", name = "Alterac Valley Mark of Honor" },
    { id = 29024, category = "Battleground", name = "Eye of the Storm Mark of Honor" },

    -- Dungeon and Raids
    { id = 29434, category = "Dungeon and Raids", name = "Badge of Justice" },
    { id = 29736, category = "Dungeon and Raids", name = "Arcane Rune" },

    -- Open World PvP
    { id = 26045, category = "Open World PvP", name = "Halaa Battle Token" },
    { id = 26044, category = "Open World PvP", name = "Halaa Research Token" },
    { id = 24581, category = "Open World PvP", name = "Mark of Thrallmar", faction = "Horde" },
    { id = 24579, category = "Open World PvP", name = "Mark of Honor Hold", faction = "Alliance" },
    { id = 28558, category = "Open World PvP", name = "Spirit Shard" },
}
