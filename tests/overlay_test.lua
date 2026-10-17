local A = require("assert")
local F = require("fakes")
local Overlay = require("src/game/overlay")

local T = {}

local function slots()
  return {
    { objectID = 1, x = 0, y = 0, width = 36, height = 32 },
    { objectID = 2, x = 40, y = 0, width = 36, height = 32 },
    { objectID = 3, x = 80, y = 0, width = 36, height = 32 },
  }
end

local function view(overrides)
  local v = {
    overlays = true, filter = "all", highlightUntagged = false, opacity = 0.5,
    categoryOf = function(objectID) return objectID == 1 and "food" or "combat" end,
    colourOf = function() return 0xFF000000 + 0xFF end,
    isTagged = function(objectID) return objectID == 1 end,
  }
  for k, val in pairs(overrides or {}) do v[k] = val end
  return v
end

function T.render_creates_one_tint_per_slot()
  local container = F.install()
  local overlay = Overlay.new()
  A.eq(overlay:render(container, slots(), view()), true)
  A.eq(F.count("rect"), 3)
  for _, c in ipairs(F.created) do A.eq(c.clickthrough, true, "overlay must be clickthrough") end
  A.eq(F.created[1].rgba, 0xFF000080, "tint alpha from opacity")
end

function T.same_signature_does_not_rebuild()
  local container = F.install()
  local overlay = Overlay.new()
  overlay:render(container, slots(), view())
  A.eq(overlay:render(container, slots(), view()), false)
  A.eq(#F.created, 3)
end

function T.changed_slot_rebuilds()
  local container = F.install()
  local overlay = Overlay.new()
  overlay:render(container, slots(), view())
  local moved = slots(); moved[1].x = 120
  A.eq(overlay:render(container, moved, view()), true)
  A.eq(F.count("rect"), 3); A.eq(F.destroyed, 3)
end

function T.clear_destroys_all()
  local container = F.install()
  local overlay = Overlay.new()
  overlay:render(container, slots(), view({ move = { move = 3, before = 1, remaining = 1 } }))
  overlay:clear()
  A.eq(F.count("rect"), 0); A.eq(F.count("text"), 0)
end

function T.filter_dims_non_matching()
  local container = F.install()
  Overlay.new():render(container, slots(), view({ filter = "food" }))
  A.eq(F.created[1].rgba, 0xFF000080); A.eq(F.created[2].rgba, 0x000000AA); A.eq(F.created[3].rgba, 0x000000AA)
end

function T.highlight_untagged_outlines()
  local container = F.install()
  Overlay.new():render(container, slots(), view({ highlightUntagged = true }))
  A.eq(F.count("rect"), 5, "3 tints + 2 untagged outlines")
end

function T.move_highlights_and_labels()
  local container = F.install()
  Overlay.new():render(container, slots(), view({ overlays = false, move = { move = 3, before = 1, remaining = 1 } }))
  A.eq(F.count("rect"), 2); A.eq(F.count("text"), 2)
  local labels = {}
  for _, c in ipairs(F.created) do if c.kind == "text" then labels[#labels + 1] = c.content end end
  A.list(labels, { "INSERT BEFORE", "MOVE" })
end

function T.after_move_label()
  local container = F.install()
  Overlay.new():render(container, slots(), view({ overlays = false, move = { move = 1, after = 3, remaining = 1 } }))
  local labels = {}
  for _, c in ipairs(F.created) do if c.kind == "text" then labels[#labels + 1] = c.content end end
  A.list(labels, { "MOVE", "AFTER" })
end

function T.container_change_clears()
  local first = F.install()
  local overlay = Overlay.new()
  overlay:render(first, slots(), view())
  local second = F.install()
  overlay:render(second, slots(), view())
  A.eq(F.count("rect"), 3)
end

return T
