-- Bank Organizer: the plugin's entry point.
--
-- The client runs this file when the plugin is enabled. It creates the
-- store (saved data) and the App (the controller), then starts every part
-- that listens to the game: the tick loop, the right-click Tags menu, the
-- sidebar and the settings. PluginShutdown is called by the client when the
-- plugin is disabled or reloaded and undoes all of it.

local Store = require("src/core/store")
local App = require("src/app")
local Tagging = require("src/game/tagging")
local Panel = require("src/ui/panel")
local Settings = require("src/ui/settings")
local Windows = require("src/ui/windows")

local store = Store.new()
local app = App.new(store)

-- Guards against the client calling PluginShutdown twice.
local stopped = false

-- Called by the client when the plugin stops: unsubscribes from every event
-- and destroys everything the plugin drew.
function PluginShutdown()
  if stopped then return end
  stopped = true
  Tagging.stop()
  Panel.stop(app)
  Settings.stop()
  Windows.closeAll()
  app:stop()
end

app:start()
-- The right-click menu opens these windows for the clicked item.
Tagging.start(app, {
  -- More... and the single menu entry open the full Tags window.
  tags = function(itemID) Windows.tags(app, itemID) end,
  -- Category... opens the small kind-of-item picker.
  category = function(itemID) Windows.categoryPicker(app, itemID) end,
})
Panel.start(app)
Settings.start(store, app)

log("[bank-organizer] loaded")
