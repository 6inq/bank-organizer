local A = require("assert")
local Sorting = require("src/core/sorting")
local Prices = require("src/game/prices")

local T = {}

local function library(opts)
  opts = opts or {}
  local lib = { ready = opts.ready ~= false, prices = opts.prices or {}, fetchingOn = opts.fetchingOn, lookups = 0 }
  lib.isReady = function(endpoint)
    A.eq(endpoint, "latest")
    if opts.readyError then error("broken") end
    return lib.ready
  end
  lib.isFetchingOn = function()
    if lib.fetchingOn == nil then return true end
    return lib.fetchingOn
  end
  lib.getLatest = function(itemID)
    lib.lookups = lib.lookups + 1
    local price = lib.prices[itemID]
    if price == nil then error("Price not found for itemId: " .. tostring(itemID)) end
    if price == false then return nil end
    return price
  end
  _G.gepl = lib
  return lib
end

local function gear(id, name, category, cost)
  return { slot = id, id = id, name = name, quantity = 1,
    info = { name = name, category = category, cost = cost, ops = { wield = true } } }
end

local function items()
  return {
    gear(1, "Abyssal whip", "WEAPON_WHIP", 120000),
    gear(2, "Torva full helm", "ARMOUR_HELMET", 9000000),
    gear(3, "Bronze dagger", "WEAPON_DAGGER", 10),
    gear(4, "Armadyl chestplate", "ARMOUR_BODY", 4000000),
  }
end

local GE = {
  [1] = { high = 3000000, low = 2000000 },
  [2] = { high = 50000, low = 40000 },
  [3] = { high = 900, low = 700 },
  [4] = { high = 1000000, low = 1000000 },
}

local function app(list)
  _G.log = function() end
  _G.PersistentDB = nil
  for key in pairs(package.loaded) do if key:match("^src/") then package.loaded[key] = nil end end
  local Bank = require("src/game/bank")
  Bank.readItems = function() return list end
  Bank.slotsContainer = function() return nil end
  Bank.tabSizes = function() return nil end
  local Store = require("src/core/store")
  local App = require("src/app")
  local store = Store.new()
  store:set("sort", "value")
  local a = App.new(store)
  a.renders = 0
  a:onChange("count", function() a.renders = a.renders + 1 end)
  return a
end

local function planned(a)
  local names = {}
  for index, entry in ipairs(a.destinations[a.store.layout:destinationOf("gear")]) do names[index] = entry.name end
  return names
end

local function valueLabel(source)
  for _, entry in ipairs(Sorting.modes(source)) do
    if entry.key == "value" then return entry.label end
  end
end

function T.ge_price_wins_over_item_value_when_known()
  library({ prices = GE })
  local a = app(items())
  a:analyze()
  A.list(planned(a), { "Abyssal whip", "Armadyl chestplate", "Torva full helm", "Bronze dagger" })
  A.eq(a:valueSource(), "live")
  _G.gepl = nil
end

function T.items_without_a_ge_price_fall_back_to_item_value()
  library({ prices = { [1] = GE[1], [3] = false } })
  local a = app(items())
  a:analyze()
  A.list(planned(a), { "Torva full helm", "Armadyl chestplate", "Abyssal whip", "Bronze dagger" },
    "helm and chestplate use cost 9m and 4m, whip uses its 2.5m GE price, dagger has no price")
  _G.gepl = nil
end

function T.loading_sorts_by_item_value_then_resorts_once_prices_arrive()
  local lib = library({ ready = false, prices = GE })
  local a = app(items())
  A.truthy(a:analyze(), "analyze never waits on prices")
  A.eq(a:valueSource(), "loading")
  A.eq(lib.lookups, 0, "no lookups before the library is ready")
  A.list(planned(a), { "Torva full helm", "Armadyl chestplate", "Abyssal whip", "Bronze dagger" })
  a:tick()
  A.eq(a:valueSource(), "loading", "still loading")
  lib.ready = true
  local before = a.renders
  a:tick()
  A.eq(a:valueSource(), "live")
  A.eq(a.renders, before + 1, "one rebuild when prices arrive")
  A.list(planned(a), { "Abyssal whip", "Armadyl chestplate", "Torva full helm", "Bronze dagger" })
  a:tick()
  A.eq(a.renders, before + 1, "no rebuild while nothing changes")
  _G.gepl = nil
end

function T.without_the_library_value_uses_item_value()
  _G.gepl = nil
  local a = app(items())
  a:analyze()
  A.eq(a:valueSource(), "none")
  A.list(planned(a), { "Torva full helm", "Armadyl chestplate", "Abyssal whip", "Bronze dagger" })
end

function T.a_broken_library_falls_back_without_crashing()
  library({ readyError = true, prices = GE })
  A.eq(Prices.source(), "none")
  local a = app(items())
  a:analyze()
  A.list(planned(a), { "Torva full helm", "Armadyl chestplate", "Abyssal whip", "Bronze dagger" })
  _G.gepl = nil
end

function T.price_fetching_turned_off_with_no_cache_is_item_value()
  library({ ready = false, fetchingOn = false })
  A.eq(Prices.source(), "none")
  library({ ready = true, fetchingOn = false, prices = GE })
  A.eq(Prices.source(), "live", "cached prices still count")
  _G.gepl = nil
end

function T.price_is_the_middle_of_buy_and_sell_or_whichever_is_known()
  library({ prices = { [1] = { high = 101, low = 100 }, [2] = { high = 70 }, [3] = { low = 30 }, [4] = { high = 0, low = 0 },
    [5] = { high = "bad" } } })
  A.eq(Prices.of(1), 100)
  A.eq(Prices.of(2), 70)
  A.eq(Prices.of(3), 30)
  A.eq(Prices.of(4), nil, "zero is not a price")
  A.eq(Prices.of(5), nil, "junk is not a price")
  A.eq(Prices.of(99), nil, "unknown item")
  _G.gepl = nil
end

function T.attach_clears_old_prices_when_not_live()
  local list = items()
  library({ prices = GE })
  A.eq(Prices.attach(list), "live")
  A.eq(list[2].info.price, 45000)
  _G.gepl.ready = false
  A.eq(Prices.attach(list), "loading")
  A.eq(list[2].info.price, nil)
  _G.gepl = nil
end

function T.sort_label_says_which_value_is_used()
  A.truthy(valueLabel("live"):find("GE price", 1, true))
  A.truthy(valueLabel("loading"):find("until GE prices load", 1, true))
  A.truthy(valueLabel("none"):find("item value", 1, true))
  A.eq(valueLabel("none"), "Value: item value (highest first)")
  A.eq(#Sorting.modes("live"), #Sorting.MODES)
  A.eq(Sorting.modes("live")[1].label, Sorting.MODES[1].label, "other modes unchanged")
end

function T.worth_prefers_price_then_cost()
  A.eq(Sorting.worth({ price = 5, cost = 9 }), 5)
  A.eq(Sorting.worth({ cost = 9 }), 9)
  A.eq(Sorting.worth({}), 0)
  A.eq(Sorting.worth(nil), 0)
end

function T.other_sort_modes_never_touch_prices()
  local lib = library({ ready = false, prices = GE })
  local a = app(items())
  a.store:set("sort", "smart")
  a:analyze()
  local before = a.renders
  lib.ready = true
  a:tick()
  A.eq(a.renders, before, "no rebuild")
  A.eq(lib.lookups, 0, "no lookups")
  _G.gepl = nil
end

return T
