local Tags = require("src/core/tags")
local Combo = require("src/ui/combo")

local Settings = {}

local EVENT_ID = "bank-organizer:settings"
local view

local HIGHLIGHTS = { { "move", "Item to move (MOVE)" }, { "target", "Drop target" }, { "line", "Guide line" } }

local function addColour(store, app, key, label)
  view:AddText(label)
  view:AddColourPicker({
    value = store:colour(key),
    onChange = function(_, colour) store:setColour(key, colour); app:rebuild() end,
  })
end

local function mount(parent, store, app)
  Settings.destroy()
  view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
  view:AddTitle("Bank Organizer")
  view:AddCheckboxButton({
    { text = "Tint bank items with their planned tab colour", value = "tint", selected = store:get("tint") },
  }, { onChange = function(_, _, changed, selected) store:set(changed, selected); app:rebuild() end })
  view:AddText("Tint opacity")
  view:AddSlider({
    min = 0, max = 100, step = 5, value = math.floor(store:get("opacity") * 100 + 0.5),
    onChange = function(_, value) store:set("opacity", value / 100); app:rebuild() end,
  })
  view:AddText({ text = "Rearrange mode (used when the game does not report it)", height = 40 })
  view:AddComboBox(Combo.options(
    { { label = "Insert (fewer moves)", key = "insert" }, { label = "Swap", key = "swap" } },
    store:get("mode"),
    function(key) store:set("mode", key) end))
  view:AddTitle("Colours by kind")
  view:AddText({ text = "A tab takes the colour of the first kind of item it holds.", height = 40 })
  for _, category in ipairs(Tags.CATEGORIES) do
    addColour(store, app, category.key, category.main)
  end
  view:AddTitle("Guide colours")
  for _, highlight in ipairs(HIGHLIGHTS) do addColour(store, app, highlight[1], highlight[2]) end
  view:AddSimpleButton("Reset all colours", function()
    prettyui.Confirm.new(parent, { title = "RESET COLOURS", body = "Put every colour back to its default?",
      confirmLabel = "RESET", onConfirm = function() store:resetColours(); app:rebuild() end })
  end)
  view:AddTitle("Corrections")
  view:AddSimpleButton("Stop ignoring all items", function()
    prettyui.Confirm.new(parent, { title = "STOP IGNORING", body = "Let the guide organize every item you ignored?",
      confirmLabel = "RESET", onConfirm = function() store:resetIgnored(); app:rebuild() end })
  end)
  view:AddSimpleButton("Reset corrections", function()
    prettyui.Confirm.new(parent, { title = "RESET CORRECTIONS", body = "Forget every category you assigned by hand?",
      confirmLabel = "RESET", onConfirm = function() store:resetCorrections(); app:rebuild() end })
  end)
end

function Settings.start(store, app)
  Event.SettingsLayerReady.Subscribe(EVENT_ID, function(event)
    local ok, err = pcall(mount, event.component, store, app)
    if not ok and log then log("[bank-organizer] settings failed: " .. tostring(err)) end
  end)
end

function Settings.destroy()
  if view then pcall(function() return view:Destroy() end) end
  view = nil
end

function Settings.stop()
  pcall(function() return Event.SettingsLayerReady.Unsubscribe(EVENT_ID) end)
  Settings.destroy()
end

return Settings
