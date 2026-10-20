-- RS3 item classifier: item facts -> tag key. Pure.
-- Uses the client's own item data (category, right-click ops, quest links, tradeability)
-- plus exact RS3 name families. Anything it is not confident about returns nil, and the
-- blueprint puts it in Storage & Cleanup (fails closed), where a right-click correction fixes it.
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

-- "Super restore (4)" -> 4 ; "Saradomin brew flask (6)" -> 6 ; nil when no dose.
function Classify.dose(name)
  local dose = tostring(name or ""):match("%((%d)%)%s*$")
  return dose and tonumber(dose) or nil
end

local function herbFamily(name)
  for _, herb in ipairs(HERBS) do
    if has(name, herb) then return herb end
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

---@param info table? { name, category (id.Category name), ops = { [op]=true }, quests (count), tradeable }
---@return string? tag key, or nil when not confident
function Classify.classify(info)
  info = info or {}
  local name = type(info.name) == "string" and info.name:lower() or ""
  local ops = type(info.ops) == "table" and info.ops or {}
  local category = type(info.category) == "string" and info.category or ""
  if name == "" then return nil end

  if name == "coins" or has(name, " token") or name:match("tickets?$") then return "currency" end
  if has(name, "clue scroll") or has(name, "casket") or has(name, "puzzle box") or has(name, "scroll box") then return "clues" end
  if has(name, "override") or category:match("^COSMETIC") then return "cosmetics" end
  if name:match(" rune$") or name:match(" runes$") then return "runes" end
  if anyOp(ops, { "teleport", "rub", "break" }) or has(name, "teleport") or has(name, "lodestone") then return "teleports" end

  local herblore = classifyHerblore(name, ops)
  if herblore then return herblore end
  local consumable = classifyConsumable(name, ops)
  if consumable then return consumable end

  if hasAny(name, OUTFITS) and isEquipment(ops, category) then return "skilling-outfits" end
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
