-- Floating windows: Blueprint, Tab Layout editor and the category picker (PrettyUI Window).
local Tags = require("src/core/tags")
local Tagging = require("src/game/tagging")

local Windows = {}

local open = {} -- name -> PrettyUI window

local function host()
  local ok, layer = pcall(function()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
  end)
  if ok then return layer end
  return nil
end

function Windows.close(name)
  local window = open[name]
  open[name] = nil
  if window then pcall(window.Destroy, window) end
end

function Windows.closeAll()
  for name in pairs(open) do Windows.close(name) end
end

function Windows.isOpen(name)
  return open[name] ~= nil
end

local function create(name, options, build)
  Windows.close(name)
  local layer = host()
  if not layer then return nil end
  options.onClose = function() open[name] = nil end
  options.destroyOnClose = true
  local window = prettyui.Window.new(layer, options)
  open[name] = window
  local ok, err = pcall(build, window)
  if not ok and log then log("[bank-organizer] " .. name .. " window failed: " .. tostring(err)) end
  return window
end

local function objectOf(itemID)
  local ok, obj = pcall(function() return config.Obj.FromID(itemID) end)
  if ok then return obj end
  return nil
end

local GRID_COLUMNS = 8

-- Blueprint: Main then Tabs 1-9, each with the items planned for it (empty ones skipped).
function Windows.blueprint(app)
  return create("blueprint", { title = "Blueprint", width = 470, height = 560, x = 60, y = 60 }, function(window)
    if not app.destinations then
      window:AddText("Press Analyze Bank first.")
      return
    end
    for d = 0, Tags.DESTINATIONS - 1 do
      local entries = app.destinations[d]
      if #entries > 0 then
        window:AddTitle(app:destinationLabel(d))
        local objects = {}
        for index, entry in ipairs(entries) do
          objects[index] = { object = objectOf(entry.id), quantity = entry.quantity, tooltip = entry.name .. " (" .. Tags.label(entry.tag) .. ")" }
        end
        window:AddItemGrid(objects, { columns = GRID_COLUMNS, rows = math.max(1, math.ceil(#objects / GRID_COLUMNS)) })
      end
    end
  end)
end

local function tagChoicesFor(layout, d)
  local list = {}
  for _, tag in ipairs(Tags.LIST) do
    local current = layout:destinationOf(tag.key)
    if current ~= d then
      list[#list + 1] = { label = tag.label .. "  (" .. Tags.destinationName(current) .. ")", id = tag.key }
    end
  end
  return list
end

-- Tab Layout: what sits on Main and Tabs 1-9; changes save and rebuild immediately.
function Windows.layout(app)
  local function changed()
    app.store:save()
    app:rebuild()
    Windows.layout(app)
  end
  return create("layout", { title = "Tab Layout", width = 470, height = 600, x = 120, y = 60 }, function(window)
    local layout = app.store.layout
    window:AddText({ text = "Choose what goes on each tab. Arrows set the order; the remove button sends a tag to Storage & Cleanup.", height = 48 })
    for d = 0, Tags.DESTINATIONS - 1 do
      window:AddTitle(Tags.destinationName(d))
      for _, key in ipairs(layout.destinations[d]) do
        window:AddText(Tags.label(key))
        window:AddSimpleButton("Up", function() if layout:shiftTag(key, -1) then changed() end end, { inline = true })
        window:AddSimpleButton("Down", function() if layout:shiftTag(key, 1) then changed() end end, { inline = true })
        window:AddSimpleButton("Remove", function() if layout:removeTag(key) then changed() end end, { inline = true })
      end
      window:AddComboBox({
        entries = { { label = "Add a tag here...", id = "none" }, table.unpack(tagChoicesFor(layout, d)) },
        selectedID = "none",
        onChange = function(_, entryID, _, eventType)
          if eventType ~= nil and eventType ~= ui.SelectionChangeEvent.SELECTED then return end
          if entryID and entryID ~= "none" and layout:moveTag(entryID, d) then changed() end
        end,
      })
    end
    window:AddSimpleButton("Reset to default", function() layout:reset(); changed() end)
  end)
end

-- Category picker for one item, opened from the right-click option.
function Windows.picker(app, itemID)
  local name = "item " .. tostring(itemID)
  local obj = objectOf(itemID)
  if obj and obj.name then name = obj.name end
  return create("picker", { title = "Assign category", width = 360, height = 220, x = 200, y = 160 }, function(window)
    local current = app.store.corrections[itemID]
    window:AddText({ text = name .. (current and ("  (now: " .. Tags.label(current) .. ")") or "  (automatic)"), height = 40 })
    window:AddComboBox({
      entries = Tagging.choices(), selectedID = current or "auto",
      onChange = function(_, entryID, _, eventType)
        if eventType ~= nil and eventType ~= ui.SelectionChangeEvent.SELECTED then return end
        if entryID == "auto" then app.store:clearCorrection(itemID) else app.store:correct(itemID, entryID) end
        app:rebuild()
        Windows.close("picker")
      end,
    })
  end)
end

return Windows
