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

-- Scan the open bank and rebuild the blueprint.
function App:analyze()
  local items = Bank.readItems()
  if not items then
    self:_setStatus(App.STATUS.CLOSED)
    return false
  end
  self.items, self.signature = items, signatureOf(items)
  self.destinations, self.bySlot = Blueprint.build(items, self.store.layout, function(item) return self:tagOf(item) end)
  self.status = App.STATUS.ANALYZED
  self:_logDiagnostics(items)
  self:_notify()
  return true
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
    self.destinations, self.bySlot = Blueprint.build(self.items, self.store.layout, function(item) return self:tagOf(item) end)
  end
  self:_notify()
end

function App:destinationOfItem(itemID)
  if not self.destinations then return nil end
  for d = 0, Tags.DESTINATIONS - 1 do
    for _, entry in ipairs(self.destinations[d]) do
      if entry.id == itemID then return d, entry end
    end
  end
  return nil
end

function App:destinationColour(d)
  local category = Tags.CATEGORIES[d + 1]
  return self.store:colour(category and category.key or "storage-cleanup")
end

function App:destinationLabel(d)
  local names = {}
  for _, tag in ipairs(self.store.layout.destinations[d]) do names[#names + 1] = Tags.label(tag) end
  return Tags.destinationName(d) .. ": " .. (#names > 0 and table.concat(names, ", ") or "empty")
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
function App:_sections(items)
  if Bank.searchActive() or not Bank.isAllItemsTab() then return nil, App.STATUS.NEED_ALL end
  local sizes = Bank.tabSizes()
  if not sizes then return nil, App.STATUS.NO_TABS end
  return Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst)
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
    self.destinations, self.bySlot = Blueprint.build(items, self.store.layout, function(item) return self:tagOf(item) end)
    if before and #before ~= #self.signature then self.status = App.STATUS.CHANGED end
  end
  local sections, reason = self:_sections(items)
  if not sections then
    self.step = nil
    return self:_setStatus(reason)
  end
  local mode = self:modeForGuide()
  self.step = Guide.next(sections, self.destinations, mode)
  self.remaining = Guide.remaining(sections, self.destinations, mode)
  self:_setStatus(self.step and App.describe(self.step, self) or App.STATUS.DONE)
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
    local where = step.to == 0 and "the Main section" or ("Tab " .. step.to)
    return string.format("Drag %s onto %s.", name, where)
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
