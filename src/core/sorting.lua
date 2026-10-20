local Classify = require("src/core/classify")

local Sorting = {}

Sorting.MODES = {
  { key = "smart", label = "Smart (style, slot, tier)" },
  { key = "name", label = "Name" },
  { key = "id", label = "Item ID" },
  { key = "keep", label = "Keep my order (only move between tabs)" },
}
Sorting.DEFAULT = "smart"

function Sorting.isMode(mode)
  for _, entry in ipairs(Sorting.MODES) do if entry.key == mode then return true end end
  return false
end

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

local GEM_ORDER = { "opal", "jade", "red topaz", "sapphire", "emerald", "ruby", "diamond", "dragonstone", "onyx", "hydrix" }

local MATERIALS = {
  { "ore" }, { "bar" }, { "logs" }, { "plank" }, { "hide", "leather" }, { "bones" }, { "ashes" },
  { "essence" }, { "energy" }, { "charm" },
}
local TIERS = {
  "bronze", "iron", "steel", "black", "mithril", "adamant", "rune", "orikalkum", "dragon", "necronium",
  "bane", "elder rune", "primal",
  "oak", "willow", "teak", "maple", "acadia", "mahogany", "yew", "magic", "elder", "eternal",
}

local STYLES = { "melee", "ranged", "magic", "necromancy", "other" }

local STYLE_CATEGORIES = {
  { "NECRO", 4 }, { "LANTERN", 4 },
  { "STAFF", 3 }, { "WAND", 3 }, { "MAGICBOOK", 3 }, { "ORB", 3 },
  { "BOW", 2 }, { "XBOW", 2 }, { "THROWN", 2 }, { "DART", 2 }, { "KNIFE", 2 }, { "GRENADE", 2 },
  { "CHINCHOMPA", 2 }, { "BLOWPIPE", 2 }, { "^AMMO_", 2 }, { "QUIVER", 2 },
  { "SWORD", 1 }, { "SCIMITAR", 1 }, { "DAGGER", 1 }, { "MACE", 1 }, { "MAUL", 1 }, { "WHIP", 1 },
  { "CLAW", 1 }, { "SPEAR", 1 }, { "HALBERD", 1 }, { "BATTLEAXE", 1 }, { "WARHAMMER", 1 },
  { "RAPIER", 1 }, { "FLAIL", 1 }, { "KHOPESH", 1 }, { "SCYTHE", 1 },
}

local STYLE_WORDS = {
  { 4, { "necromancer", "deathwarden", "death guard", "omni guard", "lantern", "nexus", "soulbound", "necro" } },
  { 3, { "robe", "wizard", "mage", "mystic", "ganodermic", "virtus", "tectonic", "subjugation", "seasinger",
    "ahrim", "zuriel", "infinity", "lunar", "elemental", "sorcer", "staff", "wand", "orb", "cywir", "grimoire" } },
  { 2, { "d'hide", "dragonhide", "coif", "chaps", "vambraces", "range", "pernix", "sirenic", "armadyl",
    "karil", "morrigan", "bow", "ascension", "eldritch", "blowpipe", "dart", "knife", "arrow", "bolt",
    "chinchompa", "elven", "quiver" } },
  { 1, { "plate", "full helm", "torva", "bandos", "malevolent", "masterwork", "kyzaj", "scimitar", "sword",
    "whip", "scourge", "mace", "maul", "claws", "defender", "dharok", "verac", "torag", "guthan", "tassets",
    "chestplate", "greaves", "gauntlets", "cuirass", "warpriest", "trials" } },
}

local SLOT_NAMES = { "main hand", "off hand", "head", "body", "legs", "hands", "feet", "cape", "neck", "ring", "ammo", "pocket", "other" }
local SLOT_CATEGORIES = {
  { "^ARMOUR_HELMET", 3 }, { "^ARMOUR_BODY", 4 }, { "^ARMOUR_LEGS", 5 }, { "^ARMOUR_HANDS", 6 }, { "GLOVES", 6 },
  { "^ARMOUR_FEET", 7 }, { "^ARMOUR_CAPE", 8 }, { "AMULET", 9 }, { "NECKLACE", 9 }, { "RING", 10 },
  { "^ARMOUR_SHIELD", 2 }, { "^ARMOUR_WEAPON", 2 }, { "^ARMOUR_SPIKE", 2 }, { "^AMMO_", 11 }, { "QUIVER", 11 },
  { "GOD_BOOK", 12 }, { "^WEAPON_", 1 }, { "NECROMANCY_NEXUS", 1 },
}
local SLOT_WORDS = {
  { 2, { "off-hand", "offhand", "defender", "shield", "kiteshield", "ward", "repriser", "lantern" } },
  { 3, { "helm", "hat", "hood", "mask", "coif", "head", "crown", "tiara", "headband", "goggles" } },
  { 4, { "platebody", "body", "top", "chest", "chestplate", "cuirass", "torso", "jacket", "garb", "shirt" } },
  { 5, { "platelegs", "legs", "chaps", "tassets", "greaves", "skirt", "bottom", "trousers", "legwear", "legguards" } },
  { 6, { "gloves", "gauntlets", "vambraces", "bracer", "hands", "arms" } },
  { 7, { "boots", "shoes", "feet", "sandals" } },
  { 8, { "cape", "cloak" } },
  { 9, { "amulet", "necklace", "pendant", "scarf", "brooch" } },
  { 10, { "ring" } },
  { 11, { "arrows", "bolts", "darts", "knives", "javelins" } },
  { 12, { "scripture", "grimoire", "pocket" } },
}

local function hasWord(text, word)
  return text:find("%f[%w]" .. word:gsub("%p", "%%%0") .. "%f[%W]") ~= nil
end

local function anyWord(text, words)
  for _, word in ipairs(words) do if hasWord(text, word) then return true end end
  return false
end

local function indexIn(list, name)
  for index, word in ipairs(list) do
    if hasWord(name, word) then return index end
  end
  return #list + 1
end

local function fromCategory(category, rules)
  for _, rule in ipairs(rules) do
    if category:match(rule[1]) then return rule[2] end
  end
  return nil
end

local function fromWords(name, rules)
  for _, rule in ipairs(rules) do
    if anyWord(name, rule[2]) then return rule[1] end
  end
  return nil
end

function Sorting.style(name, category)
  name, category = (name or ""):lower(), category or ""
  return fromCategory(category, STYLE_CATEGORIES) or fromWords(name, STYLE_WORDS) or #STYLES
end

function Sorting.slot(name, category)
  name, category = (name or ""):lower(), category or ""
  return fromWords(name, { SLOT_WORDS[1] }) or fromCategory(category, SLOT_CATEGORIES)
    or fromWords(name, SLOT_WORDS) or #SLOT_NAMES
end

Sorting.STYLES, Sorting.SLOTS = STYLES, SLOT_NAMES

local function setName(name, category)
  if category ~= "" then return category:lower() end
  local words = {}
  for word in name:gmatch("%S+") do words[#words + 1] = word end
  if #words > 1 then words[#words] = nil end
  return table.concat(words, " ")
end

local function materialOf(name)
  for index, words in ipairs(MATERIALS) do
    if anyWord(name, words) then return index end
  end
  return #MATERIALS + 1
end

local CHAINS = {
  { "irit", "super attack", "avantoe", "extreme attack", "kwuarm", "super strength", "extreme strength",
    "cadantine", "super defence", "extreme defence", "dwarf weed", "super ranging", "grenwall spikes",
    "extreme ranging", "lantadyme", "super magic", "ground mud runes", "extreme magic", "spirit weed",
    "congealed blood", "super necromancy", "ground miasma rune", "extreme necromancy", "torstol", "overload",
    "primal fruit pulp" },
  { "ranarr", "snape grass", "prayer potion", "snapdragon", "red spiders' eggs", "super restore", "super prayer",
    "fellstalk", "morchella mushroom", "prayer renewal", "wyvern bonemeal" },
  { "toadflax", "crushed nest", "saradomin brew", "super saradomin brew" },
  { "dragon scale dust", "antifire", "super antifire", "phoenix feather" },
  { "bloodweed", "adrenaline", "replenishment", "adrenaline crystal" },
  { "marrentill", "unicorn horn dust", "antipoison", "antipoison+", "super antipoison", "antipoison++",
    "poison ivy berries", "coconut", "cactus spine" },
  { "harralander", "chocolate dust", "energy potion", "super energy", "stamina" },
  { "guam", "eye of newt", "attack potion", "tarromin", "limpwurt root", "strength potion", "defence potion",
    "white berries", "ranging potion", "wine of zamorak", "magic potion", "potato cactus", "combat potion",
    "goat horn dust" },
  { "aggression", "searing ashes", "powerburst", "perfect plus", "perfect juju", "juju", "spirit attraction",
    "weapon poison", "bomb", "incense" },
}

local HERBLORE_STAGE = {
  ["grimy-herbs"] = 1, ["clean-herbs"] = 2, ["unfinished-potions"] = 3, ["secondaries"] = 4,
  ["potions"] = 5, ["potion-doses"] = 5, ["herblore-other"] = 6,
}

function Sorting.isHerblore(tag)
  return HERBLORE_STAGE[tag] ~= nil
end

function Sorting.chain(name)
  name = (name or ""):lower()
  for group, members in ipairs(CHAINS) do
    local best, length = nil, 0
    for index, member in ipairs(members) do
      if #member > length and hasWord(name, member) then best, length = index, #member end
    end
    if best then return group, best end
  end
  return #CHAINS + 1, indexIn(HERB_ORDER, name)
end

local function herbloreKeys(tag, name)
  local group, member = Sorting.chain(name)
  return { group, member, HERBLORE_STAGE[tag], -(Classify.dose(name) or 0), (name:gsub("%s*%(%d%)%s*$", "")) }
end

function Sorting.groupHerblore(entries)
  local rank
  for _, entry in ipairs(entries) do
    if Sorting.isHerblore(entry.tag) and type(entry.keys[1]) == "number" and (rank == nil or entry.keys[1] < rank) then
      rank = entry.keys[1]
    end
  end
  if rank == nil then return end
  for _, entry in ipairs(entries) do
    if Sorting.isHerblore(entry.tag) then entry.keys[1] = rank end
  end
end

local function smartKeys(tag, name, info)
  if Sorting.isHerblore(tag) then return herbloreKeys(tag, name) end
  local category = info.category or ""
  local value = -(tonumber(info.cost) or 0)
  if tag == "gear" or tag == "ammunition" then
    return { Sorting.style(name, category), Sorting.slot(name, category), value }
  end
  if tag == "skilling-outfits" then return { setName(name, category), Sorting.slot(name, category), 0 } end
  if tag == "runes" then return { indexIn(RUNE_ORDER, name), "", 0 } end
  if tag == "grimy-herbs" or tag == "clean-herbs" or tag == "herb-seeds" or tag == "unfinished-potions" then
    return { indexIn(HERB_ORDER, name), "", 0 }
  end
  if tag == "potions" or tag == "potion-doses" then
    return { 0, (name:gsub("%s*%(%d%)%s*$", "")), -(Classify.dose(name) or 0) }
  end
  if tag == "gems" then return { indexIn(GEM_ORDER, name), name:find("uncut", 1, true) and 0 or 1, 0 } end
  if tag == "raw-resources" then return { materialOf(name), indexIn(TIERS, name), 0 } end
  return { 0, "", 0 }
end

function Sorting.keys(entry, info, mode)
  local name = (entry.name or ""):lower()
  if mode == "id" then return { entry.rank, entry.id } end
  if mode == "name" then return { entry.rank, name, entry.id } end
  local keys = { entry.rank }
  for _, key in ipairs(smartKeys(entry.tag, name, info or {})) do keys[#keys + 1] = key end
  keys[#keys + 1] = name
  keys[#keys + 1] = entry.id
  return keys
end

function Sorting.compare(a, b)
  local ka, kb = a.keys, b.keys
  for index = 1, math.max(#ka, #kb) do
    local x, y = ka[index], kb[index]
    if x ~= y then
      if x == nil then return true end
      if y == nil then return false end
      if type(x) ~= type(y) then return type(x) < type(y) end
      return x < y
    end
  end
  return a.slot < b.slot
end

return Sorting
