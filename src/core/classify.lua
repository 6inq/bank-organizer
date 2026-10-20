local Classify = {}

local HERBS = {
  "guam", "marrentill", "tarromin", "harralander", "ranarr", "toadflax", "spirit weed", "irit",
  "wergali", "avantoe", "kwuarm", "bloodweed", "snapdragon", "cadantine", "lantadyme", "dwarf weed",
  "torstol", "fellstalk", "arbuck", "rogue's purse", "sagewort", "valerian", "aloe", "wormwood",
  "magebane", "featherfoil", "winter's grip", "lycopus", "buckthorn", "erzille", "argway", "ugune",
  "shuta", "erzille",
}

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

local TOOLS = {
  "pickaxe", "hatchet", "hammer", "chisel", "knife", "tinderbox", "needle", "fishing rod",
  "harpoon", "lobster pot", "small fishing net", "big fishing net", "fly fishing rod", "secateurs",
  "rake", "seed dibber", "spade", "trowel", "saw", "mould", "glassblowing pipe", "noose wand",
  "butterfly net", "box trap", "bird snare", "magnifying glass", "machete", "watering can",
  "gardening trowel", "crystal tool", "grimoire", "mattock", "brush", "auger", "archaeologist's",
}

local OUTFITS = {
  "lumberjack", "prospector", "fishing outfit", "shark outfit", "golden mining", "farmer's",
  "botanist's", "master chef", "pyromancer", "blacksmith's", "runecrafter", "artisan's",
  "constructor's", "diviner", "agile", "elite tracker", "sous chef", "sea singer",
}

local CONTAINERS = {
  "pouch", "herb bag", "gem bag", "ore box", "seed box", "log basket", "rune pouch",
  "coal bag", "tackle box", "familiar pouch", "box of", "wood box",
}

local RESOURCE_WORDS = {
  "ore", "bar", "logs", "plank", "hide", "leather", "essence", "bones", "ashes", "coal", "clay",
  "flax", "bowstring", "wool", "cotton", "silk", "sandstone", "granite", "limestone", "soda ash",
  "seaweed", "bucket of sand", "molten glass", "charm", "energy", "memory", "spirit stone",
  "component",
}

local GEMS = {
  "sapphire", "emerald", "ruby", "diamond", "dragonstone", "onyx", "hydrix", "opal", "jade",
  "red topaz", "lapis lazuli", "uncut",
}

local SKILL_CAPES = { "cape (t)", "master cape", "max cape", "gatherer's cape", "artisan's cape", "support cape", "completionist cape" }

local XP_ITEMS = {
  "knowledge bomb", "wildcard", "protean", "luminite injector", "combat dummy", "brassica primer", "lamp",
  "silverhawk", "chameleon extract", "skilling pack", "training dummy", "crafting catalyst", "dwarven toolbox",
  "artefact replicator",
}

local OUTFIT_PIECES = {
  "head", "hat", "hood", "mask", "helm", "body", "top", "torso", "chest", "jacket", "legs", "trousers", "legguards",
  "trunks", "hands", "gloves", "arms", "branch", "feet", "boots", "legwear",
}

local INVENTION_ARCH = {
  "gizmo", "dissolver", "equipment separator", "equipment siphon", "divine charge", "soil box", "urn",
  "tetracompass", "sharpening stone", "harmonic dust",
}

local FARMING = { "compost", "manure", "patch bomb", "seed bag", "farm totem" }

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

local AMMO_COMPONENTS = { "arrowheads", "arrow shaft", "headless arrow", "bolt tips", "unfinished bolts", "unf bolts", "feather" }

local function has(text, word)
  return text:find(word, 1, true) ~= nil
end

local function hasAny(text, words)
  for _, word in ipairs(words) do
    if has(text, word) then return true end
  end
  return false
end

local function hasWord(text, words)
  for _, word in ipairs(words) do
    local pattern = "%f[%w]" .. word:gsub("%p", "%%%0") .. "%f[%W]"
    if text:find(pattern) then return true end
  end
  return false
end

local function anyOp(ops, names)
  for _, name in ipairs(names) do
    if ops[name] then return true end
  end
  return false
end

function Classify.dose(name)
  local dose = tostring(name or ""):match("%((%d)%)%s*$")
  return dose and tonumber(dose) or nil
end

local function herbFamily(name)
  for _, herb in ipairs(HERBS) do
    if hasWord(name, { herb }) then return herb end
  end
  return nil
end

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

local function classifyConsumable(name, ops)
  if ops.drink or Classify.dose(name) and (has(name, "potion") or has(name, "flask") or has(name, "brew") or has(name, "mix")) then
    local dose = Classify.dose(name)
    if dose and dose <= 3 and not has(name, "flask") then return "potion-doses" end
    return "potions"
  end
  if ops.eat then return "food" end
  return nil
end

local function isEquipment(ops, category)
  return anyOp(ops, { "wear", "wield", "equip" })
    or category:match("^WEAPON_") or category:match("^ARMOUR_") or category:match("^AMMO_")
end

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

local function anyOpContains(ops, word)
  for op in pairs(ops) do
    if type(op) == "string" and has(op, word) then return true end
  end
  return false
end

function Classify.classify(info)
  info = info or {}
  local name = type(info.name) == "string" and info.name:lower() or ""
  local ops = type(info.ops) == "table" and info.ops or {}
  local category = type(info.category) == "string" and info.category or ""
  if name == "" then return nil end

  if name == "coins" or has(name, " token") or name:match("tickets?$") then return "currency" end
  if has(name, "clue scroll") or has(name, "casket") or has(name, "puzzle box") or has(name, "scroll box") then return "clues" end
  if has(name, "override") or category:match("^COSMETIC") then return "cosmetics" end
  if name:sub(1, 7) == "ground " then return "secondaries" end
  if name:match(" rune$") or name:match(" runes$") then return "runes" end
  if anyOp(ops, { "rub", "break" }) or anyOpContains(ops, "teleport") or has(name, "teleport") or has(name, "lodestone") then
    return "teleports"
  end

  if hasWord(name, XP_ITEMS) then return "xp-items" end
  local byCategory = classifyCategory(category, ops, name)
  if byCategory then return byCategory end

  local herblore = classifyHerblore(name, ops)
  if herblore then return herblore end
  local consumable = classifyConsumable(name, ops)
  if consumable then return consumable end

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
  if isEquipment(ops, category) then return "gear" end
  if hasAny(name, GEMS) and not isEquipment(ops, category) then return "gems" end
  if name:match(" seed$") or name:match(" seeds$") or has(name, "sapling") or has(name, "spore") then return "seeds" end
  if hasWord(name, RESOURCE_WORDS) or name:sub(1, 4) == "raw " then return "raw-resources" end
  if (info.quests or 0) > 0 and info.tradeable == false then return "quest-items" end
  return nil
end

return Classify
