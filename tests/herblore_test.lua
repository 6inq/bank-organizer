-- Bank Organizer tests: Smart herblore order, recipe by recipe.
--
-- Requirements covered:
--   * empty vials, then vials of water, then other vial types come first
--   * each recipe reads: grimy herb, clean herb, unfinished potion,
--     secondary, vial doses (1) to (4), flask doses (1) to (6)
--   * a herb or secondary shared by several recipes goes with the first
--   * the overload family stays together
--   * Secondaries "at the bottom" moves every secondary after the rest
--   * decant labels on: part doses that cannot decant sink to the bottom;
--     decant labels off: part doses stay with their potion
--   * herblore items not in the recipe table still sort after the recipes

local A = require("assert")
local Blueprint = require("src/core/blueprint")
local Layout = require("src/core/layout")
local Sorting = require("src/core/sorting")

local T = {}

-- Every herblore kind, so they can all be put in one tab for the test.
local HERBLORE = { "potions", "potion-doses", "clean-herbs", "grimy-herbs", "unfinished-potions", "secondaries", "herblore-other" }

-- Plans one tab of herblore items and returns their names in order.
--   rows  list of { name, kind }
--   opts  optional build options (decant, secondaries)
local function plan(rows, opts)
  local items, tags = {}, {}
  for slot, row in ipairs(rows) do
    items[slot] = { slot = slot, id = slot, name = row[1], quantity = row[3] or 1, info = { name = row[1], ops = {} } }
    tags[slot] = row[2]
  end
  local layout = Layout.new("main")
  for _, tag in ipairs(HERBLORE) do layout:moveTag(tag, 3) end
  local d = Blueprint.build(items, layout, function(it) return tags[it.slot] end, "smart", opts)
  local names = {}
  for index, entry in ipairs(d[3]) do names[index] = entry.name end
  return names
end

-- Returns rows in reverse, so tests never pass because the input was
-- already in order.
local function reversed(rows)
  local out = {}
  for index = #rows, 1, -1 do out[#out + 1] = rows[index] end
  return out
end

-- Requirement: vials first, then each recipe in the exact stage order.
function T.vials_first_then_each_recipe_stage_by_stage()
  local rows = {
    { "Vial", "herblore-other" }, { "Vial of water", "secondaries" }, { "Bomb vial", "herblore-other" },
    { "Grimy irit", "grimy-herbs" }, { "Clean irit", "clean-herbs" }, { "Irit potion (unf)", "unfinished-potions" },
    { "Eye of newt", "secondaries" }, { "Super attack (1)", "potion-doses" }, { "Super attack (2)", "potion-doses" },
    { "Super attack (3)", "potion-doses" }, { "Super attack (4)", "potions" }, { "Super attack flask (3)", "potions" },
    { "Super attack flask (6)", "potions" }, { "Grimy avantoe", "grimy-herbs" }, { "Clean avantoe", "clean-herbs" },
    { "Extreme attack (4)", "potions" },
  }
  local expected = {}
  for index, row in ipairs(rows) do expected[index] = row[1] end
  A.list(plan(reversed(rows)), expected)
end

-- Requirement: a herb used by several recipes goes with the first one in
-- recipe order (dwarf weed: extreme strength before super ranging).
function T.a_shared_herb_goes_with_its_first_recipe()
  local order = plan({
    { "Super ranging (4)", "potions" }, { "Wine of zamorak", "secondaries" }, { "Clean dwarf weed", "clean-herbs" },
    { "Extreme strength (4)", "potions" }, { "Super strength (4)", "potions" },
  })
  A.list(order, { "Super strength (4)", "Clean dwarf weed", "Extreme strength (4)", "Wine of zamorak", "Super ranging (4)" })
end

-- Requirement: every part of the overload family stays together, with
-- torstol and the overload itself last in that family.
function T.the_overload_family_stays_together()
  local order = plan({
    { "Prayer potion (4)", "potions" }, { "Overload (4)", "potions" }, { "Clean torstol", "clean-herbs" },
    { "Extreme magic (4)", "potions" }, { "Ground mud runes", "secondaries" }, { "Super magic (4)", "potions" },
    { "Clean lantadyme", "clean-herbs" },
  })
  A.list(order, { "Clean lantadyme", "Super magic (4)", "Ground mud runes", "Extreme magic (4)", "Clean torstol", "Overload (4)",
    "Prayer potion (4)" }, "lantadyme goes with extreme defence, the first recipe that uses it")
end

-- Requirement: "At the bottom of the tab" puts every secondary after the
-- rest of the herblore items, still in recipe order.
function T.secondaries_at_the_bottom()
  local rows = {
    { "Snape grass", "secondaries" }, { "Prayer potion (4)", "potions" }, { "Eye of newt", "secondaries" },
    { "Super attack (4)", "potions" }, { "Clean ranarr", "clean-herbs" },
  }
  A.list(plan(rows), { "Eye of newt", "Super attack (4)", "Clean ranarr", "Snape grass", "Prayer potion (4)" }, "with their potion")
  A.list(plan(rows, { secondaries = "bottom" }), { "Super attack (4)", "Clean ranarr", "Prayer potion (4)", "Eye of newt", "Snape grass" })
end

-- Requirement: decant labels on sinks part doses that cannot decant to the
-- very bottom (below secondaries at the bottom); decant labels off keeps
-- them with their potion.
function T.decant_setting_decides_whether_part_doses_sink()
  local rows = {
    { "Super restore (2)", "potion-doses" }, { "Super restore (4)", "potions" }, { "Snapdragon potion (unf)", "unfinished-potions" },
    { "Red spiders' eggs", "secondaries" }, { "Prayer potion (4)", "potions" },
  }
  local items = {}
  for index, row in ipairs(rows) do items[index] = { id = index, name = row[1], quantity = 1, tag = row[2] } end
  local decant = Sorting.decantInfo(items)
  A.eq(decant[1].canDecant, false, "one lone 2-dose restore cannot make a full potion")
  A.list(plan(rows), { "Prayer potion (4)", "Snapdragon potion (unf)", "Red spiders' eggs", "Super restore (2)", "Super restore (4)" },
    "labels off: the part dose stays with its potion")
  A.list(plan(rows, { decant = decant }), { "Prayer potion (4)", "Snapdragon potion (unf)", "Red spiders' eggs", "Super restore (4)", "Super restore (2)" },
    "labels on: it waits at the bottom")
  A.list(plan(rows, { decant = decant, secondaries = "bottom" }),
    { "Prayer potion (4)", "Snapdragon potion (unf)", "Super restore (4)", "Red spiders' eggs", "Super restore (2)" },
    "below even the secondaries at the bottom")
end

-- Requirement: herblore items outside the recipe table sort after the
-- recipes, near their chain family, with doses ascending.
function T.unknown_herblore_items_come_after_the_recipes()
  local order = plan({
    { "Weapon poison (3)", "potion-doses" }, { "Zamorak brew (4)", "potions" }, { "Super attack (4)", "potions" },
    { "Weapon poison (1)", "potion-doses" },
  })
  A.eq(order[1], "Super attack (4)", "known recipes first")
  local first, third
  for index, name in ipairs(order) do
    if name == "Weapon poison (1)" then first = index end
    if name == "Weapon poison (3)" then third = index end
  end
  A.truthy(first < third, "doses ascending outside the recipes too")
end

return T
