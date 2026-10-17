-- Ordered category list. The order here is also the default bank order.
local Categories = {}

Categories.list = {
  { key = "teleports", label = "Teleports", colour = 0x4A90E2FF },
  { key = "combat",    label = "Combat",    colour = 0xE2504AFF },
  { key = "potions",   label = "Potions",   colour = 0x4AC26BFF },
  { key = "food",      label = "Food",      colour = 0xA070E0FF },
  { key = "skilling",  label = "Skilling",  colour = 0xE2A04AFF },
  { key = "materials", label = "Materials", colour = 0xE04AC0FF },
  { key = "currency",  label = "Currency",  colour = 0xF2D24AFF },
  { key = "misc",      label = "Misc",      colour = 0x9AA0A6FF },
}

Categories.DEFAULT = "misc"
Categories.byKey = {}
local ranks = {}

for index, entry in ipairs(Categories.list) do
  Categories.byKey[entry.key] = entry
  ranks[entry.key] = index
end

function Categories.isValid(key)
  return key ~= nil and Categories.byKey[key] ~= nil
end

-- Unknown keys sort with misc.
function Categories.rank(key)
  return ranks[key] or ranks[Categories.DEFAULT]
end

function Categories.label(key)
  local entry = Categories.byKey[key]
  return entry and entry.label or Categories.byKey[Categories.DEFAULT].label
end

return Categories
