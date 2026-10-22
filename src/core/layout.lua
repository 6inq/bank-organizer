-- Bank Organizer: the Whole bank Tab Layout.
--
-- A layout is a list of tabs in bank order. Position 0 is the infinity tab
-- (the game's "Tab 1"); positions 1..14 are the game's Tabs 2..15. Each tab
-- holds an ordered list of kinds of item (keys from src/core/tags.lua) and an
-- optional name. Every known kind appears in exactly one tab, so every item
-- has exactly one planned home.

local Tags = require("src/core/tags")

local Layout = {}
Layout.__index = Layout

-- The two starting layouts players can pick. Both use the same tabs; the
-- Ironman one only renames some categories.
Layout.PRESETS = { main = "Main - All-Round Bank", ironman = "Ironman - All-Round Bank" }

-- RS3 banks have up to 14 custom tabs after the infinity tab.
Layout.MAX_TABS = 14

-- Builds the default tab plan: one tab per built-in category, holding that
-- category's kinds in list order. Custom categories start in the infinity
-- tab (position 0) because there is no default tab made for them.
-- Returns a table of position -> list of kind keys.
function Layout.defaultDestinations()
  local destinations = {}
  for d = 0, Tags.DESTINATIONS - 1 do destinations[d] = {} end
  for _, tag in ipairs(Tags.LIST) do
    local category = Tags.categoryByKey[tag.category]
    local d = category.index - 1
    table.insert(destinations[destinations[d] and d or 0], tag.key)
  end
  return destinations
end

-- Creates a layout.
--   preset  "main" or "ironman" (anything else means "main")
--   saved   an optional table from Layout:serialize(), or an older save
-- A missing or broken save gives the default layout.
function Layout.new(preset, saved)
  local self = setmetatable({ preset = Layout.PRESETS[preset] and preset or "main", names = {} }, Layout)
  self.destinations = Layout.sanitize(saved) or Layout.defaultDestinations()
  if type(saved) == "table" and type(saved.names) == "table" then
    -- Names are saved with string keys ("0", "1", ...); older saves used
    -- number keys, so both are read.
    for d = 0, self:last() do
      local name = saved.names[tostring(d)] or saved.names[d]
      if type(name) == "string" and name ~= "" then self.names[d] = name:sub(1, 40) end
    end
  end
  return self
end

-- Returns the saved list of kinds for tab position d. Current saves keep the
-- tabs under saved.tabs with string keys; the oldest saves kept them at the
-- top level with number keys.
local function savedList(saved, d)
  local tabs = type(saved.tabs) == "table" and saved.tabs or saved
  return tabs[d] or tabs[tostring(d)]
end

-- Cleans a saved layout.
--   saved  anything; returns nil when it is not a table
-- Unknown kinds and repeats are dropped. Kinds the save does not mention
-- (for example ones added in a newer version) are added to their default tab,
-- or to the infinity tab when that tab does not exist in this layout.
-- Returns a table of position -> list of kind keys.
function Layout.sanitize(saved)
  if type(saved) ~= "table" then return nil end
  local count = tonumber(saved.count) or Tags.DESTINATIONS
  count = math.max(1, math.min(Layout.MAX_TABS + 1, math.floor(count)))
  local destinations, seen = {}, {}
  for d = 0, count - 1 do
    destinations[d] = {}
    local list = savedList(saved, d)
    for _, key in ipairs(type(list) == "table" and list or {}) do
      if Tags.isValid(key) and not seen[key] then
        seen[key] = true
        table.insert(destinations[d], key)
      end
    end
  end
  -- Place every kind the save did not mention.
  local defaults = Layout.defaultDestinations()
  for d = 0, Tags.DESTINATIONS - 1 do
    for _, key in ipairs(defaults[d]) do
      if not seen[key] then table.insert(destinations[destinations[d] and d or 0], key) end
    end
  end
  return destinations
end

-- Returns the position of the last tab (0 when there is only infinity).
function Layout:last()
  local last = 0
  while self.destinations[last + 1] do last = last + 1 end
  return last
end

-- Returns the tab position that holds a kind of item. A kind that is not in
-- any tab goes wherever Storage & Cleanup lives, and that kind itself falls
-- back to the infinity tab, so this always returns a valid position.
function Layout:destinationOf(tagKey)
  for d = 0, self:last() do
    for _, key in ipairs(self.destinations[d]) do
      if key == tagKey then return d end
    end
  end
  if tagKey == Tags.FALLBACK then return 0 end
  return self:destinationOf(Tags.FALLBACK)
end

-- Returns the tab position of a kind and its place in that tab's list. The
-- place is math.huge when the kind is not listed (it arrived by fallback),
-- so such items sort after the listed kinds.
function Layout:rankOf(tagKey)
  local d = self:destinationOf(tagKey)
  for index, key in ipairs(self.destinations[d]) do
    if key == tagKey then return d, index end
  end
  return d, math.huge
end

-- Removes every copy of a kind from one tab's list.
local function removeFrom(list, tagKey)
  for index = #list, 1, -1 do
    if list[index] == tagKey then table.remove(list, index) end
  end
end

-- Moves a kind of item to the end of another tab's list. Returns false when
-- the kind is unknown or the tab does not exist.
function Layout:moveTag(tagKey, destination)
  if not Tags.isValid(tagKey) or not self.destinations[destination] then return false end
  for d = 0, self:last() do removeFrom(self.destinations[d], tagKey) end
  table.insert(self.destinations[destination], tagKey)
  return true
end

-- Removes a kind from every tab without checking it is still valid. Used
-- when a custom category is deleted; its items fall back automatically.
function Layout:forget(tagKey)
  for d = 0, self:last() do removeFrom(self.destinations[d], tagKey) end
end

-- Sends a kind back to wherever Storage & Cleanup lives (the Remove button).
-- Storage & Cleanup itself cannot be removed.
function Layout:removeTag(tagKey)
  if tagKey == Tags.FALLBACK then return false end
  return self:moveTag(tagKey, self:destinationOf(Tags.FALLBACK))
end

-- Moves a kind one place earlier (-1) or later (+1) inside its tab. Returns
-- false when it is already first or last.
function Layout:shiftTag(tagKey, direction)
  local d, index = self:rankOf(tagKey)
  local list = self.destinations[d]
  local other = index + direction
  if index == math.huge or other < 1 or other > #list then return false end
  list[index], list[other] = list[other], list[index]
  return true
end

-- Returns a tab's name: the player's own, or the RS3 default like "Tab 3".
function Layout:name(d)
  return self.names[d] or Tags.destinationName(d)
end

-- Renames a tab. Spaces at either end are trimmed and names are cut to 40
-- characters; an empty name clears it. Returns false for unknown tabs.
function Layout:rename(d, name)
  if not self.destinations[d] or type(name) ~= "string" then return false end
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40)
  self.names[d] = name ~= "" and name or nil
  return true
end

-- Adds an empty tab at the end. Returns false when the bank already has the
-- most tabs RS3 allows.
function Layout:addTab(name)
  local last = self:last()
  if last >= Layout.MAX_TABS then return false end
  self.destinations[last + 1] = {}
  self.names[last + 1] = name
  return true
end

-- Deletes a tab. Its kinds move to the infinity tab and later tabs shift
-- left to close the gap. The infinity tab cannot be deleted.
function Layout:removeTab(d)
  local last = self:last()
  if d < 1 or d > last then return false end
  for _, key in ipairs(self.destinations[d]) do table.insert(self.destinations[0], key) end
  for index = d, last - 1 do
    self.destinations[index], self.names[index] = self.destinations[index + 1], self.names[index + 1]
  end
  self.destinations[last], self.names[last] = nil, nil
  return true
end

-- Swaps a tab with its neighbour to the left (-1) or right (+1), taking its
-- kinds and name along. The infinity tab never moves.
function Layout:moveTab(d, direction)
  local other = d + direction
  if d < 1 or other < 1 or other > self:last() then return false end
  self.destinations[d], self.destinations[other] = self.destinations[other], self.destinations[d]
  self.names[d], self.names[other] = self.names[other], self.names[d]
  return true
end

-- Replaces the layout with one built from the player's current tabs (the
-- "Copy my current tabs" button).
--   tabCount  how many custom tabs the bank has
--   homes     kind key -> the tab position most of that kind is in
--   names     optional tab position -> name
-- Kinds with no clear home go to the infinity tab.
function Layout:copyTabs(tabCount, homes, names)
  tabCount = math.max(0, math.min(Layout.MAX_TABS, math.floor(tabCount or 0)))
  self.destinations, self.names = {}, {}
  for d = 0, tabCount do self.destinations[d] = {} end
  for _, tag in ipairs(Tags.LIST) do
    local home = homes[tag.key]
    table.insert(self.destinations[(home and home >= 1 and home <= tabCount) and home or 0], tag.key)
  end
  for d, name in pairs(names or {}) do
    if self.destinations[d] then self.names[d] = name end
  end
  return true
end

-- Puts the layout back to the default tabs and clears every tab name.
function Layout:reset()
  self.destinations, self.names = Layout.defaultDestinations(), {}
end

-- Returns a category's name for this layout's preset.
function Layout:categoryName(category)
  return self.preset == "ironman" and category.ironman or category.main
end

-- Turns the layout into a plain table for saving. String keys are used
-- because PersistentDB tables need them.
function Layout:serialize()
  local tabs, names = {}, {}
  for d = 0, self:last() do
    local copy = {}
    for index, key in ipairs(self.destinations[d]) do copy[index] = key end
    tabs[tostring(d)] = copy
    if self.names[d] then names[tostring(d)] = self.names[d] end
  end
  return { count = self:last() + 1, tabs = tabs, names = names }
end

return Layout
