-- Adds a "Bank Organizer >" submenu to right-click menus on bank items.
local Categories = require("src/core/categories")

local Tagging = {}

local EVENT_ID = "bank-organizer:menu"
local SUBMENU_LABEL = "Bank Organizer"

-- Returns the object id of the bank item the menu was opened on, if any.
local function bankObjectID(miniMenu)
  local ok, found = pcall(function()
    local bankInterface = id.Interface.BANK
    for _, entry in ipairs(miniMenu.entries) do
      local data = entry.componentData
      local component = data and data.component
      if component and component.interfaceID == bankInterface
        and component.associatedObjectID and component.associatedObjectID >= 0 then
        return component.associatedObjectID
      end
    end
    return nil
  end)
  if ok then return found end
  return nil
end

local function buildChildren(objectID, store, onChange)
  local children = {}
  for _, category in ipairs(Categories.list) do
    children[#children + 1] = {
      label = "Set: " .. category.label,
      action = function() store:setTag(objectID, category.key); onChange() end,
    }
  end
  if store:getTag(objectID) then
    children[#children + 1] = {
      label = "Clear tag",
      action = function() store:clearTag(objectID); onChange() end,
    }
  end
  return children
end

---@param store table Store instance
---@param onChange fun() called after a tag changes
---@param isLocked fun(): boolean tags cannot change while organizing
function Tagging.start(store, onChange, isLocked)
  Event.MiniMenuReady.Subscribe(EVENT_ID, function(event)
    if not store:get("tagging") or (isLocked and isLocked()) then return end
    local miniMenu = event and event.miniMenu
    if miniMenu == nil then return end
    local objectID = bankObjectID(miniMenu)
    if objectID == nil then return end
    local ok, err = pcall(prettyui.MiniMenu.AddSubmenu, miniMenu, SUBMENU_LABEL,
      buildChildren(objectID, store, onChange))
    if not ok and log then log("[bank-organizer] submenu failed: " .. tostring(err)) end
  end)
end

function Tagging.stop()
  Event.MiniMenuReady.Unsubscribe(EVENT_ID)
end

return Tagging
