local A = require("assert")
local Preset = require("src/core/preset")
local Store = require("src/core/store")

local T = {}

local function memoryDb()
  local db = { data = {} }
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  return db
end

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

function T.codes_survive_extra_spaces()
  local code = "  " .. Preset.encode(customStore()) .. "\n"
  A.truthy(Preset.decode(code))
end

function T.bad_codes_are_refused_with_a_reason()
  local _, reason = Preset.decode("hello")
  A.truthy(reason:find("not a Bank Organizer", 1, true))
  A.eq(Preset.decode(nil), nil)
  A.eq(Preset.decode("BO1|" .. string.rep("x", 5000)), nil)
end

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

return T
