-- Bank Organizer 2: Analyze -> Blueprint -> (tint, preview) -> Sorting Guide, with your
-- corrections and tab layout. Read-only: it never moves, clicks or withdraws anything.
local Tags = require("src/core/tags")
local Blueprint = require("src/core/blueprint")
local Guide = require("src/core/guide")
local Bank = require("src/game/bank")
local Overlay = require("src/game/overlay")

local App = {}
App.__index = App

local EVENT_ID = "bank-organizer:tick"

App.STATUS = {
  CLOSED = "Open your bank, then press Analyze Bank.",
  NOT_ANALYZED = "Press Analyze Bank to build your blueprint.",
  ANALYZED = "Blueprint ready. Open Blueprint to review it, or start the Sorting Guide.",
  NEED_ALL = "Open the All items view and clear the bank search to continue the guide.",
  NO_SEARCH = "Clear the bank search to continue the guide.",
  NEED_TABS = "My tabs needs your bank tab sizes, which this client is not reporting.",
  NO_TABS = "This client does not expose bank tab sizes yet, so the guide is paused.",
  DONE = "Your bank matches the blueprint.",
  CHANGED = "Your bank changed, so the blueprint was rebuilt.",
}

function App.new(store)
  return setmetatable({
    store = store, overlay = Overlay.new(), listeners = {},
    items = nil, destinations = nil, bySlot = nil, signature = nil,
    guiding = false, assigning = false, step = nil, remaining = nil,
    status = App.STATUS.CLOSED, bankOpen = false,
  }, App)
end

function App:onChange(key, fn)
  self.listeners[key] = fn
  if fn then pcall(fn, self) end
end

function App:_notify()
  for _, fn in pairs(self.listeners) do pcall(fn, self) end
end

function App:_setStatus(status)
  if status == self.status then return end
  self.status = status
  self:_notify()
end

-- Tag for an item: your correction, then the classifier, then Storage & Cleanup.
function App:tagOf(item)
  return Blueprint.resolver(self.store.corrections)(item)
end

local function signatureOf(items)
  local parts = {}
  for index, item in ipairs(items) do parts[index] = item.id .. "x" .. item.quantity end
  return table.concat(parts, ",")
end

App.SCOPES = { bank = "Whole bank (Bank Architect layout)", tabs = "My tabs (keep my tabs, infinity is misc)" }

-- Blueprint for the chosen scope: Bank Architect destinations, or the player's own tabs.
function App:_build(items)
  local tagOf = function(item) return self:tagOf(item) end
  self.tabCounts = nil
  if self.store:get("scope") == "tabs" then
    local sizes = Bank.tabSizes()
    if sizes then
      self.destinations, self.bySlot, self.tabCounts =
        Blueprint.buildFromTabs(items, Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst), tagOf)
      return true
    end
    self.status = App.STATUS.NEED_TABS
  end
  self.destinations, self.bySlot = Blueprint.build(items, self.store.layout, tagOf)
  return true
end

-- Destination numbers present in the blueprint (0 = main, then tabs), in order.
function App:destinationList()
  local list = {}
  for d in pairs(self.destinations or {}) do
    if type(d) == "number" then list[#list + 1] = d end
  end
  table.sort(list)
  if #list == 0 then for d = 0, Tags.DESTINATIONS - 1 do list[#list + 1] = d end end
  return list
end

-- Scan the open bank and rebuild the blueprint.
function App:analyze()
  local items = Bank.readItems()
  if not items then
    self:_setStatus(App.STATUS.CLOSED)
    return false
  end
  self.items, self.signature = items, signatureOf(items)
  self:_build(items)
  self.status = App.STATUS.ANALYZED
  self:_logDiagnostics(items)
  self:_saveExport(items)
  self:_notify()
  return true
end

local function opsText(ops)
  local list = {}
  for op in pairs(ops or {}) do list[#list + 1] = op end
  table.sort(list)
  return table.concat(list, "|")
end

-- Saves every bank item's facts (and which tab it is in) to PersistentDB as tab-separated
-- text, so classification can be checked against a real, hand-organised bank.
function App:_saveExport(items)
  local db = rawget(_G, "PersistentDB")
  if not db then return end
  local sizes = Bank.tabSizes()
  local sectionOf = {}
  if sizes then
    local sections = Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst)
    for s, ids in pairs(sections) do for _, itemID in ipairs(ids) do sectionOf[itemID] = s end end
  end
  local lines = { "slot\tid\tname\tcategory\tops\ttradeable\tquests\tstockmarket\ttab\ttag" }
  for _, item in ipairs(items) do
    local info = item.info or {}
    lines[#lines + 1] = table.concat({ item.slot, item.id, tostring(item.name), tostring(info.category), opsText(info.ops),
      tostring(info.tradeable), tostring(info.quests), tostring(info.stockmarket), tostring(sectionOf[item.id]),
      self:tagOf(item) }, "\t")
  end
  pcall(function() return db:SetString("bank-organizer-export", table.concat(lines, "\n")) end)
end

-- One console line to confirm the bank model in game: tab sizes, view, mode and the first
-- item of each section as the plugin splits them.
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

function App:_name(itemID)
  for _, item in ipairs(self.items or {}) do if item.id == itemID then return item.name end end
  return tostring(itemID)
end

-- Layout, preset or correction changed: rebuild from the last scan.
function App:rebuild()
  if self.items then
    self:_build(self.items)
  end
  self:_notify()
end

function App:destinationOfItem(itemID)
  if not self.destinations then return nil end
  for _, d in ipairs(self:destinationList()) do
    for _, entry in ipairs(self.destinations[d] or {}) do
      if entry.id == itemID then return d, entry end
    end
  end
  return nil
end

function App:myTabs()
  return self.tabCounts ~= nil
end

-- Colours: Bank Architect destinations use their category colour; in My tabs the main
-- (catch-all) tab is grey and custom tabs cycle through the palette.
function App:destinationColour(d)
  if self:myTabs() then
    if d == 0 then return self.store:colour("storage-cleanup") end
    local category = Tags.CATEGORIES[((d - 1) % (#Tags.CATEGORIES - 1)) + 1]
    return self.store:colour(category.key)
  end
  local category = Tags.CATEGORIES[d + 1]
  return self.store:colour(category and category.key or "storage-cleanup")
end

-- RS3 numbers the main (infinity) tab as Tab 1, so custom tab N is "Tab N+1" in game.
function App:destinationLabel(d)
  if self:myTabs() then
    if d == 0 then return "Tab 1 (infinity): misc catch-all" end
    local kinds = {}
    for _, entry in ipairs(Blueprint.profile(self.tabCounts, d, 3)) do kinds[#kinds + 1] = Tags.label(entry.tag) end
    return "Tab " .. (d + 1) .. ": " .. (#kinds > 0 and table.concat(kinds, ", ") or "empty")
  end
  local names = {}
  for _, tag in ipairs(self.store.layout.destinations[d] or {}) do names[#names + 1] = Tags.label(tag) end
  return Tags.destinationName(d) .. ": " .. (#names > 0 and table.concat(names, ", ") or "empty")
end

function App:tabName(section)
  if self:myTabs() then return section == 0 and "Tab 1 (infinity)" or ("Tab " .. (section + 1)) end
  return section == 0 and "the Main section" or ("Tab " .. section)
end

function App:setAssigning(on)
  self.assigning = on == true
  self:_notify()
end

function App:startGuide()
  if not self.destinations and not self:analyze() then return end
  self.guiding = true
  self:_tickGuide()
  self:_notify()
end

function App:stopGuide()
  self.guiding, self.step, self.remaining = false, nil, nil
  self:_notify()
end

-- Current bank state for the guide, or nil + reason when it must pause (fails closed).
-- Current bank state for the guide, the section to focus on (My tabs: the tab you are
-- viewing), or nil + reason when it must pause (fails closed).
function App:_sections(items)
  local sizes = Bank.tabSizes()
  if not sizes then return nil, App.STATUS.NO_TABS end
  if Bank.searchActive() then return nil, App.STATUS.NO_SEARCH end
  local sections = Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst)
  if self:myTabs() then
    local tab = Bank.currentTab()
    if type(tab) ~= "number" or tab < 1 then return nil, App.STATUS.NO_TABS end
    return sections, nil, tab - 1
  end
  if not Bank.isAllItemsTab() then return nil, App.STATUS.NEED_ALL end
  return sections
end

function App:modeForGuide()
  local insert = Bank.insertMode()
  if insert == nil then return self.store:get("mode") end
  return insert and Guide.INSERT or Guide.SWAP
end

function App:_tickGuide()
  local items = Bank.readItems()
  if not items then return self:_setStatus(App.STATUS.CLOSED) end
  if signatureOf(items) ~= self.signature then
    -- Deposits, withdrawals and moves all change the scan; rebuild so the plan matches the bank.
    local before = self.signature
    self.items, self.signature = items, signatureOf(items)
    self:_build(items)
    if before and #before ~= #self.signature then self.status = App.STATUS.CHANGED end
  end
  local sections, reason, focus = self:_sections(items)
  if not sections then
    self.step = nil
    return self:_setStatus(reason)
  end
  local mode = self:modeForGuide()
  self.focus = focus
  self.step = Guide.next(sections, self.destinations, mode, focus)
  self.remaining = Guide.remaining(sections, self.destinations, mode, focus)
  local done = focus and (self:tabName(focus) .. " is organized. Open another tab to keep going.") or App.STATUS.DONE
  self:_setStatus(self.step and App.describe(self.step, self) or done)
end

local function nameOf(app, id)
  for _, item in ipairs(app.items or {}) do
    if item.id == id then return item.name end
  end
  return "item " .. tostring(id)
end

-- Plain-English instruction for a guide step.
function App.describe(step, app)
  local name = nameOf(app, step.id or step.move)
  if step.kind == "new-tab" then
    return string.format("Drag %s onto the new-tab button to create Tab %d.", name, step.to)
  elseif step.kind == "to-tab" then
    return string.format("Drag %s onto %s.", name, app:tabName(step.to))
  elseif step.kind == "insert" then
    local anchor = step.before and ("before " .. nameOf(app, step.before)) or ("after " .. nameOf(app, step.after))
    return string.format("Insert %s %s (%d left).", name, anchor, app.remaining or 0)
  end
  return string.format("Swap %s with %s (%d left).", name, nameOf(app, step.swapWith), app.remaining or 0)
end

function App:tick()
  local container = Bank.slotsContainer()
  self.bankOpen = container ~= nil
  if not self.bankOpen then
    self.overlay:clear()
    return
  end
  if self.guiding then self:_tickGuide() end
  local ok, err = pcall(self.overlay.render, self.overlay, self)
  if not ok and log then log("[bank-organizer] overlay failed: " .. tostring(err)) end
end

function App:start()
  Event.ServerLogic.Subscribe(EVENT_ID, function() self:tick() end)
end

function App:stop()
  pcall(Event.ServerLogic.Unsubscribe, EVENT_ID)
  self.overlay:clear()
  self.listeners = {}
end

return App
