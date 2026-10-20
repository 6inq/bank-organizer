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

function T.smart_groups_herblore_by_recipe_chain()
  local rows = {
    { "Super restore (4)", "potions" }, { "Clean irit", "clean-herbs" }, { "Extreme attack (3)", "potion-doses" },
    { "Overload (4)", "potions" }, { "Grimy irit", "grimy-herbs" }, { "Super attack (4)", "potions" },
    { "Irit potion (unf)", "unfinished-potions" }, { "Clean avantoe", "clean-herbs" }, { "Super attack (2)", "potion-doses" },
    { "Ranarr potion (unf)", "unfinished-potions" }, { "Clean torstol", "clean-herbs" }, { "Grenwall spikes", "secondaries" },
    { "Super ranging (4)", "potions" }, { "Prayer potion (4)", "potions" },
  }
  local items, tags = {}, {}
  for slot, row in ipairs(rows) do
    items[slot] = { slot = slot, id = slot, name = row[1], quantity = 1, info = { name = row[1], ops = {} } }
    tags[slot] = row[2]
  end
  local layout = Layout.new("main")
  for _, tag in ipairs({ "potions", "potion-doses", "clean-herbs", "grimy-herbs", "unfinished-potions", "secondaries" }) do layout:moveTag(tag, 3) end
  local d = Blueprint.build(items, layout, function(item) return tags[item.slot] end, "smart")
  local names = {}
  for index, entry in ipairs(d[3]) do names[index] = entry.name end
  A.list(names, {
    "Grimy irit", "Clean irit", "Irit potion (unf)", "Super attack (4)", "Super attack (2)",
    "Clean avantoe", "Extreme attack (3)", "Super ranging (4)", "Grenwall spikes", "Clean torstol", "Overload (4)",
    "Ranarr potion (unf)", "Prayer potion (4)", "Super restore (4)",
  })
end

function T.chains_pick_the_most_specific_name()
  local group, member = Sorting.chain("Super antipoison (4)")
  local _, plain = Sorting.chain("Antipoison (4)")
  A.truthy(member > plain, "super antipoison sorts after antipoison")
  A.eq(Sorting.chain("Extreme attack (4)"), Sorting.chain("Overload (4)"), "same chain")
  A.truthy(Sorting.chain("Mystery") > group, "unknown items come after every chain")
end

local function smartOrder(tag, names, extra)
  local items = {}
  for slot, name in ipairs(names) do
    local info = { name = name, ops = {} }
    for k, v in pairs(extra and extra[name] or {}) do info[k] = v end
    items[slot] = { slot = slot, id = slot, name = name, quantity = 1, info = info }
  end
  local layout = Layout.new("main")
  local d = Blueprint.build(items, layout, function() return tag end, "smart")
  local out = {}
  for index, entry in ipairs(d[layout:destinationOf(tag)]) do out[index] = entry.name end
  return out
end

function T.smart_covers_every_kind()
  A.list(smartOrder("food", { "Shark", "1/3 blue blubber jellyfish", "Lobster", "Blue blubber jellyfish", "Rocktail" }),
    { "Lobster", "Shark", "Rocktail", "Blue blubber jellyfish", "1/3 blue blubber jellyfish" }, "food by healing tier, full portions first")
  A.list(smartOrder("teleports", { "Ring of kinship", "Varrock tablet", "Desert amulet 2", "Desert amulet 4", "Karamja gloves 4" }),
    { "Varrock tablet", "Desert amulet 4", "Desert amulet 2", "Ring of kinship", "Karamja gloves 4" }, "tablets, jewellery by charges, then gear")
  A.list(smartOrder("tools", { "Spade", "Augmented crystal hammer", "Fishing rod-o-matic", "Dragon pickaxe", "Augmentor" }),
    { "Dragon pickaxe", "Fishing rod-o-matic", "Spade", "Augmented crystal hammer", "Augmentor" }, "tools by skill")
  A.list(smartOrder("summoning", { "Binding contract (gargoyle)", "Pack yak pouch", "Gold charm", "Spirit shards", "Spirit sapphire" }),
    { "Spirit shards", "Gold charm", "Pack yak pouch", "Binding contract (gargoyle)", "Spirit sapphire" }, "summoning by kind")
  A.list(smartOrder("clues", { "Casket (elite)", "Clue scroll (easy)", "Clue scroll (elite)", "Reward casket (master)" }),
    { "Clue scroll (easy)", "Clue scroll (elite)", "Casket (elite)", "Reward casket (master)" }, "clues by tier")
  A.list(smartOrder("boss-loot", { "Cheap drop", "Big drop" }, { ["Big drop"] = { cost = 900 }, ["Cheap drop"] = { cost = 5 } }),
    { "Big drop", "Cheap drop" }, "loot by value")
end

function T.incense_stays_out_of_the_potion_chains()
  local group = Sorting.chain("Clean irit")
  A.truthy(select(1, Sorting.chain("Irit incense sticks")) == group, "the herb name alone would match")
  local items = {
    { slot = 1, id = 1, name = "Irit incense sticks", quantity = 1, info = { name = "Irit incense sticks", ops = {} } },
    { slot = 2, id = 2, name = "Super attack (4)", quantity = 1, info = { name = "Super attack (4)", ops = {} } },
  }
  local tags = { "herblore-other", "potions" }
  local layout = Layout.new("main")
  layout:moveTag("herblore-other", 2)
  local d = Blueprint.build(items, layout, function(item) return tags[item.id] end, "smart")
  A.eq(d[2][1].name, "Super attack (4)", "incense after the potions")
end

return T
