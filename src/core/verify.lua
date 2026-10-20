local Guide = require("src/core/guide")

local Verify = {}

function Verify.copy(sections)
  local out = {}
  for s, ids in pairs(sections) do
    local list = {}
    for index, id in ipairs(ids) do list[index] = id end
    out[s] = list
  end
  return out
end

local function last(sections)
  local high = 0
  for s in pairs(sections) do if s > high then high = s end end
  return high
end

local function locate(sections)
  local where = {}
  for s, ids in pairs(sections) do
    for index, id in ipairs(ids) do where[id] = { section = s, index = index } end
  end
  return where
end

local function listsEqual(a, b)
  if #a ~= #b then return false end
  for index = 1, #a do if a[index] ~= b[index] then return false end end
  return true
end

function Verify.same(a, b)
  for s = 0, math.max(last(a), last(b)) do
    if not listsEqual(a[s] or {}, b[s] or {}) then return false end
  end
  return true
end

function Verify.sameItems(a, b)
  local count = {}
  for _, ids in pairs(a) do for _, id in ipairs(ids) do count[id] = (count[id] or 0) + 1 end end
  for _, ids in pairs(b) do for _, id in ipairs(ids) do count[id] = (count[id] or 0) - 1 end end
  for _, value in pairs(count) do if value ~= 0 then return false end end
  return true
end

local function without(sections, itemID)
  local out = {}
  for s, ids in pairs(sections) do
    local list = {}
    for _, id in ipairs(ids) do if id ~= itemID then list[#list + 1] = id end end
    if #list > 0 then out[s] = list end
  end
  return out
end

local function othersUnchanged(before, after, itemID)
  return Verify.same(without(before, itemID), without(after, itemID))
end

local function insertDone(before, after, step)
  local where = locate(after)
  local moved, anchor = where[step.move], where[step.before or step.after]
  if not moved or not anchor or moved.section ~= step.section or anchor.section ~= step.section then return false end
  return math.abs(moved.index - anchor.index) == 1 and othersUnchanged(before, after, step.move)
end

local function swapDone(before, after, step)
  local expected = Verify.copy(before)
  local where = locate(expected)
  local a, b = where[step.move], where[step.swapWith]
  if not a or not b then return false end
  expected[a.section][a.index], expected[b.section][b.index] = step.swapWith, step.move
  return Verify.same(expected, after)
end

local function tabDone(before, after, step)
  local moved = locate(after)[step.id]
  return moved ~= nil and moved.section == step.to and othersUnchanged(before, after, step.id)
end

function Verify.check(before, after, step)
  if not Verify.sameItems(before, after) then return "changed" end
  if Verify.same(before, after) then return "waiting" end
  local done
  if step.kind == "insert" then
    done = insertDone(before, after, step)
  elseif step.kind == "swap" then
    done = swapDone(before, after, step)
  else
    done = tabDone(before, after, step)
  end
  return done and "done" or "mistake"
end

function Verify.restoreStep(current, target, mode)
  local destinations = { identity = true }
  for s = 0, last(target) do
    local entries = {}
    for index, id in ipairs(target[s] or {}) do entries[index] = { id = id } end
    destinations[s] = entries
  end
  return Guide.next(current, destinations, mode)
end

return Verify
