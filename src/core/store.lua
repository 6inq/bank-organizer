-- Persistent state: preset, tab layout, your category corrections and settings. Pure; the
-- db is injectable for tests and defaults to the client's PersistentDB.
local Tags = require("src/core/tags")
local Layout = require("src/core/layout")

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

-- My tabs pins: tag -> section (0 = Tab 1 infinity, N = custom tab N).
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
  self.colours = sanitizeColours(raw.colours)
  self.tabHomes = sanitizeTabHomes(raw.tabHomes)
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
  local data = {
    preset = self.preset, layout = self.layout:serialize(), corrections = corrections,
    colours = self.colours, settings = self.settings, tabHomes = self.tabHomes,
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

-- Switching preset restores that preset's default layout (Bank Architect behaviour).
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

function Store:clearCorrection(itemID)
  self.corrections[itemID] = nil
  self:save()
end

function Store:resetCorrections()
  self.corrections = {}
  self:save()
end

-- Pin a tag to a tab in My tabs mode (every item of that kind goes there).
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

-- Colour for a category key or a highlight key ("move", "target", "done").
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
