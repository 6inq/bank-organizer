-- Boots main.lua with a stubbed client (bank inventory, bank slot components, vars, PrettyUI)
-- and walks the Bank Architect workflow.
local A = require("assert")
local Store = require("src/core/store")
local Bank = require("src/game/bank")
local Guide = require("src/core/guide")
local Order = require("src/core/order")

local T = {}

local ITEMS = {
  { 101, "Shark", { "Eat" } }, { 102, "Coins" }, { 103, "Abyssal whip", { "Wield" } },
  { 104, "Air rune" }, { 105, "Grimy guam" }, { 106, "Mystery thing" }, { 107, "Prayer potion (4)", { "Drink" } },
}

local function memoryDb()
  local db = { data = {} }
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  function db:SetString(key, value) self.data[key] = value end
  return db
end

local function boot(opts)
  opts = opts or {}
  local env = { events = {}, created = {}, windows = {}, panels = {}, settings = {}, menu = {} }
  env.bank = opts.bank or { 101, 102, 103, 104, 105, 106, 107 }
  env.tabSizes = opts.tabSizes
  env.allItems = opts.allItems ~= false
  local names = {}
  for _, row in ipairs(ITEMS) do names[row[1]] = row end
  local function bus(name)
    return { Subscribe = function(k, f) env.events[name .. ":" .. k] = f end,
      Unsubscribe = function(k) env.events[name .. ":" .. k] = nil end }
  end
  _G.Event = { ServerLogic = bus("Tick"), MiniMenuReady = bus("Menu"), ContentLayerReady = bus("Content"), SettingsLayerReady = bus("Settings") }
  _G.log = function() end
  _G.config = {
    Inv = { BANK = { id = 95 } },
    Obj = { FromID = function(id)
      local row = names[id]
      local ops = {}
      for i, op in ipairs(row and row[3] or {}) do ops[i] = op end
      return row and { id = id, name = row[2], category = -1, interfaceOpNames = ops, quests = {}, isTradeable = true } or nil
    end },
  }
  _G.Inventory = { Find = function()
    local slots = {}
    for i, id in ipairs(env.bank) do slots[i] = { obj = { id = id }, count = 1 } end
    return { isValid = true, GetSlots = function() return slots end }
  end }
  -- Visible bank slot components (one per item, row-major).
  local container = { visibleGlobal = true, width = 400, height = 600 }
  function container:IterateDynamicComponents(fn)
    for i, id in ipairs(env.bank) do
      if fn({ type = 5, associatedObjectID = id, visible = true, hidden = false, x = ((i - 1) % 8) * 40, y = ((i - 1) // 8) * 40,
        width = 36, height = 32, associatedObjectQuantity = 1, interfaceID = 517 }) then return end
    end
  end
  local function component(kind)
    local c = { kind = kind }
    function c:SetPos(x, y) self.x, self.y = x, y end
    function c:SetSize(w, h) self.w, self.h = w, h end
    function c:Destroy() self.destroyed = true end
    env.created[#env.created + 1] = c
    return c
  end
  _G.ui = {
    ComponentType = { SPRITE = 5 }, SelectionChangeEvent = { SELECTED = 1 },
    Interfaces = { GetComponent = function(_, componentID)
      if componentID == 1001 then return container end
      return { kind = "host" }
    end },
    Rectangle = { new = function() return component("rect") end }, Text = { new = function() return component("text") end },
  }
  _G.id = { Component = { BANK__BANK_INV = 1001, TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = 7 }, Interface = { BANK = 517 },
    Font = { MUSEO_SANS_15PT_REGULAR = 1 }, Category = { FromID = function() return nil end } }
  _G.var = {
    VarPlayer = { BANK_CURRENT_TAB = { value = env.allItems and 1 or 3 } },
    VarClient = { BANK_SEARCHMODE_CLIENT = { value = 0 } },
  }
  _G.PersistentDB = memoryDb()
  local function recorder(list)
    return setmetatable({ Destroy = function() end }, { __index = function(_, method)
      return function(_, ...)
        local call = { method = method, args = { ... } }
        if method == "AddText" or method == "AddTitle" then call.content = type(call.args[1]) == "table" and call.args[1].text or call.args[1] end
        list[#list + 1] = call
        return call
      end
    end })
  end
  _G.prettyui = {
    SimpleView = { new = function(parent) local l = {}; local t = parent.kind == "settings" and env.settings or env.panels; t[#t + 1] = l; return recorder(l) end },
    Window = { new = function(_, options) local l = { options = options }; env.windows[#env.windows + 1] = l; local w = recorder(l); return w end },
    Confirm = { new = function(_, o) env.confirm = o end },
  }
  for key in pairs(package.loaded) do if key:match("^src/") then package.loaded[key] = nil end end
  if env.tabSizes then
    for i = 2, 15 do var.VarPlayer["BANK_TAB" .. i] = { value = env.tabSizes[i - 1] or 0 } end
  end
  dofile("main.lua")
  env.events["Content:bank-organizer:content"]({ component = { kind = "content", width = 300, height = 800 } })
  return env
end

local function panel(env) return env.panels[#env.panels] end
local function texts(calls)
  local out = {}
  for _, c in ipairs(calls or {}) do if c.content then out[#out + 1] = c.content end end
  return table.concat(out, "\n")
end
local function find(calls, method, label)
  for _, c in ipairs(calls) do if c.method == method and (label == nil or c.args[1] == label) then return c end end
end
local function tick(env) env.events["Tick:bank-organizer:tick"]() end

-- Choose a dropdown entry the way the game does: by its integer position.
local function pick(combo, key)
  for _, entry in ipairs(combo.args[1].entries) do
    if entry.key == key then return combo.args[1].onChange(nil, entry.id, entry.label, 1) end
  end
  error("no entry " .. tostring(key))
end

local function assertIntegerIds(calls)
  for _, c in ipairs(calls) do
    if c.method == "AddComboBox" then
      for _, entry in ipairs(c.args[1].entries) do A.eq(math.type(entry.id), "integer", "combo ids must be integers") end
      A.eq(math.type(c.args[1].selectedID), "integer", "selected id must be an integer")
    end
  end
end

function T.sidebar_has_the_bank_architect_controls()
  local env = boot()
  local p = panel(env)
  for _, label in ipairs({ "Open Blueprint", "Sorting Guide", "Assign Categories", "Tab Layout" }) do
    A.truthy(find(p, "AddSimpleButton", label), label)
  end
  A.truthy(find(p, "AddFancyButton", "Analyze Bank")); A.truthy(find(p, "AddComboBox"), "preset chooser")
  A.truthy(texts(p):find("Main: Frequently Used, Runes, Teleports, Currency", 1, true), "legend")
  PluginShutdown()
end

function T.analyze_then_blueprint_window_shows_planned_tabs()
  local env = boot()
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  A.truthy(texts(panel(env)):find("Blueprint ready", 1, true))
  find(panel(env), "AddSimpleButton", "Open Blueprint").args[2]()
  local w = env.windows[#env.windows]
  A.eq(w.options.title, "Blueprint")
  local grids, titles = 0, texts(w)
  for _, c in ipairs(w) do if c.method == "AddItemGrid" then grids = grids + 1 end end
  A.eq(grids, 5, "Main, Tab 1 combat, Tab 2 potions/food, Tab 3 herblore, Tab 9 storage")
  A.truthy(titles:find("Tab 9: Storage & Cleanup, Quest Items", 1, true))
  PluginShutdown()
end

function T.bank_is_tinted_by_destination()
  local env = boot()
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  tick(env)
  local rects = 0
  for _, c in ipairs(env.created) do if c.kind == "rect" and not c.destroyed then rects = rects + 1 end end
  A.eq(rects, 7, "one tint per bank item")
  PluginShutdown()
end

function T.right_click_correction_moves_an_item()
  local env = boot()
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  find(panel(env), "AddSimpleButton", "Assign Categories").args[2]()
  local added = {}
  local menu = { entries = { { componentData = { component = { interfaceID = 517, associatedObjectID = 106 } } } } }
  function menu:Add(label, fn) added[#added + 1] = { label = label, fn = fn } end
  env.events["Menu:bank-organizer:menu"]({ miniMenu = menu })
  A.eq(#added, 1); A.eq(added[1].label, "Assign category (Bank Organizer)")
  added[1].fn()
  local picker = env.windows[#env.windows]
  A.eq(picker.options.title, "Assign category")
  pick(find(picker, "AddComboBox"), "boss-loot")
  A.eq(Store.new(PersistentDB).corrections[106], "boss-loot", "saved")
  find(panel(env), "AddSimpleButton", "Open Blueprint").args[2]()
  A.truthy(texts(env.windows[#env.windows]):find("Tab 7", 1, true), "Mystery thing now planned for Tab 7")
  PluginShutdown()
end

function T.menu_entry_only_while_assigning_and_on_bank_items()
  local env = boot()
  local added = 0
  local menu = { entries = { { componentData = { component = { interfaceID = 517, associatedObjectID = 106 } } } } }
  function menu:Add() added = added + 1 end
  env.events["Menu:bank-organizer:menu"]({ miniMenu = menu })
  A.eq(added, 0, "not assigning")
  find(panel(env), "AddSimpleButton", "Assign Categories").args[2]()
  env.events["Menu:bank-organizer:menu"]({ miniMenu = { entries = { { componentData = { component = { interfaceID = 9 } } } }, Add = menu.Add } })
  A.eq(added, 0, "not a bank item")
  PluginShutdown()
end

function T.uses_the_real_rs3_tab_variables()
  local Bank = require("src/game/bank")
  A.eq(#Bank.TAB_VARS.sizes, 14, "custom tabs 2-15"); A.eq(Bank.TAB_VARS.sizes[1], "BANK_TAB2")
  A.eq(Bank.TAB_VARS.insertMode, "BANKINSERT")
end

function T.analyze_logs_the_bank_model()
  local env = boot({ tabSizes = { 2 } })
  local lines = {}
  _G.log = function(line) lines[#lines + 1] = line end
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  A.truthy(lines[1]:find("slots=7 tab=1 insert=nil sizes=2,0,0,0,0,0,0,0,0,0,0,0,0,0 main=Abyssal whip tab1=Shark", 1, true), lines[1])
  PluginShutdown()
end

function T.guide_pauses_without_tab_data()
  local env = boot()
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  A.truthy(texts(panel(env)):find("does not expose bank tab sizes", 1, true))
  PluginShutdown()
end

function T.guide_pauses_outside_all_items_view()
  local env = boot({ tabSizes = {}, allItems = false })
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  A.truthy(texts(panel(env)):find("All items view", 1, true))
  PluginShutdown()
end

function T.guide_gives_moves_and_highlights_once_tabs_are_readable()
  local env = boot({ tabSizes = {} })
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  A.truthy(texts(panel(env)):find("Drag Abyssal whip onto the new%-tab button to create Tab 1"), "first move")
  tick(env)
  local labels = {}
  for _, c in ipairs(env.created) do if c.kind == "text" and not c.destroyed then labels[#labels + 1] = c.content end end
  A.eq(labels[1], "MOVE")
  A.truthy(find(panel(env), "AddSimpleButton", "Stop Sorting Guide"))
  PluginShutdown()
end

function T.tab_layout_editor_moves_tags_and_resets()
  local env = boot()
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  find(panel(env), "AddSimpleButton", "Tab Layout").args[2]()
  local w = env.windows[#env.windows]
  A.eq(w.options.title, "Tab Layout")
  local combos = {}
  for _, c in ipairs(w) do if c.method == "AddComboBox" then combos[#combos + 1] = c end end
  A.eq(#combos, 10, "one add-tag dropdown per destination")
  pick(combos[1], "food") -- add Food & Drink to Main
  A.eq(Store.new(PersistentDB).layout:destinationOf("food"), 0, "saved")
  w = env.windows[#env.windows]
  find(w, "AddSimpleButton", "Reset to default").args[2]()
  A.eq(Store.new(PersistentDB).layout:destinationOf("food"), 2)
  PluginShutdown()
end

function T.ironman_preset_renames_categories()
  local env = boot()
  pick(find(panel(env), "AddComboBox"), "ironman")
  A.eq(Store.new(PersistentDB).preset, "ironman")
  PluginShutdown()
end

function T.shutdown_cleans_up()
  local env = boot()
  PluginShutdown(); PluginShutdown()
  A.eq(next(env.events), nil)
end

-- Bank.sections: container order -> Main + tabs.
function T.sections_split_container_order()
  local items = {}
  for i, id in ipairs({ 1, 2, 3, 4, 5, 6 }) do items[i] = { id = id } end
  local s = Bank.sections(items, { 2, 0, 1, 0, 0, 0, 0, 0, 0 }, true)
  A.list(s[1], { 1, 2 }); A.eq(s[2], nil); A.list(s[3], { 3 }); A.list(s[0], { 4, 5, 6 })
  s = Bank.sections(items, { 2, 1, 0, 0, 0, 0, 0, 0, 0 }, false)
  A.list(s[0], { 1, 2, 3 }); A.list(s[1], { 4, 5 }); A.list(s[2], { 6 })
end

function T.every_dropdown_uses_integer_ids()
  local env = boot()
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  assertIntegerIds(panel(env))
  find(panel(env), "AddSimpleButton", "Tab Layout").args[2]()
  assertIntegerIds(env.windows[#env.windows])
  env.events["Settings:bank-organizer:settings"]({ component = { kind = "settings", width = 300, height = 800 } })
  assertIntegerIds(env.settings[#env.settings])
  PluginShutdown()
end

function T.analyze_exports_item_facts_with_their_tab()
  local env = boot({ tabSizes = { 2 } })
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  local export = PersistentDB.data["bank-organizer-export"]
  local lines = {}
  for line in export:gmatch("[^\n]+") do lines[#lines + 1] = line end
  A.eq(#lines, 8, "header + 7 items")
  A.truthy(lines[1]:find("^slot\tid\tname"), "tab-separated header")
  A.truthy(lines[2]:find("\tShark\t", 1, false), "item name")
  A.truthy(lines[2]:find("eat", 1, true), "right-click ops")
  A.truthy(lines[2]:find("\t1\tfood$"), "in custom tab 1, classified as food")
  PluginShutdown()
end

return T
