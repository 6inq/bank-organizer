local Tags = require("src/core/tags")
local Layout = require("src/core/layout")
local Sorting = require("src/core/sorting")

local Store = {}
Store.__index = Store

Store.KEY = "bank-organizer-v2"

local DEFAULT_COLOURS = {}
for _, category in ipairs(Tags.CATEGORIES) do DEFAULT_COLOURS[category.key] = category.colour end
Store.HIGHLIGHT_DEFAULTS = { move = 0x3CE03CFF, target = 0xF2C94CFF, done = 0x3CE03C55, line = 0xFFFFFFE6 }

local function isBool(v) return type(v) == "boolean" end
local function isColour(v) return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 0xFFFFFFFF end

local SETTINGS = {
  tint = { default = true, valid = isBool },
  opacity = { default = 0.35, valid = function(v) return type(v) == "number" and v >= 0 and v <= 1 end },
  mode = { default = "insert", valid = function(v) return v == "insert" or v == "swap" end },
  scope = { default = "bank", valid = function(v) return v == "bank" or v == "tabs" end },
  sort = { default = Sorting.DEFAULT, valid = Sorting.isMode },
}

local function read(db)
  if not db then return {} end
  local ok, value = pcall(function() return db:GetStructuredData(Store.KEY) end)
  if ok and type(value) == "table" then return value end
  return {}
end

local function sanitizeCorrections(raw)
  local corrections = {}
  for id, tag in pairs(type(raw) == "table" and raw or {}) do
    local numeric = tonumber(id)
    if numeric and Tags.isValid(tag) then corrections[math.floor(numeric)] = tag end
  end
  return corrections
end

Store.MAX_SECTION = 14

local function sanitizeTabHomes(raw)
  local homes = {}
  for tag, section in pairs(type(raw) == "table" and raw or {}) do
    local numeric = tonumber(section)
    if Tags.isValid(tag) and numeric and numeric == math.floor(numeric) and numeric >= 0 and numeric <= Store.MAX_SECTION then
      homes[tag] = numeric
    end
  end
  return homes
end

local function isOrder(list)
  if type(list) ~= "table" then return false end
  local seen = {}
  for index = 1, #list do
    local value = list[index]
    if math.type(value) ~= "integer" or value < 1 or value > #list or seen[value] then return false end
    seen[value] = true
  end
  return #list <= Store.MAX_SECTION
end

local function sanitizeOrder(raw)
  if type(raw) ~= "table" then return nil end
  local list = {}
  for index = 1, Store.MAX_SECTION do
    local value = tonumber(raw[index] or raw[tostring(index)])
    if not value then break end
    list[index] = math.floor(value)
  end
  return isOrder(list) and #list > 0 and list or nil
end

local function sanitizeIgnored(raw)
  local ignored = {}
  for key, value in pairs(type(raw) == "table" and raw or {}) do
    local numeric = tonumber(value == true and key or value)
    if numeric then ignored[math.floor(numeric)] = true end
  end
  return ignored
end

local function sanitizeColours(raw)
  local colours = {}
  for key, colour in pairs(type(raw) == "table" and raw or {}) do
    if (Tags.categoryByKey[key] or Store.HIGHLIGHT_DEFAULTS[key]) and isColour(colour) then
      colours[key] = math.floor(colour)
    end
  end
  return colours
end

function Store.new(db)
  local self = setmetatable({}, Store)
  self.db = db or rawget(_G, "PersistentDB")
  local raw = read(self.db)
  self.preset = Layout.PRESETS[raw.preset] and raw.preset or "main"
  self.layout = Layout.new(self.preset, raw.layout)
  self.corrections = sanitizeCorrections(raw.corrections)
  self.ignored = sanitizeIgnored(raw.ignored)
  self.colours = sanitizeColours(raw.colours)
  self.tabHomes = sanitizeTabHomes(raw.tabHomes)
  self.tabOrder = sanitizeOrder(raw.tabOrder)
  self.settings = {}
  local saved = type(raw.settings) == "table" and raw.settings or {}
  for name, spec in pairs(SETTINGS) do
    if spec.valid(saved[name]) then self.settings[name] = saved[name] else self.settings[name] = spec.default end
  end
  return self
end

function Store:save()
  if not self.db then return end
  local corrections = {}
  for id, tag in pairs(self.corrections) do corrections[tostring(id)] = tag end
  local ignored = {}
  for id in pairs(self.ignored) do ignored[#ignored + 1] = id end
  table.sort(ignored)
  local data = {
    preset = self.preset, layout = self.layout:serialize(), corrections = corrections, ignored = ignored,
    colours = self.colours, settings = self.settings, tabHomes = self.tabHomes, tabOrder = self.tabOrder,
  }
  local ok, err = pcall(function() return self.db:SetStructuredData(Store.KEY, data) end)
  if not ok and log then log("[bank-organizer] save failed: " .. tostring(err)) end
end

function Store:get(name) return self.settings[name] end

function Store:set(name, value)
  local spec = SETTINGS[name]
  if not spec or not spec.valid(value) then return false end
  self.settings[name] = value
  self:save()
  return true
end

function Store:setPreset(preset)
  if not Layout.PRESETS[preset] then return false end
  self.preset = preset
  self.layout = Layout.new(preset)
  self:save()
  return true
end

function Store:correct(itemID, tag)
  if not Tags.isValid(tag) then return false end
  self.corrections[itemID] = tag
  self:save()
  return true
end

function Store:isIgnored(itemID)
  return self.ignored[itemID] == true
end

function Store:setIgnored(itemID, ignored)
  if type(itemID) ~= "number" then return false end
  self.ignored[itemID] = ignored and true or nil
  self:save()
  return true
end

function Store:ignoredCount()
  local count = 0
  for _ in pairs(self.ignored) do count = count + 1 end
  return count
end

function Store:resetIgnored()
  self.ignored = {}
  self:save()
end

function Store:clearCorrection(itemID)
  self.corrections[itemID] = nil
  self:save()
end

function Store:resetCorrections()
  self.corrections = {}
  self:save()
end

function Store:setTabHome(tag, section)
  if not Tags.isValid(tag) or type(section) ~= "number" or section ~= math.floor(section)
    or section < 0 or section > Store.MAX_SECTION then
    return false
  end
  self.tabHomes[tag] = section
  self:save()
  return true
end

function Store:clearTabHome(tag)
  self.tabHomes[tag] = nil
  self:save()
end

function Store:resetTabHomes()
  self.tabHomes = {}
  self:save()
end

function Store:setTabOrder(order)
  if order ~= nil and not isOrder(order) then return false end
  self.tabOrder = order
  self:save()
  return true
end

function Store:colour(key)
  return self.colours[key] or DEFAULT_COLOURS[key] or Store.HIGHLIGHT_DEFAULTS[key] or 0xFFFFFFFF
end

function Store:setColour(key, colour)
  if not (Tags.categoryByKey[key] or Store.HIGHLIGHT_DEFAULTS[key]) or not isColour(colour) then return false end
  self.colours[key] = math.floor(colour)
  self:save()
  return true
end

function Store:resetColours()
  self.colours = {}
  self:save()
end

return Store
