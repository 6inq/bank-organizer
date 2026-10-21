local Layout = require("src/core/layout")
local Sorting = require("src/core/sorting")
local Windows = require("src/ui/windows")
local Combo = require("src/ui/combo")

local Panel = {}

local EVENT_ID = "bank-organizer:content"
local LISTENER = "panel"
local parent, view

local function choose(app, label, choices, current, onPick)
  view:AddText(label)
  view:AddComboBox(Combo.options(choices, current, function(key)
    if key ~= current and onPick(key) then app:rebuild() end
  end))
end

local function addSetup(app)
  local store = app.store
  choose(app, "Organize", { { label = app.SCOPES.bank, key = "bank" }, { label = app.SCOPES.tabs, key = "tabs" } },
    store:get("scope"), function(scope) return store:set("scope", scope) end)
  choose(app, "Sort inside tabs", Sorting.modes(app:valueSource()), store:get("sort"), function(mode) return store:set("sort", mode) end)
  choose(app, "Sort direction", { { label = "Horizontal (rows)", key = "horizontal" }, { label = "Vertical (columns)", key = "vertical" } },
    store:get("direction"), function(direction) return store:set("direction", direction) end)
  if store:get("scope") ~= "tabs" then
    choose(app, "Starting layout", { { label = Layout.PRESETS.main, key = "main" }, { label = Layout.PRESETS.ironman, key = "ironman" } },
      store.preset, function(preset) return store:setPreset(preset) end)
  end
end

local function addActions(app)
  view:AddFancyButton("Analyze Bank", function() app:analyze() end)
  view:AddFancyButton(app.guiding and "Stop Sorting" or "Start Sorting", function()
    if app.guiding then app:stopGuide() else app:startGuide() end
  end, { variant = app.guiding and "negative" or "positive" })
  view:AddSimpleButton("Open Blueprint", function() Windows.blueprint(app) end)
  view:AddSimpleButton("Tab Layout", function() Windows.layout(app) end, { inline = true })
  view:AddSimpleButton("Share or Load a Setup", function() Windows.presets(app) end)
end

local function addStatus(app)
  view:AddText({ text = app.status, height = 56 })
  local summary = app:tagSummary()
  if summary ~= "" then view:AddText({ text = "Tags: " .. summary, height = 36 }) end
  if app.store:get("direction") == "vertical" and not app.columns then
    view:AddText({ text = "Vertical sort: open your bank so its columns can be measured. Sorting by rows until then.", height = 40 })
  end
  if app.correction then
    view:AddSimpleButton("Continue from here", function() app:continueFromHere() end)
  end
  view:AddText({ text = "Right-click any bank item and choose Tags to set its category, placement or ignore it.", height = 40 })
end

local function addLegend(app)
  view:AddTitle("Your tabs")
  for _, d in ipairs(app:destinationList()) do
    local count = app.destinations and #(app.destinations[d] or {}) or nil
    local text = app:destinationLabel(d) .. (count and ("  (" .. count .. ")") or "")
    local label = view:AddText({ text = text, height = 36 })
    if label then pcall(function() label.rgba = app:destinationColour(d) end) end
  end
end

local function divider()
  pcall(function() view:AddDivider() end)
end

local function build(app)
  view:AddTitle("Bank Organizer")
  view:AddText("by 6ing")
  addSetup(app)
  divider()
  addActions(app)
  divider()
  addStatus(app)
  divider()
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
