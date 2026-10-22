-- Bank Organizer tests: a stand-in game client for whole-plugin tests.
--
-- H.boot() fakes everything main.lua talks to (events, the bank interface,
-- item configs, vars, PrettyUI, PersistentDB), loads a fresh copy of the
-- plugin and opens the sidebar. Tests then press buttons by calling the
-- recorded callbacks, tick the game, and read back what was drawn.
--
-- PrettyUI is faked by "recorders": every Add... call on a view or window
-- is stored as { method, args } in a list, and returned so tests can call
-- its callbacks. This tests what the plugin asks PrettyUI to draw, not how
-- PrettyUI draws it.

local A = require("assert")

local H = {}

-- The fake bank's item catalogue: { id, name, right-click ops, extra }.
-- extra may set: tradeable (default true), cost (item value) and quests
-- (a list of fake quest configs { hasFinishedQuest = bool }).
H.ITEMS = {
  { 101, "Shark", { "Eat" } }, { 102, "Coins" }, { 103, "Abyssal whip", { "Wield" } },
  { 104, "Air rune" }, { 105, "Grimy guam" }, { 106, "Mystery thing" }, { 107, "Prayer potion (4)", { "Drink" } },
  { 108, "Rune scimitar", { "Wield" } },
  { 109, "Dragon dagger", { "Wield" } },
  { 110, "Ushabti" },
  { 111, "Prayer potion (3)", { "Drink" } },
  { 112, "Prayer potion (1)", { "Drink" } },
  { 113, "Super restore (2)", { "Drink" } },
  { 114, "Red partyhat", { "Wear" } },
  { 115, "Bronze dagger", { "Wield" }, { cost = 10 } },
  { 116, "Bucket", {}, { cost = 2 } },
  { 117, "Old quest note", {}, { tradeable = false, quests = { { hasFinishedQuest = true } } } },
  { 118, "Unfinished quest key", {}, { tradeable = false, quests = { { hasFinishedQuest = false } } } },
  { 119, "Rune platelegs", { "Wear" }, { cost = 64000 } },
  { 120, "Dragon bones", {}, { cost = 2000 } },
  { 121, "Strange relic", {}, { tradeable = false } },
}

-- Returns an in-memory PersistentDB stand-in.
function H.memoryDb()
  local db = { data = {} }
  -- Reads and writes go to the data table, which tests can inspect.
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  function db:SetString(key, value) self.data[key] = value end
  return db
end

-- Loads the plugin against a fake client.
--   opts.bank       list of item ids in bank order (default 101..107)
--   opts.tabSizes   sizes of custom tabs 2..15; nil = the client hides them
--   opts.allItems   false to start on a single tab instead of infinity
--   opts.frame      true to give the slots a scrolling parent viewport
--   opts.tabIcons   static id -> fake tab button component
--   opts.submenu    true to give PrettyUI a MiniMenu.AddSubmenu helper
--   opts.mouse      { x, y } mouse position in the game window, or nil for
--                   no readable mouse
--   opts.prices     item id -> GE price, to fake the GE Price Library
-- Returns env: the recorded calls and fake state.
function H.boot(opts)
  opts = opts or {}
  local env = { events = {}, created = {}, windows = {}, panels = {}, settings = {}, menu = {}, hidden = {},
    tabIcons = opts.tabIcons or {}, submenus = {} }
  env.bank = opts.bank or { 101, 102, 103, 104, 105, 106, 107 }
  env.tabSizes = opts.tabSizes
  env.allItems = opts.allItems ~= false
  local names = {}
  for _, row in ipairs(H.ITEMS) do names[row[1]] = row end
  -- A fake event bus: Subscribe stores the handler under "Bus:key".
  local function bus(name)
    return { Subscribe = function(k, f) env.events[name .. ":" .. k] = f end,
      -- Unsubscribe removes the handler.
      Unsubscribe = function(k) env.events[name .. ":" .. k] = nil end }
  end
  _G.Event = { ServerLogic = bus("Tick"), MiniMenuReady = bus("Menu"), ContentLayerReady = bus("Content"), SettingsLayerReady = bus("Settings") }
  -- Log lines are dropped; tests that check them replace log.
  _G.log = function() end
  _G.config = {
    Inv = { BANK = { id = 95 } },
    -- Item configs built from H.ITEMS.
    Obj = { FromID = function(id)
      local row = names[id]
      if not row then return nil end
      local extra = row[4] or {}
      local ops = {}
      for i, op in ipairs(row[3] or {}) do ops[i] = op end
      return { id = id, name = row[2], category = -1, interfaceOpNames = ops, quests = extra.quests or {},
        isTradeable = extra.tradeable ~= false, cost = extra.cost }
    end },
  }
  -- The bank inventory: one stack of 1 per listed id.
  _G.Inventory = { Find = function()
    local slots = {}
    for i, id in ipairs(env.bank) do slots[i] = { obj = { id = id }, count = 1 } end
    return { isValid = true, GetSlots = function() return slots end }
  end }
  -- The slot container. scrollY lives on it, or on the parent viewport
  -- (env.frame) when opts.frame is set, like the real bank.
  local container = setmetatable({ visibleGlobal = true, width = 400, height = opts.frame and 2000 or 600, xyGlobal = { x = 100, y = 100 } },
    { __index = function(_, key)
      if key == "scrollY" then return opts.frame and 0 or (env.scroll or 0) end
      if key == "scrollX" then return 0 end
    end })
  if opts.frame then
    env.frame = setmetatable({ xyGlobal = { x = 100, y = 100 }, width = 400, height = 300, scrollHeight = 2000 },
      { __index = function(_, key)
        if key == "scrollY" then return env.scroll or 0 end
        if key == "scrollX" then return 0 end
      end })
  end
  -- The plugin layer windows open on: the whole 1280 by 720 game window.
  env.layer = { kind = "layer", xyGlobal = { x = 0, y = 0 }, width = 1280, height = 720 }
  -- A stand-in for the client's Mouse table.
  _G.Mouse = {
    -- Readable only when the test gives a position.
    IsAvailable = function() return opts.mouse ~= nil end,
    GetPosition = function() return opts.mouse end,
  }
  -- Static components of the bank interface: 0 = slots, 399 = viewport,
  -- anything else = a tab button from opts.tabIcons.
  local function bankStatic(staticID)
    if staticID == 0 then return container end
    if staticID == 399 then return env.frame end
    return env.tabIcons[staticID]
  end
  -- Visits each visible slot, 8 per row, 40 pixels apart. env.display,
  -- env.displayIndex, env.view and env.hidden change what is on screen.
  function container:IterateDynamicComponents(fn)
    for i, id in ipairs(env.bank) do
      local position = i
      for index, shown in ipairs(env.display or {}) do if shown == id then position = index end end
      if env.displayIndex then position = env.displayIndex[i] end
      local x, y = ((position - 1) % 8) * 40, ((position - 1) // 8) * 40
      local onScreen = true
      if env.view then
        onScreen = false
        for _, shown in ipairs(env.view) do if shown == id then onScreen = true end end
      end
      if onScreen and not env.hidden[id] and fn({ type = 5, associatedObjectID = id, visible = true, hidden = false, x = x, y = y,
        xyGlobal = { x = 100 + x, y = 100 + y },
        width = 36, height = 32, associatedObjectQuantity = 1, interfaceID = 517 }) then return end
    end
  end
  -- Overlay components (rectangles, text, lines) are recorded in env.created.
  local function component(kind)
    local c = { kind = kind }
    -- Position, size and destruction are recorded on the component.
    function c:SetPos(x, y) self.x, self.y = x, y end
    function c:SetSize(w, h) self.w, self.h = w, h end
    function c:Destroy() self.destroyed = true end
    env.created[#env.created + 1] = c
    return c
  end
  _G.ui = {
    ComponentType = { SPRITE = 5 }, SelectionChangeEvent = { SELECTED = 1 }, AlignMode = { TOPLEFT = 1, CENTRE = 2, BOTTOMRIGHT = 3 },
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
    Font = { MUSEO_SANS_15PT_REGULAR = 1, MUSEO_SANS_11PT_REGULAR = 2 }, Category = { FromID = function() return nil end } }
  _G.var = {
    VarPlayer = { BANK_CURRENT_TAB = { value = env.allItems and 1 or 3 } },
    VarClient = { BANK_SEARCHMODE_CLIENT = { value = 0 } },
  }
  _G.Vector4 = { new = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
  _G.PersistentDB = H.memoryDb()
  -- The GE Price Library, only when the test gives prices.
  if opts.prices then
    _G.gepl = {
      -- Prices are always loaded.
      isReady = function() return true end,
      -- The same price as both the high and the low trade.
      getLatest = function(itemID) local p = opts.prices[itemID]; return p and { high = p, low = p } or nil end,
    }
  else
    _G.gepl = nil
  end
  -- A recorder: any method call is stored in list as { method, args } and
  -- returned. AddText and AddTitle also store their text as content.
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
    -- Each recording keeps its view or window object as .view, so a test can
    -- scroll it.
    SimpleView = { new = function(parent)
      local l = {}; local t = parent.kind == "settings" and env.settings or env.panels; t[#t + 1] = l
      l.view = recorder(l)
      return l.view
    end },
    -- Windows are recorded the same way, with their options.
    Window = { new = function(_, options)
      local l = { options = options }; env.windows[#env.windows + 1] = l
      l.view = recorder(l)
      return l.view
    end },
    Confirm = { new = function(_, o) env.confirm = o end },
  }
  if opts.submenu then
    prettyui.MiniMenu = { AddSubmenu = function(menu, label, children, options)
      env.submenus[#env.submenus + 1] = { menu = menu, label = label, children = children, options = options }
    end }
  end
  -- Forget every loaded plugin module so each boot starts fresh.
  for key in pairs(package.loaded) do if key:match("^src/") then package.loaded[key] = nil end end
  if env.tabSizes then
    for i = 2, 15 do var.VarPlayer["BANK_TAB" .. i] = { value = env.tabSizes[i - 1] or 0 } end
  end
  dofile("main.lua")
  env.events["Content:bank-organizer:content"]({ component = { kind = "content", width = 300, height = 800 } })
  return env
end

-- Returns the latest sidebar recording.
function H.panel(env) return env.panels[#env.panels] end

-- Returns the latest window recording.
function H.window(env) return env.windows[#env.windows] end

-- Joins every text and title in a recording into one string.
function H.texts(calls)
  local out = {}
  for _, c in ipairs(calls or {}) do if c.content then out[#out + 1] = c.content end end
  return table.concat(out, "\n")
end

-- Finds the first recorded call of a method (and with a given first
-- argument, when label is given).
function H.find(calls, method, label)
  for _, c in ipairs(calls) do if c.method == method and (label == nil or c.args[1] == label) then return c end end
end

-- Returns every recorded call of a method.
function H.findAll(calls, method)
  local out = {}
  for _, c in ipairs(calls) do if c.method == method then out[#out + 1] = c end end
  return out
end

-- Runs one game tick.
function H.tick(env) env.events["Tick:bank-organizer:tick"]() end

-- Picks the entry with the given key in a recorded dropdown.
function H.pick(combo, key)
  for _, entry in ipairs(combo.args[1].entries) do
    if entry.key == key then return combo.args[1].onChange(nil, entry.id, entry.label, 1) end
  end
  error("no entry " .. tostring(key))
end

-- Returns the first recorded dropdown that offers the given key.
function H.comboWith(calls, key)
  for _, c in ipairs(calls) do
    if c.method == "AddComboBox" then
      for _, entry in ipairs(c.args[1].entries) do if entry.key == key then return c end end
    end
  end
end

-- Fails when any dropdown in a recording has a non-integer entry id; the
-- native ComboBox only accepts whole numbers.
function H.assertIntegerIds(calls)
  for _, c in ipairs(calls) do
    if c.method == "AddComboBox" then
      for _, entry in ipairs(c.args[1].entries) do A.eq(math.type(entry.id), "integer", "combo ids must be integers") end
      A.eq(math.type(c.args[1].selectedID), "integer", "selected id must be an integer")
    end
  end
end

-- Opens a right-click menu on a bank item and returns the entries the
-- plugin added with menu:Add (the fallback path).
function H.rightClick(env, itemID)
  local added = {}
  local menu = { entries = { { componentData = { component = { interfaceID = 517, associatedObjectID = itemID } } } } }
  -- Records what the plugin adds with menu:Add.
  function menu:Add(label, fn) added[#added + 1] = { label = label, fn = fn } end
  env.events["Menu:bank-organizer:menu"]({ miniMenu = menu })
  return added
end

-- Opens an item's Tags window and returns its recording.
function H.tagsWindow(env, itemID)
  H.rightClick(env, itemID)[1].fn()
  return env.windows[#env.windows]
end

-- Ticks or unticks Ignore for an item through its Tags window.
function H.setIgnore(env, itemID, on)
  H.find(H.tagsWindow(env, itemID), "AddCheckboxButton").args[2].onChange(nil, nil, "ignore", on)
end

-- Returns the Tags window's tag checkboxes (the second checkbox group).
function H.tagBoxes(window)
  return H.findAll(window, "AddCheckboxButton")[2]
end

-- Ticks (on = true, the default) or unticks one tag on an item through its
-- Tags window.
function H.setPlacement(env, itemID, key, on)
  H.tagBoxes(H.tagsWindow(env, itemID)).args[2].onChange(nil, nil, key, on ~= false)
end

-- Returns the text of every overlay label still on screen.
function H.liveTexts(env)
  local out = {}
  for _, c in ipairs(env.created) do if c.kind == "text" and not c.destroyed then out[#out + 1] = c.content end end
  return out
end

-- Counts how many times value appears in list.
function H.count(list, value)
  local n = 0
  for _, v in ipairs(list) do if v == value then n = n + 1 end end
  return n
end

-- Opens the plugin's settings in the game's settings layer on a page and
-- returns the recorded settings view.
function H.settingsPage(env, page)
  env.events["Settings:bank-organizer:settings"]({ component = { kind = "settings", width = 300, height = 800 } })
  local button = H.find(env.settings[#env.settings], "AddSimpleButton", page)
  if button then button.args[2]() end
  return env.settings[#env.settings]
end

-- Presses the sidebar button with the given label (simple or fancy).
function H.press(env, label)
  local p = H.panel(env)
  local button = H.find(p, "AddSimpleButton", label) or H.find(p, "AddFancyButton", label)
  assert(button, "no sidebar button " .. label)
  button.args[2]()
end

-- Presses a button with the given label in the latest window.
function H.pressIn(env, label)
  local button = H.find(H.window(env), "AddSimpleButton", label)
  assert(button, "no window button " .. label .. " in " .. tostring(H.window(env).options.title))
  button.args[2]()
end

-- Submits text in the n-th text field (default the first) of the latest
-- window.
function H.submit(env, text, n)
  local field = H.findAll(H.window(env), "AddTextField")[n or 1]
  assert(field, "no text field")
  field.args[1].onSubmit(nil, text)
end

return H
