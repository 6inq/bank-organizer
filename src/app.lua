-- Plugin state and the scan -> classify -> plan -> render loop.
local Classify = require("src/core/classify")
local Order = require("src/core/order")
local Bank = require("src/game/bank")
local Overlay = require("src/game/overlay")

local App = {}
App.__index = App

local EVENT_ID = "bank-organizer:logic"
local OPEN_INTERVAL, CLOSED_INTERVAL = 3, 25

App.STATUS = {
  CLOSED = "Open your bank.",
  READY = "Ready. Check your settings, then press Start Organizing.",
  SEARCH = "Clear the bank search to keep organizing.",
  DONE = "Done! Everything here is organized.",
}
App.ALL_ITEMS_HINT = "You are organizing All items, so items may move between tabs. Open a single tab to keep your tabs intact."

function App.new(store)
  return setmetatable({
    store = store, overlay = Overlay.new(), organizing = false, skipped = {},
    move = nil, status = App.STATUS.CLOSED, hint = "", dirty = true, bankOpen = false,
    listeners = {}, autoCategory = {}, notified = nil,
  }, App)
end

-- Manual tag wins; the automatic guess is pure per item id, so it is cached.
function App:categoryOf(objectID)
  local tag = self.store:getTag(objectID)
  if tag then return tag end
  local guess = self.autoCategory[objectID]
  if guess == nil then
    guess = Classify.classify(Bank.info(objectID))
    self.autoCategory[objectID] = guess
  end
  return guess
end

function App:nameOf(objectID)
  return Bank.info(objectID).name or ("Item " .. tostring(objectID))
end

-- Listeners receive the app whenever status, hint or organizing state changes.
function App:onChange(key, fn)
  self.listeners[key] = fn
  if fn then pcall(fn, self) end
end

function App:_notify()
  local signature = self.status .. "\n" .. self.hint .. "\n" .. tostring(self.organizing)
  if signature == self.notified then return end
  self.notified = signature
  for _, fn in pairs(self.listeners) do pcall(fn, self) end
end

function App:_setStatus(status, hint)
  self.status, self.hint = status, hint or ""
  self:_notify()
end

function App:invalidate()
  self.dirty = true
end

function App:_describe(move)
  local name = self:nameOf(move.move)
  local steps = move.remaining == 1 and "1 move left" or (move.remaining .. " moves left")
  if move.before then
    return "Insert " .. name .. " before " .. self:nameOf(move.before) .. " (" .. steps .. ")"
  end
  return "Move " .. name .. " to the end, after " .. self:nameOf(move.after) .. " (" .. steps .. ")"
end

function App:_plan(slots)
  if Bank.searchActive() then
    self.move = nil
    return App.STATUS.SEARCH
  end
  local items, current = {}, {}
  for index, slot in ipairs(slots) do
    current[index] = slot.objectID
    items[index] = { objectID = slot.objectID, name = self:nameOf(slot.objectID), category = self:categoryOf(slot.objectID) }
  end
  local target = Order.buildTarget(items, self.store:get("sortMode"))
  self.move = Order.nextMove(current, target, self.skipped)
  if self.move == nil then
    self.organizing, self.idleStatus = false, App.STATUS.DONE
    return self.idleStatus
  end
  return self:_describe(self.move)
end

function App:_view()
  return {
    overlays = self.store:get("overlays"), filter = self.store:get("filter"),
    highlightUntagged = self.store:get("highlightUntagged"), opacity = self.store:get("opacity"),
    move = self.organizing and self.move or nil,
    categoryOf = function(objectID) return self:categoryOf(objectID) end,
    colourOf = function(key) return self.store:colour(key) end,
    isTagged = function(objectID) return self.store:getTag(objectID) ~= nil end,
  }
end

function App:refresh()
  self.dirty = false
  local slots, reason, container = Bank.scan()
  self.bankOpen = slots ~= nil
  if not slots then
    self.overlay:clear()
    self:_setStatus(reason)
    return
  end
  local status, hint = self.idleStatus or App.STATUS.READY, ""
  if self.organizing then
    status = self:_plan(slots)
    if self.organizing and Bank.isAllItemsTab() then hint = App.ALL_ITEMS_HINT end
  end
  self:_setStatus(status, hint)
  self.overlay:render(container, slots, self:_view())
end

function App:startOrganizing()
  self.organizing, self.skipped, self.move, self.idleStatus = true, {}, nil, nil
  self:refresh()
end

function App:stopOrganizing()
  self.organizing, self.move, self.idleStatus = false, nil, nil
  self:refresh()
end

function App:toggleOrganizing()
  if self.organizing then self:stopOrganizing() else self:startOrganizing() end
end

function App:skipCurrent()
  if self.organizing and self.move then self.skipped[self.move.move] = true end
  self:refresh()
end

function App:_onLogic(event)
  local tick = event and event.logicTick or 0
  local interval = self.bankOpen and OPEN_INTERVAL or CLOSED_INTERVAL
  if self.dirty or tick % interval == 0 then self:refresh() end
end

function App:start()
  Event.Logic.Subscribe(EVENT_ID, function(event) self:_onLogic(event) end)
  Event.InventoryUpdated.Subscribe(EVENT_ID, function(event)
    local bankType = config.Inv.BANK
    if event and event.inv and bankType and event.inv.id == bankType.id then self:invalidate() end
  end)
end

function App:stop()
  pcall(Event.Logic.Unsubscribe, EVENT_ID)
  pcall(Event.InventoryUpdated.Unsubscribe, EVENT_ID)
  self.overlay:clear()
  self.listeners = {}
end

return App
