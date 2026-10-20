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

local function direct(mode, focus)
  return mode ~= Guide.SWAP and (focus == nil or focus == 0)
end

local function crossMove(sections, destinations, map, focus, mode, targets)
  local where = locate(sections)
  local tabs = tabCount(sections)
  local best
  for d = 0, lastDestination(destinations) do
    local section = map[d]
    for _, entry in ipairs(section and destinations[d] or {}) do
      local here = where[entry.id]
      local reachable = section and section <= tabs + 1
      if here and reachable and here.section ~= section and (focus == nil or here.section == focus) then
        if not direct(mode, focus) and focus == nil then
          if not best then best = { here = here, entry = entry, section = section, d = d } end
        elseif not best or here.section < best.here.section
          or (here.section == best.here.section and here.index < best.here.index) then
          best = { here = here, entry = entry, section = section, d = d }
        end
      end
    end
  end
  if not best then return nil end
  if direct(mode, focus) and best.section <= tabs then
    local anchor = Order.anchorFor(sections[best.section] or {}, targets[best.section], best.entry.id)
    if anchor then
      return { kind = "insert", section = best.section, move = best.entry.id, before = anchor.before, after = anchor.after,
        from = best.here.section, to = best.section, destination = best.d }
    end
  end
  local kind = best.section > tabs and "new-tab" or "to-tab"
  return { kind = kind, id = best.entry.id, from = best.here.section, to = best.section, destination = best.d }
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
  local cross = crossMove(sections, destinations, map, focus, mode, targets)
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

local function directRemaining(sections, targets, map, destinations, focus)
  local where, total = locate(sections), 0
  local targetSectionOf = {}
  for dest, section in pairs(map) do
    for _, entry in ipairs(destinations[dest] or {}) do targetSectionOf[entry.id] = section end
  end
  for id, here in pairs(where) do
    local target = targetSectionOf[id]
    if target and target ~= here.section and (focus == nil or here.section == focus) then total = total + 1 end
  end
  for s, target in pairs(targets) do
    if focus == nil or s == focus then
      local inPlace = {}
      for _, id in ipairs(sections[s] or {}) do if targetSectionOf[id] == s then inPlace[#inPlace + 1] = id end end
      local move = Order.nextMove(inPlace, target)
      total = total + (move and move.remaining or 0)
    end
  end
  return total
end

function Guide.remaining(sections, destinations, mode, focus)
  sections = onlyPlanned(sections, destinations)
  local targets, map = Guide.targetSections(destinations)
  if direct(mode, focus) then return directRemaining(sections, targets, map, destinations, focus) end
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
