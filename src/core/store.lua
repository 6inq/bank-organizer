-- Bank Organizer: everything the plugin remembers between sessions.
--
-- The store reads one table from the client's PersistentDB when the plugin
-- loads, cleans every field (a damaged or old save must never crash the
-- plugin), and writes the whole table back after every change.
--
-- What it keeps:
--   settings          the player's choices (sort mode, tint, colours, ...)
--   layout            the Whole bank tab plan (src/core/layout.lua)
--   corrections       item id -> kind of item the player picked by hand
--   marks             item id -> set of tags (Active, Sell, custom tags ...)
--   tagOrder          the tag priority list (src/core/placement.lua)
--   customCategories  categories the player made, with their name rules
--   customTags        tags the player made
--   excluded          category key -> items removed from its review list
--   ignored           items the guide must never move
--   noDecant          potions that must never get a Decant label
--   keep              items the Bank Cleaner must never suggest again
--   tabHomes          My tabs pins: kind of item -> tab position
--   arrangement       My tabs: the tab order the player asked for
--   displayOrder      learned order the game shows its tabs in
--   colours           colour overrides by key
--
-- Item ids in the save are always real item ids (obj.id), never the per-slot
-- keys the bank reader makes for repeated unstackable items.

local Tags = require("src/core/tags")
local Layout = require("src/core/layout")
local Sorting = require("src/core/sorting")
local Placement = require("src/core/placement")
local Custom = require("src/core/custom")

local Store = {}
Store.__index = Store

-- The PersistentDB key everything is saved under. Keys must not contain
-- colons, which the client rejects.
Store.KEY = "bank-organizer-v2"

-- The highest tab position a pin or arrangement may name. RS3 banks have the
-- infinity tab plus up to 14 custom tabs (positions 0 to 14).
Store.MAX_SECTION = 14

-- Default tint colour for every built-in category, keyed by category key.
local DEFAULT_COLOURS = {}
for _, category in ipairs(Tags.CATEGORIES) do
  if not category.custom then DEFAULT_COLOURS[category.key] = category.colour end
end

-- Default colours for the guide's own marks plus every built-in tag label.
--   move    outline and word on the item to drag
--   target  outline and word on where it goes
--   done    fill used on tabs that are fully sorted
--   line    the guide arrow
--   label-* the slot label of each tag (and the Decant label)
Store.HIGHLIGHT_DEFAULTS = { move = 0x3CE03CFF, target = 0xF2C94CFF, done = 0x3CE03C55, line = 0xFFFFFFE6 }
for _, placement in ipairs(Placement.labelColours()) do
  Store.HIGHLIGHT_DEFAULTS[Placement.colourKey(placement.key)] = placement.colour
end

-- Small validators used by the settings table below.
local function isBool(v) return type(v) == "boolean" end
local function isColour(v) return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 0xFFFFFFFF end

-- Every setting with its default and a check for saved values. A saved value
-- that fails its check is replaced by the default, so a value of false is
-- kept (false is valid) rather than treated as missing.
local SETTINGS = {
  -- Tint bank items with the colour of the tab they belong in.
  tint = { default = true, valid = isBool },
  -- How strong the tint is, from 0 (invisible) to 1 (solid).
  opacity = { default = 0.35, valid = function(v) return type(v) == "number" and v >= 0 and v <= 1 end },
  -- Rearrange mode to assume when the game does not report it.
  mode = { default = "insert", valid = function(v) return v == "insert" or v == "swap" end },
  -- "bank" follows the Tab Layout; "tabs" keeps the player's own tabs.
  scope = { default = "bank", valid = function(v) return v == "bank" or v == "tabs" end },
  -- How items are ordered inside a tab (see src/core/sorting.lua).
  sort = { default = Sorting.DEFAULT, valid = Sorting.isMode },
  -- How a fully sorted tab looks: green, no overlay, or its own tint.
  sortedLook = { default = "green", valid = function(v) return v == "green" or v == "clear" or v == "tint" end },
  -- Fill tabs row by row ("horizontal") or column by column ("vertical").
  direction = { default = "horizontal", valid = function(v) return v == "horizontal" or v == "vertical" end },
  -- Label part-dose potions that can be decanted, and which doses count.
  decant = { default = true, valid = isBool },
  decant1 = { default = true, valid = isBool },
  decant2 = { default = true, valid = isBool },
  decant3 = { default = true, valid = isBool },
  decant4 = { default = true, valid = isBool },
  decant5 = { default = true, valid = isBool },
  -- Herblore: keep secondaries "with" their potion or at the "bottom".
  secondaries = { default = "with", valid = function(v) return v == "with" or v == "bottom" end },
  -- Bank Cleaner: tradeable stacks worth less than this many coins are
  -- suggested as low value. Up to 1,000b; the database may hand whole
  -- numbers back as decimals, so any whole number is accepted.
  cleanerThreshold = { default = 1000, valid = function(v) return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 1000000000000 end },
}

-- Reads the saved table from the database. Returns {} when there is no
-- database, nothing saved, or the read fails.
local function read(db)
  if not db then return {} end
  -- Wrapped in a closure: passing native client functions straight to pcall
  -- crashes the client.
  local ok, value = pcall(function() return db:GetStructuredData(Store.KEY) end)
  if ok and type(value) == "table" then return value end
  return {}
end

-- Turns a saved key into a whole-number item id, or nil. Saves store ids as
-- strings because PersistentDB tables need string keys.
local function idOf(key)
  local numeric = tonumber(key)
  return numeric and math.floor(numeric) or nil
end

-- Cleans saved hand-picked kinds: item id -> kind key. Unknown kinds are
-- dropped (for example a custom category that no longer exists).
local function sanitizeCorrections(raw)
  local corrections = {}
  for id, tag in pairs(type(raw) == "table" and raw or {}) do
    local numeric = idOf(id)
    if numeric and Tags.isValid(tag) then corrections[numeric] = tag end
  end
  return corrections
end

-- Cleans saved My tabs pins: kind key -> tab position 0..MAX_SECTION.
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

-- Returns true when list is a valid tab order: each number 1..#list exactly
-- once, whole numbers only, and no more than MAX_SECTION entries.
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

-- Reads a saved tab order (stored either as a list or with string keys) and
-- returns it as a list, or nil when it is missing or invalid.
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

-- Cleans saved tags per item: item id -> { [tag key] = true }.
-- Accepts three saved shapes so every older save still loads:
--   "sell"                  one tag (saves from 1.4.1 and earlier)
--   { "sell", "tag-2" }     a list of tags (current saves)
--   { sell = true }         a set of tags
-- Unknown tags are dropped, and items left with no tags are removed.
local function sanitizeMarks(raw)
  local marks = {}
  for key, value in pairs(type(raw) == "table" and raw or {}) do
    local numeric, set = idOf(key), {}
    if type(value) == "string" then value = { value } end
    for k, v in pairs(type(value) == "table" and value or {}) do
      local tag = type(k) == "number" and v or (v == true and k) or nil
      if Placement.isValid(tag) then set[tag] = true end
    end
    if numeric and next(set) then marks[numeric] = set end
  end
  return marks
end

-- Cleans a saved set of item ids. Accepts a list of ids or a map of
-- id -> true, and returns a map of id -> true.
local function sanitizeIds(raw)
  local ids = {}
  for key, value in pairs(type(raw) == "table" and raw or {}) do
    local numeric = idOf(value == true and key or value)
    if numeric then ids[numeric] = true end
  end
  return ids
end

-- Cleans saved review-list exclusions: category key -> set of item ids.
-- Exclusions for categories that no longer exist are dropped.
local function sanitizeExcluded(raw, categories)
  local known, excluded = {}, {}
  for _, def in ipairs(categories) do known[def.key] = true end
  for key, ids in pairs(type(raw) == "table" and raw or {}) do
    if known[key] then excluded[key] = sanitizeIds(ids) end
  end
  return excluded
end

-- Cleans saved colour overrides. Only keys that have a default (a category,
-- a guide colour or a tag label) are kept.
local function sanitizeColours(raw)
  local colours = {}
  for key, colour in pairs(type(raw) == "table" and raw or {}) do
    if (Tags.categoryByKey[key] or Store.HIGHLIGHT_DEFAULTS[key]) and isColour(colour) then
      colours[key] = math.floor(colour)
    end
  end
  return colours
end

-- Turns a set of ids into a sorted list for saving.
local function idList(set)
  local list = {}
  for id in pairs(set) do list[#list + 1] = id end
  table.sort(list)
  return list
end

-- Creates the store and loads the saved data.
--   db  a PersistentDB-like object; defaults to the client's PersistentDB.
--       Tests pass an in-memory stand-in.
function Store.new(db)
  local self = setmetatable({}, Store)
  self.db = db or rawget(_G, "PersistentDB")
  local raw = read(self.db)
  -- Custom categories and tags must be registered before anything else is
  -- read, because layouts, corrections, pins and tags refer to their keys.
  self.customCategories = Custom.sanitizeCategories(raw.customCategories)
  self.customTags = Custom.sanitizeTags(raw.customTags)
  self:_register()
  self.preset = Layout.PRESETS[raw.preset] and raw.preset or "main"
  self.layout = Layout.new(self.preset, raw.layout)
  self.corrections = sanitizeCorrections(raw.corrections)
  self.ignored = sanitizeIds(raw.ignored)
  self.marks = sanitizeMarks(raw.marks)
  self.tagOrder = Placement.sanitizeOrder(raw.tagOrder)
  self.excluded = sanitizeExcluded(raw.excluded, self.customCategories)
  self.keep = sanitizeIds(raw.keep)
  self.noDecant = sanitizeIds(raw.noDecant)
  self.displayOrder = sanitizeOrder(raw.displayOrder)
  self.colours = sanitizeColours(raw.colours)
  self.tabHomes = sanitizeTabHomes(raw.tabHomes)
  self.arrangement = sanitizeOrder(raw.arrangement)
  -- Each setting takes its saved value when that value is valid.
  self.settings = {}
  local saved = type(raw.settings) == "table" and raw.settings or {}
  for name, spec in pairs(SETTINGS) do
    if spec.valid(saved[name]) then self.settings[name] = saved[name] else self.settings[name] = spec.default end
  end
  return self
end

-- Registers the current custom categories and tags with the shared kind and
-- tag lists, so classification, layouts and labels can see them.
function Store:_register()
  Tags.setCustom(self.customCategories)
  Placement.setCustom(self.customTags)
end

-- Writes everything back to the database. Failures are logged, never thrown,
-- so a full or broken database cannot stop the plugin.
function Store:save()
  if not self.db then return end
  -- PersistentDB tables need string keys, so ids become strings here.
  local corrections, marks, excluded = {}, {}, {}
  for id, tag in pairs(self.corrections) do corrections[tostring(id)] = tag end
  for id, set in pairs(self.marks) do
    local list = {}
    for _, key in ipairs(self.tagOrder) do if set[key] then list[#list + 1] = key end end
    marks[tostring(id)] = list
  end
  for key, ids in pairs(self.excluded) do excluded[key] = idList(ids) end
  local data = {
    preset = self.preset, layout = self.layout:serialize(), corrections = corrections, ignored = idList(self.ignored),
    colours = self.colours, settings = self.settings, tabHomes = self.tabHomes, arrangement = self.arrangement,
    displayOrder = self.displayOrder, marks = marks, noDecant = idList(self.noDecant), keep = idList(self.keep),
    tagOrder = self.tagOrder, customCategories = self.customCategories, customTags = self.customTags, excluded = excluded,
  }
  local ok, err = pcall(function() return self.db:SetStructuredData(Store.KEY, data) end)
  if not ok and log then log("[bank-organizer] save failed: " .. tostring(err)) end
end

-- Returns the current value of a setting.
function Store:get(name) return self.settings[name] end

-- Changes a setting and saves. Returns false (and changes nothing) when the
-- setting is unknown or the value fails its check.
function Store:set(name, value)
  local spec = SETTINGS[name]
  if not spec or not spec.valid(value) then return false end
  self.settings[name] = value
  self:save()
  return true
end

-- Switches the starting layout ("main" or "ironman") and resets the Tab
-- Layout to that preset's default. Returns false for unknown presets.
function Store:setPreset(preset)
  if not Layout.PRESETS[preset] then return false end
  self.preset = preset
  self.layout = Layout.new(preset)
  self:save()
  return true
end

-- Records the kind of item the player picked by hand for an item. Returns
-- false for unknown kinds.
function Store:correct(itemID, tag)
  if not Tags.isValid(tag) then return false end
  self.corrections[itemID] = tag
  self:save()
  return true
end

-- Saves the order the game shows its tabs in, learned from the bank view.
-- Returns true only when the order is valid and actually changed.
function Store:setDisplayOrder(order)
  if not isOrder(order) then return false end
  local current = self.displayOrder or {}
  local changed = #current ~= #order
  for index = 1, #order do if current[index] ~= order[index] then changed = true end end
  if not changed then return false end
  self.displayOrder = order
  self:save()
  return true
end

-- Returns true when the player opted this potion out of Decant labels.
function Store:isNoDecant(itemID)
  return self.noDecant[itemID] == true
end

-- Opts a potion in or out of Decant labels. Returns false for bad ids.
function Store:setNoDecant(itemID, on)
  if type(itemID) ~= "number" then return false end
  self.noDecant[itemID] = on and true or nil
  self:save()
  return true
end

-- Returns the set of tags on an item (tag key -> true). The returned table
-- is the live one; callers must not change it.
function Store:tagsOf(itemID)
  return self.marks[itemID] or {}
end

-- Returns true when the item carries the given tag.
function Store:hasTag(itemID, key)
  return self.marks[itemID] ~= nil and self.marks[itemID][key] == true
end

-- Adds (on = true) or removes (on = false) one tag on an item and saves.
-- Returns false for bad ids or unknown tags.
function Store:setTag(itemID, key, on)
  if type(itemID) ~= "number" or not Placement.isValid(key) then return false end
  local set = self.marks[itemID] or {}
  set[key] = on and true or nil
  -- Items with no tags left are removed so the save stays small.
  self.marks[itemID] = next(set) and set or nil
  self:save()
  return true
end

-- Counts how many items carry each tag. Returns tag key -> count.
function Store:markCounts()
  local counts = {}
  for _, set in pairs(self.marks) do
    for key in pairs(set) do counts[key] = (counts[key] or 0) + 1 end
  end
  return counts
end

-- Removes every tag from every item (built-in and custom) and saves.
function Store:clearMarks()
  self.marks = {}
  self:save()
end

-- Returns true when the guide must never move this item.
function Store:isIgnored(itemID)
  return self.ignored[itemID] == true
end

-- Starts or stops ignoring an item. Returns false for bad ids.
function Store:setIgnored(itemID, ignored)
  if type(itemID) ~= "number" then return false end
  self.ignored[itemID] = ignored and true or nil
  self:save()
  return true
end

-- Returns how many items are ignored.
function Store:ignoredCount()
  local count = 0
  for _ in pairs(self.ignored) do count = count + 1 end
  return count
end

-- Stops ignoring every item.
function Store:resetIgnored()
  self.ignored = {}
  self:save()
end

-- Forgets the hand-picked kind for one item.
function Store:clearCorrection(itemID)
  self.corrections[itemID] = nil
  self:save()
end

-- Forgets every hand-picked kind.
function Store:resetCorrections()
  self.corrections = {}
  self:save()
end

-- Pins a kind of item to a My tabs tab position. Returns false when the kind
-- is unknown or the position is not a whole number in 0..MAX_SECTION.
function Store:setTabHome(tag, section)
  if not Tags.isValid(tag) or type(section) ~= "number" or section ~= math.floor(section)
    or section < 0 or section > Store.MAX_SECTION then
    return false
  end
  self.tabHomes[tag] = section
  self:save()
  return true
end

-- Removes the pin for one kind of item.
function Store:clearTabHome(tag)
  self.tabHomes[tag] = nil
  self:save()
end

-- Removes every pin.
function Store:resetTabHomes()
  self.tabHomes = {}
  self:save()
end

-- Saves the tab order the player asked for in My tabs, or nil to keep the
-- current order. Returns false for invalid orders.
function Store:setArrangement(order)
  if order ~= nil and not isOrder(order) then return false end
  self.arrangement = order
  self:save()
  return true
end

-- Returns the colour for a key as 0xRRGGBBAA. Looks in this order:
--   1. the player's override
--   2. the built-in default for a category or guide colour
--   3. a custom category's own colour, or a custom tag's label colour
--   4. opaque white, so drawing never fails
function Store:colour(key)
  if self.colours[key] then return self.colours[key] end
  if DEFAULT_COLOURS[key] then return DEFAULT_COLOURS[key] end
  if Store.HIGHLIGHT_DEFAULTS[key] then return Store.HIGHLIGHT_DEFAULTS[key] end
  local category = Tags.categoryByKey[key]
  if category then return category.colour end
  local tagKey = type(key) == "string" and key:match("^label%-(.+)$")
  local tag = tagKey and Placement.byKey[tagKey]
  if tag then return tag.colour end
  return 0xFFFFFFFF
end

-- Changes a colour and saves. Custom categories and custom tags store their
-- colour in their own definition (so it travels in share codes); everything
-- else is saved as an override. Returns false for unknown keys or colours.
function Store:setColour(key, colour)
  if not isColour(colour) then return false end
  local category = self:category(key)
  if category then return self:editCategory(key, { colour = colour }) end
  local tagKey = type(key) == "string" and key:match("^label%-(.+)$")
  if tagKey and self:customTag(tagKey) then return self:editTag(tagKey, { colour = colour }) end
  if not (Tags.categoryByKey[key] or Store.HIGHLIGHT_DEFAULTS[key]) then return false end
  self.colours[key] = math.floor(colour)
  self:save()
  return true
end

-- Puts every overridden colour back to its default. Custom category and tag
-- colours are part of their definitions and are left alone.
function Store:resetColours()
  self.colours = {}
  self:save()
end

-- Finds the entry with the given key in a list of definitions.
-- Returns the definition and its position, or nil.
local function findDef(list, key)
  for index, def in ipairs(list) do
    if def.key == key then return def, index end
  end
  return nil
end

-- Returns a custom category definition by key, or nil.
function Store:category(key)
  return (findDef(self.customCategories, key))
end

-- Creates a custom category and saves.
--   name    up to Custom.MAX_NAME characters (trimmed)
--   colour  optional 0xRRGGBBAA; defaults to Custom.DEFAULT_COLOUR
-- The new kind starts in the infinity tab of the Tab Layout. Returns the new
-- key, or nil when the name is empty or the limit is reached.
function Store:addCategory(name, colour)
  name = Custom.clean(name, Custom.MAX_NAME)
  if not name or #self.customCategories >= Custom.MAX_CATEGORIES then return nil end
  local key = Custom.nextKey("custom", self.customCategories)
  self.customCategories[#self.customCategories + 1] = {
    key = key, name = name, colour = isColour(colour) and colour or Custom.DEFAULT_COLOUR, rules = {},
  }
  self:_register()
  self.layout:moveTag(key, 0)
  self:save()
  return key
end

-- Changes a custom category's name and/or colour.
--   fields  { name = string?, colour = number? }
-- Returns false when the category does not exist or a field is invalid.
function Store:editCategory(key, fields)
  local def = self:category(key)
  if not def then return false end
  -- Written as an if, not "a and b or c": a cleaned-away name is nil and
  -- must be refused, not silently replaced by the old name.
  local name = def.name
  if fields.name ~= nil then name = Custom.clean(fields.name, Custom.MAX_NAME) end
  if not name or (fields.colour ~= nil and not isColour(fields.colour)) then return false end
  def.name, def.colour = name, fields.colour ~= nil and math.floor(fields.colour) or def.colour
  self:_register()
  self:save()
  return true
end

-- Deletes a custom category. Its items go back to automatic classification:
-- hand-picked choices, pins and review-list exclusions that point at it are
-- removed, and the kind leaves the Tab Layout. Returns false if unknown.
function Store:deleteCategory(key)
  local _, index = findDef(self.customCategories, key)
  if not index then return false end
  table.remove(self.customCategories, index)
  for id, tag in pairs(self.corrections) do if tag == key then self.corrections[id] = nil end end
  self.tabHomes[key], self.excluded[key] = nil, nil
  self.layout:forget(key)
  self:_register()
  self:save()
  return true
end

-- Adds a name rule to a custom category.
--   kind  "contains" or "starts"
--   text  the words to look for (trimmed, case is ignored when matching)
-- Returns false when anything is invalid or the category has too many rules.
function Store:addRule(key, kind, text)
  local def = self:category(key)
  text = Custom.clean(text, Custom.MAX_RULE_TEXT)
  if not def or not text or not Custom.isRuleKind(kind) or #def.rules >= Custom.MAX_RULES then return false end
  def.rules[#def.rules + 1] = { kind = kind, text = text }
  self:save()
  return true
end

-- Removes the rule at a position from a custom category.
function Store:removeRule(key, index)
  local def = self:category(key)
  if not def or not def.rules[index] then return false end
  table.remove(def.rules, index)
  self:save()
  return true
end

-- Removes an item from a category's automatic matches (the review list's
-- Remove button). The rule still matches it, but it is kept out.
function Store:exclude(key, itemID)
  if not self:category(key) or type(itemID) ~= "number" then return false end
  self.excluded[key] = self.excluded[key] or {}
  self.excluded[key][itemID] = true
  self:save()
  return true
end

-- Lets a removed item match its category's rules again.
function Store:restore(key, itemID)
  local ids = self.excluded[key]
  if not ids or not ids[itemID] then return false end
  ids[itemID] = nil
  self:save()
  return true
end

-- Returns a custom tag definition by key, or nil.
function Store:customTag(key)
  return (findDef(self.customTags, key))
end

-- Creates a custom tag and saves.
--   label      up to Custom.MAX_LABEL characters (shown in the slot)
--   colour     optional label colour
--   placement  "top", "bottom", "first" or "label"
-- The tag joins the end of the priority list. Returns the new key or nil.
function Store:addTag(label, colour, placement)
  label = Custom.clean(label, Custom.MAX_LABEL)
  if not label or not Custom.isPlacement(placement) or #self.customTags >= Custom.MAX_TAGS then return nil end
  local key = Custom.nextKey("tag", self.customTags)
  self.customTags[#self.customTags + 1] = {
    key = key, label = label, placement = placement, colour = isColour(colour) and colour or Custom.DEFAULT_COLOUR,
  }
  self:_register()
  self.tagOrder = Placement.sanitizeOrder(self.tagOrder)
  self:save()
  return key
end

-- Changes a custom tag.
--   fields  { label = string?, colour = number?, placement = string? }
-- Returns false when the tag does not exist or a field is invalid.
function Store:editTag(key, fields)
  local def = self:customTag(key)
  if not def then return false end
  local label = def.label
  if fields.label ~= nil then label = Custom.clean(fields.label, Custom.MAX_LABEL) end
  local placement = fields.placement or def.placement
  if not label or not Custom.isPlacement(placement) or (fields.colour ~= nil and not isColour(fields.colour)) then
    return false
  end
  def.label, def.placement = label, placement
  if fields.colour ~= nil then def.colour = math.floor(fields.colour) end
  self:_register()
  self:save()
  return true
end

-- Deletes a custom tag, removing it from every item and the priority list.
function Store:deleteTag(key)
  local _, index = findDef(self.customTags, key)
  if not index then return false end
  table.remove(self.customTags, index)
  for id, set in pairs(self.marks) do
    set[key] = nil
    if not next(set) then self.marks[id] = nil end
  end
  self:_register()
  self.tagOrder = Placement.sanitizeOrder(self.tagOrder)
  self:save()
  return true
end

-- Moves a tag up (direction -1) or down (+1) in the priority list.
-- Returns false when it is already at that end of the list.
function Store:moveTagPriority(key, direction)
  for index, current in ipairs(self.tagOrder) do
    local other = index + direction
    if current == key and self.tagOrder[other] then
      self.tagOrder[index], self.tagOrder[other] = self.tagOrder[other], self.tagOrder[index]
      self:save()
      return true
    end
  end
  return false
end

-- Puts the priority list back to its default order.
function Store:resetTagOrder()
  self.tagOrder = Placement.defaultOrder()
  self:save()
end

-- Returns true when the Bank Cleaner must never suggest this item.
function Store:isKept(itemID)
  return self.keep[itemID] == true
end

-- Adds an item to the Bank Cleaner's Keep list (on = true) or removes it.
function Store:setKept(itemID, on)
  if type(itemID) ~= "number" then return false end
  self.keep[itemID] = on and true or nil
  self:save()
  return true
end

-- Returns how many items are on the Keep list.
function Store:keptCount()
  local count = 0
  for _ in pairs(self.keep) do count = count + 1 end
  return count
end

-- Empties the Bank Cleaner's Keep list.
function Store:clearKept()
  self.keep = {}
  self:save()
end

return Store
