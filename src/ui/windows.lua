local Tags = require("src/core/tags")
local Tagging = require("src/game/tagging")
local Combo = require("src/ui/combo")
local Preset = require("src/core/preset")
local Placement = require("src/core/placement")

local Windows = {}

local open = {}
local blueprintTab = nil
local layoutNote = nil
local presetNote = nil

local function host()
  local ok, layer = pcall(function()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
  end)
  if ok then return layer end
  return nil
end

function Windows.close(name)
  local window = open[name]
  open[name] = nil
  if window then pcall(function() return window:Destroy() end) end
end

function Windows.closeAll()
  for name in pairs(open) do Windows.close(name) end
end

function Windows.isOpen(name)
  return open[name] ~= nil
end

local function create(name, options, build)
  Windows.close(name)
  local layer = host()
  if not layer then return nil end
  options.onClose = function() open[name] = nil end
  options.destroyOnClose = true
  local window = prettyui.Window.new(layer, options)
  open[name] = window
  local ok, err = pcall(build, window)
  if not ok and log then log("[bank-organizer] " .. name .. " window failed: " .. tostring(err)) end
  return window
end

local function objectOf(itemID)
  local ok, obj = pcall(function() return config.Obj.FromID(itemID) end)
  if ok then return obj end
  return nil
end

local GRID_COLUMNS = 8

local function filledTabs(app)
  local list = {}
  for _, d in ipairs(app:destinationList()) do
    if #(app.destinations[d] or {}) > 0 then list[#list + 1] = d end
  end
  return list
end

local function indexOf(list, value)
  for index, item in ipairs(list) do if item == value then return index end end
  return nil
end

function Windows.blueprint(app)
  return create("blueprint", { title = "Blueprint", width = 470, height = 560, x = 60, y = 60 }, function(window)
    if not app.destinations then
      window:AddText("Press Analyze Bank first.")
      return
    end
    local tabs = filledTabs(app)
    if #tabs == 0 then
      window:AddText("Your bank is empty.")
      return
    end
    local index = indexOf(tabs, blueprintTab) or 1
    blueprintTab = tabs[index]
    local choices = {}
    for i, d in ipairs(tabs) do
      choices[i] = { label = app:destinationLabel(d) .. "  [" .. #app.destinations[d] .. "]", key = d }
    end
    window:AddComboBox(Combo.options(choices, blueprintTab, function(d)
      blueprintTab = d
      Windows.blueprint(app)
    end))
    window:AddSimpleButton("Previous", function()
      blueprintTab = tabs[index > 1 and index - 1 or #tabs]
      Windows.blueprint(app)
    end)
    window:AddSimpleButton("Next", function()
      blueprintTab = tabs[index < #tabs and index + 1 or 1]
      Windows.blueprint(app)
    end, { inline = true })
    local entries = app.destinations[blueprintTab]
    window:AddText(string.format("Tab %d of %d: %d items", index, #tabs, #entries))
    local objects = {}
    for i, entry in ipairs(entries) do
      objects[i] = { object = objectOf(entry.objectId or entry.id), quantity = entry.quantity, tooltip = entry.name .. " (" .. Tags.label(entry.tag) .. ")" }
    end
    window:AddItemGrid(objects, { columns = GRID_COLUMNS, rows = math.max(1, math.ceil(#objects / GRID_COLUMNS)) })
  end)
end

local function tagChoicesFor(layout, d)
  local list = { { label = "Add a tag here...", key = "none" } }
  for _, tag in ipairs(Tags.LIST) do
    local current = layout:destinationOf(tag.key)
    if current ~= d then
      list[#list + 1] = { label = tag.label .. "  (" .. Tags.destinationName(current) .. ")", key = tag.key }
    end
  end
  return list
end

local function pinChoicesFor(app, d)
  local list = { { label = "Pin a tag here...", key = "none" } }
  for _, tag in ipairs(Tags.LIST) do
    local home = app:tabHomeOf(tag.key)
    if home ~= d then
      list[#list + 1] = { label = tag.label .. "  (" .. (home and app:tabName(home) or "stays put") .. ")", key = tag.key }
    end
  end
  return list
end

local function tabLayout(app, window, changed)
  window:AddText({ text = "Pin a kind of item to a tab and everything of that kind goes there; to move a kind, pick it in another tab's dropdown. Remove sends it back to Tab 1 (infinity). Move left / right swaps whole tabs; the guide then walks you through moving the items.", height = 96 })
  if not app:myTabs() then
    window:AddText("Press Analyze Bank first.")
    return
  end
  local list = app:destinationList()
  for _, d in ipairs(list) do
    window:AddTitle(app:destinationLabel(d))
    if d > 0 then
      window:AddSimpleButton("Move left", function() if app:moveMyTab(d, -1) then changed() end end)
      window:AddSimpleButton("Move right", function() if app:moveMyTab(d, 1) then changed() end end, { inline = true })
    end
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
    if d == 0 then window:AddText("Plus anything no other tab collects.") end
    window:AddComboBox(Combo.options(pinChoicesFor(app, d), "none", function(key)
      if key ~= "none" and app.store:setTabHome(key, d) then changed() end
    end))
  end
  window:AddSimpleButton("Unpin all", function() app.store:resetTabHomes(); changed() end)
  window:AddSimpleButton("Keep my tab order", function() app:resetMyTabOrder(); changed() end, { inline = true })
end

local function layoutTab(window, layout, d, changed)
  window:AddTitle(Tags.destinationName(d) .. (layout.names[d] and (" " .. layout.names[d]) or ""))
  window:AddTextField({
    text = layout.names[d] or "", placeholder = "Name this tab, then press Enter",
    onSubmit = function(_, content) if layout:rename(d, content) then changed() end end,
  })
  if d > 0 then
    window:AddSimpleButton("Move left", function() if layout:moveTab(d, -1) then changed() end end)
    window:AddSimpleButton("Move right", function() if layout:moveTab(d, 1) then changed() end end, { inline = true })
    window:AddSimpleButton("Delete tab", function() if layout:removeTab(d) then changed() end end, { inline = true })
  end
  for _, key in ipairs(layout.destinations[d]) do
    window:AddText(Tags.label(key))
    window:AddSimpleButton("Up", function() if layout:shiftTag(key, -1) then changed() end end, { inline = true })
    window:AddSimpleButton("Down", function() if layout:shiftTag(key, 1) then changed() end end, { inline = true })
    window:AddSimpleButton("Remove", function() if layout:removeTag(key) then changed() end end, { inline = true })
  end
  window:AddComboBox(Combo.options(tagChoicesFor(layout, d), "none", function(key)
    if key ~= "none" and layout:moveTag(key, d) then changed() end
  end))
end

local function bankLayout(app, window, changed)
  local layout = app.store.layout
  window:AddText({ text = "Your tabs in bank order, left to right. Name them, move them, and choose which kinds of item each one holds. Remove sends a kind to wherever Storage & Cleanup lives.", height = 64 })
  if layoutNote then
    window:AddText({ text = layoutNote, height = 40 })
    layoutNote = nil
  end
  window:AddSimpleButton("Copy my current tabs", function()
    if not app:copyCurrentTabs() then layoutNote = "Open your bank and press Analyze Bank first, so your tabs can be read." end
    changed()
  end)
  window:AddSimpleButton("Add tab", function()
    if not layout:addTab() then layoutNote = "RS3 banks have at most 14 custom tabs." end
    changed()
  end, { inline = true })
  window:AddSimpleButton("Reset to default", function() layout:reset(); changed() end, { inline = true })
  for d = 0, layout:last() do layoutTab(window, layout, d, changed) end
end

function Windows.layout(app)
  local function changed()
    app.store:save()
    app:rebuild()
    Windows.layout(app)
  end
  if app.store:get("scope") == "tabs" then
    return create("layout", { title = "Tab Layout (My tabs)", width = 470, height = 600, x = 120, y = 60 }, function(window)
      tabLayout(app, window, changed)
    end)
  end
  return create("layout", { title = "Tab Layout", width = 470, height = 600, x = 120, y = 60 }, function(window)
    bankLayout(app, window, changed)
  end)
end

function Windows.presets(app)
  return create("presets", { title = "Share or Load a Setup", width = 470, height = 420, x = 140, y = 80 }, function(window)
    window:AddTitle("Share my setup")
    window:AddText({ text = "Copy this code and post it anywhere. It holds your tabs, their names, the kinds of item in each, your pins, how you organize and how you sort.", height = 64 })
    window:AddTextField({ text = Preset.encode(app.store) })
    window:AddTitle("Load a setup")
    window:AddText({ text = "Paste a code someone shared, then press Enter. Your current setup is replaced.", height = 40 })
    if presetNote then
      window:AddText({ text = presetNote, height = 40 })
      presetNote = nil
    end
    window:AddTextField({
      placeholder = "Paste a setup code here",
      onSubmit = function(_, content)
        local preset, reason = Preset.decode(content)
        if preset then
          local last = Preset.apply(app.store, preset)
          presetNote = string.format("Loaded a setup with %d tab%s after infinity.", last, last == 1 and "" or "s")
          app:rebuild()
        else
          presetNote = reason
        end
        Windows.presets(app)
      end,
    })
  end)
end

local function placementChoices()
  local list = { { label = "None", key = "none" } }
  for _, placement in ipairs(Placement.LIST) do
    list[#list + 1] = { label = placement.label .. "  (" .. Placement.describe(placement.key) .. ")", key = placement.key }
  end
  return list
end

function Windows.tags(app, itemID)
  local name = "item " .. tostring(itemID)
  local obj = objectOf(itemID)
  if obj and obj.name then name = obj.name end
  return create("tags", { title = "Tags: " .. name, width = 380, height = 340, x = 200, y = 160 }, function(window)
    local current = app.store.corrections[itemID]
    window:AddText("Category")
    window:AddComboBox(Combo.options(Tagging.choices(), current or "auto", function(key)
      if key == "auto" then app.store:clearCorrection(itemID) else app.store:correct(itemID, key) end
      app:rebuild()
      Windows.tags(app, itemID)
    end))
    window:AddText("Placement")
    window:AddComboBox(Combo.options(placementChoices(), app:markOf(itemID) or "none", function(key)
      app:setMark(itemID, key ~= "none" and key or nil)
      Windows.tags(app, itemID)
    end))
    window:AddCheckboxButton({
      { text = "Ignore (never move this item)", value = "ignore", selected = app:isIgnored(itemID) },
    }, { onChange = function(_, _, _, selected)
      if selected ~= app:isIgnored(itemID) then app:toggleIgnore(itemID) end
      Windows.tags(app, itemID)
    end })
  end)
end

return Windows
