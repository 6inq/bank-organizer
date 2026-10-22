-- Bank Organizer: the order items take inside a tab.
--
-- Every planned item gets a list of "sort keys". Two items are compared key
-- by key, left to right, and the first difference decides which comes first
-- (see Sorting.compare). The first key is always the kind's rank in its tab,
-- so kinds stay together in the order the Tab Layout lists them.
--
-- Sort modes:
--   smart     every kind has its own sensible order (this file's main job)
--   name      alphabetical
--   id        by item id
--   value     most valuable first (live GE price, else the game's value)
--   qty-desc  biggest stacks first
--   qty-asc   smallest stacks first
--   keep      never reorder; only move items between tabs (handled in
--             src/core/blueprint.lua)
--
-- Smart herblore is ordered recipe by recipe: for each potion, its grimy
-- herb, clean herb, unfinished potion, secondary, then the potion's vial
-- doses from (1) to (4) and flask doses from (1) to (6). Empty vials and
-- vials of water come before every recipe.

local Classify = require("src/core/classify")

local Sorting = {}

-- The sort modes offered in the sidebar, in menu order.
Sorting.MODES = {
  { key = "smart", label = "Smart" },
  { key = "name", label = "Name" },
  { key = "id", label = "Item ID" },
  { key = "value", label = "Value: item value (highest first)" },
  { key = "qty-desc", label = "Quantity (highest first)" },
  { key = "qty-asc", label = "Quantity (lowest first)" },
  { key = "keep", label = "Keep my order" },
}

-- The mode new players start with.
Sorting.DEFAULT = "smart"

-- The Value label changes to say where prices come from:
--   live     GE prices are loaded
--   loading  the GE Price Library is still downloading prices
--   none     no price library, so the game's own item value is used
Sorting.VALUE_LABELS = {
  live = "Value: GE price (highest first)",
  loading = "Value: item value for now",
  none = "Value: item value (highest first)",
}

-- Returns the mode list with the Value label matching the price source.
function Sorting.modes(priceSource)
  local modes = {}
  for index, entry in ipairs(Sorting.MODES) do
    local label = entry.key == "value" and Sorting.VALUE_LABELS[priceSource] or entry.label
    modes[index] = { key = entry.key, label = label }
  end
  return modes
end

-- Returns an item's worth in coins: the GE price when one was attached,
-- otherwise the game's own item value, otherwise 0.
function Sorting.worth(info)
  if not info then return 0 end
  return tonumber(info.price) or tonumber(info.cost) or 0
end

-- Returns true when mode is one of Sorting.MODES.
function Sorting.isMode(mode)
  for _, entry in ipairs(Sorting.MODES) do if entry.key == mode then return true end end
  return false
end

-- Runes in the order the game's spellbooks and rune pouches use.
local RUNE_ORDER = {
  "air", "water", "earth", "fire", "mind", "body", "cosmic", "chaos", "nature", "law", "death",
  "astral", "blood", "soul", "armadyl", "time", "light", "dark", "necrotic", "spirit", "bone",
  "flesh", "miasma", "mist", "dust", "mud", "smoke", "steam", "lava",
}

-- Herbs by Herblore level, lowest first.
local HERB_ORDER = {
  "guam", "marrentill", "tarromin", "harralander", "ranarr", "toadflax", "spirit weed", "irit",
  "wergali", "avantoe", "kwuarm", "bloodweed", "snapdragon", "cadantine", "lantadyme",
  "dwarf weed", "torstol", "fellstalk", "arbuck",
}

-- Gems by Crafting level, lowest first.
local GEM_ORDER = { "opal", "jade", "red topaz", "sapphire", "emerald", "ruby", "diamond", "dragonstone", "onyx", "hydrix" }

-- Resource families, in the order they are grouped. Each entry lists the
-- words that identify the family.
local MATERIALS = {
  { "ore" }, { "bar" }, { "logs" }, { "plank" }, { "hide", "leather" }, { "bones" }, { "ashes" },
  { "essence" }, { "energy" }, { "charm" },
}

-- Metal and wood tiers, lowest first. Used to order resources and ammo parts.
local TIERS = {
  "bronze", "iron", "steel", "black", "mithril", "adamant", "rune", "orikalkum", "dragon", "necronium",
  "bane", "elder rune", "primal",
  "oak", "willow", "teak", "maple", "acadia", "mahogany", "yew", "magic", "elder", "eternal",
}

-- Combat styles in the order gear is grouped.
local STYLES = { "melee", "ranged", "magic", "necromancy", "other" }

-- Combat style by the game's item category name (pattern, style number).
-- Checked in order; the first match wins.
local STYLE_CATEGORIES = {
  { "NECRO", 4 }, { "LANTERN", 4 },
  { "STAFF", 3 }, { "WAND", 3 }, { "MAGICBOOK", 3 }, { "ORB", 3 },
  { "BOW", 2 }, { "XBOW", 2 }, { "THROWN", 2 }, { "DART", 2 }, { "KNIFE", 2 }, { "GRENADE", 2 },
  { "CHINCHOMPA", 2 }, { "BLOWPIPE", 2 }, { "^AMMO_", 2 }, { "QUIVER", 2 },
  { "SWORD", 1 }, { "SCIMITAR", 1 }, { "DAGGER", 1 }, { "MACE", 1 }, { "MAUL", 1 }, { "WHIP", 1 },
  { "CLAW", 1 }, { "SPEAR", 1 }, { "HALBERD", 1 }, { "BATTLEAXE", 1 }, { "WARHAMMER", 1 },
  { "RAPIER", 1 }, { "FLAIL", 1 }, { "KHOPESH", 1 }, { "SCYTHE", 1 },
}

-- Combat style by words in the item name, for items whose category does not
-- say. Each entry is { style number, list of words }.
local STYLE_WORDS = {
  { 4, { "necromancer", "deathwarden", "death guard", "omni guard", "lantern", "nexus", "soulbound", "necro" } },
  { 3, { "robe", "wizard", "mage", "mystic", "ganodermic", "virtus", "tectonic", "subjugation", "seasinger",
    "ahrim", "zuriel", "infinity", "lunar", "elemental", "sorcer", "staff", "wand", "orb", "cywir", "grimoire" } },
  { 2, { "d'hide", "dragonhide", "coif", "chaps", "vambraces", "range", "pernix", "sirenic", "armadyl",
    "karil", "morrigan", "bow", "ascension", "eldritch", "blowpipe", "dart", "knife", "arrow", "bolt",
    "chinchompa", "elven", "quiver" } },
  { 1, { "plate", "full helm", "torva", "bandos", "malevolent", "masterwork", "kyzaj", "scimitar", "sword",
    "whip", "scourge", "mace", "maul", "claws", "defender", "dharok", "verac", "torag", "guthan", "tassets",
    "chestplate", "greaves", "gauntlets", "cuirass", "warpriest", "trials", "dagger", "longsword", "battleaxe",
    "warhammer", "halberd", "spear", "hasta", "rapier", "khopesh", "flail", "scythe", "claw" } },
}

-- Equipment slots in the order gear is laid out within a style.
local SLOT_NAMES = { "main hand", "off hand", "head", "body", "legs", "hands", "feet", "cape", "neck", "ring", "ammo", "pocket", "other" }

-- Slot by the game's item category name (pattern, slot number).
local SLOT_CATEGORIES = {
  { "^ARMOUR_HELMET", 3 }, { "^ARMOUR_BODY", 4 }, { "^ARMOUR_LEGS", 5 }, { "^ARMOUR_HANDS", 6 }, { "GLOVES", 6 },
  { "^ARMOUR_FEET", 7 }, { "^ARMOUR_CAPE", 8 }, { "AMULET", 9 }, { "NECKLACE", 9 }, { "RING", 10 },
  { "^ARMOUR_SHIELD", 2 }, { "^ARMOUR_WEAPON", 2 }, { "^ARMOUR_SPIKE", 2 }, { "^AMMO_", 11 }, { "QUIVER", 11 },
  { "GOD_BOOK", 12 }, { "^WEAPON_", 1 }, { "NECROMANCY_NEXUS", 1 },
}

-- Slot by words in the item name. The first entry (off-hand words) is also
-- checked before categories, because off-hand weapons share weapon
-- categories with main-hand ones.
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

-- Returns true when word appears in text as a whole word. %f is Lua's
-- frontier pattern: it matches the edge between a non-letter and a letter,
-- so "ring" matches "gold ring" but not "string". Punctuation in the word is
-- escaped so it is matched literally.
local function hasWord(text, word)
  return text:find("%f[%w]" .. word:gsub("%p", "%%%0") .. "%f[%W]") ~= nil
end

-- Returns true when any of the words appears in text as a whole word.
local function anyWord(text, words)
  for _, word in ipairs(words) do if hasWord(text, word) then return true end end
  return false
end

-- Returns the position of the first listed word found in name, or one past
-- the end of the list when none is found (so unknown names sort last).
local function indexIn(list, name)
  for index, word in ipairs(list) do
    if hasWord(name, word) then return index end
  end
  return #list + 1
end

-- Returns the value of the first rule whose pattern matches the category
-- name, or nil. Rules are { pattern, value } pairs.
local function fromCategory(category, rules)
  for _, rule in ipairs(rules) do
    if category:match(rule[1]) then return rule[2] end
  end
  return nil
end

-- Returns the value of the first rule with a word found in name, or nil.
-- Rules are { value, list of words } pairs.
local function fromWords(name, rules)
  for _, rule in ipairs(rules) do
    if anyWord(name, rule[2]) then return rule[1] end
  end
  return nil
end

-- Returns a gear item's combat style number (index into STYLES).
--   name      item name
--   category  the game's item category name, or ""
-- The category is trusted first; name words are the fallback.
function Sorting.style(name, category)
  name, category = (name or ""):lower(), category or ""
  return fromCategory(category, STYLE_CATEGORIES) or fromWords(name, STYLE_WORDS) or #STYLES
end

-- Returns a gear item's slot number (index into SLOT_NAMES). Off-hand words
-- win first, then the category, then the remaining slot words.
function Sorting.slot(name, category)
  name, category = (name or ""):lower(), category or ""
  return fromWords(name, { SLOT_WORDS[1] }) or fromCategory(category, SLOT_CATEGORIES)
    or fromWords(name, SLOT_WORDS) or #SLOT_NAMES
end

-- Exposed so the UI and tests can show style and slot names.
Sorting.STYLES, Sorting.SLOTS = STYLES, SLOT_NAMES

-- Returns the "set name" used to keep skilling outfit pieces together: the
-- item's category when it has one, otherwise the name without its last word
-- ("Lumberjack top" and "Lumberjack legs" both become "lumberjack").
local function setName(name, category)
  if category ~= "" then return category:lower() end
  local words = {}
  for word in name:gmatch("%S+") do words[#words + 1] = word end
  if #words > 1 then words[#words] = nil end
  return table.concat(words, " ")
end

-- Returns the resource family position from MATERIALS, or one past the end.
local function materialOf(name)
  for index, words in ipairs(MATERIALS) do
    if anyWord(name, words) then return index end
  end
  return #MATERIALS + 1
end

-- Herblore "chains": groups of ingredients and potions that belong together,
-- in the order they appear in the bank. Used to place herblore items that
-- are not in the RECIPES table below, so they still land near their family.
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

-- Recipes in bank order: { potion, herb, secondary }. The herb or the
-- secondary may be nil (for example extremes are made from a super potion
-- plus one ingredient). The order follows the chains above: the whole
-- overload family first, then prayer, brews, antifire, antipoison, energy
-- and the basic combat potions.
--
-- A herb or secondary used by several recipes is placed with the FIRST
-- recipe that uses it (for example dwarf weed goes with extreme strength).
local RECIPES = {
  { "super attack", "irit", "eye of newt" },
  { "extreme attack", "avantoe", nil },
  { "super strength", "kwuarm", "limpwurt root" },
  { "extreme strength", "dwarf weed", nil },
  { "super defence", "cadantine", "white berries" },
  { "extreme defence", "lantadyme", nil },
  { "super ranging", "dwarf weed", "wine of zamorak" },
  { "extreme ranging", nil, "grenwall spikes" },
  { "super magic", "lantadyme", "potato cactus" },
  { "extreme magic", nil, "ground mud runes" },
  { "super necromancy", "spirit weed", "congealed blood" },
  { "extreme necromancy", nil, "ground miasma rune" },
  { "overload", "torstol", nil },
  { "prayer potion", "ranarr", "snape grass" },
  { "super restore", "snapdragon", "red spiders' eggs" },
  { "super prayer", nil, "wyvern bonemeal" },
  { "prayer renewal", "fellstalk", "morchella mushroom" },
  { "saradomin brew", "toadflax", "crushed nest" },
  { "antifire", "lantadyme", "dragon scale dust" },
  { "super antifire", nil, "phoenix feather" },
  { "antipoison", "marrentill", "unicorn horn dust" },
  { "super antipoison", "irit", "unicorn horn dust" },
  { "energy potion", "harralander", "chocolate dust" },
  { "super energy", "avantoe", "mort myre fungus" },
  { "attack potion", "guam", "eye of newt" },
  { "strength potion", "tarromin", "limpwurt root" },
  { "defence potion", "ranarr", "white berries" },
  { "restore potion", "harralander", "red spiders' eggs" },
  { "combat potion", "harralander", "goat horn dust" },
  { "ranging potion", "dwarf weed", "wine of zamorak" },
  { "magic potion", "lantadyme", "potato cactus" },
  { "agility potion", "toadflax", "toad's legs" },
  { "fishing potion", "avantoe", "snape grass" },
  { "hunter potion", "avantoe", "kebbit teeth dust" },
}

-- Where each herblore kind of item sits inside one recipe, before doses.
-- Potions are stage 5 in vials and stage 6 in flasks (decided by name).
local HERBLORE_STAGE = {
  ["grimy-herbs"] = 1, ["clean-herbs"] = 2, ["unfinished-potions"] = 3, ["secondaries"] = 4,
  ["potions"] = 5, ["potion-doses"] = 5, ["herblore-other"] = 6,
}

-- The four bands herblore items fall into, in tab order.
local VIALS, RECIPE, UNKNOWN, LAST_SECONDARIES = 0, 1, 2, 3

-- Returns true when tag is a herblore kind of item (herbs, secondaries,
-- unfinished potions, potions, part doses and other herblore items).
function Sorting.isHerblore(tag)
  return HERBLORE_STAGE[tag] ~= nil
end

-- Returns an item's herblore chain and its place in that chain.
--   name  item name (any case)
-- The longest matching chain member wins, so "super antipoison" is not
-- mistaken for "antipoison". Items in no chain return one past the last
-- chain, with the herb's level order as the place.
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

-- Returns the position of the first recipe whose field (1 = potion,
-- 2 = herb, 3 = secondary) is a whole word in name. For potions the longest
-- matching name wins, so "super antipoison (4)" finds Super antipoison, not
-- Antipoison. Returns nil when no recipe matches.
local function recipeBy(field, name)
  local best, length = nil, 0
  for index, recipe in ipairs(RECIPES) do
    local word = recipe[field]
    if word and hasWord(name, word) then
      if field ~= 1 then return index end
      if #word > length then best, length = index, #word end
    end
  end
  return best
end

-- Returns Sorting.chain's answer for a name, with incense sticks forced into
-- the misc chain: an incense name contains a herb name ("irit incense
-- sticks") but must not join that herb's potions.
local function chainOf(name)
  if hasWord(name, "incense") then return #CHAINS, indexIn(HERB_ORDER, name) end
  return Sorting.chain(name)
end

-- Returns the order of an empty or water vial or flask, or nil when name is
-- not one:
--   1  empty vials and flasks ("Vial", "Potion flask", "Empty vial")
--   2  vials and flasks of water
--   3  other vial or flask types (bomb vial, juju vial, crystal flask, ...)
-- Potions in flasks end with a dose like "(6)" and are never matched here.
local function vialOrder(name)
  if name == "vial" or name == "potion flask" or name == "empty vial" then return 1 end
  if (hasWord(name, "vial") or hasWord(name, "flask")) and hasWord(name, "water") then return 2 end
  if name:match(" vial$") or name:match(" flask$") or name == "flask" then return 3 end
  return nil
end

-- Builds the sort keys for one herblore item.
--   tag   the item's kind (one of HERBLORE_STAGE's keys)
--   name  lower-cased item name
--   opts  { secondaries = "with" | "bottom" }
-- Returns a list of 5 keys: band, then three numbers, then the name.
local function herbloreKeys(tag, name, opts)
  local vial = vialOrder(name)
  if vial then return { VIALS, vial, 0, 0, name } end
  local dose = Classify.dose(name) or 0
  local stage = HERBLORE_STAGE[tag]
  local recipe
  if tag == "grimy-herbs" or tag == "clean-herbs" or tag == "unfinished-potions" then
    recipe = recipeBy(2, name)
  elseif tag == "secondaries" then
    recipe = recipeBy(3, name)
  else
    recipe = recipeBy(1, name)
    -- Flasks follow the vials of the same potion.
    stage = hasWord(name, "flask") and 6 or 5
  end
  -- "At the bottom of the tab": every secondary goes after the rest of
  -- herblore, still in recipe order among themselves.
  if tag == "secondaries" and opts and opts.secondaries == "bottom" then
    return { LAST_SECONDARIES, recipe or #RECIPES + 1, 0, 0, name }
  end
  if recipe then return { RECIPE, recipe, stage, dose, name } end
  -- Not in the recipe table: fall back to its chain so it stays near its
  -- family, then by stage and dose.
  local group, member = chainOf(name)
  return { UNKNOWN, group, member, stage * 10 + dose, name }
end

-- Makes every herblore item in one tab share the same first sort key (the
-- lowest rank among them). Without this, grimy herbs, clean herbs,
-- unfinished potions, secondaries and potions would each sort as their own
-- block; with it they interleave recipe by recipe.
--   entries  the planned entries of one tab; their keys are changed in place
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

-- Food by healing tier, lowest first; drinks last.
local FOOD_ORDER = {
  "shrimps", "anchovies", "sardine", "herring", "mackerel", "trout", "cod", "pike", "salmon", "tuna", "lobster",
  "bass", "swordfish", "monkfish", "shark", "sea turtle", "cavefish", "manta ray", "rocktail", "sailfish",
  "blue blubber jellyfish", "green blubber jellyfish", "jellyfish", "potato", "pie", "pizza", "cake", "stew",
  "curry", "kebab", "wine", "beer", "ale",
}

-- Sub-groups for kinds that are ordered by "what sort of thing it is". Each
-- kind maps to a list of word lists; an item joins the first list with a
-- word in its name, and items matching none sort last.
local GROUPS = {
  teleports = {
    { "tablet", "teleport to house" }, { "amulet", "necklace", "ring", "bracelet", "pendant", "medallion", "glory" },
    { "cape", "boots", "gloves", "hood", "shield", "armour" }, { "scroll", "seed", "journal", "book", "orb", "sheet", "disk" },
  },
  currency = { { "coins" }, { "token", "tokens" }, { "ticket", "tickets" } },
  tools = {
    { "pickaxe" }, { "hatchet", "axe", "chainaxe" },
    { "fishing rod", "fly fishing rod", "harpoon", "net", "lobster pot", "rod-o-matic", "fishing" },
    { "trap", "snare", "noose", "butterfly net", "jar", "whistle" },
    { "secateurs", "rake", "seed dibber", "spade", "watering can", "trowel", "farming" },
    { "hammer", "chisel", "needle", "knife", "saw", "mould", "glassblowing", "crafting", "smithing" },
    { "tinderbox", "firelighter", "cinder" },
    { "mattock", "soil box", "tetracompass", "brush", "auger", "archaeological", "archaeology" },
    { "gizmo", "augmentor", "divine charge", "dissolver", "siphon", "separator", "junk refiner", "capacitor", "screener", "invention" },
    { "urn", "enhancer" },
    { "ritual", "ghostly ink", "candle", "skull" },
    { "porter", "grace" },
  },
  containers = {
    { "rune pouch", "pouch" }, { "ore box" }, { "wood box", "log basket" }, { "herb bag" }, { "gem bag" },
    { "seed box", "seed bag" }, { "coal bag" }, { "tackle box" }, { "loot bag" },
  },
  summoning = { { "spirit shards" }, { "charm" }, { "pouch" }, { "scroll" }, { "contract" }, { "spirit" } },
  ["xp-items"] = {
    { "knowledge bomb" }, { "lamp" }, { "star" }, { "wildcard" }, { "protean" }, { "skilling pack", "portable" },
    { "dummy", "dummies" }, { "catalyst", "silverhawk", "core" }, { "cleaner" },
  },
  seeds = { { "sapling" }, { "seed", "seeds" }, { "spore", "spores" } },
  produce = { { "compost" }, { "supercompost" }, { "ultracompost" }, { "manure" }, { "patch bomb" } },
  ["ammo-components"] = { { "arrowheads", "arrow tips", "tips" }, { "bolt tips" }, { "shaft", "headless" }, { "feather", "feathers" } },
  clues = { { "easy" }, { "medium" }, { "hard" }, { "elite" }, { "master" } },
}

-- Returns the position of the first word list with a word in name, or one
-- past the end of the lists.
local function groupOf(name, groups)
  for index, words in ipairs(groups) do
    if anyWord(name, words) then return index end
  end
  return #groups + 1
end

-- Orders partly eaten food after the whole item: whole = 0, then "2/3" and
-- "half" = 1, then "1/3" and "1/2" = 2.
local function portion(name)
  if name:find("1/3", 1, true) or name:find("1/2", 1, true) then return 2 end
  if name:find("2/3", 1, true) or name:find("half", 1, true) then return 1 end
  return 0
end

-- Returns a name without its charge count, so "Desert amulet 4" and
-- "Desert amulet 2" share the family "desert amulet".
local function family(name)
  return (name:gsub("%s*%(%d+%)", ""):gsub("%s+%d+$", ""))
end

-- Returns the charge count in a name: "(5)" or a trailing " 4", else 0.
local function charges(name)
  return tonumber(name:match("%((%d+)%)") or name:match("%s(%d+)$")) or 0
end

-- Builds the Smart sort keys for one item, after its rank.
--   tag   the item's kind
--   name  lower-cased item name
--   info  the item facts from the bank reader (category, cost, ...)
--   opts  herblore options, see herbloreKeys
-- Every kind returns its own key list; kinds without special rules return
-- { 0, "", 0 } so they fall through to name order.
local function smartKeys(tag, name, info, opts)
  if Sorting.isHerblore(tag) then return herbloreKeys(tag, name, opts) end
  local groups = GROUPS[tag]
  -- Food: healing tier, whole before partly eaten, then most valuable.
  if tag == "food" then return { indexIn(FOOD_ORDER, name), portion(name), -(tonumber(info.cost) or 0) } end
  -- Teleports: by type, then family, then most charges first.
  if tag == "teleports" then return { groupOf(name, groups), family(name), -charges(name) } end
  -- Ammo parts: by tier, then by part.
  if tag == "ammo-components" then return { indexIn(TIERS, name), groupOf(name, groups), 0 } end
  -- Clues: by tier, then scroll, casket, puzzle box.
  if tag == "clues" then
    return { groupOf(name, groups), groupOf(name, { { "scroll" }, { "casket" }, { "puzzle", "box" } }), 0 }
  end
  -- Loot and alchables: most valuable first.
  if tag == "boss-loot" or tag == "alch" then return { 0, "", -(tonumber(info.cost) or 0) } end
  if groups then return { groupOf(name, groups), "", 0 } end
  local category = info.category or ""
  local value = -(tonumber(info.cost) or 0)
  -- Gear: by combat style, then slot, best (most valuable) first.
  if tag == "gear" or tag == "ammunition" then
    return { Sorting.style(name, category), Sorting.slot(name, category), value }
  end
  -- Outfits: pieces of a set together, in slot order.
  if tag == "skilling-outfits" then return { setName(name, category), Sorting.slot(name, category), 0 } end
  if tag == "runes" then return { indexIn(RUNE_ORDER, name), "", 0 } end
  if tag == "herb-seeds" then return { indexIn(HERB_ORDER, name), "", 0 } end
  if tag == "gems" then return { indexIn(GEM_ORDER, name), name:find("uncut", 1, true) and 0 or 1, 0 } end
  if tag == "raw-resources" then return { materialOf(name), indexIn(TIERS, name), 0 } end
  return { 0, "", 0 }
end

-- Builds the full sort key list for a planned entry.
--   entry  { rank, tag, name, id, quantity }
--   info   item facts (may be nil)
--   mode   one of Sorting.MODES' keys
--   opts   optional { secondaries = "with" | "bottom" } for Smart herblore
-- Every list ends with the name and id so the order is always complete and
-- the same on every run.
function Sorting.keys(entry, info, mode, opts)
  local name = (entry.name or ""):lower()
  if mode == "id" then return { entry.rank, entry.id } end
  if mode == "name" then return { entry.rank, name, entry.id } end
  if mode == "value" then return { -Sorting.worth(info), name, entry.id } end
  if mode == "qty-desc" then return { -(tonumber(entry.quantity) or 0), name, entry.id } end
  if mode == "qty-asc" then return { tonumber(entry.quantity) or 0, name, entry.id } end
  local keys = { entry.rank }
  for _, key in ipairs(smartKeys(entry.tag, name, info or {}, opts)) do keys[#keys + 1] = key end
  keys[#keys + 1] = name
  keys[#keys + 1] = entry.id
  return keys
end

-- Compares two planned entries by their sort keys. Returns true when a must
-- come before b. A shorter key list sorts first when all shared keys are
-- equal; keys of different types are ordered by type name so mixed lists
-- never raise an error; the bank slot is the final tie-breaker.
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

-- How many doses a full potion holds in each container.
Sorting.FULL_DOSES = { vial = 4, flask = 6 }

-- The kinds of item that hold drinkable doses.
local POTION_TAGS = { potions = true, ["potion-doses"] = true }

-- Works out which part-dose potions can be decanted into full ones.
--   items  list of { id, name, quantity, tag }
-- Doses are added up per potion family and container (vial or flask); a
-- family can be decanted when its part doses add up to at least one full
-- container. Returns item id -> { dose, kind, family, canDecant } for every
-- part-dose potion.
function Sorting.decantInfo(items)
  local totals, found = {}, {}
  for _, item in ipairs(items) do
    local name = (item.name or ""):lower()
    local dose = POTION_TAGS[item.tag] and Classify.dose(name)
    if dose then
      local kind = name:find("flask", 1, true) and "flask" or "vial"
      if dose < Sorting.FULL_DOSES[kind] then
        local family = name:gsub("%s*%(%d%)%s*$", ""):gsub("%s*flask$", "") .. "|" .. kind
        totals[family] = (totals[family] or 0) + dose * math.max(1, tonumber(item.quantity) or 1)
        found[item.id] = { dose = dose, kind = kind, family = family }
      end
    end
  end
  for _, info in pairs(found) do info.canDecant = totals[info.family] >= Sorting.FULL_DOSES[info.kind] end
  return found
end

-- Rearranges a sorted list so it reads top to bottom, column by column,
-- instead of left to right, row by row.
--   list     the sorted entries
--   columns  how many slots the bank shows per row
-- Bank slots are filled row by row, so this works out which entry belongs in
-- each slot for the list to read down the columns. Returns a new list; lists
-- that are too short to need it are returned unchanged.
function Sorting.vertical(list, columns)
  local n = #list
  if not columns or columns < 2 or n < 2 then return list end
  -- Slot numbers 0..n-1, ordered column first: all of column 0, then 1, ...
  local cells = {}
  for i = 0, n - 1 do cells[#cells + 1] = i end
  table.sort(cells, function(a, b)
    local ca, cb = a % columns, b % columns
    if ca ~= cb then return ca < cb end
    return a < b
  end)
  -- The k-th entry in sorted order goes into the k-th cell of that order.
  local out = {}
  for k, cell in ipairs(cells) do out[cell + 1] = list[k] end
  return out
end

return Sorting
