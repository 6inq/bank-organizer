local Tags = require("src/core/tags")
local Classify = require("src/core/classify")
local Sorting = require("src/core/sorting")
local Placement = require("src/core/placement")

local Blueprint = {}

function Blueprint.compare(a, b)
  local ga, gb = a.group or Placement.NORMAL, b.group or Placement.NORMAL
  if ga ~= gb then return ga < gb end
  return Sorting.compare(a, b)
end

function Blueprint.smart(mode)
  return mode == nil or mode == "smart"
end

local function markOf(opts, item)
  return opts and opts.markOf and opts.markOf(item) or nil
end

local function entryFor(item, tag, d, rank, mode, opts)
  local mark = markOf(opts, item)
  local entry = { slot = item.slot, id = item.id, objectId = item.objectId or item.id, name = item.name, quantity = item.quantity,
    tag = tag, destination = d, rank = rank, mark = mark, group = Placement.group(mark, tag) }
  entry.keys = Sorting.keys(entry, item.info, mode)
  local decant = opts and opts.decant and opts.decant[item.id]
  if decant and not decant.canDecant and Blueprint.smart(mode) and Sorting.isHerblore(tag) then entry.keys[2] = math.huge end
  return entry
end

local function finish(destinations, last, mode, opts)
  for d = 0, last do
    if Blueprint.smart(mode) then Sorting.groupHerblore(destinations[d]) end
    table.sort(destinations[d], Blueprint.compare)
    if opts and opts.vertical and opts.columns and mode ~= "keep" then
      destinations[d] = Sorting.vertical(destinations[d], opts.columns)
    end
  end
end

function Blueprint.build(items, layout, tagOf, mode, opts)
  local destinations, bySlot = {}, {}
  local last = layout:last()
  for d = 0, last do destinations[d] = {} end
  for _, item in ipairs(items) do
    local tag = tagOf(item)
    local d, rank = layout:rankOf(tag)
    if Placement.toInfinity(markOf(opts, item), tag) then d = 0 end
    local entry = entryFor(item, tag, d, rank, mode, opts)
    table.insert(destinations[d], entry)
    bySlot[item.slot] = entry
  end
  finish(destinations, last, mode, opts)
  return destinations, bySlot
end

Blueprint.MIN_TO_ROUTE = 2

local function tagCounts(items, sectionOf, tagOf)
  local counts, tags = {}, {}
  for _, item in ipairs(items) do
    local tag = tagOf(item)
    tags[item.id] = tag
    local s = sectionOf[item.id]
    if s and s > 0 then
      counts[s] = counts[s] or {}
      counts[s][tag] = (counts[s][tag] or 0) + 1
    end
  end
  return counts, tags
end

function Blueprint.tagHomes(counts)
  local homes = {}
  for s, byTag in pairs(counts) do
    for tag, count in pairs(byTag) do
      local best = homes[tag]
      if tag ~= Tags.FALLBACK and count >= Blueprint.MIN_TO_ROUTE
        and (not best or count > best.count or (count == best.count and s < best.section)) then
        homes[tag] = { section = s, count = count }
      end
    end
  end
  return homes
end

function Blueprint.profile(counts, s, limit)
  local list = {}
  for tag, count in pairs(counts[s] or {}) do list[#list + 1] = { tag = tag, count = count } end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.tag < b.tag
  end)
  for index = #list, (limit or 3) + 1, -1 do list[index] = nil end
  return list
end

function Blueprint.orderFor(order, last)
  local positionOf = {}
  for s = 1, last do positionOf[s] = s end
  if type(order) ~= "table" or #order ~= last then return positionOf, false end
  local seen = {}
  for position, s in ipairs(order) do
    if s < 1 or s > last or seen[s] then
      for t = 1, last do positionOf[t] = t end
      return positionOf, false
    end
    seen[s], positionOf[s] = true, position
  end
  return positionOf, true
end

function Blueprint.buildFromTabs(items, sections, tagOf, pinned, order, mode, opts)
  local sectionOf, last = {}, 0
  for s, ids in pairs(sections) do
    if s > last then last = s end
    for _, id in ipairs(ids) do sectionOf[id] = s end
  end
  local counts, tags = tagCounts(items, sectionOf, tagOf)
  local homes = Blueprint.tagHomes(counts)
  local positionOf = Blueprint.orderFor(order, last)
  positionOf[0] = 0
  local destinations, bySlot = { identity = true }, {}
  for s = 0, last do destinations[s] = {} end
  for _, item in ipairs(items) do
    local tag, here = tags[item.id], sectionOf[item.id] or 0
    local pin = pinned and pinned[tag]
    local d = positionOf[here] or here
    if Placement.toInfinity(markOf(opts, item), tag) then
      d = 0
    elseif pin and pin <= last then
      d = pin
    elseif here == 0 and homes[tag] then
      d = positionOf[homes[tag].section]
    end
    local entry = entryFor(item, tag, d, Tags.byKey[tag] and Tags.byKey[tag].index or math.huge, mode, opts)
    table.insert(destinations[d], entry)
    bySlot[item.slot] = entry
  end
  finish(destinations, last, mode, opts)
  return destinations, bySlot, counts, homes
end

function Blueprint.keepOrder(destinations, sectionOf, sectionMap)
  for d, entries in pairs(destinations) do
    if type(d) == "number" then
      for _, entry in ipairs(entries) do
        local arrived = (sectionOf[entry.id] or 0) ~= (sectionMap[d] or d) and 1 or 0
        entry.keys = { arrived, entry.slot }
      end
      table.sort(entries, Sorting.compare)
    end
  end
end

function Blueprint.resolver(corrections)
  return function(item)
    local corrected = corrections and corrections[item.objectId or item.id]
    if corrected and Tags.isValid(corrected) then return corrected end
    return Classify.classify(item.info) or Tags.FALLBACK
  end
end

function Blueprint.usedDestinations(destinations)
  local used = {}
  local d = 0
  while destinations[d] do
    if #destinations[d] > 0 then used[#used + 1] = d end
    d = d + 1
  end
  return used
end

return Blueprint
