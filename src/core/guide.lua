-- Sorting guide planner: one safe manual move at a time. Pure and stateless: it re-plans
-- from the bank as it actually is after every move, so a different move never confuses it.
--
-- Bank model: sections[0] = Main (untabbed items), sections[1..n] = the custom tabs, each an
-- ordered list of item ids.
-- Whole-bank blueprints (destinations 0-9) map densely onto custom tabs in order, skipping
-- empty ones. "My tabs" blueprints set destinations.identity: destination N is custom tab N.
local Order = require("src/core/order")

local Guide = {}

Guide.INSERT, Guide.SWAP = "insert", "swap"

local function lastDestination(destinations)
  local last = 0
  for d in pairs(destinations) do
    if type(d) == "number" and d > last then last = d end
  end
  return last
end

-- Blueprint destination -> custom tab index (Main stays 0).
function Guide.sectionMap(destinations)
  local map, physical = { [0] = 0 }, 0
  for d = 1, lastDestination(destinations) do
    local entries = destinations[d] or {}
    if destinations.identity then
      map[d] = d
      physical = d
    elseif #entries > 0 then
      physical = physical + 1
      map[d] = physical
    end
  end
  return map, physical
end

-- Target ids per custom tab.
function Guide.targetSections(destinations)
  local map = Guide.sectionMap(destinations)
  local targets = {}
  for d = 0, lastDestination(destinations) do
    local section = map[d]
    if section then
      targets[section] = {}
      for index, entry in ipairs(destinations[d] or {}) do targets[section][index] = entry.id end
    end
  end
  return targets, map
end

local function locate(sections)
  local where = {}
  for s, ids in pairs(sections) do
    for index, id in ipairs(ids) do where[id] = { section = s, index = index } end
  end
  return where
end

local function tabCount(sections)
  local count = 0
  for s in pairs(sections) do if s > count then count = s end end
  return count
end

-- Swap mode: put the right item in the first wrong position.
local function nextSwap(current, target)
  for index, id in ipairs(target) do
    if current[index] ~= id then
      for other = index + 1, #current do
        if current[other] == id then return { move = id, swapWith = current[index] } end
      end
    end
  end
  return nil
end

-- Swaps needed to sort = n - cycles (exact for unique ids).
function Guide.swapCount(current, target)
  local position = {}
  for index, id in ipairs(target) do position[id] = index end
  local visited, cycles, n = {}, 0, 0
  for index, id in ipairs(current) do
    if position[id] then
      n = n + 1
      if not visited[index] then
        cycles = cycles + 1
        local cursor = index
        while not visited[cursor] and current[cursor] and position[current[cursor]] do
          visited[cursor] = true
          cursor = position[current[cursor]]
        end
      end
    end
  end
  return n - cycles
end

-- Moves between sections. With a focus, only items leaving the viewed section count:
-- an item can only be dragged from the tab you are looking at.
local function crossMove(sections, destinations, map, focus)
  local where = locate(sections)
  for d = 0, lastDestination(destinations) do
    local section = map[d]
    for _, entry in ipairs(section and destinations[d] or {}) do
      local here = where[entry.id]
      if here and here.section ~= section and (focus == nil or here.section == focus) then
        local kind = section > tabCount(sections) and "new-tab" or "to-tab"
        return { kind = kind, id = entry.id, from = here.section, to = section, destination = d }
      end
    end
  end
  return nil
end

local function orderMove(current, target, mode, s)
  if mode == Guide.SWAP then
    local swap = nextSwap(current, target)
    if swap then swap.kind, swap.section, swap.remaining = "swap", s, Guide.swapCount(current, target) end
    return swap
  end
  local move = Order.nextMove(current, target)
  if move then move.kind, move.section = "insert", s end
  return move
end

---@param sections table { [0..n] = { id, ... } } bank as it is now
---@param destinations table blueprint destinations
---@param mode string Guide.INSERT or Guide.SWAP
---@param focus integer? only plan for this section (the tab you are viewing)
---@return table? step, string status ("done" when the bank matches the blueprint)
function Guide.next(sections, destinations, mode, focus)
  local targets, map = Guide.targetSections(destinations)
  local cross = crossMove(sections, destinations, map, focus)
  if cross then return cross, "moving" end
  local order = {}
  for s in pairs(targets) do
    if focus == nil or s == focus then order[#order + 1] = s end
  end
  table.sort(order)
  for _, s in ipairs(order) do
    local step = orderMove(sections[s] or {}, targets[s], mode, s)
    if step then return step, "sorting" end
  end
  return nil, "done"
end

-- Total manual moves left: between-section moves, then in-section moves counted on each
-- section as it will look once those arrive (moved items land at the end, in blueprint order).
function Guide.remaining(sections, destinations, mode, focus)
  local targets, map = Guide.targetSections(destinations)
  local where, total = locate(sections), 0
  local after, targetSectionOf = {}, {}
  for s in pairs(targets) do after[s] = {} end
  for dest, section in pairs(map) do
    for _, entry in ipairs(destinations[dest] or {}) do targetSectionOf[entry.id] = section end
  end
  for s, ids in pairs(sections) do
    for _, id in ipairs(ids) do
      if targetSectionOf[id] == s and after[s] then table.insert(after[s], id) end
    end
  end
  for dest = 0, lastDestination(destinations) do
    for _, entry in ipairs(map[dest] and destinations[dest] or {}) do
      local here = where[entry.id]
      if here and here.section ~= map[dest] and (focus == nil or here.section == focus) then
        total = total + 1
        table.insert(after[map[dest]], entry.id)
      end
    end
  end
  for s, target in pairs(targets) do
    if focus == nil or s == focus then
      if mode == Guide.SWAP then
        total = total + Guide.swapCount(after[s], target)
      else
        local move = Order.nextMove(after[s], target)
        total = total + (move and move.remaining or 0)
      end
    end
  end
  return total
end

return Guide
