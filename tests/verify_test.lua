local A = require("assert")
local Verify = require("src/core/verify")
local Order = require("src/core/order")

local T = {}

local BEFORE = { [0] = { 9 }, [1] = { 1, 2, 3, 4 } }

local function judge(after, step)
  return Verify.check(BEFORE, Verify.flatten(after), after, step)
end

local function insert(before, anchor) return { kind = "insert", section = 1, move = 4, before = before, after = anchor } end

function T.nothing_moved_yet_is_waiting()
  A.eq(judge(Verify.copy(BEFORE), insert(1)), "waiting")
end

function T.the_instructed_insert_is_done()
  A.eq(judge({ [0] = { 9 }, [1] = { 4, 1, 2, 3 } }, insert(1)), "done")
end

function T.landing_just_after_the_target_still_counts()
  A.eq(judge({ [0] = { 9 }, [1] = { 1, 4, 2, 3 } }, insert(1)), "done", "RS3 drops a forward drag after the item")
end

function T.swapping_instead_of_inserting_is_a_mistake()
  A.eq(judge({ [0] = { 9 }, [1] = { 4, 2, 3, 1 } }, insert(1)), "mistake")
end

function T.moving_a_different_item_is_a_mistake()
  A.eq(judge({ [0] = { 9 }, [1] = { 2, 1, 3, 4 } }, insert(1)), "mistake")
end

function T.deposits_and_withdrawals_are_not_mistakes()
  A.eq(judge({ [0] = { 9, 7 }, [1] = { 1, 2, 3, 4 } }, insert(1)), "changed")
  A.eq(judge({ [0] = {}, [1] = { 1, 2, 3, 4 } }, insert(1)), "changed")
end

function T.swaps_must_match_exactly()
  local step = { kind = "swap", section = 1, move = 4, swapWith = 1 }
  A.eq(judge({ [0] = { 9 }, [1] = { 4, 2, 3, 1 } }, step), "done")
  A.eq(judge({ [0] = { 9 }, [1] = { 4, 1, 2, 3 } }, step), "mistake", "inserted instead of swapped")
end

function T.tab_moves_need_the_right_tab()
  local step = { kind = "to-tab", id = 9, from = 0, to = 1 }
  A.eq(judge({ [0] = {}, [1] = { 1, 2, 3, 4, 9 } }, step), "done")
  local newTab = { kind = "new-tab", id = 9, from = 0, to = 2 }
  A.eq(judge({ [0] = {}, [1] = { 1, 2, 3, 4 }, [2] = { 9 } }, newTab), "done")
end

local TWO_TABS = { [0] = { 7, 9 }, [1] = { 1, 2 }, [2] = { 5, 6 } }

function T.a_tab_drop_counts_even_while_the_games_tab_sizes_lag()
  local step = { kind = "to-tab", id = 9, from = 0, to = 1 }
  local flat = { 1, 2, 9, 5, 6, 7 }
  local stale = { [0] = { 6, 7 }, [1] = { 1, 2 }, [2] = { 9, 5 } }
  local verdict, expected = Verify.check(TWO_TABS, flat, stale, step)
  A.eq(verdict, "done", "the order says the bones landed at the end of tab 1")
  A.list(Verify.sizes(expected, 2), { 3, 2 }, "the sizes the move must have produced")
end

function T.a_drop_on_the_wrong_tab_is_a_mistake()
  local step = { kind = "to-tab", id = 9, from = 0, to = 1 }
  local flat = { 1, 2, 5, 6, 9, 7 }
  A.eq(Verify.check(TWO_TABS, flat, { [0] = { 7 }, [1] = { 1, 2 }, [2] = { 5, 6, 9 } }, step), "mistake")
end

function T.when_only_tab_sizes_change_they_decide()
  local step = { kind = "to-tab", id = 7, from = 0, to = 2 }
  local flat = { 1, 2, 5, 6, 7, 9 }
  A.eq(Verify.check(TWO_TABS, flat, TWO_TABS, step), "waiting", "order and sizes both unchanged")
  A.eq(Verify.check(TWO_TABS, flat, { [0] = { 9 }, [1] = { 1, 2 }, [2] = { 5, 6, 7 } }, step), "done")
end

function T.flatten_follows_the_bank_order()
  A.list(Verify.flatten(TWO_TABS), { 1, 2, 5, 6, 7, 9 }, "custom tabs first, then infinity")
  A.list(Verify.flatten(TWO_TABS, false), { 7, 9, 1, 2, 5, 6 })
end

local function apply(sections, step)
  return Verify.apply(sections, step)
end

function T.restore_steps_lead_back_to_where_you_were()
  for _, mode in ipairs({ "insert", "swap" }) do
    local current = { [0] = { 9 }, [1] = { 4, 2, 3, 1 } }
    for _ = 1, 6 do
      if Verify.same(current, BEFORE) then break end
      current = apply(current, Verify.restoreStep(current, BEFORE, mode))
    end
    A.eq(Verify.same(current, BEFORE), true, mode .. " mode restores the bank")
  end
end

function T.mistake_lines_name_the_first_change()
  local line = Verify.describe({ 1, 2, 3 }, { 1, 3, 2 }, { kind = "insert", move = 3, before = 2 })
  A.truthy(line:find("insert:3->2", 1, true), line)
  A.truthy(line:find("first change at 2: 2 -> 3", 1, true), line)
end

return T
