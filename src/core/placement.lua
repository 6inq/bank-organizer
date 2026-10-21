local Placement = {}

Placement.LIST = {
  { key = "active", label = "Active", badge = "ACTIVE", group = 1, infinity = true },
  { key = "vanity", label = "Vanity", group = 2, infinity = true },
  { key = "favourite", label = "Favourite", badge = "FAV", group = 0, infinity = false },
  { key = "sell", label = "Sell", badge = "SELL", group = 4, infinity = true },
  { key = "alch", label = "Alch", badge = "ALCH", group = 5, infinity = true },
  { key = "disassemble", label = "Disassemble", badge = "DIS", group = 6, infinity = true },
  { key = "trash", label = "Trash", badge = "TRASH", group = 7, infinity = true },
}

Placement.NORMAL = 3
Placement.RARES_TAG = "vanity"

Placement.byKey = {}
for _, mark in ipairs(Placement.LIST) do Placement.byKey[mark.key] = mark end

function Placement.isValid(key)
  return Placement.byKey[key] ~= nil
end

function Placement.effective(mark, tag)
  if Placement.byKey[mark] then return Placement.byKey[mark] end
  if tag == Placement.RARES_TAG then return Placement.byKey.vanity end
  return nil
end

function Placement.group(mark, tag)
  local placement = Placement.effective(mark, tag)
  return placement and placement.group or Placement.NORMAL
end

function Placement.toInfinity(mark, tag)
  local placement = Placement.effective(mark, tag)
  return placement ~= nil and placement.infinity
end

local WHERE = {
  active = "top of infinity", vanity = "top of infinity, with rares", favourite = "first in its tab",
  sell = "bottom of infinity", alch = "bottom of infinity", disassemble = "bottom of infinity", trash = "bottom of infinity",
}

function Placement.describe(key)
  return WHERE[key] or ""
end

function Placement.badge(mark)
  local placement = Placement.byKey[mark]
  return placement and placement.badge or nil
end

return Placement
