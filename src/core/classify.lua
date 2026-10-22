-- Bank Organizer: deciding what kind of item something is.
--
-- Classify.classify looks at an item's facts from the client and returns a
-- kind key from src/core/tags.lua, or nil when it cannot tell (the caller
-- then uses Storage & Cleanup). It checks, in order:
--   1. rares and a few unmistakable names (coins, clues, overrides, runes,
--      teleports, XP items)
--   2. the client's own item category, which is the most reliable source
--   3. herblore and consumables (by name and the Drink and Eat options)
--   4. name families for tools, outfits, containers, resources and so on
--   5. equipment (Wear, Wield, Equip) and quest items last
-- The order matters: for example a "rune pouch" must be a container, not a
-- rune, and a teleport tablet must not be a resource.
--
-- Words lists below are lower case; names are lower-cased before checks.

local Classify = {}

-- Herb names, used to spot grimy herbs, clean herbs, herb seeds and
-- unfinished potions.
local HERBS = {
  "guam", "marrentill", "tarromin", "harralander", "ranarr", "toadflax", "spirit weed", "irit",
  "wergali", "avantoe", "kwuarm", "bloodweed", "snapdragon", "cadantine", "lantadyme", "dwarf weed",
  "torstol", "fellstalk", "arbuck", "rogue's purse", "sagewort", "valerian", "aloe", "wormwood",
  "magebane", "featherfoil", "winter's grip", "lycopus", "buckthorn", "erzille", "argway", "ugune",
  "shuta", "erzille",
}

-- Herblore secondary ingredients (and vials and flasks used in potions).
local SECONDARIES = {
  "eye of newt", "unicorn horn dust", "limpwurt root", "red spiders' eggs", "white berries",
  "snape grass", "mort myre fungus", "dragon scale dust", "wine of zamorak", "potato cactus",
  "jangerberries", "crushed nest", "poison ivy berries", "chocolate dust", "toad's legs",
  "goat horn dust", "kebbit teeth dust", "phoenix feather", "yew roots", "magic roots",
  "crystal flask", "vial of water", "coconut milk", "swamp tar", "ground mud runes",
  "cactus spine", "volcanic ash", "frog spawn", "bark", "dragon bitter", "papaya fruit",
  "grenwall spikes", "morchella mushroom", "ground fishing bait", "spider venom", "wimpy feather",
  "ground miasma rune", "beak snot", "lagoon", "primal extract", "inert adrenaline crystal",
  "clean dragonfruit", "harmony moss", "black dragonhide", "white dragon scale",
}

-- Skilling tools, matched as whole words.
local TOOLS = {
  "pickaxe", "hatchet", "hammer", "chisel", "knife", "tinderbox", "needle", "fishing rod",
  "harpoon", "lobster pot", "small fishing net", "big fishing net", "fly fishing rod", "secateurs",
  "rake", "seed dibber", "spade", "trowel", "saw", "mould", "glassblowing pipe", "noose wand",
  "butterfly net", "box trap", "bird snare", "magnifying glass", "machete", "watering can",
  "gardening trowel", "crystal tool", "grimoire", "mattock", "brush", "auger", "archaeologist's",
}

-- Skilling outfit set names (only counted for wearable items).
local OUTFITS = {
  "lumberjack", "prospector", "fishing outfit", "shark outfit", "golden mining", "farmer's",
  "botanist's", "master chef", "pyromancer", "blacksmith's", "runecrafter", "artisan's",
  "constructor's", "diviner", "agile", "elite tracker", "sous chef", "sea singer",
}

-- Bags, boxes and pouches that hold other items.
local CONTAINERS = {
  "pouch", "herb bag", "gem bag", "ore box", "seed box", "log basket", "rune pouch",
  "coal bag", "tackle box", "familiar pouch", "box of", "wood box",
}

-- Words that mark raw or processed skilling resources.
local RESOURCE_WORDS = {
  "ore", "bar", "logs", "plank", "hide", "leather", "essence", "bones", "ashes", "coal", "clay",
  "flax", "bowstring", "wool", "cotton", "silk", "sandstone", "granite", "limestone", "soda ash",
  "seaweed", "bucket of sand", "molten glass", "charm", "energy", "memory", "spirit stone",
  "component",
}

-- Gem names (cut or uncut) for Gems & Jewellery.
local GEMS = {
  "sapphire", "emerald", "ruby", "diamond", "dragonstone", "onyx", "hydrix", "opal", "jade",
  "red topaz", "lapis lazuli", "uncut",
}

-- Skill and achievement capes, kept with skilling outfits.
local SKILL_CAPES = { "cape (t)", "master cape", "max cape", "gatherer's cape", "artisan's cape", "support cape", "completionist cape" }

-- MTX and XP boost items (lamps, stars, protean items and so on).
local XP_ITEMS = {
  "knowledge bomb", "wildcard", "protean", "luminite injector", "combat dummy", "brassica primer", "lamp",
  "silverhawk", "chameleon extract", "skilling pack", "training dummy", "crafting catalyst", "dwarven toolbox",
  "artefact replicator",
}

-- Equipment slot words; a Treasure Hunter item with one of these is an
-- outfit piece rather than an XP item.
local OUTFIT_PIECES = {
  "head", "hat", "hood", "mask", "helm", "body", "top", "torso", "chest", "jacket", "legs", "trousers", "legguards",
  "trunks", "hands", "gloves", "arms", "branch", "feet", "boots", "legwear",
}

-- Invention and Archaeology items that count as tools.
local INVENTION_ARCH = {
  "gizmo", "dissolver", "equipment separator", "equipment siphon", "divine charge", "soil box", "urn",
  "tetracompass", "sharpening stone", "harmonic dust",
}

-- Farming supplies that count as produce.
local FARMING = { "compost", "manure", "patch bomb", "seed bag", "farm totem" }

-- The client's item category name -> kind, as { pattern, kind } pairs.
-- Checked in order; the first matching pattern wins. A kind of false means
-- "this category says nothing useful", so classification carries on (lore
-- eggs and baby lore items are not Summoning items).
local CATEGORY_RULES = {
  { "^MAGIC_RUNE$", "runes" }, { "^NECROMANCY_RUNE$", "runes" }, { "^RUNE_MULTIPLIER$", "runes" },
  { "^LORE_.*EGG$", false }, { "^LORE_BABY", false }, { "^LORE_", "summoning" }, { "SPIRIT_GEM", "summoning" },
  { "^TRH_SKILL", "xp-items" }, { "^TRH_PORTABLE_PACK$", "xp-items" }, { "PROTEAN", "xp-items" },
  { "DUMMY", "xp-items" }, { "CLEANER_TOKEN", "xp-items" }, { "^DIV_LOCATION_OBJ$", "xp-items" },
  { "OUTFIT", "skilling-outfits" }, { "^WOF_SKILL_SET_ITEM$", "skilling-outfits" },
  { "^UNFINISHED_POTION$", "unfinished-potions" }, { "^HERB$", "clean-herbs" }, { "^UNIDENTIFIED$", "grimy-herbs" },
  { "^HERB_BOMB$", "potions" }, { "^INCENSE_STICKS$", "herblore-other" },
  { "^GOD_GRAPES$", "secondaries" }, { "^GOD_WINE$", "secondaries" }, { "^PRIMAL_EXTRACT$", "secondaries" },
  { "^INVENT_", "tools" }, { "^URN$", "tools" }, { "^ARCH_MATERIAL$", "raw-resources" }, { "^ARCH_", "tools" },
  { "^IMCANDO", "tools" }, { "^DIV_SIGN_PORTER", "tools" }, { "^NECRO_RITUAL", "tools" }, { "^GHOSTLY_INK$", "tools" },
  { "^LOCKPICK$", "tools" }, { "_TOOL$", "tools" }, { "^WEAPON_PICK$", "tools" }, { "^WEAPON_AXE$", "tools" },
  { "^WEAPON_MATTOCK$", "tools" }, { "^GNOME_FIRELIGHTER$", "tools" },
  { "OREBOX$", "containers" }, { "WOODBOX$", "containers" }, { "STONE_SPIRIT$", "raw-resources" }, { "GEM_BAG$", "containers" },
  { "^NECRO_ENSOULED", "raw-resources" }, { "^NECROPLASM$", "raw-resources" }, { "^MASTERWORK", "raw-resources" },
  { "^LOGS$", "raw-resources" }, { "^ORE$", "raw-resources" }, { "^PLANK$", "raw-resources" },
  { "^BONES$", "raw-resources" }, { "^DIV_ENERGY$", "raw-resources" }, { "^NAIL$", "raw-resources" },
  { "^CRAFTING_", "raw-resources" }, { "^CUT_GEM$", "gems" }, { "^UNCUT_GEM$", "gems" },
  { "^XBOWS_BOLT_TIP$", "ammo-components" }, { "^ARROWHEADS$", "ammo-components" }, { "SHAFT$", "ammo-components" },
  { "^ECOSYSTEM_OBJECT$", "produce" }, { "^POF_", "produce" }, { "^ELR1_", "produce" },
  { "^FARMING_.*SEED$", "seeds" }, { "^FARMING_", "produce" }, { "^PLANTPOT", "produce" },
  { "^POH_TABLET$", "teleports" }, { "_TELE$", "teleports" }, { "_TELEPORT$", "teleports" },
  { "^EGWD_", "boss-loot" }, { "^DINO_GAME_REWARD", "boss-loot" }, { "^SLAYER_", "boss-loot" }, { "^HOTM_", "boss-loot" },
  { "^NTK_ARTEFACT", "alch" }, { "PETS_UNLOCK_ITEM$", "collection-log" }, { "^COLLECTION_LOG$", "collection-log" },
}

-- Parts used to make ammunition.
local AMMO_COMPONENTS = { "arrowheads", "arrow shaft", "headless arrow", "bolt tips", "unfinished bolts", "unf bolts", "feather" }

-- Returns true when word appears anywhere in text (plain text match).
local function has(text, word)
  return text:find(word, 1, true) ~= nil
end

-- Returns true when any of the words appears anywhere in text.
local function hasAny(text, words)
  for _, word in ipairs(words) do
    if has(text, word) then return true end
  end
  return false
end

-- Returns true when any of the words appears in text as a whole word. %f is
-- Lua's frontier pattern: it matches the edge between a non-letter and a
-- letter, so "bar" matches "gold bar" but not "barbarian". Punctuation in
-- the word is escaped so it is matched literally.
local function hasWord(text, words)
  for _, word in ipairs(words) do
    local pattern = "%f[%w]" .. word:gsub("%p", "%%%0") .. "%f[%W]"
    if text:find(pattern) then return true end
  end
  return false
end

-- Returns true when the item has any of the named right-click options.
local function anyOp(ops, names)
  for _, name in ipairs(names) do
    if ops[name] then return true end
  end
  return false
end

-- Returns the dose in a potion name like "Prayer potion (3)", or nil.
function Classify.dose(name)
  local dose = tostring(name or ""):match("%((%d)%)%s*$")
  return dose and tonumber(dose) or nil
end

-- Returns the herb a name is about ("irit"), or nil.
local function herbFamily(name)
  for _, herb in ipairs(HERBS) do
    if hasWord(name, { herb }) then return herb end
  end
  return nil
end

-- Classifies herblore ingredients: grimy herbs, unfinished potions, herb
-- seeds, clean herbs (a herb name that is not a potion or tar) and
-- secondaries. Returns a kind or nil.
local function classifyHerblore(name, ops)
  if name:sub(1, 6) == "grimy " and herbFamily(name) then return "grimy-herbs" end
  if has(name, "(unf)") or has(name, "unfinished potion") then return "unfinished-potions" end
  if herbFamily(name) and (has(name, " seed") or has(name, "seeds")) then return "herb-seeds" end
  if herbFamily(name) and not has(name, "potion") and not ops.drink and not has(name, "tar") then
    return "clean-herbs"
  end
  if hasAny(name, SECONDARIES) then return "secondaries" end
  return nil
end

-- Classifies things to drink or eat. Vial potions with 1 to 3 doses are
-- Part Doses; full vials and every flask are Potions. Returns a kind or nil.
local function classifyConsumable(name, ops)
  if ops.drink or Classify.dose(name) and (has(name, "potion") or has(name, "flask") or has(name, "brew") or has(name, "mix")) then
    local dose = Classify.dose(name)
    if dose and dose <= 3 and not has(name, "flask") then return "potion-doses" end
    return "potions"
  end
  if ops.eat then return "food" end
  return nil
end

-- Returns true for items that can be worn or wielded.
local function isEquipment(ops, category)
  return anyOp(ops, { "wear", "wield", "equip" })
    or category:match("^WEAPON_") or category:match("^ARMOUR_") or category:match("^AMMO_")
end

-- Classifies by the client's item category name using CATEGORY_RULES.
-- Treasure Hunter (TRH) items are outfit pieces when wearable and named like
-- a slot, otherwise XP items. Returns a kind or nil.
local function classifyCategory(category, ops, name)
  if category == "" then return nil end
  for _, rule in ipairs(CATEGORY_RULES) do
    if category:match(rule[1]) then return rule[2] or nil end
  end
  if category:match("^TRH") then
    return isEquipment(ops, category) and hasWord(name, OUTFIT_PIECES) and "skilling-outfits" or "xp-items"
  end
  return nil
end

-- Returns true when any right-click option contains word ("Teleport to ...").
local function anyOpContains(ops, word)
  for op in pairs(ops) do
    if type(op) == "string" and has(op, word) then return true end
  end
  return false
end

-- Discontinued rares, which always belong with Vanity & Rares.
local RARES = {
  ["red partyhat"] = true, ["yellow partyhat"] = true, ["green partyhat"] = true, ["blue partyhat"] = true,
  ["purple partyhat"] = true, ["white partyhat"] = true,
  ["red halloween mask"] = true, ["green halloween mask"] = true, ["blue halloween mask"] = true,
  ["santa hat"] = true, ["black santa hat"] = true, ["inverted santa hat"] = true,
  ["christmas cracker"] = true,
}

-- Returns true when a name is one of the rares above (any case).
function Classify.isRare(name)
  return RARES[(name or ""):lower()] == true
end

-- Returns the kind of item for the item facts from the bank reader, or nil.
--   info  { name, ops (option name -> true), category, quests, tradeable }
function Classify.classify(info)
  info = info or {}
  local name = type(info.name) == "string" and info.name:lower() or ""
  local ops = type(info.ops) == "table" and info.ops or {}
  local category = type(info.category) == "string" and info.category or ""
  if name == "" then return nil end
  -- 1. Rares and names that leave no doubt.
  if RARES[name] then return "vanity" end

  if name == "coins" or has(name, " token") or name:match("tickets?$") then return "currency" end
  if has(name, "clue scroll") or has(name, "casket") or has(name, "puzzle box") or has(name, "scroll box") then return "clues" end
  if has(name, "override") or category:match("^COSMETIC") then return "cosmetics" end
  if name:sub(1, 7) == "ground " then return "secondaries" end
  if name:match(" rune$") or name:match(" runes$") then return "runes" end
  if anyOp(ops, { "rub", "break" }) or anyOpContains(ops, "teleport") or has(name, "teleport") or has(name, "lodestone") then
    return "teleports"
  end

  if hasWord(name, XP_ITEMS) then return "xp-items" end
  -- 2. The client's own item category.
  local byCategory = classifyCategory(category, ops, name)
  if byCategory then return byCategory end

  -- 3. Herblore, then things to drink or eat.
  local herblore = classifyHerblore(name, ops)
  if herblore then return herblore end
  local consumable = classifyConsumable(name, ops)
  if consumable then return consumable end

  -- 4. Name families. Tools and containers come before ammunition and gear
  -- because many tools can also be wielded.
  if (hasAny(name, OUTFITS) or hasAny(name, SKILL_CAPES)) and isEquipment(ops, category) then return "skilling-outfits" end
  if hasWord(name, INVENTION_ARCH) or hasWord(name, { "trap" }) then return "tools" end
  if has(name, "spirit shards") then return "summoning" end
  if hasAny(name, FARMING) then return "produce" end
  if name:match("vial$") or name:match("flask$") then return "herblore-other" end
  if hasWord(name, TOOLS) or hasAny(name, { "archaeologist's", "grimoire" }) then return "tools" end
  if hasAny(name, CONTAINERS) then return "containers" end
  if hasAny(name, AMMO_COMPONENTS) and not isEquipment(ops, category) then return "ammo-components" end
  if category:match("^AMMO_") or name:match("arrows$") or name:match("bolts$") or name:match("darts$") or name:match("knives$") then
    return "ammunition"
  end
  -- 5. Anything else that can be worn or wielded is combat gear.
  if isEquipment(ops, category) then return "gear" end
  if hasAny(name, GEMS) and not isEquipment(ops, category) then return "gems" end
  if name:match(" seed$") or name:match(" seeds$") or has(name, "sapling") or has(name, "spore") then return "seeds" end
  if hasWord(name, RESOURCE_WORDS) or name:sub(1, 4) == "raw " then return "raw-resources" end
  -- Untradeable items tied to a quest are quest items.
  if (info.quests or 0) > 0 and info.tradeable == false then return "quest-items" end
  return nil
end

return Classify
