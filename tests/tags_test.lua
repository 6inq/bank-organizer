-- Bank Organizer tests: tags on items, rares, decanting and vertical order.
--
-- Requirements covered: tags place items at the top or bottom of the
-- infinity tab or first in their own tab; rares count as Vanity; decantable
-- part doses are found per potion family; vertical order fills columns; and
-- tags are saved per item.

local A = require("assert")
local Blueprint = require("src/core/blueprint")
local Layout = require("src/core/layout")
local Sorting = require("src/core/sorting")
local Classify = require("src/core/classify")
local Placement = require("src/core/placement")
local Guide = require("src/core/guide")
local Order = require("src/core/order")
local Preset = require("src/core/preset")
local Store = require("src/core/store")

local T = {}

-- Builds a bank item with right-click options and a stack size.
local function item(slot, name, ops, quantity)
  local set = {}
  for _, op in ipairs(ops or {}) do set[op] = true end
  return { slot = slot, id = slot, name = name, quantity = quantity or 1, info = { name = name, ops = set } }
end

-- Returns the names of planned entries, in order.
local function names(list)
  local out = {}
  for index, entry in ipairs(list) do out[index] = entry.name end
  return out
end

-- Turns "item id -> one tag key" into the build option that reports each
-- item's set of tags.
local function marked(marks)
  return { tagsOf = function(it) return marks[it.id] and { [marks[it.id]] = true } or nil end }
end

-- Requirement: Placement groups order the infinity tab.
function T.placement_groups_order_the_infinity_tab()
  local items = {
    item(1, "Abyssal whip", { "wield" }), item(2, "Shark", { "eat" }), item(3, "Coins"), item(4, "Red partyhat"),
    item(5, "Air rune"), item(6, "Prayer potion (4)", { "drink" }), item(7, "Dragon dagger", { "wield" }), item(8, "Bones"),
  }
  local marks = { [1] = "sell", [2] = "active", [5] = "trash", [6] = "alch", [7] = "disassemble" }
  local d = Blueprint.build(items, Layout.new("main"), Blueprint.resolver({}), "smart", marked(marks))
  local infinity = names(d[0])
  A.eq(infinity[1], "Shark", "Active first")
  A.eq(infinity[2], "Red partyhat", "then Vanity & Rares")
  A.eq(infinity[3], "Coins", "then the infinity tab's own items")
  A.list({ infinity[#infinity - 3], infinity[#infinity - 2], infinity[#infinity - 1], infinity[#infinity] },
    { "Abyssal whip", "Prayer potion (4)", "Dragon dagger", "Air rune" }, "Sell, Alch, Disassemble, Trash at the bottom")
  A.eq(#d[1], 0, "the whip and dagger left the combat tab")
end

-- Requirement: Favourite sorts first in its own tab.
function T.favourite_sorts_first_in_its_own_tab()
  local items = { item(1, "Abyssal whip", { "wield" }), item(2, "Rune scimitar", { "wield" }), item(3, "Dragon dagger", { "wield" }) }
  local layout = Layout.new("main")
  local d = Blueprint.build(items, layout, Blueprint.resolver({}), "smart", marked({ [2] = "favourite" }))
  A.eq(d[layout:destinationOf("gear")][1].name, "Rune scimitar")
  A.eq(#d[0], 0, "a favourite stays in its own tab")
end

-- Requirement: My tabs tags beat pins and homes.
function T.my_tabs_tags_beat_pins_and_homes()
  local items = { item(1, "Abyssal whip", { "wield" }), item(2, "Rune scimitar", { "wield" }), item(3, "Red partyhat") }
  local sections = { [0] = {}, [1] = { 1, 2, 3 } }
  local d = Blueprint.buildFromTabs(items, sections, Blueprint.resolver({}), { gear = 1 }, nil, "smart", marked({ [2] = "sell" }))
  A.list(names(d[0]), { "Red partyhat", "Rune scimitar" }, "the rare goes to the top of infinity, the sell item to the bottom")
  A.list(names(d[1]), { "Abyssal whip" }, "the pin keeps only the untagged gear")
end

-- Requirement: Rares are recognised and look alikes are not.
function T.rares_are_recognised_and_look_alikes_are_not()
  for _, name in ipairs({ "Red partyhat", "White partyhat", "Green halloween mask", "Santa hat", "Black santa hat", "Christmas cracker" }) do
    A.eq(Classify.classify({ name = name }), "vanity", name)
  end
  for _, name in ipairs({ "Partyhat & specs", "Santa costume top", "Cracker", "Halloween wig", "Blue partyhat token" }) do
    A.truthy(Classify.classify({ name = name }) ~= "vanity", name .. " must not count as a rare")
  end
  local rare = Placement.resolve(nil, "vanity")
  A.eq(rare.move.key, "vanity", "a rare counts as tagged Vanity"); A.eq(rare.infinity, true)
  A.eq(Placement.resolve({ favourite = true }, "gear").infinity, false, "a favourite stays in its own tab")
end

-- Builds a potion entry for decant checks.
local function potion(id, name, quantity)
  return { id = id, name = name, quantity = quantity or 1, tag = "potions" }
end

-- Requirement: Decant counts doses per family.
function T.decant_counts_doses_per_family()
  local info = Sorting.decantInfo({
    potion(1, "Prayer potion (3)"), potion(2, "Prayer potion (1)"),
    potion(3, "Super restore (2)"),
    potion(4, "Super attack (2)", 2),
    potion(5, "Saradomin brew flask (5)"),
    potion(6, "Overload flask (5)"), potion(7, "Overload flask (2)"),
    potion(8, "Prayer potion (4)"), potion(9, "Overload (3)"),
  })
  A.eq(info[1].canDecant, true, "3 + 1 doses make a full vial"); A.eq(info[2].canDecant, true)
  A.eq(info[3].canDecant, false, "2 doses alone cannot")
  A.eq(info[4].canDecant, true, "a stack of two 2-dose potions makes one full vial")
  A.eq(info[5].canDecant, false, "5 doses fall short of a full flask")
  A.eq(info[6].canDecant, true, "5 + 2 flask doses make a full flask"); A.eq(info[6].kind, "flask")
  A.eq(info[8], nil, "a full vial needs no decanting")
  A.eq(info[9].canDecant, false, "vials and flasks of one potion are counted apart")
end

-- Requirement: Part doses that cannot decant sink to the bottom of the herb tab.
function T.part_doses_that_cannot_decant_sink_to_the_bottom_of_the_herb_tab()
  local items = {
    item(1, "Super restore (2)", { "drink" }), item(2, "Clean irit"), item(3, "Super attack (4)", { "drink" }), item(4, "Prayer potion (4)", { "drink" }),
  }
  local tags = { "potion-doses", "clean-herbs", "potions", "potions" }
  local layout = Layout.new("main")
  for _, tag in ipairs({ "potions", "potion-doses", "clean-herbs" }) do layout:moveTag(tag, 3) end
  local decant = Sorting.decantInfo({ { id = 1, name = "Super restore (2)", quantity = 1, tag = "potion-doses" } })
  local d = Blueprint.build(items, layout, function(it) return tags[it.id] end, "smart", { decant = decant })
  A.eq(d[3][#d[3]].name, "Super restore (2)", "nothing to decant it with, so it waits at the bottom")
end

-- Requirement: Vertical layouts fill columns.
function T.vertical_layouts_fill_columns()
  local letters = { "a", "b", "c", "d", "e", "f", "g" }
  A.list(Sorting.vertical(letters, 3), { "a", "d", "f", "b", "e", "g", "c" }, "7 items in 3 columns: the left column is tallest")
  A.list(Sorting.vertical({ "a", "b", "c", "d", "e", "f" }, 3), { "a", "c", "e", "b", "d", "f" }, "a full grid reads down each column")
  A.list(Sorting.vertical({ "a", "b", "c" }, 3), { "a", "b", "c" }, "one row is the same either way")
  A.list(Sorting.vertical({ "a", "b" }, 8), { "a", "b" }, "fewer items than columns")
  A.list(Sorting.vertical(letters, nil), letters, "unknown columns: rows")
end

-- Requirement: Keep my order ignores the direction.
function T.keep_my_order_ignores_the_direction()
  local items = {}
  for slot, name in ipairs({ "Coins", "Bones", "Air rune", "Shark", "Abyssal whip" }) do items[slot] = item(slot, name) end
  local d = Blueprint.build(items, Layout.new("main"), function() return "cleanup" end, "keep", { vertical = true, columns = 2 })
  local horizontal = Blueprint.build(items, Layout.new("main"), function() return "cleanup" end, "keep")
  local layout = Layout.new("main")
  A.list(names(d[layout:destinationOf("cleanup")]), names(horizontal[layout:destinationOf("cleanup")]))
end

-- Requirement: A vertical plan is reached move by move.
function T.a_vertical_plan_is_reached_move_by_move()
  local items, ids = {}, {}
  for slot = 1, 40 do
    items[slot] = item(slot, string.format("Thing %02d", (slot * 17) % 40))
    ids[slot] = slot
  end
  local d = Blueprint.build(items, Layout.new("main"), function() return "cleanup" end, "smart", { vertical = true, columns = 8 })
  local destinations = { identity = true, [0] = d[Layout.new("main"):destinationOf("cleanup")] }
  local sections = { [0] = ids }
  local moves = Guide.remaining(sections, destinations, Guide.INSERT)
  for _ = 1, 80 do
    local step = Guide.next(sections, destinations, Guide.INSERT)
    if not step then break end
    sections[0] = Order.apply(sections[0], step)
    moves = moves - 1
  end
  A.eq(moves, 0, "exactly as many moves as counted")
  for index, entry in ipairs(destinations[0]) do A.eq(sections[0][index], entry.id) end
end

-- Requirement: Share codes carry the direction.
function T.share_codes_carry_the_direction()
  local db = { data = {} }
  -- An in-memory database stand-in.
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  local store = Store.new(db)
  store:set("direction", "vertical")
  local other = Store.new({ data = {}, GetStructuredData = db.GetStructuredData, SetStructuredData = db.SetStructuredData })
  Preset.apply(other, assert(Preset.decode(Preset.encode(store))))
  A.eq(other:get("direction"), "vertical")
  local old = assert(Preset.decode("BO1|s=tabs|o=smart|t=runes/gear|n=|p="))
  A.eq(old.direction, nil, "codes from before 1.4.1 still load")
end

-- Requirement: tags are saved per item, several per item, and Clear all
-- tags removes them all.
function T.tags_save_and_clear()
  local db = { data = {} }
  -- An in-memory database stand-in.
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  local store = Store.new(db)
  A.eq(store:setTag(101, "sell", true), true); A.eq(store:setTag(102, "bogus", true), false)
  store:setTag(103, "trash", true); store:setTag(103, "vanity", true)
  local again = Store.new(db)
  A.eq(again:hasTag(101, "sell"), true)
  A.eq(again:hasTag(103, "trash"), true, "an item keeps every tag it was given")
  A.eq(again:hasTag(103, "vanity"), true)
  A.eq(again:markCounts().sell, 1)
  again:setTag(103, "trash", false)
  A.eq(Store.new(db):hasTag(103, "trash"), false, "one tag removed, the other stays")
  A.eq(Store.new(db):hasTag(103, "vanity"), true)
  again:clearMarks()
  A.eq(Store.new(db):hasTag(101, "sell"), false)
end

return T
