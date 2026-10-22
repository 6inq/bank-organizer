-- Bank Organizer: the right-click "Tags (Bank Organizer)" entry on bank items.
--
-- Right-clicking a bank item adds one entry to the game's menu. Choosing it
-- opens the Tags window right next to the mouse, where the item's category,
-- tags, Ignore and Decant opt-out are set with a click. A window is used
-- instead of a hover submenu because it stays open until the player closes
-- it, so it never disappears while the mouse moves over it.

local Tags = require("src/core/tags")

local Tagging = {}

-- The id this plugin subscribes to right-click menus with.
local EVENT_ID = "bank-organizer:menu"

-- The menu entry's text.
Tagging.LABEL = "Tags (Bank Organizer)"

-- Finds the bank item a right-click menu belongs to.
--   miniMenu  the menu from Event.MiniMenuReady
-- Returns { id = real item id } when the menu was opened on a bank item
-- slot, otherwise nil. Every read is inside pcall because menu entries can
-- belong to any interface and may not have the fields read here.
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

-- Returns the choices for the kind-of-item dropdown: automatic first, then
-- every kind by name (short enough to fit the dropdown).
function Tagging.choices()
  local list = { { label = "Automatic", key = "auto" } }
  for _, tag in ipairs(Tags.LIST) do
    list[#list + 1] = { label = tag.label, key = tag.key }
  end
  return list
end

-- Adds the Tags entry to a bank item's right-click menu.
--   openTags  function(itemID) that opens the Tags window
function Tagging.addEntry(menu, itemID, openTags)
  pcall(function() return menu:Add(Tagging.LABEL, function() openTags(itemID) end) end)
end

-- Subscribes to right-click menus.
--   openTags  function(itemID) that opens the Tags window
function Tagging.start(openTags)
  Event.MiniMenuReady.Subscribe(EVENT_ID, function(event)
    local menu = event and event.miniMenu
    local item = menu and Tagging.bankItem(menu)
    if not item then return end
    Tagging.addEntry(menu, item.id, openTags)
  end)
end

-- Unsubscribes from right-click menus.
function Tagging.stop()
  pcall(function() return Event.MiniMenuReady.Unsubscribe(EVENT_ID) end)
end

return Tagging
