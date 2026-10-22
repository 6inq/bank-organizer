-- Bank Organizer: player-made categories and tags.
--
-- A custom category is a new kind of item the player names and colours. It
-- can carry name rules ("name contains X", "name starts with X") so matching
-- items join it automatically.
--
-- A custom tag is a short label (up to 6 characters) shown in the bottom of
-- an item's slot. Like the built-in tags (Active, Sell, Trash and so on) it
-- can also move the item: to the top or bottom of the infinity tab, to the
-- front of its own tab, or nowhere at all (label only).
--
-- This module only checks and cleans the definitions and matches names. The
-- store (src/core/store.lua) keeps them, and src/core/tags.lua and
-- src/core/placement.lua register them so the rest of the plugin sees them.

local Custom = {}

-- Limits that keep saves, share codes and the UI a sensible size.
Custom.MAX_NAME = 40        -- characters in a category name
Custom.MAX_LABEL = 6        -- characters in a tag label (it must fit a slot)
Custom.MAX_RULES = 20       -- name rules per category
Custom.MAX_RULE_TEXT = 40   -- characters in one rule
Custom.MAX_CATEGORIES = 30  -- custom categories in total
Custom.MAX_TAGS = 20        -- custom tags in total

-- The colour a new category or tag starts with (a soft teal, 0xRRGGBBAA).
Custom.DEFAULT_COLOUR = 0x4FD1C5FF

-- The kinds of name rule. "contains" matches anywhere in the item name and
-- "starts" matches only at the beginning. Both ignore upper and lower case.
Custom.RULE_KINDS = {
  { key = "contains", label = "Name contains" },
  { key = "starts", label = "Name starts with" },
}

-- Where a custom tag puts its items. The labels are what players see.
Custom.PLACEMENTS = {
  { key = "top", label = "Top of the infinity tab" },
  { key = "bottom", label = "Bottom of the infinity tab" },
  { key = "first", label = "First in its own tab" },
  { key = "label", label = "Label only (never moves the item)" },
}

-- Quick lookups built from the two lists above: key -> true.
local RULE_KIND, PLACEMENT = {}, {}
for _, kind in ipairs(Custom.RULE_KINDS) do RULE_KIND[kind.key] = true end
for _, placement in ipairs(Custom.PLACEMENTS) do PLACEMENT[placement.key] = true end

-- Returns true when value is a colour the client accepts: a whole number
-- from 0 to 0xFFFFFFFF.
local function isColour(value)
  return type(value) == "number" and value == math.floor(value) and value >= 0 and value <= 0xFFFFFFFF
end

-- Trims spaces from both ends of text and cuts it to at most limit
-- characters. Returns nil when text is not a string or ends up empty.
function Custom.clean(text, limit)
  if type(text) ~= "string" then return nil end
  text = text:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, limit)
  if text == "" then return nil end
  return text
end

-- Returns true when the placement key is one of Custom.PLACEMENTS.
function Custom.isPlacement(key)
  return PLACEMENT[key] == true
end

-- Returns true when the rule kind is one of Custom.RULE_KINDS.
function Custom.isRuleKind(key)
  return RULE_KIND[key] == true
end

-- Returns true when key has the shape the store gives custom entries:
-- prefix, a dash and a number (for example "custom-3" or "tag-1").
local function isKey(key, prefix)
  return type(key) == "string" and key:match("^" .. prefix .. "%-%d+$") ~= nil
end

-- Cleans a list of name rules read from a save or a share code.
--   raw  anything; only well-formed { kind, text } entries survive
-- Returns a new list with at most Custom.MAX_RULES rules.
local function sanitizeRules(raw)
  local rules = {}
  for _, rule in ipairs(type(raw) == "table" and raw or {}) do
    local text = type(rule) == "table" and Custom.clean(rule.text, Custom.MAX_RULE_TEXT)
    if text and Custom.isRuleKind(rule.kind) and #rules < Custom.MAX_RULES then
      rules[#rules + 1] = { kind = rule.kind, text = text }
    end
  end
  return rules
end

-- Cleans the list of custom categories read from a save or share code.
--   raw  anything; entries need a "custom-N" key and a non-empty name
-- Returns a list of { key, name, colour, rules }. Duplicate keys and entries
-- past Custom.MAX_CATEGORIES are dropped. A bad colour falls back to the
-- default colour instead of dropping the whole category.
function Custom.sanitizeCategories(raw)
  local list, seen = {}, {}
  for _, def in ipairs(type(raw) == "table" and raw or {}) do
    local name = type(def) == "table" and Custom.clean(def.name, Custom.MAX_NAME)
    if name and isKey(def.key, "custom") and not seen[def.key] and #list < Custom.MAX_CATEGORIES then
      seen[def.key] = true
      list[#list + 1] = {
        key = def.key, name = name,
        colour = isColour(def.colour) and math.floor(def.colour) or Custom.DEFAULT_COLOUR,
        rules = sanitizeRules(def.rules),
      }
    end
  end
  return list
end

-- Cleans the list of custom tags read from a save or share code.
--   raw  anything; entries need a "tag-N" key, a label and a valid placement
-- Returns a list of { key, label, colour, placement }.
function Custom.sanitizeTags(raw)
  local list, seen = {}, {}
  for _, def in ipairs(type(raw) == "table" and raw or {}) do
    local label = type(def) == "table" and Custom.clean(def.label, Custom.MAX_LABEL)
    if label and isKey(def.key, "tag") and not seen[def.key] and Custom.isPlacement(def.placement)
      and #list < Custom.MAX_TAGS then
      seen[def.key] = true
      list[#list + 1] = {
        key = def.key, label = label, placement = def.placement,
        colour = isColour(def.colour) and math.floor(def.colour) or Custom.DEFAULT_COLOUR,
      }
    end
  end
  return list
end

-- Returns the next unused key for a new entry, for example "custom-4" when
-- "custom-1" to "custom-3" exist. Numbers are never reused while a higher one
-- exists, so a deleted category's key does not come back straight away.
function Custom.nextKey(prefix, list)
  local highest = 0
  for _, def in ipairs(list or {}) do
    local n = tonumber((def.key or ""):match("^" .. prefix .. "%-(%d+)$"))
    if n and n > highest then highest = n end
  end
  return prefix .. "-" .. (highest + 1)
end

-- Returns true when one name rule matches an item name.
--   rule       { kind = "contains" | "starts", text = string }
--   lowerName  the item name, already lower-cased
-- The rule text is matched as plain text (no Lua patterns), ignoring case.
function Custom.ruleMatches(rule, lowerName)
  local text = rule.text:lower()
  if rule.kind == "starts" then return lowerName:sub(1, #text) == text end
  return lowerName:find(text, 1, true) ~= nil
end

-- Returns true when any of a category's rules match the item name.
function Custom.categoryMatches(def, lowerName)
  for _, rule in ipairs(def.rules or {}) do
    if Custom.ruleMatches(rule, lowerName) then return true end
  end
  return false
end

-- Finds the custom category an item joins through name rules.
--   name        the item's display name (any case)
--   objectId    the item's real id, used to honour exclusions
--   categories  the list of custom category definitions, first match wins
--   excluded    map of category key -> { [objectId] = true } for items the
--               player removed from that category's review list
-- Returns the category key, or nil when no rule matches.
function Custom.categoryFor(name, objectId, categories, excluded)
  local lowerName = (name or ""):lower()
  if lowerName == "" then return nil end
  for _, def in ipairs(categories or {}) do
    local removed = excluded and excluded[def.key]
    if not (removed and removed[objectId]) and Custom.categoryMatches(def, lowerName) then return def.key end
  end
  return nil
end

return Custom
