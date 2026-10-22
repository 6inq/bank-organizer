-- Bank Organizer: share codes ("Share or Load a Setup").
--
-- A share code is one line of text holding a whole setup, so players can
-- post it anywhere and others can paste it in. It looks like:
--
--   BO1|s=bank|o=smart|t=runes,gear/potions|n=1:Weapons|p=gear:2|d=horizontal|...
--
-- The code starts with the prefix "BO1", then fields separated by "|". Each
-- field is a single letter, "=", and a value:
--   s  organize mode: "bank" (Whole bank) or "tabs" (My tabs)
--   o  sort mode
--   t  Tab Layout: tabs separated by "/", kinds in a tab separated by ","
--   n  tab names: "position:name" pairs separated by ","
--   p  My tabs pins: "kind:position" pairs separated by ","
--   d  sort direction: "horizontal" or "vertical"
--   c  custom categories: "key:name:colour:rules" entries separated by ","
--      where rules are "kind~text" pairs separated by ";"
--   g  custom tags: "key:label:colour:placement" entries separated by ","
--   r  tag priority order: tag keys separated by ","
--   h  herblore secondaries: "with" or "bottom"
--
-- Player-typed text (names, labels, rule text) is escaped so it can never
-- contain the separators: every character that is not a letter or digit is
-- written as "%" plus two hex digits. Colours are written as 8 hex digits.
--
-- Codes deliberately leave out everything about single items: hand-picked
-- kinds, tags on items, ignored items, review-list removals and the Bank
-- Cleaner's Keep list stay personal.
--
-- Older versions of the plugin read codes field by field and ignore letters
-- they do not know, so codes made by this version still load there (without
-- the new parts). Codes from older versions have no c, g, r or h field and
-- load here unchanged.

local Tags = require("src/core/tags")
local Layout = require("src/core/layout")
local Sorting = require("src/core/sorting")
local Custom = require("src/core/custom")
local Placement = require("src/core/placement")

local Preset = {}

-- Every share code starts with this, followed by "|".
Preset.PREFIX = "BO1"

-- Longer pasted text is refused before parsing, to keep parsing cheap.
local MAX_LENGTH = 6000

-- Makes player text safe inside a code: every character that is not a
-- letter or digit becomes "%" and two hex digits (for example ":" -> "%3A").
local function escape(text)
  return (text:gsub("[^%w]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- Reverses escape.
local function unescape(text)
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Writes a colour as 8 hex digits (RRGGBBAA).
local function hexColour(colour)
  return string.format("%08X", colour)
end

-- Writes the custom categories field value.
local function encodeCategories(categories)
  local parts = {}
  for _, def in ipairs(categories or {}) do
    local rules = {}
    for _, rule in ipairs(def.rules) do rules[#rules + 1] = rule.kind .. "~" .. escape(rule.text) end
    parts[#parts + 1] = table.concat({ def.key, escape(def.name), hexColour(def.colour), table.concat(rules, ";") }, ":")
  end
  return table.concat(parts, ",")
end

-- Writes the custom tags field value.
local function encodeTags(tags)
  local parts = {}
  for _, def in ipairs(tags or {}) do
    parts[#parts + 1] = table.concat({ def.key, escape(def.label), hexColour(def.colour), def.placement }, ":")
  end
  return table.concat(parts, ",")
end

-- Builds the share code for the store's current setup.
function Preset.encode(store)
  local layout = store.layout
  local tabs, names = {}, {}
  for d = 0, layout:last() do
    tabs[#tabs + 1] = table.concat(layout.destinations[d], ",")
    if layout.names[d] then names[#names + 1] = d .. ":" .. escape(layout.names[d]) end
  end
  -- Pins are sorted so the same setup always gives the same code.
  local pins = {}
  for tag, section in pairs(store.tabHomes or {}) do pins[#pins + 1] = tag .. ":" .. section end
  table.sort(pins)
  return table.concat({
    Preset.PREFIX, "s=" .. store:get("scope"), "o=" .. store:get("sort"), "t=" .. table.concat(tabs, "/"),
    "n=" .. table.concat(names, ","), "p=" .. table.concat(pins, ","), "d=" .. store:get("direction"),
    "c=" .. encodeCategories(store.customCategories), "g=" .. encodeTags(store.customTags),
    "r=" .. table.concat(store.tagOrder or {}, ","), "h=" .. store:get("secondaries"),
  }, "|")
end

-- Splits a code into its fields: letter -> value. Unknown letters are kept
-- but never read, which is what lets newer codes load in older versions.
local function fields(text)
  local out = {}
  for part in text:gmatch("[^|]+") do
    local key, value = part:match("^(%a)=(.*)$")
    if key then out[key] = value end
  end
  return out
end

-- Splits text on a single separator character, keeping empty pieces.
local function split(text, separator)
  local out = {}
  for piece in (text .. separator):gmatch("([^" .. separator .. "]*)" .. separator) do out[#out + 1] = piece end
  return out
end

-- Reads the custom categories field. Returns a cleaned list, or nil when the
-- field is absent (an older code), so the player's own categories are kept.
local function decodeCategories(value)
  if value == nil then return nil end
  local raw = {}
  for _, entry in ipairs(value ~= "" and split(value, ",") or {}) do
    local key, name, colour, rules = entry:match("^([%w%-]+):([^:]*):(%x+):(.*)$")
    if key then
      local list = {}
      for _, rule in ipairs(rules ~= "" and split(rules, ";") or {}) do
        local kind, text = rule:match("^(%a+)~(.*)$")
        if kind then list[#list + 1] = { kind = kind, text = unescape(text) } end
      end
      raw[#raw + 1] = { key = key, name = unescape(name), colour = tonumber(colour, 16), rules = list }
    end
  end
  return Custom.sanitizeCategories(raw)
end

-- Reads the custom tags field. Returns a cleaned list, or nil when absent.
local function decodeTags(value)
  if value == nil then return nil end
  local raw = {}
  for _, entry in ipairs(value ~= "" and split(value, ",") or {}) do
    local key, label, colour, placement = entry:match("^([%w%-]+):([^:]*):(%x+):(%a+)$")
    if key then raw[#raw + 1] = { key = key, label = unescape(label), colour = tonumber(colour, 16), placement = placement } end
  end
  return Custom.sanitizeTags(raw)
end

-- Reads a share code.
--   text  what the player pasted
-- Returns a table describing the setup, or nil and a message for the player
-- when the text is not a usable code. Nothing is changed here; see
-- Preset.apply.
function Preset.decode(text)
  if type(text) ~= "string" then return nil, "Paste a setup code first." end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if #text > MAX_LENGTH then return nil, "That code is too long." end
  if text:sub(1, #Preset.PREFIX + 1) ~= Preset.PREFIX .. "|" then return nil, "That is not a Bank Organizer setup code." end
  local f = fields(text)
  local categories = decodeCategories(f.c)
  -- Kinds in the layout and pins may name the code's own custom categories,
  -- which are not registered yet, so they count as valid here too.
  local codeKinds = {}
  for _, def in ipairs(categories or {}) do codeKinds[def.key] = true end
  -- Returns true when a kind named in the code may be used.
  local function validKind(tag)
    if codeKinds[tag] then return true end
    -- The player's own custom categories are only valid when the code does
    -- not bring its own set (an older code).
    return Tags.isValid(tag) and (categories == nil or not Tags.isCustom(tag))
  end
  local tabs, count = {}, 0
  for list in ((f.t or "") .. "/"):gmatch("([^/]*)/") do
    local tags = {}
    for tag in list:gmatch("[^,]+") do if validKind(tag) then tags[#tags + 1] = tag end end
    tabs[tostring(count)] = tags
    count = count + 1
  end
  if count == 0 then return nil, "That code has no tabs in it." end
  local names = {}
  for d, name in (f.n or ""):gmatch("(%d+):([^,]*)") do names[d] = unescape(name):sub(1, 40) end
  local pins = {}
  for tag, section in (f.p or ""):gmatch("([%w%-]+):(%d+)") do
    local n = tonumber(section)
    if validKind(tag) and n <= 14 then pins[tag] = n end
  end
  local order
  if f.r then
    order = {}
    for key in f.r:gmatch("[%w%-]+") do order[#order + 1] = key end
  end
  return {
    scope = (f.s == "tabs" or f.s == "bank") and f.s or nil,
    direction = (f.d == "horizontal" or f.d == "vertical") and f.d or nil,
    sort = Sorting.isMode(f.o) and f.o or nil,
    secondaries = (f.h == "with" or f.h == "bottom") and f.h or nil,
    layout = { count = count, tabs = tabs, names = names },
    pins = pins,
    categories = categories,
    tags = decodeTags(f.g),
    order = order,
  }
end

-- Replaces the store's setup with a decoded share code and saves.
--   store   the Store
--   preset  the table from Preset.decode
-- Custom categories and tags are replaced only when the code carries them.
-- Per-item data (hand-picked kinds, tags on items, ignores, the Keep list)
-- is kept; anything that points at a category or tag the new setup does not
-- have simply stops applying. Returns the last tab position of the layout.
function Preset.apply(store, preset)
  if preset.categories then store.customCategories = preset.categories end
  if preset.tags then store.customTags = preset.tags end
  store:_register()
  -- Drop review-list removals for categories that no longer exist.
  for key in pairs(store.excluded) do
    if not store:category(key) then store.excluded[key] = nil end
  end
  store.tagOrder = Placement.sanitizeOrder(preset.order or store.tagOrder)
  store.layout = Layout.new(store.preset, preset.layout)
  store.tabHomes = preset.pins or {}
  store.arrangement = nil
  if preset.scope then store.settings.scope = preset.scope end
  if preset.sort then store.settings.sort = preset.sort end
  if preset.direction then store.settings.direction = preset.direction end
  if preset.secondaries then store.settings.secondaries = preset.secondaries end
  store:save()
  return store.layout:last()
end

return Preset
