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

local function lookup(objectID)
  local obj = config.Obj.FromID(objectID)
  if obj == nil then return nil end
  local categoryName = obj.category and id.Category.FromID(obj.category) or nil
  return { id = objectID, name = obj.name, category = categoryName, ops = readOps(obj) }
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

function Bank.isAllItemsTab()
  return varValue("VarPlayer", "BANK_CURRENT_TAB") == ALL_ITEMS_TAB
end

function Bank.viewSignature()
  return table.concat({
    tostring(varValue("VarPlayer", "BANK_CURRENT_TAB")),
    tostring(varValue("VarPlayer", "BANK_FILTER")),
    tostring(varValue("VarClient", "BANK_SEARCHMODE_CLIENT")),
    tostring(varValue("VarClient", "BANK_LASTSEARCHSTRING")),
  }, ":")
end

-- Test hook.
function Bank._resetCache()
  infoCache = {}
end

return Bank
