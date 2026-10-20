local Guide = require("src/core/guide")
local Order = require("src/core/order")

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

local function countIds(lists)
  local count = {}
  for _, ids in pairs(lists) do for _, id in ipairs(ids) do count[id] = (count[id] or 0) + 1 end end
  return count
end

function Verify.sameItems(a, b)
  local left, right = countIds(a), countIds(b)
  for id, n in pairs(left) do if right[id] ~= n then return false end end
  for id, n in pairs(right) do if left[id] ~= n then return false end end
  return true
end

function Verify.flatten(sections, tabsFirst)
  local order = {}
  if tabsFirst ~= false then
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

function Verify.sizes(sections, count)
  local sizes = {}
  for s = 1, math.max(count or 0, last(sections)) do sizes[s] = #(sections[s] or {}) end
  return sizes
end

local function where(sections, itemID)
  for s, ids in pairs(sections) do
    for index, id in ipairs(ids) do if id == itemID then return s, index end end
  end
  return nil
end

function Verify.apply(sections, step)
  local out = Verify.copy(sections)
  if step.kind == "insert" then
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

local function without(list, itemID)
  local out = {}
  for _, id in ipairs(list) do if id ~= itemID then out[#out + 1] = id end end
  return out
end

local function indexOf(list, itemID)
  for index, id in ipairs(list) do if id == itemID then return index end end
  return nil
end

local function insertLanded(beforeFlat, afterFlat, step)
  local moved, anchor = indexOf(afterFlat, step.move), indexOf(afterFlat, step.before or step.after)
  return moved ~= nil and anchor ~= nil and math.abs(moved - anchor) == 1
    and listsEqual(without(beforeFlat, step.move), without(afterFlat, step.move))
end

function Verify.check(before, afterFlat, after, step, tabsFirst)
  local beforeFlat = Verify.flatten(before, tabsFirst)
  if not Verify.sameItems({ beforeFlat }, { afterFlat }) then return "changed" end
  local expected = Verify.apply(before, step)
  local expectedFlat = Verify.flatten(expected, tabsFirst)
  local unmoved = listsEqual(afterFlat, beforeFlat)
  if listsEqual(afterFlat, expectedFlat) and not (unmoved and Verify.same(after, before)) then
    return "done", expected
  end
  if unmoved then return "waiting" end
  if step.kind == "insert" and insertLanded(beforeFlat, afterFlat, step) then return "done", nil end
  return "mistake", expected
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
