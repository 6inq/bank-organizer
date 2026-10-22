-- Bank Organizer: the settings, shown in two places with the same content:
--   * the game's own settings gear for this plugin (SettingsLayerReady)
--   * a Settings window opened from the sidebar's Tools section
--
-- Settings are split into pages chosen with a tab bar along the top:
--   General         tint, sorted tabs, rearrange mode, resets
--   Sorting         sort mode, direction, herblore secondaries, decanting
--   Tags & Labels   tag priority, clearing tags, every label colour
--   Colours         category and guide colours
--   Cleaner         Bank Cleaner threshold and Keep list
-- Each page is made of collapsible sections. Every setting has a muted hint
-- under it in plain words. A footer names the plugin, its creator and its
-- version.

local Tags = require("src/core/tags")
local Combo = require("src/ui/combo")
local Placement = require("src/core/placement")
local Sorting = require("src/core/sorting")
local Cleaner = require("src/core/cleaner")
local Widgets = require("src/ui/widgets")
local Windows = require("src/ui/windows")
local Version = require("src/version")

local Settings = {}

-- The id this plugin subscribes to the settings layer with.
local EVENT_ID = "bank-organizer:settings"

-- The pages, in tab bar order.
Settings.PAGES = { "General", "Sorting", "Tags & Labels", "Colours", "Cleaner" }

-- The view inside the game's settings layer.
local view

-- Which page is showing and which sections are collapsed. Shared by the
-- settings layer and the window so both open where the player left off.
local state = { page = "General", sections = {} }

-- The guide's own colours with their names in the Colours page.
local HIGHLIGHTS = { { "move", "Item to move (MOVE)" }, { "target", "Drop target" }, { "line", "Guide line" }, { "done", "Sorted tabs" } }

-- The Bank Cleaner low value thresholds players can pick, in coins.
Settings.THRESHOLDS = { 0, 100, 500, 1000, 5000, 10000, 50000, 100000, 1000000 }

-- Adds a labelled colour picker that saves and redraws on change.
local function addColour(target, store, app, key, label)
  target:AddText(label)
  target:AddColourPicker({
    value = store:colour(key),
    -- Saves the new colour and redraws the overlay with it.
    onChange = function(_, colour) store:setColour(key, colour); app:rebuild() end,
  })
end

-- Adds a labelled dropdown for one setting.
--   choices  list of { label, key }
--   onPick   function(key) called with the new value
local function addChoice(target, label, hint, choices, current, onPick, width)
  Widgets.setting(target, label, hint, function()
    target:AddComboBox(Combo.options(choices, current, onPick))
  end, width)
end

-- The General page.
local function generalPage(target, store, app, ctx)
  Widgets.section(target, state.sections, "look", "Look", ctx.refresh, function()
    target:AddCheckboxButton({
      { text = "Tint bank items with their planned tab colour", value = "tint", selected = store:get("tint") },
    }, { onChange = function(_, _, changed, selected) store:set(changed, selected); app:rebuild() end })
    Widgets.muted(target, "Each item is coloured like the tab it belongs in, so you can see the plan at a glance.", ctx.width)
    Widgets.setting(target, "Tint opacity", "How strong the colour is, from 0 (invisible) to 100 (solid).", function()
      target:AddSlider({
        min = 0, max = 100, step = 5, value = math.floor(store:get("opacity") * 100 + 0.5),
        -- The slider gives 0 to 100; the setting is stored as 0 to 1.
        onChange = function(_, value) store:set("opacity", value / 100); app:rebuild() end,
      })
    end, ctx.width)
    addChoice(target, "Tabs that are sorted", "How a tab looks once every item in it is in place.",
      { { label = "Green", key = "green" }, { label = "No overlay", key = "clear" }, { label = "Keep tab colour", key = "tint" } },
      store:get("sortedLook"), function(key) store:set("sortedLook", key); app:rebuild() end, ctx.width)
  end)
  Widgets.section(target, state.sections, "guide", "Sorting Guide", ctx.refresh, function()
    addChoice(target, "Rearrange mode", "Only used when the game does not report its own Insert or Swap setting.",
      { { label = "Insert (fewer moves)", key = "insert" }, { label = "Swap", key = "swap" } },
      store:get("mode"), function(key) store:set("mode", key) end, ctx.width)
  end)
  Widgets.section(target, state.sections, "resets", "Resets", ctx.refresh, function()
    target:AddSimpleButton("Stop ignoring all items", function()
      ctx.confirm("STOP IGNORING", "Let the guide organize every item you ignored?", "RESET", function() store:resetIgnored(); app:rebuild() end)
    end)
    target:AddSimpleButton("Reset corrections", function()
      ctx.confirm("RESET CORRECTIONS", "Forget every category you assigned by hand?", "RESET", function() store:resetCorrections(); app:rebuild() end)
    end)
  end)
end

-- The Sorting page.
local function sortingPage(target, store, app, ctx)
  Widgets.section(target, state.sections, "order", "Order", ctx.refresh, function()
    addChoice(target, "Sort inside tabs", "Smart gives every kind of item its own sensible order.",
      Sorting.modes(app:valueSource()), store:get("sort"), function(mode) store:set("sort", mode); app:rebuild() end, ctx.width)
    addChoice(target, "Sort direction", "Rows fill left to right; columns fill top to bottom.",
      { { label = "Horizontal (rows)", key = "horizontal" }, { label = "Vertical (columns)", key = "vertical" } },
      store:get("direction"), function(direction) store:set("direction", direction); app:rebuild() end, ctx.width)
  end)
  Widgets.section(target, state.sections, "herblore", "Herblore", ctx.refresh, function()
    addChoice(target, "Secondaries", "With their potion: herb, unfinished potion, secondary, then the potion. At the bottom: all secondaries after the rest of your herblore.",
      { { label = "With their potion", key = "with" }, { label = "At the bottom of the tab", key = "bottom" } },
      store:get("secondaries"), function(key) store:set("secondaries", key); app:rebuild() end, ctx.width)
    target:AddCheckboxButton({
      { text = "Label part-dose potions you can decant", value = "decant", selected = store:get("decant") },
      { text = "1 dose", value = "decant1", selected = store:get("decant1") },
      { text = "2 dose", value = "decant2", selected = store:get("decant2") },
      { text = "3 dose", value = "decant3", selected = store:get("decant3") },
      { text = "4 dose (flasks)", value = "decant4", selected = store:get("decant4") },
      { text = "5 dose (flasks)", value = "decant5", selected = store:get("decant5") },
    }, { onChange = function(_, _, changed, selected) store:set(changed, selected); app:rebuild() end })
    Widgets.muted(target, "With labels on, part doses that cannot make a full potion wait at the bottom of the herb tab. With labels off, part doses stay with their potion.", ctx.width)
  end)
end

-- The Tags & Labels page.
local function tagsPage(target, store, app, ctx)
  Widgets.section(target, state.sections, "tags", "Tags", ctx.refresh, function()
    Widgets.muted(target, "Make your own tags and change which tag wins in Custom tags.", ctx.width)
    target:AddSimpleButton("Custom tags", function() Windows.customTags(app) end)
    target:AddSimpleButton("Custom categories", function() Windows.categories(app) end, { inline = true })
    target:AddSimpleButton("Clear all tags", function()
      ctx.confirm("CLEAR TAGS", "Remove every tag (Active, Vanity, Favourite, Sell, Alch, Disassemble, Trash and your own) from every item?",
        "CLEAR", function() store:clearMarks(); app:rebuild() end)
    end)
  end)
  Widgets.section(target, state.sections, "labels", "Tag label colours", ctx.refresh, function()
    for _, placement in ipairs(Placement.labelColours()) do
      addColour(target, store, app, Placement.colourKey(placement.key), placement.label .. " (" .. placement.badge .. ")")
    end
  end)
end

-- The Colours page.
local function coloursPage(target, store, app, ctx)
  Widgets.section(target, state.sections, "kinds", "Colours by kind", ctx.refresh, function()
    Widgets.muted(target, "A tab takes the colour of the first kind of item it holds. Custom categories are coloured in Custom categories.", ctx.width)
    for _, category in ipairs(Tags.CATEGORIES) do
      if not category.custom then addColour(target, store, app, category.key, category.main) end
    end
  end)
  Widgets.section(target, state.sections, "guideColours", "Guide colours", ctx.refresh, function()
    for _, highlight in ipairs(HIGHLIGHTS) do addColour(target, store, app, highlight[1], highlight[2]) end
  end)
  target:AddSimpleButton("Reset all colours", function()
    ctx.confirm("RESET COLOURS", "Put every colour back to its default?", "RESET", function() store:resetColours(); app:rebuild() end)
  end)
end

-- The Cleaner page.
local function cleanerPage(target, store, app, ctx)
  Widgets.section(target, state.sections, "cleaner", "Bank Cleaner", ctx.refresh, function()
    local choices = {}
    for index, coins in ipairs(Settings.THRESHOLDS) do choices[index] = { label = Cleaner.coins(coins) .. " gp", key = coins } end
    addChoice(target, "Low value below", "Tradeable stacks worth less than this are suggested as low value.",
      choices, store:get("cleanerThreshold"), function(coins) store:set("cleanerThreshold", coins); ctx.refresh() end, ctx.width)
    target:AddText("Kept items: " .. store:keptCount())
    target:AddSimpleButton("Clear Keep list", function()
      ctx.confirm("CLEAR KEEP LIST", "Let the Bank Cleaner suggest every kept item again?", "CLEAR", function() store:clearKept(); ctx.refresh() end)
    end)
    target:AddSimpleButton("Open the Bank Cleaner", function() Windows.cleaner(app) end, { inline = true })
  end)
end

-- Page name -> the function that draws it.
local PAGE_BUILDERS = {
  ["General"] = generalPage, ["Sorting"] = sortingPage, ["Tags & Labels"] = tagsPage,
  ["Colours"] = coloursPage, ["Cleaner"] = cleanerPage,
}

-- Draws the whole settings content into a view or window.
--   target  the SimpleView or Window
--   ctx     { refresh = function() redraw, confirm = function(...) ask,
--             width = number }
function Settings.build(target, store, app, ctx)
  target:AddTitle("Bank Organizer settings")
  Widgets.tabBar(target, Settings.PAGES, state.page, function(page) state.page = page; ctx.refresh() end, ctx.width)
  Widgets.divider(target)
  local builder = PAGE_BUILDERS[state.page] or generalPage
  builder(target, store, app, ctx)
  Widgets.divider(target)
  Widgets.muted(target, "Bank Organizer | Created by 6ing", ctx.width)
  Widgets.muted(target, "Version " .. Version.NUMBER, ctx.width)
end

-- Draws the settings into the game's settings layer.
local function mount(parent, store, app)
  -- A redraw after a change keeps the scroll position.
  local scrolled = view and Widgets.scrollOf(view) or 0
  Settings.destroy()
  view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
  Settings.build(view, store, app, {
    width = parent.width,
    -- Redraws the settings layer after a page or section change.
    refresh = function() mount(parent, store, app) end,
    -- Asks before a reset, inside the settings layer.
    confirm = function(title, body, label, onConfirm)
      prettyui.Confirm.new(parent, { title = title, body = body, confirmLabel = label, onConfirm = onConfirm })
    end,
  })
  Widgets.restoreScroll(view, scrolled)
end

-- Opens the settings in their own window (Tools, Settings).
function Settings.openWindow(app)
  local store = app.store
  return Windows.open("settings", { title = "Settings", width = 470, height = 640, x = 100, y = 40 }, function(window)
    Settings.build(window, store, app, {
      width = 470,
      -- Redraws the Settings window after a page or section change.
      refresh = function() Settings.openWindow(app) end,
      confirm = Windows.confirm,
    })
  end)
end

-- Subscribes to the game's settings layer so the gear shows the settings.
function Settings.start(store, app)
  Event.SettingsLayerReady.Subscribe(EVENT_ID, function(event)
    local ok, err = pcall(mount, event.component, store, app)
    if not ok and log then log("[bank-organizer] settings failed: " .. tostring(err)) end
  end)
end

-- Removes the settings view from the game's settings layer.
function Settings.destroy()
  if view then pcall(function() return view:Destroy() end) end
  view = nil
end

-- Unsubscribes and removes the settings view.
function Settings.stop()
  pcall(function() return Event.SettingsLayerReady.Unsubscribe(EVENT_ID) end)
  Settings.destroy()
end

return Settings
