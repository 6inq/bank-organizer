-- Bank Organizer: live Grand Exchange prices.
--
-- Prices come from the GE Price Library plugin (a required dependency,
-- available to this plugin as the global "gepl"). Bank Organizer itself
-- makes no network requests. When the library is missing or still loading,
-- the game's own item value is used instead (see Sorting.worth).
--
-- Every call into the library is wrapped in pcall(function() ... end), so a
-- problem in another plugin can never break this one.

local Prices = {}

-- Returns the price library, or nil when it is not loaded.
local function library()
  return gepl
end

-- Returns where prices come from right now:
--   "live"     the library has its latest prices
--   "loading"  the library is still downloading them
--   "none"     there is no library, or price fetching is switched off
function Prices.source()
  local lib = library()
  if lib == nil then return "none" end
  local ok, ready = pcall(function() return lib.isReady("latest") end)
  if not ok then return "none" end
  if ready then return "live" end
  local known, enabled = pcall(function() return lib.isFetchingOn() end)
  if known and enabled == false then return "none" end
  return "loading"
end

-- Returns the middle of the latest high and low trade prices, or whichever
-- one exists.
local function midpoint(latest)
  local high, low = tonumber(latest.high), tonumber(latest.low)
  if high and low then return math.floor((high + low) / 2) end
  return high or low
end

-- Returns an item's GE price in coins, or nil when there is none.
function Prices.of(itemID)
  local lib = library()
  if lib == nil then return nil end
  local ok, price = pcall(function()
    local latest = lib.getLatest(itemID)
    return latest and midpoint(latest)
  end)
  if ok and type(price) == "number" and price > 0 then return price end
  return nil
end

-- Writes each item's GE price into item.info.price (nil when there is no
-- live price) for Value sort. Returns the price source.
function Prices.attach(items)
  local source = Prices.source()
  for _, item in ipairs(items or {}) do
    if item.info then item.info.price = source == "live" and Prices.of(item.objectId or item.id) or nil end
  end
  return source
end

return Prices
