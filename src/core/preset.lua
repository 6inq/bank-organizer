local Tags = require("src/core/tags")
local Layout = require("src/core/layout")
local Sorting = require("src/core/sorting")

local Preset = {}

Preset.PREFIX = "BO1"
local MAX_LENGTH = 4000

local function escape(text)
  return (text:gsub("[^%w]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function unescape(text)
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function Preset.encode(store)
  local layout = store.layout
  local tabs, names = {}, {}
  for d = 0, layout:last() do
    tabs[#tabs + 1] = table.concat(layout.destinations[d], ",")
    if layout.names[d] then names[#names + 1] = d .. ":" .. escape(layout.names[d]) end
  end
  local pins = {}
  for tag, section in pairs(store.tabHomes or {}) do pins[#pins + 1] = tag .. ":" .. section end
  table.sort(pins)
  return table.concat({
    Preset.PREFIX, "s=" .. store:get("scope"), "o=" .. store:get("sort"), "t=" .. table.concat(tabs, "/"),
    "n=" .. table.concat(names, ","), "p=" .. table.concat(pins, ","), "d=" .. store:get("direction"),
  }, "|")
end

local function fields(text)
  local out = {}
  for part in text:gmatch("[^|]+") do
    local key, value = part:match("^(%a)=(.*)$")
    if key then out[key] = value end
  end
  return out
end

function Preset.decode(text)
  if type(text) ~= "string" then return nil, "Paste a setup code first." end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if #text > MAX_LENGTH then return nil, "That code is too long." end
  if text:sub(1, #Preset.PREFIX + 1) ~= Preset.PREFIX .. "|" then return nil, "That is not a Bank Organizer setup code." end
  local f = fields(text)
  local tabs, count = {}, 0
  for list in ((f.t or "") .. "/"):gmatch("([^/]*)/") do
    local tags = {}
    for tag in list:gmatch("[^,]+") do if Tags.isValid(tag) then tags[#tags + 1] = tag end end
    tabs[tostring(count)] = tags
    count = count + 1
  end
  if count == 0 then return nil, "That code has no tabs in it." end
  local names = {}
  for d, name in (f.n or ""):gmatch("(%d+):([^,]*)") do names[d] = unescape(name):sub(1, 40) end
  local pins = {}
  for tag, section in (f.p or ""):gmatch("([%w%-]+):(%d+)") do
    local n = tonumber(section)
    if Tags.isValid(tag) and n <= 14 then pins[tag] = n end
  end
  return {
    scope = (f.s == "tabs" or f.s == "bank") and f.s or nil,
    direction = (f.d == "horizontal" or f.d == "vertical") and f.d or nil,
    sort = Sorting.isMode(f.o) and f.o or nil,
    layout = { count = count, tabs = tabs, names = names },
    pins = pins,
  }
end

function Preset.apply(store, preset)
  store.layout = Layout.new(store.preset, preset.layout)
  store.tabHomes = preset.pins or {}
  store.tabOrder = nil
  if preset.scope then store.settings.scope = preset.scope end
  if preset.sort then store.settings.sort = preset.sort end
  if preset.direction then store.settings.direction = preset.direction end
  store:save()
  return store.layout:last()
end

return Preset
