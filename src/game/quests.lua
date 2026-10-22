-- Bank Organizer: reads whether an item's quests are finished.
--
-- The Bank Cleaner keeps items needed for quests the player has not
-- finished. The client lists the quests related to an item in
-- config.Obj.FromID(id).quests, and each quest config can say whether the
-- player has finished it (hasFinishedQuest). As a backup, a quest's progress
-- variable is compared with its completion value (masterQuestVars).
--
-- Every client read is wrapped in pcall(function() ... end): native client
-- functions must never be passed straight to pcall, which crashes the
-- client. When anything cannot be read the answer is "unknown", and the
-- cleaner then keeps the item.

local Quests = {}

-- Returns true, false or nil (unreadable) for "the player finished quest".
--   quest  a QuestType config from obj.quests
local function finished(quest)
  local ok, done = pcall(function() return quest.hasFinishedQuest end)
  if ok and type(done) == "boolean" then return done end
  -- Backup: compare the quest's progress variable with its end value.
  local okVar, value, endState = pcall(function()
    local master = quest.masterQuestVars[1]
    return master.varPlayer.value, master.endState
  end)
  if okVar and type(value) == "number" and type(endState) == "number" then return value >= endState end
  return nil
end

-- Returns the list of quests related to an item, or nil when unreadable.
local function questsOf(objectId)
  local ok, list = pcall(function()
    local obj = config.Obj.FromID(objectId)
    if not obj then return nil end
    -- obj.quests is a client list; copy it into a plain Lua table.
    local out = {}
    for _, quest in ipairs(obj.quests or {}) do out[#out + 1] = quest end
    return out
  end)
  if ok then return list end
  return nil
end

-- Returns the quest state of an item:
--   "none"     the item is not related to any quest
--   "done"     every related quest is finished
--   "open"     at least one related quest is not finished
--   "unknown"  the quests could not be read
function Quests.state(objectId)
  local list = questsOf(objectId)
  if list == nil then return "unknown" end
  if #list == 0 then return "none" end
  local unknown = false
  for _, quest in ipairs(list) do
    local done = finished(quest)
    if done == false then return "open" end
    if done == nil then unknown = true end
  end
  return unknown and "unknown" or "done"
end

return Quests
