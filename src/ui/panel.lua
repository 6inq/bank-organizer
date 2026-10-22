-- Bank Organizer: the sidebar panel.
--
-- Top to bottom:
--   Header       title, version and creator
--   Status card  the next step, moves left, sorted tabs, tag counts, and the
--                buttons that only make sense right now (Continue from here,
--                Run the Bank Cleaner)
--   Main buttons Analyze Bank, Start / Stop Sorting, Open Blueprint, Tab Layout
--   Organize     (collapsible) how the bank is organized and sorted
--   Your tabs    (collapsible) one row per tab: first item icon, name in the
--                tab's colour, what it holds and how many items
--   Tools        (collapsible) every other window
--   Footer hint  how to reach the right-click Tags menu
--
-- The panel is redrawn from scratch whenever the App notifies a change.

local Layout = require("src/core/layout")
local Sorting = require("src/core/sorting")
local Windows = require("src/ui/windows")
local Settings = require("src/ui/settings")
local Combo = require("src/ui/combo")
local Widgets = require("src/ui/widgets")

local Panel = {}

-- The id this plugin subscribes to the content layer with, and its
-- listener name on the App.
local EVENT_ID = "bank-organizer:content"
local LISTENER = "panel"

-- The content layer component and the current SimpleView inside it.
local parent, view

-- Collapsed sections of the sidebar: key -> true.
local collapsed = {}

-- Adds a labelled dropdown that saves the choice and rebuilds the plan.
--   onPick  function(key) -> true when the value was saved
local function choose(app, label, hint, choices, current, onPick)
  Widgets.setting(view, label, hint, function()
    view:AddComboBox(Combo.options(choices, current, function(key)
      if key ~= current and onPick(key) then app:rebuild() end
    end))
  end, parent and parent.width)
end

-- The Organize section: organize mode, sort mode, direction and (Whole bank
-- only) the starting layout.
local function addSetup(app)
  local store = app.store
  choose(app, "Organize", "My tabs keeps your tabs. Whole bank follows your Tab Layout.",
    { { label = app.SCOPES.bank, key = "bank" }, { label = app.SCOPES.tabs, key = "tabs" } },
    store:get("scope"), function(scope) return store:set("scope", scope) end)
  choose(app, "Sort inside tabs", "Smart gives every kind of item its own sensible order.",
    Sorting.modes(app:valueSource()), store:get("sort"), function(mode) return store:set("sort", mode) end)
  choose(app, "Sort direction", "Rows fill left to right; columns fill top to bottom.",
    { { label = "Horizontal (rows)", key = "horizontal" }, { label = "Vertical (columns)", key = "vertical" } },
    store:get("direction"), function(direction) return store:set("direction", direction) end)
  if store:get("scope") ~= "tabs" then
    choose(app, "Starting layout", "Changing it resets your Tab Layout.",
      { { label = Layout.PRESETS.main, key = "main" }, { label = Layout.PRESETS.ironman, key = "ironman" } },
      store.preset, function(preset) return store:setPreset(preset) end)
  end
end

-- The main buttons. Start Sorting is green and turns into a red Stop
-- Sorting while the guide runs.
local function addActions(app)
  view:AddFancyButton("Analyze Bank", function() app:analyze() end, { variant = "neutral" })
  view:AddFancyButton(app.guiding and "Stop Sorting" or "Start Sorting", function()
    if app.guiding then app:stopGuide() else app:startGuide() end
  end, { variant = app.guiding and "negative" or "positive" })
  view:AddSimpleButton("Open Blueprint", function() Windows.blueprint(app) end)
  view:AddSimpleButton("Tab Layout", function() Windows.layout(app) end, { inline = true })
end

-- The status card: what to do next and how far along the player is.
local function addStatus(app)
  view:AddText({ text = app.status, height = Widgets.heightFor(app.status, parent and parent.width) })
  if app.guiding and app.remaining then Widgets.muted(view, "Moves left: " .. app.remaining) end
  local done, total = app:sortedCount()
  if done then Widgets.muted(view, "Sorted tabs " .. done .. " / " .. total) end
  local summary = app:tagSummary()
  if summary ~= "" then view:AddText({ text = "Tags: " .. summary, height = Widgets.heightFor("Tags: " .. summary) }) end
  if app.store:get("direction") == "vertical" and not app.columns then
    view:AddText({ text = "Vertical sort: open your bank so its columns can be measured. Sorting by rows until then.", height = 40 })
  end
  if app.correction then
    view:AddSimpleButton("Continue from here", function() app:continueFromHere() end)
  end
  if app:isDone() then
    view:AddSimpleButton("Run the Bank Cleaner", function() Windows.cleaner(app) end)
  end
end

-- Returns the client item config for an id, or nil.
local function objectOf(itemID)
  local ok, obj = pcall(function() return config.Obj.FromID(itemID) end)
  if ok then return obj end
  return nil
end

-- The Your tabs section: one row per tab.
local function addLegend(app)
  for _, d in ipairs(app:destinationList()) do
    local entries = app.destinations and app.destinations[d]
    local first = entries and entries[1]
    -- The tab's first planned item as its icon, like a bank tab button.
    if first then
      view:AddItemGrid({ { object = objectOf(first.objectId or first.id), quantity = first.quantity, tooltip = first.name } },
        { columns = 1, rows = 1 })
    end
    local text = app:destinationLabel(d) .. (entries and ("  (" .. #entries .. ")") or "")
    Widgets.coloured(view, text, app:destinationColour(d), parent and parent.width)
  end
end

-- The Tools section: every window that is not part of the main flow.
local function addTools(app)
  view:AddSimpleButton("Share or Load a Setup", function() Windows.presets(app) end)
  view:AddSimpleButton("Bank Cleaner", function() Windows.cleaner(app) end)
  view:AddSimpleButton("Custom tags", function() Windows.customTags(app) end, { inline = true })
  view:AddSimpleButton("Custom categories", function() Windows.categories(app) end)
  view:AddSimpleButton("Settings", function() Settings.openWindow(app) end, { inline = true })
end

-- Draws the whole panel.
local function build(app)
  -- Redraws the panel after a section is opened or closed.
  local refresh = function() Panel.render(app) end
  view:AddTitle("Bank Organizer")
  Widgets.muted(view, "v" .. app.VERSION .. " | by 6ing")
  addStatus(app)
  Widgets.divider(view)
  addActions(app)
  Widgets.divider(view)
  Widgets.section(view, collapsed, "organize", "Organize", refresh, function() addSetup(app) end)
  Widgets.section(view, collapsed, "tabs", "Your tabs", refresh, function() addLegend(app) end)
  Widgets.section(view, collapsed, "tools", "Tools", refresh, function() addTools(app) end)
  Widgets.divider(view)
  Widgets.muted(view, "Right-click any bank item: Tags (Bank Organizer) sets its category and tags, or ignores it.")
end

-- Replaces the panel's view with a freshly built one. A failing build is
-- logged and leaves whatever was drawn so far.
function Panel.render(app)
  if not parent then return end
  if view then pcall(function() return view:Destroy() end) end
  view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
  local ok, err = pcall(build, app)
  if not ok and log then log("[bank-organizer] panel failed: " .. tostring(err)) end
end

-- Subscribes to the sidebar content layer and redraws on every App change.
function Panel.start(app)
  Event.ContentLayerReady.Subscribe(EVENT_ID, function(event)
    parent = event.component
    app:onChange(LISTENER, function() Panel.render(app) end)
  end)
end

-- Unsubscribes and removes the panel.
function Panel.stop(app)
  pcall(function() return Event.ContentLayerReady.Unsubscribe(EVENT_ID) end)
  if app then app:onChange(LISTENER, nil) end
  if view then pcall(function() return view:Destroy() end) end
  view, parent = nil, nil
end

return Panel
