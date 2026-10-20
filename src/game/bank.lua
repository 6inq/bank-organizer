local Bank = {}

local SLOT_COMPONENT = "BANK__BANK_INV"
local ALL_ITEMS_TAB = 1
local infoCache = {}

local function varValue(group, name)
  local ok, value = pcall(function()
    local entry = var[group][name]
    return entry and entry.value
  end)
  if ok then return value end
  return nil
end

function Bank.slotsContainer()
  local ok, container = pcall(function()
    local componentID = id.Component[SLOT_COMPONENT]
    if componentID == nil or componentID < 0 then return nil end
    return ui.Interfaces:GetComponent(componentID)
  end)
  if not ok or container == nil then return nil end
  if not container.visibleGlobal or container.width <= 0 or container.height <= 0 then return nil end
  return container
end

local function isItemSlot(component)
  return component.type == ui.ComponentType.SPRITE and component.associatedObjectID ~= nil
    and component.associatedObjectID >= 0 and component.visible and not component.hidden
end

local function rowMajor(a, b)
  if a.y ~= b.y then return a.y < b.y end
  return a.x < b.x
end

function Bank.scan()
  local container = Bank.slotsContainer()
  if container == nil then return nil, "Open your bank." end
  local slots = {}
  container:IterateDynamicComponents(function(component)
    if isItemSlot(component) then
      slots[#slots + 1] = {
        objectID = component.associatedObjectID, component = component,
        x = component.x, y = component.y, width = component.width, height = component.height,
        quantity = component.associatedObjectQuantity,
      }
    end
    return false
  end)
  table.sort(slots, rowMajor)
  return slots, nil, container
end

local function readOps(obj)
  local ops = {}
  local names = obj.interfaceOpNames
  if type(names) ~= "table" and type(names) ~= "userdata" then return ops end
  for _, op in pairs(names) do
    if type(op) == "string" then ops[op:lower()] = true end
  end
  return ops
end

local function count(list)
  local n = 0
  for _ in pairs(type(list) == "table" and list or {}) do n = n + 1 end
  return n
end

local function readParams(obj, ops)
  if not (ops.wear or ops.wield or ops.equip) then return nil end
  local ok, text = pcall(function()
    local parts = {}
    for _, param in pairs(obj.params) do
      parts[#parts + 1] = tostring(param.configName or param.id) .. "=" .. tostring(obj:GetParamValue(param))
    end
    table.sort(parts)
    return table.concat(parts, "|")
  end)
  return ok and text or nil
end

local function lookup(objectID)
  local obj = config.Obj.FromID(objectID)
  if obj == nil then return nil end
  local categoryName = obj.category and obj.category >= 0 and id.Category.FromID(obj.category) or nil
  local ops = readOps(obj)
  return {
    id = objectID, name = obj.name, category = categoryName, ops = ops,
    quests = count(obj.quests), tradeable = obj.isTradeable, stockmarket = obj.isStockmarket, cost = obj.cost,
    params = readParams(obj, ops),
  }
end

function Bank.info(objectID)
  local cached = infoCache[objectID]
  if cached then return cached end
  local ok, info = pcall(lookup, objectID)
  if not ok or info == nil then info = { id = objectID, name = "Item " .. tostring(objectID), ops = {} } end
  infoCache[objectID] = info
  return info
end

function Bank.searchActive()
  local mode = varValue("VarClient", "BANK_SEARCHMODE_CLIENT")
  return mode ~= nil and mode ~= false and mode ~= 0
end

function Bank.currentTab()
  return varValue("VarPlayer", "BANK_CURRENT_TAB")
end

function Bank.isAllItemsTab()
  return Bank.currentTab() == ALL_ITEMS_TAB
end

function Bank.viewSignature()
  return table.concat({
    tostring(varValue("VarPlayer", "BANK_CURRENT_TAB")),
    tostring(varValue("VarPlayer", "BANK_FILTER")),
    tostring(varValue("VarClient", "BANK_SEARCHMODE_CLIENT")),
    tostring(varValue("VarClient", "BANK_LASTSEARCHSTRING")),
  }, ":")
end

Bank.TAB_VARS = {
  group = "VarPlayer",
  sizes = {
    "BANK_TAB2", "BANK_TAB3", "BANK_TAB4", "BANK_TAB5", "BANK_TAB6", "BANK_TAB7", "BANK_TAB8",
    "BANK_TAB9", "BANK_TAB10", "BANK_TAB11", "BANK_TAB12", "BANK_TAB13", "BANK_TAB14", "BANK_TAB15",
  },
  insertMode = "BANKINSERT",
  tabsFirst = true,
}

function Bank.tabSizes()
  local vars = Bank.TAB_VARS
  if #vars.sizes == 0 then return nil end
  local sizes = {}
  for index, name in ipairs(vars.sizes) do
    local value = varValue(vars.group, name)
    if type(value) ~= "number" or value < 0 then return nil end
    sizes[index] = value
  end
  return sizes
end

function Bank.insertMode()
  local name = Bank.TAB_VARS.insertMode
  if not name then return nil end
  local value = varValue(Bank.TAB_VARS.group, name)
  if value == nil then return nil end
  return value ~= 0
end

function Bank.readItems()
  local ok, items = pcall(function()
    local inv = Inventory.Find(config.Inv.BANK)
    if not inv or not inv.isValid then return nil end
    local list = {}
    for slot, entry in ipairs(inv:GetSlots() or {}) do
      local obj = entry and entry.obj
      if obj and obj.id and obj.id >= 0 then
        local info = Bank.info(obj.id)
        list[#list + 1] = { slot = slot, id = obj.id, name = info.name, quantity = entry.count or 0, info = info }
      end
    end
    return list
  end)
  if ok then return items end
  return nil
end

function Bank.sections(items, sizes, tabsFirst)
  local sections, cursor = { [0] = {} }, 1
  local function take(count, into)
    for _ = 1, count do
      local item = items[cursor]
      if not item then return end
      table.insert(into, item.id)
      cursor = cursor + 1
    end
  end
  if tabsFirst ~= false then
    for tab, size in ipairs(sizes) do
      if size > 0 then sections[tab] = {}; take(size, sections[tab]) end
    end
    while items[cursor] do table.insert(sections[0], items[cursor].id); cursor = cursor + 1 end
  else
    local tabbed = 0
    for _, size in ipairs(sizes) do tabbed = tabbed + size end
    take(#items - tabbed, sections[0])
    for tab, size in ipairs(sizes) do
      if size > 0 then sections[tab] = {}; take(size, sections[tab]) end
    end
  end
  return sections
end

function Bank.componentsById()
  local slots, _, container = Bank.scan()
  local byId = {}
  for _, slot in ipairs(slots or {}) do byId[slot.objectID] = slot end
  return byId, container, slots
end

function Bank._resetCache()
  infoCache = {}
end

function Bank.scroll(container)
  local ok, x, y = pcall(function() return container.scrollX, container.scrollY end)
  if ok then return tonumber(x) or 0, tonumber(y) or 0 end
  return 0, 0
end

function Bank.globalXY(component)
  local ok, x, y = pcall(function()
    local xy = component.xyGlobal
    return xy.x, xy.y
  end)
  if ok and type(x) == "number" and type(y) == "number" then return x, y end
  return 0, 0
end

function Bank.drawLayer(container)
  local ok, layer = pcall(function()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
  end)
  local host = ok and layer or container
  local x, y = Bank.globalXY(host)
  return host, x, y
end

local MAX_STATIC_ID = 400

local function bankComponents(container)
  local list = {}
  local cx, cy = Bank.globalXY(container)
  local function isSlotArea(component)
    local x, y = Bank.globalXY(component)
    return x == cx and y == cy and component.width == container.width and component.height == container.height
  end
  for staticID = 0, MAX_STATIC_ID do
    local ok, component = pcall(function() return ui.Interfaces:GetComponent(id.Interface.BANK, staticID) end)
    if ok and component and not isSlotArea(component) then
      list[#list + 1] = { component = component, staticID = staticID }
      pcall(function()
        component:IterateDynamicComponents(function(child)
          list[#list + 1] = { component = child, staticID = staticID, dynamic = true }
          return false
        end)
      end)
    end
  end
  return list
end
Bank._bankComponents = bankComponents

local BUTTON_MIN, BUTTON_MAX = 20, 72
local ROW_REACH = 80

local function isShown(component)
  local ok, shown = pcall(function()
    if component.hidden then return false end
    if component.visibleGlobal ~= nil then return component.visibleGlobal end
    return component.visible ~= false
  end)
  return ok and shown
end

function Bank.tabButtons(container)
  local cx, cy = Bank.globalXY(container)
  local byColumn = {}
  for _, found in ipairs(bankComponents(container)) do
    local component = found.component
    local w, h = component.width or 0, component.height or 0
    if w >= BUTTON_MIN and w <= BUTTON_MAX and h >= BUTTON_MIN and h <= BUTTON_MAX and isShown(component) then
      local x, y = Bank.globalXY(component)
      local inRow = y + h <= cy + 4 and y + h >= cy - ROW_REACH and x >= cx - 24 and x <= cx + (container.width or 0)
      if inRow then
        local column = math.floor(x / 8 + 0.5)
        local best = byColumn[column]
        if not best or w * h > best.width * best.height then
          byColumn[column] = { x = x, y = y, width = w, height = h }
        end
      end
    end
  end
  local widths, common, most = {}, nil, 0
  for _, box in pairs(byColumn) do
    local key = math.floor(box.width / 4 + 0.5)
    widths[key] = (widths[key] or 0) + 1
    if widths[key] > most then common, most = key, widths[key] end
  end
  local buttons = {}
  for _, box in pairs(byColumn) do
    if math.floor(box.width / 4 + 0.5) == common then buttons[#buttons + 1] = box end
  end
  table.sort(buttons, function(a, b) return a.x < b.x end)
  return buttons
end

function Bank.describeInterface(container)
  local lines = { "names: " .. table.concat(Bank.componentNames("BANK__"), ","), "mapping: " .. table.concat(Bank.tabMapping(), ",") }
  for _, found in ipairs(bankComponents(container)) do
    local c = found.component
    local ok, line = pcall(function()
      local x, y = Bank.globalXY(c)
      return table.concat({ found.staticID, found.dynamic and "d" or "s", tostring(c.type), x, y, c.width, c.height,
        tostring(isShown(c)), tostring(c.associatedObjectID) }, "\t")
    end)
    if ok then lines[#lines + 1] = line end
  end
  return table.concat(lines, "\n")
end

function Bank.tabMapping()
  local values = {}
  for tab = 2, 15 do values[#values + 1] = tostring(varValue("VarPlayer", "BANK_TAB_" .. tab .. "_MAPPING_SERVER")) end
  return values
end

function Bank.componentNames(prefix)
  local names = {}
  pcall(function()
    for name in pairs(id.Component) do
      if type(name) == "string" and name:sub(1, #prefix) == prefix then names[#names + 1] = name end
    end
  end)
  table.sort(names)
  return names
end

return Bank
