-- Bank Organizer: the right-click "Tags (Bank Organizer)" menu on bank items.
--
-- With PrettyUI 1.2.0 or newer, the entry opens a submenu titled with the
-- item's name. Each choice toggles at once:
--   Category...                 opens a small window to pick its kind
--   Ignore                      never move this item
--   every tag (built-in first, then custom, in priority order)
--   Never label for decanting   only on potions with a dose
--   More...                     opens the full Tags window
-- Choices that are on start with "[x]", choices that are off with "[ ]"
-- (plain text, because menus have no checkboxes).
--
-- With an older PrettyUI (no MiniMenu.AddSubmenu) the entry opens the Tags
-- window directly, as in earlier versions.

local Tags = require("src/core/tags")
local Placement = require("src/core/placement")
local Classify = require("src/core/classify")

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
-- every kind with its category in brackets.
function Tagging.choices()
  local list = { { label = "Use automatic classification", key = "auto" } }
  for _, tag in ipairs(Tags.LIST) do
    local category = Tags.categoryByKey[tag.category]
    list[#list + 1] = { label = tag.label .. "  (" .. category.main .. ")", key = tag.key }
  end
  return list
end

-- Returns an item's display name, or nil when it cannot be read.
local function nameOf(itemID)
  local ok, name = pcall(function()
    local obj = config.Obj.FromID(itemID)
    return obj and obj.name
  end)
  if ok and type(name) == "string" then return name end
  return nil
end

-- Returns "[x] label" when on, "[ ] label" when off.
local function marked(on, label)
  return (on and "[x] " or "[ ] ") .. label
end

-- Builds the submenu's choices for one item.
--   app      the App
--   itemID   the item's real id
--   name     its display name (or nil)
--   openers  { tags = function(itemID), category = function(itemID) }
-- Returns a list of { label, action } in menu order.
function Tagging.children(app, itemID, name, openers)
  local store = app.store
  local list = {
    { label = "Category...", action = function() openers.category(itemID) end },
    { label = marked(store:isIgnored(itemID), "Ignore"), action = function() app:toggleIgnore(itemID) end },
  }
  for _, key in ipairs(store.tagOrder) do
    local def = Placement.byKey[key]
    if def then
      list[#list + 1] = { label = marked(store:hasTag(itemID, key), def.label), action = function() app:toggleTag(itemID, key) end }
    end
  end
  if name and Classify.dose(name) then
    list[#list + 1] = {
      label = marked(store:isNoDecant(itemID), "Never label for decanting"),
      -- Flips the Decant opt-out for this potion.
      action = function() app:setNoDecant(itemID, not store:isNoDecant(itemID)) end,
    }
  end
  list[#list + 1] = { label = "More...", action = function() openers.tags(itemID) end }
  return list
end

-- Returns PrettyUI's submenu helper when this PrettyUI version has one.
local function submenuHelper()
  local ok, helper = pcall(function()
    local menu = prettyui and prettyui.MiniMenu
    return menu and menu.AddSubmenu
  end)
  if ok and type(helper) == "function" then return helper end
  return nil
end

-- Adds the Tags entry to a bank item's right-click menu: a submenu when
-- PrettyUI supports it, otherwise one entry that opens the Tags window. If
-- adding the submenu fails for any reason, the single entry is added
-- instead so the player always has a way in.
function Tagging.addEntry(menu, app, itemID, openers)
  local helper = submenuHelper()
  if helper then
    local name = nameOf(itemID)
    local added = pcall(function()
      helper(menu, Tagging.LABEL, Tagging.children(app, itemID, name, openers), { title = name or Tagging.LABEL })
    end)
    if added then return "submenu" end
  end
  pcall(function() return menu:Add(Tagging.LABEL, function() openers.tags(itemID) end) end)
  return "entry"
end

-- Subscribes to right-click menus.
--   app      the App
--   openers  { tags = function(itemID), category = function(itemID) }
function Tagging.start(app, openers)
  Event.MiniMenuReady.Subscribe(EVENT_ID, function(event)
    local menu = event and event.miniMenu
    local item = menu and Tagging.bankItem(menu)
    if not item then return end
    Tagging.addEntry(menu, app, item.id, openers)
  end)
end

-- Unsubscribes from right-click menus.
function Tagging.stop()
  pcall(function() return Event.MiniMenuReady.Unsubscribe(EVENT_ID) end)
end

return Tagging
