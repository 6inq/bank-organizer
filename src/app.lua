local Tags = require("src/core/tags")
local Blueprint = require("src/core/blueprint")
local Guide = require("src/core/guide")
local Verify = require("src/core/verify")
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
  NO_TABS_YET = "You have no tabs yet, so My tabs follows your Tab Layout to create them.",
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

function App:tagOf(item)
  return Blueprint.resolver(self.store.corrections)(item)
end

local function signatureOf(items)
  local parts = {}
  for index, item in ipairs(items) do parts[index] = item.id .. "x" .. item.quantity end
  return table.concat(parts, ",")
end

App.SCOPES = { bank = "Whole bank (follow my Tab Layout)", tabs = "My tabs (keep my tabs, infinity is misc)" }

function App:_build(allItems)
  local items = {}
  for _, item in ipairs(allItems) do
    if not self.store:isIgnored(item.id) then items[#items + 1] = item end
  end
  local tagOf = function(item) return self:tagOf(item) end
  local mode = self.store:get("sort")
  self.tabCounts, self.noTabs = nil, false
  local sizes = Bank.tabSizes()
  local sections = sizes and Bank.sections(allItems, sizes, Bank.TAB_VARS.tabsFirst)
  if self.store:get("scope") == "tabs" then
    if not sizes then
      self.status = App.STATUS.NEED_TABS
    elseif App.countTabs(sections) == 0 then
      self.noTabs = true
    else
      self.destinations, self.bySlot, self.tabCounts, self.autoHomes = Blueprint.buildFromTabs(
        items, sections, tagOf, self.store.tabHomes, self.store.tabOrder, mode)
      self:_trackOrder(sections)
      self:_keepOrder(sections)
      return true
    end
  end
  self.destinations, self.bySlot = Blueprint.build(items, self.store.layout, tagOf, mode)
  self:_keepOrder(sections)
  return true
end

function App.countTabs(sections)
  local total = 0
  for s in pairs(sections or {}) do if s > total then total = s end end
  return total
end

function App:_keepOrder(sections)
  if self.store:get("sort") ~= "keep" or not sections then return end
  local sectionOf = {}
  for s, ids in pairs(sections) do for _, itemID in ipairs(ids) do sectionOf[itemID] = s end end
  Blueprint.keepOrder(self.destinations, sectionOf, Guide.sectionMap(self.destinations))
end

function App:destinationList()
  local list = {}
  for d in pairs(self.destinations or {}) do
    if type(d) == "number" then list[#list + 1] = d end
  end
  table.sort(list)
  if #list == 0 then for d = 0, self.store.layout:last() do list[#list + 1] = d end end
  return list
end

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

local function opsText(ops)
  local list = {}
  for op in pairs(ops or {}) do list[#list + 1] = op end
  table.sort(list)
  return table.concat(list, "|")
end

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
    lines[#lines + 1] = table.concat({ item.slot, item.id, tostring(item.name), tostring(info.category), opsText(info.ops),
      tostring(info.tradeable), tostring(info.quests), tostring(info.stockmarket), tostring(sectionOf[item.id]),
      self:tagOf(item), info.params or "" }, "\t")
  end
  pcall(function() return db:SetString("bank-organizer-export", table.concat(lines, "\n")) end)
  local container = Bank.slotsContainer()
  if container then
    pcall(function() return db:SetString("bank-organizer-ui", Bank.describeInterface(container)) end)
  end
end

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

function App:tabHomeOf(tag)
  local pin = self.store.tabHomes[tag]
  local list = self:destinationList()
  if pin and pin <= list[#list] then return pin, true end
  local home = self.autoHomes and self.autoHomes[tag]
  if home then return (self.positionOf and self.positionOf[home.section]) or home.section, false end
  return nil, false
end

function App:_trackOrder(sections)
  self.tabTotal = 0
  for s in pairs(sections) do if s > self.tabTotal then self.tabTotal = s end end
  self.positionOf = Blueprint.orderFor(self.store.tabOrder, self.tabTotal)
  self.sectionAt = {}
  for s, position in pairs(self.positionOf) do self.sectionAt[position] = s end
end

function App:moveMyTab(d, direction)
  local other, total = d + direction, self.tabTotal or 0
  if not self:myTabs() or d < 1 or other < 1 or d > total or other > total then return false end
  local order = {}
  for position = 1, total do order[position] = self.sectionAt[position] end
  order[d], order[other] = order[other], order[d]
  local identity = true
  for position, s in ipairs(order) do if s ~= position then identity = false end end
  for tag, pin in pairs(self.store.tabHomes) do
    if pin == d then self.store.tabHomes[tag] = other elseif pin == other then self.store.tabHomes[tag] = d end
  end
  self.store:setTabOrder(not identity and order or nil)
  self:rebuild()
  return true
end

function App:resetMyTabOrder()
  self.store:setTabOrder(nil)
  self:rebuild()
end

function App:destinationColour(d)
  if self:myTabs() then
    if d == 0 then return self.store:colour("storage-cleanup") end
    local category = Tags.CATEGORIES[((d - 1) % (#Tags.CATEGORIES - 1)) + 1]
    return self.store:colour(category.key)
  end
  local first = (self.store.layout.destinations[d] or {})[1]
  local category = first and Tags.categoryOf(first)
  return self.store:colour(category and category.key or "storage-cleanup")
end

function App:destinationLabel(d)
  if self:myTabs() then
    if d == 0 then return "Tab 1 (infinity): misc catch-all" end
    local kinds, from = {}, self.sectionAt and self.sectionAt[d] or d
    for _, entry in ipairs(Blueprint.profile(self.tabCounts, from, 3)) do kinds[#kinds + 1] = Tags.label(entry.tag) end
    local moved = from ~= d and (" (now Tab " .. (from + 1) .. ")") or ""
    return "Tab " .. (d + 1) .. moved .. ": " .. (#kinds > 0 and table.concat(kinds, ", ") or "empty")
  end
  local layout = self.store.layout
  local names = {}
  for _, tag in ipairs(layout.destinations[d] or {}) do names[#names + 1] = Tags.label(tag) end
  local title = Tags.destinationName(d) .. (layout.names[d] and (" " .. layout.names[d]) or "")
  return title .. ": " .. (#names > 0 and table.concat(names, ", ") or "empty")
end

function App:tabName(section, destination)
  local name = Tags.destinationName(section)
  local layout = self.store.layout
  local first = destination and (layout.destinations[destination] or {})[1]
  local custom = not self:myTabs() and destination and (layout.names[destination] or (first and Tags.label(first)))
  return custom and (name .. " (" .. custom .. ")") or name
end

function App:copyCurrentTabs()
  local sizes = self.items and Bank.tabSizes()
  if not sizes then return false end
  local tagOf = function(item) return self:tagOf(item) end
  local sections = Bank.sections(self.items, sizes, Bank.TAB_VARS.tabsFirst)
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

function App:setAssigning(on)
  self.assigning = on == true
  self:_notify()
end

function App:startGuide()
  if not self.destinations and not self:analyze() then return end
  self.guiding, self.pending, self.correction = true, nil, nil
  self:_tickGuide()
  self:_notify()
end

function App:stopGuide()
  self.guiding, self.step, self.remaining, self.pending, self.correction = false, nil, nil, nil, nil
  self:_notify()
end

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
  self.focus, self.sections = focus, sections
  self:_checkMove(sections)
  if self:_correcting(sections, mode) then return end
  self.step = Guide.next(sections, self.destinations, mode, focus)
  self.remaining = Guide.remaining(sections, self.destinations, mode, focus)
  self.pending = self.step and { step = self.step, before = Verify.copy(sections) } or nil
  local done = focus and (self:tabName(focus) .. " is organized. Open another tab to keep going.") or App.STATUS.DONE
  self:_setStatus(self.step and App.describe(self.step, self) or done)
end

function App:_checkMove(sections)
  local pending = self.pending
  if not pending or self.correction then return end
  if Verify.check(pending.before, sections, pending.step) == "mistake" then
    self.correction = { target = pending.before, step = pending.step }
    self.pending = nil
  end
end

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

function App:isIgnored(itemID)
  return self.store:isIgnored(itemID)
end

function App:toggleIgnore(itemID)
  self.store:setIgnored(itemID, not self.store:isIgnored(itemID))
  self.pending, self.correction = nil, nil
  self:rebuild()
  if self.guiding then self:_tickGuide() end
end

function App:continueFromHere()
  self.correction, self.pending = nil, nil
  if self.guiding then self:_tickGuide() end
  self:_notify()
end

local function nameOf(app, id)
  for _, item in ipairs(app.items or {}) do
    if item.id == id then return item.name end
  end
  return "item " .. tostring(id)
end

function App.left(app)
  return app.remaining and string.format(" (%d left)", app.remaining) or ""
end

function App.describe(step, app)
  local name = nameOf(app, step.id or step.move)
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

function App:tick()
  local container = Bank.slotsContainer()
  self.bankOpen = container ~= nil
  if not self.bankOpen then
    self.overlay:clear()
    return
  end
  if self.guiding then self:_tickGuide() end
  local ok, err = pcall(function() return self.overlay:render(self) end)
  if not ok and log then log("[bank-organizer] overlay failed: " .. tostring(err)) end
end

function App:start()
  Event.ServerLogic.Subscribe(EVENT_ID, function() self:tick() end)
end

function App:stop()
  pcall(function() return Event.ServerLogic.Unsubscribe(EVENT_ID) end)
  self.overlay:clear()
  self.listeners = {}
end

return App
