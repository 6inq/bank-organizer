local Tags = require("src/core/tags")

local Tagging = {}

local EVENT_ID = "bank-organizer:menu"
Tagging.LABEL = "Assign category (Bank Organizer)"
Tagging.IGNORE = "Ignore (Bank Organizer)"
Tagging.UNIGNORE = "Stop ignoring (Bank Organizer)"

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

function Tagging.choices()
  local list = { { label = "Use automatic classification", key = "auto" } }
  for _, tag in ipairs(Tags.LIST) do
    local category = Tags.categoryByKey[tag.category]
    list[#list + 1] = { label = tag.label .. "  (" .. category.main .. ")", key = tag.key }
  end
  return list
end

function Tagging.start(app, openPicker)
  Event.MiniMenuReady.Subscribe(EVENT_ID, function(event)
    local menu = event and event.miniMenu
    local item = menu and Tagging.bankItem(menu)
    if not item then return end
    local label = app:isIgnored(item.id) and Tagging.UNIGNORE or Tagging.IGNORE
    pcall(function() return menu:Add(label, function() app:toggleIgnore(item.id) end) end)
    if app.assigning then
      pcall(function() return menu:Add(Tagging.LABEL, function() openPicker(item.id) end) end)
    end
  end)
end

function Tagging.stop()
  pcall(function() return Event.MiniMenuReady.Unsubscribe(EVENT_ID) end)
end

return Tagging
