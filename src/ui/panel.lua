-- Sidebar (ribbon panel), laid out like Bank Architect's: preset chooser, then
-- Analyze Bank, Open Blueprint, Sorting Guide, Assign Categories, Tab Layout, and the legend.
local Tags = require("src/core/tags")
local Layout = require("src/core/layout")
local Windows = require("src/ui/windows")
local Combo = require("src/ui/combo")

local Panel = {}

local EVENT_ID = "bank-organizer:content"
local LISTENER = "panel"
local parent, view

local function addPreset(app)
  view:AddComboBox(Combo.options(
    { { label = Layout.PRESETS.main, key = "main" }, { label = Layout.PRESETS.ironman, key = "ironman" } },
    app.store.preset,
    function(preset)
      if preset ~= app.store.preset and app.store:setPreset(preset) then app:rebuild() end
    end))
end

local function addScope(app)
  view:AddText("Organize")
  view:AddComboBox(Combo.options(
    { { label = app.SCOPES.bank, key = "bank" }, { label = app.SCOPES.tabs, key = "tabs" } },
    app.store:get("scope"),
    function(scope)
      if scope ~= app.store:get("scope") and app.store:set("scope", scope) then app:rebuild() end
    end))
end

local function addActions(app)
  view:AddFancyButton("Analyze Bank", function() app:analyze() end)
  view:AddSimpleButton("Open Blueprint", function() Windows.blueprint(app) end)
  view:AddSimpleButton(app.guiding and "Stop Sorting Guide" or "Sorting Guide", function()
    if app.guiding then app:stopGuide() else app:startGuide() end
  end)
  view:AddSimpleButton(app.assigning and "Stop Assigning" or "Assign Categories", function()
    app:setAssigning(not app.assigning)
  end)
  if app.store:get("scope") ~= "tabs" then
    view:AddSimpleButton("Tab Layout", function() Windows.layout(app) end)
  end
end

local function addLegend(app)
  view:AddTitle("Legend")
  for _, d in ipairs(app:destinationList()) do
    local count = app.destinations and #(app.destinations[d] or {}) or 0
    local label = view:AddText({ text = app:destinationLabel(d) .. (app.destinations and ("  [" .. count .. "]") or ""), height = 36 })
    if label then pcall(function() label.rgba = app:destinationColour(d) end) end
  end
end

local function build(app)
  view:AddTitle("Bank Organizer")
  view:AddText("by 6ing")
  addScope(app)
  if app.store:get("scope") ~= "tabs" then addPreset(app) end
  addActions(app)
  view:AddText({ text = app.status, height = 56 })
  if app.assigning then
    view:AddText({ text = "Right-click any bank item and choose Assign category to correct it.", height = 40 })
  end
  addLegend(app)
end

local function render(app)
  if not parent then return end
  if view then pcall(function() return view:Destroy() end) end
  view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
  local ok, err = pcall(build, app)
  if not ok and log then log("[bank-organizer] panel failed: " .. tostring(err)) end
end

function Panel.start(app)
  Event.ContentLayerReady.Subscribe(EVENT_ID, function(event)
    parent = event.component
    app:onChange(LISTENER, function() render(app) end)
  end)
end

function Panel.stop(app)
  pcall(function() return Event.ContentLayerReady.Unsubscribe(EVENT_ID) end)
  if app then app:onChange(LISTENER, nil) end
  if view then pcall(function() return view:Destroy() end) end
  view, parent = nil, nil
end

return Panel
