local TabOrder = {}

local function lastKey(sections)
  local high = 0
  for s in pairs(sections) do if s > high then high = s end end
  return high
end

function TabOrder.learn(displayIds, containerSections)
  local sectionOf = {}
  for s, ids in pairs(containerSections) do
    for _, id in ipairs(ids) do sectionOf[id] = s end
  end
  local order, seen, current = {}, {}, nil
  for _, id in ipairs(displayIds) do
    local s = sectionOf[id]
    if s ~= nil and s ~= current then
      if seen[s] then return nil end
      seen[s], current = true, s
      if s ~= 0 then order[#order + 1] = s end
    end
  end
  for s = 1, lastKey(containerSections) do
    if #(containerSections[s] or {}) > 0 and not seen[s] then return nil end
  end
  return order
end

function TabOrder.fits(order, containerSections)
  if type(order) ~= "table" then return false end
  local listed = {}
  for _, s in ipairs(order) do
    if listed[s] or #(containerSections[s] or {}) == 0 then return false end
    listed[s] = true
  end
  for s = 1, lastKey(containerSections) do
    if #(containerSections[s] or {}) > 0 and not listed[s] then return false end
  end
  return true
end

function TabOrder.maps(order, containerSections)
  local displayOf, containerOf = { [0] = 0 }, { [0] = 0 }
  local used = 0
  if TabOrder.fits(order, containerSections) then
    for position, s in ipairs(order) do displayOf[s], containerOf[position] = position, s end
    used = #order
  end
  for s = 1, math.max(lastKey(containerSections), used) + 1 do
    if displayOf[s] == nil then
      used = used + 1
      displayOf[s], containerOf[used] = used, s
    end
  end
  return displayOf, containerOf
end

function TabOrder.toDisplay(containerSections, displayOf)
  local out = {}
  for s, ids in pairs(containerSections) do out[displayOf[s] or s] = ids end
  return out
end

function TabOrder.containerSequence(displayOf, containerOf, tabsFirst)
  local sequence = {}
  local count = 0
  for position in pairs(containerOf) do if position > count then count = position end end
  local tabs = {}
  for c = 1, count do tabs[#tabs + 1] = displayOf[c] end
  if tabsFirst ~= false then
    for _, d in ipairs(tabs) do sequence[#sequence + 1] = d end
    sequence[#sequence + 1] = 0
  else
    sequence[1] = 0
    for _, d in ipairs(tabs) do sequence[#sequence + 1] = d end
  end
  return sequence
end

return TabOrder
