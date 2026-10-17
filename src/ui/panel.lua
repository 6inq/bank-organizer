-- Ribbon panel: how-to steps, the Start/Stop Organizing button and live status.
local Panel = {}

local EVENT_ID = "bank-organizer:content"
local LISTENER = "panel"
local view

Panel.START_LABEL = "Start Organizing"
Panel.STOP_LABEL = "Stop Organizing"
Panel.STEPS = {
  "1. Open your bank.",
  "2. Enable the plugin.",
  "3. Go through the settings (gear icon) and set everything how you want it.",
  "4. Click Start Organizing.",
}

local function setContent(label, text)
  if label then pcall(function() label.content = text end) end
end

local function addSteps(target)
  target:AddTitle("How to use")
  for _, step in ipairs(Panel.STEPS) do target:AddText({ text = step, height = 40 }) end
  target:AddText({ text = "To change settings, click Stop Organizing first.", height = 40 })
end

local function addControls(target, app)
  local toggle = target:AddFancyButton(Panel.START_LABEL, function() app:toggleOrganizing() end)
  local skip = target:AddSimpleButton("Skip item", function() app:skipCurrent() end)
  local status = target:AddText({ text = app.status, height = 48 })
  local hint = target:AddText({ text = app.hint, height = 48 })
  app:onChange(LISTENER, function(state)
    pcall(toggle.SetText, toggle, state.organizing and Panel.STOP_LABEL or Panel.START_LABEL)
    pcall(skip.SetDisabled, skip, not state.organizing)
    setContent(status, state.status)
    setContent(hint, state.hint)
  end)
end

local function mount(parent, app)
  Panel.destroy(app)
  view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
  view:AddTitle("Bank Organizer")
  view:AddText("by 6ing")
  addSteps(view)
  view:AddDivider()
  addControls(view, app)
end

function Panel.start(app)
  Event.ContentLayerReady.Subscribe(EVENT_ID, function(event)
    local ok, err = pcall(mount, event.component, app)
    if not ok and log then log("[bank-organizer] panel failed: " .. tostring(err)) end
  end)
end

function Panel.destroy(app)
  if app then app:onChange(LISTENER, nil) end
  if view then pcall(view.Destroy, view) end
  view = nil
end

function Panel.stop(app)
  pcall(Event.ContentLayerReady.Unsubscribe, EVENT_ID)
  Panel.destroy(app)
end

return Panel
