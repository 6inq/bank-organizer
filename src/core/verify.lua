-- Bank Organizer: checking each move the player makes.
--
-- After the guide asks for a move, the next bank read is compared with what
-- the bank should look like if that move was made. Possible verdicts:
--   done      the right move (the guide carries on)
--   waiting   nothing has changed yet
--   changed   items were added or removed (not a move at all)
--   mistake   something else moved: the guide walks the player back
--
-- Moves are judged on the FLAT item order (every item of the bank in the
-- order the game stores them), not on per-tab lists. The game updates its
-- item order straight away but can report the tab sizes a few ticks late,
-- so per-tab lists built from stale sizes would make a right move look wrong.
--
-- Sections throughout are tables of tab position -> list of item keys.

local Guide = require("src/core/guide")
local Order = require("src/core/order")

local Verify = {}

-- Returns a deep copy of a sections table (new lists, same keys).
function Verify.copy(sections)
  local out = {}
  for s, ids in pairs(sections) do
    local list = {}
    for index, id in ipairs(ids) do list[index] = id end
    out[s] = list
  end
  return out
end

-- Returns the highest tab position in a sections table.
local function last(sections)
  local high = 0
  for s in pairs(sections) do if s > high then high = s end end
  return high
end

-- Returns true when two lists hold the same values in the same order.
local function listsEqual(a, b)
  if #a ~= #b then return false end
  for index = 1, #a do if a[index] ~= b[index] then return false end end
  return true
end

-- Returns true when every tab holds the same items in the same order.
function Verify.same(a, b)
  for s = 0, math.max(last(a), last(b)) do
    if not listsEqual(a[s] or {}, b[s] or {}) then return false end
  end
  return true
end

-- Counts how many times each key appears across a table of lists.
local function countIds(lists)
  local count = {}
  for _, ids in pairs(lists) do for _, id in ipairs(ids) do count[id] = (count[id] or 0) + 1 end end
  return count
end

-- Returns true when both sides hold exactly the same items (in any order
-- and any tab). False means items were added or removed.
function Verify.sameItems(a, b)
  local left, right = countIds(a), countIds(b)
  for id, n in pairs(left) do if right[id] ~= n then return false end end
  for id, n in pairs(right) do if left[id] ~= n then return false end end
  return true
end

-- Builds the stored order of tabs from a sequence list, adding any tab in
-- sections that the sequence does not mention just before the infinity
-- tab (where the game stores new tabs).
local function sequenceFor(sections, sequence)
  local listed, order = {}, {}
  for _, s in ipairs(sequence) do listed[s] = true end
  local extra = {}
  for s in pairs(sections) do if not listed[s] then extra[#extra + 1] = s end end
  table.sort(extra)
  for _, s in ipairs(sequence) do
    if s == 0 then for _, e in ipairs(extra) do order[#order + 1] = e end end
    order[#order + 1] = s
  end
  return order
end

-- Joins all tabs into one list in the order the game stores them.
--   tabsFirst  either a list of tab positions in stored order (the live
--              mapping), true (custom tabs, then infinity) or false
--              (infinity, then custom tabs)
function Verify.flatten(sections, tabsFirst)
  local order = {}
  if type(tabsFirst) == "table" then
    order = sequenceFor(sections, tabsFirst)
  elseif tabsFirst ~= false then
    for s = 1, last(sections) do order[#order + 1] = s end
    order[#order + 1] = 0
  else
    order[1] = 0
    for s = 1, last(sections) do order[#order + 1] = s end
  end
  local flat = {}
  for _, s in ipairs(order) do
    for _, id in ipairs(sections[s] or {}) do flat[#flat + 1] = id end
  end
  return flat
end

-- Returns the size of each custom tab, padded to at least count tabs.
function Verify.sizes(sections, count)
  local sizes = {}
  for s = 1, math.max(count or 0, last(sections)) do sizes[s] = #(sections[s] or {}) end
  return sizes
end

-- Returns the tab and position of an item, or nil.
local function where(sections, itemID)
  for s, ids in pairs(sections) do
    for index, id in ipairs(ids) do if id == itemID then return s, index end end
  end
  return nil
end

-- Returns a copy of sections with one planned step applied, the way the
-- game would apply it:
--   insert  the item is taken out and dropped before or after its anchor
--   swap    the two items trade places
--   to-tab / new-tab  the item goes to the end of the target tab
function Verify.apply(sections, step)
  local out = Verify.copy(sections)
  if step.kind == "insert" then
    local s, index = where(out, step.move)
    if s and s ~= step.section then table.remove(out[s], index) end
    out[step.section] = Order.apply(out[step.section] or {}, step)
  elseif step.kind == "swap" then
    local sa, ia = where(out, step.move)
    local sb, ib = where(out, step.swapWith)
    if sa and sb then out[sa][ia], out[sb][ib] = step.swapWith, step.move end
  else
    local s, index = where(out, step.id)
    if s then table.remove(out[s], index) end
    out[step.to] = out[step.to] or {}
    table.insert(out[step.to], step.id)
  end
  return out
end

-- Returns a copy of list without one item.
local function without(list, itemID)
  local out = {}
  for _, id in ipairs(list) do if id ~= itemID then out[#out + 1] = id end end
  return out
end

-- Returns the position of an item in a list, or nil.
local function indexOf(list, itemID)
  for index, id in ipairs(list) do if id == itemID then return index end end
  return nil
end

-- Returns true when an insert ended up right next to its anchor and nothing
-- else moved. This accepts a correct insert whose exact flat position
-- differs from the prediction because a tab boundary lies between them.
local function insertLanded(beforeFlat, afterFlat, step)
  local moved, anchor = indexOf(afterFlat, step.move), indexOf(afterFlat, step.before or step.after)
  return moved ~= nil and anchor ~= nil and math.abs(moved - anchor) == 1
    and listsEqual(without(beforeFlat, step.move), without(afterFlat, step.move))
end

-- Judges the player's move.
--   before     the bank (sections) when the move was asked for
--   afterFlat  the flat item order now
--   after      the bank (sections) now
--   step       the move that was asked for
--   tabsFirst  the stored tab order (see Verify.flatten)
-- Returns "done" (with the expected sections, used to fix lagging tab
-- sizes), "waiting", "changed", or "mistake" (with the expected sections).
function Verify.check(before, afterFlat, after, step, tabsFirst)
  local beforeFlat = Verify.flatten(before, tabsFirst)
  if not Verify.sameItems({ beforeFlat }, { afterFlat }) then return "changed" end
  local expected = Verify.apply(before, step)
  local expectedFlat = Verify.flatten(expected, tabsFirst)
  local unmoved = listsEqual(afterFlat, beforeFlat)
  -- The flat order matches the prediction. A tab move does not change the
  -- flat order when it is a move within the stored sequence, so a move
  -- whose flat order is unchanged only counts when the tabs changed too.
  if listsEqual(afterFlat, expectedFlat) and not (unmoved and Verify.same(after, before)) then
    return "done", expected
  end
  if unmoved then return "waiting" end
  if step.kind == "insert" and insertLanded(beforeFlat, afterFlat, step) then return "done", nil end
  return "mistake", expected
end

-- Plans the move that walks the bank back towards target (the bank as it
-- was before a wrong move), by treating target as the blueprint.
function Verify.restoreStep(current, target, mode)
  local destinations = { identity = true }
  for s = 0, last(target) do
    local entries = {}
    for index, id in ipairs(target[s] or {}) do entries[index] = { id = id } end
    destinations[s] = entries
  end
  return Guide.next(current, destinations, mode)
end

-- Returns a one-line description of a wrong move for the debug log: the
-- step that was asked for and the first place the flat order changed.
function Verify.describe(beforeFlat, afterFlat, step)
  local parts = { "step=" .. tostring(step.kind) .. ":" .. tostring(step.id or step.move) .. "->" .. tostring(step.to or step.before or step.after or step.swapWith) }
  for index = 1, math.max(#beforeFlat, #afterFlat) do
    if beforeFlat[index] ~= afterFlat[index] then
      parts[#parts + 1] = "first change at " .. index .. ": " .. tostring(beforeFlat[index]) .. " -> " .. tostring(afterFlat[index])
      break
    end
  end
  return table.concat(parts, " ")
end

return Verify
