local F = {}

local SPRITE, RECT = 5, 3

local function component(fields)
  local c = { visible = true, hidden = false, type = SPRITE, width = 36, height = 32, destroyed = false }
  for k, v in pairs(fields or {}) do c[k] = v end
  function c:SetPos(x, y) self.x, self.y = x, y end
  function c:SetSize(w, h) self.width, self.height = w, h end
  function c:Destroy() self.destroyed = true; F.destroyed = F.destroyed + 1 end
  return c
end

function F.install(opts)
  opts = opts or {}
  F.created, F.destroyed, F.events = {}, 0, {}
  local children = {}
  for _, item in ipairs(opts.items or {}) do
    children[#children + 1] = component({
      associatedObjectID = item.id, x = item.x, y = item.y, associatedObjectQuantity = item.qty or 1,
      hidden = item.hidden or false, visible = item.visible ~= false, type = item.type or SPRITE,
      interfaceID = 517,
    })
  end
  local container = component({ visibleGlobal = opts.visible ~= false, width = 400, height = 600 })
  function container:IterateDynamicComponents(fn)
    for _, child in ipairs(children) do
      if fn(child) then return end
    end
  end
  F.container, F.children = container, children

  local function factory(kind)
    return { new = function(parent)
      local c = component({ kind = kind, parent = parent, type = RECT })
      F.created[#F.created + 1] = c
      return c
    end }
  end

  _G.ui = {
    ComponentType = { SPRITE = SPRITE },
    SelectionChangeEvent = { SELECTED = 1 },
    Interfaces = { GetComponent = function(_, componentID)
      if opts.missing then return nil end
      if componentID == 1001 then return container end
      return nil
    end },
    Rectangle = factory("rect"),
    Text = factory("text"),
  }
  _G.id = {
    Component = { BANK__BANK_INV = 1001 },
    Interface = { BANK = 517 },
    Font = { MUSEO_SANS_15PT_REGULAR = 1 },
    Category = { FromID = function(n) return (opts.categories or {})[n] end },
  }
  _G.var = {
    VarPlayer = { BANK_CURRENT_TAB = { value = opts.tab or 2 }, BANK_FILTER = { value = 0 } },
    VarClient = { BANK_SEARCHMODE_CLIENT = { value = opts.search or 0 }, BANK_LASTSEARCHSTRING = { value = "" } },
  }
  _G.config = {
    Inv = { BANK = { id = 95 } },
    Obj = { FromID = function(objectID)
      local def = (opts.objects or {})[objectID]
      if def == nil then return nil end
      return { id = objectID, name = def.name, category = def.category, interfaceOpNames = def.ops or {} }
    end },
  }
  local function bus(name)
    return {
      Subscribe = function(key, fn) F.events[name .. ":" .. key] = fn end,
      Unsubscribe = function(key) F.events[name .. ":" .. key] = nil end,
    }
  end
  _G.Event = { Logic = bus("Logic"), InventoryUpdated = bus("InventoryUpdated"), MiniMenuReady = bus("MiniMenuReady") }
  _G.log = function() end
  return container
end

function F.count(kind)
  local n = 0
  for _, c in ipairs(F.created) do
    if c.kind == kind and not c.destroyed then n = n + 1 end
  end
  return n
end

function F.memoryDb()
  local db = { data = {} }
  function db:GetStructuredData(key) return self.data[key] end
  function db:SetStructuredData(key, value) self.data[key] = value end
  return db
end

return F
