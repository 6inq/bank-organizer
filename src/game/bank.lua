-- Bank Organizer: everything read from the game's bank.
--
-- Two sources are read:
--   * the bank inventory (Inventory.Find(config.Inv.BANK)): every item in
--     the order the game STORES it, with amounts. This is the truth used
--     for planning.
--   * the bank interface's slot components: what is ON SCREEN right now,
--     with positions, used for drawing and for telling which tab is shown.
--
-- Facts about the client this file depends on (verified in game):
--   * Tab sizes are the BANK_TAB2..BANK_TAB15 player variables. The game
--     stores custom tabs first and the infinity tab's items last.
--   * BANK_TAB_k_MAPPING_SERVER says which stored tab is shown as Tab k.
--   * The slot area (BANK__BANK_INV) never scrolls itself; a parent
--     viewport holds the scroll offset (see Bank.scrollFrame).
--   * Unstackable items that repeat (like filled Ushabti) share one item id,
--     so every copy gets its own key: id + n * 2^24 (Bank.KEY_STRIDE).
--
-- Every client read is wrapped in pcall(function() ... end). Native client
-- functions must never be passed straight to pcall: that crashes the
-- client.

local Bank = {}

-- The client component name of the slot area.
local SLOT_COMPONENT = "BANK__BANK_INV"

-- BANK_CURRENT_TAB reads 1 while the infinity ("All items") view is open.
local ALL_ITEMS_TAB = 1

-- Item facts by item id, read once per plugin load (configs never change).
local infoCache = {}

-- Reads a game variable's value, for example var.VarPlayer.BANK_TAB2.
-- Returns nil when the variable does not exist or cannot be read.
local function varValue(group, name)
  local ok, value = pcall(function()
    local entry = var[group][name]
    return entry and entry.value
  end)
  if ok then return value end
  return nil
end

-- Returns the bank's slot area component when the bank is open and shown,
-- otherwise nil.
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

-- 2^24: larger than any item id, so id + n * KEY_STRIDE never collides.
Bank.KEY_STRIDE = 16777216

-- Returns the real item id inside a per-copy key.
function Bank.realId(key)
  return key % Bank.KEY_STRIDE
end

-- Returns a function that gives each copy of an item its own key: the first
-- copy keeps the plain id, the second gets id + KEY_STRIDE, and so on.
local function keyer()
  local seen = {}
  return function(objectID)
    local n = seen[objectID] or 0
    seen[objectID] = n + 1
    return objectID + n * Bank.KEY_STRIDE
  end
end

-- Returns true for a visible slot component that shows an item.
local function isItemSlot(component)
  return component.type == ui.ComponentType.SPRITE and component.associatedObjectID ~= nil
    and component.associatedObjectID >= 0 and component.visible and not component.hidden
end

-- Orders slots like reading: top row first, left to right.
local function rowMajor(a, b)
  if a.y ~= b.y then return a.y < b.y end
  return a.x < b.x
end

-- Reads the item slots on screen.
-- Returns (slots, nil, container), or (nil, message) when the bank is
-- closed. Each slot is { objectID, key, component, x, y, width, height,
-- quantity }, in reading order, with per-copy keys.
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
    -- Returning false tells the client to keep iterating.
    return false
  end)
  table.sort(slots, rowMajor)
  local keyOf = keyer()
  for _, slot in ipairs(slots) do slot.key = keyOf(slot.objectID) end
  return slots, nil, container
end

-- Returns an item's right-click option names as a set (lower case).
local function readOps(obj)
  local ops = {}
  local names = obj.interfaceOpNames
  if type(names) ~= "table" and type(names) ~= "userdata" then return ops end
  for _, op in pairs(names) do
    if type(op) == "string" then ops[op:lower()] = true end
  end
  return ops
end

-- Counts the entries in a list (0 for anything that is not a table).
local function count(list)
  local n = 0
  for _ in pairs(type(list) == "table" and list or {}) do n = n + 1 end
  return n
end

-- For equipment only: returns the item's params as "name=value|..." text,
-- saved in the export to help improve classification. Nil otherwise.
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

-- Reads the facts about one item from its config. Returns nil when the item
-- has no config. May throw; Bank.info wraps it.
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

-- Returns the cached facts about an item:
--   { id, name, category, ops, quests (count), tradeable, stockmarket,
--     cost (item value), params }
-- An unreadable item still gets a placeholder name so nothing breaks.
function Bank.info(objectID)
  local cached = infoCache[objectID]
  if cached then return cached end
  -- lookup is this file's own Lua function, so passing it to pcall is safe.
  local ok, info = pcall(lookup, objectID)
  if not ok or info == nil then info = { id = objectID, name = "Item " .. tostring(objectID), ops = {} } end
  infoCache[objectID] = info
  return info
end

-- Returns true while the bank search box is in use (the view is filtered,
-- so tabs cannot be read).
function Bank.searchActive()
  local mode = varValue("VarClient", "BANK_SEARCHMODE_CLIENT")
  return mode ~= nil and mode ~= false and mode ~= 0
end

-- Returns the game's current-tab variable. Not always reliable for which
-- tab is on screen; App:_viewedSection checks the visible items instead.
function Bank.currentTab()
  return varValue("VarPlayer", "BANK_CURRENT_TAB")
end

-- Returns true while the infinity ("All items") view is open.
function Bank.isAllItemsTab()
  return Bank.currentTab() == ALL_ITEMS_TAB
end

-- Returns a short text that changes whenever the bank view changes (tab,
-- filter or search).
function Bank.viewSignature()
  return table.concat({
    tostring(varValue("VarPlayer", "BANK_CURRENT_TAB")),
    tostring(varValue("VarPlayer", "BANK_FILTER")),
    tostring(varValue("VarClient", "BANK_SEARCHMODE_CLIENT")),
    tostring(varValue("VarClient", "BANK_LASTSEARCHSTRING")),
  }, ":")
end

-- The game variables that describe tabs:
--   sizes       BANK_TAB2..BANK_TAB15: items in each custom tab
--   insertMode  BANKINSERT: 1 for Insert, 0 for Swap
--   tabsFirst   custom tabs are stored before the infinity tab's items
Bank.TAB_VARS = {
  group = "VarPlayer",
  sizes = {
    "BANK_TAB2", "BANK_TAB3", "BANK_TAB4", "BANK_TAB5", "BANK_TAB6", "BANK_TAB7", "BANK_TAB8",
    "BANK_TAB9", "BANK_TAB10", "BANK_TAB11", "BANK_TAB12", "BANK_TAB13", "BANK_TAB14", "BANK_TAB15",
  },
  insertMode = "BANKINSERT",
  tabsFirst = true,
}

-- Returns the 14 custom tab sizes in stored order, or nil when any of them
-- cannot be read.
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

-- Returns true for Insert mode, false for Swap, nil when unreadable.
function Bank.insertMode()
  local name = Bank.TAB_VARS.insertMode
  if not name then return nil end
  local value = varValue(Bank.TAB_VARS.group, name)
  if value == nil then return nil end
  return value ~= 0
end

-- Reads every item in the bank in stored order.
-- Returns a list of { slot, id (per-copy key), objectId (real id), name,
-- quantity, info }, or nil when the bank cannot be read.
function Bank.readItems()
  local ok, items = pcall(function()
    local inv = Inventory.Find(config.Inv.BANK)
    if not inv or not inv.isValid then return nil end
    local list, keyOf = {}, keyer()
    for slot, entry in ipairs(inv:GetSlots() or {}) do
      local obj = entry and entry.obj
      if obj and obj.id and obj.id >= 0 then
        local info = Bank.info(obj.id)
        list[#list + 1] = { slot = slot, id = keyOf(obj.id), objectId = obj.id, name = info.name, quantity = entry.count or 0, info = info }
      end
    end
    return list
  end)
  if ok then return items end
  return nil
end

-- Splits the stored item list into tabs using the tab sizes.
--   items      from Bank.readItems
--   sizes      from Bank.tabSizes
--   tabsFirst  true when custom tabs are stored before infinity's items
-- Returns stored position -> list of item keys. Empty custom tabs are left
-- out; position 0 (infinity) is always present.
function Bank.sections(items, sizes, tabsFirst)
  local sections, cursor = { [0] = {} }, 1
  -- Moves the next count items into a list.
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

-- Returns the on-screen slots by key, the slot area, and the slot list.
function Bank.componentsById()
  local slots, _, container = Bank.scan()
  local byId = {}
  for _, slot in ipairs(slots or {}) do byId[slot.key] = slot end
  return byId, container, slots
end

-- Forgets cached item facts (used by tests).
function Bank._resetCache()
  infoCache = {}
end

-- Returns a component's scroll offset (x, y), or 0, 0.
function Bank.scroll(container)
  local ok, x, y = pcall(function() return container.scrollX, container.scrollY end)
  if ok then return tonumber(x) or 0, tonumber(y) or 0 end
  return 0, 0
end

-- Returns a component's position on screen, or 0, 0 when unreadable.
function Bank.globalXY(component)
  local ok, x, y = pcall(function()
    local xy = component.xyGlobal
    return xy.x, xy.y
  end)
  if ok and type(x) == "number" and type(y) == "number" then return x, y end
  return 0, 0
end

-- Returns the layer the guide line is drawn on (the plugin's top layer, so
-- it can reach tab buttons outside the slot area) and its screen position.
-- Falls back to the slot area itself.
function Bank.drawLayer(container)
  local ok, layer = pcall(function()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
  end)
  local host = ok and layer or container
  local x, y = Bank.globalXY(host)
  return host, x, y
end

-- The bank interface's static components are numbered from 0; none of the
-- ones needed are above this.
local MAX_STATIC_ID = 400

-- Lists every component of the bank interface except the slot area itself:
-- each static component and its dynamic children, as { component, staticID,
-- dynamic }.
local function bankComponents(container)
  local list = {}
  local cx, cy = Bank.globalXY(container)
  -- The slot area is skipped (it would list every item slot again).
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

-- Tab buttons are square-ish and between these sizes, in pixels.
local BUTTON_MIN, BUTTON_MAX = 20, 72

-- How far above the slot area the tab button row may be, in pixels.
local ROW_REACH = 80

-- Returns true when a component is shown.
local function isShown(component)
  local ok, shown = pcall(function()
    if component.hidden then return false end
    if component.visibleGlobal ~= nil then return component.visibleGlobal end
    return component.visible ~= false
  end)
  return ok and shown
end

-- Finds the tab buttons above the slot area, left to right, as screen boxes
-- { x, y, width, height }. There is no named component for them, so they are
-- found by shape: shown, button-sized, in the row just above the slots.
-- Components in the same column are merged (largest wins), and only the
-- most common button width is kept so stray icons are dropped.
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
  -- Count widths in 4 pixel steps and keep the most common one.
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

-- Reads a number property from a component, or nil.
local function number(component, field)
  local ok, value = pcall(function() return component[field] end)
  return ok and tonumber(value) or nil
end

-- Finds the viewport that scrolls the slot area: the smallest bank
-- component that contains the slot area's top left corner and can scroll
-- (its content is taller than itself, or it is scrolled already). Returns
-- nil when there is none.
function Bank.scrollFrame(container)
  local cx, cy = Bank.globalXY(container)
  local best, area
  for _, found in ipairs(bankComponents(container)) do
    local c = found.component
    if not found.dynamic then
      local w, h, sh = number(c, "width") or 0, number(c, "height") or 0, number(c, "scrollHeight") or 0
      local x, y = Bank.globalXY(c)
      local scrolls = sh > h + 1 or (number(c, "scrollY") or 0) > 0
      if scrolls and w > 0 and h > 0 and cx >= x - 1 and cx <= x + w and cy >= y - 1 and cy <= y + h and (area == nil or w * h < area) then
        best, area = c, w * h
      end
    end
  end
  return best
end

-- Returns the visible window onto the slots: total scroll offset (slot area
-- plus viewport) and the visible box on screen.
function Bank.view(container, frame)
  local sx, sy = Bank.scroll(container)
  local host = container
  if frame then
    local fx, fy = Bank.scroll(frame)
    sx, sy, host = sx + fx, sy + fy, frame
  end
  local x, y = Bank.globalXY(host)
  return { scrollX = sx, scrollY = sy, x = x, y = y, width = number(host, "width") or 0, height = number(host, "height") or 0 }
end

-- Describes the bank interface as text (component names, tab mapping,
-- fonts and every component's position and size). Saved by Analyze into
-- PersistentDB as bank-organizer-ui, to diagnose layout problems.
function Bank.describeInterface(container)
  local lines = { "names: " .. table.concat(Bank.componentNames("BANK__"), ","), "mapping: " .. table.concat(Bank.tabMapping(), ","),
    "fonts: " .. table.concat(Bank.fontNames(), ",") }
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

-- Reads the live tab order from BANK_TAB_k_MAPPING_SERVER: shown Tab k
-- (k = 2..15) holds stored tab (value - 1). Returns order[shown position]
-- = stored position, stopping at the first unset variable.
function Bank.liveDisplayOrder()
  local order = {}
  for tab = 2, 15 do
    local value = tonumber(varValue("VarPlayer", "BANK_TAB_" .. tab .. "_MAPPING_SERVER"))
    if not value or value < 1 then break end
    order[tab - 1] = value - 1
  end
  return order
end

-- Returns the raw mapping variables as text, for diagnostics.
function Bank.tabMapping()
  local values = {}
  for tab = 2, 15 do values[#values + 1] = tostring(varValue("VarPlayer", "BANK_TAB_" .. tab .. "_MAPPING_SERVER")) end
  return values
end

-- Returns the font names the client lists, for diagnostics. Some clients
-- cannot list id tables at all; the result is then empty. Never use a font
-- name just because it appears here: only known fonts are used in drawing.
function Bank.fontNames()
  local names = {}
  pcall(function()
    for name in pairs(id.Font) do
      if type(name) == "string" then names[#names + 1] = name end
    end
  end)
  table.sort(names)
  return names
end

-- Returns component names that start with prefix, for diagnostics.
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
