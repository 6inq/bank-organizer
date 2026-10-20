local A = require("assert")
local Store = require("src/core/store")
local Bank = require("src/game/bank")
local Guide = require("src/core/guide")
local Order = require("src/core/order")

local T = {}

local ITEMS = {
  { 101, "Shark", { "Eat" } }, { 102, "Coins" }, { 103, "Abyssal whip", { "Wield" } },
  { 104, "Air rune" }, { 105, "Grimy guam" }, { 106, "Mystery thing" }, { 107, "Prayer potion (4)", { "Drink" } },
  { 108, "Rune scimitar", { "Wield" } },
  { 109, "Dragon dagger", { "Wield" } },
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
  local env = { events = {}, created = {}, windows = {}, panels = {}, settings = {}, menu = {}, hidden = {}, tabIcons = opts.tabIcons or {} }
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
  local container = { visibleGlobal = true, width = 400, height = 600, xyGlobal = { x = 100, y = 100 } }
  env.layer = { kind = "layer", xyGlobal = { x = 0, y = 0 } }
  local function bankStatic(staticID)
    if staticID == 0 then return container end
    return env.tabIcons[staticID]
  end
  function container:IterateDynamicComponents(fn)
    for i, id in ipairs(env.bank) do
      local position = i
      for index, shown in ipairs(env.display or {}) do if shown == id then position = index end end
      local x, y = ((position - 1) % 8) * 40, ((position - 1) // 8) * 40
      if not env.hidden[id] and fn({ type = 5, associatedObjectID = id, visible = true, hidden = false, x = x, y = y,
        xyGlobal = { x = 100 + x, y = 100 + y - (env.scroll or 0) },
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
    Interfaces = { GetComponent = function(_, componentID, staticID)
      if staticID ~= nil then return componentID == 517 and bankStatic(staticID) or nil end
      if componentID == 1001 then return container end
      if componentID == 7 then return env.layer end
      return { kind = "host" }
    end },
    Rectangle = { new = function(parent) local c = component("rect"); c.parent = parent; return c end },
    Text = { new = function(parent) local c = component("text"); c.parent = parent; return c end },
    Line = { new = function(parent) local c = component("line"); c.parent = parent; return c end },
  }
  _G.id = { Component = { BANK__BANK_INV = 1001, TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = 7 }, Interface = { BANK = 517 },
    Font = { MUSEO_SANS_15PT_REGULAR = 1 }, Category = { FromID = function() return nil end } }
  _G.var = {
    VarPlayer = { BANK_CURRENT_TAB = { value = env.allItems and 1 or 3 } },
    VarClient = { BANK_SEARCHMODE_CLIENT = { value = 0 } },
  }
  _G.Vector4 = { new = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
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

local function pick(combo, key)
  for _, entry in ipairs(combo.args[1].entries) do
    if entry.key == key then return combo.args[1].onChange(nil, entry.id, entry.label, 1) end
  end
  error("no entry " .. tostring(key))
end

local function comboWith(calls, key)
  for _, c in ipairs(calls) do
    if c.method == "AddComboBox" then
      for _, entry in ipairs(c.args[1].entries) do if entry.key == key then return c end end
    end
  end
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
  A.truthy(find(p, "AddFancyButton", "Analyze Bank")); A.truthy(comboWith(p, "ironman"), "preset chooser")
  A.truthy(comboWith(p, "tabs"), "Organize: whole bank / my tabs")
  A.truthy(texts(p):find("Tab 1 (infinity): Frequently Used, Runes, Summoning, Teleports, Currency", 1, true), "legend")
  PluginShutdown()
end

function T.analyze_then_blueprint_window_shows_planned_tabs()
  local env = boot()
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  A.truthy(texts(panel(env)):find("Blueprint ready", 1, true))
  find(panel(env), "AddSimpleButton", "Open Blueprint").args[2]()
  local w = env.windows[#env.windows]
  A.eq(w.options.title, "Blueprint")
  local grids = 0
  for _, c in ipairs(w) do if c.method == "AddItemGrid" then grids = grids + 1 end end
  A.eq(grids, 1, "one tab at a time, however big the bank")
  local picker = find(w, "AddComboBox")
  A.eq(#picker.args[1].entries, 5, "main, combat, potions/food, herblore, storage")
  local last = picker.args[1].entries[5].label
  A.truthy(last:find("^Tab 10: Storage & Cleanup, Quest Items"), last)
  assertIntegerIds(w)
  A.truthy(texts(w):find("Tab 1 of 5", 1, true))
  find(w, "AddSimpleButton", "Next").args[2]()
  A.truthy(texts(env.windows[#env.windows]):find("Tab 2 of 5", 1, true), "Next steps through the tabs")
  pick(find(env.windows[#env.windows], "AddComboBox"), 9)
  A.truthy(texts(env.windows[#env.windows]):find("Tab 5 of 5", 1, true), "dropdown jumps to a tab")
  find(env.windows[#env.windows], "AddSimpleButton", "Next").args[2]()
  A.truthy(texts(env.windows[#env.windows]):find("Tab 1 of 5", 1, true), "Next wraps around")
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
  A.eq(#added, 2); A.eq(added[1].label, "Ignore (Bank Organizer)"); A.eq(added[2].label, "Assign category (Bank Organizer)")
  added[2].fn()
  local picker = env.windows[#env.windows]
  A.eq(picker.options.title, "Assign category")
  pick(find(picker, "AddComboBox"), "boss-loot")
  A.eq(Store.new(PersistentDB).corrections[106], "boss-loot", "saved")
  find(panel(env), "AddSimpleButton", "Open Blueprint").args[2]()
  A.truthy(comboWith(env.windows[#env.windows], 7), "Mystery thing now planned for boss loot (Tab 8)")
  PluginShutdown()
end

function T.menu_entry_only_while_assigning_and_on_bank_items()
  local env = boot()
  local added = 0
  local menu = { entries = { { componentData = { component = { interfaceID = 517, associatedObjectID = 106 } } } } }
  function menu:Add() added = added + 1 end
  env.events["Menu:bank-organizer:menu"]({ miniMenu = menu })
  A.eq(added, 1, "only Ignore while not assigning")
  added = 0
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
  A.truthy(texts(panel(env)):find("Drag Abyssal whip onto the %+ button to start Tab 2 %(Combat Gear%)"), texts(panel(env)))
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
  pick(combos[1], "food")
  A.eq(Store.new(PersistentDB).layout:destinationOf("food"), 0, "saved")
  w = env.windows[#env.windows]
  find(w, "AddSimpleButton", "Reset to default").args[2]()
  A.eq(Store.new(PersistentDB).layout:destinationOf("food"), 2)
  PluginShutdown()
end

function T.ironman_preset_renames_categories()
  local env = boot()
  pick(comboWith(panel(env), "ironman"), "ironman")
  A.eq(Store.new(PersistentDB).preset, "ironman")
  PluginShutdown()
end

function T.shutdown_cleans_up()
  local env = boot()
  PluginShutdown(); PluginShutdown()
  A.eq(next(env.events), nil)
end

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
  A.truthy(lines[2]:find("\t1\tfood\t"), "in custom tab 1, classified as food, then params")
  PluginShutdown()
end

local function mainLine(env)
  for _, c in ipairs(env.created) do
    if c.kind == "line" and not c.destroyed and c.width == 3 then return c end
  end
end

function T.guide_line_joins_move_item_and_target()
  local env = boot({ tabSizes = {}, bank = { 102, 104 } })
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  tick(env)
  local lines, shadows, bar = 0, 0, nil
  for _, c in ipairs(env.created) do
    if not c.destroyed and c.parent == env.layer then
      if c.kind == "line" and c.width == 3 then lines = lines + 1 end
      if c.kind == "line" and c.width == 6 then shadows = shadows + 1 end
      if c.kind == "rect" then bar = c end
    end
  end
  A.eq(lines, 3, "a white line plus a two-legged arrowhead")
  A.eq(shadows, 3, "each with a dark outline underneath")
  A.truthy(bar and bar.fill, "a filled insertion bar marks the drop point")
  local white = mainLine(env)
  A.eq(white.colour.r, 1); A.eq(white.colour.g, 1); A.eq(white.colour.b, 1)
  PluginShutdown()
end

function T.line_box_covers_both_directions()
  local Overlay = require("src/game/overlay")
  local x, y, w, h, invert = Overlay.lineBox(10, 10, 50, 90)
  A.eq(x, 10); A.eq(y, 10); A.eq(w, 40); A.eq(h, 80); A.eq(invert, false)
  x, y, w, h, invert = Overlay.lineBox(50, 10, 10, 90)
  A.eq(x, 10); A.eq(y, 10); A.eq(invert, true, "down-left needs invert")
  x, y, w, h = Overlay.lineBox(10, 20, 90, 20)
  A.eq(h, 1, "flat line keeps a 1px height")
end

function T.my_tabs_keeps_tabs_and_numbers_them_like_rs3()
  local env = boot({ tabSizes = { 2 }, bank = { 101, 107, 102, 104, 106 } })
  pick(comboWith(panel(env), "tabs"), "tabs")
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  local text = texts(panel(env))
  A.truthy(text:find("Tab 1 (infinity): misc catch-all", 1, true), "infinity is the catch-all")
  A.truthy(text:find("Tab 2: Food & Drink, Potions", 1, true) or text:find("Tab 2: Potions, Food & Drink", 1, true), "tab profile from its items")
  A.truthy(find(panel(env), "AddSimpleButton", "Tab Layout"), "layout editor in My tabs too")
  A.eq(comboWith(panel(env), "ironman"), nil, "presets only for whole-bank mode")
  PluginShutdown()
end

function T.my_tabs_guide_focuses_on_the_viewed_tab()
  local env = boot({ tabSizes = { 2 }, bank = { 101, 107, 102, 104 } })
  pick(comboWith(panel(env), "tabs"), "tabs")
  var.VarPlayer.BANK_CURRENT_TAB.value = 2
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  local text = texts(panel(env))
  A.truthy(text:find("Insert Prayer potion %(4%) before Shark") or text:find("Insert Shark after Prayer potion %(4%)"), "sorts only this tab: " .. text)
  A.truthy(text:find("1 left", 1, true), "one move fixes this tab")
  var.VarPlayer.BANK_CURRENT_TAB.value = 1
  tick(env)
  text = texts(panel(env))
  A.truthy(text:find("Insert Air rune before Coins") or text:find("Insert Coins after Air rune"), "infinity sorts its own items: " .. text)
  PluginShutdown()
end

function T.my_tabs_routes_infinity_items_to_the_matching_tab()
  local Blueprint = require("src/core/blueprint")
  local function it(slot, id, name, ops)
    local set = {}
    for _, op in ipairs(ops or {}) do set[op] = true end
    return { slot = slot, id = id, name = name, quantity = 1, info = { name = name, ops = set } }
  end
  local items = { it(1, 1, "Shark", { "eat" }), it(2, 2, "Lobster", { "eat" }), it(3, 3, "Air rune"),
    it(4, 4, "Monkfish", { "eat" }), it(5, 5, "Fire rune"), it(6, 6, "Strange thing") }
  local sections = { [0] = { 4, 5, 6 }, [1] = { 1, 2 }, [2] = { 3 } }
  local d = Blueprint.buildFromTabs(items, sections, Blueprint.resolver({}))
  local function ids(list) local out = {} for i, e in ipairs(list) do out[i] = e.id end return out end
  A.eq(d.identity, true)
  A.list(ids(d[1]), { 2, 4, 1 }, "Monkfish joins the food tab (2 food there), sorted by name")
  A.list(ids(d[2]), { 3 }, "one rune is not enough evidence to pull Fire rune in")
  A.list(ids(d[0]), { 5, 6 }, "Fire rune and the unknown item stay in infinity")
end

function T.pinned_tag_overrides_automatic_routing()
  local Blueprint = require("src/core/blueprint")
  local function it(slot, id, name, ops)
    local set = {}
    for _, op in ipairs(ops or {}) do set[op] = true end
    return { slot = slot, id = id, name = name, quantity = 1, info = { name = name, ops = set } }
  end
  local items = { it(1, 1, "Shark", { "eat" }), it(2, 2, "Lobster", { "eat" }), it(3, 3, "Air rune"), it(4, 4, "Monkfish", { "eat" }) }
  local sections = { [0] = { 4 }, [1] = { 1, 2 }, [2] = { 3 } }
  local function ids(list) local out = {} for i, e in ipairs(list) do out[i] = e.id end return out end
  local d = Blueprint.buildFromTabs(items, sections, Blueprint.resolver({}), { food = 2 })
  A.list(ids(d[2]), { 3, 2, 4, 1 }, "pinned food pulls every food item into tab 2, even from tab 1")
  A.list(ids(d[1]), {}, "tab 1 empties")
  d = Blueprint.buildFromTabs(items, sections, Blueprint.resolver({}), { food = 0 })
  A.list(ids(d[0]), { 2, 4, 1 }, "pinning to infinity sends food back to the catch-all")
  d = Blueprint.buildFromTabs(items, sections, Blueprint.resolver({}), { food = 9 })
  A.list(ids(d[1]), { 2, 4, 1 }, "a pin to a tab you no longer have is ignored (automatic routing applies)")
end

function T.my_tabs_layout_window_pins_unpins_and_saves()
  local env = boot({ tabSizes = { 2 }, bank = { 101, 107, 102, 104, 106 } })
  pick(comboWith(panel(env), "tabs"), "tabs")
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  find(panel(env), "AddSimpleButton", "Tab Layout").args[2]()
  local w = env.windows[#env.windows]
  A.eq(w.options.title, "Tab Layout (My tabs)")
  assertIntegerIds(w)
  local combos = {}
  for _, c in ipairs(w) do if c.method == "AddComboBox" then combos[#combos + 1] = c end end
  A.eq(#combos, 2, "one pin dropdown per tab (infinity + custom tab 1)")
  pick(combos[2], "runes")
  A.eq(Store.new(PersistentDB).tabHomes.runes, 1, "pin saved")
  w = env.windows[#env.windows]
  A.truthy(texts(w):find("Runes  (pinned)", 1, true), "shown as pinned: " .. texts(w))
  find(w, "AddSimpleButton", "Unpin").args[2]()
  A.eq(Store.new(PersistentDB).tabHomes.runes, nil, "unpinned")
  pick(combos[1], "food")
  w = env.windows[#env.windows]
  find(w, "AddSimpleButton", "Unpin all").args[2]()
  A.eq(next(Store.new(PersistentDB).tabHomes), nil, "all pins cleared")
  PluginShutdown()
end

function T.store_rejects_bad_pins()
  local db = { data = { ["bank-organizer-v2"] = { tabHomes = { runes = 3, food = "x", nope = 1, gear = 99, potions = 1.5 } } } }
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  local store = Store.new(db)
  A.eq(store.tabHomes.runes, 3); A.eq(store.tabHomes.food, nil); A.eq(store.tabHomes.nope, nil)
  A.eq(store.tabHomes.gear, nil); A.eq(store.tabHomes.potions, nil)
  A.eq(store:setTabHome("runes", -1), false); A.eq(store:setTabHome("bogus", 1), false)
  A.eq(store:setTabHome("runes", 0), true); A.eq(db.data["bank-organizer-v2"].tabHomes.runes, 0)
end

local function liveLine(env)
  for _, c in ipairs(env.created) do
    if c.kind == "line" and not c.destroyed and c.width == 3 then return c end
  end
end

local TAB_BANK = { bank = { 103, 108, 102, 104 }, tabSizes = { 1 } }

local function tabRow4()
  local row = {}
  for i = 0, 3 do row[#row + 1] = { xyGlobal = { x = 100 + i * 48, y = 60 }, width = 40, height = 40, visible = true } end
  return row
end

local function tabRow()
  local row = {}
  for i = 0, 2 do
    local x = 100 + i * 48
    row[#row + 1] = { xyGlobal = { x = x, y = 60 }, width = 40, height = 40, visible = true }
    row[#row + 1] = { xyGlobal = { x = x + 4, y = 64 }, width = 32, height = 32, visible = true }
  end
  row[#row + 1] = { xyGlobal = { x = 480, y = 84 }, width = 16, height = 16, visible = true }
  return row
end

function T.guide_line_points_at_the_tab_button()
  local env = boot({ bank = TAB_BANK.bank, tabSizes = TAB_BANK.tabSizes, tabIcons = tabRow() })
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  A.truthy(texts(panel(env)):find("Drag Rune scimitar onto Tab 2", 1, true), texts(panel(env)))
  tick(env)
  local line = liveLine(env)
  A.truthy(line, "a line for a drag-to-tab step")
  A.eq(line.parent, env.layer, "drawn on the plugin layer so nothing clips it")
  A.eq(line.x, 158); A.eq(line.y, 100); A.eq(line.w, 10); A.eq(line.h, 16); A.eq(line.invert, true)
  local box
  for _, c in ipairs(env.created) do if c.kind == "rect" and not c.destroyed and c.parent == env.layer then box = c end end
  A.truthy(box and not box.fill, "the tab button is outlined")
  A.eq(box.x, 146); A.eq(box.y, 58); A.eq(box.w, 44); A.eq(box.h, 44)
  PluginShutdown()
end

function T.guide_line_falls_back_to_the_tab_row()
  local env = boot({ bank = TAB_BANK.bank, tabSizes = TAB_BANK.tabSizes })
  local lines = {}
  _G.log = function(text) lines[#lines + 1] = text end
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  tick(env)
  local line = liveLine(env)
  A.truthy(line, "still a line without a tab button")
  A.eq(line.y, 100 - 24 + 16, "ends just above the slots")
  A.truthy(table.concat(lines, "\n"):find("tab button for Tab 2 not found", 1, true), "logged once for diagnosis")
  PluginShutdown()
end

function T.guide_line_stays_while_the_item_is_dragged()
  local env = boot({ bank = TAB_BANK.bank, tabSizes = TAB_BANK.tabSizes, tabIcons = tabRow() })
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  tick(env)
  env.hidden[108] = true
  tick(env)
  local line = liveLine(env)
  A.truthy(line, "line kept during the drag")
  A.eq(line.x, 158, "from where the item was")
  PluginShutdown()
end

local function layoutWindow(env)
  find(panel(env), "AddSimpleButton", "Tab Layout").args[2]()
  return env.windows[#env.windows]
end

function T.top_row_labels_stay_inside_the_slot_area()
  local env = boot({ tabSizes = {}, bank = { 102, 104 } })
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  tick(env)
  for _, c in ipairs(env.created) do
    if c.kind == "text" and not c.destroyed then A.truthy(c.y >= 0, c.content .. " label at y=" .. tostring(c.y)) end
  end
  PluginShutdown()
end

local MY_BANK = { bank = { 103, 108, 101, 107, 102 }, tabSizes = { 2, 2 } }

local function myTabsLayout(env)
  pick(comboWith(panel(env), "tabs"), "tabs")
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  find(panel(env), "AddSimpleButton", "Tab Layout").args[2]()
  return env.windows[#env.windows]
end

function T.my_tabs_remove_sends_an_auto_kind_to_infinity()
  local env = boot(MY_BANK)
  local w = myTabsLayout(env)
  A.truthy(texts(w):find("Combat Gear  (auto)", 1, true))
  find(w, "AddSimpleButton", "Remove").args[2]()
  A.eq(Store.new(PersistentDB).tabHomes.gear, 0, "removed = pinned to infinity")
  A.truthy(texts(panel(env)):find("Tab 1 (infinity): misc catch-all  (3)", 1, true), texts(panel(env)))
  PluginShutdown()
end

function T.my_tabs_swap_two_tabs()
  local env = boot(MY_BANK)
  local w = myTabsLayout(env)
  find(w, "AddSimpleButton", "Move right").args[2]()
  A.list(Store.new(PersistentDB).tabOrder, { 2, 1 }, "saved")
  local text = texts(panel(env))
  A.truthy(text:find("Tab 2 (now Tab 3): Food & Drink, Potions", 1, true), text)
  A.truthy(text:find("Tab 3 (now Tab 2): Combat Gear", 1, true), text)
  var.VarPlayer.BANK_CURRENT_TAB.value = 2
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  A.truthy(texts(panel(env)):find("Drag Abyssal whip onto Tab 3", 1, true), texts(panel(env)))
  find(env.windows[#env.windows], "AddSimpleButton", "Keep my tab order").args[2]()
  A.eq(Store.new(PersistentDB).tabOrder, nil, "order reset")
  PluginShutdown()
end

function T.swapping_back_clears_the_order_and_pins_follow_their_tab()
  local env = boot(MY_BANK)
  local w = myTabsLayout(env)
  pick(find(w, "AddComboBox"), "runes")
  local store = Store.new(PersistentDB)
  A.eq(store.tabHomes.runes, 0)
  w = env.windows[#env.windows]
  local combos = {}
  for _, c in ipairs(w) do if c.method == "AddComboBox" then combos[#combos + 1] = c end end
  pick(combos[2], "clues")
  w = env.windows[#env.windows]
  find(w, "AddSimpleButton", "Move right").args[2]()
  A.eq(Store.new(PersistentDB).tabHomes.clues, 2, "pin moved with its tab")
  w = env.windows[#env.windows]
  local lefts = {}
  for _, c in ipairs(w) do if c.method == "AddSimpleButton" and c.args[1] == "Move left" then lefts[#lefts + 1] = c end end
  lefts[2].args[2]()
  A.eq(Store.new(PersistentDB).tabOrder, nil, "back to your own order")
  A.eq(Store.new(PersistentDB).tabHomes.clues, 1)
  PluginShutdown()
end

function T.tab_layout_adds_renames_moves_and_deletes_tabs()
  local env = boot()
  local w = layoutWindow(env)
  find(w, "AddSimpleButton", "Add tab").args[2]()
  A.eq(Store.new(PersistentDB).layout:last(), 10, "11th destination added")
  w = env.windows[#env.windows]
  local fields = {}
  for _, c in ipairs(w) do if c.method == "AddTextField" then fields[#fields + 1] = c end end
  A.eq(#fields, 11, "one name field per tab")
  fields[2].args[1].onSubmit(nil, "  Combat  ")
  A.eq(Store.new(PersistentDB).layout.names[1], "Combat", "renamed and trimmed")
  w = env.windows[#env.windows]
  find(w, "AddSimpleButton", "Move right").args[2]()
  local saved = Store.new(PersistentDB).layout
  A.eq(saved.names[2], "Combat", "name travels with the tab")
  A.eq(saved:destinationOf("gear"), 2, "and so do its tags")
  w = env.windows[#env.windows]
  find(w, "AddSimpleButton", "Delete tab").args[2]()
  saved = Store.new(PersistentDB).layout
  A.eq(saved:last(), 9); A.eq(saved:destinationOf("potions"), 0, "deleted tab's tags go to infinity")
  A.eq(saved.names[1], "Combat", "later tabs shift left")
  A.truthy(texts(panel(env)):find("Tab 2 Combat: Combat Gear", 1, true), "legend uses the name: " .. texts(panel(env)))
  PluginShutdown()
end

function T.copy_my_current_tabs_needs_an_analyzed_bank()
  local env = boot({ bank = { 101, 107, 103, 108, 102 }, tabSizes = { 2, 2 } })
  local w = layoutWindow(env)
  find(w, "AddSimpleButton", "Copy my current tabs").args[2]()
  A.truthy(texts(env.windows[#env.windows]):find("press Analyze Bank first", 1, true))
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  find(env.windows[#env.windows], "AddSimpleButton", "Copy my current tabs").args[2]()
  local saved = Store.new(PersistentDB).layout
  A.eq(saved:last(), 2, "one tab per custom tab")
  A.eq(saved:destinationOf("gear"), 2, "whip and scimitar make tab 2 the gear tab")
  A.eq(saved.names[2], "Combat Gear", "named after what it holds")
  A.eq(saved:destinationOf("food"), 0, "one food item is not enough evidence")
  PluginShutdown()
end

function T.focused_guide_only_drags_from_the_viewed_tab()
  local Blueprint = require("src/core/blueprint")
  local destinations = { identity = true, [0] = {}, [1] = { { id = 1 }, { id = 2 } }, [2] = { { id = 3 } } }
  local sections = { [0] = { 2 }, [1] = { 1 }, [2] = { 3 } }
  local step = Guide.next(sections, destinations, Guide.INSERT, 2)
  A.eq(step, nil, "nothing to do in tab 2; item 2 must be dragged from infinity")
  step = Guide.next(sections, destinations, Guide.INSERT, 0)
  A.eq(step.kind, "to-tab"); A.eq(step.id, 2); A.eq(step.to, 1)
end

function T.no_tabs_yet_starts_tabs_from_the_plus_button()
  local env = boot({ bank = { 103, 101, 102 }, tabSizes = {}, tabIcons = tabRow() })
  pick(comboWith(panel(env), "tabs"), "tabs")
  find(panel(env), "AddFancyButton", "Analyze Bank").args[2]()
  A.truthy(texts(panel(env)):find("You have no tabs yet", 1, true), texts(panel(env)))
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  A.truthy(texts(panel(env)):find("Drag Abyssal whip onto the + button to start Tab 2 (Combat Gear)", 1, true), texts(panel(env)))
  tick(env)
  local box
  for _, c in ipairs(env.created) do if c.kind == "rect" and not c.destroyed and c.parent == env.layer then box = c end end
  A.truthy(box, "the + button is outlined")
  A.eq(box.x, 100 + 2 * 48 - 2, "the last button in the row")
  PluginShutdown()
end

function T.sort_choice_is_in_the_sidebar_and_saved()
  local env = boot()
  local combo = comboWith(panel(env), "keep")
  A.truthy(combo, "Sort inside tabs dropdown")
  pick(combo, "name")
  A.eq(Store.new(PersistentDB):get("sort"), "name")
  PluginShutdown()
end

function T.arrow_follows_the_bank_when_it_scrolls()
  local env = boot({ bank = TAB_BANK.bank, tabSizes = TAB_BANK.tabSizes, tabIcons = tabRow() })
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  tick(env)
  A.eq(liveLine(env).y, 100, "starts at the scimitar")
  env.scroll = 10
  tick(env)
  local line = liveLine(env)
  A.eq(line.y + line.h, 116 - 10, "redrawn from where the scimitar now is")
  PluginShutdown()
end

function T.offscreen_item_gets_a_scroll_pointer_instead_of_a_line()
  local env = boot({ bank = TAB_BANK.bank, tabSizes = TAB_BANK.tabSizes, tabIcons = tabRow() })
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  env.scroll = 300
  tick(env)
  local line = liveLine(env)
  A.truthy(line, "a pointer is drawn")
  A.eq(line.w, 1, "straight up at the top edge"); A.eq(line.y, 106); A.eq(line.h, 26)
  for _, c in ipairs(env.created) do
    A.truthy(not (c.kind == "rect" and not c.destroyed and c.parent == env.layer), "no drop marker until the item is in view")
  end
  PluginShutdown()
end

local function settle(env) tick(env); tick(env) end

local MISTAKE_BANK = { bank = { 108, 101, 103 }, tabSizes = { 3 } }

local function guideOnTab(env)
  pick(comboWith(panel(env), "tabs"), "tabs")
  var.VarPlayer.BANK_CURRENT_TAB.value = 2
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  return texts(panel(env))
end

function T.a_wrong_move_is_caught_and_walked_back()
  local env = boot(MISTAKE_BANK)
  local first = guideOnTab(env)
  A.truthy(first:find("Insert Abyssal whip before Rune scimitar", 1, true), first)
  env.bank = { 103, 101, 108 }
  settle(env)
  local text = texts(panel(env))
  A.truthy(text:find("Not quite", 1, true), "mistake noticed: " .. text)
  A.truthy(find(panel(env), "AddSimpleButton", "Continue from here"), "can accept the new layout")
  env.bank = { 108, 101, 103 }
  settle(env)
  text = texts(panel(env))
  A.truthy(text:find("Insert Abyssal whip before Rune scimitar", 1, true), "back to the original move: " .. text)
  A.eq(find(panel(env), "AddSimpleButton", "Continue from here"), nil)
  PluginShutdown()
end

function T.the_right_move_moves_on()
  local env = boot(MISTAKE_BANK)
  guideOnTab(env)
  env.bank = { 103, 108, 101 }
  settle(env)
  local text = texts(panel(env))
  A.eq(text:find("Not quite", 1, true), nil, text)
  A.truthy(text:find("Tab 2 is organized", 1, true), text)
  PluginShutdown()
end

function T.continue_from_here_accepts_the_new_layout()
  local env = boot(MISTAKE_BANK)
  guideOnTab(env)
  env.bank = { 103, 101, 108 }
  settle(env)
  find(panel(env), "AddSimpleButton", "Continue from here").args[2]()
  local text = texts(panel(env))
  A.eq(text:find("Not quite", 1, true), nil, "planning from the bank as it is now: " .. text)
  PluginShutdown()
end

local function rightClick(env, itemID)
  local added = {}
  local menu = { entries = { { componentData = { component = { interfaceID = 517, associatedObjectID = itemID } } } } }
  function menu:Add(label, fn) added[#added + 1] = { label = label, fn = fn } end
  env.events["Menu:bank-organizer:menu"]({ miniMenu = menu })
  return added
end

function T.ignored_items_are_left_alone()
  local env = boot(MISTAKE_BANK)
  guideOnTab(env)
  local menu = rightClick(env, 103)
  A.eq(menu[1].label, "Ignore (Bank Organizer)")
  menu[1].fn()
  A.eq(Store.new(PersistentDB):isIgnored(103), true, "saved")
  local text = texts(panel(env))
  A.truthy(text:find("Ignoring 1 item", 1, true), text)
  A.truthy(text:find("Tab 2 is organized", 1, true), "the whip no longer needs moving: " .. text)
  tick(env)
  local outlined = 0
  for _, c in ipairs(env.created) do if c.kind == "rect" and not c.destroyed and c.outlineThickness == 1 then outlined = outlined + 1 end end
  A.eq(outlined, 1, "the ignored whip gets a thin outline instead of a tint")
  menu = rightClick(env, 103)
  A.eq(menu[1].label, "Stop ignoring (Bank Organizer)")
  menu[1].fn()
  A.eq(Store.new(PersistentDB):isIgnored(103), false)
  A.truthy(texts(panel(env)):find("Insert Abyssal whip before Rune scimitar", 1, true), "sorted again once unignored")
  PluginShutdown()
end

function T.ignored_items_never_move_between_tabs()
  local env = boot({ bank = TAB_BANK.bank, tabSizes = TAB_BANK.tabSizes })
  rightClick(env, 108)[1].fn()
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  A.eq(texts(panel(env)):find("Rune scimitar", 1, true), nil, "the ignored scimitar is never asked to move: " .. texts(panel(env)))
  PluginShutdown()
end

function T.ignore_list_survives_a_restart()
  local db = { data = { ["bank-organizer-v2"] = { ignored = { 103, "108", "x" } } } }
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  local store = Store.new(db)
  A.eq(store:isIgnored(103), true); A.eq(store:isIgnored(108), true); A.eq(store:ignoredCount(), 2)
  store:setIgnored(101, true)
  A.list(db.data["bank-organizer-v2"].ignored, { 101, 103, 108 }, "saved as a plain sorted list")
  store:resetIgnored()
  A.eq(Store.new(db):ignoredCount(), 0)
end

function T.a_right_move_is_not_judged_while_the_game_is_mid_update()
  local env = boot({ bank = { 103, 108, 101, 107, 109, 102 }, tabSizes = { 2, 2 } })
  pick(comboWith(panel(env), "tabs"), "tabs")
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  local text = texts(panel(env))
  A.truthy(text:find("Drag Dragon dagger onto Tab 2", 1, true), text)
  env.bank = { 103, 108, 109, 101, 107, 102 }
  tick(env)
  var.VarPlayer.BANK_TAB2.value = 3
  tick(env)
  tick(env)
  text = texts(panel(env))
  A.eq(text:find("Not quite", 1, true), nil, "the tab sizes caught up a tick later: " .. text)
  A.eq(text:find("Dragon dagger", 1, true), nil, "the dagger is home: " .. text)
  PluginShutdown()
end

function T.a_right_move_is_accepted_when_the_games_tab_sizes_never_catch_up()
  local env = boot({ bank = { 103, 108, 101, 107, 109, 102 }, tabSizes = { 2, 2 } })
  pick(comboWith(panel(env), "tabs"), "tabs")
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  env.bank = { 103, 108, 109, 101, 107, 102 }
  settle(env); settle(env); settle(env)
  local text = texts(panel(env))
  A.eq(text:find("Not quite", 1, true), nil, text)
  A.eq(text:find("Dragon dagger", 1, true), nil, "no loop back to the dagger: " .. text)
  PluginShutdown()
end

function T.a_mistake_is_logged_for_diagnosis()
  local env = boot(MISTAKE_BANK)
  local lines = {}
  _G.log = function(line) lines[#lines + 1] = line end
  guideOnTab(env)
  env.bank = { 103, 101, 108 }
  settle(env)
  A.truthy(table.concat(lines, " | "):find("move check: step=insert", 1, true), table.concat(lines, " | "))
  A.truthy(PersistentDB.data["bank-organizer-debug"], "saved for PluginData.db")
  PluginShutdown()
end

function T.tabs_shown_in_a_different_order_than_stored()
  local env = boot({ bank = { 103, 108, 101, 107, 109, 102 }, tabSizes = { 2, 2 }, tabIcons = tabRow4() })
  env.display = { 109, 102, 101, 107, 103, 108 }
  pick(comboWith(panel(env), "tabs"), "tabs")
  tick(env)
  A.list(Store.new(PersistentDB).displayOrder, { 2, 1 }, "learned from the infinity view: stored tab 2 is shown first")
  find(panel(env), "AddSimpleButton", "Sorting Guide").args[2]()
  local text = texts(panel(env))
  A.truthy(text:find("Drag Dragon dagger onto Tab 3", 1, true), "the gear tab is the third button on screen: " .. text)
  tick(env)
  local box
  for _, c in ipairs(env.created) do if c.kind == "rect" and not c.destroyed and c.parent == env.layer then box = c end end
  A.eq(box.x, 100 + 2 * 48 - 2, "the arrow outlines the third button")
  env.bank = { 103, 108, 109, 101, 107, 102 }
  env.display = { 102, 101, 107, 103, 108, 109 }
  settle(env); settle(env)
  text = texts(panel(env))
  A.eq(text:find("Not quite", 1, true), nil, text)
  A.eq(text:find("Dragon dagger", 1, true), nil, "the dagger is home: " .. text)
  PluginShutdown()
end

function T.share_and_load_a_setup_from_the_sidebar()
  local env = boot()
  find(panel(env), "AddSimpleButton", "Share or Load a Setup").args[2]()
  local w = env.windows[#env.windows]
  local fields = {}
  for _, c in ipairs(w) do if c.method == "AddTextField" then fields[#fields + 1] = c end end
  A.truthy(fields[1].args[1].text:find("^BO1|"), "your code is shown to copy")
  fields[2].args[1].onSubmit(nil, "not a code")
  A.truthy(texts(env.windows[#env.windows]):find("not a Bank Organizer setup code", 1, true))
  w = env.windows[#env.windows]
  fields = {}
  for _, c in ipairs(w) do if c.method == "AddTextField" then fields[#fields + 1] = c end end
  fields[2].args[1].onSubmit(nil, "BO1|s=tabs|o=name|t=runes/gear|n=1:Weapons|p=")
  A.truthy(texts(env.windows[#env.windows]):find("Loaded a setup with 1 tab after infinity", 1, true))
  local store = Store.new(PersistentDB)
  A.eq(store:get("scope"), "tabs"); A.eq(store:get("sort"), "name"); A.eq(store.layout.names[1], "Weapons")
  PluginShutdown()
end

return T
