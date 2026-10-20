local A = require("assert")
local Verify = require("src/core/verify")
local Order = require("src/core/order")

local T = {}

local BEFORE = { [0] = { 9 }, [1] = { 1, 2, 3, 4 } }

local function insert(before, anchor) return { kind = "insert", section = 1, move = 4, before = before, after = anchor } end

function T.nothing_moved_yet_is_waiting()
  A.eq(Verify.check(BEFORE, Verify.copy(BEFORE), insert(1)), "waiting")
end

function T.the_instructed_insert_is_done()
  A.eq(Verify.check(BEFORE, { [0] = { 9 }, [1] = { 4, 1, 2, 3 } }, insert(1)), "done")
end

function T.landing_just_after_the_target_still_counts()
  A.eq(Verify.check(BEFORE, { [0] = { 9 }, [1] = { 1, 4, 2, 3 } }, insert(1)), "done", "RS3 drops a forward drag after the item")
end

function T.swapping_instead_of_inserting_is_a_mistake()
  A.eq(Verify.check(BEFORE, { [0] = { 9 }, [1] = { 4, 2, 3, 1 } }, insert(1)), "mistake")
end

function T.moving_a_different_item_is_a_mistake()
  A.eq(Verify.check(BEFORE, { [0] = { 9 }, [1] = { 2, 1, 3, 4 } }, insert(1)), "mistake")
end

function T.deposits_and_withdrawals_are_not_mistakes()
  A.eq(Verify.check(BEFORE, { [0] = { 9, 7 }, [1] = { 1, 2, 3, 4 } }, insert(1)), "changed")
  A.eq(Verify.check(BEFORE, { [0] = {}, [1] = { 1, 2, 3, 4 } }, insert(1)), "changed")
end

function T.swaps_must_match_exactly()
  local step = { kind = "swap", section = 1, move = 4, swapWith = 1 }
  A.eq(Verify.check(BEFORE, { [0] = { 9 }, [1] = { 4, 2, 3, 1 } }, step), "done")
  A.eq(Verify.check(BEFORE, { [0] = { 9 }, [1] = { 4, 1, 2, 3 } }, step), "mistake", "inserted instead of swapped")
end

function T.tab_moves_need_the_right_tab()
  local step = { kind = "to-tab", id = 9, from = 0, to = 1 }
  A.eq(Verify.check(BEFORE, { [0] = {}, [1] = { 1, 2, 3, 4, 9 } }, step), "done")
  A.eq(Verify.check(BEFORE, { [0] = {}, [1] = { 1, 2, 3, 4 }, [2] = { 9 } }, step), "mistake", "dropped on a new tab instead")
  local newTab = { kind = "new-tab", id = 9, from = 0, to = 2 }
  A.eq(Verify.check(BEFORE, { [0] = {}, [1] = { 1, 2, 3, 4 }, [2] = { 9 } }, newTab), "done")
end

local function apply(sections, step)
  local out = Verify.copy(sections)
  if step.kind == "insert" then
    out[step.section] = Order.apply(out[step.section], step)
  elseif step.kind == "swap" then
    local list = out[step.section]
    local a, b
    for index, id in ipairs(list) do
      if id == step.move then a = index end
      if id == step.swapWith then b = index end
    end
    list[a], list[b] = list[b], list[a]
  end
  return out
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

return T
