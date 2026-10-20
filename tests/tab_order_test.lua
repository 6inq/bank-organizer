local A = require("assert")
local TabOrder = require("src/core/tab_order")

local T = {}

local CONTAINER = { [0] = { 9, 10 }, [1] = { 1, 2 }, [2] = { 3 }, [3] = { 4, 5 } }

function T.learns_the_on_screen_order_from_the_infinity_view()
  A.list(TabOrder.learn({ 9, 10, 4, 5, 1, 2, 3 }, CONTAINER), { 3, 1, 2 })
end

function T.refuses_a_view_that_does_not_add_up()
  A.eq(TabOrder.learn({ 9, 4, 10, 5, 1, 2, 3 }, CONTAINER), nil, "a tab split in two")
  A.eq(TabOrder.learn({ 9, 10, 1, 2, 3 }, CONTAINER), nil, "a tab missing")
end

function T.maps_both_ways_and_keeps_room_for_a_new_tab()
  local displayOf, containerOf = TabOrder.maps({ 3, 1, 2 }, CONTAINER)
  A.eq(displayOf[3], 1); A.eq(displayOf[1], 2); A.eq(displayOf[2], 3); A.eq(displayOf[0], 0)
  A.eq(containerOf[1], 3); A.eq(containerOf[3], 2)
  A.eq(displayOf[4], 4, "a new tab is stored and shown last")
  local shown = TabOrder.toDisplay(CONTAINER, displayOf)
  A.list(shown[1], { 4, 5 }); A.list(shown[2], { 1, 2 }); A.list(shown[3], { 3 })
end

function T.an_order_that_no_longer_fits_is_ignored()
  local displayOf = TabOrder.maps({ 2, 1 }, CONTAINER)
  A.eq(displayOf[1], 1, "three tabs now, the saved order had two")
  A.eq(TabOrder.fits({ 3, 1, 2 }, CONTAINER), true)
  A.eq(TabOrder.fits({ 3, 3, 2 }, CONTAINER), false)
end

function T.container_sequence_lists_shown_tabs_in_stored_order()
  local displayOf, containerOf = TabOrder.maps({ 3, 1, 2 }, CONTAINER)
  A.list(TabOrder.containerSequence(displayOf, containerOf, true), { 2, 3, 1, 4, 0 })
end

return T
