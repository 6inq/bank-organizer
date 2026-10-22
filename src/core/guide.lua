-- Bank Organizer: the Sorting Guide's planner.
--
-- Given the bank as it is (sections: tab position -> item keys in order) and
-- the blueprint (destinations: planned tab -> planned entries), the planner
-- returns ONE next move for the player to make. It is called again after
-- every move, so it always plans from the real bank.
--
-- The order of work is:
--   1. Move items that are in the wrong tab, from the infinity tab first,
--      then tab by tab, top to bottom ("to-tab"). Dropping an item on the +
--      button starts a new tab ("new-tab").
--   2. Then put each tab in order, either with Insert moves (the fewest,
--      see src/core/order.lua) or with Swap moves, matching the game's own
--      Insert/Swap setting.
--
-- In Whole bank mode, empty planned tabs are skipped, so planned tab d maps
-- to the d-th tab that will actually exist (sectionMap). In My tabs mode the
-- plan uses the player's own tab positions directly (destinations.identity).

local Order = require("src/core/order")

local Guide = {}

-- The two rearrange modes, matching the game's bank setting.
Guide.INSERT, Guide.SWAP = "insert", "swap"

-- Returns the highest planned tab position.
local function lastDestination(destinations)
  local last = 0
  for d in pairs(destinations) do
    if type(d) == "number" and d > last then last = d end
  end
  return last
end

-- Maps each planned tab to the bank tab it will become.
-- Returns map (planned position -> bank position) and the number of custom
-- tabs the plan needs. Empty planned tabs get no bank tab, except in My
-- tabs mode, where positions are kept as they are.
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

-- Returns the target contents of each bank tab (bank position -> item keys
-- in planned order) and the map from Guide.sectionMap.
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

-- Returns item key -> { section, index } for where every item is now.
local function locate(sections)
  local where = {}
  for s, ids in pairs(sections) do
    for index, id in ipairs(ids) do where[id] = { section = s, index = index } end
  end
  return where
end

-- Returns how many custom tabs the bank has now.
local function tabCount(sections)
  local count = 0
  for s in pairs(sections) do if s > count then count = s end end
  return count
end

-- Plans the next Swap move in one tab: the first slot holding the wrong
-- item is swapped with the slot further on that holds the right one.
-- Returns { move, swapWith } or nil when the tab is in order.
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

-- Counts the swaps needed to turn current into target. Each cycle of items
-- that are in each other's places takes (cycle length - 1) swaps, so the
-- total is the number of items minus the number of cycles.
function Guide.swapCount(current, target)
  local position = {}
  for index, id in ipairs(target) do position[id] = index end
  local visited, cycles, n = {}, 0, 0
  for index, id in ipairs(current) do
    if position[id] then
      n = n + 1
      if not visited[index] then
        cycles = cycles + 1
        -- Follow the cycle: where should the item in this slot go?
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

-- Lists every item that is in the wrong tab, as candidates for a tab move.
--   focus  optional bank tab to limit the list to (My tabs, one tab viewed)
-- Sorted by the tab they are in now, then by position, so the infinity tab
-- is emptied top down first and then each tab in turn.
local function crossCandidates(sections, destinations, map, focus)
  local where, list = locate(sections), {}
  for d = 0, lastDestination(destinations) do
    local section = map[d]
    for _, entry in ipairs(section and destinations[d] or {}) do
      local here = where[entry.id]
      if here and here.section ~= section and (focus == nil or here.section == focus) then
        list[#list + 1] = { id = entry.id, from = here.section, index = here.index, to = section, destination = d }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.from ~= b.from then return a.from < b.from end
    return a.index < b.index
  end)
  return list
end

-- Returns the next tab move, or nil. An item can only go to an existing tab
-- or to the very next new one (the + button), so candidates for tabs that
-- do not exist yet wait until earlier tabs are started.
local function crossMove(sections, destinations, map, focus)
  local tabs = tabCount(sections)
  for _, c in ipairs(crossCandidates(sections, destinations, map, focus)) do
    if c.to <= tabs + 1 then
      return { kind = c.to > tabs and "new-tab" or "to-tab", id = c.id, from = c.from, to = c.to, destination = c.destination }
    end
  end
  return nil
end

-- Returns the next move that orders one tab (s), in the given mode, or nil.
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

-- Removes items that are not in the plan (ignored items) from every tab, so
-- the planner works around them without ever moving them.
local function onlyPlanned(sections, destinations)
  local planned = {}
  for d, entries in pairs(destinations) do
    if type(d) == "number" then for _, entry in ipairs(entries) do planned[entry.id] = true end end
  end
  local out = {}
  for s, ids in pairs(sections) do
    local list = {}
    for _, id in ipairs(ids) do if planned[id] then list[#list + 1] = id end end
    out[s] = list
  end
  return out
end

-- Returns the next move for the player and what phase the guide is in.
--   sections      the bank now
--   destinations  the blueprint
--   mode          Guide.INSERT or Guide.SWAP
--   focus         optional bank tab to work on (My tabs)
-- Returns (step, "moving") for a tab move, (step, "sorting") for a move
-- inside a tab, or (nil, "done").
function Guide.next(sections, destinations, mode, focus)
  sections = onlyPlanned(sections, destinations)
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

-- Counts every move left: tab moves plus the moves to order each tab once
-- all items have arrived. Used for "(n left)" and the status card.
function Guide.remaining(sections, destinations, mode, focus)
  sections = onlyPlanned(sections, destinations)
  local targets, map = Guide.targetSections(destinations)
  -- Which bank tab each planned item belongs in.
  local targetSectionOf, after, total = {}, {}, 0
  for dest, section in pairs(map) do
    for _, entry in ipairs(destinations[dest] or {}) do targetSectionOf[entry.id] = section end
  end
  -- Start each tab with the items already in the right tab, in their order.
  for s in pairs(targets) do after[s] = {} end
  for s, ids in pairs(sections) do
    for _, id in ipairs(ids) do
      if targetSectionOf[id] == s and after[s] then table.insert(after[s], id) end
    end
  end
  -- Count the tab moves the same way the guide makes them: one at a time,
  -- new tabs only once the previous one exists. Arriving items go to the
  -- end of their tab, as dropping on a tab button does.
  local pending, tabs = crossCandidates(sections, destinations, map, focus), tabCount(sections)
  local done = {}
  for _ = 1, #pending do
    for index, c in ipairs(pending) do
      if not done[index] and c.to <= tabs + 1 then
        done[index], total = true, total + 1
        if c.to > tabs then tabs = c.to end
        after[c.to] = after[c.to] or {}
        table.insert(after[c.to], c.id)
        break
      end
    end
  end
  -- Then add the moves that order each tab.
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
