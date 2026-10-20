-- Reads the live bank slot grid. Every client access is guarded.
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

---@return ui.ComponentCollection?
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

---@return table[]? slots sorted row-major
---@return string? reason when the bank is unavailable
---@return ui.ComponentCollection? container
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

local function lookup(objectID)
  local obj = config.Obj.FromID(objectID)
  if obj == nil then return nil end
  local categoryName = obj.category and obj.category >= 0 and id.Category.FromID(obj.category) or nil
  return {
    id = objectID, name = obj.name, category = categoryName, ops = readOps(obj),
    quests = count(obj.quests), tradeable = obj.isTradeable, stockmarket = obj.isStockmarket, cost = obj.cost,
  }
end

---@return table { id, name, category, ops }
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

-- RS3's first (main) tab shows every item, like OSRS's All items view. Quest Helper's bank
-- filter relies on the same value (1) for "the main bank tab".
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

-- Bank tab variables, from the client's VarPlayer list (`pan VarPlayer`):
-- Tab 1 is the main tab; BANK_TAB2..BANK_TAB15 hold the item counts of the 14 custom tabs.
-- BANKINSERT is non-zero in Insert mode. tabsFirst: custom-tab items sit before the main
-- tab's in the bank container (as in OSRS); confirmed by the log line Analyze prints.
Bank.TAB_VARS = {
  group = "VarPlayer",
  sizes = {
    "BANK_TAB2", "BANK_TAB3", "BANK_TAB4", "BANK_TAB5", "BANK_TAB6", "BANK_TAB7", "BANK_TAB8",
    "BANK_TAB9", "BANK_TAB10", "BANK_TAB11", "BANK_TAB12", "BANK_TAB13", "BANK_TAB14", "BANK_TAB15",
  },
  insertMode = "BANKINSERT",
  tabsFirst = true,
}

-- Item counts of the custom tabs, or nil when they cannot be read.
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

-- Every occupied bank slot, in container order, with item facts for the classifier.
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

-- Split container-ordered items into sections: [0] = Main, [1..n] = numbered tabs.
---@param sizes integer[] item counts of the custom tabs, in order
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

-- Bank item components by item id, for drawing highlights on the visible slots.
function Bank.componentsById()
  local slots, _, container = Bank.scan()
  local byId = {}
  for _, slot in ipairs(slots or {}) do byId[slot.objectID] = slot end
  return byId, container, slots
end

-- Test hook.
function Bank._resetCache()
  infoCache = {}
end

return Bank
