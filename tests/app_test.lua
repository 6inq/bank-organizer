-- End-to-end: fake bank -> App.refresh -> status + overlays, including a full ordering session.
local A = require("assert")
local F = require("fakes")
local Store = require("src/core/store")
local Bank = require("src/game/bank")
local App = require("src/app")

local T = {}

local OBJECTS = {
  [1] = { name = "Shark", ops = { "Eat" } },
  [2] = { name = "Varrock teleport", ops = { "Break" } },
  [3] = { name = "Coins" },
  [4] = { name = "Yew logs" },
}

local function setup(order, opts)
  opts = opts or {}
  local items = {}
  for index, objectID in ipairs(order) do items[index] = { id = objectID, x = (index - 1) * 40, y = 0 } end
  F.install({ items = items, objects = OBJECTS, search = opts.search, tab = opts.tab, missing = opts.missing })
  Bank._resetCache()
  package.loaded["src/app"] = nil
  local App = require("src/app")
  return App.new(Store.new(F.memoryDb()))
end

-- Simulate the player performing a move by re-laying out the fake bank.
local function perform(app, move)
  local Order = require("src/core/order")
  local current = {}
  for index, slot in ipairs(Bank.scan()) do current[index] = slot.objectID end
  local after = Order.apply(current, move)
  local byID = {}
  for _, child in ipairs(F.children) do byID[child.associatedObjectID] = child end
  for index, objectID in ipairs(after) do byID[objectID].x = (index - 1) * 40 end
  app:invalidate()
end

function T.bank_closed_status()
  local app = setup({}, { missing = true })
  app:refresh()
  A.eq(app.status, "Open your bank.")
end

function T.full_ordering_session_reaches_target()
  -- Target: teleports(2), food(1), materials(4), currency(3)
  local app = setup({ 3, 1, 4, 2 })
  app:startOrganizing()
  local guard = 0
  while app.organizing do
    A.truthy(app.move, "move present while ordering")
    A.truthy(app.status:find("Insert") or app.status:find("Move"), "status describes move")
    perform(app, app.move)
    app:refresh()
    guard = guard + 1
    if guard > 10 then error("did not finish") end
  end
  A.eq(app.status, App.STATUS.DONE)
  local final = Bank.scan()
  local ids = {}
  for index, slot in ipairs(final) do ids[index] = slot.objectID end
  A.list(ids, { 2, 1, 4, 3 })
  app:refresh()
  A.eq(app.status, App.STATUS.DONE, "finish message persists")
end

function T.manual_tag_overrides_classifier()
  local app = setup({ 1, 2 })
  app.store:setTag(1, "teleports")
  A.eq(app:categoryOf(1), "teleports")
  app:startOrganizing()
  A.eq(app.organizing, false, "both teleports by id order already sorted")
end

function T.search_blocks_ordering()
  local app = setup({ 3, 1 }, { search = 1 })
  app:startOrganizing()
  A.eq(app.status, App.STATUS.SEARCH); A.eq(app.move, nil)
end

function T.all_items_tab_hint()
  local app = setup({ 3, 1 }, { tab = 1 })
  app:startOrganizing()
  A.truthy(app.hint:find("between tabs"))
end

function T.skip_current_move()
  local app = setup({ 1, 2 })
  app:startOrganizing()
  A.eq(app.move.remaining, 1)
  app:skipCurrent()
  A.eq(app.status, App.STATUS.DONE)
end

function T.stop_clears_highlights_and_events()
  local app = setup({ 3, 1 })
  app:start()
  A.truthy(F.events["Logic:bank-organizer:logic"])
  app:startOrganizing()
  app:stopOrganizing()
  A.eq(app.move, nil)
  app:stop()
  A.eq(F.events["Logic:bank-organizer:logic"], nil)
  A.eq(F.count("rect") + F.count("text"), 0)
end

function T.inventory_event_invalidates_only_for_bank()
  local app = setup({ 1 })
  app:start()
  app.dirty = false
  F.events["InventoryUpdated:bank-organizer:logic"]({ inv = { id = 93 } })
  A.eq(app.dirty, false)
  F.events["InventoryUpdated:bank-organizer:logic"]({ inv = { id = 95 } })
  A.eq(app.dirty, true)
end

return T
