-- Bank Organizer tests: share codes (src/core/preset.lua).
--
-- Requirements covered: a whole setup round-trips through a code; codes
-- survive extra spaces; bad codes are refused with a reason; unknown kinds
-- and values are dropped; custom categories, tags, priority order and
-- Secondaries travel; per-item data never does; old and future codes load.

local A = require("assert")
local Preset = require("src/core/preset")
local Store = require("src/core/store")

local T = {}

-- Returns an in-memory PersistentDB stand-in.
local function memoryDb()
  local db = { data = {} }
  -- An in-memory database stand-in.
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  return db
end

-- A store with a customised setup: an extra named tab (with separators in
-- its name), a moved kind, a renamed tab, My tabs, Value sort and a pin.
local function customStore()
  local store = Store.new(memoryDb())
  store.layout:addTab("Bossing | PvM, 100% & more")
  store.layout:moveTag("runes", 10)
  store.layout:rename(1, "Gear")
  store:set("scope", "tabs")
  store:set("sort", "value")
  store:setTabHome("xp-items", 3)
  return store
end

-- Requirement: A setup round trips through a code.
function T.a_setup_round_trips_through_a_code()
  local code = Preset.encode(customStore())
  A.truthy(code:sub(1, 4) == "BO1|", code)
  local other = Store.new(memoryDb())
  local preset = assert(Preset.decode(code))
  A.eq(Preset.apply(other, preset), 10)
  A.eq(other.layout:destinationOf("runes"), 10)
  A.eq(other.layout.names[10], "Bossing | PvM, 100% & more", "names with any characters survive")
  A.eq(other.layout.names[1], "Gear")
  A.eq(other:get("scope"), "tabs"); A.eq(other:get("sort"), "value")
  A.eq(other.tabHomes["xp-items"], 3)
end

-- Requirement: Codes survive extra spaces.
function T.codes_survive_extra_spaces()
  local code = "  " .. Preset.encode(customStore()) .. "\n"
  A.truthy(Preset.decode(code))
end

-- Requirement: Bad codes are refused with a reason.
function T.bad_codes_are_refused_with_a_reason()
  local _, reason = Preset.decode("hello")
  A.truthy(reason:find("not a Bank Organizer", 1, true))
  A.eq(Preset.decode(nil), nil)
  A.eq(Preset.decode("BO1|" .. string.rep("x", 7000)), nil)
end

-- Requirement: Unknown kinds and values are dropped not trusted.
function T.unknown_kinds_and_values_are_dropped_not_trusted()
  local preset = assert(Preset.decode("BO1|s=evil|o=os.execute|t=runes,not-a-tag/gear|n=1:Ok|p=gear:99,runes:0,fake:1"))
  A.eq(preset.scope, nil); A.eq(preset.sort, nil)
  A.list(preset.layout.tabs["0"], { "runes" })
  A.eq(preset.pins.gear, nil); A.eq(preset.pins.runes, 0); A.eq(preset.pins.fake, nil)
  local store = Store.new(memoryDb())
  Preset.apply(store, preset)
  A.eq(store.layout:destinationOf("gear"), 1)
  A.eq(store.layout:destinationOf("food"), 0, "kinds the code leaves out still have a home")
end

-- Requirement: custom categories (with rules), custom tags, the tag
-- priority order and the Secondaries setting travel in a code, and
-- separators in player text survive.
function T.custom_definitions_round_trip_with_any_characters()
  local store = Store.new(memoryDb())
  local tricky = "A|B,C:D%E~F;G"
  local key = store:addCategory(tricky, 0x12345678)
  store:addRule(key, "starts", tricky)
  store:addRule(key, "contains", "dragon")
  store.layout:moveTag(key, 4)
  store:setTabHome(key, 2)
  local tag = store:addTag("x|,:%", 0x0A0B0C0D, "bottom")
  store:moveTagPriority(tag, -1)
  store:set("secondaries", "bottom")
  local code = Preset.encode(store)
  local other = Store.new(memoryDb())
  Preset.apply(other, assert(Preset.decode(code)))
  local def = other:category(key)
  A.eq(def.name, tricky); A.eq(def.colour, 0x12345678)
  A.eq(def.rules[1].kind, "starts"); A.eq(def.rules[1].text, tricky); A.eq(def.rules[2].text, "dragon")
  A.eq(other.layout:destinationOf(key), 4, "the custom kind keeps its tab")
  A.eq(other.tabHomes[key], 2, "and its pin")
  A.eq(other:customTag(tag).label, "x|,:%"); A.eq(other:customTag(tag).placement, "bottom")
  A.eq(other.tagOrder[#other.tagOrder - 1], tag, "the priority order travels")
  A.eq(other:get("secondaries"), "bottom")
end

-- Requirement: tags on single items, hand-picked kinds, ignores, the Keep
-- list and review-list removals are never part of a code, and loading a
-- code leaves the loader's own per-item choices alone.
function T.per_item_data_stays_personal()
  local store = Store.new(memoryDb())
  local key = store:addCategory("Mine")
  store:setTag(555, "sell", true); store:correct(556, "food"); store:setIgnored(557, true)
  store:setKept(558, true); store:exclude(key, 559)
  local code = Preset.encode(store)
  for _, id in ipairs({ "555", "556", "557", "558", "559" }) do A.eq(code:find(id, 1, true), nil, "item " .. id .. " is not in the code") end
  local other = Store.new(memoryDb())
  other:setTag(777, "trash", true); other:correct(778, "runes")
  Preset.apply(other, assert(Preset.decode(code)))
  A.eq(other:hasTag(777, "trash"), true); A.eq(other.corrections[778], "runes")
  A.eq(other:hasTag(555, "sell"), false)
end

-- Requirement: codes from before 1.4.2 still load and keep the loader's
-- own custom categories and tags.
function T.old_codes_keep_your_own_custom_definitions()
  local store = Store.new(memoryDb())
  local key = store:addCategory("Mine")
  local tag = store:addTag("Mine", nil, "top")
  Preset.apply(store, assert(Preset.decode("BO1|s=bank|o=smart|t=runes/gear|n=|p=|d=horizontal")))
  A.eq(store:category(key).name, "Mine"); A.eq(store:customTag(tag).label, "Mine")
  A.eq(store:get("secondaries"), "with", "an old code leaves the setting alone")
end

-- Requirement: fields a version does not know are ignored, which is how
-- older versions read codes made by this one.
function T.unknown_fields_are_ignored()
  local code = "BO1|s=tabs|o=smart|t=runes/gear|z=from-the-future|q=1:2:3"
  local preset = assert(Preset.decode(code))
  A.eq(preset.scope, "tabs"); A.list(preset.layout.tabs["0"], { "runes" })
end

-- Requirement: a code that brings its own categories replaces the loader's
-- custom categories, and kinds the code does not define are dropped.
function T.a_new_code_replaces_custom_definitions()
  local code = Preset.encode(Store.new(memoryDb()))
  local mine = Store.new(memoryDb())
  local key = mine:addCategory("Mine")
  Preset.apply(mine, assert(Preset.decode(code)))
  A.eq(mine:category(key), nil, "their setup has no custom categories")
  A.eq(#mine.customCategories, 0)
end

return T
