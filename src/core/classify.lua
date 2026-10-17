-- Heuristic item categorizer. First matching rule wins.
local Classify = {}

local TOOL_WORDS = {
  "pickaxe", "hatchet", "hammer", "chisel", "knife", "tinderbox", "needle",
  "fishing rod", "harpoon", "lobster pot", "secateurs", "rake", "spade",
  "trowel", "saw", "mould",
}

local MATERIAL_WORDS = {
  "ore", "bar", "logs", "plank", "grimy", "clean ", "herb", "seed", "hide",
  "leather", "uncut", "essence", "bones", "ashes", "raw ", "scale", "thread",
  "flax", "cloth", "gem", "salvage", "arrowheads", "tips", "unfinished", "shell",
}

-- Name fallback for gear when the client gives no wear/wield op.
local COMBAT_WORDS = {
  "sword", "longsword", "2h sword", "scimitar", "dagger", "mace", "battleaxe", "warhammer",
  "spear", "halberd", "claws", "whip", "rapier", "shield", "defender", "platebody",
  "platelegs", "plateskirt", "chainbody", "helm", "full helm", "boots", "gloves",
  "gauntlets", "vambraces", "bow", "shortbow", "longbow", "crossbow", "arrows", "bolts",
  "darts", "staff", "battlestaff", "wand", "robe top", "robe bottom", "chaps", "coif", "cape",
}

local function contains(text, word)
  return text:find(word, 1, true) ~= nil
end

local function containsAny(text, words)
  for _, word in ipairs(words) do
    if contains(text, word) then return true end
  end
  return false
end

-- Whole-word match so "bar" does not hit "barrows" and "ore" does not hit "core".
local function hasWord(text, words)
  for _, word in ipairs(words) do
    local plain = word:gsub("%s+$", "")
    local pattern = "%f[%w]" .. plain:gsub("%p", "%%%0") .. "%f[%W]"
    if text:find(pattern) then return true end
  end
  return false
end

local function hasOp(ops, names)
  for _, name in ipairs(names) do
    if ops[name] then return true end
  end
  return false
end

local function isCurrency(name)
  if contains(name, "coin pouch") then return false end
  return name == "coins" or contains(name, "token") or contains(name, "ticket")
    or contains(name, "coins")
end

local function isTeleport(name, ops)
  return hasOp(ops, { "teleport", "rub", "break" })
    or containsAny(name, { "teleport", "tablet", "lodestone" })
end

local function isPotion(name, ops)
  return ops.drink == true or name:find("%(%d%)$") ~= nil
    or containsAny(name, { "potion", "flask", "brew" })
end

local function isCombat(name, ops, category)
  if hasOp(ops, { "wear", "wield", "equip" }) then return true end
  if category:match("^WEAPON_") or category:match("^ARMOUR_") or category:match("^AMMO_") then
    return true
  end
  return name:match(" rune$") ~= nil or name:match("runes$") ~= nil or hasWord(name, COMBAT_WORDS)
end

---@param info table? { id, name, category, ops = { [lowercase op] = true } }
---@return string category key
function Classify.classify(info)
  info = info or {}
  local name = type(info.name) == "string" and info.name:lower() or ""
  local ops = type(info.ops) == "table" and info.ops or {}
  local category = type(info.category) == "string" and info.category or ""

  if isCurrency(name) then return "currency" end
  if isTeleport(name, ops) then return "teleports" end
  if isPotion(name, ops) then return "potions" end
  if ops.eat then return "food" end
  -- Tools before combat: RS3 pickaxes and hatchets are wieldable.
  if hasWord(name, TOOL_WORDS) then return "skilling" end
  if isCombat(name, ops, category) then return "combat" end
  if hasWord(name, MATERIAL_WORDS) then return "materials" end
  return "misc"
end

return Classify
