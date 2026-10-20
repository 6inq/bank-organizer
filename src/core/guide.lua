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

local function crossMove(sections, destinations, map, focus)
  local tabs = tabCount(sections)
  for _, c in ipairs(crossCandidates(sections, destinations, map, focus)) do
    if c.to <= tabs + 1 then
      return { kind = c.to > tabs and "new-tab" or "to-tab", id = c.id, from = c.from, to = c.to, destination = c.destination }
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

function Guide.remaining(sections, destinations, mode, focus)
  sections = onlyPlanned(sections, destinations)
  local targets, map = Guide.targetSections(destinations)
  local targetSectionOf, after, total = {}, {}, 0
  for dest, section in pairs(map) do
    for _, entry in ipairs(destinations[dest] or {}) do targetSectionOf[entry.id] = section end
  end
  for s in pairs(targets) do after[s] = {} end
  for s, ids in pairs(sections) do
    for _, id in ipairs(ids) do
      if targetSectionOf[id] == s and after[s] then table.insert(after[s], id) end
    end
  end
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
