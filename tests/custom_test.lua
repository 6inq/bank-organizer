-- Bank Organizer tests: custom categories and custom tags (store and plan).
--
-- Requirements covered:
--   * custom categories can be created, renamed, recoloured and deleted, and
--     survive a restart
--   * precedence: the player's own choice > category name rules > the
--     built-in classifier; review-list removals keep an item out
--   * deleting a category sends its items back to automatic sorting
--   * custom tags can be created, edited and deleted; labels are cut to 6
--     characters; every placement works
--   * an item can carry any combination of tags; the priority list decides
--     placement and label; label-only tags never move items
--   * saves from before 1.4.2 (one tag per item) still load

local A = require("assert")
local Store = require("src/core/store")
local Tags = require("src/core/tags")
local Placement = require("src/core/placement")
local Blueprint = require("src/core/blueprint")
local Layout = require("src/core/layout")
local Custom = require("src/core/custom")

local T = {}

-- Returns an in-memory database.
local function memoryDb()
  local db = { data = {} }
  -- An in-memory database stand-in.
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  return db
end

-- Builds a bank item the way the bank reader does.
local function item(slot, name, ops)
  local set = {}
  for _, op in ipairs(ops or {}) do set[op] = true end
  return { slot = slot, id = slot, objectId = slot, name = name, quantity = 1, info = { name = name, ops = set } }
end

-- Returns the names in a list of planned entries.
local function names(list)
  local out = {}
  for index, entry in ipairs(list) do out[index] = entry.name end
  return out
end

-- Requirement: create, rename, recolour and delete a category, and keep it
-- across a restart.
function T.categories_are_created_edited_and_deleted()
  local db = memoryDb()
  local store = Store.new(db)
  local key = store:addCategory("  Slayer stuff  ", 0x112233FF)
  A.eq(key, "custom-1")
  A.eq(Tags.isValid(key), true, "a new kind of item")
  A.eq(Tags.label(key), "Slayer stuff", "the name is trimmed")
  A.eq(store.layout:destinationOf(key), 0, "new categories start in the infinity tab")
  A.eq(store:colour(key), 0x112233FF)
  local again = Store.new(db)
  A.eq(again:category(key).name, "Slayer stuff", "saved")
  A.eq(again:editCategory(key, { name = "Slayer" }), true)
  A.eq(again:setColour(key, 0x445566FF), true, "recolouring through the colour settings edits the category")
  A.eq(Store.new(db):category(key).colour, 0x445566FF)
  A.eq(Store.new(db):category(key).name, "Slayer")
  A.eq(again:editCategory(key, { name = "   " }), false, "a category needs a name")
  A.eq(again:addCategory(""), nil, "an empty name makes nothing")
  A.eq(again:addCategory("Second"), "custom-2", "keys count up")
  A.eq(again:deleteCategory(key), true)
  A.eq(Tags.isValid(key), false, "gone")
  A.eq(Store.new(db):category(key), nil, "gone after a restart too")
  A.eq(again:deleteCategory("custom-99"), false)
end

-- Requirement: names are cut to 40 characters and there is a limit on how
-- many categories can exist.
function T.category_limits()
  local store = Store.new(memoryDb())
  local key = store:addCategory(string.rep("a", 60))
  A.eq(#store:category(key).name, Custom.MAX_NAME)
  for n = 2, Custom.MAX_CATEGORIES do A.truthy(store:addCategory("C" .. n)) end
  A.eq(store:addCategory("One too many"), nil)
end

-- Requirement: player's choice > name rules > classifier.
function T.rules_sit_between_corrections_and_the_classifier()
  local store = Store.new(memoryDb())
  local key = store:addCategory("Dragon things")
  A.eq(store:addRule(key, "contains", "DRAGON"), true, "case is ignored")
  A.eq(store:addRule(key, "sideways", "x"), false, "unknown rule kinds are refused")
  A.eq(store:addRule(key, "contains", "  "), false, "empty rules are refused")
  -- A fresh resolver each time, so it sees the store's latest changes.
  local resolve = function() return Blueprint.resolver(store.corrections, { categories = store.customCategories, excluded = store.excluded }) end
  local bones, whip = item(1, "Dragon bones"), item(2, "Abyssal whip", { "wield" })
  A.eq(resolve()(bones), key, "the rule beats the classifier")
  A.eq(resolve()(whip), "gear", "items the rule does not match are classified as usual")
  store:correct(1, "food")
  A.eq(resolve()(bones), "food", "the player's own choice beats the rule")
  store:clearCorrection(1)
  store:exclude(key, 1)
  A.eq(resolve()(bones), "raw-resources", "removed from the review list: back to the classifier")
  store:restore(key, 1)
  A.eq(resolve()(bones), key, "restored")
end

-- Requirement: "starts with" rules only match at the start of the name.
function T.starts_with_rules_only_match_the_start()
  local rule = { kind = "starts", text = "Super" }
  A.eq(Custom.ruleMatches(rule, "super attack (4)"), true)
  A.eq(Custom.ruleMatches(rule, "antipoison super"), false)
  A.eq(Custom.ruleMatches({ kind = "contains", text = "100%" }, "a 100% thing"), true, "rule text is plain text, not a pattern")
end

-- Requirement: deleting a category sends its items back to automatic
-- sorting, removing choices, pins and removals that point at it.
function T.deleting_a_category_cleans_up_after_it()
  local db = memoryDb()
  local store = Store.new(db)
  local key = store:addCategory("Temp")
  store:correct(5, key)
  store:setTabHome(key, 2)
  store:exclude(key, 6)
  store.layout:moveTag(key, 3)
  store:deleteCategory(key)
  local again = Store.new(db)
  A.eq(again.corrections[5], nil); A.eq(again.tabHomes[key], nil); A.eq(again.excluded[key], nil)
  for d = 0, again.layout:last() do
    for _, kind in ipairs(again.layout.destinations[d]) do A.truthy(kind ~= key, "no longer in the Tab Layout") end
  end
end

-- Requirement: custom categories plan like built-in kinds: their own tab
-- in Whole bank, sorted by name inside it.
function T.custom_categories_plan_like_built_in_kinds()
  local store = Store.new(memoryDb())
  local key = store:addCategory("Bossing")
  store:addRule(key, "contains", "bones")
  store.layout:moveTag(key, 7)
  local items = { item(1, "Frost dragon bones"), item(2, "Abyssal whip", { "wield" }), item(3, "Dagannoth bones") }
  local resolver = Blueprint.resolver(store.corrections, { categories = store.customCategories, excluded = store.excluded })
  local d = Blueprint.build(items, store.layout, resolver, "smart", {})
  A.list(names(d[7]), { "Dagannoth bones", "Frost dragon bones" }, "together in their tab, by name")
end

-- Requirement: custom tags can be made with any placement; labels are cut
-- to 6 characters; bad input is refused.
function T.custom_tags_are_created_edited_and_deleted()
  local db = memoryDb()
  local store = Store.new(db)
  local key = store:addTag("Bossing", 0xFF0000FF, "top")
  A.eq(key, "tag-1")
  A.eq(store:customTag(key).label, "Bossin", "labels fit a slot: at most 6 characters")
  A.eq(Placement.isValid(key), true)
  A.eq(store.tagOrder[#store.tagOrder], key, "new tags join the end of the priority list")
  A.eq(store:addTag("X", nil, "sideways"), nil, "unknown placements are refused")
  A.eq(store:addTag("   ", nil, "top"), nil, "a tag needs a label")
  A.eq(store:editTag(key, { placement = "label", label = "Boss" }), true)
  A.eq(store:setColour(Placement.colourKey(key), 0x00FF00FF), true, "label colour through the colour settings")
  local again = Store.new(db)
  A.eq(again:customTag(key).placement, "label"); A.eq(again:customTag(key).label, "Boss")
  A.eq(again:colour(Placement.colourKey(key)), 0x00FF00FF)
  again:setTag(9, key, true)
  A.eq(again:deleteTag(key), true)
  A.eq(again:hasTag(9, key), false, "removed from every item")
  for _, other in ipairs(again.tagOrder) do A.truthy(other ~= key, "removed from the priority list") end
end

-- Requirement: with several tags, the highest in the priority list decides
-- where the item goes and which label shows.
function T.priority_decides_placement_and_label()
  local store = Store.new(memoryDb())
  local set = { sell = true, active = true }
  local placed = Placement.resolve(set, "gear", store.tagOrder)
  A.eq(placed.move.key, "active", "Active is above Sell by default")
  A.eq(placed.label.key, "active")
  A.truthy(placed.group < Placement.NORMAL, "top of infinity sorts before untagged items")
  store:moveTagPriority("sell", -1); store:moveTagPriority("sell", -1); store:moveTagPriority("sell", -1)
  A.eq(store.tagOrder[1], "sell", "Sell moved to the top")
  placed = Placement.resolve(set, "gear", store.tagOrder)
  A.eq(placed.move.key, "sell"); A.truthy(placed.group > Placement.NORMAL, "bottom of infinity sorts after untagged items")
  A.eq(store:moveTagPriority("sell", -1), false, "already at the top")
  store:resetTagOrder()
  A.eq(store.tagOrder[1], "active")
end

-- Requirement: label-only tags show their label but never move the item;
-- a lower moving tag still decides where it goes.
function T.label_only_tags_never_move_items()
  local store = Store.new(memoryDb())
  local key = store:addTag("Note", nil, "label")
  store:moveTagPriority(key, -10)
  for _ = 1, 10 do store:moveTagPriority(key, -1) end
  A.eq(store.tagOrder[1], key)
  local placed = Placement.resolve({ [key] = true }, "gear", store.tagOrder)
  A.eq(placed.label.key, key); A.eq(placed.move, nil); A.eq(placed.infinity, false)
  placed = Placement.resolve({ [key] = true, trash = true }, "gear", store.tagOrder)
  A.eq(placed.label.key, key, "the label-only tag is highest, so its label shows")
  A.eq(placed.move.key, "trash", "but Trash still decides where it goes")
  local items = { item(1, "Abyssal whip", { "wield" }) }
  local layout = Layout.new("main")
  local d = Blueprint.build(items, layout, Blueprint.resolver({}), "smart", {
    -- The whip carries only the label-only tag.
    tagsOf = function() return { [key] = true } end, order = store.tagOrder })
  A.eq(#d[layout:destinationOf("gear")], 1, "the whip stays in the combat tab")
end

-- Requirement: every custom placement moves items where it says.
function T.custom_placements_move_items()
  local store = Store.new(memoryDb())
  local top, bottom, first = store:addTag("Top", nil, "top"), store:addTag("Bot", nil, "bottom"), store:addTag("First", nil, "first")
  local items = {
    item(1, "Abyssal whip", { "wield" }), item(2, "Rune scimitar", { "wield" }), item(3, "Coins"), item(4, "Dragon dagger", { "wield" }),
  }
  local tags = { [1] = { [top] = true }, [2] = { [first] = true }, [4] = { [bottom] = true } }
  local layout = Layout.new("main")
  local d = Blueprint.build(items, layout, Blueprint.resolver({}), "smart", {
    -- Each item's custom tag, in the store's priority order.
    tagsOf = function(it) return tags[it.id] end, order = store.tagOrder })
  A.list(names(d[0]), { "Abyssal whip", "Coins", "Dragon dagger" }, "top of infinity, untagged, bottom of infinity")
  A.list(names(d[layout:destinationOf("gear")]), { "Rune scimitar" }, "first in its own tab stays in that tab")
end

-- Requirement: saves from 1.4.1 (one tag per item as a string) still load,
-- and unknown tags are dropped.
function T.old_one_tag_saves_still_load()
  local db = memoryDb()
  db.data[Store.KEY] = { marks = { ["101"] = "sell", ["102"] = "bogus", ["103"] = { "trash", "alch" }, ["104"] = { vanity = true } } }
  local store = Store.new(db)
  A.eq(store:hasTag(101, "sell"), true, "a 1.4.1 save")
  A.eq(next(store:tagsOf(102)), nil, "an unknown tag is dropped")
  A.eq(store:hasTag(103, "trash"), true); A.eq(store:hasTag(103, "alch"), true)
  A.eq(store:hasTag(104, "vanity"), true)
  A.eq(#store.tagOrder, #Placement.LIST, "no saved priority list: the default one")
end

-- Requirement: damaged custom definitions in a save never break loading.
function T.damaged_definitions_are_cleaned()
  local db = memoryDb()
  db.data[Store.KEY] = {
    customCategories = { { key = "custom-1", name = "Ok", colour = "red", rules = { { kind = "contains", text = "x" }, { kind = "bad" } } },
      { key = "evil", name = "No" }, "junk", { key = "custom-1", name = "Duplicate" } },
    customTags = { { key = "tag-1", label = "Ok", placement = "top" }, { key = "tag-2", label = "No", placement = "nowhere" } },
    tagOrder = { "tag-1", "nope", "sell" },
  }
  local store = Store.new(db)
  A.eq(#store.customCategories, 1); A.eq(store.customCategories[1].colour, Custom.DEFAULT_COLOUR, "a bad colour falls back")
  A.eq(#store.customCategories[1].rules, 1, "the bad rule is dropped")
  A.eq(#store.customTags, 1)
  A.list({ store.tagOrder[1], store.tagOrder[2] }, { "tag-1", "sell" }, "the saved order is kept and the rest added")
  A.eq(#store.tagOrder, #Placement.LIST)
end

return T
