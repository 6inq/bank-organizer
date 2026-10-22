-- Bank Organizer tests: complete sorting sessions on banks of 10, 100, 500
-- and 1,000 real RS3 items, shuffled across tabs.
--
-- Requirements covered: the guide always finishes, uses exactly the number
-- of moves it predicted, and stays fast on large banks.

local A = require("assert")
local Layout = require("src/core/layout")
local Blueprint = require("src/core/blueprint")
local Guide = require("src/core/guide")
local Order = require("src/core/order")
local ITEMS = require("fixtures/rs3_items")

local T = {}

-- Applies a guide step to sections the way the game would.
local function apply(sections, step)
  if step.kind == "to-tab" or step.kind == "new-tab" then
    local from = sections[step.from]
    for index, id in ipairs(from) do if id == step.id then table.remove(from, index); break end end
    sections[step.to] = sections[step.to] or {}
    table.insert(sections[step.to], step.id)
  elseif step.kind == "insert" then
    if step.from and step.from ~= step.section then
      local from = sections[step.from]
      for index, id in ipairs(from) do if id == step.move then table.remove(from, index); break end end
    end
    sections[step.section] = Order.apply(sections[step.section] or {}, step)
  else
    local list = sections[step.section]
    local a, b
    for index, id in ipairs(list) do
      if id == step.move then a = index end
      if id == step.swapWith then b = index end
    end
    list[a], list[b] = list[b], list[a]
  end
end

-- Runs a full sorting session on the first count fixture items, shuffled
-- at random across the infinity tab and three custom tabs. Returns the moves
-- made, the moves predicted and the time taken.
local function session(count, mode)
  math.randomseed(count)
  local items, ids = {}, {}
  for index = 1, count do
    local row = ITEMS[index]
    items[index] = { slot = index, id = row.id, name = row.name, quantity = 1, info = { name = row.name } }
    ids[index] = row.id
  end
  for i = count, 2, -1 do local j = math.random(i); ids[i], ids[j] = ids[j], ids[i] end
  local sections = { [0] = {}, {}, {}, {} }
  for _, id in ipairs(ids) do table.insert(sections[math.random(0, 3)], id) end
  local destinations = Blueprint.build(items, Layout.new("main"), Blueprint.resolver({}))
  local expected, moves, started = Guide.remaining(sections, destinations, mode), 0, os.clock()
  while true do
    local step = Guide.next(sections, destinations, mode)
    if not step then break end
    apply(sections, step)
    moves = moves + 1
    if moves > count * 4 then error("did not converge") end
  end
  local targets = Guide.targetSections(destinations)
  for s, target in pairs(targets) do A.list(sections[s] or {}, target, "section " .. s) end
  return moves, expected, os.clock() - started
end

-- Requirement: Ten.
function T.ten() local m, e = session(10, Guide.INSERT); A.eq(m, e) end
-- Requirement: Hundred.
function T.hundred() local m, e = session(100, Guide.INSERT); A.eq(m, e) end
-- Requirement: Five hundred.
function T.five_hundred() local m, e = session(500, Guide.INSERT); A.eq(m, e) end

-- Requirement: Thousand insert exact and fast.
function T.thousand_insert_exact_and_fast()
  local moves, expected, elapsed = session(1000, Guide.INSERT)
  A.eq(moves, expected, "exactly the minimum number of moves")
  A.truthy(elapsed < 120, "took " .. elapsed .. "s")
end

-- Requirement: Five hundred swap mode finishes.
function T.five_hundred_swap_mode_finishes()
  local moves, expected = session(500, Guide.SWAP)
  A.truthy(moves <= expected, "swap estimate is an upper bound")
end

return T
