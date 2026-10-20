-- Assign Categories: while it is on, right-clicking a bank item offers
-- "Assign category (Bank Organizer)", which opens a small picker for that item.
-- Uses the game's own MiniMenu:Add, so it works with any PrettyUI version. It only records
-- your choice locally; it performs no bank action.
local Tags = require("src/core/tags")

local Tagging = {}

local EVENT_ID = "bank-organizer:menu"
Tagging.LABEL = "Assign category (Bank Organizer)"

-- The bank item the menu was opened on: id and name, or nil.
function Tagging.bankItem(miniMenu)
  local ok, found = pcall(function()
    local bankInterface = id.Interface.BANK
    for _, entry in ipairs(miniMenu.entries) do
      local data = entry.componentData
      local component = data and data.component
      if component and component.interfaceID == bankInterface
        and component.associatedObjectID and component.associatedObjectID >= 0 then
        return { id = component.associatedObjectID }
      end
    end
    return nil
  end)
  if ok then return found end
  return nil
end

-- Entries for the picker: automatic first, then every tag grouped by category.
function Tagging.choices()
  local list = { { label = "Use automatic classification", key = "auto" } }
  for _, tag in ipairs(Tags.LIST) do
    local category = Tags.categoryByKey[tag.category]
    list[#list + 1] = { label = tag.label .. "  (" .. category.main .. ")", key = tag.key }
  end
  return list
end

---@param app table App (assigning flag, store, rebuild)
---@param openPicker fun(itemID: integer) shows the picker window
function Tagging.start(app, openPicker)
  Event.MiniMenuReady.Subscribe(EVENT_ID, function(event)
    if not app.assigning then return end
    local menu = event and event.miniMenu
    local item = menu and Tagging.bankItem(menu)
    if not item then return end
    pcall(menu.Add, menu, Tagging.LABEL, function() openPicker(item.id) end)
  end)
end

function Tagging.stop()
  pcall(Event.MiniMenuReady.Unsubscribe, EVENT_ID)
end

return Tagging
