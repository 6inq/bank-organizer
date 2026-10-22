-- Bank Organizer tests: the Bank Cleaner, quest states and clue items.
--
-- Requirements covered:
--   * untradeable items whose quests are all finished are suggested as quest
--     leftovers; items for unfinished quests, or whose quest state cannot be
--     read, are never suggested
--   * clue items, rares, the Vanity kind, currency, and items tagged Active,
--     Vanity or Favourite, ignored or kept are never suggested
--   * low value uses the whole stack and the player's threshold
--   * alch suggests items whose high alchemy value beats the GE price
--   * unplaced items are offered for review
--   * repeated unstackable items are one row
--   * quest state is read from the client safely, with a backup

local A = require("assert")
local Cleaner = require("src/core/cleaner")
local Clues = require("src/core/clues")

local T = {}

-- Builds a bank item. extra may set tradeable and cost.
local function item(id, name, quantity, extra)
  extra = extra or {}
  return { id = id, objectId = extra.objectId or id, name = name, quantity = quantity or 1,
    info = { name = name, tradeable = extra.tradeable, cost = extra.cost } }
end

-- Builds a cleaner context where everything is allowed, then applies the
-- given overrides.
local function context(overrides)
  local ctx = {
    -- By default every item is unplaced (Storage & Cleanup) unless the test sets item.kind.
    tagOf = function(it) return it.kind or "cleanup" end,
    tagsOf = function() return {} end,
    -- Nothing is ignored, kept or tagged unless the test says so.
    isIgnored = function() return false end,
    isKept = function() return false end,
    isClue = Clues.isClue,
    -- No quests and no GE prices unless the test says so.
    questState = function() return "none" end,
    price = function() return nil end,
    threshold = 1000,
  }
  for k, v in pairs(overrides or {}) do ctx[k] = v end
  return ctx
end

-- Returns the names of the rows in one group.
local function namesIn(groups, key)
  local out = {}
  for index, row in ipairs(groups[key]) do out[index] = row.name end
  return out
end

-- Requirement: finished quests make leftovers; unfinished or unreadable
-- quests keep the item.
function T.quest_items_follow_quest_progress()
  local states = { [1] = "done", [2] = "open", [3] = "unknown" }
  local groups = Cleaner.suggest({
    item(1, "Old key", 1, { tradeable = false }), item(2, "Current key", 1, { tradeable = false }),
    item(3, "Mystery key", 1, { tradeable = false }),
  }, context({ questState = function(id) return states[id] end }))
  A.list(namesIn(groups, "quest"), { "Old key" })
  A.eq(Cleaner.total(groups), 1, "the unfinished and unreadable ones are kept")
end

-- Requirement: protected items are never suggested, whatever their value.
function T.protected_items_are_never_suggested()
  local bank = {
    item(1, "Bronze dagger", 1, { cost = 10 }), item(2, "Clue scroll (easy)", 1), item(3, "Red partyhat", 1),
    item(4, "Shark", 1, { cost = 5 }), item(5, "Lobster", 1, { cost = 5 }), item(6, "Trout", 1, { cost = 5 }),
    item(7, "Bucket", 1, { cost = 2 }), item(8, "Coins", 5), item(9, "Spade", 1, { cost = 3 }),
    item(10, "Sardine", 1, { cost = 1 }), item(11, "Pot", 1, { cost = 1 }),
  }
  bank[8].kind = "currency"
  bank[10].kind = "vanity"
  local tags = { [4] = { active = true }, [5] = { favourite = true }, [6] = { vanity = true }, [11] = { sell = true } }
  local groups = Cleaner.suggest(bank, context({
    -- Tags and ignores for this test's items.
    tagsOf = function(id) return tags[id] or {} end,
    isIgnored = function(id) return id == 7 end,
  }))
  A.eq(Cleaner.total(groups), 0, "stash item, clue scroll, rare, Active, Favourite, Vanity, ignored, coins, clue tool, Vanity kind, already Sell")
  groups = Cleaner.suggest({ item(7, "Bucket", 1, { cost = 2 }) }, context({ isKept = function() return true end }))
  A.eq(Cleaner.total(groups), 0, "the Keep list")
end

-- Requirement: low value compares the whole stack with the threshold, and
-- uses the GE price when there is one.
function T.low_value_uses_the_stack_and_the_threshold()
  local bank = { item(1, "Bucket", 10, { cost = 2 }), item(2, "Air rune", 1000, { cost = 4 }), item(3, "Pot", 1, { cost = 1 }) }
  A.list(namesIn(Cleaner.suggest(bank, context()), "low"), { "Bucket", "Pot" }, "20 gp and 1 gp stacks; 4,000 gp of runes is not low")
  A.list(namesIn(Cleaner.suggest(bank, context({ threshold = 10 })), "low"), { "Pot" }, "a lower threshold")
  A.list(namesIn(Cleaner.suggest(bank, context({ price = function(id) return id == 1 and 500 or nil end })), "low"), { "Pot" },
    "the GE price makes the buckets worth 5,000 gp")
  local row = Cleaner.suggest(bank, context()).low[1]
  A.truthy(row.reason:find("20 gp", 1, true), row.reason)
end

-- Requirement: suggest alching when high alchemy pays more than the GE.
function T.alch_beats_the_grand_exchange()
  local bank = { item(1, "Rune platelegs", 1, { cost = 64000 }) }
  bank[1].kind = "gear"
  local groups = Cleaner.suggest(bank, context({ price = function() return 30000 end, threshold = 0 }))
  A.list(namesIn(groups, "alch"), { "Rune platelegs" })
  A.truthy(groups.alch[1].reason:find("38,400", 1, true), groups.alch[1].reason)
  groups = Cleaner.suggest(bank, context({ price = function() return 50000 end, threshold = 0 }))
  A.eq(Cleaner.total(groups), 0, "the GE pays more")
  groups = Cleaner.suggest(bank, context({ threshold = 0 }))
  A.eq(#groups.alch, 0, "no GE price, no alch comparison")
end

-- Requirement: items the classifier could not place are offered for review.
function T.unplaced_items_are_offered_for_review()
  local bank = { item(1, "Strange thing", 1, { tradeable = false }) }
  A.list(namesIn(Cleaner.suggest(bank, context()), "review"), { "Strange thing" })
  bank[1].kind = "gear"
  A.eq(Cleaner.total(Cleaner.suggest(bank, context())), 0, "placed untradeable items are left alone")
end

-- Requirement: repeated unstackable items (Ushabti) are one row.
function T.repeated_items_are_one_row()
  local bank = { item(1, "Ushabti", 1, { cost = 1 }), item(1 + 2 ^ 24, "Ushabti", 1, { cost = 1, objectId = 1 }) }
  local groups = Cleaner.suggest(bank, context())
  A.eq(#groups.low, 1); A.eq(groups.low[1].quantity, 2)
end

-- Requirement: coin amounts read with thousands separators.
function T.coins_are_readable()
  A.eq(Cleaner.coins(0), "0"); A.eq(Cleaner.coins(999), "999"); A.eq(Cleaner.coins(1000), "1,000")
  A.eq(Cleaner.coins(1234567), "1,234,567"); A.eq(Cleaner.coins(-4500), "-4,500")
end

-- Requirement: clue items are recognised from the bundled list, the tool
-- list and name patterns, and ordinary items are not.
function T.clue_items_are_recognised()
  A.truthy(Clues.count() > 100, "the generated hidey-hole list is bundled")
  for _, name in ipairs({ "Bronze dagger", "AMULET OF GLORY", "Sextant", "Clue scroll (elite)", "Reward casket (master)", "Puzzle box" }) do
    A.eq(Clues.isClue(name), true, name)
  end
  for _, name in ipairs({ "Shark", "Abyssal whip", "", nil }) do A.eq(Clues.isClue(name), false, tostring(name)) end
end

-- Requirement: quest state comes from hasFinishedQuest, falls back to the
-- quest's progress variable, and is "unknown" when nothing can be read.
function T.quest_state_is_read_safely()
  local finished = { hasFinishedQuest = true }
  local open = { hasFinishedQuest = false }
  local byVar = { masterQuestVars = { { varPlayer = { value = 10 }, endState = 10 } } }
  local byVarOpen = { masterQuestVars = { { varPlayer = { value = 3 }, endState = 10 } } }
  local broken = setmetatable({}, { __index = function() error("unreadable") end })
  local objects = {
    [1] = { quests = { finished } }, [2] = { quests = { finished, open } }, [3] = { quests = { byVar } },
    [4] = { quests = { byVarOpen } }, [5] = { quests = { broken } }, [6] = { quests = {} },
  }
  _G.config = { Obj = { FromID = function(objectId)
    if objectId == 7 then error("no config") end
    return objects[objectId]
  end } }
  package.loaded["src/game/quests"] = nil
  local Quests = require("src/game/quests")
  A.eq(Quests.state(1), "done"); A.eq(Quests.state(2), "open"); A.eq(Quests.state(3), "done", "by progress variable")
  A.eq(Quests.state(4), "open"); A.eq(Quests.state(5), "unknown"); A.eq(Quests.state(6), "none")
  A.eq(Quests.state(7), "unknown", "a failing read never throws")
  A.eq(Quests.state(99), "unknown", "no config: unsure, so the item is kept")
end

-- Requirement: the low value limit can be typed the way players write
-- amounts: plain, with commas, or with k, m and b in either case.
function T.typed_amounts_are_understood()
  local cases = {
    { "500", 500 }, { "1,000", 1000 }, { "250k", 250000 }, { "1m", 1000000 }, { "1.5m", 1500000 },
    { "200M", 200000000 }, { "1b", 1000000000 }, { "3b", 3000000000 }, { " 2.25 B ", 2250000000 },
    { "750gp", 750 }, { ".5m", 500000 }, { "0", 0 },
  }
  for _, case in ipairs(cases) do A.eq(Cleaner.parseCoins(case[1]), case[2], case[1]) end
  for _, bad in ipairs({ "", "abc", "1x", "-5", "1mm", "2t", "1.2.3", "9999b" }) do
    A.eq(Cleaner.parseCoins(bad), nil, "refused: " .. bad)
  end
  A.eq(Cleaner.parseCoins(nil), nil)
end

-- Requirement: the limit is shown back in the same short form.
function T.amounts_are_shown_short()
  A.eq(Cleaner.shortCoins(750), "750"); A.eq(Cleaner.shortCoins(1000), "1k"); A.eq(Cleaner.shortCoins(250000), "250k")
  A.eq(Cleaner.shortCoins(1500000), "1.5m"); A.eq(Cleaner.shortCoins(200000000), "200m"); A.eq(Cleaner.shortCoins(3000000000), "3b")
  A.eq(Cleaner.shortCoins(2250000000), "2.25b")
end

-- Requirement: every group gives its own tag: quest leftovers and low
-- value Trash, worth alching Alch, review Rev (the Review tag).
function T.each_group_gives_its_tag()
  A.eq(Cleaner.TAG_OF.quest, "trash"); A.eq(Cleaner.TAG_OF.low, "trash")
  A.eq(Cleaner.TAG_OF.alch, "alch"); A.eq(Cleaner.TAG_OF.review, "review")
  local Placement = require("src/core/placement")
  A.eq(Placement.byKey.review.badge, "Rev"); A.eq(Placement.byKey.review.placement, "bottom")
end

-- Requirement: an item already carrying its group's tag stays listed as
-- ticked; an item the player tagged something else is left alone.
function T.tagged_items_stay_listed_as_ticked()
  local bank = { item(1, "Bucket", 1, { cost = 2 }), item(2, "Pot", 1, { cost = 1 }), item(3, "Jug", 1, { cost = 1 }) }
  local tags = { [1] = { trash = true }, [2] = { sell = true } }
  local groups = Cleaner.suggest(bank, context({ tagsOf = function(id) return tags[id] or {} end }))
  A.list(namesIn(groups, "low"), { "Bucket", "Jug" }, "the Sell-tagged pot was already decided")
  A.eq(groups.low[1].tagged, true); A.eq(groups.low[1].tag, "trash")
  A.eq(groups.low[2].tagged, false)
end

return T
