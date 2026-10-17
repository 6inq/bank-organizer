-- Minimal assertion helpers for the test suites.
local A = {}

local function show(value)
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  for index, item in ipairs(value) do parts[index] = tostring(item) end
  return "{" .. table.concat(parts, ",") .. "}"
end

function A.eq(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function A.list(actual, expected, message)
  local same = #actual == #expected
  for index = 1, #expected do
    if actual[index] ~= expected[index] then same = false end
  end
  if not same then
    error((message or "lists differ") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function A.truthy(value, message)
  if not value then error(message or "expected truthy value", 2) end
end

return A
