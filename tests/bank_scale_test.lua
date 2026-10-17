-- Full ordering sessions on banks of 10 / 100 / 500 / 1000 REAL RS3 items.
-- The plugin must read item ids from the bank slots itself, resolve their names,
-- and reach the target order in exactly the minimal number of moves.
local A = require("assert")
local F = require("fakes")
local Store = require("src/core/store")
local Bank = require("src/game/bank")
local App = require("src/app")
local Order = require("src/core/order")
local Categories = require("src/core/categories")
local ITEMS = require("fixtures/rs3_items")

local COLUMNS, CELL = 10, 44
local T = {}

local function layout(children, orderedIDs)
  local byID = {}
  for _, child in ipairs(children) do byID[child.associatedObjectID] = child end
  for index, objectID in ipairs(orderedIDs) do
    byID[objectID].x = ((index - 1) % COLUMNS) * CELL
    byID[objectID].y = ((index - 1) // COLUMNS) * CELL
  end
end

local function shuffled(count, seed)
  local list = {}
  for index = 1, count do list[index] = ITEMS[index] end
  math.randomseed(seed)
  for i = count, 2, -1 do
    local j = math.random(1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

local function scannedIDs()
  local ids = {}
  for index, slot in ipairs(Bank.scan()) do ids[index] = slot.objectID end
  return ids
end

local function setup(count)
  local bankItems, objects, names = {}, {}, {}
  for index, item in ipairs(shuffled(count, count)) do
    bankItems[index] = { id = item.id, x = 0, y = 0 }
    objects[item.id] = { name = item.name }
    names[item.id] = item.name
  end
  F.install({ items = bankItems, objects = objects })
  local initial = {}
  for index, item in ipairs(bankItems) do initial[index] = item.id end
  layout(F.children, initial)
  Bank._resetCache()
  package.loaded["src/app"] = nil
  return require("src/app").new(Store.new(F.memoryDb())), initial, names
end

local function expectedTarget(app, ids)
  local items = {}
  for index, objectID in ipairs(ids) do
    items[index] = { objectID = objectID, name = app:nameOf(objectID), category = app:categoryOf(objectID) }
  end
  return Order.buildTarget(items, "id")
end

local function runSession(count)
  local app, initial, names = setup(count)

  -- The plugin pulls the ids from the slot components, in visual order.
  A.list(scannedIDs(), initial, "scan returns the bank's item ids in order")
  for objectID, name in pairs(names) do A.eq(Bank.info(objectID).name, name, "name for id " .. objectID) end

  local target = expectedTarget(app, initial)
  local started = os.clock()
  app:startOrganizing()
  local expectedMoves = app.move and app.move.remaining or 0
  local moves = 0
  while app.organizing do
    layout(F.children, Order.apply(scannedIDs(), app.move))
    app:invalidate()
    app:refresh()
    moves = moves + 1
    if moves > count then error("did not converge") end
  end
  local elapsed = os.clock() - started

  A.eq(app.status, App.STATUS.DONE)
  A.list(scannedIDs(), target, "final bank order equals target")
  A.eq(moves, expectedMoves, "used exactly the minimal number of moves")
  local lastRank = 0
  for _, objectID in ipairs(scannedIDs()) do
    local rank = Categories.rank(app:categoryOf(objectID))
    A.truthy(rank >= lastRank, "categories are contiguous")
    lastRank = rank
  end
  return moves, elapsed
end

function T.bank_10_items() runSession(10) end
function T.bank_100_items() runSession(100) end
function T.bank_500_items() runSession(500) end

function T.bank_1000_items()
  local moves, elapsed = runSession(1000)
  A.truthy(moves > 900, "a shuffled 1000-item bank needs most items moved")
  -- About 1000 full rescans; keep the whole session comfortably fast.
  A.truthy(elapsed < 60, "1000-item session took " .. elapsed .. "s")
end

function T.single_refresh_1000_items_is_fast()
  local app = setup(1000)
  app:startOrganizing()
  local started = os.clock()
  for _ = 1, 10 do app:invalidate(); app:refresh() end
  local perRefresh = (os.clock() - started) / 10
  A.truthy(perRefresh < 0.05, "refresh took " .. perRefresh .. "s for 1000 slots")
end

function T.fixture_ids_are_real_and_unique()
  A.eq(#ITEMS, 1000)
  local seen = {}
  for _, item in ipairs(ITEMS) do
    A.truthy(item.id > 0 and item.name ~= "", "valid fixture row")
    A.eq(seen[item.id], nil, "duplicate id " .. item.id)
    seen[item.id] = true
  end
end

return T
