-- The game's combo box only accepts integer entry ids, so dropdowns use positions (1, 2, 3...)
-- and map the chosen position back to our own key.
local Combo = {}

---@param choices table[] { { label = string, key = any }, ... }
---@param selectedKey any key to show as selected (falls back to the first entry)
---@param onPick fun(key: any) called with the chosen entry's key
---@param extra table? additional ComboBox options (width, inline, ...)
function Combo.options(choices, selectedKey, onPick, extra)
  local entries, selectedID = {}, 1
  for index, choice in ipairs(choices) do
    entries[index] = { label = choice.label, id = index, key = choice.key }
    if choice.key == selectedKey then selectedID = index end
  end
  local options = {
    entries = entries, selectedID = selectedID,
    onChange = function(_, entryID, _, eventType)
      if eventType ~= nil and ui and ui.SelectionChangeEvent and eventType ~= ui.SelectionChangeEvent.SELECTED then return end
      local choice = choices[tonumber(entryID)]
      if choice then onPick(choice.key) end
    end,
  }
  for k, v in pairs(extra or {}) do options[k] = v end
  return options
end

return Combo
