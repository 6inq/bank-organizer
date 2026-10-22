-- Bank Organizer: the pop-up windows.
--
--   Blueprint          the plan, one tab at a time, with item icons
--   Tab Layout         a rail of tab buttons; the chosen tab's kinds, items
--                      and buttons below (Whole bank and My tabs versions)
--   Share or Load      share codes (src/core/preset.lua)
--   Tags               an item's kind, its tags, Ignore and Decant opt-out;
--                      opens next to the mouse from the right-click entry
--   Custom categories  make categories, name rules and the review list
--   Custom tags        make tags and order the tag priority list
--   Bank Cleaner       suggestions with reasons; ticking tags an item
--
-- Windows are PrettyUI Windows on the plugin's top layer. Each one is drawn
-- by a build function; after any change the window is simply rebuilt by
-- opening it again with the same name, which replaces the old one.

local Tags = require("src/core/tags")
local Tagging = require("src/game/tagging")
local Combo = require("src/ui/combo")
local Preset = require("src/core/preset")
local Placement = require("src/core/placement")
local Classify = require("src/core/classify")
local Custom = require("src/core/custom")
local Cleaner = require("src/core/cleaner")
local Widgets = require("src/ui/widgets")

local Windows = {}

-- Open windows by name, so each one can be replaced or closed.
local open = {}

-- What each window was showing, kept between rebuilds:
--   blueprintTab  tab shown in the Blueprint
--   layoutTab     tab chosen in the Tab Layout rail
--   layoutNote    one-off message shown at the top of the Tab Layout
--   presetNote    one-off message in Share or Load
--   categoryKey   custom category being edited
--   ruleKind      rule kind chosen for the next name rule
--   categoryNote  one-off message in Custom categories
--   tagKey        custom tag being edited
--   newPlacement  placement chosen for the next new tag
--   tagNote       one-off message in Custom tags
--   cleanerNote   one-off message in the Bank Cleaner
--   sections      collapsed sections: key -> true
local state = { ruleKind = "contains", newPlacement = "bottom", sections = {} }


-- Columns in the item icon grids.
local GRID_COLUMNS = 8

-- Every window is this wide, so the hint text wraps the same way.
local WIDTH = 470

-- Returns the layer windows are drawn on, or nil when it is not available.
local function host()
  local ok, layer = pcall(function()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
  end)
  if ok then return layer end
  return nil
end

-- Closes one window by name (if it is open).
function Windows.close(name)
  local window = open[name]
  open[name] = nil
  if window then pcall(function() return window:Destroy() end) end
end

-- Closes every window (on shutdown).
function Windows.closeAll()
  for name in pairs(open) do Windows.close(name) end
end

-- How much room (pixels) a window leaves below it when it has to be made
-- shorter to fit the game, so it can always be dragged a little.
local FIT_MARGIN = 40

-- The shortest (pixels) a window is ever made. Its content scrolls, so
-- nothing is lost when it is shorter than it asked for.
local MIN_HEIGHT = 240

-- Returns where an open window is now as { x, y } (pixels, relative to the
-- plugin layer), or nil when it cannot be read. PrettyUI moves the window's
-- root component while the player drags it, so root.x and root.y are the
-- dragged position. Read through pcall: a destroyed component throws.
local function positionOf(window)
  local ok, x, y = pcall(function() return window.root.x, window.root.y end)
  if ok and type(x) == "number" and type(y) == "number" then return { x = x, y = y } end
  return nil
end

-- Makes a window fit inside the plugin layer so it can be dragged.
--   layer    the plugin layer (its width and height are the game's size)
--   options  the PrettyUI Window options; height, x and y are changed in place
-- PrettyUI keeps a dragged window inside the layer by limiting its top to
-- between 0 and (layer height - window height). When the window is taller
-- than the layer that limit is below 0, so the window is pinned and cannot
-- move. So a window that is too tall is made shorter (its content scrolls),
-- and a position off the edge is pulled back on. When the layer's size
-- cannot be read the options are left as they are.
local function fitOnLayer(layer, options)
  local ok, width, height = pcall(function() return layer.width, layer.height end)
  if not ok or type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return end
  options.height = math.max(MIN_HEIGHT, math.min(options.height, height - FIT_MARGIN))
  options.x = math.max(0, math.min(options.x or 0, width - options.width))
  options.y = math.max(0, math.min(options.y or 0, height - options.height))
end

-- Returns true when the named window is open.
function Windows.isOpen(name)
  return open[name] ~= nil
end

-- Opens (or replaces) a window.
--   name     the window's name in the open table
--   options  PrettyUI Window options (title, width, height, x, y)
--   build    function(window) that adds the window's content
-- A failing build is logged and leaves a partly drawn window rather than
-- breaking the plugin. A window that is rebuilt keeps its place and scroll,
-- and every window is fitted inside the game (see fitOnLayer). Returns the
-- window, or nil when there is no layer.
function Windows.open(name, options, build)
  local previous = open[name]
  -- A window redrawn after a change keeps its scroll position.
  local scrolled = previous and Widgets.scrollOf(previous) or 0
  -- It also stays where the player dragged it, instead of jumping back to
  -- the spot it first opened at.
  local at = previous and positionOf(previous)
  if at then options.x, options.y = at.x, at.y end
  Windows.close(name)
  local layer = host()
  if not layer then return nil end
  fitOnLayer(layer, options)
  -- Forget the window when the player closes it with its own X button.
  options.onClose = function() open[name] = nil end
  options.destroyOnClose = true
  local window = prettyui.Window.new(layer, options)
  open[name] = window
  local ok, err = pcall(build, window)
  if not ok and log then log("[bank-organizer] " .. name .. " window failed: " .. tostring(err)) end
  Widgets.restoreScroll(window, scrolled)
  return window
end

-- Asks the player to confirm before a change that cannot be undone.
--   title, body, label  the dialog's heading, question and button text
--   onConfirm           function() run only when the player confirms
function Windows.confirm(title, body, label, onConfirm)
  local layer = host()
  if not layer then return end
  prettyui.Confirm.new(layer, { title = title, body = body, confirmLabel = label, onConfirm = onConfirm })
end

-- Returns the client's item config for an id (used for icons), or nil.
local function objectOf(itemID)
  local ok, obj = pcall(function() return config.Obj.FromID(itemID) end)
  if ok then return obj end
  return nil
end

-- Returns an item's display name, or "item <id>" when it cannot be read.
local function nameOf(itemID)
  local obj = objectOf(itemID)
  return obj and obj.name or ("item " .. tostring(itemID))
end

-- Adds an icon grid for a list of planned entries.
--   entries  list of { objectId or id, name, quantity, tag }
local function itemGrid(window, entries)
  local objects = {}
  for i, entry in ipairs(entries) do
    objects[i] = { object = objectOf(entry.objectId or entry.id), quantity = entry.quantity,
      tooltip = entry.name .. (entry.tag and (" (" .. Tags.label(entry.tag) .. ")") or "") }
  end
  if #objects == 0 then return end
  window:AddItemGrid(objects, { columns = GRID_COLUMNS, rows = math.max(1, math.ceil(#objects / GRID_COLUMNS)) })
end

-- Returns the tabs that have at least one planned item.
local function filledTabs(app)
  local list = {}
  for _, d in ipairs(app:destinationList()) do
    if #(app.destinations[d] or {}) > 0 then list[#list + 1] = d end
  end
  return list
end

-- Returns the position of value in list, or nil.
local function indexOf(list, value)
  for index, item in ipairs(list) do if item == value then return index end end
  return nil
end

-- The Blueprint window: pick a tab (dropdown or Previous/Next) and see its
-- planned items in order.
function Windows.blueprint(app)
  return Windows.open("blueprint", { title = "Blueprint", width = WIDTH, height = 560, x = 60, y = 60 }, function(window)
    if not app.destinations then
      window:AddText("Press Analyze Bank first.")
      return
    end
    local tabs = filledTabs(app)
    if #tabs == 0 then
      window:AddText("Your bank is empty.")
      return
    end
    local index = indexOf(tabs, state.blueprintTab) or 1
    state.blueprintTab = tabs[index]
    local choices = {}
    for i, d in ipairs(tabs) do
      choices[i] = { label = app:destinationTitle(d) .. "  (" .. #app.destinations[d] .. ")", key = d }
    end
    window:AddComboBox(Combo.options(choices, state.blueprintTab, function(d)
      state.blueprintTab = d
      Windows.blueprint(app)
    end))
    -- Previous and Next wrap around at either end.
    Widgets.buttonRow(window, {
      { "Previous", function()
        state.blueprintTab = tabs[index > 1 and index - 1 or #tabs]
        Windows.blueprint(app)
      end },
      { "Next", function()
        state.blueprintTab = tabs[index < #tabs and index + 1 or 1]
        Windows.blueprint(app)
      end },
    }, WIDTH)
    local entries = app.destinations[state.blueprintTab]
    window:AddText(string.format("Tab %d of %d: %d items", index, #tabs, #entries))
    Widgets.muted(window, app:kindsSummary(state.blueprintTab))
    itemGrid(window, entries)
  end)
end

-- Adds the row of tab buttons along the top of the Tab Layout.
--   list      tab positions to show
--   selected  the chosen position
--   onPick    function(position)
-- Buttons read 1, 2, 3 ... like the game's own tab numbers; the chosen one
-- is in square brackets. They wrap onto more rows when they do not fit.
local function rail(window, list, selected, onPick)
  local buttons = {}
  for index, d in ipairs(list) do
    local label = tostring(d + 1)
    if d == selected then label = "[" .. label .. "]" end
    buttons[index] = { label, function() onPick(d) end }
  end
  Widgets.buttonRow(window, buttons, WIDTH)
end

-- Returns the dropdown choices for adding a kind to tab d (Whole bank).
-- Each choice says which tab the kind is in now.
local function tagChoicesFor(layout, d)
  local list = { { label = "Add a kind here...", key = "none" } }
  for _, tag in ipairs(Tags.LIST) do
    local current = layout:destinationOf(tag.key)
    if current ~= d then
      list[#list + 1] = { label = tag.label .. "  (" .. Tags.destinationName(current) .. ")", key = tag.key }
    end
  end
  return list
end

-- Returns the dropdown choices for pinning a kind to tab d (My tabs).
local function pinChoicesFor(app, d)
  local list = { { label = "Pin a kind here...", key = "none" } }
  for _, tag in ipairs(Tags.LIST) do
    local home = app:tabHomeOf(tag.key)
    if home ~= d then
      list[#list + 1] = { label = tag.label .. "  (" .. (home and app:tabName(home) or "stays put") .. ")", key = tag.key }
    end
  end
  return list
end

-- Adds the planned items of tab d as icons, when the bank was analyzed.
local function plannedItems(app, window, d)
  local entries = app.destinations and app.destinations[d]
  if not entries then return end
  window:AddText("Planned items (" .. #entries .. ")")
  itemGrid(window, entries)
end

-- Draws the My tabs version of the Tab Layout: pins and tab moves.
--   changed  function() to call after any change (saves and redraws)
local function tabLayout(app, window, changed)
  Widgets.muted(window, "Pick a tab. Pin a kind of item to it and everything of that kind goes there. Remove sends a kind back to Tab 1 (infinity). Move left and Move right swap whole tabs; the guide then shows you the one drag to make.")
  if not app:myTabs() then
    window:AddText("Press Analyze Bank first.")
    return
  end
  local list = app:destinationList()
  local d = indexOf(list, state.layoutTab) and state.layoutTab or list[1]
  state.layoutTab = d
  rail(window, list, d, function(picked) state.layoutTab = picked; changed() end)
  window:AddTitle(app:destinationTitle(d))
  Widgets.muted(window, app:kindsSummary(d))
  for _, tag in ipairs(Tags.LIST) do
    local home, pinned = app:tabHomeOf(tag.key)
    if home == d then
      local buttons = {}
      if pinned then
        buttons[#buttons + 1] = { "Unpin", function() app.store:clearTabHome(tag.key); changed() end }
      end
      if d > 0 then
        buttons[#buttons + 1] = { "Remove", function() if app.store:setTabHome(tag.key, 0) then changed() end end }
      end
      Widgets.textWithButtons(window, tag.label .. (pinned and "  (pinned)" or "  (auto)"), buttons, WIDTH)
    end
  end
  if d == 0 then Widgets.muted(window, "Plus anything no other tab collects.") end
  window:AddComboBox(Combo.options(pinChoicesFor(app, d), "none", function(key)
    if key ~= "none" and app.store:setTabHome(key, d) then changed() end
  end))
  plannedItems(app, window, d)
  Widgets.divider(window)
  -- Bottom bar. A tab move keeps the moved tab chosen.
  local buttons = {}
  if d > 0 then
    buttons[#buttons + 1] = { "Move left", function() if app:moveMyTab(d, -1) then changed() end end }
    buttons[#buttons + 1] = { "Move right", function() if app:moveMyTab(d, 1) then changed() end end }
  end
  buttons[#buttons + 1] = { "Unpin all", function() app.store:resetTabHomes(); changed() end }
  buttons[#buttons + 1] = { "Keep my tab order", function() app:resetMyTabOrder(); changed() end }
  Widgets.buttonRow(window, buttons, WIDTH)
end

-- Draws the chosen tab's details in the Whole bank Tab Layout.
local function layoutTab(app, window, layout, d, changed)
  -- The tab's own name is shown in the field below, where it can be long.
  window:AddTitle(Tags.destinationName(d))
  window:AddTextField({
    text = layout.names[d] or "", placeholder = "Name this tab, then press Enter",
    -- Enter saves the new name (an empty name clears it).
    onSubmit = function(_, content) if layout:rename(d, content) then changed() end end,
  })
  -- Each kind with buttons to reorder it or send it back to Storage & Cleanup.
  for _, key in ipairs(layout.destinations[d]) do
    Widgets.textWithButtons(window, Tags.label(key), {
      { "Up", function() if layout:shiftTag(key, -1) then changed() end end },
      { "Down", function() if layout:shiftTag(key, 1) then changed() end end },
      { "Remove", function() if layout:removeTag(key) then changed() end end },
    }, WIDTH)
  end
  window:AddComboBox(Combo.options(tagChoicesFor(layout, d), "none", function(key)
    if key ~= "none" and layout:moveTag(key, d) then changed() end
  end))
  plannedItems(app, window, d)
end

-- Draws the Whole bank version of the Tab Layout.
local function bankLayout(app, window, changed)
  local layout = app.store.layout
  Widgets.muted(window, "Your tabs in bank order, left to right. Pick a tab to name it, move it and choose which kinds of item it holds. Remove sends a kind to wherever Storage & Cleanup lives.")
  if state.layoutNote then
    window:AddText({ text = state.layoutNote })
    state.layoutNote = nil
  end
  local list = {}
  for d = 0, layout:last() do list[#list + 1] = d end
  local d = (state.layoutTab and state.layoutTab <= layout:last()) and state.layoutTab or 0
  state.layoutTab = d
  rail(window, list, d, function(picked) state.layoutTab = picked; changed() end)
  layoutTab(app, window, layout, d, changed)
  Widgets.divider(window)
  -- Bottom bar. Moving a tab keeps it chosen; deleting chooses its left
  -- neighbour.
  local buttons = {
    { "Add tab", function()
      if layout:addTab() then state.layoutTab = layout:last() else state.layoutNote = "RS3 banks have at most 14 custom tabs." end
      changed()
    end },
  }
  if d > 0 then
    buttons[#buttons + 1] = { "Delete tab", function()
      if layout:removeTab(d) then state.layoutTab = d - 1 end
      changed()
    end }
    buttons[#buttons + 1] = { "Move left", function() if layout:moveTab(d, -1) then state.layoutTab = d - 1 end; changed() end }
    buttons[#buttons + 1] = { "Move right", function() if layout:moveTab(d, 1) then state.layoutTab = d + 1 end; changed() end }
  end
  Widgets.buttonRow(window, buttons, WIDTH)
  Widgets.buttonRow(window, {
    { "Copy my current tabs", function()
      if not app:copyCurrentTabs() then state.layoutNote = "Open your bank and press Analyze Bank first, so your tabs can be read." end
      changed()
    end },
    { "Reset to default", function() layout:reset(); changed() end },
  }, WIDTH)
end

-- Opens the Tab Layout window for the current organize mode.
function Windows.layout(app)
  -- After any change: save, rebuild the plan and redraw this window.
  local function changed()
    app.store:save()
    app:rebuild()
    Windows.layout(app)
  end
  if app.store:get("scope") == "tabs" then
    return Windows.open("layout", { title = "Tab Layout (My tabs)", width = WIDTH, height = 620, x = 120, y = 60 }, function(window)
      tabLayout(app, window, changed)
    end)
  end
  return Windows.open("layout", { title = "Tab Layout", width = WIDTH, height = 620, x = 120, y = 60 }, function(window)
    bankLayout(app, window, changed)
  end)
end

-- The Share or Load a Setup window.
function Windows.presets(app)
  return Windows.open("presets", { title = "Share or Load a Setup", width = WIDTH, height = 440, x = 140, y = 80 }, function(window)
    window:AddTitle("Share my setup")
    Widgets.muted(window, "Copy this code and post it anywhere. It holds your tabs, their names, the kinds of item in each, your pins, your custom categories and tags, how you organize and how you sort. Tags on single items stay yours.")
    window:AddTextField({ text = Preset.encode(app.store) })
    window:AddTitle("Load a setup")
    Widgets.muted(window, "Paste a code someone shared, then press Enter. Your current setup is replaced.")
    if state.presetNote then
      window:AddText({ text = state.presetNote })
      state.presetNote = nil
    end
    window:AddTextField({
      placeholder = "Paste a setup code here",
      -- Enter loads the pasted code, or explains why it cannot.
      onSubmit = function(_, content)
        local preset, reason = Preset.decode(content)
        if preset then
          local last = Preset.apply(app.store, preset)
          state.presetNote = string.format("Loaded a setup with %d tab%s after infinity.", last, last == 1 and "" or "s")
          app:rebuild()
        else
          state.presetNote = reason
        end
        Windows.presets(app)
      end,
    })
  end)
end

-- Adds the kind-of-item dropdown for one item. Picking "Use automatic
-- classification" forgets the hand-picked kind.
--   reopen  function() that redraws the window afterwards
local function categoryCombo(app, window, itemID, reopen)
  local current = app.store.corrections[itemID]
  window:AddComboBox(Combo.options(Tagging.choices(), current or "auto", function(key)
    if key == "auto" then app.store:clearCorrection(itemID) else app.store:correct(itemID, key) end
    app:rebuild()
    reopen()
  end))
end

-- The Tags window's size, in pixels.
local TAGS_WIDTH, TAGS_HEIGHT = 340, 520

-- How far from the mouse the Tags window opens, in pixels, so the cursor
-- does not sit on its title bar.
local MOUSE_GAP = 16

-- Where the Tags window opens when the mouse cannot be read.
local TAGS_DEFAULT = { x = 200, y = 120 }

-- Returns a position for the Tags window just right of and below the mouse,
-- relative to the plugin layer, kept fully on screen. Returns nil when the
-- mouse cannot be read (for example on mobile), so the default is used.
function Windows.nearMouse()
  local ok, mouse = pcall(function()
    if not Mouse.IsAvailable() then return nil end
    return Mouse.GetPosition()
  end)
  if not ok or not mouse then return nil end
  local layer = host()
  local ox, oy, width, height = 0, 0, nil, nil
  -- The mouse is measured from the game window; the layer may start elsewhere.
  pcall(function()
    ox, oy = layer.xyGlobal.x, layer.xyGlobal.y
    width, height = layer.width, layer.height
  end)
  local x, y = mouse.x - ox + MOUSE_GAP, mouse.y - oy + MOUSE_GAP
  -- Near the right or bottom edge, open on the other side of the mouse.
  if type(width) == "number" and width > 0 and x + TAGS_WIDTH > width then x = math.max(0, mouse.x - ox - MOUSE_GAP - TAGS_WIDTH) end
  if type(height) == "number" and height > 0 and y + TAGS_HEIGHT > height then y = math.max(0, height - TAGS_HEIGHT) end
  return { x = math.floor(x), y = math.floor(y) }
end

-- The Tags window for one item: category, Ignore, Decant opt-out and every
-- tag, all set with a click. It stays open until the player closes it.
--   itemID    the item's real id
--   position  optional { x, y } (see Windows.nearMouse); redraws after a
--             change keep the window where it is
function Windows.tags(app, itemID, position)
  local name = nameOf(itemID)
  local at = position or TAGS_DEFAULT
  -- Redraws this window in the same place after a change.
  local function reopen() Windows.tags(app, itemID, at) end
  -- The item's name goes in the window, where it can wrap, not in the title
  -- bar, where a long name would be cut off.
  return Windows.open("tags", { title = "Tags", width = TAGS_WIDTH, height = TAGS_HEIGHT, x = at.x, y = at.y }, function(window)
    -- The item itself, so it is clear what is being tagged.
    window:AddItemGrid({ { object = objectOf(itemID), tooltip = name } }, { columns = 1, rows = 1 })
    window:AddText(name)
    window:AddText("Category")
    categoryCombo(app, window, itemID, reopen)
    Widgets.muted(window, "Your choice always wins over automatic sorting.")
    -- Ignore, and for potions with a dose the Decant opt-out.
    local boxes = { { text = "Ignore (never move this item)", value = "ignore", selected = app:isIgnored(itemID) } }
    if Classify.dose(name) then
      boxes[#boxes + 1] = { text = "Never label for decanting", value = "nodecant", selected = app.store:isNoDecant(itemID) }
    end
    window:AddCheckboxButton(boxes, { onChange = function(_, _, changed, selected)
      if changed == "nodecant" then
        app:setNoDecant(itemID, selected)
      elseif selected ~= app:isIgnored(itemID) then
        app:toggleIgnore(itemID)
      end
      reopen()
    end })
    -- Every tag, in priority order, ticked when the item carries it.
    window:AddTitle("Tags")
    local tags = {}
    for _, key in ipairs(app.store.tagOrder) do
      local def = Placement.byKey[key]
      if def then
        tags[#tags + 1] = { text = def.label .. "  (" .. Placement.describe(key) .. ")", value = key, selected = app.store:hasTag(itemID, key) }
      end
    end
    window:AddCheckboxButton(tags, { onChange = function(_, _, changed, selected)
      app:setTag(itemID, changed, selected)
      reopen()
    end })
    Widgets.muted(window, "An item can have several tags. The highest one in Tools, Custom tags decides where it goes.")
  end)
end

-- Adds one review-list section of the Custom categories window.
--   rows    list of { objectId, name }
--   suffix  text after each name (may be "")
--   button  optional { label, fn(objectId) } added beside each row
local function reviewRows(window, rows, suffix, button)
  for _, row in ipairs(rows) do
    local buttons = button and { { button.label, function() button.fn(row.objectId) end } } or {}
    Widgets.textWithButtons(window, row.name .. suffix, buttons, WIDTH)
  end
end

-- Draws the chosen category's editor: name, colour, rules, review list and
-- delete.
local function categoryEditor(app, window, def, reopen)
  local store = app.store
  -- After a change that affects classification: rebuild, then redraw.
  local function changed() app:rebuild(); reopen() end
  -- The name itself is in the field below, where it can be long.
  window:AddTitle("Edit category")
  window:AddTextField({ text = def.name, placeholder = "Rename, then press Enter", onSubmit = function(_, text)
    if not store:editCategory(def.key, { name = text }) then state.categoryNote = "A category needs a name." end
    changed()
  end })
  window:AddText("Colour")
  window:AddColourPicker({ value = def.colour, onChange = function(_, colour) store:editCategory(def.key, { colour = colour }); app:rebuild() end })
  Widgets.section(window, state.sections, "rules", "Name rules (" .. #def.rules .. ")", reopen, function()
    Widgets.muted(window, "Items whose names match a rule join this category automatically. Upper and lower case are ignored.")
    for index, rule in ipairs(def.rules) do
      local kind = rule.kind == "starts" and "Name starts with" or "Name contains"
      Widgets.textWithButtons(window, kind .. ": " .. rule.text, {
        { "Remove", function() store:removeRule(def.key, index); changed() end },
      }, WIDTH)
    end
    window:AddComboBox(Combo.options(Custom.RULE_KINDS, state.ruleKind, function(kind) state.ruleKind = kind; reopen() end))
    window:AddTextField({ placeholder = "Words to look for, then press Enter", onSubmit = function(_, text)
      if not store:addRule(def.key, state.ruleKind, text) then state.categoryNote = "Type some words for the rule first." end
      changed()
    end })
  end)
  local review = app:categoryReview(def.key)
  local total = #review.matched + #review.removed + #review.byHand
  Widgets.section(window, state.sections, "review", "Review list (" .. total .. ")", reopen, function()
    if not app.items then
      Widgets.muted(window, "Press Analyze Bank to see which items in your bank the rules match.")
      return
    end
    Widgets.muted(window, "Items your rules added. Remove keeps an item out even though a rule matches it.")
    reviewRows(window, review.matched, "", { label = "Remove", fn = function(objectId) store:exclude(def.key, objectId); changed() end })
    reviewRows(window, review.removed, "  (removed)", { label = "Restore", fn = function(objectId) store:restore(def.key, objectId); changed() end })
    reviewRows(window, review.byHand, "  (picked by hand)")
    if total == 0 then Widgets.muted(window, "No items in your bank match yet.") end
  end)
  Widgets.divider(window)
  window:AddSimpleButton("Delete category", function()
    Windows.confirm("DELETE CATEGORY", "Delete " .. def.name .. "? Its items go back to automatic sorting.", "DELETE", function()
      store:deleteCategory(def.key)
      state.categoryKey = nil
      changed()
    end)
  end)
end

-- The Custom categories window: a row of category buttons, a field to make
-- a new one, and the chosen category's editor.
function Windows.categories(app)
  -- Redraws this window after a change.
  local function reopen() Windows.categories(app) end
  return Windows.open("categories", { title = "Custom categories", width = WIDTH, height = 640, x = 160, y = 60 }, function(window)
    local store = app.store
    Widgets.muted(window, "Make your own kinds of item. New categories start in Tab 1 (infinity); move them in Tab Layout.")
    if state.categoryNote then
      window:AddText({ text = state.categoryNote })
      state.categoryNote = nil
    end
    window:AddTextField({ placeholder = "New category name, then press Enter", onSubmit = function(_, text)
      local key = store:addCategory(text)
      if key then
        state.categoryKey = key
        app:rebuild()
      else
        state.categoryNote = "Type a name first (you can have up to " .. Custom.MAX_CATEGORIES .. " categories)."
      end
      reopen()
    end })
    if #store.customCategories == 0 then
      Widgets.muted(window, "No custom categories yet.")
      return
    end
    local def = store:category(state.categoryKey) or store.customCategories[1]
    state.categoryKey = def.key
    -- One button per category; the chosen one is in square brackets. They
    -- wrap onto more rows when they do not fit.
    local buttons = {}
    for index, other in ipairs(store.customCategories) do
      local label = other.key == def.key and ("[" .. other.name .. "]") or other.name
      buttons[index] = { label, function() state.categoryKey = other.key; reopen() end }
    end
    Widgets.buttonRow(window, buttons, WIDTH)
    Widgets.divider(window)
    categoryEditor(app, window, def, reopen)
  end)
end

-- Returns the dropdown choices for a custom tag's placement.
local function placementChoices()
  local list = {}
  for index, placement in ipairs(Custom.PLACEMENTS) do list[index] = { label = placement.label, key = placement.key } end
  return list
end

-- Draws the editor for one custom tag: label, placement, colour, delete.
local function tagEditor(app, window, def, reopen)
  local store = app.store
  -- Rebuilds the plan after a change, then redraws this window.
  local function changed() app:rebuild(); reopen() end
  window:AddTitle("Edit tag: " .. def.label)
  window:AddTextField({ text = def.label, placeholder = "Label (up to 6 characters), then press Enter", onSubmit = function(_, text)
    if not store:editTag(def.key, { label = text }) then state.tagNote = "A tag needs a label." end
    changed()
  end })
  window:AddComboBox(Combo.options(placementChoices(), def.placement, function(placement)
    store:editTag(def.key, { placement = placement })
    changed()
  end))
  window:AddText("Label colour")
  window:AddColourPicker({ value = def.colour, onChange = function(_, colour) store:editTag(def.key, { colour = colour }); app:rebuild() end })
  window:AddSimpleButton("Delete tag", function()
    Windows.confirm("DELETE TAG", "Delete the " .. def.label .. " tag? It is removed from every item.", "DELETE", function()
      store:deleteTag(def.key)
      state.tagKey = nil
      changed()
    end)
  end)
end

-- The Custom tags window: the tag priority list (built-in and custom), a
-- form for new tags, and the editor for the chosen custom tag.
function Windows.customTags(app)
  -- Redraws this window after a change.
  local function reopen() Windows.customTags(app) end
  return Windows.open("customTags", { title = "Custom tags", width = WIDTH, height = 640, x = 180, y = 60 }, function(window)
    local store = app.store
    -- Rebuilds the plan after a change, then redraws this window.
    local function changed() app:rebuild(); reopen() end
    if state.tagNote then
      window:AddText({ text = state.tagNote })
      state.tagNote = nil
    end
    window:AddTitle("Priority")
    Widgets.muted(window, "When an item has several tags, the highest one here decides where it goes and which label shows in its slot.")
    for index, key in ipairs(store.tagOrder) do
      local def = Placement.byKey[key]
      if def then
        local buttons = {
          { "Up", function() if store:moveTagPriority(key, -1) then changed() end end },
          { "Down", function() if store:moveTagPriority(key, 1) then changed() end end },
        }
        if def.custom then
          buttons[#buttons + 1] = { "Edit", function() state.tagKey = key; reopen() end }
        end
        Widgets.textWithButtons(window, index .. ". " .. def.label .. "  (" .. Placement.describe(key) .. ")", buttons, WIDTH)
      end
    end
    window:AddSimpleButton("Reset priority", function() store:resetTagOrder(); changed() end)
    Widgets.divider(window)
    window:AddTitle("New tag")
    window:AddComboBox(Combo.options(placementChoices(), state.newPlacement, function(placement) state.newPlacement = placement; reopen() end))
    window:AddTextField({ placeholder = "Label (up to 6 characters), then press Enter", onSubmit = function(_, text)
      local key = store:addTag(text, nil, state.newPlacement)
      if key then state.tagKey = key else state.tagNote = "Type a label first (you can have up to " .. Custom.MAX_TAGS .. " custom tags)." end
      changed()
    end })
    Widgets.muted(window, "Choose where the tag puts items first, then type its label. Label only never moves anything.")
    local def = state.tagKey and store:customTag(state.tagKey)
    if def then
      Widgets.divider(window)
      tagEditor(app, window, def, reopen)
    end
  end)
end

-- Adds one group of Bank Cleaner suggestions: icons, then each item as a
-- checkbox. Ticking it gives the item its group's tag straight away (and
-- unticking takes the tag off), so the Sorting Guide lines it up with the
-- other tagged items. Under each item: why it is suggested, and Keep.
-- Checkbox labels stay on one line, so the label is only the name, amount
-- and tag; the reason is wrapping text.
local function cleanerGroup(app, window, group, rows, reopen)
  local tagLabel = Placement.byKey[group.tag] and Placement.byKey[group.tag].label or group.tag
  Widgets.section(window, state.sections, "cleaner-" .. group.key, group.title .. " (" .. #rows .. ")", reopen, function()
    Widgets.muted(window, group.hint .. " Ticked items are tagged " .. tagLabel .. ".")
    local icons = {}
    for index, row in ipairs(rows) do
      icons[index] = { objectId = row.objectId, name = row.name, quantity = row.quantity }
    end
    itemGrid(window, icons)
    for _, row in ipairs(rows) do
      window:AddCheckboxButton({
        { text = row.name .. " x" .. Cleaner.coins(row.quantity) .. " (" .. tagLabel .. ")", value = tostring(row.objectId), selected = row.tagged },
      }, {
        -- Ticking tags the item, unticking removes the tag.
        onChange = function(_, _, _, selected)
          app:setTag(row.objectId, row.tag, selected)
          reopen()
        end,
      })
      Widgets.textWithButtons(window, row.reason, {
        -- Keep: never suggest this item again, and take off the tag the
        -- cleaner gave it.
        { "Keep", function()
          if row.tagged then app:setTag(row.objectId, row.tag, false) end
          app.store:setKept(row.objectId, true)
          state.cleanerNote = row.name .. " is kept and will not be suggested again."
          reopen()
        end },
      }, WIDTH)
    end
  end)
end

-- The Bank Cleaner window.
function Windows.cleaner(app)
  -- Redraws this window after a change.
  local function reopen() Windows.cleaner(app) end
  return Windows.open("cleaner", { title = "Bank Cleaner", width = WIDTH, height = 660, x = 180, y = 40 }, function(window)
    Widgets.muted(window, "Suggestions only: nothing is ever destroyed, dropped or sold for you. Tick an item to tag it (quest leftovers and low value items Trash, items worth alching Alch, items to review Rev); the Sorting Guide then lines it up at the bottom of your infinity tab. Untick to remove the tag, or press Keep so it is never suggested again. Clue items, rares, Vanity, Active and Favourite items, and items for quests you have not finished are never suggested.")
    local groups = app:cleanerSuggestions()
    if not groups then
      window:AddText("Press Analyze Bank first.")
      return
    end
    if state.cleanerNote then
      window:AddText({ text = state.cleanerNote })
      state.cleanerNote = nil
    end
    Widgets.muted(window, "Low value means under " .. Cleaner.coins(app.store:get("cleanerThreshold")) .. " gp per stack (Settings, Cleaner). Kept items: " .. app.store:keptCount() .. ".")
    for _, group in ipairs(Cleaner.GROUPS) do
      local rows = groups[group.key]
      if #rows > 0 then cleanerGroup(app, window, group, rows, reopen) end
    end
    if Cleaner.total(groups) == 0 then window:AddText("Nothing to suggest. Your bank looks tidy.") end
    Widgets.divider(window)
    window:AddSimpleButton("Clear Keep list", function()
      Windows.confirm("CLEAR KEEP LIST", "Let the Bank Cleaner suggest every kept item again?", "CLEAR", function()
        app.store:clearKept()
        reopen()
      end)
    end)
  end)
end

return Windows
