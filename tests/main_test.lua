-- Boots main.lua with a stubbed client + PrettyUI and walks the real user flow:
-- open bank -> plugin enabled -> settings -> Start Organizing -> Stop Organizing.
local A = require("assert")
local F = require("fakes")
local Store = require("src/core/store")
local App = require("src/app")

local T = {}
local UNSORTED = { { id = 2, x = 0, y = 0 }, { id = 1, x = 40, y = 0 } } -- coins before food
local SORTED = { { id = 1, x = 0, y = 0 }, { id = 2, x = 40, y = 0 } }

local function widget(calls, method, args)
  local w = { method = method, args = args, disabled = false }
  function w:SetText(text) self.text = text end
  function w:SetDisabled(disabled) self.disabled = disabled end
  function w:Destroy() self.destroyed = true end
  if method == "AddText" or method == "AddTitle" then
    w.content = type(args[1]) == "table" and args[1].text or args[1]
  end
  calls[#calls + 1] = w
  return w
end

local function view(calls)
  return setmetatable({ Destroy = function() end }, { __index = function(_, method)
    return function(_, ...) return widget(calls, method, { ... }) end
  end })
end

local function boot(opts)
  opts = opts or {}
  F.install({ items = opts.items or UNSORTED,
    objects = { [1] = { name = "Shark", ops = { "Eat" } }, [2] = { name = "Coins" } } })
  local bus = function(name)
    return { Subscribe = function(key, fn) F.events[name .. ":" .. key] = fn end,
      Unsubscribe = function(key) F.events[name .. ":" .. key] = nil end }
  end
  Event.ContentLayerReady, Event.SettingsLayerReady = bus("Content"), bus("Settings")
  _G.PersistentDB = F.memoryDb()
  if opts.settings then PersistentDB:SetStructuredData(Store.SETTINGS_KEY, opts.settings) end
  local ui = { panel = {}, settings = {}, submenus = {} }
  local target = ui.panel
  _G.prettyui = {
    SimpleView = { new = function() return view(target) end },
    Confirm = { new = function() end },
    MiniMenu = { AddSubmenu = function(_, label, children) ui.submenus[#ui.submenus + 1] = { label, children } end },
  }
  dofile(package.path:match("^(.-)/%?%.lua") .. "/main.lua")
  F.events["Logic:bank-organizer:logic"]({ logicTick = 0 })
  F.events["Content:bank-organizer:content"]({ component = { width = 300, height = 500 } })
  target = ui.settings
  F.events["Settings:bank-organizer:settings"]({ component = { width = 300, height = 500 } })
  return ui
end

local function find(calls, method, label)
  for _, w in ipairs(calls) do
    if w.method == method and (label == nil or w.args[1] == label) then return w end
  end
end

local function settingsControls(ui)
  local list = {}
  for _, w in ipairs(ui.settings) do
    if w.method ~= "AddText" and w.method ~= "AddTitle" then list[#list + 1] = w end
  end
  return list
end

local function texts(calls)
  local list = {}
  for _, w in ipairs(calls) do if w.content then list[#list + 1] = w.content end end
  return table.concat(list, "\n")
end

function T.panel_shows_the_four_steps_and_credit()
  local ui = boot()
  local all = texts(ui.panel)
  for _, step in ipairs({ "1. Open your bank.", "2. Enable the plugin.", "4. Click Start Organizing.", "by 6ing" }) do
    A.truthy(all:find(step, 1, true), "panel shows: " .. step)
  end
  PluginShutdown()
end

function T.every_option_lives_in_settings()
  local ui = boot()
  for _, method in ipairs({ "AddComboBox", "AddCheckboxButton", "AddSlider", "AddColourPicker", "AddSimpleButton" }) do
    A.truthy(find(ui.settings, method), method .. " in settings")
    A.eq(find(ui.panel, method == "AddSimpleButton" and "none" or method), nil, method .. " not in panel")
  end
  PluginShutdown()
end

function T.start_turns_into_stop_and_locks_settings()
  local ui = boot()
  local button = find(ui.panel, "AddFancyButton")
  A.eq(button.args[1], "Start Organizing")
  A.eq(find(ui.panel, "AddSimpleButton", "Skip item").disabled, true, "skip disabled before start")
  for _, control in ipairs(settingsControls(ui)) do A.eq(control.disabled, false, control.method .. " editable") end

  button.args[2]()
  A.eq(button.text, "Stop Organizing")
  A.eq(find(ui.panel, "AddSimpleButton", "Skip item").disabled, false, "skip enabled while organizing")
  for _, control in ipairs(settingsControls(ui)) do A.eq(control.disabled, true, control.method .. " locked") end
  A.truthy(texts(ui.settings):find("locked while organizing", 1, true), "lock message shown")
  A.truthy(texts(ui.panel):find("Move Coins to the end, after Shark", 1, true), "status shows the first move")

  button.args[2]()
  A.eq(button.text, "Start Organizing")
  for _, control in ipairs(settingsControls(ui)) do A.eq(control.disabled, false, control.method .. " unlocked") end
  A.eq(texts(ui.settings):find("locked while organizing", 1, true), nil, "lock message cleared")
  PluginShutdown()
end

function T.finishing_unlocks_automatically()
  local ui = boot({ items = SORTED })
  local button = find(ui.panel, "AddFancyButton")
  button.args[2]()
  A.eq(button.text, "Start Organizing")
  A.truthy(texts(ui.panel):find(App.STATUS.DONE, 1, true))
  for _, control in ipairs(settingsControls(ui)) do A.eq(control.disabled, false) end
  PluginShutdown()
end

local function bankMenu()
  return { entries = { { componentData = { component = F.children[1] } } } }
end

function T.tagging_hidden_when_disabled()
  local ui = boot()
  F.events["MiniMenuReady:bank-organizer:menu"]({ miniMenu = bankMenu() })
  A.eq(#ui.submenus, 0)
  PluginShutdown()
end

function T.tagging_sets_tag()
  local ui = boot({ settings = { tagging = true } })
  F.events["MiniMenuReady:bank-organizer:menu"]({ miniMenu = bankMenu() })
  A.eq(#ui.submenus, 1); A.eq(ui.submenus[1][1], "Bank Organizer")
  local children = ui.submenus[1][2]
  A.eq(#children, 8, "no Clear tag before tagging")
  A.eq(children[3].label, "Set: Potions")
  children[3].action()
  A.eq(Store.new(PersistentDB):getTag(F.children[1].associatedObjectID), "potions")
  F.events["MiniMenuReady:bank-organizer:menu"]({ miniMenu = bankMenu() })
  A.eq(ui.submenus[2][2][9].label, "Clear tag")
  PluginShutdown()
end

function T.tagging_locked_while_organizing()
  local ui = boot({ settings = { tagging = true } })
  find(ui.panel, "AddFancyButton").args[2]()
  F.events["MiniMenuReady:bank-organizer:menu"]({ miniMenu = bankMenu() })
  A.eq(#ui.submenus, 0, "no tagging submenu while organizing")
  PluginShutdown()
end

function T.non_bank_menu_ignored()
  local ui = boot({ settings = { tagging = true } })
  F.events["MiniMenuReady:bank-organizer:menu"]({ miniMenu = { entries = { { componentData = {} }, {} } } })
  A.eq(#ui.submenus, 0)
  PluginShutdown()
end

function T.shutdown_is_idempotent_and_unsubscribes()
  boot()
  PluginShutdown()
  PluginShutdown()
  for _, key in ipairs({ "Logic:bank-organizer:logic", "MiniMenuReady:bank-organizer:menu",
    "Content:bank-organizer:content", "Settings:bank-organizer:settings" }) do
    A.eq(F.events[key], nil, key .. " unsubscribed")
  end
end

function T.settings_offer_every_colour()
  local ui = boot()
  local pickers, labels = 0, texts(ui.settings)
  for _, w in ipairs(ui.settings) do if w.method == "AddColourPicker" then pickers = pickers + 1 end end
  A.eq(pickers, 12, "8 categories + move, target, dim, untagged")
  for _, label in ipairs({ "Item to move (MOVE)", "Drop target (INSERT BEFORE)", "Dimmed slots when filtering", "Untagged item outline" }) do
    A.truthy(labels:find(label, 1, true), label)
  end
  A.truthy(find(ui.settings, "AddSimpleButton", "Reset all colours"))
  PluginShutdown()
end

return T
