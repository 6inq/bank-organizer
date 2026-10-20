-- Builds the blueprint: the ordered contents of Main and Tabs 1-9 for the items you own. Pure.
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

---@param items table[] { slot, id, name, quantity, info } one per bank slot
---@param layout table Layout
---@param tagOf fun(item): string tag for an item (corrections, then classifier, then fallback)
---@return table { [0..9] = { entries } }, table entry by slot
function Blueprint.build(items, layout, tagOf)
  local destinations, bySlot = {}, {}
  for d = 0, Tags.DESTINATIONS - 1 do destinations[d] = {} end
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
  for d = 0, Tags.DESTINATIONS - 1 do
    table.sort(destinations[d], function(a, b)
      if a.rank ~= b.rank then return a.rank < b.rank end
      if a.primary ~= b.primary then return a.primary < b.primary end
      if a.family ~= b.family then return a.family < b.family end
      if a.secondary ~= b.secondary then return a.secondary < b.secondary end
      if a.id ~= b.id then return a.id < b.id end
      return a.slot < b.slot
    end)
  end
  return destinations, bySlot
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
  for d = 0, Tags.DESTINATIONS - 1 do
    if #destinations[d] > 0 then used[#used + 1] = d end
  end
  return used
end

return Blueprint
