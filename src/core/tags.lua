-- Categories (bundles) and the tags they split into, modelled on Bank Architect.
-- Destination 0 is the Main section; 1..9 are the numbered bank tabs.
local Tags = {}

-- Ten categories, in default destination order (Main, Tab 1 .. Tab 9).
Tags.CATEGORIES = {
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

-- Tags in their default order within each category.
Tags.LIST = {
  { key = "frequently-used", label = "Frequently Used", category = "currency-utilities" },
  { key = "runes", label = "Runes", category = "currency-utilities" },
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
}

-- Where anything unclassified goes (Bank Architect "fails closed" into review).
Tags.FALLBACK = "cleanup"
Tags.DESTINATIONS = 10 -- Main + 9 tabs

Tags.byKey, Tags.categoryByKey = {}, {}
for index, tag in ipairs(Tags.LIST) do
  tag.index = index
  Tags.byKey[tag.key] = tag
end
for index, category in ipairs(Tags.CATEGORIES) do
  category.index = index
  Tags.categoryByKey[category.key] = category
end

function Tags.isValid(key)
  return Tags.byKey[key] ~= nil
end

function Tags.label(key)
  local tag = Tags.byKey[key]
  return tag and tag.label or key
end

function Tags.categoryOf(key)
  local tag = Tags.byKey[key]
  return tag and Tags.categoryByKey[tag.category]
end

-- "Main" for destination 0, "Tab N" otherwise.
function Tags.destinationName(destination)
  if destination == 0 then return "Main" end
  return "Tab " .. destination
end

return Tags
