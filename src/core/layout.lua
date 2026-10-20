-- Tab layout: the tabs you want, in bank order (Main/infinity first), each with a name and the
-- tags that go there. Pure. Every tag always has exactly one destination, so nothing falls out
-- of the blueprint.
local Tags = require("src/core/tags")

local Layout = {}
Layout.__index = Layout

Layout.PRESETS = { main = "Main - All-Round Bank", ironman = "Ironman - All-Round Bank" }
Layout.MAX_TABS = 14 -- RS3 custom tabs after the infinity tab

-- Default: each category's tags on the destination matching its position (Main, Tab 1 .. 9).
function Layout.defaultDestinations()
  local destinations = {}
  for d = 0, Tags.DESTINATIONS - 1 do destinations[d] = {} end
  for _, tag in ipairs(Tags.LIST) do
    local category = Tags.categoryByKey[tag.category]
    table.insert(destinations[category.index - 1], tag.key)
  end
  return destinations
end

---@param preset string "main" or "ironman"
---@param saved table? previous serialize() output (or the older { [destination] = tags } form)
function Layout.new(preset, saved)
  local self = setmetatable({ preset = Layout.PRESETS[preset] and preset or "main", names = {} }, Layout)
  self.destinations = Layout.sanitize(saved) or Layout.defaultDestinations()
  if type(saved) == "table" and type(saved.names) == "table" then
    for d = 0, self:last() do
      local name = saved.names[tostring(d)] or saved.names[d]
      if type(name) == "string" and name ~= "" then self.names[d] = name:sub(1, 40) end
    end
  end
  return self
end

local function savedList(saved, d)
  local tabs = type(saved.tabs) == "table" and saved.tabs or saved
  return tabs[d] or tabs[tostring(d)]
end

-- Accepts a saved arrangement, keeping every tag exactly once; tags missing from an older save
-- go back to their default destination (or Main if that tab no longer exists).
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
  local defaults = Layout.defaultDestinations()
  for d = 0, Tags.DESTINATIONS - 1 do
    for _, key in ipairs(defaults[d]) do
      if not seen[key] then table.insert(destinations[destinations[d] and d or 0], key) end
    end
  end
  return destinations
end

-- Highest destination number (0 = Main only).
function Layout:last()
  local last = 0
  while self.destinations[last + 1] do last = last + 1 end
  return last
end

function Layout:destinationOf(tagKey)
  for d = 0, self:last() do
    for _, key in ipairs(self.destinations[d]) do
      if key == tagKey then return d end
    end
  end
  if tagKey == Tags.FALLBACK then return 0 end
  return self:destinationOf(Tags.FALLBACK)
end

-- Position of a tag within its destination (1-based); used for ordering items.
function Layout:rankOf(tagKey)
  local d = self:destinationOf(tagKey)
  for index, key in ipairs(self.destinations[d]) do
    if key == tagKey then return d, index end
  end
  return d, math.huge
end

local function removeFrom(list, tagKey)
  for index = #list, 1, -1 do
    if list[index] == tagKey then table.remove(list, index) end
  end
end

-- Move a tag to another destination (appended at the end there).
function Layout:moveTag(tagKey, destination)
  if not Tags.isValid(tagKey) or not self.destinations[destination] then return false end
  for d = 0, self:last() do removeFrom(self.destinations[d], tagKey) end
  table.insert(self.destinations[destination], tagKey)
  return true
end

-- The no-entry button: send a tag to wherever Storage & Cleanup lives.
function Layout:removeTag(tagKey)
  if tagKey == Tags.FALLBACK then return false end
  return self:moveTag(tagKey, self:destinationOf(Tags.FALLBACK))
end

-- Move a tag up (-1) or down (+1) within its destination.
function Layout:shiftTag(tagKey, direction)
  local d, index = self:rankOf(tagKey)
  local list = self.destinations[d]
  local other = index + direction
  if index == math.huge or other < 1 or other > #list then return false end
  list[index], list[other] = list[other], list[index]
  return true
end

-- Tabs --------------------------------------------------------------------------------

function Layout:name(d)
  return self.names[d] or Tags.destinationName(d)
end

function Layout:rename(d, name)
  if not self.destinations[d] or type(name) ~= "string" then return false end
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40)
  self.names[d] = name ~= "" and name or nil
  return true
end

-- Append an empty custom tab.
function Layout:addTab(name)
  local last = self:last()
  if last >= Layout.MAX_TABS then return false end
  self.destinations[last + 1] = {}
  self.names[last + 1] = name
  return true
end

-- Delete a custom tab; its tags move to Main. Later tabs shift up one place.
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

-- Swap a custom tab with its neighbour (-1 left, +1 right). Main always stays first.
function Layout:moveTab(d, direction)
  local other = d + direction
  if d < 1 or other < 1 or other > self:last() then return false end
  self.destinations[d], self.destinations[other] = self.destinations[other], self.destinations[d]
  self.names[d], self.names[other] = self.names[other], self.names[d]
  return true
end

-- Rebuild from the bank you already have: one tab per custom tab, in your order, each holding
-- the tags it collects (homes: tag -> section); every other tag goes to Main.
---@param tabCount integer number of custom tabs in the bank
---@param homes table { [tag] = section }
---@param names table? { [section] = name }
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

function Layout:reset()
  self.destinations, self.names = Layout.defaultDestinations(), {}
end

function Layout:categoryName(category)
  return self.preset == "ironman" and category.ironman or category.main
end

-- Plain table for PersistentDB (string keys only).
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
