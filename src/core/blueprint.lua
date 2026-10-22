-- Bank Organizer: the blueprint, which says where every item belongs.
--
-- Analyze Bank reads the bank and hands the items here. The blueprint gives
-- each item a kind (src/core/tags.lua), a destination tab and a place inside
-- that tab. The Sorting Guide (src/core/guide.lua) then plans the moves that
-- turn the real bank into the blueprint.
--
-- There are two ways to build it:
--   Blueprint.build          Whole bank: follow the player's Tab Layout
--   Blueprint.buildFromTabs  My tabs: keep the player's own tabs, route loose
--                            items to the tab that already holds most of
--                            their kind, and honour pins
-- Both return destinations: tab position -> ordered list of planned entries.

local Tags = require("src/core/tags")
local Classify = require("src/core/classify")
local Sorting = require("src/core/sorting")
local Placement = require("src/core/placement")
local Custom = require("src/core/custom")

local Blueprint = {}

-- Orders two planned entries in the same tab: tag placement group first
-- (see src/core/placement.lua), then the sort keys.
function Blueprint.compare(a, b)
  local ga, gb = a.group or Placement.NORMAL, b.group or Placement.NORMAL
  if ga ~= gb then return ga < gb end
  return Sorting.compare(a, b)
end

-- Returns true for the Smart sort mode (nil also means Smart).
function Blueprint.smart(mode)
  return mode == nil or mode == "smart"
end

-- Returns an item's set of tags using the build options, or nil.
--   opts.tagsOf  function(item) -> { [tag key] = true } or nil
local function tagsOf(opts, item)
  return opts and opts.tagsOf and opts.tagsOf(item) or nil
end

-- Works out what an item's tags mean (see Placement.resolve).
local function resolve(opts, item, tag)
  return Placement.resolve(tagsOf(opts, item), tag, opts and opts.order)
end

-- Builds the planned entry for one item.
--   item   an item from the bank reader { slot, id, objectId, name, quantity, info }
--   tag    its kind of item
--   d      its destination tab position
--   rank   its kind's place in that tab's list (sorts kinds in layout order)
--   mode   the sort mode
--   opts   build options (see Blueprint.build)
--   placed the Placement.resolve result for the item
local function entryFor(item, tag, d, rank, mode, opts, placed)
  local entry = { slot = item.slot, id = item.id, objectId = item.objectId or item.id, name = item.name, quantity = item.quantity,
    tag = tag, destination = d, rank = rank, group = placed.group, placement = placed.move and placed.move.key }
  entry.keys = Sorting.keys(entry, item.info, mode, { secondaries = opts and opts.secondaries })
  -- With decant labels on, part doses that cannot be combined into a full
  -- potion sink to the bottom of the herblore part of their tab. The second
  -- key is the herblore band (see src/core/sorting.lua); math.huge puts it
  -- after every band.
  local decant = opts and opts.decant and opts.decant[item.id]
  if decant and not decant.canDecant and Blueprint.smart(mode) and Sorting.isHerblore(tag) then entry.keys[2] = math.huge end
  return entry
end

-- Sorts every tab's entries and applies vertical order when asked.
--   destinations  tab position -> list of entries (changed in place)
--   last          the last tab position
local function finish(destinations, last, mode, opts)
  for d = 0, last do
    if Blueprint.smart(mode) then Sorting.groupHerblore(destinations[d]) end
    table.sort(destinations[d], Blueprint.compare)
    -- Keep my order never reorders, so vertical order does not apply to it.
    if opts and opts.vertical and opts.columns and mode ~= "keep" then
      destinations[d] = Sorting.vertical(destinations[d], opts.columns)
    end
  end
end

-- Builds the Whole bank blueprint from the Tab Layout.
--   items   bank items (see entryFor)
--   layout  a Layout (src/core/layout.lua)
--   tagOf   function(item) -> kind key
--   mode    sort mode
--   opts    optional table:
--             tagsOf       function(item) -> set of tags
--             order        tag priority list
--             decant       Sorting.decantInfo result, only when decant
--                          labels are on
--             secondaries  "with" or "bottom"
--             vertical     true to fill tabs column by column
--             columns      slots per bank row (needed for vertical)
-- Returns destinations (position -> entries) and bySlot (slot -> entry).
function Blueprint.build(items, layout, tagOf, mode, opts)
  local destinations, bySlot = {}, {}
  local last = layout:last()
  for d = 0, last do destinations[d] = {} end
  for _, item in ipairs(items) do
    local tag = tagOf(item)
    local d, rank = layout:rankOf(tag)
    local placed = resolve(opts, item, tag)
    -- Tags that send items to the infinity tab beat the layout.
    if placed.infinity then d = 0 end
    local entry = entryFor(item, tag, d, rank, mode, opts, placed)
    table.insert(destinations[d], entry)
    bySlot[item.slot] = entry
  end
  finish(destinations, last, mode, opts)
  return destinations, bySlot
end

-- My tabs only routes a loose kind to a tab that already holds at least
-- this many items of that kind, so one stray item does not claim a tab.
Blueprint.MIN_TO_ROUTE = 2

-- Counts how many items of each kind each custom tab holds.
--   sectionOf  item key -> current tab position
-- Returns counts (position -> kind -> count) and tags (item key -> kind).
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

-- Picks the automatic home tab of each kind: the tab holding the most items
-- of that kind (at least MIN_TO_ROUTE), the leftmost tab on a tie. Storage &
-- Cleanup never gets a home; its items stay put.
-- Returns kind -> { section, count }.
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

-- Returns the most common kinds in one tab, most common first (ties by key),
-- at most limit of them (default 3). Used for tab summaries in the sidebar.
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

-- Turns a requested tab order into "tab -> new position".
--   order  list where order[position] = tab, or nil
--   last   the last tab position
-- Returns the map and true, or the identity map and false when the order is
-- missing or invalid.
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

-- Builds the My tabs blueprint from the player's own tabs.
--   items     bank items
--   sections  tab position -> list of item keys, as shown on screen
--   tagOf     function(item) -> kind key
--   pinned    kind -> tab position (pins); may be nil
--   order     optional tab order (see Blueprint.orderFor)
--   mode      sort mode
--   opts      see Blueprint.build
-- An item's destination is decided in this order:
--   1. a tag that sends it to the infinity tab
--   2. a pin for its kind
--   3. if it sits in the infinity tab, its kind's automatic home tab
--   4. otherwise, the tab it is already in
-- Returns destinations, bySlot, counts and homes.
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
  -- identity marks a My tabs plan, where positions are the player's own tabs.
  local destinations, bySlot = { identity = true }, {}
  for s = 0, last do destinations[s] = {} end
  for _, item in ipairs(items) do
    local tag, here = tags[item.id], sectionOf[item.id] or 0
    local pin = pinned and pinned[tag]
    local d = positionOf[here] or here
    local placed = resolve(opts, item, tag)
    if placed.infinity then
      d = 0
    elseif pin and pin <= last then
      d = pin
    elseif here == 0 and homes[tag] then
      d = positionOf[homes[tag].section]
    end
    local entry = entryFor(item, tag, d, Tags.byKey[tag] and Tags.byKey[tag].index or math.huge, mode, opts, placed)
    table.insert(destinations[d], entry)
    bySlot[item.slot] = entry
  end
  finish(destinations, last, mode, opts)
  return destinations, bySlot, counts, homes
end

-- Keep my order: items already in their destination keep their current
-- order, and items arriving from another tab go after them.
--   destinations  the plan to adjust (changed in place)
--   sectionOf     item key -> tab position it is in now
--   sectionMap    destination position -> the tab position it maps to
function Blueprint.keepOrder(destinations, sectionOf, sectionMap)
  for d, entries in pairs(destinations) do
    -- destinations also holds the identity flag; only number keys are tabs.
    if type(d) == "number" then
      for _, entry in ipairs(entries) do
        local arrived = (sectionOf[entry.id] or 0) ~= (sectionMap[d] or d) and 1 or 0
        entry.keys = { arrived, entry.slot }
      end
      table.sort(entries, Sorting.compare)
    end
  end
end

-- Returns the function that decides each item's kind.
--   corrections  item id -> kind the player picked by hand
--   custom       optional { categories, excluded } for custom name rules
-- The order of precedence is:
--   1. the player's own choice (from the Tags window)
--   2. a custom category's name rules (unless the item was removed from
--      that category's review list)
--   3. the built-in classifier
--   4. Storage & Cleanup
function Blueprint.resolver(corrections, custom)
  return function(item)
    local objectId = item.objectId or item.id
    local corrected = corrections and corrections[objectId]
    if corrected and Tags.isValid(corrected) then return corrected end
    if custom then
      local matched = Custom.categoryFor(item.name, objectId, custom.categories, custom.excluded)
      if matched and Tags.isValid(matched) then return matched end
    end
    return Classify.classify(item.info) or Tags.FALLBACK
  end
end

-- Returns the tab positions that have at least one planned item, in order.
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
