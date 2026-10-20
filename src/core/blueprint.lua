-- Builds the blueprint: the ordered contents of each tab in your layout for the items you own. Pure.
-- Never invents items or empty slots: only real bank slots (including placeholders) are placed.
local Tags = require("src/core/tags")
local Classify = require("src/core/classify")

local Blueprint = {}

local RUNE_ORDER = {
  "air", "water", "earth", "fire", "mind", "body", "cosmic", "chaos", "nature", "law", "death",
  "astral", "blood", "soul", "armadyl", "time", "light", "dark", "necrotic", "spirit", "bone",
  "flesh", "miasma", "mist", "dust", "mud", "smoke", "steam", "lava",
}

local HERB_ORDER = {
  "guam", "marrentill", "tarromin", "harralander", "ranarr", "toadflax", "spirit weed", "irit",
  "wergali", "avantoe", "kwuarm", "bloodweed", "snapdragon", "cadantine", "lantadyme",
  "dwarf weed", "torstol", "fellstalk", "arbuck",
}

local function indexIn(list, name)
  for index, word in ipairs(list) do
    if name:find(word, 1, true) then return index end
  end
  return #list + 1
end

-- Sort key inside a tag: family first, then a stage/dose order, then name, then id.
local function sortKey(tag, name)
  name = (name or ""):lower()
  if tag == "runes" then return indexIn(RUNE_ORDER, name), 0 end
  if tag == "grimy-herbs" or tag == "clean-herbs" or tag == "herb-seeds" or tag == "unfinished-potions" then
    return indexIn(HERB_ORDER, name), 0
  end
  if tag == "potions" or tag == "potion-doses" then
    return 0, -(Classify.dose(name) or 0) -- families stay together via the name key below
  end
  return 0, 0
end

-- Potion family without the dose suffix, so (4) (3) (2) (1) sit together.
local function familyName(tag, name)
  name = (name or ""):lower()
  if tag == "potions" or tag == "potion-doses" then return (name:gsub("%s*%(%d%)%s*$", "")) end
  return name
end

-- Order within a destination: tag order, then family/stage, then name, dose, id.
function Blueprint.compare(a, b)
  if a.rank ~= b.rank then return a.rank < b.rank end
  if a.primary ~= b.primary then return a.primary < b.primary end
  if a.family ~= b.family then return a.family < b.family end
  if a.secondary ~= b.secondary then return a.secondary < b.secondary end
  if a.id ~= b.id then return a.id < b.id end
  return a.slot < b.slot
end

---@param items table[] { slot, id, name, quantity, info } one per bank slot
---@param layout table Layout
---@param tagOf fun(item): string tag for an item (corrections, then classifier, then fallback)
---@return table { [0..9] = { entries } }, table entry by slot
function Blueprint.build(items, layout, tagOf)
  local destinations, bySlot = {}, {}
  local last = layout:last()
  for d = 0, last do destinations[d] = {} end
  for _, item in ipairs(items) do
    local tag = tagOf(item)
    local d, rank = layout:rankOf(tag)
    local primary, secondary = sortKey(tag, item.name)
    local entry = {
      slot = item.slot, id = item.id, name = item.name, quantity = item.quantity, tag = tag,
      destination = d, rank = rank, primary = primary, secondary = secondary, family = familyName(tag, item.name),
    }
    table.insert(destinations[d], entry)
    bySlot[item.slot] = entry
  end
  for d = 0, last do table.sort(destinations[d], Blueprint.compare) end
  return destinations, bySlot
end

-- "My tabs": keep the player's own tabs. Items already in a custom tab stay there; items in the
-- main (infinity) tab move to the custom tab that already holds the most items of their kind
-- (at least MIN_TO_ROUTE of them); anything else stays in the main tab as misc.
-- A tag the player pinned to a tab overrides all of that: every item of it goes to that tab.
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

-- For each tag, the custom tab holding most items of it (ties go to the earlier tab).
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

-- The kinds of item a tab mostly holds, most common first (for the legend).
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

---@param sections table { [0..n] = { id, ... } } the bank as it is now
---@param pinned table? { [tag] = section } the player's own choices
---@return table destinations keyed 0..n with identity = true, table entry by slot, table counts, table homes
function Blueprint.buildFromTabs(items, sections, tagOf, pinned)
  local sectionOf, last = {}, 0
  for s, ids in pairs(sections) do
    if s > last then last = s end
    for _, id in ipairs(ids) do sectionOf[id] = s end
  end
  local counts, tags = tagCounts(items, sectionOf, tagOf)
  local homes = Blueprint.tagHomes(counts)
  local destinations, bySlot = { identity = true }, {}
  for s = 0, last do destinations[s] = {} end
  for _, item in ipairs(items) do
    local tag, here = tags[item.id], sectionOf[item.id] or 0
    local pin = pinned and pinned[tag]
    local d = here
    if pin and pin <= last then
      d = pin
    elseif here == 0 and homes[tag] then
      d = homes[tag].section
    end
    local primary, secondary = sortKey(tag, item.name)
    local entry = {
      slot = item.slot, id = item.id, name = item.name, quantity = item.quantity, tag = tag, destination = d,
      rank = Tags.byKey[tag] and Tags.byKey[tag].index or math.huge, primary = primary, secondary = secondary,
      family = familyName(tag, item.name),
    }
    table.insert(destinations[d], entry)
    bySlot[item.slot] = entry
  end
  for s = 0, last do table.sort(destinations[s], Blueprint.compare) end
  return destinations, bySlot, counts, homes
end

-- Default tag resolution: your correction wins, then the classifier, else Storage & Cleanup.
function Blueprint.resolver(corrections)
  return function(item)
    local corrected = corrections and corrections[item.id]
    if corrected and Tags.isValid(corrected) then return corrected end
    return Classify.classify(item.info) or Tags.FALLBACK
  end
end

-- Destinations with at least one item; each empty destination is skipped (a bank cannot keep
-- an empty tab), keeping its number and name for display.
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
