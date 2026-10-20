-- Draws on top of the real bank slots: each item tinted with the colour of the tab it is
-- planned for, plus the current guide step (MOVE and its drop target). Every shape is
-- clickthrough, so the player can still drag items underneath. Draws only; never acts.
local Bank = require("src/game/bank")

local Overlay = {}
Overlay.__index = Overlay

local LABEL_HEIGHT = 14

function Overlay.new()
  return setmetatable({ components = {}, signature = nil, container = nil }, Overlay)
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

local function signatureOf(slots, app, tint, marks)
  local parts = { tostring(tint), tostring(app.store:get("opacity")), tostring(app.assigning) }
  for _, slot in ipairs(slots) do
    local d = app:destinationOfItem(slot.objectID)
    local mark = marks[slot.objectID]
    parts[#parts + 1] = slot.objectID .. "@" .. slot.x .. "," .. slot.y .. "=" .. tostring(d)
      .. ":" .. tostring(d and app:destinationColour(d)) .. (mark and mark[1] or "")
  end
  for _, key in ipairs({ "move", "target" }) do parts[#parts + 1] = tostring(app.store:colour(key)) end
  return table.concat(parts, "|")
end

function Overlay:render(app)
  if not app.destinations then return self:clear() end
  local _, container, slots = Bank.componentsById()
  if not container then return self:clear() end
  if container ~= self.container then self:clear() end
  local tint = app.store:get("tint") or app.assigning
  local marks = app.guiding and stepMarks(app.step) or {}
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
  return true
end

function Overlay:clear()
  for _, component in ipairs(self.components) do pcall(component.Destroy, component) end
  self.components, self.signature, self.container = {}, nil, nil
end

return Overlay
