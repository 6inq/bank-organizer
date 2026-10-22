-- Bank Organizer: recognising Treasure Trail (clue scroll) items.
--
-- The Bank Cleaner must never suggest getting rid of anything a clue scroll
-- needs. The game does not say which items clues need, so this module uses:
--   * a bundled list of hidey-hole (STASH) and emote clue items, generated
--     from the RuneScape Wiki by tools/gen_clue_items.py into
--     src/data/clue_items.lua
--   * a short curated list of clue tools and name patterns for clue
--     scrolls, caskets and puzzle boxes, which are easy to spot by name

local ClueItems = require("src/data/clue_items")

local Clues = {}

-- Every listed name, lower-cased, as a set for quick lookups.
local NAMES = {}
for _, name in ipairs(ClueItems.stash or {}) do NAMES[name:lower()] = true end
for _, name in ipairs(ClueItems.tools or {}) do NAMES[name:lower()] = true end

-- Name fragments that always mean a Treasure Trail item: the scrolls
-- themselves, their caskets and boxes, and the puzzles and devices clues
-- hand out.
local PATTERNS = {
  "clue scroll", "casket", "puzzle box", "scroll box", "lockbox", "celtic knot", "light box", "towers puzzle",
  "challenge scroll", "treasure trail", "strange device", "slide puzzle",
}

-- Returns true when an item is needed for, or part of, Treasure Trails.
--   name  the item's display name (any case)
function Clues.isClue(name)
  local lower = (name or ""):lower()
  if lower == "" then return false end
  if NAMES[lower] then return true end
  for _, pattern in ipairs(PATTERNS) do
    if lower:find(pattern, 1, true) then return true end
  end
  return false
end

-- Returns how many clue items the bundled list holds (for tests and the UI).
function Clues.count()
  local count = 0
  for _ in pairs(NAMES) do count = count + 1 end
  return count
end

return Clues
