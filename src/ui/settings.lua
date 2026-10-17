-- Settings panel: every option lives here and is locked while organizing.
local Categories = require("src/core/categories")

local Settings = {}

local EVENT_ID = "bank-organizer:settings"
local LISTENER = "settings"
local LOCKED_TEXT = "Settings are locked while organizing. Click Stop Organizing to make changes."
local view
local controls = {}

local function track(control)
  controls[#controls + 1] = control
  return control
end

local function onSelected(handler)
  return function(_, entryID, _, eventType)
    if eventType ~= nil and eventType ~= ui.SelectionChangeEvent.SELECTED then return end
    if entryID ~= nil then handler(entryID) end
  end
end

local function filterEntries()
  local entries = { { label = "All categories", id = "all" } }
  for _, category in ipairs(Categories.list) do
    entries[#entries + 1] = { label = category.label, id = category.key }
  end
  return entries
end

local function addOrganizing(target, store, app)
  target:AddTitle("Organizing")
  target:AddText("Order items within each category by:")
  track(target:AddComboBox({
    entries = { { label = "Item ID", id = "id" }, { label = "Name", id = "name" } },
    selectedID = store:get("sortMode"),
    onChange = onSelected(function(entryID) store:set("sortMode", entryID); app:invalidate() end),
  }))
end

local function addOverlays(target, store, app)
  target:AddTitle("Overlays")
  track(target:AddCheckboxButton({
    { text = "Show category colours", value = "overlays", selected = store:get("overlays") },
    { text = "Highlight untagged items", value = "highlightUntagged", selected = store:get("highlightUntagged") },
  }, {
    onChange = function(_, _, changed, selected) store:set(changed, selected); app:invalidate() end,
  }))
  target:AddText("Show only this category:")
  track(target:AddComboBox({
    entries = filterEntries(), selectedID = store:get("filter"),
    onChange = onSelected(function(entryID) store:set("filter", entryID); app:invalidate() end),
  }))
  target:AddText("Overlay opacity")
  track(target:AddSlider({
    min = 0, max = 100, step = 5, value = math.floor(store:get("opacity") * 100 + 0.5),
    onChange = function(_, value) store:set("opacity", value / 100); app:invalidate() end,
  }))
end

local function addTagging(target, parent, store, app)
  target:AddTitle("Categories")
  track(target:AddCheckboxButton({
    { text = "Tag items via right-click", value = "tagging", selected = store:get("tagging") },
  }, {
    onChange = function(_, _, changed, selected) store:set(changed, selected) end,
  }))
  for _, category in ipairs(Categories.list) do
    target:AddText(category.label .. " colour")
    track(target:AddColourPicker({
      value = store:colour(category.key),
      onChange = function(_, colour) store:setColour(category.key, colour); app:invalidate() end,
    }))
  end
  track(target:AddSimpleButton("Reset all tags", function()
    prettyui.Confirm.new(parent, {
      title = "RESET TAGS",
      body = "Remove every category tag you have set? Automatic categories stay.",
      confirmLabel = "RESET",
      onConfirm = function() store:clearAllTags(); app:invalidate() end,
    })
  end))
end

local function applyLock(state, lockLabel)
  for _, control in ipairs(controls) do pcall(control.SetDisabled, control, state.organizing) end
  if lockLabel then pcall(function() lockLabel.content = state.organizing and LOCKED_TEXT or "" end) end
end

local function mount(parent, store, app)
  Settings.destroy(app)
  view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
  local lockLabel = view:AddText({ text = "", height = 48 })
  addOrganizing(view, store, app)
  addOverlays(view, store, app)
  addTagging(view, parent, store, app)
  app:onChange(LISTENER, function(state) applyLock(state, lockLabel) end)
end

function Settings.start(store, app)
  Event.SettingsLayerReady.Subscribe(EVENT_ID, function(event)
    local ok, err = pcall(mount, event.component, store, app)
    if not ok and log then log("[bank-organizer] settings failed: " .. tostring(err)) end
  end)
end

function Settings.destroy(app)
  if app then app:onChange(LISTENER, nil) end
  if view then pcall(view.Destroy, view) end
  view, controls = nil, {}
end

function Settings.stop(app)
  pcall(Event.SettingsLayerReady.Unsubscribe, EVENT_ID)
  Settings.destroy(app)
end

return Settings
