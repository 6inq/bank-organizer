-- Bank Organizer tests: the 1.4.2 interface, through main.lua and a fake
-- client (tests/harness.lua).
--
-- Requirements covered:
--   * sidebar: header with version, status card (moves left, sorted tabs,
--     Bank Cleaner offer when done), collapsible Organize / Your tabs /
--     Tools sections, item slots in Your tabs, footer hint
--   * settings: five pages in the game's settings gear and in a Settings
--     window; every setting is reachable and saves; every page has hints
--     and a version footer
--   * right-click: one Tags entry that opens the Tags window next to the
--     mouse, kept on screen
--   * Custom categories, Custom tags and Bank Cleaner windows work end to
--     end, and custom categories show up in Tab Layout, pins and the legend
--   * Ignore wins over tags
--   * every dropdown uses whole-number ids
--   * the version in the plugin matches plugin.json
--   * the Tools section sits under the main buttons, above Organize
--   * windows can be dragged: a redrawn window stays where it was dragged,
--     and a window is fitted inside the game so it is never pinned

local A = require("assert")
local H = require("harness")
local Store = require("src/core/store")
local Widgets = require("src/ui/widgets")

local T = {}

local boot, panel, texts, find, pick, press = H.boot, H.panel, H.texts, H.find, H.pick, H.press

-- Returns the labels of every simple button in a recording.
local function buttons(calls)
  local out = {}
  for _, c in ipairs(H.findAll(calls, "AddSimpleButton")) do out[#out + 1] = c.args[1] end
  return table.concat(out, "\n")
end

-- Reads the version from plugin.json.
local function manifestVersion()
  local file = assert(io.open("plugin.json", "r"))
  local text = file:read("a")
  file:close()
  return text:match('"version"%s*:%s*"([^"]+)"')
end

-- Requirement: the plugin's version matches plugin.json.
function T.version_matches_the_manifest()
  local Version = require("src/version")
  A.eq(Version.NUMBER, manifestVersion())
end

-- Requirement: the sidebar has a header, the main buttons, three
-- collapsible sections and a footer hint.
function T.sidebar_layout()
  local env = boot()
  local p = panel(env)
  A.truthy(texts(p):find("v" .. manifestVersion() .. " | by 6ing", 1, true), "version and creator under the title")
  for _, label in ipairs({ "[-] Organize", "[-] Your tabs", "[-] Tools", "Open Blueprint", "Tab Layout" }) do
    A.truthy(find(p, "AddSimpleButton", label), label)
  end
  for _, label in ipairs({ "Share or Load a Setup", "Bank Cleaner", "Custom tags", "Custom categories", "Settings" }) do
    A.truthy(find(p, "AddSimpleButton", label), "Tools: " .. label)
  end
  A.eq(find(p, "AddFancyButton", "Analyze Bank").args[3].variant, "neutral")
  A.truthy(texts(p):find("Right-click any bank item", 1, true), "footer hint")
  H.assertIntegerIds(p)
  PluginShutdown()
end

-- Requirement: sections collapse and open again.
function T.sidebar_sections_collapse()
  local env = boot()
  A.truthy(H.comboWith(panel(env), "tabs"), "Organize is open")
  press(env, "[-] Organize")
  A.eq(H.comboWith(panel(env), "tabs"), nil, "Organize is closed")
  A.truthy(find(panel(env), "AddSimpleButton", "[+] Organize"))
  press(env, "[+] Organize")
  A.truthy(H.comboWith(panel(env), "tabs"), "open again")
  PluginShutdown()
end

-- Requirement: after Analyze, each Your tabs row starts with its first
-- planned item's icon.
function T.your_tabs_rows_have_item_slots()
  local env = boot()
  press(env, "Analyze Bank")
  local grids = H.findAll(panel(env), "AddItemGrid")
  A.truthy(#grids >= 3, "an item slot per filled tab")
  A.eq(grids[1].args[2].columns, 1, "a single slot")
  A.truthy(grids[1].args[1][1].tooltip, "the item name on hover")
  PluginShutdown()
end

-- Requirement: the status card shows moves left and sorted tabs while
-- sorting, and offers the Bank Cleaner once everything is sorted.
function T.status_card_tracks_progress_and_offers_the_cleaner()
  local env = boot({ bank = { 103, 108, 102, 104 }, tabSizes = { 1 } })
  var.VarPlayer.BANKINSERT = { value = 0 }
  press(env, "Start Sorting")
  local text = texts(panel(env))
  A.truthy(text:find("Moves left: ", 1, true), text)
  A.truthy(text:find("Sorted tabs ", 1, true), text)
  A.eq(find(panel(env), "AddSimpleButton", "Run the Bank Cleaner"), nil, "not done yet")
  PluginShutdown()
  local done = boot({ bank = { 104, 102 }, tabSizes = {} })
  press(done, "Start Sorting")
  A.truthy(texts(panel(done)):find("matches the blueprint", 1, true), texts(panel(done)))
  press(done, "Run the Bank Cleaner")
  A.eq(H.window(done).options.title, "Bank Cleaner")
  PluginShutdown()
end

-- Requirement: Settings has five pages, a tab bar, hints on every page and
-- a footer with the creator and the version.
function T.settings_pages_have_hints_and_a_footer()
  local env = boot()
  for _, page in ipairs({ "General", "Sorting", "Tags & Labels", "Colours", "Cleaner" }) do
    local view = H.settingsPage(env, page)
    A.truthy(find(view, "AddSimpleButton", "[" .. page .. "]"), page .. " is the chosen tab")
    local text = texts(view)
    A.truthy(text:find("Bank Organizer | Created by 6ing", 1, true), page .. " footer")
    A.truthy(text:find("Version " .. manifestVersion(), 1, true), page .. " version")
    local hints = 0
    for _, c in ipairs(view) do
      if c.method == "AddText" and c.rgba == Widgets.MUTED then hints = hints + 1 end
    end
    A.truthy(hints >= 1, page .. " explains its settings")
    H.assertIntegerIds(view)
  end
  PluginShutdown()
end

-- Requirement: every setting is reachable from a page and saves.
function T.every_setting_is_reachable_and_saves()
  local env = boot()
  local general = H.settingsPage(env, "General")
  find(general, "AddCheckboxButton").args[2].onChange(nil, nil, "tint", false)
  find(general, "AddSlider").args[1].onChange(nil, 80)
  pick(H.comboWith(general, "clear"), "clear")
  pick(H.comboWith(H.settingsPage(env, "General"), "swap"), "swap")
  local sorting = H.settingsPage(env, "Sorting")
  pick(H.comboWith(sorting, "name"), "name")
  pick(H.comboWith(H.settingsPage(env, "Sorting"), "vertical"), "vertical")
  pick(H.comboWith(H.settingsPage(env, "Sorting"), "bottom"), "bottom")
  find(H.settingsPage(env, "Sorting"), "AddCheckboxButton").args[2].onChange(nil, nil, "decant2", false)
  H.findAll(H.settingsPage(env, "Cleaner"), "AddTextField")[1].args[1].onSubmit(nil, "5k")
  local store = Store.new(PersistentDB)
  A.eq(store:get("tint"), false); A.eq(store:get("opacity"), 0.8); A.eq(store:get("sortedLook"), "clear")
  A.eq(store:get("mode"), "swap"); A.eq(store:get("sort"), "name"); A.eq(store:get("direction"), "vertical")
  A.eq(store:get("secondaries"), "bottom"); A.eq(store:get("decant2"), false); A.eq(store:get("cleanerThreshold"), 5000)
  local colours = H.settingsPage(env, "Colours")
  A.eq(#H.findAll(colours, "AddColourPicker"), 14, "ten category colours and four guide colours")
  H.findAll(colours, "AddColourPicker")[1].args[1].onChange(nil, 0x010203FF)
  A.eq(Store.new(PersistentDB):colour("currency-utilities"), 0x010203FF)
  find(H.settingsPage(env, "Colours"), "AddSimpleButton", "Reset all colours").args[2]()
  env.confirm.onConfirm()
  A.eq(Store.new(PersistentDB):colour("currency-utilities"), 0xFFCD3CFF, "reset after confirming")
  PluginShutdown()
end

-- Requirement: Tools, Settings opens the same pages in a window.
function T.settings_window_from_tools()
  local env = boot()
  press(env, "Settings")
  local w = H.window(env)
  A.eq(w.options.title, "Settings")
  A.truthy(find(w, "AddSimpleButton", "[General]"))
  H.pressIn(env, "Cleaner")
  A.truthy(find(H.window(env), "AddSimpleButton", "[Cleaner]"), "the tab bar works in the window")
  A.truthy(find(H.window(env), "AddSimpleButton", "Clear Keep list"))
  PluginShutdown()
end

-- Requirement: right-click adds exactly one Tags entry, even when PrettyUI
-- offers a submenu helper (hover submenus closed too easily in game).
function T.right_click_adds_one_entry_and_no_submenu()
  local env = boot({ submenu = true })
  local added = H.rightClick(env, 103)
  A.eq(#added, 1); A.eq(added[1].label, "Tags (Bank Organizer)")
  A.eq(#env.submenus, 0, "no hover submenu is used")
  PluginShutdown()
end

-- Requirement: the Tags window opens just right of and below the mouse,
-- shows the item, and stays in place when a choice redraws it.
function T.tags_window_opens_next_to_the_mouse()
  local env = boot({ mouse = { x = 300, y = 100 } })
  press(env, "Analyze Bank")
  local w = H.tagsWindow(env, 103)
  A.eq(w.options.x, 316); A.eq(w.options.y, 116)
  A.eq(find(w, "AddItemGrid").args[1][1].tooltip, "Abyssal whip", "the item is shown at the top")
  H.tagBoxes(w).args[2].onChange(nil, nil, "sell", true)
  A.eq(H.window(env).options.x, 316, "redrawing keeps it next to where it opened")
  A.eq(H.window(env).options.y, 116)
  PluginShutdown()
end

-- Requirement: near the right or bottom edge of the screen the window opens
-- on the other side of the mouse, so it is never cut off.
function T.tags_window_stays_on_screen()
  local env = boot({ mouse = { x = 1250, y = 700 } })
  local w = H.tagsWindow(env, 103)
  A.eq(w.options.x, 1250 - 16 - 340, "left of the mouse")
  A.eq(w.options.y, 720 - 520, "pulled up to fit")
  PluginShutdown()
end

-- Requirement: without a readable mouse the window opens in its usual place.
function T.tags_window_without_a_mouse()
  local env = boot()
  local w = H.tagsWindow(env, 103)
  A.eq(w.options.x, 200); A.eq(w.options.y, 120)
  PluginShutdown()
end

-- Requirement: potions with a dose get the Decant opt-out in the Tags
-- window, other items do not.
function T.tags_window_offers_decanting_only_for_potions()
  local env = boot({ bank = { 111, 103, 102 } })
  A.eq(#find(H.tagsWindow(env, 103), "AddCheckboxButton").args[1], 1, "a whip has only Ignore")
  local boxes = find(H.tagsWindow(env, 111), "AddCheckboxButton")
  A.eq(boxes.args[1][2].value, "nodecant")
  boxes.args[2].onChange(nil, nil, "nodecant", true)
  A.eq(Store.new(PersistentDB):isNoDecant(111), true)
  PluginShutdown()
end

-- Requirement: Custom categories: create, add a rule, review matches,
-- remove and restore, rename, and delete with a confirm.
function T.custom_categories_window_end_to_end()
  local env = boot({ bank = { 109, 120, 103, 101 } })
  press(env, "Analyze Bank")
  press(env, "Custom categories")
  A.eq(H.window(env).options.title, "Custom categories")
  H.submit(env, "Dragon things")
  local store = Store.new(PersistentDB)
  A.eq(store:category("custom-1").name, "Dragon things")
  pick(H.comboWith(H.window(env), "contains"), "contains")
  H.submit(env, "dragon", 3)
  A.eq(Store.new(PersistentDB):category("custom-1").rules[1].text, "dragon")
  local w = H.window(env)
  A.truthy(texts(w):find("Dragon dagger", 1, true) and texts(w):find("Dragon bones", 1, true), "both matches are listed: " .. texts(w))
  local removes = {}
  for _, c in ipairs(w) do if c.method == "AddSimpleButton" and c.args[1] == "Remove" then removes[#removes + 1] = c end end
  removes[#removes].args[2]()
  A.eq(Store.new(PersistentDB).excluded["custom-1"][120], true, "Dragon bones removed from the category")
  A.truthy(texts(H.window(env)):find("Dragon bones  (removed)", 1, true))
  H.pressIn(env, "Restore")
  A.eq(Store.new(PersistentDB).excluded["custom-1"][120], nil, "restored")
  H.submit(env, "Dragon gear", 2)
  A.eq(Store.new(PersistentDB):category("custom-1").name, "Dragon gear", "renamed")
  H.assertIntegerIds(H.window(env))
  H.pressIn(env, "Delete category")
  A.eq(env.confirm.title, "DELETE CATEGORY")
  env.confirm.onConfirm()
  A.eq(#Store.new(PersistentDB).customCategories, 0)
  PluginShutdown()
end

-- Requirement: custom categories show up in the Whole bank Tab Layout, the
-- My tabs pin dropdown and the sidebar legend.
function T.custom_categories_appear_in_layouts_pins_and_the_legend()
  local env = boot({ bank = { 109, 120, 103 }, tabSizes = { 1 } })
  press(env, "Custom categories")
  H.submit(env, "Slayer")
  press(env, "Tab Layout")
  H.pressIn(env, "3")
  pick(H.comboWith(H.window(env), "custom-1"), "custom-1")
  A.eq(Store.new(PersistentDB).layout:destinationOf("custom-1"), 2)
  A.truthy(texts(panel(env)):find("Slayer", 1, true), "the legend names it: " .. texts(panel(env)))
  pick(H.comboWith(panel(env), "tabs"), "tabs")
  press(env, "Analyze Bank")
  press(env, "Tab Layout")
  H.pressIn(env, "2")
  pick(H.comboWith(H.window(env), "custom-1"), "custom-1")
  A.eq(Store.new(PersistentDB).tabHomes["custom-1"], 1, "pinned in My tabs")
  PluginShutdown()
end

-- Requirement: Custom tags: create with a placement, use it from the Tags
-- window, change the priority, edit and delete.
function T.custom_tags_window_end_to_end()
  local env = boot({ bank = { 103, 108, 102 } })
  press(env, "Analyze Bank")
  press(env, "Custom tags")
  local w = H.window(env)
  A.eq(w.options.title, "Custom tags")
  A.truthy(texts(w):find("1. Active", 1, true), "the priority list starts with Active")
  pick(H.comboWith(w, "label"), "label")
  H.submit(env, "Keep it")
  local store = Store.new(PersistentDB)
  A.eq(store:customTag("tag-1").label, "Keep i", "cut to 6 characters")
  A.eq(store:customTag("tag-1").placement, "label")
  local boxes = H.tagBoxes(H.tagsWindow(env, 103))
  A.eq(#boxes.args[1], 9, "the new tag is in the Tags window")
  H.setPlacement(env, 103, "tag-1")
  H.tick(env)
  A.eq(H.count(H.liveTexts(env), "Keep i"), 1, "its label shows on the whip")
  press(env, "Custom tags")
  local ups = {}
  for _, c in ipairs(H.window(env)) do if c.method == "AddSimpleButton" and c.args[1] == "Up" then ups[#ups + 1] = c end end
  ups[#ups].args[2]()
  local order = Store.new(PersistentDB).tagOrder
  A.eq(order[#order - 1], "tag-1", "moved up one place")
  H.pressIn(env, "Edit")
  H.pressIn(env, "Delete tag")
  env.confirm.onConfirm()
  A.eq(Store.new(PersistentDB):customTag("tag-1"), nil)
  A.eq(Store.new(PersistentDB):hasTag(103, "tag-1"), false, "removed from the whip too")
  PluginShutdown()
end

-- Requirement: a label-only tag never moves an item.
function T.label_only_tags_leave_items_where_they_are()
  local env = boot({ bank = { 103, 102 } })
  press(env, "Custom tags")
  pick(H.comboWith(H.window(env), "label"), "label")
  H.submit(env, "Note")
  press(env, "Analyze Bank")
  local before = H.texts(panel(env))
  H.setPlacement(env, 103, "tag-1")
  local after = H.texts(panel(env)):gsub("Tags: [^\n]*\n?", "")
  A.eq(after, (before:gsub("Tags: [^\n]*\n?", "")), "the plan did not change")
  PluginShutdown()
end

-- Requirement: Ignore wins over every tag.
function T.ignore_wins_over_tags()
  local env = boot({ bank = { 103, 102 } })
  press(env, "Analyze Bank")
  H.setPlacement(env, 103, "sell")
  H.setIgnore(env, 103, true)
  local found = false
  for _, c in ipairs(panel(env)) do
    if c.method == "AddText" and c.content and c.content:find("Tab 1 (infinity)", 1, true) then found = c.content end
  end
  A.truthy(found and found:find("(1)", 1, true), "only the coins are planned in infinity: " .. tostring(found))
  PluginShutdown()
end

-- Returns the Bank Cleaner checkbox for an item, or nil when it is not
-- listed.
local function cleanerBox(env, itemID)
  for _, c in ipairs(H.findAll(H.window(env), "AddCheckboxButton")) do
    if c.args[1][1].value == tostring(itemID) then return c end
  end
end

-- Requirement: the Bank Cleaner groups suggestions with reasons and never
-- suggests protected items. Ticking an item gives it its group's tag at
-- once (quest leftovers and low value Trash, worth alching Alch, review
-- Rev) and unticking takes it off; tagged items stay listed, ticked, and
-- get their label in the bank. Keep hides an item for good, and clearing
-- the Keep list asks first.
function T.bank_cleaner_window_end_to_end()
  local env = boot({ bank = { 117, 118, 116, 119, 121, 115, 114, 102 }, prices = { [119] = 30000 } })
  press(env, "Bank Cleaner")
  A.truthy(texts(H.window(env)):find("Press Analyze Bank first", 1, true))
  press(env, "Analyze Bank")
  press(env, "Bank Cleaner")
  local w = H.window(env)
  for _, header in ipairs({ "[-] Quest leftovers (1)", "[-] Worth more alched (1)", "[-] Low value (1)", "[-] Review (1)" }) do
    A.truthy(find(w, "AddSimpleButton", header), header .. " in " .. buttons(w))
  end
  A.eq(cleanerBox(env, 117).args[1][1].text, "Old quest note x1 (Trash)")
  A.eq(cleanerBox(env, 119).args[1][1].text, "Rune platelegs x1 (Alch)")
  A.eq(cleanerBox(env, 116).args[1][1].text, "Bucket x1 (Trash)")
  A.eq(cleanerBox(env, 121).args[1][1].text, "Strange relic x1 (Review)")
  for _, kept in ipairs({ 118, 115, 114, 102 }) do A.eq(cleanerBox(env, kept), nil, "item " .. kept .. " must never be suggested") end
  A.truthy(texts(w):find("Suggestions only", 1, true))
  -- Ticking tags straight away; each item keeps its box, now ticked.
  for _, case in ipairs({ { 117, "trash" }, { 119, "alch" }, { 116, "trash" }, { 121, "review" } }) do
    cleanerBox(env, case[1]).args[2].onChange(nil, nil, tostring(case[1]), true)
    A.eq(Store.new(PersistentDB):hasTag(case[1], case[2]), true, "item " .. case[1] .. " tagged " .. case[2])
    A.eq(cleanerBox(env, case[1]).args[1][1].selected, true, "still listed, ticked")
  end
  H.tick(env)
  A.eq(H.count(H.liveTexts(env), "Rev"), 1, "the review item shows Rev in its slot")
  A.eq(H.count(H.liveTexts(env), "Alch"), 1)
  -- Unticking takes the tag off again.
  cleanerBox(env, 116).args[2].onChange(nil, nil, "116", false)
  A.eq(Store.new(PersistentDB):hasTag(116, "trash"), false)
  A.eq(cleanerBox(env, 116).args[1][1].selected, false)
  -- Keep: the first row (the quest leftover) is kept and its tag removed.
  H.pressIn(env, "Keep")
  local store = Store.new(PersistentDB)
  A.eq(store:isKept(117), true); A.eq(store:hasTag(117, "trash"), false, "a kept item loses the cleaner's tag")
  A.eq(cleanerBox(env, 117), nil, "kept items leave the list")
  A.truthy(texts(H.window(env)):find("Old quest note is kept", 1, true))
  H.pressIn(env, "Clear Keep list")
  A.eq(env.confirm.title, "CLEAR KEEP LIST")
  env.confirm.onConfirm()
  A.eq(Store.new(PersistentDB):isKept(117), false)
  H.assertIntegerIds(H.window(env))
  PluginShutdown()
end

-- Requirement: every new window's dropdowns use whole-number ids.
function T.every_new_window_uses_integer_ids()
  local env = boot()
  press(env, "Analyze Bank")
  for _, label in ipairs({ "Custom tags", "Custom categories", "Bank Cleaner", "Settings", "Tab Layout", "Open Blueprint" }) do
    press(env, label)
    H.assertIntegerIds(H.window(env))
  end
  H.assertIntegerIds(H.tagsWindow(env, 103))
  PluginShutdown()
end

-- Requirement: the settings tab bar wraps onto a new row instead of running
-- past the edge of the window (the last tab used to be cut off): no row of
-- tabs is wider than the room inside the window.
function T.settings_tabs_wrap_to_fit()
  local env = boot()
  press(env, "Settings")
  local Widgets = require("src/ui/widgets")
  local room = Widgets.room(H.window(env).view, 470)
  local rows, widest = 0, 0
  local used = 0
  for _, c in ipairs(H.findAll(H.window(env), "AddSimpleButton")) do
    local page = c.args[1]:gsub("^%[", ""):gsub("%]$", "")
    for _, name in ipairs({ "General", "Sorting", "Tags & Labels", "Colours", "Cleaner" }) do
      if page == name then
        local size = Widgets.buttonWidth(c.args[1])
        if c.args[3] and c.args[3].inline then used = used + 8 + size else rows, used = rows + 1, size end
        if used > widest then widest = used end
      end
    end
  end
  A.truthy(rows >= 2, "five tabs do not fit one row, so they wrap")
  A.truthy(widest <= room, "no row runs past the edge: " .. widest .. " > " .. room)
  PluginShutdown()
end

-- Returns the scroll position a recording was restored to, or nil.
local function restoredTo(calls)
  local call = find(calls, "SetScrollPosition")
  return call and call.args[1]
end

-- Requirement: folding or opening a sidebar section keeps the sidebar
-- scrolled where it was instead of jumping back to the top.
function T.sidebar_keeps_its_scroll_position()
  local env = boot()
  panel(env).view.scrollY = 240
  press(env, "[-] Tools")
  A.eq(restoredTo(panel(env)), 240, "scrolled back to where it was")
  panel(env).view.scrollY = 0
  press(env, "[+] Tools")
  A.eq(restoredTo(panel(env)), nil, "at the top, nothing to restore")
  PluginShutdown()
end

-- Requirement: windows redrawn after a click keep their scroll position.
function T.windows_keep_their_scroll_position()
  local env = boot()
  press(env, "Custom tags")
  H.window(env).view.scrollY = 300
  local downs = H.findAll(H.window(env), "AddSimpleButton")
  for _, c in ipairs(downs) do if c.args[1] == "Down" then c.args[2](); break end end
  A.eq(restoredTo(H.window(env)), 300)
  PluginShutdown()
end

-- Requirement: the settings in the game's settings gear keep their scroll
-- position when a section is folded or a setting changes.
function T.settings_keep_their_scroll_position()
  local env = boot()
  local view = H.settingsPage(env, "General")
  env.settings[#env.settings].view.scrollY = 150
  find(view, "AddSimpleButton", "[-] Look").args[2]()
  A.eq(restoredTo(env.settings[#env.settings]), 150)
  PluginShutdown()
end

-- Requirement: the low value limit is a text box: typing 3b saves three
-- billion and shows "3b"; anything else explains what to type.
function T.low_value_is_typed()
  local env = boot()
  local page = H.settingsPage(env, "Cleaner")
  local field = H.findAll(page, "AddTextField")[1]
  A.eq(field.args[1].text, "1k", "the current limit, written short")
  field.args[1].onSubmit(nil, "3b")
  A.eq(Store.new(PersistentDB):get("cleanerThreshold"), 3000000000)
  local latest = env.settings[#env.settings]
  A.eq(H.findAll(latest, "AddTextField")[1].args[1].text, "3b")
  A.truthy(texts(latest):find("3,000,000,000 gp", 1, true), texts(latest))
  H.findAll(latest, "AddTextField")[1].args[1].onSubmit(nil, "lots")
  A.truthy(texts(env.settings[#env.settings]):find("Type an amount like", 1, true))
  A.eq(Store.new(PersistentDB):get("cleanerThreshold"), 3000000000, "a bad amount changes nothing")
  PluginShutdown()
end

-- Fails when anything in a recording could be cut off:
--   * text with a fixed height (PrettyUI only wraps text it can size itself)
--   * a dropdown entry longer than Widgets.MAX_CHOICE
--   * a checkbox label, or a row of text and buttons, wider than the room
local function assertNothingCutOff(calls, room, where)
  local Widgets = require("src/ui/widgets")
  local used = 0
  for _, c in ipairs(calls) do
    local options = type(c.args[1]) == "table" and c.args[1] or {}
    if c.method == "AddText" then
      A.eq(options.height, nil, where .. ": text with a fixed height: " .. tostring(options.text))
      used = Widgets.measure(c.content or "") + 4
    elseif c.method == "AddSimpleButton" then
      local size = Widgets.buttonWidth(c.args[1])
      used = (c.args[3] and c.args[3].inline) and (used + 8 + size) or size
      A.truthy(used <= room, where .. ": a row ending in " .. c.args[1] .. " is " .. used .. " wide, room " .. room)
    elseif c.method == "AddComboBox" then
      for _, entry in ipairs(options.entries) do
        A.truthy(#entry.label <= Widgets.MAX_CHOICE, where .. ": dropdown entry too long: " .. entry.label)
      end
      used = 0
    elseif c.method == "AddCheckboxButton" then
      for _, box in ipairs(c.args[1]) do
        A.truthy(Widgets.measure(box.text) + 22 <= room, where .. ": checkbox label too wide: " .. box.text)
      end
      used = 0
    else
      used = 0
    end
  end
end

-- Requirement: nowhere in the sidebar, the settings or any window is text
-- cut off: text wraps, and rows, labels and dropdown entries fit.
function T.nothing_is_cut_off_anywhere()
  local Widgets = require("src/ui/widgets")
  local env = boot({ bank = { 117, 116, 115, 114, 111, 103, 109, 120, 102 }, tabSizes = {} })
  press(env, "Analyze Bank")
  assertNothingCutOff(panel(env), Widgets.room(panel(env).view, 300), "sidebar")
  for _, page in ipairs({ "General", "Sorting", "Tags & Labels", "Colours", "Cleaner" }) do
    local view = H.settingsPage(env, page)
    assertNothingCutOff(view, Widgets.room(view.view, 300), "settings " .. page)
  end
  press(env, "Custom categories")
  H.submit(env, "A category with a long name here")
  H.submit(env, "dragon", 3)
  press(env, "Custom tags")
  pick(H.comboWith(H.window(env), "label"), "label")
  H.submit(env, "Note")
  for _, label in ipairs({ "Open Blueprint", "Tab Layout", "Share or Load a Setup", "Bank Cleaner", "Custom tags",
    "Custom categories", "Settings" }) do
    press(env, label)
    local w = H.window(env)
    assertNothingCutOff(w, Widgets.room(w.view, w.options.width), label)
  end
  local tags = H.tagsWindow(env, 111)
  assertNothingCutOff(tags, Widgets.room(tags.view, tags.options.width), "Tags window")
  pick(H.comboWith(panel(env), "tabs"), "tabs")
  press(env, "Tab Layout")
  assertNothingCutOff(H.window(env), Widgets.room(H.window(env).view, 470), "Tab Layout (My tabs)")
  PluginShutdown()
end

-- Returns where in a recording the first call of a method with a given
-- first argument is (its position in the list), or nil.
local function indexOf(calls, method, label)
  for index, c in ipairs(calls) do
    if c.method == method and c.args[1] == label then return index end
  end
end

-- Requirement: the Tools section sits right under the main buttons
-- (Analyze Bank, Sorting, Open Blueprint, Tab Layout) and above the
-- Organize and Your tabs sections.
function T.tools_sit_under_the_main_buttons()
  local env = boot()
  local p = panel(env)
  local tools = indexOf(p, "AddSimpleButton", "[-] Tools")
  A.truthy(tools, "Tools section shown")
  A.truthy(indexOf(p, "AddFancyButton", "Analyze Bank") < tools, "Tools below Analyze Bank")
  A.truthy(indexOf(p, "AddSimpleButton", "Tab Layout") < tools, "Tools below Tab Layout")
  A.truthy(tools < indexOf(p, "AddSimpleButton", "[-] Organize"), "Tools above Organize")
  A.truthy(tools < indexOf(p, "AddSimpleButton", "[-] Your tabs"), "Tools above Your tabs")
  PluginShutdown()
end

-- Acts out the player dragging a window: moves its root to x, y.
local function drag(recording, x, y)
  recording.view.root.x, recording.view.root.y = x, y
end

-- Requirement: a window the player dragged stays there when it is redrawn
-- after a change (ticking a box in the Bank Cleaner), instead of jumping
-- back to where it first opened.
function T.dragged_cleaner_stays_put_when_redrawn()
  local env = boot({ bank = { 117, 116 } })
  press(env, "Analyze Bank")
  press(env, "Bank Cleaner")
  drag(H.window(env), 300, 25)
  cleanerBox(env, 117).args[2].onChange(nil, nil, "117", true)
  A.eq(H.window(env).options.x, 300); A.eq(H.window(env).options.y, 25)
  PluginShutdown()
end

-- Requirement: the Tags window also stays where it was dragged when a
-- change redraws it.
function T.dragged_tags_window_stays_put_when_redrawn()
  local env = boot({ bank = { 111 } })
  local tags = H.tagsWindow(env, 111)
  drag(tags, 640, 90)
  find(tags, "AddCheckboxButton").args[2].onChange(nil, nil, "ignore", true)
  A.eq(H.window(env).options.title, "Tags")
  A.eq(H.window(env).options.x, 640); A.eq(H.window(env).options.y, 90)
  PluginShutdown()
end

-- Requirement: a window taller than the game is made shorter, so PrettyUI
-- does not pin it in place and it can be dragged. Its top starts inside
-- the game.
function T.tall_window_on_short_game_can_still_move()
  local env = boot({ bank = { 117 } })
  env.layer.height = 500
  press(env, "Bank Cleaner")
  local options = H.window(env).options
  A.eq(options.height, 460, "game height less the margin")
  A.truthy(options.y >= 0 and options.y <= 500 - options.height, "top inside the game, y = " .. tostring(options.y))
  PluginShutdown()
end

-- Requirement: on a very small game a window is never made shorter than
-- its minimum, and it never starts above or left of the game.
function T.tiny_game_keeps_minimum_height()
  local env = boot({ bank = { 117 } })
  env.layer.width, env.layer.height = 300, 200
  press(env, "Bank Cleaner")
  local options = H.window(env).options
  A.eq(options.height, 240); A.eq(options.x, 0); A.eq(options.y, 0)
  PluginShutdown()
end

-- Requirement: a window dragged past the edge (for example before the game
-- window was made smaller) is pulled back inside the game when redrawn.
function T.window_past_the_edge_is_pulled_back()
  local env = boot({ bank = { 117, 116 } })
  press(env, "Analyze Bank")
  press(env, "Bank Cleaner")
  drag(H.window(env), 5000, 5000)
  env.layer.width, env.layer.height = 1000, 700
  cleanerBox(env, 117).args[2].onChange(nil, nil, "117", true)
  local options = H.window(env).options
  A.eq(options.x, 1000 - options.width); A.eq(options.y, 700 - options.height)
  PluginShutdown()
end

-- Requirement: when the game's size cannot be read, a window opens exactly
-- as asked rather than failing.
function T.unknown_game_size_leaves_window_as_asked()
  local env = boot({ bank = { 117 } })
  env.layer.width, env.layer.height = nil, nil
  press(env, "Bank Cleaner")
  local options = H.window(env).options
  A.eq(options.height, 660); A.eq(options.x, 180); A.eq(options.y, 40)
  PluginShutdown()
end

return T
