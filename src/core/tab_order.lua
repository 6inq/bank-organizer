-- Bank Organizer: the difference between stored and shown tab order.
--
-- The game stores bank tabs in one order and can SHOW them in another
-- (players can drag tab buttons around). Everything the player sees, and
-- every instruction the guide gives, uses the shown order; the bank's item
-- list and tab sizes use the stored order.
--
-- Terms used here:
--   container (stored) position  where a tab's items sit in the item list
--   display (shown) position     where its button sits on screen
--   order                        list where order[shown position] = stored
--                                position, for custom tabs 1..n
--
-- The live order comes from the game's BANK_TAB_k_MAPPING_SERVER variables
-- (see src/game/bank.lua). TabOrder.learn is a backup that works it out
-- from the infinity view, which lists every tab's items in shown order.

local TabOrder = {}

-- Returns the highest tab position in a sections table.
local function lastKey(sections)
  local high = 0
  for s in pairs(sections) do if s > high then high = s end end
  return high
end

-- Works out the shown order from the infinity view.
--   displayIds         item keys in the order they appear on screen (only
--                      items that appear once, so each one names a tab)
--   containerSections  stored position -> item keys
-- Each run of items from the same stored tab is one shown tab. Returns the
-- order list, or nil when the view does not fit (a tab appears twice, or a
-- non-empty tab never appears).
function TabOrder.learn(displayIds, containerSections)
  local sectionOf = {}
  for s, ids in pairs(containerSections) do
    for _, id in ipairs(ids) do sectionOf[id] = s end
  end
  local order, seen, current = {}, {}, nil
  for _, id in ipairs(displayIds) do
    local s = sectionOf[id]
    if s ~= nil and s ~= current then
      if seen[s] then return nil end
      seen[s], current = true, s
      -- The infinity tab is not a numbered custom tab, so it is not listed.
      if s ~= 0 then order[#order + 1] = s end
    end
  end
  for s = 1, lastKey(containerSections) do
    if #(containerSections[s] or {}) > 0 and not seen[s] then return nil end
  end
  return order
end

-- Returns true when an order names every non-empty stored tab exactly once
-- and no empty ones.
function TabOrder.fits(order, containerSections)
  if type(order) ~= "table" then return false end
  local listed = {}
  for _, s in ipairs(order) do
    if listed[s] or #(containerSections[s] or {}) == 0 then return false end
    listed[s] = true
  end
  for s = 1, lastKey(containerSections) do
    if #(containerSections[s] or {}) > 0 and not listed[s] then return false end
  end
  return true
end

-- Builds the two lookup maps from an order:
--   displayOf[stored]    -> shown position
--   containerOf[shown]   -> stored position
-- Tabs the order does not cover (or every tab, when the order does not fit)
-- keep their stored position, one after another. One extra position is
-- mapped past the last tab, for the tab the + button would create.
function TabOrder.maps(order, containerSections)
  local displayOf, containerOf = { [0] = 0 }, { [0] = 0 }
  local used = 0
  if TabOrder.fits(order, containerSections) then
    for position, s in ipairs(order) do displayOf[s], containerOf[position] = position, s end
    used = #order
  end
  for s = 1, math.max(lastKey(containerSections), used) + 1 do
    if displayOf[s] == nil then
      used = used + 1
      displayOf[s], containerOf[used] = used, s
    end
  end
  return displayOf, containerOf
end

-- Re-keys a sections table from stored positions to shown positions.
function TabOrder.toDisplay(containerSections, displayOf)
  local out = {}
  for s, ids in pairs(containerSections) do out[displayOf[s] or s] = ids end
  return out
end

-- Returns the shown positions in the order the game STORES them, with the
-- infinity tab (0) last when custom tabs are stored first, or first
-- otherwise. Verify.flatten uses it to rebuild the stored item order from
-- tabs keyed by shown position.
function TabOrder.containerSequence(displayOf, containerOf, tabsFirst)
  local sequence = {}
  local count = 0
  for position in pairs(containerOf) do if position > count then count = position end end
  local tabs = {}
  for c = 1, count do tabs[#tabs + 1] = displayOf[c] end
  if tabsFirst ~= false then
    for _, d in ipairs(tabs) do sequence[#sequence + 1] = d end
    sequence[#sequence + 1] = 0
  else
    sequence[1] = 0
    for _, d in ipairs(tabs) do sequence[#sequence + 1] = d end
  end
  return sequence
end

return TabOrder
