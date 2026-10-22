-- Bank Organizer tests: the small assertion library every test uses.
--
-- Each check raises an error with a readable message when it fails; the
-- runner (tests/run.py) catches the error and reports the test as failed.
-- The error level 2 points the message at the test's own line.

local A = {}

-- Turns a value into text for messages. Lists are shown as {a,b,c}.
local function show(value)
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  for index, item in ipairs(value) do parts[index] = tostring(item) end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- Fails unless actual == expected.
function A.eq(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

-- Fails unless the two lists hold the same values in the same order.
function A.list(actual, expected, message)
  local same = #actual == #expected
  for index = 1, #expected do
    if actual[index] ~= expected[index] then same = false end
  end
  if not same then
    error((message or "lists differ") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

-- Fails when value is nil or false.
function A.truthy(value, message)
  if not value then error(message or "expected truthy value", 2) end
end

return A
