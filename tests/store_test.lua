local A = require("assert")
local Store = require("src/core/store")
local Categories = require("src/core/categories")

local function fakeDb(initial)
  local db = { data = initial or {}, writes = 0 }
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value)
    self.writes = self.writes + 1
    local copy = {}
    for k, v in pairs(value) do copy[k] = v end
    self.data[key] = copy
  end
  return db
end

local T = {}

function T.defaults()
  local store = Store.new(fakeDb())
  A.eq(store:get("sortMode"), "id"); A.eq(store:get("overlays"), true)
  A.eq(store:get("filter"), "all"); A.eq(store:get("highlightUntagged"), false)
  A.eq(store:get("tagging"), false); A.eq(store:get("opacity"), 0.35)
  A.eq(store:colour("food"), Categories.byKey.food.colour)
end

function T.tag_set_get_clear_persists()
  local db = fakeDb()
  local store = Store.new(db)
  A.truthy(store:setTag(1511, "materials"))
  A.eq(Store.new(db):getTag(1511), "materials", "reload sees tag")
  store:clearTag(1511)
  A.eq(Store.new(db):getTag(1511), nil, "reload sees cleared tag")
end

function T.invalid_tag_rejected()
  local store = Store.new(fakeDb())
  A.eq(store:setTag(1, "nope"), false); A.eq(store:getTag(1), nil)
end

function T.clear_all_tags()
  local db = fakeDb()
  local store = Store.new(db)
  store:setTag(1, "food"); store:setTag(2, "combat")
  store:clearAllTags()
  local reloaded = Store.new(db)
  A.eq(reloaded:getTag(1), nil); A.eq(reloaded:getTag(2), nil)
end

function T.invalid_stored_data_sanitized()
  local db = fakeDb({
    [Store.TAGS_KEY] = { ["12"] = "food", ["abc"] = "food", ["13"] = "bogus", [14.0] = "combat" },
    [Store.SETTINGS_KEY] = { sortMode = "random", opacity = 5, filter = "bogus", overlays = "yes",
      colours = { food = 0x112233FF, bogus = 1, combat = -5, potions = 0x445566FF + 0.0 } },
  })
  local store = Store.new(db)
  A.eq(store:getTag(12), "food"); A.eq(store:getTag(13), nil); A.eq(store:getTag(14), "combat")
  A.eq(store:get("sortMode"), "id"); A.eq(store:get("opacity"), 0.35)
  A.eq(store:get("filter"), "all"); A.eq(store:get("overlays"), true)
  A.eq(store:colour("food"), 0x112233FF); A.eq(store:colour("combat"), Categories.byKey.combat.colour)
  A.eq(store:colour("potions"), 0x445566FF)
end

function T.non_table_storage_tolerated()
  local store = Store.new(fakeDb({ [Store.TAGS_KEY] = "garbage", [Store.SETTINGS_KEY] = 42 }))
  A.eq(store:get("sortMode"), "id"); A.eq(store:getTag(1), nil)
end

function T.throwing_db_tolerated()
  local db = {}
  function db:GetStructuredData() error("boom") end
  function db:SetStructuredData() error("boom") end
  local store = Store.new(db)
  A.truthy(store:setTag(1, "food"), "set still succeeds in memory")
  A.eq(store:getTag(1), "food")
end

function T.settings_validate_and_persist()
  local db = fakeDb()
  local store = Store.new(db)
  A.eq(store:set("sortMode", "name"), true); A.eq(store:set("sortMode", "bad"), false)
  A.eq(store:set("unknown", 1), false); A.eq(store:set("opacity", 1.5), false)
  A.eq(store:setColour("food", 0xABCDEF80), true); A.eq(store:setColour("bogus", 1), false)
  local reloaded = Store.new(db)
  A.eq(reloaded:get("sortMode"), "name"); A.eq(reloaded:colour("food"), 0xABCDEF80)
end

function T.highlight_colours_default_set_and_reset()
  local db = fakeDb()
  local store = Store.new(db)
  A.eq(store:colour("move"), Store.HIGHLIGHT_DEFAULTS.move); A.eq(store:colour("target"), Store.HIGHLIGHT_DEFAULTS.target)
  A.eq(store:colour("dim"), Store.HIGHLIGHT_DEFAULTS.dim); A.eq(store:colour("untagged"), nil, "follows category colour")
  for _, key in ipairs({ "move", "target", "dim", "untagged", "food" }) do
    A.eq(store:setColour(key, 0x11223344), true, key)
  end
  local reloaded = Store.new(db)
  for _, key in ipairs({ "move", "target", "dim", "untagged", "food" }) do A.eq(reloaded:colour(key), 0x11223344, key) end
  A.eq(store:setColour("nope", 0x11223344), false)
  reloaded:resetColours()
  local reset = Store.new(db)
  A.eq(reset:colour("move"), Store.HIGHLIGHT_DEFAULTS.move); A.eq(reset:colour("untagged"), nil)
  A.eq(reset:colour("food"), Categories.byKey.food.colour)
end

return T
