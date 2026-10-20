-- Tab layout: which tags sit on Main and Tabs 1-9, and in what order. Pure.
-- Every tag always has exactly one destination, so nothing falls out of the blueprint.
local Tags = require("src/core/tags")

local Layout = {}
Layout.__index = Layout

Layout.PRESETS = { main = "Main - All-Round Bank", ironman = "Ironman - All-Round Bank" }

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
---@param saved table? { [destination] = { tagKey, ... } } previously saved arrangement
function Layout.new(preset, saved)
  local self = setmetatable({ preset = Layout.PRESETS[preset] and preset or "main" }, Layout)
  self.destinations = Layout.sanitize(saved) or Layout.defaultDestinations()
  return self
end

-- Accepts a saved arrangement only if every tag appears exactly once.
function Layout.sanitize(saved)
  if type(saved) ~= "table" then return nil end
  local destinations, seen = {}, {}
  for d = 0, Tags.DESTINATIONS - 1 do
    destinations[d] = {}
    local list = saved[d] or saved[tostring(d)]
    for _, key in ipairs(type(list) == "table" and list or {}) do
      if Tags.isValid(key) and not seen[key] then
        seen[key] = true
        table.insert(destinations[d], key)
      end
    end
  end
  -- Tags missing from an older save go back to their default destination.
  local defaults = Layout.defaultDestinations()
  for d = 0, Tags.DESTINATIONS - 1 do
    for _, key in ipairs(defaults[d]) do
      if not seen[key] then table.insert(destinations[d], key) end
    end
  end
  return destinations
end

function Layout:destinationOf(tagKey)
  for d = 0, Tags.DESTINATIONS - 1 do
    for _, key in ipairs(self.destinations[d]) do
      if key == tagKey then return d end
    end
  end
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
  if not Tags.isValid(tagKey) or destination < 0 or destination >= Tags.DESTINATIONS then return false end
  for d = 0, Tags.DESTINATIONS - 1 do removeFrom(self.destinations[d], tagKey) end
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

function Layout:reset()
  self.destinations = Layout.defaultDestinations()
end

function Layout:categoryName(category)
  return self.preset == "ironman" and category.ironman or category.main
end

-- Plain table for PersistentDB (string keys).
function Layout:serialize()
  local out = {}
  for d = 0, Tags.DESTINATIONS - 1 do
    local copy = {}
    for index, key in ipairs(self.destinations[d]) do copy[index] = key end
    out[tostring(d)] = copy
  end
  return out
end

return Layout
