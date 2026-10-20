-- Target ordering and a minimal-move planner.
-- Each "insert X before Y" move grows the longest in-order run (LIS) by one,
-- so the number of moves needed is exactly n - LIS.
local Order = {}

-- Keep ids present in both lists and not skipped, preserving current order.
local function rankedSequence(currentIDs, targetIDs, skipped)
  local rankOf = {}
  for index, id in ipairs(targetIDs) do
    if not skipped[id] and rankOf[id] == nil then rankOf[id] = index end
  end
  local ids, ranks, seen = {}, {}, {}
  for _, id in ipairs(currentIDs) do
    if rankOf[id] and not seen[id] then
      seen[id] = true
      ids[#ids + 1], ranks[#ranks + 1] = id, rankOf[id]
    end
  end
  return ids, ranks
end

-- Indexes (into ranks) of one longest strictly increasing subsequence.
local function lisIndexes(ranks)
  local tails, tailIndex, parent = {}, {}, {}
  for i, value in ipairs(ranks) do
    local lo, hi = 1, #tails + 1
    while lo < hi do
      local mid = (lo + hi) // 2
      if tails[mid] < value then lo = mid + 1 else hi = mid end
    end
    tails[lo], tailIndex[lo] = value, i
    parent[i] = lo > 1 and tailIndex[lo - 1] or nil
  end
  local members, cursor = {}, tailIndex[#tails]
  while cursor do
    members[cursor] = true
    cursor = parent[cursor]
  end
  return members
end

---@param currentIDs integer[] ids in the bank's visual order
---@param targetIDs integer[] ids in desired order
---@param skipped table<integer, boolean>?
---@return table? { move, before | after, remaining }
function Order.nextMove(currentIDs, targetIDs, skipped)
  local ids, ranks = rankedSequence(currentIDs or {}, targetIDs or {}, skipped or {})
  local inLis = lisIndexes(ranks)
  local remaining = #ids
  for _ in pairs(inLis) do remaining = remaining - 1 end
  if remaining == 0 then return nil end

  local moveIndex
  for i = 1, #ids do
    if not inLis[i] and (moveIndex == nil or ranks[i] < ranks[moveIndex]) then moveIndex = i end
  end

  local beforeIndex
  for i = 1, #ids do
    if inLis[i] and ranks[i] > ranks[moveIndex] and (beforeIndex == nil or ranks[i] < ranks[beforeIndex]) then
      beforeIndex = i
    end
  end

  if beforeIndex then
    return { move = ids[moveIndex], before = ids[beforeIndex], remaining = remaining }
  end
  local lastIndex = #ids
  if lastIndex == moveIndex then lastIndex = lastIndex - 1 end
  return { move = ids[moveIndex], after = ids[lastIndex], remaining = remaining }
end

-- Applies a move to a list of ids (used by tests and for previewing).
function Order.apply(currentIDs, move)
  local result = {}
  for _, id in ipairs(currentIDs) do
    if id ~= move.move then result[#result + 1] = id end
  end
  local anchor = move.before or move.after
  for index, id in ipairs(result) do
    if id == anchor then
      table.insert(result, move.before and index or index + 1, move.move)
      return result
    end
  end
  result[#result + 1] = move.move
  return result
end

return Order
