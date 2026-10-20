local A = require("assert")
local Order = require("src/core/order")

local T = {}

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

function T.sorted_returns_nil() A.eq(Order.nextMove({ 1, 2, 3 }, { 1, 2, 3 }), nil) end
function T.empty_returns_nil() A.eq(Order.nextMove({}, {}), nil) end
function T.single_returns_nil() A.eq(Order.nextMove({ 7 }, { 7 }), nil) end

function T.one_item_out_of_place()
  local move = Order.nextMove({ 1, 2, 4, 5, 3 }, { 1, 2, 3, 4, 5 })
  A.eq(move.move, 3); A.eq(move.before, 4); A.eq(move.remaining, 1)
end

function T.item_belonging_at_end_returns_after()
  local move = Order.nextMove({ 5, 1, 2, 3, 4 }, { 1, 2, 3, 4, 5 })
  A.eq(move.move, 5); A.eq(move.after, 4); A.eq(move.before, nil); A.eq(move.remaining, 1)
  A.list(Order.apply({ 5, 1, 2, 3, 4 }, move), { 1, 2, 3, 4, 5 })
end

function T.reverse_converges_in_n_minus_one()
  local current, target = {}, {}
  for i = 1, 12 do target[i] = i; current[i] = 13 - i end
  local final, moves, first = solve(current, target)
  A.list(final, target); A.eq(moves, 11); A.eq(first.remaining, 11)
end

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

function T.skipped_ids_are_ignored()
  local move = Order.nextMove({ 3, 1, 2 }, { 1, 2, 3 }, { [3] = true })
  A.eq(move, nil)
end

function T.ids_in_only_one_list_ignored()
  A.eq(Order.nextMove({ 1, 99, 2 }, { 1, 2, 50 }), nil)
end

function T.apply_before_and_after()
  A.list(Order.apply({ 1, 2, 3 }, { move = 3, before = 1 }), { 3, 1, 2 })
  A.list(Order.apply({ 1, 2, 3 }, { move = 1, after = 3 }), { 2, 3, 1 })
end

return T
