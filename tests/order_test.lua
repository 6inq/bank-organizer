-- Bank Organizer tests: the fewest-insert-moves planner (src/core/order.lua).
--
-- Requirements covered: every planned move sequence ends in the target
-- order, the count of moves is the minimum (items minus the longest run
-- already in order), and skipped items are left alone.

local A = require("assert")
local Order = require("src/core/order")

local T = {}

-- Applies Order.nextMove until done. Returns the final list, the number of
-- moves made and the first move (with its predicted count).
local function solve(current, target, skipped, limit)
  local first = Order.nextMove(current, target, skipped)
  local moves, move = 0, first
  while move do
    current = Order.apply(current, move)
    moves = moves + 1
    if moves > (limit or 10000) then error("did not converge") end
    move = Order.nextMove(current, target, skipped)
  end
  return current, moves, first
end

-- Requirement: Sorted returns nil.
function T.sorted_returns_nil() A.eq(Order.nextMove({ 1, 2, 3 }, { 1, 2, 3 }), nil) end
-- Requirement: Empty returns nil.
function T.empty_returns_nil() A.eq(Order.nextMove({}, {}), nil) end
-- Requirement: Single returns nil.
function T.single_returns_nil() A.eq(Order.nextMove({ 7 }, { 7 }), nil) end

-- Requirement: One item out of place.
function T.one_item_out_of_place()
  local move = Order.nextMove({ 1, 2, 4, 5, 3 }, { 1, 2, 3, 4, 5 })
  A.eq(move.move, 3); A.eq(move.before, 4); A.eq(move.remaining, 1)
end

-- Requirement: Item belonging at end returns after.
function T.item_belonging_at_end_returns_after()
  local move = Order.nextMove({ 5, 1, 2, 3, 4 }, { 1, 2, 3, 4, 5 })
  A.eq(move.move, 5); A.eq(move.after, 4); A.eq(move.before, nil); A.eq(move.remaining, 1)
  A.list(Order.apply({ 5, 1, 2, 3, 4 }, move), { 1, 2, 3, 4, 5 })
end

-- Requirement: Reverse converges in n minus one.
function T.reverse_converges_in_n_minus_one()
  local current, target = {}, {}
  for i = 1, 12 do target[i] = i; current[i] = 13 - i end
  local final, moves, first = solve(current, target)
  A.list(final, target); A.eq(moves, 11); A.eq(first.remaining, 11)
end

-- Requirement: Random permutations minimal and converge.
function T.random_permutations_minimal_and_converge()
  for seed = 1, 200 do
    math.randomseed(seed)
    local n = math.random(1, 60)
    local target, current = {}, {}
    for i = 1, n do target[i] = i * 10; current[i] = i * 10 end
    for i = n, 2, -1 do
      local j = math.random(1, i)
      current[i], current[j] = current[j], current[i]
    end
    local final, moves, first = solve(current, target)
    A.list(final, target, "seed " .. seed)
    A.eq(moves, first and first.remaining or 0, "seed " .. seed .. " move count")
  end
end

-- Requirement: Skipped ids are ignored.
function T.skipped_ids_are_ignored()
  local move = Order.nextMove({ 3, 1, 2 }, { 1, 2, 3 }, { [3] = true })
  A.eq(move, nil)
end

-- Requirement: Ids in only one list ignored.
function T.ids_in_only_one_list_ignored()
  A.eq(Order.nextMove({ 1, 99, 2 }, { 1, 2, 50 }), nil)
end

-- Requirement: Apply before and after.
function T.apply_before_and_after()
  A.list(Order.apply({ 1, 2, 3 }, { move = 3, before = 1 }), { 3, 1, 2 })
  A.list(Order.apply({ 1, 2, 3 }, { move = 1, after = 3 }), { 2, 3, 1 })
end

return T
