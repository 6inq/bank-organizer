local GuideLine = {}

local BAR_WIDTH = 4
local ARROW_LENGTH = 11
local ARROW_SPREAD = math.rad(28)
local SHADOW = 0x000000A0

local function centre(box)
  return box.x + box.width / 2, box.y + box.height / 2
end

local function clamp(value, low, high)
  if high < low then return low end
  return math.max(low, math.min(high, value))
end

local function dropPoint(target, viewport)
  local box = target.box
  if target.kind == "before" or target.kind == "after" then
    local x = target.kind == "before" and box.x - BAR_WIDTH / 2 - 1 or box.x + box.width + 1 - BAR_WIDTH / 2
    local marker = { kind = "bar", x = x, y = box.y, width = BAR_WIDTH, height = box.height }
    return x + BAR_WIDTH / 2, box.y + box.height / 2, marker
  end
  local x, y = centre(box)
  if target.kind == "tab" then
    return x, box.y + box.height, { kind = "box", x = box.x - 2, y = box.y - 2, width = box.width + 4, height = box.height + 4 }
  end
  return x, y, { kind = "box", x = box.x - 1, y = box.y - 1, width = box.width + 2, height = box.height + 2 }
end

function GuideLine.inView(box, viewport)
  local _, y = centre(box)
  return y >= viewport.y and y <= viewport.y + viewport.height
end

function GuideLine.scrollHint(from, viewport)
  local fx, fy = centre(from)
  local x = clamp(fx, viewport.x + 12, viewport.x + viewport.width - 12)
  local up = fy < viewport.y
  local tip = up and viewport.y + 6 or viewport.y + viewport.height - 6
  local tail = up and tip + 26 or tip - 26
  local arrow = {}
  for _, side in ipairs({ -1, 1 }) do
    arrow[#arrow + 1] = { x, tip, x + side * 8, up and tip + 8 or tip - 8 }
  end
  return { start = { x, tail }, finish = { x, tip }, arrow = arrow, scroll = up and "up" or "down" }
end

function GuideLine.plan(from, target, viewport)
  if viewport and not GuideLine.inView(from, viewport) then return GuideLine.scrollHint(from, viewport) end
  local fx, fy = centre(from)
  local tx, ty, marker = dropPoint(target, viewport)
  if viewport and target.kind ~= "tab" then
    local clampedY = clamp(ty, viewport.y + 4, viewport.y + viewport.height - 4)
    if clampedY ~= ty then marker, ty = nil, clampedY end
  end
  local dx, dy = tx - fx, ty - fy
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 1 then return nil end
  local ux, uy = dx / length, dy / length
  local inset = math.min(from.width, from.height) / 2 + 2
  if length > inset * 2 then fx, fy = fx + ux * inset, fy + uy * inset end
  local arrow = {}
  for _, side in ipairs({ -1, 1 }) do
    local angle = math.atan(-uy, -ux) + side * ARROW_SPREAD
    arrow[#arrow + 1] = { tx, ty, tx + math.cos(angle) * ARROW_LENGTH, ty + math.sin(angle) * ARROW_LENGTH }
  end
  return { start = { fx, fy }, finish = { tx, ty }, marker = marker, arrow = arrow }
end

function GuideLine.box(x1, y1, x2, y2)
  local x, y = math.min(x1, x2), math.min(y1, y2)
  local invert = (x2 - x1) * (y2 - y1) < 0
  return x, y, math.max(1, math.abs(x2 - x1)), math.max(1, math.abs(y2 - y1)), invert
end

local function vector(rgba)
  return Vector4.new(((rgba >> 24) & 0xFF) / 255, ((rgba >> 16) & 0xFF) / 255, ((rgba >> 8) & 0xFF) / 255, (rgba & 0xFF) / 255)
end

function GuideLine.draw(plan, host, ox, oy, rgba, track)
  local function segment(x1, y1, x2, y2, colour, width)
    local x, y, w, h, invert = GuideLine.box(x1 - ox, y1 - oy, x2 - ox, y2 - oy)
    local line = track(ui.Line.new(host))
    line:SetPos(math.floor(x + 0.5), math.floor(y + 0.5))
    line:SetSize(math.floor(w + 0.5), math.floor(h + 0.5))
    line.invert = invert
    line.width = width
    line.colour = vector(colour)
    return line
  end
  local pieces = { { plan.start[1], plan.start[2], plan.finish[1], plan.finish[2] } }
  for _, leg in ipairs(plan.arrow) do pieces[#pieces + 1] = leg end
  for _, piece in ipairs(pieces) do segment(piece[1], piece[2], piece[3], piece[4], SHADOW, 6) end
  for _, piece in ipairs(pieces) do segment(piece[1], piece[2], piece[3], piece[4], rgba, 3) end
  local marker = plan.marker
  if marker then
    local rect = track(ui.Rectangle.new(host))
    rect:SetPos(math.floor(marker.x - ox + 0.5), math.floor(marker.y - oy + 0.5))
    rect:SetSize(math.floor(marker.width + 0.5), math.floor(marker.height + 0.5))
    rect.fill = marker.kind == "bar"
    rect.outlineThickness = marker.kind == "bar" and 0 or 2
    rect.rgba = rgba
  end
end

return GuideLine
