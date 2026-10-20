local A = require("assert")
local Tags = require("src/core/tags")
local Layout = require("src/core/layout")
local Classify = require("src/core/classify")
local Blueprint = require("src/core/blueprint")
local Guide = require("src/core/guide")
local Order = require("src/core/order")

local T = {}

local function ops(...)
  local set = {}
  for _, op in ipairs({ ... }) do set[op] = true end
  return set
end

function T.ten_categories_and_their_tags()
  A.eq(#Tags.CATEGORIES, 10); A.eq(#Tags.LIST, 32)
  for _, tag in ipairs(Tags.LIST) do A.truthy(Tags.categoryByKey[tag.category], tag.key .. " has a category") end
end

function T.default_layout_puts_each_category_on_its_own_destination()
  local layout = Layout.new("main")
  A.eq(layout:destinationOf("runes"), 0, "Main: currency, runes & teleports")
  A.eq(layout:destinationOf("gear"), 1); A.eq(layout:destinationOf("potions"), 2)
  A.eq(layout:destinationOf("grimy-herbs"), 3); A.eq(layout:destinationOf("cleanup"), 9)
  A.list(layout.destinations[0], { "frequently-used", "runes", "summoning", "teleports", "currency" })
end

function T.preset_names()
  local main, iron = Layout.new("main"), Layout.new("ironman")
  A.eq(main:categoryName(Tags.CATEGORIES[1]), "Currency, Runes & Teleports")
  A.eq(iron:categoryName(Tags.CATEGORIES[1]), "Frequently Used, Runes & Teleports")
  A.eq(Layout.new("bogus").preset, "main")
end

function T.move_shift_remove_and_reset_tags()
  local layout = Layout.new("main")
  A.eq(layout:moveTag("food", 0), true); A.eq(layout:destinationOf("food"), 0)
  A.eq(layout.destinations[0][6], "food", "appended at the end")
  A.eq(layout:shiftTag("food", -1), true); A.eq(layout.destinations[0][5], "food")
  A.eq(layout:shiftTag("frequently-used", -1), false, "already first")
  A.eq(layout:removeTag("food"), true); A.eq(layout:destinationOf("food"), 9, "back to Storage & Cleanup's tab")
  A.eq(layout:removeTag("cleanup"), false, "cleanup itself cannot be removed")
  A.eq(layout:moveTag("food", 10), false); A.eq(layout:moveTag("nope", 1), false)
  layout:reset(); A.eq(layout:destinationOf("food"), 2)
end

function T.saved_layout_round_trips_and_repairs()
  local layout = Layout.new("ironman")
  layout:moveTag("runes", 5)
  local restored = Layout.new("ironman", layout:serialize())
  A.eq(restored:destinationOf("runes"), 5)
  local broken = { ["0"] = { "runes", "runes", "bogus" } }
  local repaired = Layout.new("main", broken)
  A.eq(repaired:destinationOf("runes"), 0); A.eq(repaired:destinationOf("gear"), 1, "missing tags restored to defaults")
  local count = 0
  for d = 0, 9 do count = count + #repaired.destinations[d] end
  A.eq(count, #Tags.LIST, "every tag exactly once")
end

function T.tabs_can_be_added_moved_renamed_and_removed()
  local layout = Layout.new("main")
  A.eq(layout:last(), 9)
  for _ = 1, 5 do A.eq(layout:addTab(), true) end
  A.eq(layout:last(), 14); A.eq(layout:addTab(), false, "RS3 has 14 custom tabs at most")
  A.eq(layout:rename(3, "Herbs"), true); A.eq(layout:name(3), "Herbs")
  A.eq(layout:rename(3, "   "), true); A.eq(layout:name(3), "Tab 4", "blank name falls back to the RS3 number")
  A.eq(layout:moveTab(0, 1), false, "infinity stays first")
  A.eq(layout:moveTab(1, -1), false); A.eq(layout:moveTab(14, 1), false)
  A.eq(layout:moveTab(1, 1), true); A.eq(layout:destinationOf("gear"), 2)
  A.eq(layout:removeTab(0), false); A.eq(layout:removeTab(15), false)
  A.eq(layout:removeTab(2), true); A.eq(layout:destinationOf("gear"), 0, "tags of a deleted tab go to infinity")
  A.eq(layout:last(), 13)
  local count = 0
  for d = 0, layout:last() do count = count + #layout.destinations[d] end
  A.eq(count, #Tags.LIST, "never loses a tag")
end

function T.custom_layout_round_trips_and_old_saves_load()
  local layout = Layout.new("main")
  layout:addTab("Extra"); layout:moveTag("runes", 10); layout:rename(1, "Combat")
  local again = Layout.new("main", layout:serialize())
  A.eq(again:last(), 10); A.eq(again:destinationOf("runes"), 10)
  A.eq(again.names[10], "Extra"); A.eq(again.names[1], "Combat")
  local old = { ["0"] = { "runes" }, ["4"] = { "gear" } }
  local loaded = Layout.new("main", old)
  A.eq(loaded:last(), 9); A.eq(loaded:destinationOf("gear"), 4); A.eq(loaded:destinationOf("food"), 2, "missing tags restored")
  local short = Layout.new("main", { count = 2, tabs = { ["0"] = {}, ["1"] = { "gear" } } })
  A.eq(short:last(), 1); A.eq(short:destinationOf("food"), 0)
end

function T.copy_tabs_builds_a_layout_from_the_bank()
  local layout = Layout.new("main")
  layout:copyTabs(3, { ["xp-items"] = 1, gear = 3, runes = 9 }, { [1] = "MTX" })
  A.eq(layout:last(), 3)
  A.list(layout.destinations[1], { "xp-items" }); A.list(layout.destinations[3], { "gear" })
  A.eq(layout:destinationOf("runes"), 0, "a home past the last tab falls back to infinity")
  A.eq(layout.names[1], "MTX")
end

local cases = {
  { { name = "Coins" }, "currency" },
  { { name = "Air rune" }, "runes" },
  { { name = "Varrock teleport", ops = ops("break") }, "teleports" },
  { { name = "Super restore (4)", ops = ops("drink") }, "potions" },
  { { name = "Super restore (2)", ops = ops("drink") }, "potion-doses" },
  { { name = "Saradomin brew flask (6)", ops = ops("drink") }, "potions" },
  { { name = "Shark", ops = ops("eat") }, "food" },
  { { name = "Grimy ranarr" }, "grimy-herbs" },
  { { name = "Clean ranarr" }, "clean-herbs" },
  { { name = "Ranarr seed" }, "herb-seeds" },
  { { name = "Ranarr potion (unf)" }, "unfinished-potions" },
  { { name = "Eye of newt" }, "secondaries" },
  { { name = "Abyssal whip", ops = ops("wield") }, "gear" },
  { { name = "Rune arrows", ops = ops("wield") }, "ammunition" },
  { { name = "Dragon pickaxe", ops = ops("wield") }, "tools", "tools beat gear" },
  { { name = "Lumberjack top", ops = ops("wear") }, "skilling-outfits" },
  { { name = "Gem bag" }, "containers" },
  { { name = "Yew logs" }, "raw-resources" },
  { { name = "Uncut dragonstone" }, "gems" },
  { { name = "Bane arrowheads" }, "ammo-components" },
  { { name = "Potato seed" }, "seeds" },
  { { name = "Clue scroll (elite)" }, "clues" },
  { { name = "Hood override token" }, "currency", "tokens count as currency first" },
  { { name = "Ghostspeak amulet", quests = 1, tradeable = false }, "quest-items" },
}

local function real(name, category, opList)
  return { name = name, category = category, ops = ops(table.unpack(opList or {})) }
end
local realCases = {
  { real("Decorated cooking urn (empty)", "URN"), "tools" },
  { real("Augmentor", "INVENT_AUGMENTOR"), "tools" },
  { real("Gizmo dissolver", ""), "tools" },
  { real("Electrified trap", "", { "lay" }), "tools" },
  { real("Disk of returning", ""), nil, "\"returning\" is not an urn" },
  { real("Pack yak pouch", "LORE_PACK_YAK"), "summoning", "familiar pouches are summoning, not containers" },
  { real("Binding contract (gargoyle)", "LORE_ANCIENT_GARGOYLE"), "summoning" },
  { real("Black dragon egg", "LORE_DRAGON_EGG"), nil, "eggs are not summoning" },
  { real("Spirit sapphire", "WOF59_SPIRIT_GEM_EMPTY"), "summoning", "\"spirit\" is not the herb irit" },
  { real("Spirit shards", ""), "summoning" },
  { real("Augmented arcane spirit shield", "ARMOUR_SHIELD", { "wear" }), "gear" },
  { real("Elemental anima stone", "RUNE_MULTIPLIER"), "runes" },
  { real("Fury shark body", "TRH48_SHARK_FURY", { "wear" }), "skilling-outfits" },
  { real("Fury shark feet", "TRH48_SHARK_FURY", { "wear" }), "skilling-outfits" },
  { real("Master archaeologist's hat", "ARCH_ELITE_SKILLING_OUTFIT", { "wear" }), "skilling-outfits" },
  { real("Botanist's top", "WOF_SKILL_SET_ITEM", { "wear" }), "skilling-outfits" },
  { real("Hooded cooking cape (t)", "ARMOUR_CAPE", { "wear" }), "skilling-outfits" },
  { real("Fire cape", "ARMOUR_CAPE", { "wear" }), "gear", "combat capes stay gear" },
  { real("Prime Gaming knowledge bomb", "", { "activate" }), "xp-items", "MTX tab" },
  { real("Slayer Wildcard", ""), "xp-items" },
  { real("Large portable skilling pack", "TRH_PORTABLE_PACK"), "xp-items" },
  { real("Protean logs", "LOGS"), "xp-items" },
  { real("Silverhawk boots", "TRH5_PEGASUS_BOOTS", { "wear" }), "xp-items" },
  { real("Cinder core", "TRH165_CINDER_CORE", { "wear" }), "xp-items" },
  { real("Pungent vine", "ECOSYSTEM_OBJECT"), "produce" },
  { real("Supercompost", "", { "empty" }), "produce" },
  { real("Torstol potion (unfinished)", "UNFINISHED_POTION"), "unfinished-potions" },
  { real("Potion flask", ""), "herblore-other" },
  { real("Irit incense sticks", "INCENSE_STICKS"), "herblore-other" },
  { real("Glacor remnants", "EGWD_WEN_BOSS_INGREDIENT"), "boss-loot" },
  { real("Broken shackle", "BPETS_UNLOCK_ITEM"), "collection-log" },
  { real("Platinum stone spirit", "MINING_STONE_SPIRIT"), "raw-resources" },
  { real("Primal ore box", "MINING_OREBOX"), "containers" },
  { real("Pirate spell sheet", "", { "braindeath-teleport" }), "teleports" },
  { real("Ground mud runes", ""), "secondaries", "ground runes are a herblore ingredient" },
  { real("Ground miasma rune", ""), "secondaries" },
}

function T.classifier_real_bank_cases()
  for _, case in ipairs(realCases) do
    A.eq(Classify.classify(case[1]), case[2], case[3] or case[1].name)
  end
end

function T.classifier_cases()
  for _, case in ipairs(cases) do
    A.eq(Classify.classify(case[1]), case[2], case[3] or case[1].name)
  end
end

function T.classifier_fails_closed()
  A.eq(Classify.classify({ name = "Strange rock thing of mystery" }), nil)
  A.eq(Classify.classify(nil), nil); A.eq(Classify.classify({}), nil)
  A.eq(Classify.classify({ name = 5, ops = "x" }), nil)
end

function T.dose_parsing()
  A.eq(Classify.dose("Prayer potion (3)"), 3); A.eq(Classify.dose("Overload flask (6)"), 6); A.eq(Classify.dose("Shark"), nil)
end

local function item(slot, id, name, extra)
  local info = { name = name }
  for k, v in pairs(extra or {}) do info[k] = v end
  return { slot = slot, id = id, name = name, quantity = 1, info = info }
end

local BANK = {
  item(1, 101, "Shark", { ops = ops("eat") }),
  item(2, 102, "Prayer potion (2)", { ops = ops("drink") }),
  item(3, 103, "Coins"),
  item(4, 104, "Prayer potion (4)", { ops = ops("drink") }),
  item(5, 105, "Fire rune"),
  item(6, 106, "Air rune"),
  item(7, 107, "Mystery thing"),
  item(8, 108, "Abyssal whip", { ops = ops("wield") }),
  item(9, 109, "Grimy guam"),
  item(10, 110, "Grimy ranarr"),
}

local function ids(list)
  local out = {}
  for index, entry in ipairs(list) do out[index] = entry.id end
  return out
end

function T.blueprint_places_and_orders_items()
  local destinations = Blueprint.build(BANK, Layout.new("main"), Blueprint.resolver({}))
  A.list(ids(destinations[0]), { 106, 105, 103 }, "Main: runes (air before fire), then currency")
  A.list(ids(destinations[1]), { 108 }, "Tab 1: combat")
  A.list(ids(destinations[2]), { 104, 101 }, "Tab 2: potions then food")
  A.list(ids(destinations[3]), { 110, 102, 109 }, "Tab 3: ranarr with its prayer potion, then the guam chain")
  A.list(ids(destinations[9]), { 107 }, "unknown -> Storage & Cleanup")
end

function T.corrections_win()
  local destinations = Blueprint.build(BANK, Layout.new("main"), Blueprint.resolver({ [107] = "boss-loot", [101] = "frequently-used" }))
  A.list(ids(destinations[7]), { 107 }); A.eq(destinations[0][1].id, 101, "frequently used comes first on Main")
end

function T.empty_destinations_are_skipped()
  local destinations = Blueprint.build(BANK, Layout.new("main"), Blueprint.resolver({}))
  A.list(Blueprint.usedDestinations(destinations), { 0, 1, 2, 3, 9 })
  local map, physical = Guide.sectionMap(destinations)
  A.eq(physical, 4); A.eq(map[1], 1); A.eq(map[3], 3); A.eq(map[9], 4, "Storage tab becomes physical tab 4")
end

local function apply(sections, step)
  if step.kind == "to-tab" or step.kind == "new-tab" then
    local from = sections[step.from]
    for index, id in ipairs(from) do if id == step.id then table.remove(from, index); break end end
    sections[step.to] = sections[step.to] or {}
    table.insert(sections[step.to], step.id)
    for s = #sections, 1, -1 do if #sections[s] == 0 and s == #sections then sections[s] = nil end end
  elseif step.kind == "insert" then
    sections[step.section] = Order.apply(sections[step.section], step)
  elseif step.kind == "swap" then
    local list = sections[step.section]
    local a, b
    for index, id in ipairs(list) do
      if id == step.move then a = index end
      if id == step.swapWith then b = index end
    end
    list[a], list[b] = list[b], list[a]
  end
end

local function solve(sections, destinations, mode)
  local moves, first = 0, Guide.remaining(sections, destinations, mode)
  while true do
    local step, status = Guide.next(sections, destinations, mode)
    if not step then return moves, first, status end
    apply(sections, step)
    moves = moves + 1
    if moves > 5000 then error("guide did not converge") end
  end
end

local function matches(sections, destinations)
  local targets = Guide.targetSections(destinations)
  for s, target in pairs(targets) do A.list(sections[s] or {}, target, "section " .. s) end
end

function T.guide_sorts_an_all_main_bank_in_insert_mode()
  local destinations = Blueprint.build(BANK, Layout.new("main"), Blueprint.resolver({}))
  local sections = { [0] = { 101, 102, 103, 104, 105, 106, 107, 108, 109, 110 } }
  local moves, estimate, status = solve(sections, destinations, Guide.INSERT)
  A.eq(status, "done"); matches(sections, destinations); A.eq(moves, estimate, "exact move count")
end

function T.guide_swap_mode_also_finishes()
  local destinations = Blueprint.build(BANK, Layout.new("main"), Blueprint.resolver({}))
  local sections = { [0] = { 110, 109, 108, 107, 106, 105, 104, 103, 102, 101 } }
  local moves, estimate, status = solve(sections, destinations, Guide.SWAP)
  A.eq(status, "done"); matches(sections, destinations)
  A.truthy(moves <= estimate, "swap estimate is an upper bound")
end

function T.first_steps_create_tabs_in_order()
  local destinations = Blueprint.build(BANK, Layout.new("main"), Blueprint.resolver({}))
  local step = Guide.next({ [0] = { 108, 101, 103 } }, destinations, Guide.INSERT)
  A.eq(step.kind, "new-tab"); A.eq(step.id, 108); A.eq(step.to, 1)
end

function T.random_banks_converge_in_both_modes()
  local names = { "Shark", "Air rune", "Coins", "Grimy guam", "Abyssal whip", "Yew logs", "Potato seed",
    "Clue scroll (hard)", "Mystery", "Rune arrows", "Prayer potion (4)", "Gem bag", "Bane arrowheads" }
  for seed = 1, 60 do
    math.randomseed(seed)
    local items, all = {}, {}
    for index = 1, math.random(5, 40) do
      local name = names[math.random(#names)] .. " " .. index
      items[index] = item(index, 1000 + index, name, { ops = name:find("Shark") and ops("eat") or nil })
      all[index] = 1000 + index
    end
    local destinations = Blueprint.build(items, Layout.new("ironman"), Blueprint.resolver({}))
    for _, mode in ipairs({ Guide.INSERT, Guide.SWAP }) do
      local sections, pool = { [0] = {} }, {}
      for i = #all, 2, -1 do local j = math.random(i); all[i], all[j] = all[j], all[i] end
      for _, id in ipairs(all) do pool[#pool + 1] = id end
      local tabs = math.random(0, 3)
      for s = 1, tabs do sections[s] = {} end
      for _, id in ipairs(pool) do table.insert(sections[math.random(0, tabs)], id) end
      for s = tabs, 1, -1 do if #sections[s] == 0 and s == tabs then sections[s] = nil; tabs = tabs - 1 end end
      local _, _, status = solve(sections, destinations, mode)
      A.eq(status, "done", "seed " .. seed .. " " .. mode)
      matches(sections, destinations)
    end
  end
end

function T.already_sorted_bank_is_done()
  local destinations = Blueprint.build(BANK, Layout.new("main"), Blueprint.resolver({}))
  local sections = Guide.targetSections(destinations)
  local step, status = Guide.next(sections, destinations, Guide.INSERT)
  A.eq(step, nil); A.eq(status, "done"); A.eq(Guide.remaining(sections, destinations, Guide.INSERT), 0)
end

function T.blueprint_follows_a_custom_tab_order()
  local layout = Layout.new("main")
  layout:copyTabs(2, { gear = 1, food = 2 })
  local items = { item(1, 1, "Shark", { ops = ops("eat") }), item(2, 2, "Abyssal whip", { ops = ops("wield") }), item(3, 3, "Coins") }
  local d = Blueprint.build(items, layout, Blueprint.resolver({}))
  A.eq(d[3], nil, "only as many tabs as the layout has")
  A.list(ids(d[1]), { 2 }); A.list(ids(d[2]), { 1 }); A.list(ids(d[0]), { 3 })
end

function T.my_tabs_order_moves_whole_tabs()
  local items = { item(1, 1, "Shark", { ops = ops("eat") }), item(2, 2, "Lobster", { ops = ops("eat") }),
    item(3, 3, "Abyssal whip", { ops = ops("wield") }), item(4, 4, "Monkfish", { ops = ops("eat") }) }
  local sections = { [0] = { 4 }, [1] = { 1, 2 }, [2] = { 3 } }
  local d = Blueprint.buildFromTabs(items, sections, Blueprint.resolver({}), {}, { 2, 1 })
  A.list(ids(d[1]), { 3 }, "the gear tab is now first")
  A.list(ids(d[2]), { 2, 4, 1 }, "food moved right, and Monkfish follows the food tab")
  d = Blueprint.buildFromTabs(items, sections, Blueprint.resolver({}), {}, { 1, 1 })
  A.list(ids(d[1]), { 2, 4, 1 }, "a broken order is ignored")
  d = Blueprint.buildFromTabs(items, sections, Blueprint.resolver({}), {}, { 2, 1, 3 })
  A.list(ids(d[1]), { 2, 4, 1 }, "an order for a different number of tabs is ignored")
end

return T
