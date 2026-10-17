-- Draws category tints and move highlights on top of native bank slots.
-- Everything is clickthrough so the player can still drag items underneath.
local Overlay = {}
Overlay.__index = Overlay

local DIM = 0x000000AA
local MOVE_COLOUR = 0x3CE03CFF
local TARGET_COLOUR = 0xF2C94CFF
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

local function signatureOf(slots, view)
  local parts = {
    tostring(view.overlays), view.filter, tostring(view.highlightUntagged), tostring(view.opacity),
    view.move and (view.move.move .. ">" .. tostring(view.move.before or view.move.after)) or "-",
  }
  for _, slot in ipairs(slots) do
    local key = view.categoryOf(slot.objectID)
    parts[#parts + 1] = slot.objectID .. "@" .. slot.x .. "," .. slot.y .. "=" .. key
      .. ":" .. view.colourOf(key) .. (view.isTagged(slot.objectID) and "t" or "")
  end
  return table.concat(parts, "|")
end

function Overlay:_drawCategories(slots, view)
  for _, slot in ipairs(slots) do
    local key = view.categoryOf(slot.objectID)
    local matches = view.filter == "all" or view.filter == key
    if matches then
      self:_rect(slot, withAlpha(view.colourOf(key), view.opacity))
    else
      self:_rect(slot, DIM)
    end
    if view.highlightUntagged and not view.isTagged(slot.objectID) then
      self:_rect(slot, withAlpha(view.colourOf(key), 1), 2)
    end
  end
end

function Overlay:_drawMove(slots, move)
  local anchor = move.before or move.after
  for _, slot in ipairs(slots) do
    if slot.objectID == move.move then
      self:_rect(slot, MOVE_COLOUR, 3)
      self:_label(slot, "MOVE", MOVE_COLOUR)
    elseif slot.objectID == anchor then
      self:_rect(slot, TARGET_COLOUR, 3)
      self:_label(slot, move.before and "INSERT BEFORE" or "AFTER", TARGET_COLOUR)
    end
  end
end

---@param container ui.ComponentCollection
---@param slots table[] from Bank.scan
---@param view table { overlays, filter, highlightUntagged, opacity, categoryOf, colourOf, isTagged, move }
function Overlay:render(container, slots, view)
  if container ~= self.container then self:clear() end
  local signature = signatureOf(slots, view)
  if signature == self.signature then return false end
  self:clear()
  self.container, self.signature = container, signature
  if view.overlays then self:_drawCategories(slots, view) end
  if view.move then self:_drawMove(slots, view.move) end
  return true
end

function Overlay:clear()
  for _, component in ipairs(self.components) do
    pcall(component.Destroy, component)
  end
  self.components, self.signature, self.container = {}, nil, nil
end

return Overlay
