-- Sorting guide planner: one safe manual move at a time. Pure and stateless: it re-plans
-- from the bank as it actually is after every move, so a different move never confuses it.
--
-- Bank model: sections[0] = Main (untabbed items), sections[1..n] = the physical tabs,
-- each an ordered list of item ids. Blueprint destinations 1-9 map densely onto physical
-- tabs in order, skipping empty ones (a bank cannot keep an empty tab).
local Order = require("src/core/order")
local Tags = require("src/core/tags")

local Guide = {}

Guide.INSERT, Guide.SWAP = "insert", "swap"

-- Blueprint destination -> physical section index (Main stays 0).
function Guide.sectionMap(destinations)
  local map, physical = { [0] = 0 }, 0
  for d = 1, Tags.DESTINATIONS - 1 do
    if #destinations[d] > 0 then
      physical = physical + 1
      map[d] = physical
    end
  end
  return map, physical
end

-- Target ids per physical section.
function Guide.targetSections(destinations)
  local map = Guide.sectionMap(destinations)
  local targets = {}
  for d = 0, Tags.DESTINATIONS - 1 do
    local section = map[d]
    if section then
      targets[section] = {}
      for index, entry in ipairs(destinations[d]) do targets[section][index] = entry.id end
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
        if current[other] == id then return { move = id, swapWith = current[index], remaining = nil } end
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

---@param sections table { [0..n] = { id, ... } } bank as it is now
---@param destinations table blueprint destinations
---@param mode string Guide.INSERT or Guide.SWAP
---@return table? step, string status ("done" when the bank matches the blueprint)
function Guide.next(sections, destinations, mode)
  local targets, map = Guide.targetSections(destinations)
  local where = locate(sections)
  local needed = 0
  for _, s in pairs(map) do if s > needed then needed = s end end

  -- 1. Items in the wrong section, in blueprint order (Main first, then tab by tab).
  for d = 0, Tags.DESTINATIONS - 1 do
    local section = map[d]
    for _, entry in ipairs(section and destinations[d] or {}) do
      local here = where[entry.id]
      if here and here.section ~= section then
        if section > tabCount(sections) then
          return { kind = "new-tab", id = entry.id, from = here.section, to = section, destination = d }, "moving"
        end
        return { kind = "to-tab", id = entry.id, from = here.section, to = section, destination = d }, "moving"
      end
    end
  end

  -- 2. Order within each section.
  local sectionIndexes = {}
  for s in pairs(targets) do sectionIndexes[#sectionIndexes + 1] = s end
  table.sort(sectionIndexes)
  for _, s in ipairs(sectionIndexes) do
    local current, target = sections[s] or {}, targets[s]
    if mode == Guide.SWAP then
      local swap = nextSwap(current, target)
      if swap then
        swap.kind, swap.section, swap.remaining = "swap", s, Guide.swapCount(current, target)
        return swap, "sorting"
      end
    else
      local move = Order.nextMove(current, target)
      if move then
        move.kind, move.section = "insert", s
        return move, "sorting"
      end
    end
  end
  return nil, "done"
end

-- Total manual moves left: between-section moves, then in-section moves counted on each
-- section as it will look once those arrive (moved items land at the end, in blueprint order).
function Guide.remaining(sections, destinations, mode)
  local targets, map = Guide.targetSections(destinations)
  local where, total = locate(sections), 0
  local after = {}
  for s in pairs(targets) do after[s] = {} end
  local targetSectionOf = {}
  for dest, section in pairs(map) do
    for _, entry in ipairs(destinations[dest]) do targetSectionOf[entry.id] = section end
  end
  -- Items already in their target section keep their current relative order.
  for s, ids in pairs(sections) do
    for _, id in ipairs(ids) do
      if targetSectionOf[id] == s and after[s] then table.insert(after[s], id) end
    end
  end
  for dest = 0, Tags.DESTINATIONS - 1 do
    for _, entry in ipairs(map[dest] and destinations[dest] or {}) do
      local here = where[entry.id]
      if here and here.section ~= map[dest] then
        total = total + 1
        table.insert(after[map[dest]], entry.id)
      end
    end
  end
  for s, target in pairs(targets) do
    if mode == Guide.SWAP then
      total = total + Guide.swapCount(after[s], target)
    else
      local move = Order.nextMove(after[s], target)
      total = total + (move and move.remaining or 0)
    end
  end
  return total
end

return Guide
