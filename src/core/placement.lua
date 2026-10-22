-- Bank Organizer: tags that place items and label their slots.
--
-- A tag is something the player puts on a single item from the right-click
-- Tags menu: Active, Vanity, Favourite, Sell, Alch, Disassemble, Trash, or a
-- custom tag they made. An item can carry any number of tags at once.
--
-- Tags are ranked by one priority list the player can reorder. For an item:
--   * the highest-ranked tag that moves items decides where the item goes
--     (top of infinity, bottom of infinity, or first in its own tab)
--   * the highest-ranked tag of any kind gives the short label shown in its
--     slot
-- Label-only custom tags never move anything.
--
-- Placement "groups" are numbers used when sorting a tab: lower groups sort
-- first. Untagged items are group 3 (NORMAL). "First in its tab" tags sort
-- below 1, "top of infinity" tags between 1 and 2, and "bottom of infinity"
-- tags between 4 and 5. Inside those bands the priority position breaks ties,
-- so a higher-ranked tag always sorts ahead of a lower-ranked one.

local Placement = {}

-- The built-in tags. Each one has:
--   key        stable id saved per item and in share codes
--   label      the name shown in menus and windows
--   badge      the short word drawn in the item's slot
--   placement  "top", "bottom", "first" or "label" (where it moves items)
--   colour     the default label colour, 0xRRGGBBAA
local BUILTIN = {
  { key = "active", label = "Active", badge = "Active", placement = "top", colour = 0x6EE68AFF },
  { key = "vanity", label = "Vanity", badge = "Van", placement = "top", colour = 0xD7A6FFFF },
  { key = "favourite", label = "Favourite", badge = "Fav", placement = "first", colour = 0xFFD84DFF },
  { key = "sell", label = "Sell", badge = "Sell", placement = "bottom", colour = 0x7FD3FFFF },
  { key = "alch", label = "Alch", badge = "Alch", placement = "bottom", colour = 0xFFB04DFF },
  { key = "disassemble", label = "Disassemble", badge = "Dis", placement = "bottom", colour = 0xD0D0D0FF },
  { key = "trash", label = "Trash", badge = "Trash", placement = "bottom", colour = 0xFF7070FF },
}

-- The sort group for items without a moving tag.
Placement.NORMAL = 3

-- The kind of item (see src/core/tags.lua) that counts as tagged Vanity even
-- when the player never tagged it: rares like partyhats.
Placement.RARES_TAG = "vanity"

-- The label shown on part-dose potions that can be combined. It is not a tag
-- players set; it only shares the label colour settings with the tags.
Placement.DECANT = { key = "decant", label = "Decant", badge = "Decant", colour = 0xF2C94CFF }

-- Plain-English descriptions of each placement, used in menus and windows.
local WHERE = {
  top = "top of infinity", bottom = "bottom of infinity", first = "first in its tab", label = "label only",
}

-- Rebuilds Placement.LIST and Placement.byKey from the built-in tags plus
-- the player's custom tags.
--   custom  a list of { key, label, colour, placement } (may be nil)
-- A custom tag's label doubles as its slot badge.
function Placement.setCustom(custom)
  Placement.LIST, Placement.byKey = {}, {}
  for _, def in ipairs(BUILTIN) do Placement.LIST[#Placement.LIST + 1] = def end
  for _, def in ipairs(custom or {}) do
    Placement.LIST[#Placement.LIST + 1] = {
      key = def.key, label = def.label, badge = def.label, placement = def.placement, colour = def.colour, custom = true,
    }
  end
  for _, def in ipairs(Placement.LIST) do Placement.byKey[def.key] = def end
end

-- Start with only the built-in tags. The store registers saved custom tags.
Placement.setCustom(nil)

-- Returns true when key names a known tag (built-in or custom).
function Placement.isValid(key)
  return Placement.byKey[key] ~= nil
end

-- Returns the plain-English place a tag sends its items, or "" if unknown.
function Placement.describe(key)
  local def = Placement.byKey[key]
  return def and WHERE[def.placement] or ""
end

-- Returns the default priority list: every known tag key in list order.
function Placement.defaultOrder()
  local order = {}
  for index, def in ipairs(Placement.LIST) do order[index] = def.key end
  return order
end

-- Cleans a saved priority list so it holds every known tag exactly once.
--   raw  anything; unknown and repeated keys are dropped
-- Tags missing from the saved list (for example a new custom tag) are added
-- at the end in their default order. Returns a new list.
function Placement.sanitizeOrder(raw)
  local order, seen = {}, {}
  for _, key in ipairs(type(raw) == "table" and raw or {}) do
    if Placement.isValid(key) and not seen[key] then
      seen[key] = true
      order[#order + 1] = key
    end
  end
  for _, key in ipairs(Placement.defaultOrder()) do
    if not seen[key] then order[#order + 1] = key end
  end
  return order
end

-- Works out what an item's tags mean for its placement and label.
--   set    map of tag key -> true for the tags on this item (may be nil)
--   kind   the item's kind of item; rares count as tagged Vanity
--   order  the priority list (Placement.sanitizeOrder output); nil means
--          the default order
-- Returns a table with:
--   label     the tag whose badge is drawn in the slot, or nil
--   move      the tag that decides where the item goes, or nil
--   group     the sort group number (see the top of this file)
--   infinity  true when the item belongs in the infinity tab
function Placement.resolve(set, kind, order)
  local result = { group = Placement.NORMAL, infinity = false }
  order = order or Placement.defaultOrder()
  for position, key in ipairs(order) do
    local def = Placement.byKey[key]
    -- A rare (by kind) counts as carrying the Vanity tag.
    local carried = (set and set[key]) or (key == "vanity" and kind == Placement.RARES_TAG)
    if def and carried then
      -- The first carried tag in priority order provides the label.
      result.label = result.label or def
      -- The first carried tag that moves items decides placement and group.
      if not result.move and def.placement ~= "label" then
        result.move = def
        local tie = position / 100
        if def.placement == "first" then
          result.group = tie
        elseif def.placement == "top" then
          result.group, result.infinity = 1 + tie, true
        else
          result.group, result.infinity = 4 + tie, true
        end
      end
    end
  end
  return result
end

-- Returns the settings key that holds a tag label's colour, e.g. "label-sell".
function Placement.colourKey(key)
  return "label-" .. key
end

-- Returns every label that has a colour setting: all tags plus Decant.
function Placement.labelColours()
  local list = {}
  for _, def in ipairs(Placement.LIST) do list[#list + 1] = def end
  list[#list + 1] = Placement.DECANT
  return list
end

return Placement
