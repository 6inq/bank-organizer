-- Bank Organizer: small building blocks shared by the sidebar and windows.
--
-- Every view in this plugin is a PrettyUI SimpleView or Window, which lays
-- its children out top to bottom. These helpers add common patterns on top:
--   * tab bars: a row of buttons that switch between pages
--   * collapsible sections: a header button that hides or shows its content
--   * muted hint text under a control, explaining it in plain words
--
-- Only PrettyUI calls this plugin already uses are made here (AddText,
-- AddTitle, AddSimpleButton, AddDivider). Colours on returned components
-- are set inside pcall(function() ... end) because not every component
-- accepts every property.

local Widgets = {}

-- The grey used for hint text and footers (0xRRGGBBAA).
Widgets.MUTED = 0xA0A0A0FF

-- Rough text width: about how many characters fit on one line of a view.
local CHARS_PER_LINE = 42

-- One line of text is about this many pixels tall.
local LINE_HEIGHT = 18

-- Returns a height that fits text in a view of the given width, so long
-- hints wrap instead of being cut off.
--   text   the text to fit
--   width  optional view width in pixels (default fits the sidebar)
function Widgets.heightFor(text, width)
  local perLine = width and math.max(20, math.floor(width / 7)) or CHARS_PER_LINE
  local lines = math.max(1, math.ceil(#(text or "") / perLine))
  return lines * LINE_HEIGHT + 4
end

-- Adds text in the given colour and returns the component. The colour is
-- applied in pcall: if the client refuses it, the text still shows.
function Widgets.coloured(view, text, colour, width)
  local label = view:AddText({ text = text, height = Widgets.heightFor(text, width) })
  if label and colour then pcall(function() label.rgba = colour end) end
  return label
end

-- Adds a muted (grey) hint line, used under controls and in footers.
function Widgets.muted(view, text, width)
  return Widgets.coloured(view, text, Widgets.MUTED, width)
end

-- Adds a divider line. Wrapped in pcall because older PrettyUI versions
-- may not offer AddDivider; a missing divider is only cosmetic.
function Widgets.divider(view)
  pcall(function() view:AddDivider() end)
end

-- Adds a row of buttons that act as page tabs.
--   view      the SimpleView or Window
--   pages     list of page names
--   selected  the page currently shown
--   onPick    function(page) called when another page's button is pressed
-- The selected page's button is shown in square brackets, for example
-- "[General]", so players can see where they are.
function Widgets.tabBar(view, pages, selected, onPick)
  for index, page in ipairs(pages) do
    local label = page == selected and ("[" .. page .. "]") or page
    view:AddSimpleButton(label, function() if page ~= selected then onPick(page) end end, { inline = index > 1 })
  end
end

-- Returns the label a tab bar uses for a page, for tests and lookups.
function Widgets.tabLabel(page, selected)
  return page == selected and ("[" .. page .. "]") or page
end

-- Adds a collapsible section.
--   view      the SimpleView or Window
--   state     a table remembering which sections are closed (key -> true)
--   key       this section's key in state
--   title     the header text
--   refresh   function() that redraws the view after a toggle
--   build     function() that adds the section's content when open
-- The header is a button reading "[-] Title" when open and "[+] Title" when
-- closed. Sections start open.
function Widgets.section(view, state, key, title, refresh, build)
  local closed = state[key] == true
  view:AddSimpleButton((closed and "[+] " or "[-] ") .. title, function()
    state[key] = not closed or nil
    refresh()
  end)
  if not closed then build() end
end

-- Adds a setting's label, its control, and a muted hint below.
--   view     the view
--   label    the setting's name
--   hint     a plain-words explanation (may be nil)
--   control  function() that adds the control itself
--   width    optional view width, for wrapping the hint
function Widgets.setting(view, label, hint, control, width)
  view:AddText(label)
  control()
  if hint then Widgets.muted(view, hint, width) end
end

return Widgets
