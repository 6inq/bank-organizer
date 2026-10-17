local A = require("assert")
local F = require("fakes")
local Bank = require("src/game/bank")

local T = {}

function T.scan_filters_and_sorts_row_major()
  F.install({ items = {
    { id = 30, x = 40, y = 0 },
    { id = 10, x = 0, y = 40 },
    { id = 20, x = 0, y = 0 },
    { id = 99, x = 80, y = 0, hidden = true },
    { id = 98, x = 120, y = 0, type = 9 },
    { id = -1, x = 160, y = 0 },
    { id = 97, x = 200, y = 0, visible = false },
  } })
  local slots = Bank.scan()
  local ids = {}
  for index, slot in ipairs(slots) do ids[index] = slot.objectID end
  A.list(ids, { 20, 30, 10 })
end

function T.scan_missing_container()
  F.install({ missing = true })
  local slots, reason = Bank.scan()
  A.eq(slots, nil); A.eq(reason, "Open your bank.")
end

function T.scan_invisible_container()
  F.install({ visible = false, items = { { id = 1, x = 0, y = 0 } } })
  local slots, reason = Bank.scan()
  A.eq(slots, nil); A.truthy(reason)
end

function T.scan_tolerates_missing_globals()
  F.install()
  _G.id = nil
  local slots, reason = Bank.scan()
  A.eq(slots, nil); A.truthy(reason)
end

function T.info_reads_name_category_ops()
  F.install({ objects = { [385] = { name = "Shark", category = 7, ops = { "Eat", "Drop" } } }, categories = { [7] = "FOOD" } })
  Bank._resetCache()
  local info = Bank.info(385)
  A.eq(info.name, "Shark"); A.eq(info.category, "FOOD"); A.eq(info.ops.eat, true); A.eq(info.ops.drop, true)
end

function T.info_unknown_item_falls_back()
  F.install()
  Bank._resetCache()
  A.eq(Bank.info(12345).name, "Item 12345")
end

function T.search_and_tab_state()
  F.install({ search = 1, tab = 1 })
  A.eq(Bank.searchActive(), true); A.eq(Bank.isAllItemsTab(), true)
  F.install({ search = 0, tab = 3 })
  A.eq(Bank.searchActive(), false); A.eq(Bank.isAllItemsTab(), false)
end

return T
