-- Bank Organizer: dropdown (ComboBox) options with safe entry ids.
--
-- The client's native ComboBox only accepts whole-number entry ids, but the
-- plugin's choices have text keys (like "smart" or "custom-2"). This helper
-- numbers the entries 1, 2, 3 ... and maps the picked number back to its
-- key, so every dropdown in the plugin is built the same safe way.

local Combo = {}

-- Builds the options table for view:AddComboBox.
--   choices      list of { label = text shown, key = value returned }
--   selectedKey  the key to show as chosen (the first entry if not found)
--   onPick       function(key) called when the player picks an entry
--   extra        optional table of more options copied in as they are
-- Returns the options table.
function Combo.options(choices, selectedKey, onPick, extra)
  local entries, selectedID = {}, 1
  for index, choice in ipairs(choices) do
    entries[index] = { label = choice.label, id = index, key = choice.key }
    if choice.key == selectedKey then selectedID = index end
  end
  local options = {
    entries = entries, selectedID = selectedID,
    -- Called by the ComboBox. Only real selections count: other event types
    -- (for example the list opening) are ignored when the client says what
    -- kind of event it is.
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
