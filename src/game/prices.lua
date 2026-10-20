local Prices = {}

local function library()
  return gepl
end

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

local function midpoint(latest)
  local high, low = tonumber(latest.high), tonumber(latest.low)
  if high and low then return math.floor((high + low) / 2) end
  return high or low
end

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

function Prices.attach(items)
  local source = Prices.source()
  for _, item in ipairs(items or {}) do
    if item.info then item.info.price = source == "live" and Prices.of(item.id) or nil end
  end
  return source
end

return Prices
