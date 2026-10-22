-- Bank Organizer: the Bank Cleaner's suggestions.
--
-- The Bank Cleaner looks for items the player may be able to get rid of and
-- explains why. It never destroys, drops, sells or moves anything. Each
-- group has a tag: ticking an item gives it that tag at once (and unticking
-- takes it away), so the Sorting Guide lines it up at the bottom of the
-- infinity tab. Items can also be Kept, so they are never suggested again.
--
-- Items are never suggested when they are:
--   * ignored, on the Keep list, or tagged Active, Vanity or Favourite
--   * rares (partyhats and the like) or anything of the Vanity kind
--   * coins, tokens and other currency
--   * needed for a quest the player has not finished, or whose quest
--     progress cannot be read (when unsure, keep it)
--   * Treasure Trail items (see src/core/clues.lua)
--   * already tagged Sell, Alch, Disassemble, Trash or Review, unless that
--     tag is the one their group gives (then they are listed as ticked)
--
-- Everything else may land in one group, checked in this order:
--   quest  untradeable quest items whose quests are all complete
--   alch   tradeable items whose high alchemy value beats the GE price
--   low    tradeable items whose whole stack is worth less than the
--          player's threshold
--   review items the classifier could not place (Storage & Cleanup)

local Classify = require("src/core/classify")

local Cleaner = {}

-- The groups in the order the window shows them. tag is the tag a ticked
-- item in the group gets.
Cleaner.GROUPS = {
  { key = "quest", title = "Quest leftovers", tag = "trash", hint = "Quests done. Many quest items can be reclaimed from an NPC if you need them again." },
  { key = "alch", title = "Worth more alched", tag = "alch", hint = "High Alchemy pays more than the Grand Exchange." },
  { key = "low", title = "Low value", tag = "trash", hint = "The whole stack is worth less than your threshold." },
  { key = "review", title = "Review", tag = "review", hint = "Items Bank Organizer could not place. Have a look." },
}

-- Group key -> the tag its ticked items get.
Cleaner.TAG_OF = {}
for _, group in ipairs(Cleaner.GROUPS) do Cleaner.TAG_OF[group.key] = group.tag end

-- High Alchemy pays 60% of an item's value (rounded down).
Cleaner.HIGH_ALCH = 0.6

-- Tags that mean "keep this" and tags that mean "already decided".
local KEEP_TAGS = { active = true, vanity = true, favourite = true }
local DECIDED_TAGS = { sell = true, alch = true, disassemble = true, trash = true, review = true }

-- Kinds of item that are never suggested.
local KEEP_KINDS = { vanity = true, currency = true }

-- Formats a whole number with thousands separators: 1234567 -> "1,234,567".
function Cleaner.coins(n)
  local text = tostring(math.floor(n or 0))
  local sign, digits = text:match("^(-?)(%d+)$")
  if not digits then return text end
  -- Insert a comma before every group of three digits from the right.
  digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return sign .. digits
end

-- The largest amount the low value limit accepts: 1,000b.
Cleaner.MAX_THRESHOLD = 1000000000000

-- What each amount suffix multiplies by.
local SUFFIX = { [""] = 1, k = 1000, m = 1000000, b = 1000000000 }

-- Reads an amount of coins typed by the player.
--   text  for example "500", "1,000", "250k", "1m", "1.5m", "200M", "3b"
-- Spaces, commas and a trailing "gp" are allowed; the suffix is k, m or b
-- in either case. Returns a whole number of coins (0 to MAX_THRESHOLD), or
-- nil when the text is not an amount.
function Cleaner.parseCoins(text)
  if type(text) ~= "string" then return nil end
  local cleaned = text:lower():gsub("[%s,]", ""):gsub("gp$", "")
  local number, suffix = cleaned:match("^(%d+%.?%d*)([kmb]?)$")
  if not number then number, suffix = cleaned:match("^(%.%d+)([kmb]?)$") end
  if not number then return nil end
  local coins = math.floor(tonumber(number) * SUFFIX[suffix] + 0.5)
  if coins < 0 or coins > Cleaner.MAX_THRESHOLD then return nil end
  return coins
end

-- Writes an amount the short way players type it: "750", "250k", "1m",
-- "1.5m", "3b". Up to two decimals are kept and trailing zeros dropped.
function Cleaner.shortCoins(coins)
  coins = math.floor(coins or 0)
  for _, unit in ipairs({ { 1000000000, "b" }, { 1000000, "m" }, { 1000, "k" } }) do
    if coins >= unit[1] then
      local text = string.format("%.2f", coins / unit[1]):gsub("0+$", ""):gsub("%.$", "")
      return text .. unit[2]
    end
  end
  return tostring(coins)
end

-- Returns true when any key in the item's tag set is in the lookup table.
local function carries(set, lookup)
  for key in pairs(set or {}) do
    if lookup[key] then return true end
  end
  return false
end

-- Merges repeated unstackable items (for example several filled Ushabti) into
-- one row per real item id, adding up their quantities.
--   items  bank items { id, objectId, name, quantity, info }
-- Returns a list of { objectId, name, quantity, info, item } in bank order.
local function merge(items)
  local rows, byId = {}, {}
  for _, item in ipairs(items or {}) do
    local objectId = item.objectId or item.id
    local row = byId[objectId]
    if row then
      row.quantity = row.quantity + (tonumber(item.quantity) or 0)
    else
      row = { objectId = objectId, name = item.name, quantity = tonumber(item.quantity) or 0, info = item.info or {}, item = item }
      byId[objectId] = row
      rows[#rows + 1] = row
    end
  end
  return rows
end

-- Returns true when the cleaner must never suggest this row.
--   row  a merged row (see merge)
--   ctx  the context table (see Cleaner.suggest)
local function protected(row, ctx)
  local set = ctx.tagsOf and ctx.tagsOf(row.objectId) or {}
  if ctx.isIgnored and ctx.isIgnored(row.objectId) then return true end
  if ctx.isKept and ctx.isKept(row.objectId) then return true end
  if carries(set, KEEP_TAGS) then return true end
  if KEEP_KINDS[ctx.tagOf(row.item)] or Classify.isRare(row.name) then return true end
  if ctx.isClue and ctx.isClue(row.name) then return true end
  -- Quest items: keep unless every related quest is known to be finished.
  local quest = ctx.questState and ctx.questState(row.objectId) or "none"
  return quest == "open" or quest == "unknown"
end

-- Decides which group a row belongs to and why.
-- Returns the group key and the reason text, or nil when it is not a
-- suggestion.
local function judge(row, ctx)
  local info = row.info
  local tradeable = info.tradeable ~= false
  local quest = ctx.questState and ctx.questState(row.objectId) or "none"
  if not tradeable and quest == "done" then
    return "quest", "All of its quests are complete."
  end
  local value = tonumber(info.cost) or 0
  local price = ctx.price and ctx.price(row.objectId) or nil
  if tradeable then
    local alch = math.floor(value * Cleaner.HIGH_ALCH)
    if price and alch > price then
      return "alch", "High Alchemy gives " .. Cleaner.coins(alch) .. " gp; the GE pays about " .. Cleaner.coins(price) .. " gp."
    end
    local each = price or value
    local total = each * math.max(1, row.quantity)
    if total < (ctx.threshold or 0) then
      return "low", "The stack is worth about " .. Cleaner.coins(total) .. " gp."
    end
  end
  if ctx.tagOf(row.item) == "cleanup" then
    return "review", "Bank Organizer could not tell what kind of item this is."
  end
  return nil
end

-- Builds the cleaner's suggestions.
--   items  bank items as read by the bank reader
--   ctx    a table of questions the cleaner asks about each item:
--            tagOf(item)          -> kind key
--            tagsOf(objectId)     -> set of tags on the item
--            isIgnored(objectId)  -> boolean
--            isKept(objectId)     -> boolean (the cleaner's Keep list)
--            isClue(name)         -> boolean
--            questState(objectId) -> "none", "done", "open" or "unknown"
--            price(objectId)      -> GE price in coins, or nil
--            threshold            -> the low value limit in coins
-- Returns true when the item carries a "decided" tag other than the one
-- its group gives: the player already chose something else for it.
local function decidedOtherwise(set, groupTag)
  for key in pairs(set or {}) do
    if DECIDED_TAGS[key] and key ~= groupTag then return true end
  end
  return false
end

-- Returns a table: group key -> list of rows, where each row is
-- { objectId, name, quantity, reason, group, tag, tagged }: tag is the tag
-- ticking it gives, and tagged is true when the item already has it. Every
-- group key from Cleaner.GROUPS is present, possibly with an empty list.
function Cleaner.suggest(items, ctx)
  local groups = {}
  for _, group in ipairs(Cleaner.GROUPS) do groups[group.key] = {} end
  for _, row in ipairs(merge(items)) do
    if not protected(row, ctx) then
      local key, reason = judge(row, ctx)
      local set = ctx.tagsOf and ctx.tagsOf(row.objectId) or {}
      local tag = key and Cleaner.TAG_OF[key]
      if key and not decidedOtherwise(set, tag) then
        local list = groups[key]
        list[#list + 1] = { objectId = row.objectId, name = row.name, quantity = row.quantity, reason = reason, group = key,
          tag = tag, tagged = set[tag] == true }
      end
    end
  end
  return groups
end

-- Counts every suggestion across all groups.
function Cleaner.total(groups)
  local total = 0
  for _, list in pairs(groups or {}) do total = total + #list end
  return total
end

return Cleaner
