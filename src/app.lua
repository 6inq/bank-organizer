local Tags = require("src/core/tags")
local Blueprint = require("src/core/blueprint")
local Guide = require("src/core/guide")
local Verify = require("src/core/verify")
local TabOrder = require("src/core/tab_order")
local Bank = require("src/game/bank")
local Prices = require("src/game/prices")
local Overlay = require("src/game/overlay")
local Sorting = require("src/core/sorting")
local Placement = require("src/core/placement")

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
    guiding = false, step = nil, remaining = nil,
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
    if not self.store:isIgnored(item.objectId or item.id) then items[#items + 1] = item end
  end
  local tagOf = function(item) return self:tagOf(item) end
  local mode = self.store:get("sort")
  if mode == "value" then self.priceSource = Prices.attach(items) end
  self.itemByKey = {}
  for _, item in ipairs(allItems) do self.itemByKey[item.id] = item end
  local tagged = {}
  for index, item in ipairs(items) do
    tagged[index] = { id = item.id, name = item.name, quantity = item.quantity, tag = self:tagOf(item) }
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
        items, sections, tagOf, self.store.tabHomes, self.store.tabOrder, mode, opts)
      self:_trackOrder(sections)
      self:_keepOrder(sections)
      return true
    end
  end
  self.destinations, self.bySlot = Blueprint.build(items, self.store.layout, tagOf, mode, opts)
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

function App:_buildOptions()
  return {
    markOf = function(item) return self.store:markOf(item.objectId or item.id) end,
    decant = self.decant,
    vertical = self.store:get("direction") == "vertical",
    columns = self.columns,
  }
end

function App:markOf(objectId)
  return self.store:markOf(objectId)
end

function App:setMark(objectId, mark)
  if not self.store:setMark(objectId, mark) then return false end
  self.pending, self.correction = nil, nil
  self:rebuild()
  if self.guiding then self:_tickGuide() end
  return true
end

function App:slotLabel(key)
  local item = self.itemByKey and self.itemByKey[key]
  if not item then return nil end
  local badge = Placement.badge(self.store:markOf(item.objectId or item.id))
  if badge then return badge, "badge" end
  local decant = self.store:get("decant") and self.decant and self.decant[key]
  if decant and decant.canDecant and self.store:get("decant" .. decant.dose) then return "DECANT", "decant" end
  return nil
end

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

function App:startGuide()
  if not self.destinations and not self:analyze() then return end
  self.guiding, self.pending, self.correction, self.step, self.lastRead = true, nil, nil, nil, nil
  self:_tickGuide()
  self:_notify()
end

function App:stopGuide()
  self.guiding, self.step, self.remaining, self.pending, self.correction = false, nil, nil, nil, nil
  self:_notify()
end

function App:_displaySections(items, sizes)
  local container = Bank.sections(items, sizes, Bank.TAB_VARS.tabsFirst)
  self.displayOf, self.containerOf = TabOrder.maps(self.store.displayOrder, container)
  self.containerSequence = TabOrder.containerSequence(self.displayOf, self.containerOf, Bank.TAB_VARS.tabsFirst)
  self.displaySections = TabOrder.toDisplay(container, self.displayOf)
  return self.displaySections
end

App.VIEW_MAJORITY = 0.8

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
    local target = targets[s] or {}
    local same = #target > 0 and #list == #target
    for index = 1, #target do if list[index] ~= target[index] then same = false end end
    sorted[s] = same
  end
  self.sorted, self.sectionOfKey, self.sortedKey = sorted, sectionOfKey, key
  return sorted, sectionOfKey
end

function App:isSortedSlot(key)
  local sorted, sectionOfKey = self:sortedSections()
  local s = sectionOfKey[key]
  return s ~= nil and sorted[s] == true
end

function App:assignSlotKeys(slots)
  local shown = self.displaySections
  if not shown then return end
  local seen, repeated = {}, false
  for _, slot in ipairs(slots) do
    if seen[slot.objectID] then repeated = true end
    seen[slot.objectID] = true
  end
  if not repeated then return end
  local sectionOfSlot = {}
  local view = Bank.currentTab()
  if view == 1 then
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

function App:tabSizes()
  local raw = Bank.tabSizes()
  local override = self.sizeOverride
  if raw and override and override.game == table.concat(raw, ",") then return override.sizes end
  self.sizeOverride = nil
  return raw
end

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

function App:modeForGuide()
  local insert = Bank.insertMode()
  if insert == nil then return self.store:get("mode") end
  return insert and Guide.INSERT or Guide.SWAP
end

App.SETTLE_READS = 2

function App:_settled(sections)
  if self.lastRead and Verify.same(self.lastRead, sections) then
    self.reads = self.reads + 1
  else
    self.lastRead, self.reads = Verify.copy(sections), 1
  end
  return self.reads >= App.SETTLE_READS or self.step == nil
end

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
  if self:_checkMove(items, sections) == "resync" then
    self:_build(items)
    sections, reason, focus = self:_sections(items)
    if not sections then return self:_setStatus(reason) end
    self.focus, self.sections, self.lastRead, self.reads = focus, sections, Verify.copy(sections), App.SETTLE_READS
  end
  if self:_correcting(sections, mode) then return end
  self.step = Guide.next(sections, self.destinations, mode, focus)
  self.remaining = Guide.remaining(sections, self.destinations, mode, focus)
  self.pending = self.step and { step = self.step, before = Verify.copy(sections) } or nil
  self:_setStatus(self.step and App.describe(self.step, self) or self:_doneMessage(sections, mode, focus))
end

function App:_doneMessage(sections, mode, focus)
  if focus == nil then return App.STATUS.DONE end
  local next = Guide.next(sections, self.destinations, mode)
  if not next then return App.STATUS.DONE end
  local section = next.from or next.section or 0
  return self:tabName(focus) .. " is organized. Open " .. self:tabName(section) .. " next."
end

local function flatIds(items)
  local flat = {}
  for index, item in ipairs(items) do flat[index] = item.id end
  return flat
end

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

function App:_recordMistake(line)
  if log then log("[bank-organizer] move check: " .. line) end
  self.mistakes = self.mistakes or {}
  table.insert(self.mistakes, line)
  while #self.mistakes > 20 do table.remove(self.mistakes, 1) end
  local db = rawget(_G, "PersistentDB")
  if db then pcall(function() return db:SetString("bank-organizer-debug", table.concat(self.mistakes, "\n")) end) end
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

function App:valueSource()
  return self.priceSource or Prices.source()
end

function App:_watchPrices()
  if self.store:get("sort") ~= "value" then return end
  local source = Prices.source()
  if source == self.priceSource then return end
  self.priceSource = source
  self:rebuild()
end

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

function App:start()
  Event.ServerLogic.Subscribe(EVENT_ID, function() self:tick() end)
end

function App:stop()
  pcall(function() return Event.ServerLogic.Unsubscribe(EVENT_ID) end)
  self.overlay:clear()
  self.listeners = {}
end

return App
