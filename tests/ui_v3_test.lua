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
--   * right-click: a Tags submenu with every choice when PrettyUI has
--     MiniMenu.AddSubmenu, falling back to one entry otherwise
--   * Custom categories, Custom tags and Bank Cleaner windows work end to
--     end, and custom categories show up in Tab Layout, pins and the legend
--   * Ignore wins over tags
--   * every dropdown uses whole-number ids
--   * the version in the plugin matches plugin.json

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
  pick(H.comboWith(H.settingsPage(env, "Cleaner"), 5000), 5000)
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

-- Opens the right-click menu with the fake submenu helper and returns the
-- recorded submenu.
local function submenu(env, itemID)
  H.rightClick(env, itemID)
  return env.submenus[#env.submenus]
end

-- Returns the submenu child whose label ends with text.
local function child(menu, text)
  for _, entry in ipairs(menu.children) do
    if entry.label:sub(-#text) == text then return entry end
  end
end

-- Requirement: with MiniMenu.AddSubmenu, right-click shows a Tags submenu
-- with Category, Ignore, every tag and More, each toggling at once.
function T.right_click_tags_submenu()
  local env = boot({ submenu = true })
  press(env, "Analyze Bank")
  local added = H.rightClick(env, 103)
  A.eq(#added, 0, "no plain entry when the submenu is used")
  local menu = env.submenus[#env.submenus]
  A.eq(menu.label, "Tags (Bank Organizer)"); A.eq(menu.options.title, "Abyssal whip")
  local labels = {}
  for index, entry in ipairs(menu.children) do labels[index] = entry.label end
  A.list(labels, { "Category...", "[ ] Ignore", "[ ] Active", "[ ] Vanity", "[ ] Favourite", "[ ] Sell", "[ ] Alch",
    "[ ] Disassemble", "[ ] Trash", "More..." }, "no decant choice on a whip")
  child(menu, "Sell").action()
  A.eq(Store.new(PersistentDB):hasTag(103, "sell"), true)
  menu = submenu(env, 103)
  A.eq(child(menu, "Sell").label, "[x] Sell", "ticked next time")
  child(menu, "Sell").action()
  A.eq(Store.new(PersistentDB):hasTag(103, "sell"), false, "and toggled off again")
  child(submenu(env, 103), "Ignore").action()
  A.eq(Store.new(PersistentDB):isIgnored(103), true)
  child(submenu(env, 103), "Category...").action()
  A.eq(H.window(env).options.title, "Category: Abyssal whip")
  pick(find(H.window(env), "AddComboBox"), "boss-loot")
  A.eq(Store.new(PersistentDB).corrections[103], "boss-loot")
  child(submenu(env, 103), "More...").action()
  A.eq(H.window(env).options.title, "Tags: Abyssal whip")
  PluginShutdown()
end

-- Requirement: potions with a dose get the decant choice in the submenu.
function T.submenu_offers_decanting_only_for_potions()
  local env = boot({ submenu = true, bank = { 111, 112, 102 } })
  local entry = child(submenu(env, 111), "Never label for decanting")
  A.truthy(entry, "on a 3-dose prayer potion")
  entry.action()
  A.eq(Store.new(PersistentDB):isNoDecant(111), true)
  A.eq(child(submenu(env, 111), "Never label for decanting").label, "[x] Never label for decanting")
  PluginShutdown()
end

-- Requirement: when the submenu helper fails, the single entry still
-- appears, so the Tags window is always reachable.
function T.a_failing_submenu_falls_back_to_one_entry()
  local env = boot({ submenu = true })
  -- A helper that fails, like one from an incompatible PrettyUI.
  prettyui.MiniMenu.AddSubmenu = function() error("older PrettyUI") end
  local added = H.rightClick(env, 103)
  A.eq(#added, 1); A.eq(added[1].label, "Tags (Bank Organizer)")
  added[1].fn()
  A.eq(H.window(env).options.title, "Tags: Abyssal whip")
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
  A.eq(#boxes.args[1], 8, "the new tag is in the Tags window")
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

-- Requirement: the Bank Cleaner groups suggestions with reasons, never
-- suggests protected items, tags or keeps what the player ticks, and asks
-- before clearing the Keep list.
function T.bank_cleaner_window_end_to_end()
  local env = boot({ bank = { 117, 118, 116, 115, 114, 102 } })
  press(env, "Bank Cleaner")
  A.truthy(texts(H.window(env)):find("Press Analyze Bank first", 1, true))
  press(env, "Analyze Bank")
  press(env, "Bank Cleaner")
  local w = H.window(env)
  local text = texts(w)
  A.truthy(find(w, "AddSimpleButton", "[-] Quest leftovers (1)"), buttons(w))
  A.truthy(find(w, "AddSimpleButton", "[-] Low value (1)"), buttons(w))
  local rows = {}
  for _, c in ipairs(H.findAll(w, "AddCheckboxButton")) do
    for _, box in ipairs(c.args[1]) do rows[#rows + 1] = box.text end
  end
  local all = table.concat(rows, "\n")
  A.truthy(all:find("Old quest note", 1, true), all); A.truthy(all:find("Bucket", 1, true), all)
  for _, kept in ipairs({ "Unfinished quest key", "Bronze dagger", "Red partyhat", "Coins" }) do
    A.eq(all:find(kept, 1, true), nil, kept .. " must never be suggested")
  end
  A.truthy(text:find("Suggestions only", 1, true))
  H.pressIn(env, "Tag as Trash")
  A.truthy(texts(H.window(env)):find("Tick some items first", 1, true))
  local boxes = H.findAll(H.window(env), "AddCheckboxButton")
  boxes[#boxes].args[2].onChange(nil, nil, "116", true)
  H.pressIn(env, "Tag as Trash")
  A.eq(Store.new(PersistentDB):hasTag(116, "trash"), true)
  A.truthy(texts(H.window(env)):find("Tagged 1 as Trash.", 1, true))
  boxes = H.findAll(H.window(env), "AddCheckboxButton")
  boxes[1].args[2].onChange(nil, nil, "117", true)
  H.pressIn(env, "Keep")
  A.eq(Store.new(PersistentDB):isKept(117), true)
  A.eq(find(H.window(env), "AddSimpleButton", "[-] Quest leftovers (1)"), nil, "kept items leave the list")
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

return T
