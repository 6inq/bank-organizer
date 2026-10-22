-- Bank Organizer: small building blocks shared by the sidebar and windows.
--
-- Every view in this plugin is a PrettyUI SimpleView or Window, which lays
-- its children out top to bottom. These helpers add common patterns on top:
--   * text that wraps to fit, so nothing is cut off
--   * rows of buttons that wrap onto a new line instead of running past the
--     edge (PrettyUI places side-by-side buttons in one row however wide)
--   * tab bars and collapsible sections
--   * muted hint text under a control, explaining it in plain words
--   * keeping the scroll position when a view is rebuilt
--
-- Sizes follow how PrettyUI draws: text in the 15pt body font, buttons as
-- wide as their text plus 16 pixels (rounded up to 8), 8 pixels between
-- buttons, 14 pixels of padding each side, and a 18 pixel scroll bar.
-- Colours on returned components are set inside pcall(function() ... end)
-- because not every component accepts every property.

local Widgets = {}

-- The grey used for hint text and footers (0xRRGGBBAA).
Widgets.MUTED = 0xA0A0A0FF

-- Layout sizes in pixels (see the top of this file).
local PADDING, SCROLLBAR, BUTTON_GAP, BUTTON_TILE = 14, 18, 8, 8

-- Extra room taken by a window's own frame, used only when the view's width
-- cannot be read.
local WINDOW_EDGE = 16

-- Pixels per character, used only when the font cannot measure text.
local CHAR_WIDTH = 7

-- The longest label a dropdown entry may have, in characters. Longer labels
-- are shortened with "..." so they fit even the narrow sidebar.
Widgets.MAX_CHOICE = 34

-- Returns how wide text is in the body font, in pixels.
function Widgets.measure(text)
  local ok, width = pcall(function() return config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth(text, false) end)
  if ok and type(width) == "number" then return width end
  return #tostring(text or "") * CHAR_WIDTH
end

-- Returns how wide a simple button with this label is, in pixels: the text
-- plus 8 pixels each side, rounded up to a multiple of 8.
function Widgets.buttonWidth(label)
  return math.max(BUTTON_TILE * 3, math.ceil((Widgets.measure(label) + BUTTON_TILE * 2) / BUTTON_TILE) * BUTTON_TILE)
end

-- Returns the width, in pixels, that a row of content can use in a view.
--   view   the SimpleView or Window
--   width  the view's width, used when the view cannot report it
-- Room for a scroll bar is always kept, because one may appear as more
-- content is added.
function Widgets.room(view, width)
  local ok, contentWidth = pcall(function() return view.contentWidth end)
  if ok and type(contentWidth) == "number" and contentWidth > 0 then
    local scrollbarShown = false
    pcall(function() scrollbarShown = view.scrollbarVisible == true end)
    return contentWidth - PADDING * 2 - (scrollbarShown and 0 or SCROLLBAR)
  end
  return (width or 300) - PADDING * 2 - SCROLLBAR - WINDOW_EDGE
end

-- Shortens text to at most max characters, ending with "..." when cut.
function Widgets.fit(text, max)
  text = tostring(text or "")
  if #text <= max then return text end
  return text:sub(1, max - 3):gsub("%s+$", "") .. "..."
end

-- Adds text in the given colour and returns the component. No height is
-- given, so PrettyUI measures the text and wraps it onto as many lines as
-- it needs. The colour is applied in pcall: if the client refuses it, the
-- text still shows.
function Widgets.coloured(view, text, colour)
  local label = view:AddText({ text = text })
  if label and colour then pcall(function() label.rgba = colour end) end
  return label
end

-- Adds a muted (grey) hint, used under controls and in footers. It wraps.
function Widgets.muted(view, text)
  return Widgets.coloured(view, text, Widgets.MUTED)
end

-- Returns how far a view or window is scrolled down, in pixels (0 when it
-- cannot be read). Views are rebuilt from scratch after every change, so
-- this is read first and put back with Widgets.restoreScroll; otherwise the
-- view would jump back to the top on every click.
function Widgets.scrollOf(view)
  local ok, y = pcall(function() return view.scrollY end)
  if ok and type(y) == "number" then return y end
  return 0
end

-- Scrolls a freshly built view or window back to a saved position. Called
-- after all content is added, so the position is kept within the new
-- content. Does nothing for 0 or when the view cannot scroll.
function Widgets.restoreScroll(view, y)
  if not view or not y or y <= 0 then return end
  pcall(function() view:SetScrollPosition(y) end)
end

-- Adds a divider line. Wrapped in pcall because older PrettyUI versions
-- may not offer AddDivider; a missing divider is only cosmetic.
function Widgets.divider(view)
  pcall(function() view:AddDivider() end)
end

-- Adds buttons side by side on a new row, wrapping onto another row
-- whenever the next button would not fit.
--   view     the SimpleView or Window
--   buttons  list of { label, function }
--   width    the view's width (used when the view cannot report it)
--   used     optional: how much of the current row is already taken; when
--            given, the first button continues that row if it fits
function Widgets.buttonRow(view, buttons, width, used)
  local room = Widgets.room(view, width)
  for index, button in ipairs(buttons) do
    local size = Widgets.buttonWidth(button[1])
    local continuing = (index > 1 or used ~= nil) and (used or 0) > 0
    local inline = continuing and used + BUTTON_GAP + size <= room
    used = inline and (used + BUTTON_GAP + size) or size
    view:AddSimpleButton(button[1], button[2], { inline = inline })
  end
end

-- Adds a line of text followed by its buttons. The buttons sit on the same
-- line when everything fits; otherwise they go on the line below, so
-- neither the text nor a button is ever cut off.
--   buttons  list of { label, function }
--   width    the view's width (used when the view cannot report it)
function Widgets.textWithButtons(view, text, buttons, width)
  view:AddText(text)
  local room = Widgets.room(view, width)
  local textWidth = Widgets.measure(text) + 4
  local total = textWidth
  for _, button in ipairs(buttons) do total = total + BUTTON_GAP + Widgets.buttonWidth(button[1]) end
  Widgets.buttonRow(view, buttons, width, total <= room and textWidth or nil)
end

-- Adds buttons that act as page tabs, wrapping onto a new row whenever the
-- next button would not fit.
--   view      the SimpleView or Window
--   pages     list of page names
--   selected  the page currently shown
--   onPick    function(page) called when another page's button is pressed
--   width     the view's width (used when the view cannot report it)
-- The selected page's button is shown in square brackets, for example
-- "[General]", so players can see where they are.
function Widgets.tabBar(view, pages, selected, onPick, width)
  local buttons = {}
  for index, page in ipairs(pages) do
    buttons[index] = { Widgets.tabLabel(page, selected), function() if page ~= selected then onPick(page) end end }
  end
  Widgets.buttonRow(view, buttons, width)
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
function Widgets.setting(view, label, hint, control)
  view:AddText(label)
  control()
  if hint then Widgets.muted(view, hint) end
end

return Widgets
