-- Bank Organizer: kinds of item and the categories that group them.
--
-- Every bank item is given exactly one "kind" (for example Runes, Potions or
-- Combat Gear). Kinds are what the Tab Layout moves between tabs. Each kind
-- belongs to a "category", which supplies the colour a tab is tinted with and
-- the group the kind starts in on the default layout.
--
-- The built-in kinds and categories below never change. Players can also make
-- their own categories (see src/core/custom.lua). Those are registered here at
-- runtime with Tags.setCustom so the rest of the plugin can treat them exactly
-- like the built-in ones.

local Tags = {}

-- The built-in categories, in default tab order. Each one has:
--   key     a stable id saved in layouts and share codes
--   main    the name shown with the "Main" starting layout
--   ironman the name shown with the "Ironman" starting layout
--   colour  the default tint as 0xRRGGBBAA
local BUILTIN_CATEGORIES = {
  { key = "currency-utilities", main = "Currency, Runes & Teleports", ironman = "Frequently Used, Runes & Teleports", colour = 0xFFCD3CFF },
  { key = "combat-gear", main = "Combat Gear", ironman = "Combat Gear", colour = 0xE24A4AFF },
  { key = "potions-food", main = "Potions & Food", ironman = "Potions, Food & PvM Supplies", colour = 0x5EC878FF },
  { key = "herblore", main = "Herblore", ironman = "Herblore & Potion Making", colour = 0x78C8CDFF },
  { key = "seeds-farming", main = "Seeds & Farming", ironman = "Seeds & Farming", colour = 0x96CD4BFF },
  { key = "skilling-tools", main = "Skilling Tools", ironman = "Skilling Tools", colour = 0xF09646FF },
  { key = "resources", main = "Raw & Processed Resources", ironman = "Raw & Processed Resources", colour = 0xAF8764FF },
  { key = "slayer-boss-loot", main = "Bossing & Slayer Loot", ironman = "Slayer, Boss Loot & Unique Drops", colour = 0xBE78E1FF },
  { key = "clues-cosmetics", main = "Clues, Cosmetics & Collection Log", ironman = "Clues, Cosmetics & Collection Log", colour = 0x5FA5F0FF },
  { key = "storage-cleanup", main = "Storage & Cleanup Review", ironman = "Storage & Cleanup Review", colour = 0x969696FF },
}

-- The built-in kinds of item. Each one has a stable key, the label players
-- see, and the key of the category it belongs to. The order here is the
-- order kinds appear inside a category on the default layout.
local BUILTIN_LIST = {
  { key = "frequently-used", label = "Frequently Used", category = "currency-utilities" },
  { key = "runes", label = "Runes", category = "currency-utilities" },
  { key = "summoning", label = "Summoning", category = "currency-utilities" },
  { key = "teleports", label = "Teleports", category = "currency-utilities" },
  { key = "currency", label = "Currency", category = "currency-utilities" },
  { key = "gear", label = "Combat Gear", category = "combat-gear" },
  { key = "ammunition", label = "Ammunition", category = "combat-gear" },
  { key = "potions", label = "Potions", category = "potions-food" },
  { key = "food", label = "Food & Drink", category = "potions-food" },
  { key = "herb-seeds", label = "Herb Seeds", category = "herblore" },
  { key = "grimy-herbs", label = "Grimy Herbs", category = "herblore" },
  { key = "clean-herbs", label = "Clean Herbs", category = "herblore" },
  { key = "secondaries", label = "Secondaries", category = "herblore" },
  { key = "unfinished-potions", label = "Unfinished Potions", category = "herblore" },
  { key = "potion-doses", label = "Part Doses", category = "herblore" },
  { key = "herblore-other", label = "Herblore Other", category = "herblore" },
  { key = "seeds", label = "Seeds", category = "seeds-farming" },
  { key = "produce", label = "Produce", category = "seeds-farming" },
  { key = "tools", label = "Skilling Tools", category = "skilling-tools" },
  { key = "skilling-outfits", label = "Skilling Outfits", category = "skilling-tools" },
  { key = "containers", label = "Containers", category = "skilling-tools" },
  { key = "xp-items", label = "MTX & XP Boosts", category = "skilling-tools" },
  { key = "raw-resources", label = "Raw & Processed Resources", category = "resources" },
  { key = "gems", label = "Gems & Jewellery", category = "resources" },
  { key = "ammo-components", label = "Ammo Components", category = "resources" },
  { key = "boss-loot", label = "Slayer & Boss Loot", category = "slayer-boss-loot" },
  { key = "alch", label = "Alch", category = "slayer-boss-loot" },
  { key = "clues", label = "Clue Scrolls & Caskets", category = "clues-cosmetics" },
  { key = "cosmetics", label = "Cosmetics", category = "clues-cosmetics" },
  { key = "collection-log", label = "Collection Log", category = "clues-cosmetics" },
  { key = "cleanup", label = "Storage & Cleanup", category = "storage-cleanup" },
  { key = "quest-items", label = "Quest Items", category = "storage-cleanup" },
  { key = "vanity", label = "Vanity & Rares", category = "currency-utilities" },
}

-- The kind given to anything the classifier cannot place.
Tags.FALLBACK = "cleanup"

-- How many tabs the default layout has (infinity plus nine custom tabs). It
-- matches the number of built-in categories, one tab per category.
Tags.DESTINATIONS = #BUILTIN_CATEGORIES

-- Rebuilds the public lists and lookup tables from the built-in entries plus
-- the given custom categories.
--   custom  a list of { key, name, colour } tables (may be nil or empty)
-- Each custom category becomes both a category (for its colour) and a kind of
-- the same key and name (so it can be placed in tabs). Indexes are renumbered
-- so Tags.LIST[i].index == i and Tags.CATEGORIES[i].index == i always hold.
function Tags.setCustom(custom)
  Tags.CATEGORIES, Tags.LIST = {}, {}
  -- Copy the built-in entries first so their indexes never change.
  for _, category in ipairs(BUILTIN_CATEGORIES) do Tags.CATEGORIES[#Tags.CATEGORIES + 1] = category end
  for _, tag in ipairs(BUILTIN_LIST) do Tags.LIST[#Tags.LIST + 1] = tag end
  -- Then add each custom category as a category and as a kind with one key.
  for _, def in ipairs(custom or {}) do
    Tags.CATEGORIES[#Tags.CATEGORIES + 1] = { key = def.key, main = def.name, ironman = def.name, colour = def.colour, custom = true }
    Tags.LIST[#Tags.LIST + 1] = { key = def.key, label = def.name, category = def.key, custom = true }
  end
  -- Rebuild the key lookups and stamp each entry with its position.
  Tags.byKey, Tags.categoryByKey = {}, {}
  for index, tag in ipairs(Tags.LIST) do
    tag.index = index
    Tags.byKey[tag.key] = tag
  end
  for index, category in ipairs(Tags.CATEGORIES) do
    category.index = index
    Tags.categoryByKey[category.key] = category
  end
end

-- Start with no custom categories. The store registers the saved ones when
-- the plugin loads.
Tags.setCustom(nil)

-- Returns true when key names a known kind of item (built-in or custom).
function Tags.isValid(key)
  return Tags.byKey[key] ~= nil
end

-- Returns true when key names a kind the player created themselves.
function Tags.isCustom(key)
  local tag = Tags.byKey[key]
  return tag ~= nil and tag.custom == true
end

-- Returns the label players see for a kind, or the key itself when the kind
-- is unknown (for example a custom category that was just deleted).
function Tags.label(key)
  local tag = Tags.byKey[key]
  return tag and tag.label or key
end

-- Returns the category table a kind belongs to, or nil for unknown kinds.
function Tags.categoryOf(key)
  local tag = Tags.byKey[key]
  return tag and Tags.categoryByKey[tag.category]
end

-- Returns the RS3 name for a tab position. Position 0 is the infinity tab
-- (the game's "Tab 1"); position n is the game's "Tab n+1".
function Tags.destinationName(destination)
  if destination == 0 then return "Tab 1 (infinity)" end
  return "Tab " .. (destination + 1)
end

return Tags
