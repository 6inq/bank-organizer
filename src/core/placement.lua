local Placement = {}

Placement.LIST = {
  { key = "active", label = "Active", badge = "Active", group = 1, infinity = true, colour = 0x6EE68AFF },
  { key = "vanity", label = "Vanity", badge = "Van", group = 2, infinity = true, colour = 0xD7A6FFFF },
  { key = "favourite", label = "Favourite", badge = "Fav", group = 0, infinity = false, colour = 0xFFD84DFF },
  { key = "sell", label = "Sell", badge = "Sell", group = 4, infinity = true, colour = 0x7FD3FFFF },
  { key = "alch", label = "Alch", badge = "Alch", group = 5, infinity = true, colour = 0xFFB04DFF },
  { key = "disassemble", label = "Disassemble", badge = "Dis", group = 6, infinity = true, colour = 0xD0D0D0FF },
  { key = "trash", label = "Trash", badge = "Trash", group = 7, infinity = true, colour = 0xFF7070FF },
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

Placement.DECANT = { key = "decant", label = "Decant", badge = "Decant", colour = 0xF2C94CFF }

function Placement.colourKey(key)
  return "label-" .. key
end

function Placement.labelColours()
  local list = {}
  for _, placement in ipairs(Placement.LIST) do list[#list + 1] = placement end
  list[#list + 1] = Placement.DECANT
  return list
end

function Placement.badge(mark, tag)
  local placement = Placement.effective(mark, tag)
  if not placement then return nil end
  return placement.badge, Placement.colourKey(placement.key)
end

return Placement
