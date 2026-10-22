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
--   Bank Cleaner       suggestions with reasons, and tag or keep buttons
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
--   picked        Bank Cleaner rows ticked: item id -> true
--   cleanerNote   one-off message in the Bank Cleaner
--   sections      collapsed sections: key -> true
local state = { ruleKind = "contains", newPlacement = "bottom", picked = {}, sections = {} }

-- How many tab buttons fit on one row of the Tab Layout rail.
local RAIL_COLUMNS = 8

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

-- Returns true when the named window is open.
function Windows.isOpen(name)
  return open[name] ~= nil
end

-- Opens (or replaces) a window.
--   name     the window's name in the open table
--   options  PrettyUI Window options (title, width, height, x, y)
--   build    function(window) that adds the window's content
-- A failing build is logged and leaves a partly drawn window rather than
-- breaking the plugin. Returns the window, or nil when there is no layer.
function Windows.open(name, options, build)
  Windows.close(name)
  local layer = host()
  if not layer then return nil end
  -- Forget the window when the player closes it with its own X button.
  options.onClose = function() open[name] = nil end
  options.destroyOnClose = true
  local window = prettyui.Window.new(layer, options)
  open[name] = window
  local ok, err = pcall(build, window)
  if not ok and log then log("[bank-organizer] " .. name .. " window failed: " .. tostring(err)) end
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
      choices[i] = { label = app:destinationLabel(d) .. "  [" .. #app.destinations[d] .. "]", key = d }
    end
    window:AddComboBox(Combo.options(choices, state.blueprintTab, function(d)
      state.blueprintTab = d
      Windows.blueprint(app)
    end))
    -- Previous and Next wrap around at either end.
    window:AddSimpleButton("Previous", function()
      state.blueprintTab = tabs[index > 1 and index - 1 or #tabs]
      Windows.blueprint(app)
    end)
    window:AddSimpleButton("Next", function()
      state.blueprintTab = tabs[index < #tabs and index + 1 or 1]
      Windows.blueprint(app)
    end, { inline = true })
    local entries = app.destinations[state.blueprintTab]
    window:AddText(string.format("Tab %d of %d: %d items", index, #tabs, #entries))
    itemGrid(window, entries)
  end)
end

-- Adds the row of tab buttons along the top of the Tab Layout.
--   list      tab positions to show
--   selected  the chosen position
--   onPick    function(position)
-- Buttons read 1, 2, 3 ... like the game's own tab numbers; the chosen one
-- is in square brackets.
local function rail(window, list, selected, onPick)
  for index, d in ipairs(list) do
    local label = tostring(d + 1)
    if d == selected then label = "[" .. label .. "]" end
    window:AddSimpleButton(label, function() onPick(d) end, { inline = (index - 1) % RAIL_COLUMNS ~= 0 })
  end
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
  Widgets.muted(window, "Pick a tab. Pin a kind of item to it and everything of that kind goes there. Remove sends a kind back to Tab 1 (infinity). Move left and Move right swap whole tabs; the guide then shows you the one drag to make.", WIDTH)
  if not app:myTabs() then
    window:AddText("Press Analyze Bank first.")
    return
  end
  local list = app:destinationList()
  local d = indexOf(list, state.layoutTab) and state.layoutTab or list[1]
  state.layoutTab = d
  rail(window, list, d, function(picked) state.layoutTab = picked; changed() end)
  window:AddTitle(app:destinationLabel(d))
  for _, tag in ipairs(Tags.LIST) do
    local home, pinned = app:tabHomeOf(tag.key)
    if home == d then
      window:AddText(tag.label .. (pinned and "  (pinned)" or "  (auto)"))
      if pinned then
        window:AddSimpleButton("Unpin", function() app.store:clearTabHome(tag.key); changed() end, { inline = true })
      end
      if d > 0 then
        window:AddSimpleButton("Remove", function() if app.store:setTabHome(tag.key, 0) then changed() end end, { inline = true })
      end
    end
  end
  if d == 0 then Widgets.muted(window, "Plus anything no other tab collects.", WIDTH) end
  window:AddComboBox(Combo.options(pinChoicesFor(app, d), "none", function(key)
    if key ~= "none" and app.store:setTabHome(key, d) then changed() end
  end))
  plannedItems(app, window, d)
  Widgets.divider(window)
  -- Bottom bar. A tab move keeps the moved tab chosen.
  if d > 0 then
    window:AddSimpleButton("Move left", function() if app:moveMyTab(d, -1) then changed() end end)
    window:AddSimpleButton("Move right", function() if app:moveMyTab(d, 1) then changed() end end, { inline = true })
  end
  window:AddSimpleButton("Unpin all", function() app.store:resetTabHomes(); changed() end)
  window:AddSimpleButton("Keep my tab order", function() app:resetMyTabOrder(); changed() end, { inline = true })
end

-- Draws the chosen tab's details in the Whole bank Tab Layout.
local function layoutTab(app, window, layout, d, changed)
  window:AddTitle(Tags.destinationName(d) .. (layout.names[d] and (" " .. layout.names[d]) or ""))
  window:AddTextField({
    text = layout.names[d] or "", placeholder = "Name this tab, then press Enter",
    -- Enter saves the new name (an empty name clears it).
    onSubmit = function(_, content) if layout:rename(d, content) then changed() end end,
  })
  -- Each kind with buttons to reorder it or send it back to Storage & Cleanup.
  for _, key in ipairs(layout.destinations[d]) do
    window:AddText(Tags.label(key))
    window:AddSimpleButton("Up", function() if layout:shiftTag(key, -1) then changed() end end, { inline = true })
    window:AddSimpleButton("Down", function() if layout:shiftTag(key, 1) then changed() end end, { inline = true })
    window:AddSimpleButton("Remove", function() if layout:removeTag(key) then changed() end end, { inline = true })
  end
  window:AddComboBox(Combo.options(tagChoicesFor(layout, d), "none", function(key)
    if key ~= "none" and layout:moveTag(key, d) then changed() end
  end))
  plannedItems(app, window, d)
end

-- Draws the Whole bank version of the Tab Layout.
local function bankLayout(app, window, changed)
  local layout = app.store.layout
  Widgets.muted(window, "Your tabs in bank order, left to right. Pick a tab to name it, move it and choose which kinds of item it holds. Remove sends a kind to wherever Storage & Cleanup lives.", WIDTH)
  if state.layoutNote then
    window:AddText({ text = state.layoutNote, height = 40 })
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
  window:AddSimpleButton("Add tab", function()
    if layout:addTab() then state.layoutTab = layout:last() else state.layoutNote = "RS3 banks have at most 14 custom tabs." end
    changed()
  end)
  if d > 0 then
    window:AddSimpleButton("Delete tab", function()
      if layout:removeTab(d) then state.layoutTab = d - 1 end
      changed()
    end, { inline = true })
    window:AddSimpleButton("Move left", function() if layout:moveTab(d, -1) then state.layoutTab = d - 1 end; changed() end, { inline = true })
    window:AddSimpleButton("Move right", function() if layout:moveTab(d, 1) then state.layoutTab = d + 1 end; changed() end, { inline = true })
  end
  window:AddSimpleButton("Copy my current tabs", function()
    if not app:copyCurrentTabs() then state.layoutNote = "Open your bank and press Analyze Bank first, so your tabs can be read." end
    changed()
  end)
  window:AddSimpleButton("Reset to default", function() layout:reset(); changed() end, { inline = true })
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
    Widgets.muted(window, "Copy this code and post it anywhere. It holds your tabs, their names, the kinds of item in each, your pins, your custom categories and tags, how you organize and how you sort. Tags on single items stay yours.", WIDTH)
    window:AddTextField({ text = Preset.encode(app.store) })
    window:AddTitle("Load a setup")
    Widgets.muted(window, "Paste a code someone shared, then press Enter. Your current setup is replaced.", WIDTH)
    if state.presetNote then
      window:AddText({ text = state.presetNote, height = 40 })
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
  return Windows.open("tags", { title = "Tags: " .. name, width = TAGS_WIDTH, height = TAGS_HEIGHT, x = at.x, y = at.y }, function(window)
    -- The item itself, so it is clear what is being tagged.
    window:AddItemGrid({ { object = objectOf(itemID), tooltip = name } }, { columns = 1, rows = 1 })
    window:AddText("Category")
    categoryCombo(app, window, itemID, reopen)
    Widgets.muted(window, "Your choice always wins over automatic sorting.", TAGS_WIDTH)
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
    Widgets.muted(window, "An item can have several tags. The highest one in Tools, Custom tags decides where it goes.", TAGS_WIDTH)
  end)
end

-- Adds one review-list section of the Custom categories window.
--   rows    list of { objectId, name }
--   suffix  text after each name (may be "")
--   button  optional { label, fn(objectId) } added beside each row
local function reviewRows(window, rows, suffix, button)
  for _, row in ipairs(rows) do
    window:AddText(row.name .. suffix)
    if button then
      window:AddSimpleButton(button.label, function() button.fn(row.objectId) end, { inline = true })
    end
  end
end

-- Draws the chosen category's editor: name, colour, rules, review list and
-- delete.
local function categoryEditor(app, window, def, reopen)
  local store = app.store
  -- After a change that affects classification: rebuild, then redraw.
  local function changed() app:rebuild(); reopen() end
  window:AddTitle(def.name)
  window:AddTextField({ text = def.name, placeholder = "Rename, then press Enter", onSubmit = function(_, text)
    if not store:editCategory(def.key, { name = text }) then state.categoryNote = "A category needs a name." end
    changed()
  end })
  window:AddText("Colour")
  window:AddColourPicker({ value = def.colour, onChange = function(_, colour) store:editCategory(def.key, { colour = colour }); app:rebuild() end })
  Widgets.section(window, state.sections, "rules", "Name rules (" .. #def.rules .. ")", reopen, function()
    Widgets.muted(window, "Items whose names match a rule join this category automatically. Upper and lower case are ignored.", WIDTH)
    for index, rule in ipairs(def.rules) do
      local kind = rule.kind == "starts" and "Name starts with" or "Name contains"
      window:AddText(kind .. ": " .. rule.text)
      window:AddSimpleButton("Remove", function() store:removeRule(def.key, index); changed() end, { inline = true })
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
      Widgets.muted(window, "Press Analyze Bank to see which items in your bank the rules match.", WIDTH)
      return
    end
    Widgets.muted(window, "Items your rules added. Remove keeps an item out even though a rule matches it.", WIDTH)
    reviewRows(window, review.matched, "", { label = "Remove", fn = function(objectId) store:exclude(def.key, objectId); changed() end })
    reviewRows(window, review.removed, "  (removed)", { label = "Restore", fn = function(objectId) store:restore(def.key, objectId); changed() end })
    reviewRows(window, review.byHand, "  (picked by hand)")
    if total == 0 then Widgets.muted(window, "No items in your bank match yet.", WIDTH) end
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
    Widgets.muted(window, "Make your own kinds of item. New categories start in Tab 1 (infinity); move them in Tab Layout.", WIDTH)
    if state.categoryNote then
      window:AddText({ text = state.categoryNote, height = 40 })
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
      Widgets.muted(window, "No custom categories yet.", WIDTH)
      return
    end
    local def = store:category(state.categoryKey) or store.customCategories[1]
    state.categoryKey = def.key
    -- One button per category; the chosen one is in square brackets.
    for index, other in ipairs(store.customCategories) do
      local label = other.key == def.key and ("[" .. other.name .. "]") or other.name
      window:AddSimpleButton(label, function() state.categoryKey = other.key; reopen() end, { inline = index > 1 })
    end
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
      window:AddText({ text = state.tagNote, height = 40 })
      state.tagNote = nil
    end
    window:AddTitle("Priority")
    Widgets.muted(window, "When an item has several tags, the highest one here decides where it goes and which label shows in its slot.", WIDTH)
    for index, key in ipairs(store.tagOrder) do
      local def = Placement.byKey[key]
      if def then
        window:AddText(index .. ". " .. def.label .. "  (" .. Placement.describe(key) .. ")")
        window:AddSimpleButton("Up", function() if store:moveTagPriority(key, -1) then changed() end end, { inline = true })
        window:AddSimpleButton("Down", function() if store:moveTagPriority(key, 1) then changed() end end, { inline = true })
        if def.custom then
          window:AddSimpleButton("Edit", function() state.tagKey = key; reopen() end, { inline = true })
        end
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
    Widgets.muted(window, "Choose where the tag puts items first, then type its label. Label only never moves anything.", WIDTH)
    local def = state.tagKey and store:customTag(state.tagKey)
    if def then
      Widgets.divider(window)
      tagEditor(app, window, def, reopen)
    end
  end)
end

-- The Bank Cleaner buttons: what each one does to the ticked items.
local CLEANER_ACTIONS = {
  { label = "Tag as Sell", action = "sell", done = "Tagged %d as Sell." },
  { label = "Tag as Alch", action = "alch", done = "Tagged %d as Alch." },
  { label = "Tag as Trash", action = "trash", done = "Tagged %d as Trash." },
  { label = "Keep", action = "keep", done = "Kept %d; they will not be suggested again." },
}

-- Returns the ticked Bank Cleaner rows as a sorted list of item ids.
local function pickedIds()
  local list = {}
  for objectId in pairs(state.picked) do list[#list + 1] = objectId end
  table.sort(list)
  return list
end

-- Adds one group of Bank Cleaner suggestions: icons, then a ticked list.
local function cleanerGroup(window, group, rows, reopen)
  Widgets.section(window, state.sections, "cleaner-" .. group.key, group.title .. " (" .. #rows .. ")", reopen, function()
    Widgets.muted(window, group.hint, WIDTH)
    local icons, boxes = {}, {}
    for index, row in ipairs(rows) do
      icons[index] = { objectId = row.objectId, name = row.name, quantity = row.quantity }
      boxes[index] = { text = row.name .. " x" .. Cleaner.coins(row.quantity) .. ": " .. row.reason,
        value = tostring(row.objectId), selected = state.picked[row.objectId] == true }
    end
    itemGrid(window, icons)
    window:AddCheckboxButton(boxes, { onChange = function(_, _, changed, selected)
      local objectId = tonumber(changed)
      if objectId then state.picked[objectId] = selected and true or nil end
    end })
  end)
end

-- The Bank Cleaner window.
function Windows.cleaner(app)
  -- Redraws this window after a change.
  local function reopen() Windows.cleaner(app) end
  return Windows.open("cleaner", { title = "Bank Cleaner", width = WIDTH, height = 660, x = 180, y = 40 }, function(window)
    Widgets.muted(window, "Suggestions only: nothing is ever destroyed, dropped or sold for you. Tick items, then tag them so the guide lines them up at the bottom of your infinity tab, or Keep them so they are never suggested again. Clue items, rares, Vanity, Active and Favourite items, and items for quests you have not finished are never suggested.", WIDTH)
    local groups = app:cleanerSuggestions()
    if not groups then
      window:AddText("Press Analyze Bank first.")
      return
    end
    if state.cleanerNote then
      window:AddText({ text = state.cleanerNote, height = 40 })
      state.cleanerNote = nil
    end
    Widgets.muted(window, "Low value means under " .. Cleaner.coins(app.store:get("cleanerThreshold")) .. " gp per stack (Settings, Cleaner). Kept items: " .. app.store:keptCount() .. ".", WIDTH)
    for _, group in ipairs(Cleaner.GROUPS) do
      local rows = groups[group.key]
      if #rows > 0 then cleanerGroup(window, group, rows, reopen) end
    end
    if Cleaner.total(groups) == 0 then window:AddText("Nothing to suggest. Your bank looks tidy.") end
    Widgets.divider(window)
    for index, button in ipairs(CLEANER_ACTIONS) do
      window:AddSimpleButton(button.label, function()
        local ids = pickedIds()
        local changed = app:applyCleaner(ids, button.action)
        state.picked = {}
        state.cleanerNote = #ids == 0 and "Tick some items first." or string.format(button.done, changed)
        reopen()
      end, { inline = index > 1 })
    end
    window:AddSimpleButton("Clear Keep list", function()
      Windows.confirm("CLEAR KEEP LIST", "Let the Bank Cleaner suggest every kept item again?", "CLEAR", function()
        app.store:clearKept()
        reopen()
      end)
    end)
  end)
end

return Windows
