-- Bank Organizer by 6ing
local Store = require("src/core/store")
local App = require("src/app")
local Tagging = require("src/game/tagging")
local Panel = require("src/ui/panel")
local Settings = require("src/ui/settings")

local store = Store.new()
local app = App.new(store)
local stopped = false

-- Client lifecycle hook: runs when the plugin is disabled or reloaded.
function PluginShutdown()
  if stopped then return end
  stopped = true
  Tagging.stop()
  Panel.stop(app)
  Settings.stop(app)
  app:stop()
end

app:start()
Tagging.start(store, function() app:invalidate() end, function() return app.organizing end)
Panel.start(app)
Settings.start(store, app)

log("[bank-organizer] loaded")
