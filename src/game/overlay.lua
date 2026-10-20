-- Draws on top of the real bank slots: each item tinted with the colour of the tab it is
-- planned for, plus the current guide step (MOVE and its drop target) and a line from the item
-- to where it goes. Every shape is clickthrough, so the player can still drag items underneath.
-- Draws only; never acts.
local Bank = require("src/game/bank")

local Overlay = {}
Overlay.__index = Overlay

local LABEL_HEIGHT = 14
local TAB_ROW_GAP = 24 -- fallback target: just above the slots, where the tab row sits

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

function Overlay:_label(slot, text, rgba)
  local label = self:_track(ui.Text.new(self.container))
  label:SetPos(slot.x - 4, slot.y - LABEL_HEIGHT)
  label:SetSize(slot.width + 8, LABEL_HEIGHT)
  label.font = id.Font.MUSEO_SANS_15PT_REGULAR
  label.content = text
  label.rgba = rgba
  return label
end

local function unpackColour(rgba)
  return ((rgba >> 24) & 0xFF) / 255, ((rgba >> 16) & 0xFF) / 255, ((rgba >> 8) & 0xFF) / 255, (rgba & 0xFF) / 255
end

-- A ui.Line runs from its top-left to its bottom-right (invert: bottom-left to top-right),
-- so a line between two points is the box spanning them.
function Overlay.lineBox(x1, y1, x2, y2)
  local x, y = math.min(x1, x2), math.min(y1, y2)
  local invert = (x2 - x1) * (y2 - y1) < 0
  return x, y, math.max(1, math.abs(x2 - x1)), math.max(1, math.abs(y2 - y1)), invert
end

local function centre(box)
  return box.x + box.width / 2, box.y + box.height / 2
end

-- Line between two boxes given in the coordinates of `parent`.
function Overlay:_line(parent, from, to, rgba)
  local x1, y1 = centre(from)
  local x2, y2 = centre(to)
  local x, y, w, h, invert = Overlay.lineBox(x1, y1, x2, y2)
  local line = self:_track(ui.Line.new(parent))
  line:SetPos(x, y)
  line:SetSize(w, h)
  line.invert = invert
  line.width = 3
  line.colour = Vector4.new(unpackColour(rgba))
  return line
end

-- The item the guide says to move, and the item it should land next to (insert/swap steps).
local function stepEnds(step)
  if not step then return nil end
  if step.kind == "insert" then return step.move, step.before or step.after end
  if step.kind == "swap" then return step.move, step.swapWith end
  return step.id, nil
end

-- What the guide step highlights: { [itemID] = { text, colourKey } }.
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

local function stepKey(step)
  if not step then return "" end
  return table.concat({ step.kind, tostring(step.id or step.move), tostring(step.to or step.before or step.after or step.swapWith) }, ":")
end

local function signatureOf(slots, app, tint, marks)
  local parts = { tostring(tint), tostring(app.store:get("opacity")), tostring(app.assigning), stepKey(app.guiding and app.step) }
  for _, slot in ipairs(slots) do
    local d = app:destinationOfItem(slot.objectID)
    local mark = marks[slot.objectID]
    parts[#parts + 1] = slot.objectID .. "@" .. slot.x .. "," .. slot.y .. "=" .. tostring(d)
      .. ":" .. tostring(d and app:destinationColour(d)) .. (mark and mark[1] or "")
  end
  for _, key in ipairs({ "move", "target", "line" }) do parts[#parts + 1] = tostring(app.store:colour(key)) end
  return table.concat(parts, "|")
end

-- Global box of a slot, from its component (falls back to container-relative + container).
local function globalBox(slot, container)
  local ok, box = pcall(function()
    local xy = slot.component.xyGlobal
    return { x = xy.x, y = xy.y, width = slot.width, height = slot.height }
  end)
  if ok and box then return box end
  local cx, cy = Bank.globalXY(container)
  return { x = cx + slot.x, y = cy + slot.y, width = slot.width, height = slot.height }
end

-- Where a to-tab / new-tab step should be dropped, as a global box: the tab's button when it
-- can be found (RS3 shows a tab's first item on its button), else just above the slots.
function Overlay:_tabTarget(app, step, container)
  local section = app.sections and app.sections[step.to]
  local first = step.kind == "to-tab" and step.to > 0 and section and section[1]
  local icon = first and Bank.tabIcon(container, first)
  if icon then return icon end
  if first and log and not self.loggedMissing then
    self.loggedMissing = true
    log("[bank-organizer] tab button for " .. app:tabName(step.to) .. " not found; pointing at the tab row")
  end
  local cx, cy = Bank.globalXY(container)
  return { x = cx + container.width / 2 - 8, y = cy - TAB_ROW_GAP, width = 16, height = 16 }
end

function Overlay:_guideLine(app, container, byId)
  local step = app.guiding and app.step
  local fromID, toID = stepEnds(step)
  if not fromID then return end
  local from = byId[fromID] and globalBox(byId[fromID], container) or self.lastSeen[fromID]
  if not from then return end
  local to
  if toID then
    to = byId[toID] and globalBox(byId[toID], container) or self.lastSeen[toID]
  else
    to = self:_tabTarget(app, step, container)
  end
  if not to then return end
  local host, hx, hy = Bank.lineHost(container)
  local function local_(box) return { x = box.x - hx, y = box.y - hy, width = box.width, height = box.height } end
  self:_line(host, local_(from), local_(to), app.store:colour("line"))
end

function Overlay:render(app)
  if not app.destinations then return self:clear() end
  local _, container, slots = Bank.componentsById()
  if not container then return self:clear() end
  if container ~= self.container then self:clear() end
  local tint = app.store:get("tint") or app.assigning
  local marks = app.guiding and stepMarks(app.step) or {}
  local byId = {}
  for _, slot in ipairs(slots or {}) do byId[slot.objectID] = slot end
  -- An item being dragged leaves its slot; the line keeps its last known spot.
  local key = stepKey(app.guiding and app.step)
  if key ~= self.lastStep then self.lastSeen, self.lastStep = {}, key end
  local fromID, toID = stepEnds(app.guiding and app.step)
  for _, itemID in ipairs({ fromID or false, toID or false }) do
    if itemID and byId[itemID] then self.lastSeen[itemID] = globalBox(byId[itemID], container) end
  end
  local signature = signatureOf(slots or {}, app, tint, marks)
  if signature == self.signature then return false end
  self:clear()
  self.container, self.signature = container, signature
  local opacity = app.store:get("opacity")
  for _, slot in ipairs(slots or {}) do
    local d = app:destinationOfItem(slot.objectID)
    if tint and d then self:_rect(slot, withAlpha(app:destinationColour(d), opacity)) end
    local mark = marks[slot.objectID]
    if mark then
      local colour = app.store:colour(mark[2])
      self:_rect(slot, colour, 3)
      self:_label(slot, mark[1], colour)
    end
  end
  -- Drawn last so it sits on top of the tints and highlights.
  local ok, err = pcall(function() self:_guideLine(app, container, byId) end)
  if not ok and log then log("[bank-organizer] guide line failed: " .. tostring(err)) end
  return true
end

function Overlay:clear()
  for _, component in ipairs(self.components) do pcall(function() return component:Destroy() end) end
  self.components, self.signature, self.container = {}, nil, nil
end

return Overlay
