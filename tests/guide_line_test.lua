local A = require("assert")
_G.Vector4 = _G.Vector4 or { new = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
local GuideLine = require("src/game/guide_line")

local T = {}

local function slot(x, y) return { x = x, y = y, width = 36, height = 32 } end
local VIEW = { x = 0, y = 0, width = 400, height = 300 }

local function near(actual, expected, label)
  A.truthy(math.abs(actual - expected) < 0.01, (label or "") .. ": expected " .. expected .. ", got " .. actual)
end

function T.insert_before_ends_on_a_bar_in_the_gap()
  local plan = GuideLine.plan(slot(200, 100), { kind = "before", box = slot(40, 100) }, VIEW)
  A.eq(plan.marker.kind, "bar")
  A.eq(plan.marker.height, 32)
  near(plan.marker.x, 40 - 2 - 1, "bar sits in the gap left of the target")
  near(plan.finish[1], 39, "line ends on the bar"); near(plan.finish[2], 116)
end

function T.insert_after_puts_the_bar_on_the_right()
  local plan = GuideLine.plan(slot(200, 100), { kind = "after", box = slot(40, 100) }, VIEW)
  near(plan.finish[1], 40 + 36 + 1, "right edge")
end

function T.start_leaves_the_item_icon_uncovered()
  local plan = GuideLine.plan(slot(200, 100), { kind = "swap", box = slot(40, 100) }, VIEW)
  near(plan.start[1], 218 - 18, "starts at the item's edge"); near(plan.start[2], 116)
  A.eq(plan.marker.kind, "box")
end

function T.short_lines_start_at_the_centre()
  local plan = GuideLine.plan(slot(60, 100), { kind = "swap", box = slot(40, 100) }, VIEW)
  near(plan.start[1], 78)
end

function T.arrowhead_points_back_along_the_line()
  local plan = GuideLine.plan(slot(200, 100), { kind = "swap", box = slot(40, 100) }, VIEW)
  A.eq(#plan.arrow, 2)
  for _, leg in ipairs(plan.arrow) do
    near(leg[1], plan.finish[1]); near(leg[2], plan.finish[2])
    A.truthy(leg[3] > plan.finish[1], "legs trail back toward the item")
  end
  A.truthy(plan.arrow[1][4] ~= plan.arrow[2][4], "one leg above, one below")
end

function T.tab_targets_end_under_the_button()
  local button = { x = 148, y = -40, width = 40, height = 40 }
  local plan = GuideLine.plan(slot(200, 100), { kind = "tab", box = button }, VIEW)
  near(plan.finish[1], 168); near(plan.finish[2], 0)
  A.eq(plan.marker.width, 44, "button outlined with a margin")
end

function T.offscreen_targets_point_at_the_edge()
  local plan = GuideLine.plan(slot(200, 100), { kind = "before", box = slot(40, 900) }, VIEW)
  A.eq(plan.marker, nil, "no marker for a slot you cannot see")
  near(plan.finish[2], 296, "line stops at the bottom edge")
end

function T.no_line_when_already_there()
  A.eq(GuideLine.plan(slot(40, 100), { kind = "swap", box = slot(40, 100) }, VIEW), nil)
end

function T.box_covers_both_directions()
  local x, y, w, h, invert = GuideLine.box(10, 10, 50, 90)
  A.eq(x, 10); A.eq(y, 10); A.eq(w, 40); A.eq(h, 80); A.eq(invert, false)
  x, y, w, h, invert = GuideLine.box(50, 10, 10, 90)
  A.eq(invert, true)
end

function T.item_above_the_view_points_up()
  local plan = GuideLine.plan(slot(200, -80), { kind = "swap", box = slot(40, 100) }, VIEW)
  A.eq(plan.scroll, "up"); A.eq(plan.marker, nil)
  near(plan.finish[2], 6, "tip at the top edge"); near(plan.start[2], 32)
  near(plan.finish[1], 218, "in the item's column")
end

function T.item_below_the_view_points_down()
  local plan = GuideLine.plan(slot(390, 500), { kind = "tab", box = slot(40, -40) }, VIEW)
  A.eq(plan.scroll, "down")
  near(plan.finish[2], 294); near(plan.finish[1], 388, "kept inside the view")
  for _, leg in ipairs(plan.arrow) do A.truthy(leg[4] < plan.finish[2], "arrowhead opens upward from the tip") end
end

return T
