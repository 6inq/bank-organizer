local Bank = require("src/game/bank")
local GuideLine = require("src/game/guide_line")

local Overlay = {}
Overlay.__index = Overlay

local LABEL_HEIGHT = 14
local IGNORED_OUTLINE = 0x969696AA
local BADGE_COLOUR = 0xFFFFFFFF
local DECANT_COLOUR = 0xF2C94CFF
local TAB_ROW_GAP = 24

function Overlay.new()
  return setmetatable({ components = {}, signature = nil, container = nil, lastSeen = {} }, Overlay)
end

local function withAlpha(colour, alpha)
  return (colour & 0xFFFFFF00) | math.floor(alpha * 255 + 0.5)
end

function Overlay:_track(component)
  component.clickthrough = true
  self.components[#self.components + 1] = component
  return component
end

function Overlay:_rect(slot, rgba, outline)
  local rect = self:_track(ui.Rectangle.new(self.container))
  rect:SetPos(slot.x, slot.y)
  rect:SetSize(slot.width, slot.height)
  rect.fill = outline == nil
  rect.outlineThickness = outline or 0
  rect.rgba = rgba
  return rect
end

function Overlay:_badge(slot, text, rgba)
  local badge = self:_track(ui.Text.new(self.container))
  badge:SetPos(slot.x - 2, slot.y + slot.height - LABEL_HEIGHT)
  badge:SetSize(slot.width + 4, LABEL_HEIGHT)
  badge.font = id.Font.MUSEO_SANS_15PT_REGULAR
  badge.content = text
  badge.rgba = rgba
  return badge
end

function Overlay:_label(slot, text, rgba)
  local label = self:_track(ui.Text.new(self.container))
  local y = slot.y - LABEL_HEIGHT
  local scrolled = self.view and self.view.scrollY or 0
  if slot.y - scrolled < LABEL_HEIGHT then y = slot.y + slot.height - LABEL_HEIGHT end
  label:SetPos(slot.x - 4, y)
  label:SetSize(slot.width + 8, LABEL_HEIGHT)
  label.font = id.Font.MUSEO_SANS_15PT_REGULAR
  label.content = text
  label.rgba = rgba
  return label
end

Overlay.lineBox = GuideLine.box

local function stepEnds(step)
  if not step then return nil end
  if step.kind == "insert" then return step.move, step.before or step.after end
  if step.kind == "swap" then return step.move, step.swapWith end
  return step.id, nil
end

local function stepMarks(step)
  if not step then return {} end
  local marks = {}
  if step.kind == "insert" then
    marks[step.move] = { "MOVE", "move" }
    if step.before then marks[step.before] = { "INSERT BEFORE", "target" } end
    if step.after then marks[step.after] = { "AFTER", "target" } end
  elseif step.kind == "swap" then
    marks[step.move] = { "SWAP", "move" }
    marks[step.swapWith] = { "WITH", "target" }
  else
    marks[step.id] = { "MOVE", "move" }
  end
  return marks
end

local function activeStep(app)
  return app.guiding and not app.settling and app.step or nil
end

local function stepKey(step)
  if not step then return "" end
  return table.concat({ step.kind, tostring(step.id or step.move), tostring(step.to or step.before or step.after or step.swapWith) }, ":")
end

local function signatureOf(slots, app, tint, marks)
  local parts = { tostring(tint), tostring(app.store:get("opacity")), stepKey(activeStep(app)) }
  for _, slot in ipairs(slots) do
    local d = app:destinationOfItem(slot.key)
    local mark = marks[slot.key]
    parts[#parts + 1] = slot.key .. "@" .. slot.x .. "," .. slot.y .. "=" .. tostring(d)
      .. ":" .. tostring(d and app:destinationColour(d)) .. (mark and mark[1] or "") .. (app:isSortedSlot(slot.key) and "S" or "")
      .. tostring(app:slotLabel(slot.key))
  end
  for _, key in ipairs({ "move", "target", "line", "done" }) do parts[#parts + 1] = tostring(app.store:colour(key)) end
  parts[#parts + 1] = tostring(app.store:get("sortedLook"))
  return table.concat(parts, "|")
end

local function globalBox(slot, container, view)
  local cx, cy = Bank.globalXY(container)
  return { x = cx + slot.x - view.scrollX, y = cy + slot.y - view.scrollY, width = slot.width, height = slot.height }
end

function Overlay:_view(container)
  local cx, cy = Bank.globalXY(container)
  local key = table.concat({ cx, cy, container.width or 0, container.height or 0 }, ":")
  if key ~= self.frameKey then self.frame, self.frameKey = Bank.scrollFrame(container), key end
  return Bank.view(container, self.frame)
end

function Overlay:_buttons(container, tabs)
  local cx, cy = Bank.globalXY(container)
  local key = table.concat({ cx, cy, container.width or 0, tabs }, ":")
  if key ~= self.buttonsKey then self.buttons, self.buttonsKey = Bank.tabButtons(container), key end
  return self.buttons
end

function Overlay:_tabTarget(app, step, container)
  local tabs = 0
  for s in pairs(app.sections or {}) do if s > tabs then tabs = s end end
  local buttons = self:_buttons(container, tabs)
  if step.kind == "to-tab" and buttons[step.to + 1] and #buttons >= tabs + 1 then return buttons[step.to + 1] end
  if step.kind == "new-tab" and #buttons >= tabs + 2 then return buttons[#buttons] end
  if log and not self.loggedMissing then
    self.loggedMissing = true
    log("[bank-organizer] tab button for " .. app:tabName(step.to) .. " not found (" .. #buttons
      .. " buttons for " .. tabs .. " tabs); pointing at the tab row")
  end
  local cx, cy = Bank.globalXY(container)
  return { x = cx + container.width / 2 - 8, y = cy - TAB_ROW_GAP, width = 16, height = 16 }
end

local function targetKind(step)
  if step.kind == "insert" then return step.before and "before" or "after" end
  if step.kind == "swap" then return "swap" end
  return "tab"
end

function Overlay:_guideLine(app, container, byId)
  local step = activeStep(app)
  local fromID, toID = stepEnds(step)
  if not fromID then return end
  local view = self.view
  local from = byId[fromID] and globalBox(byId[fromID], container, view) or self.lastSeen[fromID]
  if not from then return end
  local box
  if toID then
    box = byId[toID] and globalBox(byId[toID], container, view) or self.lastSeen[toID]
  else
    box = self:_tabTarget(app, step, container)
  end
  if not box then return end
  local viewport = { x = view.x, y = view.y, width = view.width, height = view.height }
  local plan = GuideLine.plan(from, { kind = targetKind(step), box = box }, viewport)
  if not plan then return end
  local host, hx, hy = Bank.drawLayer(container)
  GuideLine.draw(plan, host, hx, hy, app.store:colour("line"), function(component) return self:_track(component) end)
end

function Overlay:render(app)
  if not app.destinations then return self:clear() end
  local _, container, slots = Bank.componentsById()
  if not container then return self:clear() end
  if container ~= self.container then self:clear() end
  local tint = app.store:get("tint")
  app:noteColumns(slots or {})
  local marks = activeStep(app) and stepMarks(app.step) or {}
  app:assignSlotKeys(slots or {})
  self.view = self:_view(container)
  local byId = {}
  for _, slot in ipairs(slots or {}) do byId[slot.key] = slot end
  local key = stepKey(activeStep(app))
  if key ~= self.lastStep then self.lastSeen, self.lastStep = {}, key end
  local fromID, toID = stepEnds(activeStep(app))
  for _, itemID in ipairs({ fromID or false, toID or false }) do
    if itemID and byId[itemID] then self.lastSeen[itemID] = globalBox(byId[itemID], container, self.view) end
  end
  local onScreen = {}
  for _, itemID in ipairs({ fromID or false, toID or false }) do
    local box = itemID and self.lastSeen[itemID]
    if box then onScreen[#onScreen + 1] = box.x .. "," .. box.y end
  end
  local signature = signatureOf(slots or {}, app, tint, marks) .. "|" .. table.concat(onScreen, ";")
  if signature == self.signature then return false end
  self:clear()
  self.container, self.signature = container, signature
  local opacity = app.store:get("opacity")
  for _, slot in ipairs(slots or {}) do
    local d = app:destinationOfItem(slot.key)
    local look = app:isSortedSlot(slot.key) and app.store:get("sortedLook") or "tint"
    if tint and d and look == "green" then
      self:_rect(slot, app.store:colour("done"))
    elseif tint and d and look == "tint" then
      self:_rect(slot, withAlpha(app:destinationColour(d), opacity))
    elseif tint and app:isIgnored(slot.objectID) then
      self:_rect(slot, IGNORED_OUTLINE, 1)
    end
    local mark = marks[slot.key]
    if mark then
      local colour = app.store:colour(mark[2])
      self:_rect(slot, colour, 3)
      self:_label(slot, mark[1], colour)
    else
      local text, kind = app:slotLabel(slot.key)
      if text then self:_badge(slot, text, kind == "decant" and DECANT_COLOUR or BADGE_COLOUR) end
    end
  end
  local ok, err = pcall(function() self:_guideLine(app, container, byId) end)
  if not ok and log then log("[bank-organizer] guide line failed: " .. tostring(err)) end
  return true
end

function Overlay:clear()
  for _, component in ipairs(self.components) do pcall(function() return component:Destroy() end) end
  self.components, self.signature, self.container = {}, nil, nil
end

return Overlay
