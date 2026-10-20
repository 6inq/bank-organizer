local A = require("assert")
local Sorting = require("src/core/sorting")
local Blueprint = require("src/core/blueprint")
local Layout = require("src/core/layout")

local T = {}

local MELEE, RANGED, MAGIC, NECRO, OTHER = 1, 2, 3, 4, 5

function T.styles_from_category_then_name()
  A.eq(Sorting.style("Abyssal whip", "WEAPON_WHIP"), MELEE)
  A.eq(Sorting.style("Augmented ascension crossbow", "WEAPON_XBOW"), RANGED)
  A.eq(Sorting.style("Skull sceptre", "WEAPON_STAFF"), MAGIC, "category beats the name")
  A.eq(Sorting.style("Deathwarden nexus", "NECROMANCY_NEXUS"), NECRO)
  A.eq(Sorting.style("Armadyl chestplate", "ARMOUR_BODY"), RANGED, "a named set beats 'chestplate'")
  A.eq(Sorting.style("Virtus robe top", "ARMOUR_BODY"), MAGIC)
  A.eq(Sorting.style("Elite sirenic mask", "ARMOUR_HELMET"), RANGED)
  A.eq(Sorting.style("Torva full helm", "ARMOUR_HELMET"), MELEE)
  A.eq(Sorting.style("Ring of kinship", "RING"), OTHER)
end

function T.slots_in_bank_preset_order()
  A.eq(Sorting.SLOTS[Sorting.slot("Abyssal whip", "WEAPON_WHIP")], "main hand")
  A.eq(Sorting.SLOTS[Sorting.slot("Augmented off-hand ascension crossbow", "WEAPON_XBOW")], "off hand", "off-hand beats the weapon category")
  A.eq(Sorting.SLOTS[Sorting.slot("Augmented ancient defender", "ARMOUR_WEAPON")], "off hand")
  A.eq(Sorting.SLOTS[Sorting.slot("Helm of Trials", "ARMOUR_HELMET")], "head")
  A.eq(Sorting.SLOTS[Sorting.slot("Platelegs of Trials", "ARMOUR_LEGS")], "legs")
  A.eq(Sorting.SLOTS[Sorting.slot("Primeval boots", "ARMOUR_FEET")], "feet")
  A.eq(Sorting.SLOTS[Sorting.slot("Essence of Finality amulet", "")], "neck", "name when there is no category")
  A.eq(Sorting.SLOTS[Sorting.slot("Reaver's ring", "REXKINGS_BERSERKER_RING")], "ring")
  A.eq(Sorting.SLOTS[Sorting.slot("Mystery", "")], "other")
end

local function gear(slot, id, name, category, cost)
  return { slot = slot, id = id, name = name, quantity = 1,
    info = { name = name, category = category, cost = cost, ops = { wield = true } } }
end

local function order(items, mode)
  local layout = Layout.new("main")
  local d = Blueprint.build(items, layout, function() return "gear" end, mode)
  local names = {}
  for index, entry in ipairs(d[layout:destinationOf("gear")]) do names[index] = entry.name end
  return names
end

local GEAR = {
  gear(1, 50, "Virtus robe top", "ARMOUR_BODY", 900),
  gear(2, 40, "Torva full helm", "ARMOUR_HELMET", 800),
  gear(3, 30, "Armadyl chestplate", "ARMOUR_BODY", 700),
  gear(4, 20, "Abyssal whip", "WEAPON_WHIP", 100),
  gear(5, 10, "Noxious scythe", "WEAPON_SCYTHE", 5000),
  gear(6, 60, "Wand of the Cywir elders", "WEAPON_WAND", 3000),
}

function T.smart_groups_gear_by_style_then_slot_then_best_first()
  A.list(order(GEAR, "smart"), {
    "Noxious scythe", "Abyssal whip",
    "Torva full helm",
    "Armadyl chestplate",
    "Wand of the Cywir elders",
    "Virtus robe top",
  })
end

function T.name_and_id_modes()
  A.list(order(GEAR, "name"), { "Abyssal whip", "Armadyl chestplate", "Noxious scythe", "Torva full helm", "Virtus robe top", "Wand of the Cywir elders" })
  A.list(order(GEAR, "id"), { "Noxious scythe", "Abyssal whip", "Armadyl chestplate", "Torva full helm", "Virtus robe top", "Wand of the Cywir elders" })
end

function T.smart_keeps_potion_families_together_highest_dose_first()
  local items = {}
  for slot, name in ipairs({ "Super restore (1)", "Prayer potion (3)", "Super restore (4)", "Prayer potion (4)", "Super restore (2)" }) do
    items[slot] = { slot = slot, id = slot, name = name, quantity = 1, info = { name = name, ops = { drink = true } } }
  end
  local layout = Layout.new("main")
  local d = Blueprint.build(items, layout, function() return "potions" end, "smart")
  local names = {}
  for index, entry in ipairs(d[layout:destinationOf("potions")]) do names[index] = entry.name end
  A.list(names, { "Prayer potion (4)", "Prayer potion (3)", "Super restore (4)", "Super restore (2)", "Super restore (1)" })
end

function T.smart_resources_by_material_then_tier()
  local items = {}
  for slot, name in ipairs({ "Magic logs", "Rune bar", "Oak logs", "Bronze bar", "Mithril ore" }) do
    items[slot] = { slot = slot, id = slot, name = name, quantity = 1, info = { name = name, ops = {} } }
  end
  local layout = Layout.new("main")
  local d = Blueprint.build(items, layout, function() return "raw-resources" end, "smart")
  local names = {}
  for index, entry in ipairs(d[layout:destinationOf("raw-resources")]) do names[index] = entry.name end
  A.list(names, { "Mithril ore", "Bronze bar", "Rune bar", "Oak logs", "Magic logs" })
end

function T.keep_my_order_leaves_a_tab_alone_and_appends_arrivals()
  local destinations = { [0] = {}, [1] = {
    { id = 7, slot = 9 }, { id = 5, slot = 2 }, { id = 6, slot = 1 }, { id = 8, slot = 4 },
  } }
  local sectionOf = { [5] = 1, [6] = 1, [7] = 0, [8] = 1 }
  Blueprint.keepOrder(destinations, sectionOf, { [0] = 0, [1] = 1 })
  local ids = {}
  for index, entry in ipairs(destinations[1]) do ids[index] = entry.id end
  A.list(ids, { 6, 5, 8, 7 }, "tab members in their current order, the newcomer last")
end

function T.every_mode_is_offered_and_valid()
  A.eq(#Sorting.MODES, 4)
  for _, mode in ipairs(Sorting.MODES) do A.eq(Sorting.isMode(mode.key), true) end
  A.eq(Sorting.isMode("bogus"), false)
end

return T
