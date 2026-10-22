-- Bank Organizer: what is drawn on top of the bank.
--
-- For every visible slot the overlay may draw:
--   * a tint in the colour of the tab the item belongs in (or green once
--     its tab is sorted, depending on the settings)
--   * a grey outline on ignored items
--   * the guide's marks: a thick outline and a word ("MOVE", "INSERT
--     BEFORE", "AFTER", "SWAP", "WITH") on the items in the current move
--   * otherwise a small label at the bottom of the slot (a tag such as
--     "Sell", or "Decant")
-- plus the guide arrow (src/game/guide_line.lua).
--
-- Redrawing every tick would be wasteful, so a "signature" text describing
-- everything visible is built first; nothing is redrawn while it is the
-- same as last time.
--
-- Fonts: only fonts known to exist are used. Probing other font names hid
-- every label in game, so slot labels use the 11pt font with the 15pt font
-- as the fallback.

local Bank = require("src/game/bank")
local GuideLine = require("src/game/guide_line")
local Placement = require("src/core/placement")

local Overlay = {}
Overlay.__index = Overlay

-- Height of the guide's word above a slot, in pixels.
local LABEL_HEIGHT = 14

-- Outline colour for ignored items (0xRRGGBBAA).
local IGNORED_OUTLINE = 0x969696AA

-- Height of a slot label at the bottom of a slot, in pixels.
local BADGE_HEIGHT = 11

-- How far above the slot area the tab row is, in pixels, used when the tab
-- buttons cannot be found.
local TAB_ROW_GAP = 24

-- Creates an empty overlay.
--   components  everything drawn, so it can all be destroyed
--   signature   the last drawn state (see the top of this file)
--   lastSeen    item key -> last known screen box of the move's items, so
--               the arrow survives while an item is being dragged
function Overlay.new()
  return setmetatable({ components = {}, signature = nil, container = nil, lastSeen = {} }, Overlay)
end

-- Replaces a colour's alpha with alpha (0 to 1).
local function withAlpha(colour, alpha)
  return (colour & 0xFFFFFF00) | math.floor(alpha * 255 + 0.5)
end

-- Records a drawn component (and makes it ignore clicks so the bank still
-- works underneath). Returns the component.
function Overlay:_track(component)
  component.clickthrough = true
  self.components[#self.components + 1] = component
  return component
end

-- Draws a rectangle over a slot: filled, or an outline of the given width.
function Overlay:_rect(slot, rgba, outline)
  local rect = self:_track(ui.Rectangle.new(self.container))
  rect:SetPos(slot.x, slot.y)
  rect:SetSize(slot.width, slot.height)
  rect.fill = outline == nil
  rect.outlineThickness = outline or 0
  rect.rgba = rgba
  return rect
end

-- Returns the font for slot labels: the 11pt font when the client has it,
-- else the 15pt font. Only these two known fonts are ever used.
function Overlay.badgeFont()
  local ok, font = pcall(function() return id.Font.MUSEO_SANS_11PT_REGULAR end)
  if ok and type(font) == "number" and font >= 0 then return font end
  return id.Font.MUSEO_SANS_15PT_REGULAR
end

-- Draws a small label along the bottom of a slot, centred and shadowed.
-- Alignment and shadow are each set in their own pcall so a client without
-- one of them still shows the text.
function Overlay:_badge(slot, text, rgba)
  local badge = self:_track(ui.Text.new(self.container))
  badge:SetPos(slot.x, slot.y + slot.height - BADGE_HEIGHT)
  badge:SetSize(slot.width, BADGE_HEIGHT)
  badge.font = Overlay.badgeFont()
  badge.content = text
  badge.rgba = rgba
  pcall(function() badge.horizontalAlignment = ui.AlignMode.CENTRE end)
  pcall(function() badge.isShadowed = true end)
  return badge
end

-- Draws the guide's word above a slot. In the top row (where there is no
-- room above, counting the scroll) it goes inside the slot instead.
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

-- Shared with tests: the box helper used for lines.
Overlay.lineBox = GuideLine.box

-- Returns the two item keys a step involves (the item to move and its
-- anchor or swap partner), or nil for tab drags.
local function stepEnds(step)
  if not step or step.kind == "tab-move" then return nil end
  if step.kind == "insert" then return step.move, step.before or step.after end
  if step.kind == "swap" then return step.move, step.swapWith end
  return step.id, nil
end

-- Returns item key -> { word, colour key } for the guide's marks.
local function stepMarks(step)
  if not step or step.kind == "tab-move" then return {} end
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

-- Returns the step to draw, or nil. Nothing is drawn while the bank is
-- settling after a move, so a stale arrow never shows.
local function activeStep(app)
  return app.guiding and not app.settling and app.step or nil
end

-- Returns a short text that identifies a step.
local function stepKey(step)
  if not step then return "" end
  return table.concat({ step.kind, tostring(step.id or step.move), tostring(step.to or step.before or step.after or step.swapWith) }, ":")
end

-- Builds the signature: every slot's key, position, destination, colour,
-- mark, sorted state and label, plus every colour setting. Any change in
-- what would be drawn changes this text.
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
  for _, placement in ipairs(Placement.labelColours()) do
    parts[#parts + 1] = tostring(app.store:colour(Placement.colourKey(placement.key)))
  end
  parts[#parts + 1] = tostring(app.store:get("sortedLook"))
  return table.concat(parts, "|")
end

-- Converts a slot's box to screen coordinates. Slot positions are relative
-- to the slot area and ignore scrolling, so the scroll offset is removed.
local function globalBox(slot, container, view)
  local cx, cy = Bank.globalXY(container)
  return { x = cx + slot.x - view.scrollX, y = cy + slot.y - view.scrollY, width = slot.width, height = slot.height }
end

-- Returns the visible window onto the slots. The scrolling viewport is
-- looked up again only when the slot area moves or resizes.
function Overlay:_view(container)
  local cx, cy = Bank.globalXY(container)
  local key = table.concat({ cx, cy, container.width or 0, container.height or 0 }, ":")
  if key ~= self.frameKey then self.frame, self.frameKey = Bank.scrollFrame(container), key end
  return Bank.view(container, self.frame)
end

-- Returns the tab buttons, found again only when the bank moves or the
-- number of tabs changes.
function Overlay:_buttons(container, tabs)
  local cx, cy = Bank.globalXY(container)
  local key = table.concat({ cx, cy, container.width or 0, tabs }, ":")
  if key ~= self.buttonsKey then self.buttons, self.buttonsKey = Bank.tabButtons(container), key end
  return self.buttons
end

-- Returns the box a tab move should point at: the target tab's button, or
-- the + button for a new tab. When the buttons cannot be found (logged
-- once), it points at the middle of the tab row instead.
function Overlay:_tabTarget(app, step, container)
  local tabs = 0
  for s in pairs(app.sections or {}) do if s > tabs then tabs = s end end
  local buttons = self:_buttons(container, tabs)
  -- buttons[1] is the infinity tab, so tab position n is buttons[n + 1].
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

-- Returns the target kind GuideLine.plan expects for a step.
local function targetKind(step)
  if step.kind == "insert" then return step.before and "before" or "after" end
  if step.kind == "swap" then return "swap" end
  return "tab"
end

-- Draws the arrow for a tab drag: from one tab button to another.
function Overlay:_tabMoveLine(app, container, step)
  local tabs = 0
  for s in pairs(app.sections or {}) do if s > tabs then tabs = s end end
  local buttons = self:_buttons(container, tabs)
  local from, to = buttons[step.from + 1], buttons[step.to + 1]
  if not from or not to then return end
  local plan = GuideLine.plan(from, { kind = "tab", box = to })
  if not plan then return end
  local host, hx, hy = Bank.drawLayer(container)
  GuideLine.draw(plan, host, hx, hy, app.store:colour("line"), function(component) return self:_track(component) end)
end

-- Draws the arrow for the current move.
--   byId  item key -> on-screen slot
-- When an item is not on screen (being dragged, or in another tab), its last
-- known box is used so the arrow stays put.
function Overlay:_guideLine(app, container, byId)
  local step = activeStep(app)
  if step and step.kind == "tab-move" then return self:_tabMoveLine(app, container, step) end
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

-- Draws (or keeps) the overlay for the current state. Returns true when it
-- redrew, false when nothing changed.
function Overlay:render(app)
  if not app.destinations then return self:clear() end
  local _, container, slots = Bank.componentsById()
  if not container then return self:clear() end
  if container ~= self.container then self:clear() end
  local tint = app.store:get("tint")
  app:noteColumns(slots or {})
  local marks = activeStep(app) and stepMarks(app.step) or {}
  -- Give repeated items their per-copy keys before anything uses slot.key.
  app:assignSlotKeys(slots or {})
  self.view = self:_view(container)
  local byId = {}
  for _, slot in ipairs(slots or {}) do byId[slot.key] = slot end
  -- A new step forgets where the previous step's items were.
  local key = stepKey(activeStep(app))
  if key ~= self.lastStep then self.lastSeen, self.lastStep = {}, key end
  local fromID, toID = stepEnds(activeStep(app))
  for _, itemID in ipairs({ fromID or false, toID or false }) do
    if itemID and byId[itemID] then self.lastSeen[itemID] = globalBox(byId[itemID], container, self.view) end
  end
  -- The move's items' screen positions are part of the signature, so the
  -- arrow follows the bank when it scrolls.
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
    -- Sorted tabs follow the "Tabs that are sorted" setting.
    local look = app:isSortedSlot(slot.key) and app.store:get("sortedLook") or "tint"
    if tint and d and look == "green" then
      self:_rect(slot, app.store:colour("done"))
    elseif tint and d and look == "tint" then
      self:_rect(slot, withAlpha(app:destinationColour(d), opacity))
    elseif tint and app:isIgnored(slot.objectID) then
      self:_rect(slot, IGNORED_OUTLINE, 1)
    end
    -- The guide's mark wins over a tag label on the same slot.
    local mark = marks[slot.key]
    if mark then
      local colour = app.store:colour(mark[2])
      self:_rect(slot, colour, 3)
      self:_label(slot, mark[1], colour)
    else
      local text, colourKey = app:slotLabel(slot.key)
      if text then self:_badge(slot, text, app.store:colour(colourKey)) end
    end
  end
  local ok, err = pcall(function() self:_guideLine(app, container, byId) end)
  if not ok and log then log("[bank-organizer] guide line failed: " .. tostring(err)) end
  return true
end

-- Destroys everything drawn and forgets the signature.
function Overlay:clear()
  for _, component in ipairs(self.components) do pcall(function() return component:Destroy() end) end
  self.components, self.signature, self.container = {}, nil, nil
end

return Overlay
