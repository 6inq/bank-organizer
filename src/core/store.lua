-- Persistent tags and settings. The db is injectable for tests.
local Categories = require("src/core/categories")

local Store = {}
Store.__index = Store

Store.TAGS_KEY = "bank-organizer:tags"
Store.SETTINGS_KEY = "bank-organizer:settings"

local DEFAULTS = {
  sortMode = "id",
  overlays = true,
  filter = "all",
  highlightUntagged = false,
  tagging = false,
  opacity = 0.35,
}

local VALIDATORS = {
  sortMode = function(v) return v == "id" or v == "name" end,
  overlays = function(v) return type(v) == "boolean" end,
  filter = function(v) return v == "all" or Categories.isValid(v) end,
  highlightUntagged = function(v) return type(v) == "boolean" end,
  tagging = function(v) return type(v) == "boolean" end,
  opacity = function(v) return type(v) == "number" and v >= 0 and v <= 1 end,
}

-- Accept integral floats: structured data may round-trip numbers as floats.
local function isColour(v)
  return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 0xFFFFFFFF
end

local function readTable(db, key)
  if db == nil then return {} end
  local ok, value = pcall(db.GetStructuredData, db, key)
  if ok and type(value) == "table" then return value end
  return {}
end

local function sanitizeTags(raw)
  local tags = {}
  for id, key in pairs(raw) do
    local numeric = tonumber(id)
    if numeric and Categories.isValid(key) then tags[tostring(math.floor(numeric))] = key end
  end
  return tags
end

local function sanitizeSettings(raw)
  local settings = {}
  for name, default in pairs(DEFAULTS) do
    local value = raw[name]
    if VALIDATORS[name](value) then settings[name] = value else settings[name] = default end
  end
  settings.colours = {}
  for key, colour in pairs(type(raw.colours) == "table" and raw.colours or {}) do
    if Categories.isValid(key) and isColour(colour) then settings.colours[key] = math.floor(colour) end
  end
  return settings
end

---@param db table? defaults to the global PersistentDB
function Store.new(db)
  local self = setmetatable({}, Store)
  self.db = db or rawget(_G, "PersistentDB")
  self.tags = sanitizeTags(readTable(self.db, Store.TAGS_KEY))
  self.settings = sanitizeSettings(readTable(self.db, Store.SETTINGS_KEY))
  return self
end

function Store:_save(key, value)
  if self.db == nil then return end
  local ok, err = pcall(self.db.SetStructuredData, self.db, key, value)
  if not ok and log then log("[bank-organizer] save failed: " .. tostring(err)) end
end

function Store:getTag(objectID)
  return self.tags[tostring(objectID)]
end

function Store:setTag(objectID, key)
  if not Categories.isValid(key) then return false end
  self.tags[tostring(objectID)] = key
  self:_save(Store.TAGS_KEY, self.tags)
  return true
end

function Store:clearTag(objectID)
  self.tags[tostring(objectID)] = nil
  self:_save(Store.TAGS_KEY, self.tags)
end

function Store:clearAllTags()
  self.tags = {}
  self:_save(Store.TAGS_KEY, self.tags)
end

function Store:get(name)
  return self.settings[name]
end

function Store:set(name, value)
  local validate = VALIDATORS[name]
  if not validate or not validate(value) then return false end
  self.settings[name] = value
  self:_save(Store.SETTINGS_KEY, self.settings)
  return true
end

function Store:colour(key)
  local custom = self.settings.colours[key]
  if custom then return custom end
  local entry = Categories.byKey[key] or Categories.byKey[Categories.DEFAULT]
  return entry.colour
end

function Store:setColour(key, colour)
  if not Categories.isValid(key) or not isColour(colour) then return false end
  self.settings.colours[key] = colour
  self:_save(Store.SETTINGS_KEY, self.settings)
  return true
end

return Store
