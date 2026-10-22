-- Bank Organizer: the fewest insert moves that put one tab in order.
--
-- In the game's Insert mode, dragging an item drops it between two others
-- and everything shifts along. The items that never need to move are the
-- longest run that is already in the right relative order: the "longest
-- increasing subsequence" (LIS) of their target positions. Every other item
-- needs exactly one drag, so the number of moves is the item count minus the
-- LIS length, which is the fewest possible.
--
-- Order.nextMove picks the first item that is out of place and says which
-- in-place item to drop it before (or after, at the end).

local Order = {}

-- Pairs each current item with its position in the target order.
--   currentIDs  the item keys in the tab now, in order
--   targetIDs   the item keys in the order they should end up in
--   skipped     keys to leave out (for example items that are not planned)
-- Returns two parallel lists: the items that appear in the target (in their
-- current order, without repeats) and each one's target position.
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

-- Finds one longest strictly increasing subsequence of ranks.
-- Returns a set of the positions (in ranks) that belong to it.
--
-- This is the classic O(n log n) method: tails[k] is the smallest possible
-- last value of an increasing run of length k found so far. Each value
-- either extends the longest run or replaces a tail, found by binary
-- search. parent links rebuild the run at the end.
local function lisIndexes(ranks)
  local tails, tailIndex, parent = {}, {}, {}
  for i, value in ipairs(ranks) do
    -- Binary search for the first tail that is not smaller than value.
    local lo, hi = 1, #tails + 1
    while lo < hi do
      local mid = (lo + hi) // 2
      if tails[mid] < value then lo = mid + 1 else hi = mid end
    end
    tails[lo], tailIndex[lo] = value, i
    parent[i] = lo > 1 and tailIndex[lo - 1] or nil
  end
  -- Walk back from the end of the longest run to collect its members.
  local members, cursor = {}, tailIndex[#tails]
  while cursor do
    members[cursor] = true
    cursor = parent[cursor]
  end
  return members
end

-- Plans the next insert move for one tab.
--   currentIDs  item keys as they are now
--   targetIDs   item keys as they should be
--   skipped     optional set of keys to ignore
-- Returns nil when the tab is already in order, otherwise a table:
--   move       the item to drag
--   before     the in-place item to drop it in front of, or
--   after      the in-place item to drop it behind (when it goes last)
--   remaining  how many moves are left, including this one
function Order.nextMove(currentIDs, targetIDs, skipped)
  local ids, ranks = rankedSequence(currentIDs or {}, targetIDs or {}, skipped or {})
  local inLis = lisIndexes(ranks)
  local remaining = #ids
  for _ in pairs(inLis) do remaining = remaining - 1 end
  if remaining == 0 then return nil end

  -- The first item (in current order) that is not part of the run moves.
  local moveIndex
  for i = 1, #ids do
    if not inLis[i] then
      moveIndex = i
      break
    end
  end

  -- It goes in front of the in-place item with the smallest rank that is
  -- still bigger than its own.
  local beforeIndex
  for i = 1, #ids do
    if inLis[i] and ranks[i] > ranks[moveIndex] and (beforeIndex == nil or ranks[i] < ranks[beforeIndex]) then
      beforeIndex = i
    end
  end

  if beforeIndex then
    return { move = ids[moveIndex], before = ids[beforeIndex], remaining = remaining }
  end
  -- No bigger rank in place: it belongs after the last in-place item.
  local lastIndex
  for i = 1, #ids do if inLis[i] then lastIndex = i end end
  return { move = ids[moveIndex], after = ids[lastIndex], remaining = remaining }
end

-- Returns a new list with one move applied, as the game would do it: the
-- moved item is taken out and put back before (or after) its anchor. An
-- anchor that is missing puts the item at the end.
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
