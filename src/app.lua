-- Bank Organizer: the controller that ties everything together.
--
-- The App owns the current state of the plugin and runs its main loop:
--   1. Analyze: read the bank, classify every item and build the blueprint
--      (where every item belongs) with src/core/blueprint.lua.
--   2. Sorting Guide: every game tick, read the bank again, check the last
--      move the player made, and plan the next single move with
--      src/core/guide.lua. The overlay (src/game/overlay.lua) draws it.
--   3. Notify: whenever something visible changes, tell the sidebar and
--      windows to redraw through onChange listeners.
--
-- Important client facts this file relies on (all verified in game):
--   * The game stores tabs in a different order than it shows them. The
--     live mapping comes from BANK_TAB_k_MAPPING_SERVER (Bank.liveDisplayOrder)
--     and, as a backup, an order learned from the infinity view.
--   * After a move, the item order updates at once but the tab sizes can lag
--     a few ticks. Moves are therefore judged on the flat item order, and a
--     size override is used until the game catches up.
--   * Repeated unstackable items (like filled Ushabti) share one item id, so
--     each slot gets its own key: id + n * 2^24 (Bank.KEY_STRIDE).
--
-- Saved data uses real item ids (item.objectId); planning uses slot keys
-- (item.id), which equal the real id for ordinary items.

local Tags = require("src/core/tags")
local Blueprint = require("src/core/blueprint")
local Guide = require("src/core/guide")
local Verify = require("src/core/verify")
local TabOrder = require("src/core/tab_order")
local Bank = require("src/game/bank")
local Prices = require("src/game/prices")
local Overlay = require("src/game/overlay")
local Quests = require("src/game/quests")
local Sorting = require("src/core/sorting")
local Placement = require("src/core/placement")
local Cleaner = require("src/core/cleaner")
local Clues = require("src/core/clues")
local Custom = require("src/core/custom")
local Version = require("src/version")

local App = {}
App.__index = App

-- The plugin's version, shown in the sidebar and the settings footer.
App.VERSION = Version.NUMBER

-- The id this plugin subscribes to the game tick with.
local EVENT_ID = "bank-organizer:tick"

-- Every status line the sidebar can show (moves have their own wording, see
-- App.describe).
App.STATUS = {
  CLOSED = "Open your bank, then press Analyze Bank.",
  NOT_ANALYZED = "Press Analyze Bank to build your blueprint.",
  ANALYZED = "Blueprint ready. Open Blueprint to review it, or start the Sorting Guide.",
  NEED_ALL = "Open the All items view and clear the bank search to continue the guide.",
  NO_SEARCH = "Clear the bank search to continue the guide.",
  NEED_TABS = "My tabs needs your bank tab sizes, which this client is not reporting.",
  NO_TABS_YET = "You have no tabs yet, so My tabs follows your Tab Layout to create them.",
  NO_TABS = "This client does not expose bank tab sizes yet, so the guide is paused.",
  DONE = "Your bank matches the blueprint.",
  CHANGED = "Your bank changed, so the blueprint was rebuilt.",
}

-- Creates the App around a Store (src/core/store.lua).
function App.new(store)
  return setmetatable({
    store = store, overlay = Overlay.new(), listeners = {},
    items = nil, destinations = nil, bySlot = nil, signature = nil,
    guiding = false, step = nil, remaining = nil,
    status = App.STATUS.CLOSED, bankOpen = false,
  }, App)
end

-- Registers (or with fn = nil, removes) a listener under a name. Listeners
-- are called with the App whenever something visible changes. A new
-- listener is called once straight away so it can draw.
function App:onChange(key, fn)
  self.listeners[key] = fn
  if fn then pcall(fn, self) end
end

-- Calls every listener. A failing listener is skipped so one broken window
-- cannot stop the others.
function App:_notify()
  for _, fn in pairs(self.listeners) do pcall(fn, self) end
end

-- Changes the status line and notifies listeners when it actually changed.
function App:_setStatus(status)
  if status == self.status then return end
  self.status = status
  self:_notify()
end

-- The custom category data the resolver needs: definitions and review-list
-- removals.
function App:_custom()
  return { categories = self.store.customCategories, excluded = self.store.excluded }
end

-- Returns an item's kind of item, honouring the player's own choice, then
-- custom category rules, then the built-in classifier.
function App:tagOf(item)
  return Blueprint.resolver(self.store.corrections, self:_custom())(item)
end

-- Returns a short text that changes whenever the bank's items or amounts
-- change. Used to notice when the bank needs re-reading.
local function signatureOf(items)
  local parts = {}
  for index, item in ipairs(items) do parts[index] = item.id .. "x" .. item.quantity end
  return table.concat(parts, ",")
end

-- The two organize modes as the sidebar describes them.
App.SCOPES = { bank = "Whole bank (follow my Tab Layout)", tabs = "My tabs (keep my tabs, infinity is misc)" }

-- Builds the blueprint from a list of bank items.
--   allItems  every item from Bank.readItems
-- Ignored items are left out of the plan entirely. In My tabs mode the
-- player's real tabs are used when the client reports their sizes; with no
-- tabs at all, the Tab Layout is followed so new tabs can be started.
function App:_build(allItems)
  local items = {}
  for _, item in ipairs(allItems) do
    if not self.store:isIgnored(item.objectId or item.id) then items[#items + 1] = item end
  end
  -- The kind of each item, as the blueprint asks for it.
  local tagOf = function(item) return self:tagOf(item) end
  local mode = self.store:get("sort")
  if mode == "value" then self.priceSource = Prices.attach(items) end
  self.itemByKey = {}
  for _, item in ipairs(allItems) do self.itemByKey[item.id] = item end
  -- Work out which part-dose potions can be decanted (players can opt a
  -- potion out from its Tags window).
  local tagged = {}
  for _, item in ipairs(items) do
    if not self.store:isNoDecant(item.objectId or item.id) then
      tagged[#tagged + 1] = { id = item.id, name = item.name, quantity = item.quantity, tag = self:tagOf(item) }
    end
  end
  self.decant = Sorting.decantInfo(tagged)
  local opts = self:_buildOptions()
  self.tabCounts, self.noTabs = nil, false
  local sizes = self:tabSizes()
  local sections = sizes and self:_displaySections(allItems, sizes)
  if self.store:get("scope") == "tabs" then
    if not sizes then
      self.status = App.STATUS.NEED_TABS
    elseif App.countTabs(sections) == 0 then
      self.noTabs = true
    else
      self.destinations, self.bySlot, self.tabCounts, self.autoHomes = Blueprint.buildFromTabs(
        items, sections, tagOf, self.store.tabHomes, nil, mode, opts)
      self.tabTotal = App.countTabs(sections)
      self:_keepOrder(sections)
      return true
    end
  end
  self.destinations, self.bySlot = Blueprint.build(items, self.store.layout, tagOf, mode, opts)
  self:_keepOrder(sections)
  return true
end

-- Returns the highest tab position in a sections table (0 = no custom tabs).
function App.countTabs(sections)
  local total = 0
  for s in pairs(sections or {}) do if s > total then total = s end end
  return total
end

-- Applies "Keep my order" to the plan when that sort mode is chosen and the
-- bank's tabs are known.
function App:_keepOrder(sections)
  if self.store:get("sort") ~= "keep" or not sections then return end
  local sectionOf = {}
  for s, ids in pairs(sections) do for _, itemID in ipairs(ids) do sectionOf[itemID] = s end end
  Blueprint.keepOrder(self.destinations, sectionOf, Guide.sectionMap(self.destinations))
end

-- Returns the planned tab positions in order. Before Analyze it lists the
-- Tab Layout's tabs instead, so the sidebar always has something to show.
function App:destinationList()
  local list = {}
  for d in pairs(self.destinations or {}) do
    if type(d) == "number" then list[#list + 1] = d end
  end
  table.sort(list)
  if #list == 0 then for d = 0, self.store.layout:last() do list[#list + 1] = d end end
  return list
end

-- The Analyze Bank button: reads the bank and builds the blueprint.
-- Returns false when the bank is not open.
function App:analyze()
  local items = Bank.readItems()
  if not items then
    self:_setStatus(App.STATUS.CLOSED)
    return false
  end
  self.items, self.signature = items, signatureOf(items)
  self:_build(items)
  self.status = self.noTabs and App.STATUS.NO_TABS_YET or App.STATUS.ANALYZED
  self:_logDiagnostics(items)
  self:_saveExport(items)
  self:_notify()
  return true
end

-- Joins an item's right-click option names into one sorted line.
local function opsText(ops)
  local list = {}
  for op in pairs(ops or {}) do list[#list + 1] = op end
  table.sort(list)
  return table.concat(list, "|")
end

-- Saves a tab-separated table of every item's facts (and a description of
-- the bank interface) into PersistentDB under bank-organizer-export and
-- bank-organizer-ui. These are read from the client's PluginData.db when a
-- player reports a wrong classification.
function App:_saveExport(items)
  local db = rawget(_G, "PersistentDB")
  if not db then return end
  local sizes = Bank.tabSizes()
  local sectionOf = {}
  if sizes then
    local sections = Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst)
    for s, ids in pairs(sections) do for _, itemID in ipairs(ids) do sectionOf[itemID] = s end end
  end
  local lines = { "slot\tid\tname\tcategory\tops\ttradeable\tquests\tstockmarket\ttab\ttag\tparams" }
  for _, item in ipairs(items) do
    local info = item.info or {}
    lines[#lines + 1] = table.concat({ item.slot, item.objectId or item.id, tostring(item.name), tostring(info.category), opsText(info.ops),
      tostring(info.tradeable), tostring(info.quests), tostring(info.stockmarket), tostring(sectionOf[item.id]),
      self:tagOf(item), info.params or "" }, "\t")
  end
  pcall(function() return db:SetString("bank-organizer-export", table.concat(lines, "\n")) end)
  local container = Bank.slotsContainer()
  if container then
    pcall(function() return db:SetString("bank-organizer-ui", Bank.describeInterface(container)) end)
  end
end

-- Writes one line to the client log describing the bank: item count, the
-- open tab, insert mode, tab sizes and the first item of each tab.
function App:_logDiagnostics(items)
  if not log then return end
  local sizes = Bank.tabSizes()
  local parts = { "[bank-organizer] slots=" .. #items, "tab=" .. tostring(Bank.currentTab()),
    "insert=" .. tostring(Bank.insertMode()), "sizes=" .. (sizes and table.concat(sizes, ",") or "unreadable") }
  if sizes then
    local sections = Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst)
    for s = 0, #sizes do
      local first = sections[s] and sections[s][1]
      if first then parts[#parts + 1] = (s == 0 and "main" or ("tab" .. s)) .. "=" .. self:_name(first) end
    end
  end
  log(table.concat(parts, " "))
end

-- Returns the name of the item with a given slot key, or the key as text.
function App:_name(itemID)
  for _, item in ipairs(self.items or {}) do if item.id == itemID then return item.name end end
  return tostring(itemID)
end

-- Rebuilds the blueprint from the last bank read (after any setting or tag
-- change) and notifies listeners.
function App:rebuild()
  if self.items then
    self:_build(self.items)
  end
  self:_notify()
end

-- Returns the planned tab position of an item and its planned entry, or nil
-- when the item is not in the plan (ignored, or no Analyze yet).
function App:destinationOfItem(itemID)
  if not self.destinations then return nil end
  for _, d in ipairs(self:destinationList()) do
    for _, entry in ipairs(self.destinations[d] or {}) do
      if entry.id == itemID then return d, entry end
    end
  end
  return nil
end

-- Returns true when the current plan was built in My tabs mode.
function App:myTabs()
  return self.tabCounts ~= nil
end

-- Returns where a kind of item goes in My tabs and whether that is a pin:
-- (position, true) for a pin, (position, false) for its automatic home, or
-- (nil, false) when it stays wherever it is.
function App:tabHomeOf(tag)
  local pin = self.store.tabHomes[tag]
  local list = self:destinationList()
  if pin and pin <= list[#list] then return pin, true end
  local home = self.autoHomes and self.autoHomes[tag]
  if home then return home.section, false end
  return nil, false
end

-- Returns the tint colour for a tab position.
-- Whole bank: the colour of the first kind the tab holds.
-- My tabs: the infinity tab uses the Storage & Cleanup grey and the other
-- tabs cycle through the built-in category colours.
function App:destinationColour(d)
  if self:myTabs() then
    if d == 0 then return self.store:colour("storage-cleanup") end
    local builtIn = Tags.DESTINATIONS
    local category = Tags.CATEGORIES[((d - 1) % (builtIn - 1)) + 1]
    return self.store:colour(category.key)
  end
  local first = (self.store.layout.destinations[d] or {})[1]
  local category = first and Tags.categoryOf(first)
  return self.store:colour(category and category.key or "storage-cleanup")
end

-- Returns the kinds a tab holds as one short line, for summaries. My tabs
-- lists the three most common kinds; Whole bank lists the layout's kinds.
function App:kindsSummary(d)
  local kinds = {}
  if self:myTabs() then
    if d == 0 then return "Misc catch-all" end
    for _, entry in ipairs(Blueprint.profile(self.tabCounts, d, 3)) do kinds[#kinds + 1] = Tags.label(entry.tag) end
  else
    for _, tag in ipairs(self.store.layout.destinations[d] or {}) do kinds[#kinds + 1] = Tags.label(tag) end
  end
  return #kinds > 0 and table.concat(kinds, ", ") or "empty"
end

-- Returns the title of a tab for lists: "Tab 3" plus its name in Whole bank
-- mode, or plus "(moving to Tab n)" in My tabs when a rearrangement is
-- pending.
function App:destinationTitle(d)
  if self:myTabs() then
    local target = self:arrangedPosition(d)
    local moving = target and target ~= d and (" (moving to Tab " .. (target + 1) .. ")") or ""
    return Tags.destinationName(d) .. moving
  end
  local layout = self.store.layout
  return Tags.destinationName(d) .. (layout.names[d] and (" " .. layout.names[d]) or "")
end

-- Returns the full one-line description of a tab: its title and what it
-- holds, for example "Tab 2 Combat: Combat Gear, Ammunition".
function App:destinationLabel(d)
  if self:myTabs() and d == 0 then return "Tab 1 (infinity): misc catch-all" end
  return self:destinationTitle(d) .. ": " .. self:kindsSummary(d)
end

-- Returns the name the guide uses for a tab, for example "Tab 3 (Herblore)".
--   section      the tab position on screen
--   destination  optional planned position whose layout name to show
function App:tabName(section, destination)
  local name = Tags.destinationName(section)
  local layout = self.store.layout
  local first = destination and (layout.destinations[destination] or {})[1]
  local custom = not self:myTabs() and destination and (layout.names[destination] or (first and Tags.label(first)))
  return custom and (name .. " (" .. custom .. ")") or name
end

-- The "Copy my current tabs" button: turns the player's current tabs into a
-- Tab Layout. Each kind goes to the tab that holds most of it, and each tab
-- is named after its most common kind. Returns false before Analyze.
function App:copyCurrentTabs()
  local sizes = self.items and Bank.tabSizes()
  if not sizes then return false end
  -- The kind of each item, as the blueprint asks for it.
  local tagOf = function(item) return self:tagOf(item) end
  local sections = self:_displaySections(self.items, sizes)
  local _, _, counts, homes = Blueprint.buildFromTabs(self.items, sections, tagOf)
  local last = 0
  for s in pairs(sections) do if s > last then last = s end end
  local sectionOf, names = {}, {}
  for tag, home in pairs(homes) do sectionOf[tag] = home.section end
  for s = 1, last do
    local top = Blueprint.profile(counts, s, 1)[1]
    names[s] = top and Tags.label(top.tag) or nil
  end
  self.store.layout:copyTabs(last, sectionOf, names)
  self.store:save()
  self:rebuild()
  return true
end

-- Collects the options the blueprint needs from the current settings.
-- Decant information is only passed while decant labels are on: with labels
-- off, part doses stay grouped with their potion and nothing sinks.
function App:_buildOptions()
  return {
    -- Tags are saved by real item id, so per-copy keys are not used here.
    tagsOf = function(item) return self.store:tagsOf(item.objectId or item.id) end,
    order = self.store.tagOrder,
    decant = self.store:get("decant") and self.decant or nil,
    secondaries = self.store:get("secondaries"),
    vertical = self.store:get("direction") == "vertical",
    columns = self.columns,
  }
end

-- Opts a potion in or out of Decant labels and rebuilds.
function App:setNoDecant(objectId, on)
  self.store:setNoDecant(objectId, on)
  self:rebuild()
end

-- Keeps My tabs pins attached to their tab when the player drags tabs into
-- a new order: a pin on stored tab X follows X to its new position.
function App:_followTabs()
  local old, current = self.lastContainerOf, self.containerOf
  self.lastContainerOf = current
  if not old then return end
  local changed = false
  for tag, pin in pairs(self.store.tabHomes) do
    local moved = pin > 0 and old[pin] and self.displayOf[old[pin]]
    if moved and moved ~= pin then
      self.store.tabHomes[tag], changed = moved, true
    end
  end
  if changed then self.store:save() end
end

-- Returns the stored tab shown at each position right now.
function App:_currentArrangement()
  local list = {}
  for position = 1, self.tabTotal or 0 do list[position] = self.containerOf and self.containerOf[position] end
  return list
end

-- Returns the saved tab rearrangement when it still fits the bank, or nil.
function App:_validArrangement()
  local arrangement = self.store.arrangement
  if not arrangement or not self.containerSections then return nil end
  if #arrangement ~= (self.tabTotal or 0) or not TabOrder.fits(arrangement, self.containerSections) then return nil end
  return arrangement
end

-- Returns the position a tab is being moved to by a pending rearrangement,
-- or nil when none is pending.
function App:arrangedPosition(d)
  local arrangement = self:_validArrangement()
  local c = arrangement and self.containerOf and self.containerOf[d]
  if not c then return nil end
  for position, wanted in ipairs(arrangement) do if wanted == c then return position end end
  return nil
end

-- My tabs "Move left / Move right": swaps a tab with its neighbour in the
-- requested order. The guide then asks for one tab drag. Returns false when
-- the move is not possible.
function App:moveMyTab(d, direction)
  local total = self.tabTotal or 0
  if not self:myTabs() or d < 1 or d > total then return false end
  local arrangement = {}
  for position, c in ipairs(self:_validArrangement() or self:_currentArrangement()) do arrangement[position] = c end
  local from = self:arrangedPosition(d) or d
  local to = from + direction
  if to < 1 or to > total then return false end
  arrangement[from], arrangement[to] = arrangement[to], arrangement[from]
  -- Moving back to the current order cancels the request.
  local current, same = self:_currentArrangement(), true
  for position = 1, total do if current[position] ~= arrangement[position] then same = false end end
  self.store:setArrangement(not same and arrangement or nil)
  self:rebuild()
  return true
end

-- Cancels a requested tab rearrangement.
function App:resetMyTabOrder()
  self.store:setArrangement(nil)
  self:rebuild()
end

-- Returns the next tab drag needed for a requested rearrangement, or nil
-- when the tabs are already in that order (the request is then cleared).
function App:_tabArrangementStep()
  if not self:myTabs() then return nil end
  local arrangement = self:_validArrangement()
  if not arrangement then
    if self.store.arrangement then self.store:setArrangement(nil) end
    return nil
  end
  local current = self:_currentArrangement()
  for position, wanted in ipairs(arrangement) do
    if current[position] ~= wanted then
      for from, c in ipairs(current) do
        if c == wanted then return { kind = "tab-move", from = from, to = position } end
      end
    end
  end
  self.store:setArrangement(nil)
  return nil
end

-- Returns the set of tags on an item (tag key -> true).
function App:tagsOf(objectId)
  return self.store:tagsOf(objectId)
end

-- Adds or removes one tag on an item, then rebuilds and re-plans. Any
-- half-checked move or correction is dropped because the plan changed.
-- Returns false when the tag or item is invalid.
function App:setTag(objectId, key, on)
  if not self.store:setTag(objectId, key, on) then return false end
  self.pending, self.correction = nil, nil
  self:rebuild()
  if self.guiding then self:_tickGuide() end
  return true
end

-- Returns the label to draw in a slot and its colour setting key, or nil.
--   key  the slot's item key
-- A tag label wins; otherwise a Decant label is shown on part doses that can
-- be combined, when decant labels and that dose are switched on.
function App:slotLabel(key)
  local item = self.itemByKey and self.itemByKey[key]
  if not item then return nil end
  local placed = Placement.resolve(self.store:tagsOf(item.objectId or item.id), self:tagOf(item), self.store.tagOrder)
  if placed.label then return placed.label.badge, Placement.colourKey(placed.label.key) end
  local decant = self.store:get("decant") and self.decant and self.decant[key]
  if decant and decant.canDecant and self.store:get("decant" .. decant.dose) then
    return Placement.DECANT.badge, Placement.colourKey(Placement.DECANT.key)
  end
  return nil
end

-- Learns how many slots the bank shows per row from the slots on screen.
-- Vertical sort needs this; when it changes, the plan is rebuilt.
function App:noteColumns(slots)
  local perRow, columns = {}, 0
  for _, slot in ipairs(slots) do
    perRow[slot.y] = (perRow[slot.y] or 0) + 1
    if perRow[slot.y] > columns then columns = perRow[slot.y] end
  end
  if columns < 2 or columns == self.columns then return end
  self.columns = columns
  if self.store:get("direction") == "vertical" and self.items then
    self:_build(self.items)
    self:_notify()
  end
end

-- Returns a one-line count of tagged and ignored items for the sidebar, for
-- example "Sell 2, Trash 1, Ignored 3". Empty when nothing is tagged.
function App:tagSummary()
  local counts = self.store:markCounts()
  local parts = {}
  for _, placement in ipairs(Placement.LIST) do
    local n = counts[placement.key]
    if n and n > 0 then parts[#parts + 1] = placement.label .. " " .. n end
  end
  local ignored = self.store:ignoredCount()
  if ignored > 0 then parts[#parts + 1] = "Ignored " .. ignored end
  return table.concat(parts, ", ")
end

-- The Start Sorting button: analyzes first when needed, then starts the
-- guide on this tick.
function App:startGuide()
  if not self.destinations and not self:analyze() then return end
  self.guiding, self.pending, self.correction, self.step, self.lastRead = true, nil, nil, nil, nil
  self:_tickGuide()
  self:_notify()
end

-- The Stop Sorting button.
function App:stopGuide()
  self.guiding, self.step, self.remaining, self.pending, self.correction = false, nil, nil, nil, nil
  self:_notify()
end

-- Splits the bank into tabs in the order the game SHOWS them.
--   items  bank items in stored order
--   sizes  the tab sizes the game reports (stored order)
-- Uses the live tab mapping when it fits the bank, else the learned order.
-- Also records the stored/shown position maps the guide and overlay need.
function App:_displaySections(items, sizes)
  local container = Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst)
  local live = Bank.liveDisplayOrder()
  local order = TabOrder.fits(live, container) and live or self.store.displayOrder
  self.displayOf, self.containerOf = TabOrder.maps(order, container)
  self.containerSections = container
  self:_followTabs()
  self.containerSequence = TabOrder.containerSequence(self.displayOf, self.containerOf, Bank.TAB_VARS.tabsFirst)
  self.displaySections = TabOrder.toDisplay(container, self.displayOf)
  return self.displaySections
end

-- A tab counts as "on screen" when at least this share of the visible items
-- belong to it (some items can be shared between tabs).
App.VIEW_MAJORITY = 0.8

-- Works out which tab the player is looking at from the items on screen,
-- because the game's current-tab variable is not reliable. Returns the tab
-- position, or nil when no single tab clearly dominates.
function App:_viewedSection(sections)
  local slots = Bank.scan()
  if not slots or #slots == 0 then return nil end
  local sectionOf, shared = {}, {}
  for s, keys in pairs(sections) do
    for _, key in ipairs(keys) do
      local real = Bank.realId(key)
      if sectionOf[real] ~= nil and sectionOf[real] ~= s then shared[real] = true end
      sectionOf[real] = s
    end
  end
  -- Each visible item votes for its tab; items found in several tabs abstain.
  local votes, total, best = {}, 0, nil
  for _, slot in ipairs(slots) do
    local s = not shared[slot.objectID] and sectionOf[slot.objectID]
    if s then
      votes[s], total = (votes[s] or 0) + 1, total + 1
      if best == nil or votes[s] > votes[best] then best = s end
    end
  end
  if best == nil or votes[best] < total * App.VIEW_MAJORITY then return nil end
  return best
end

-- Works out which tabs already match the plan exactly.
-- Returns sorted (position -> true/false) and sectionOfKey (item key ->
-- position). Results are cached until the bank or the plan changes.
function App:sortedSections()
  if not self.destinations or not self.displaySections then return {}, {} end
  local key = tostring(self.signature) .. "|" .. tostring(self.sizesKey) .. "|" .. tostring(self.destinations) .. "|" .. tostring(self.displaySections)
  if key == self.sortedKey then return self.sorted, self.sectionOfKey end
  local targets = Guide.targetSections(self.destinations)
  local planned = {}
  for _, target in pairs(targets) do for _, id in ipairs(target) do planned[id] = true end end
  local sorted, sectionOfKey = {}, {}
  for s, keys in pairs(self.displaySections) do
    local list = {}
    for _, k in ipairs(keys) do
      sectionOfKey[k] = s
      if planned[k] then list[#list + 1] = k end
    end
    -- A tab is sorted when its planned items are exactly its target, in order.
    local target = targets[s] or {}
    local same = #target > 0 and #list == #target
    for index = 1, #target do if list[index] ~= target[index] then same = false end end
    sorted[s] = same
  end
  self.sorted, self.sectionOfKey, self.sortedKey = sorted, sectionOfKey, key
  return sorted, sectionOfKey
end

-- Returns how many planned tabs are sorted and how many there are, for the
-- sidebar's "Sorted tabs X / Y". Returns nil before the bank's tabs are
-- known.
function App:sortedCount()
  local sorted = self:sortedSections()
  if not next(sorted) then return nil end
  local done, total = 0, 0
  for _, d in ipairs(self:destinationList()) do
    if #(self.destinations and self.destinations[d] or {}) > 0 then
      total = total + 1
      if sorted[d] then done = done + 1 end
    end
  end
  return done, total
end

-- Returns true when the item in this slot sits in a fully sorted tab.
function App:isSortedSlot(key)
  local sorted, sectionOfKey = self:sortedSections()
  local s = sectionOfKey[key]
  return s ~= nil and sorted[s] == true
end

-- Gives every on-screen slot its per-slot key when the bank holds repeated
-- unstackable items. Without this, several filled Ushabti would all look
-- like one item and the arrow could point at the wrong copy.
--   slots  the scanned slots (slot.key is changed in place)
-- Copies are matched tab by tab in order: the n-th copy on screen in a tab
-- gets the n-th key planned for that tab.
function App:assignSlotKeys(slots)
  local shown = self.displaySections
  if not shown then return end
  local seen, repeated = {}, false
  for _, slot in ipairs(slots) do
    if seen[slot.objectID] then repeated = true end
    seen[slot.objectID] = true
  end
  if not repeated then return end
  -- Work out which tab each visible slot belongs to.
  local sectionOfSlot = {}
  local view = Bank.currentTab()
  if view == 1 then
    -- The infinity view shows every tab: the infinity tab's items first,
    -- then each custom tab in order.
    local blocks, total, last = { 0 }, #(shown[0] or {}), 0
    for d in pairs(shown) do if d > last then last = d end end
    for d = 1, last do
      blocks[#blocks + 1] = d
      total = total + #(shown[d] or {})
    end
    if total ~= #slots then return end
    local index = 1
    for _, d in ipairs(blocks) do
      for _ = 1, #(shown[d] or {}) do sectionOfSlot[index], index = d, index + 1 end
    end
  elseif type(view) == "number" and shown[view - 1] then
    for index = 1, #slots do sectionOfSlot[index] = view - 1 end
  else
    return
  end
  -- keysOf[tab][real id] = the keys planned for that item in that tab.
  local keysOf, used = {}, {}
  for d, keys in pairs(shown) do
    keysOf[d] = {}
    for _, key in ipairs(keys) do
      local real = Bank.realId(key)
      keysOf[d][real] = keysOf[d][real] or {}
      table.insert(keysOf[d][real], key)
    end
  end
  for index, slot in ipairs(slots) do
    local d = sectionOfSlot[index]
    local list = d and keysOf[d] and keysOf[d][slot.objectID]
    if list then
      used[d] = used[d] or {}
      local n = (used[d][slot.objectID] or 0) + 1
      used[d][slot.objectID] = n
      slot.key = list[n] or slot.key
    end
  end
end

-- Learns the order the game shows its tabs in, from the infinity view.
-- Only runs when the view, bank or sizes changed, and only with no search.
function App:_learnTabOrder()
  if not Bank.isAllItemsTab() or Bank.searchActive() then return end
  local items = Bank.readItems()
  local sizes = self:tabSizes()
  if not items or not sizes then return end
  local key = signatureOf(items) .. "|" .. table.concat(sizes, ",")
  if key == self.learnKey then return end
  self.learnKey = key
  local slots = Bank.scan()
  if not slots then return end
  -- Only items that appear once can be trusted to tell tabs apart.
  local copies, displayIds = {}, {}
  for _, slot in ipairs(slots) do copies[slot.objectID] = (copies[slot.objectID] or 0) + 1 end
  for _, slot in ipairs(slots) do
    if copies[slot.objectID] == 1 then displayIds[#displayIds + 1] = slot.objectID end
  end
  local order = TabOrder.learn(displayIds, Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst))
  if order and self.store:setDisplayOrder(order) and self.items then
    self:_build(self.items)
  end
end

-- Returns the bank's tab sizes. While the game's sizes lag behind a move
-- that has already happened, the sizes worked out from the move are used
-- instead (sizeOverride), until the game reports something new.
function App:tabSizes()
  local raw = Bank.tabSizes()
  local override = self.sizeOverride
  if raw and override and override.game == table.concat(raw, ",") then return override.sizes end
  self.sizeOverride = nil
  return raw
end

-- Returns the bank's tabs as shown, plus a reason when the guide cannot run,
-- plus (in My tabs) the tab the player is looking at.
function App:_sections(items)
  local sizes = self:tabSizes()
  if not sizes then return nil, App.STATUS.NO_TABS end
  if Bank.searchActive() then return nil, App.STATUS.NO_SEARCH end
  local sections = self:_displaySections(items, sizes)
  if self:myTabs() then
    local tab = Bank.currentTab()
    if tab == 1 then return sections end
    local viewed = self:_viewedSection(sections) or (type(tab) == "number" and tab > 1 and tab - 1) or nil
    if not viewed then return nil, App.STATUS.NO_TABS end
    return sections, nil, viewed
  end
  if not Bank.isAllItemsTab() then return nil, App.STATUS.NEED_ALL end
  return sections
end

-- Returns the rearrange mode to plan for: the game's own insert/swap setting
-- when it is readable, else the player's setting.
function App:modeForGuide()
  local insert = Bank.insertMode()
  if insert == nil then return self.store:get("mode") end
  return insert and Guide.INSERT or Guide.SWAP
end

-- The bank must read the same this many ticks in a row before a move is
-- judged, so a half-finished update is never mistaken for a wrong move.
App.SETTLE_READS = 2

-- Returns true once the bank has read the same SETTLE_READS times in a row
-- (or straight away when no move is waiting to be checked).
function App:_settled(sections)
  if self.lastRead and Verify.same(self.lastRead, sections) then
    self.reads = self.reads + 1
  else
    self.lastRead, self.reads = Verify.copy(sections), 1
  end
  return self.reads >= App.SETTLE_READS or self.step == nil
end

-- One tick of the Sorting Guide:
--   1. re-read the bank and rebuild the plan if it changed
--   2. wait for the bank to settle after a move
--   3. check the last move (and walk the player back after a mistake)
--   4. ask for a tab drag if a rearrangement is pending
--   5. otherwise plan the next item move and update the status line
function App:_tickGuide()
  local items = Bank.readItems()
  if not items then return self:_setStatus(App.STATUS.CLOSED) end
  local sizes = table.concat(self:tabSizes() or {}, ",")
  if signatureOf(items) ~= self.signature or sizes ~= self.sizesKey then
    local before = self.signature
    self.items, self.signature, self.sizesKey = items, signatureOf(items), sizes
    self:_build(items)
    if before and #before ~= #self.signature then self.status = App.STATUS.CHANGED end
  end
  local sections, reason, focus = self:_sections(items)
  if not sections then
    self.step = nil
    return self:_setStatus(reason)
  end
  self.settling = not self:_settled(sections)
  if self.settling then return end
  local mode = self:modeForGuide()
  self.focus, self.sections = focus, sections
  -- A correct move whose tab sizes lag: rebuild with the worked-out sizes.
  if self:_checkMove(items, sections) == "resync" then
    self:_build(items)
    sections, reason, focus = self:_sections(items)
    if not sections then return self:_setStatus(reason) end
    self.focus, self.sections, self.lastRead, self.reads = focus, sections, Verify.copy(sections), App.SETTLE_READS
  end
  if self:_correcting(sections, mode) then return end
  local tabStep = self:_tabArrangementStep()
  if tabStep then
    self.step, self.remaining, self.pending = tabStep, nil, nil
    return self:_setStatus(App.describe(tabStep, self))
  end
  self.step = Guide.next(sections, self.destinations, mode, focus)
  self.remaining = Guide.remaining(sections, self.destinations, mode, focus)
  self.pending = self.step and { step = self.step, before = Verify.copy(sections) } or nil
  self:_setStatus(self.step and App.describe(self.step, self) or self:_doneMessage(sections, mode, focus))
end

-- Returns true when the guide has nothing left to do anywhere.
function App:isDone()
  return self.status == App.STATUS.DONE
end

-- Returns the status line once the viewed tab (or the whole bank) is done.
-- In My tabs, it names the next tab that still needs work.
function App:_doneMessage(sections, mode, focus)
  if focus == nil then return App.STATUS.DONE end
  local next = Guide.next(sections, self.destinations, mode)
  if not next then return App.STATUS.DONE end
  local section = next.from or next.section or 0
  return self:tabName(focus) .. " is organized. Open " .. self:tabName(section) .. " next."
end

-- Returns the bank's item keys in stored order.
local function flatIds(items)
  local flat = {}
  for index, item in ipairs(items) do flat[index] = item.id end
  return flat
end

-- Checks the move the player just made against the move that was asked for.
--   "done"     the right move: when the tab sizes lag, records the expected
--              sizes and returns "resync"
--   "mistake"  a wrong move: starts a correction that walks it back
-- Judged on the flat item order, because item order updates at once while
-- tab sizes can lag.
function App:_checkMove(items, sections)
  local pending = self.pending
  if not pending or self.correction then return end
  local flat = flatIds(items)
  local verdict, expected = Verify.check(pending.before, flat, sections, pending.step, self.containerSequence)
  if verdict == "done" and expected and not Verify.same(expected, sections) then
    local game = Bank.tabSizes()
    if game then
      local sizes = {}
      for c = 1, #game do sizes[c] = #(expected[self.displayOf[c] or c] or {}) end
      self.sizeOverride = { game = table.concat(game, ","), sizes = sizes }
      return "resync"
    end
  elseif verdict == "mistake" then
    self.correction = { target = pending.before, step = pending.step }
    self.pending = nil
    self:_recordMistake(Verify.describe(Verify.flatten(pending.before, self.containerSequence), flat, pending.step)
      .. " sizes=" .. table.concat(Bank.tabSizes() or {}, ","))
  end
end

-- Logs a wrong move and keeps the last 20 in PersistentDB under
-- bank-organizer-debug, so a reported problem can be diagnosed.
function App:_recordMistake(line)
  if log then log("[bank-organizer] move check: " .. line) end
  self.mistakes = self.mistakes or {}
  table.insert(self.mistakes, line)
  while #self.mistakes > 20 do table.remove(self.mistakes, 1) end
  local db = rawget(_G, "PersistentDB")
  if db then pcall(function() return db:SetString("bank-organizer-debug", table.concat(self.mistakes, "\n")) end) end
end

-- While a correction is active, plans the move that puts the bank back to
-- how it was before the mistake. Returns true while correcting. The
-- correction ends when the bank matches again, or when items were added or
-- removed (the old layout no longer applies).
function App:_correcting(sections, mode)
  local correction = self.correction
  if not correction then return false end
  if not Verify.sameItems(correction.target, sections) or Verify.same(correction.target, sections) then
    self.correction = nil
    return false
  end
  local step = Verify.restoreStep(sections, correction.target, mode)
  if not step then
    self.correction = nil
    return false
  end
  self.step, self.remaining, self.pending = step, nil, nil
  self:_setStatus("Not quite: that wasn't the move. Put it back first. " .. App.describe(step, self))
  return true
end

-- Returns true when the guide must never move this item.
function App:isIgnored(itemID)
  return self.store:isIgnored(itemID)
end

-- Starts or stops ignoring an item, then rebuilds and re-plans.
function App:toggleIgnore(itemID)
  self.store:setIgnored(itemID, not self.store:isIgnored(itemID))
  self.pending, self.correction = nil, nil
  self:rebuild()
  if self.guiding then self:_tickGuide() end
end

-- The "Continue from here" button: accepts the bank as it is after a wrong
-- move instead of walking it back.
function App:continueFromHere()
  self.correction, self.pending = nil, nil
  if self.guiding then self:_tickGuide() end
  self:_notify()
end

-- Returns the name of the item with a given key, for guide messages.
local function nameOf(app, id)
  for _, item in ipairs(app.items or {}) do
    if item.id == id then return item.name end
  end
  return "item " .. tostring(id)
end

-- Returns " (n left)" while the guide knows how many moves remain, else "".
function App.left(app)
  return app.remaining and string.format(" (%d left)", app.remaining) or ""
end

-- Turns a planned step into the sentence shown in the sidebar.
function App.describe(step, app)
  local name = nameOf(app, step.id or step.move)
  if step.kind == "tab-move" then
    return string.format("Drag the %s button onto %s to rearrange your tabs.", app:tabName(step.from), app:tabName(step.to))
  end
  if step.kind == "new-tab" then
    return string.format("Drag %s onto the + button to start %s.", name, app:tabName(step.to, step.destination))
  elseif step.kind == "to-tab" then
    return string.format("Drag %s onto %s.", name, app:tabName(step.to, step.destination))
  elseif step.kind == "insert" then
    local anchor = step.before and ("before " .. nameOf(app, step.before)) or ("after " .. nameOf(app, step.after))
    return string.format("Insert %s %s%s.", name, anchor, App.left(app))
  end
  return string.format("Swap %s with %s%s.", name, nameOf(app, step.swapWith), App.left(app))
end

-- Returns where Value sort gets its prices: "live", "loading" or "none".
function App:valueSource()
  return self.priceSource or Prices.source()
end

-- Rebuilds the plan once GE prices finish loading, so Value sort uses them.
function App:_watchPrices()
  if self.store:get("sort") ~= "value" then return end
  local source = Prices.source()
  if source == self.priceSource then return end
  self.priceSource = source
  self:rebuild()
end

-- Returns the items that a custom category's rules match in the last read
-- bank, split three ways for the review list:
--   matched   items the rules add automatically
--   removed   items the player removed from the category
--   byHand    items the player put in the category from the Tags window
-- Each entry is { objectId, name }; repeated items appear once.
function App:categoryReview(key)
  local def = self.store:category(key)
  local review = { matched = {}, removed = {}, byHand = {} }
  if not def then return review end
  local excluded, seen = self.store.excluded[key] or {}, {}
  for _, item in ipairs(self.items or {}) do
    local objectId = item.objectId or item.id
    if not seen[objectId] then
      seen[objectId] = true
      local row = { objectId = objectId, name = item.name }
      if self.store.corrections[objectId] == key then
        review.byHand[#review.byHand + 1] = row
      elseif Custom.categoryMatches(def, (item.name or ""):lower()) then
        local list = excluded[objectId] and review.removed or review.matched
        list[#list + 1] = row
      end
    end
  end
  return review
end

-- Builds the Bank Cleaner's suggestions from the last read bank (see
-- src/core/cleaner.lua). Returns nil before Analyze.
function App:cleanerSuggestions()
  if not self.items then return nil end
  local store = self.store
  local live = Prices.source() == "live"
  return Cleaner.suggest(self.items, {
    -- The cleaner asks the same questions the rest of the plugin answers.
    tagOf = function(item) return self:tagOf(item) end,
    -- Tags, ignores and the Keep list come from the store.
    tagsOf = function(objectId) return store:tagsOf(objectId) end,
    isIgnored = function(objectId) return store:isIgnored(objectId) end,
    isKept = function(objectId) return store:isKept(objectId) end,
    isClue = Clues.isClue,
    questState = Quests.state,
    -- GE prices only count once the price library has loaded them.
    price = function(objectId) return live and Prices.of(objectId) or nil end,
    threshold = store:get("cleanerThreshold"),
  })
end

-- Applies a Bank Cleaner button to the chosen items.
--   objectIds  list of real item ids
--   action     "sell", "alch" or "trash" (adds that tag) or "keep" (adds
--              the item to the Keep list)
-- Rebuilds once at the end. Returns how many items were changed.
function App:applyCleaner(objectIds, action)
  local changed = 0
  for _, objectId in ipairs(objectIds or {}) do
    local ok
    if action == "keep" then
      ok = self.store:setKept(objectId, true)
    else
      ok = self.store:setTag(objectId, action, true)
    end
    if ok then changed = changed + 1 end
  end
  if changed > 0 then
    self.pending, self.correction = nil, nil
    self:rebuild()
  end
  return changed
end

-- Runs once per game tick: watches GE prices, learns the tab order, runs the
-- guide and redraws the overlay. Each part is wrapped in pcall so a problem
-- in one never stops the others; problems are logged.
function App:tick()
  local watched, watchErr = pcall(function() self:_watchPrices() end)
  if not watched and log then log("[bank-organizer] prices failed: " .. tostring(watchErr)) end
  local container = Bank.slotsContainer()
  self.bankOpen = container ~= nil
  if not self.bankOpen then
    self.overlay:clear()
    return
  end
  local learned, learnErr = pcall(function() self:_learnTabOrder() end)
  if not learned and log then log("[bank-organizer] tab order failed: " .. tostring(learnErr)) end
  if self.guiding then self:_tickGuide() end
  local ok, err = pcall(function() return self.overlay:render(self) end)
  if not ok and log then log("[bank-organizer] overlay failed: " .. tostring(err)) end
end

-- Subscribes to the game tick.
function App:start()
  Event.ServerLogic.Subscribe(EVENT_ID, function() self:tick() end)
end

-- Unsubscribes, clears the overlay and drops every listener.
function App:stop()
  pcall(function() return Event.ServerLogic.Unsubscribe(EVENT_ID) end)
  self.overlay:clear()
  self.listeners = {}
end

return App
