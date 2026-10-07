local _, ns = ...

---------------------------------------------------------------------------
-- The look: dark, flat panels with an accent colour, matching EllesmereUI.
-- When EllesmereUI is installed, its font and the player's accent colour are used;
-- otherwise the same values are built in.
---------------------------------------------------------------------------
local T = {
  accent = { 12 / 255, 210 / 255, 157 / 255 },
  bg = { 0.067, 0.067, 0.067, 0.97 },
  header = { 0.09, 0.09, 0.09, 1 },
  border = { 1, 1, 1, 0.08 },
  button = { 0.061, 0.095, 0.120, 0.6 },
  buttonHover = 0.9,
  text = { 1, 1, 1, 1 },
  dim = { 1, 1, 1, 0.53 },
  section = { 1, 1, 1, 0.41 },
  font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
}
ns.Theme = T

---------------------------------------------------------------------------
-- Themes (owner, October 4: "implement all three" from the mockup). Settings,
-- Appearance picks one per profile (settings.theme) and an accent colour
-- (settings.accent: "" = EllesmereUI's when installed, else the theme's own; or a hex
-- colour like "0cd29d"). Applied once at load (Core.lua calls T:Apply), before any of
-- our frames exist, so every frame is drawn in it; changing it asks for a reload.
-- All three keep EllesmereUI's flat dark base so they sit well next to it:
--   clean    flat and soft: neutral greys (not EllesmereUI's blue-grey), thin
--            borders, tick boxes, the accent for headings
--   default  warm browns, a bronze line along the top, gold titles, small-caps gold
--            headings, sections as cards, rounded switches, a tinted footer
--   gilded   plus a bronze frame, bronze-edged buttons and lines, titles and headings
--            in WoW's Friz Quadrata in gold with a gold rule under headings
-- Second pass after the owner's screenshots (October 4): the first was too close to
-- EllesmereUI; these follow the mockup more closely.
---------------------------------------------------------------------------
local GOLD = { 0.91, 0.76, 0.48 }
local BRONZE = { 0.61, 0.42, 0.21 }
local TEAL = { 12 / 255, 210 / 255, 157 / 255 }

T.THEMES = {
  clean = { name = "FL Clean", accent = TEAL,
    bg = { 0.071, 0.071, 0.071, 0.97 }, header = { 0.09, 0.09, 0.09, 1 },
    button = { 0.105, 0.105, 0.105, 0.95 }, border = { 1, 1, 1, 0.10 },
    material = { tint = { 1, 1, 1 }, body = 0.025, header = 0.10 },
    rim = { color = { 0.72, 0.75, 0.77 }, outer = 0.50, inner = 0.12 } },
  default = { name = "FL Default", accent = TEAL,
    bg = { 0.071, 0.065, 0.059, 0.97 }, header = { 0.094, 0.082, 0.071, 1 },
    button = { 0.118, 0.106, 0.094, 0.95 }, border = { 1, 0.92, 0.80, 0.10 },
    font = "Fonts\\ARIALN.TTF", fontAdd = 1, labelAdd = 1, dimAlpha = 0.5,
    -- (no bronze line along the top: it didn't match the rest; owner, October 4)
    underLine = true, title = GOLD, heading = GOLD, cards = true, toggles = true, footer = true,
    material = { tint = { 1, 0.92, 0.80 }, body = 0.12, header = 0.40 },
    rim = { color = BRONZE, outer = 0.60, inner = 0.16 } },
  gilded = { name = "FL Gilded", accent = TEAL,
    bg = { 0.078, 0.069, 0.059, 0.97 }, header = { 0.118, 0.094, 0.071, 1 },
    button = { 0.125, 0.106, 0.086, 0.95 }, border = { BRONZE[1], BRONZE[2], BRONZE[3], 0.55 },
    font = "Fonts\\FRIZQT__.TTF", dimAlpha = 0.5,
    frame = BRONZE, topLine = BRONZE, title = GOLD, heading = GOLD, serif = true,
    cards = true, cardEdge = BRONZE, toggles = true, footer = true,
    material = { tint = { 1, 0.92, 0.80 }, body = 0.09, header = 0.32 },
    rim = { color = GOLD, outer = 0.72, inner = 0.20 }, corner = 32 },
}
T.THEME_ORDER = { "clean", "default", "gilded" }
T.SERIF = "Fonts\\FRIZQT__.TTF"   -- WoW's own Friz Quadrata (Morpheus read oddly at heading size)
T.theme = T.THEMES.default

-- "0cd29d" -> { r, g, b } (nil if it isn't a colour).
function T:FromHex(hex)
  if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then return end
  return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end
function T:ToHex(c) return ("%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end

-- EllesmereUI's accent, if it's installed.
local function euiAccent()
  local E = EllesmereUI
  if type(E) ~= "table" then return end
  if type(E.ResolveProfileAccent) == "function" and type(E.GetActiveProfileData) == "function" then
    local ok, _, r, g, b = pcall(function() return E.ResolveProfileAccent(E.GetActiveProfileData()) end)
    if ok and r then return { r, g, b } end
  end
  local green = E.ELLESMERE_GREEN
  if type(green) == "table" and green.r then return { green.r, green.g, green.b } end
end

-- The theme and accent this character's settings ask for (Core.lua, at load).
function T:Apply()
  local s = ns.db and ns.db.settings
  local key = s and s.theme
  T.themeKey = T.THEMES[key or ""] and key or "default"
  T.theme = T.THEMES[T.themeKey]
  T.bg, T.header = T.theme.bg, T.theme.header
  T.button, T.border = T.theme.button or T.button, T.theme.border or T.border
  -- Fonts (owner, October 4): Clean keeps EllesmereUI's; Default uses Arial Narrow and
  -- Gilded Friz Quadrata, plain (a thickened version was tried and dropped).
  T.fontAdd = T.theme.fontAdd or 0
  if T.theme.font then T.font = T.theme.font end
  -- Grey text (descriptions, hints) a little dimmer on Default and Gilded, so the names
  -- above it stand out (owner's test, October 4).
  T.dim = { 1, 1, 1, T.theme.dimAlpha or 0.53 }
  T.accent = T:FromHex(s and s.accent) or euiAccent() or T.theme.accent
end

-- Read EllesmereUI's font, and its accent unless one was picked. Safe to call any time;
-- does nothing without it.
function T:Refresh()
  local E = EllesmereUI
  if type(E) ~= "table" then return end
  if type(E.GetFontPath) == "function" and not T.theme.font then
    local ok, path = pcall(E.GetFontPath)
    if ok and type(path) == "string" and path ~= "" then T.font = path end
  end
  local picked = ns.db and T:FromHex(ns.db.settings.accent)
  if not picked then T.accent = euiAccent() or T.accent end
end

-- Whether the look on screen differs from the settings (a reload shows it).
function T:NeedsReload()
  local s = ns.db and ns.db.settings
  if not s then return false end
  local want = T.THEMES[s.theme or ""] and s.theme or "default"
  local accent = T:FromHex(s.accent) or euiAccent() or T.THEMES[want].accent
  return want ~= T.themeKey or T:ToHex(accent) ~= T:ToHex(T.accent)
end

-- Colour code for window titles: gold on themes with gold titles, else white.
function T:TitleCode()
  local c = T.theme.title or T.text
  return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- A page or window title: gold (and serif on Gilded) where the theme has them.
function T:StyleTitle(fs, size)
  local t = T.theme
  fs:SetFont((t.serif and T.SERIF) or T.font, (size or 16) + (t.serif and 2 or (T.fontAdd or 0) * 2), "")
  local c = t.title or T.text
  fs:SetTextColor(c[1], c[2], c[3], 1)
end

-- A small heading: accent small caps (Clean), gold small caps (Default), gold serif
-- (Gilded). Pass the plain text; returns what to show.
function T:StyleHeading(fs, text)
  local t = T.theme
  local c = t.heading or T.accent
  if t.serif then
    fs:SetFont(T.SERIF, 13, "")
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetText(text)
  else
    fs:SetFont(T.font, 11 + (T.fontAdd or 0), "")
    fs:SetTextColor(c[1], c[2], c[3], 0.9)
    fs:SetText(text:upper())
  end
end

-- A section as a card (Default and Gilded): a faint panel with an edge.
function T:Card(frame)
  if not T.theme.cards then return end
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, 0.025)
  T:Border(frame, T.theme.cardEdge and { T.theme.cardEdge[1], T.theme.cardEdge[2], T.theme.cardEdge[3], 0.45 } or { 1, 1, 1, 0.07 })
end

-- Cards drawn as textures on a page itself (a frame on top would cover its text): the
-- i-th card from top to bottom (pixels down from the page's top) across width. Default
-- and Gilded; nothing on Clean. Settings groups and Help topics.
local function cardTextures(page, i)
  page.cards = page.cards or {}
  local c = page.cards[i]
  if not c then
    local e = T.theme.cardEdge and { T.theme.cardEdge[1], T.theme.cardEdge[2], T.theme.cardEdge[3], 0.45 } or { 1, 1, 1, 0.07 }
    c = { bg = page:CreateTexture(nil, "BACKGROUND", nil, -8) }
    c.bg:SetColorTexture(1, 1, 1, 0.025)
    for k = 1, 4 do
      c[k] = page:CreateTexture(nil, "BORDER")
      c[k]:SetColorTexture(e[1], e[2], e[3], e[4])
    end
    page.cards[i] = c
  end
  return c
end

-- left: pixels from the page's left edge (2 by default); always: draw it on Clean too
-- (the Dashboard's tiles need their edges on every theme).
function T:PlaceCard(page, i, top, bottom, width, left, always)
  if not (T.theme.cards or always) then return end
  local c = cardTextures(page, i)
  local x = left or 2
  local h, w = bottom - top, width - 4
  c.bg:ClearAllPoints(); c.bg:SetPoint("TOPLEFT", page, "TOPLEFT", x, -top); c.bg:SetSize(w, h)
  c[1]:ClearAllPoints(); c[1]:SetPoint("TOPLEFT", page, "TOPLEFT", x, -top); c[1]:SetSize(w, 1)
  c[2]:ClearAllPoints(); c[2]:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(bottom - 1)); c[2]:SetSize(w, 1)
  c[3]:ClearAllPoints(); c[3]:SetPoint("TOPLEFT", page, "TOPLEFT", x, -top); c[3]:SetSize(1, h)
  c[4]:ClearAllPoints(); c[4]:SetPoint("TOPLEFT", page, "TOPLEFT", x + w - 1, -top); c[4]:SetSize(1, h)
  c.bg:Show(); for k = 1, 4 do c[k]:Show() end
end

-- Hides a page's cards from the from-th on.
function T:HideCards(page, from)
  for i = from or 1, #(page.cards or {}) do
    local c = page.cards[i]
    c.bg:Hide(); for k = 1, 4 do c[k]:Hide() end
  end
end

-- Original neutral artwork: materials keep their quiet theme tint while active
-- controls keep the player's accent. Static regions only; no events or timers.
local THEME_MEDIA = "Interface\\AddOns\\ForeverLedger\\media\\themes\\"
local function materialTexture(parent, tint, alpha)
  local tex = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
  tex:SetAllPoints()
  tex:SetTexture(THEME_MEDIA .. "ledger-grain.tga")
  tex:SetVertexColor(tint[1], tint[2], tint[3], alpha)
  return tex
end

function T:WindowMaterial(f, bar)
  local t = T.theme
  if not t.material or f.ledgerMaterial then return end
  local m = t.material
  f.ledgerMaterial = materialTexture(f, m.tint, m.body)
  if bar then f.ledgerHeaderMaterial = materialTexture(bar, m.tint, m.header) end
  -- Fine double edges catch the light like the concept's book-cover frame.
  -- Keep widget borders unchanged: this treatment belongs to window frames only.
  if t.rim then
    f.ledgerRim = {}
    local c = t.rim.color
    local function edge(p1, p2, inset, horizontal, alpha)
      local tex = f:CreateTexture(nil, "BORDER", nil, 1)
      tex:SetColorTexture(c[1], c[2], c[3], alpha)
      local function anchor(point)
        local x = point:find("LEFT") and inset or -inset
        local y = point:find("TOP") and -inset or inset
        tex:SetPoint(point, f, point, x, y)
      end
      anchor(p1); anchor(p2)
      if horizontal then tex:SetHeight(1) else tex:SetWidth(1) end
      f.ledgerRim[#f.ledgerRim + 1] = tex
    end
    for inset = 0, 2, 2 do
      local a = inset == 0 and t.rim.outer or t.rim.inner
      edge("TOPLEFT", "TOPRIGHT", inset, true, a)
      edge("BOTTOMLEFT", "BOTTOMRIGHT", inset, true, a * 0.65)
      edge("TOPLEFT", "BOTTOMLEFT", inset, false, a)
      edge("TOPRIGHT", "BOTTOMRIGHT", inset, false, a * 0.65)
    end
  end
  if not t.corner then return end
  -- Fine mirrored open filigree, inside the existing edge. Texture regions
  -- cannot take mouse input; buttons and title text remain above them.
  f.ledgerCorners = {}
  local corners = {
    { "TOPLEFT", 1, -1, 0, 1, 0, 1 }, { "TOPRIGHT", -1, -1, 1, 0, 0, 1 },
    { "BOTTOMLEFT", 1, 1, 0, 1, 1, 0 }, { "BOTTOMRIGHT", -1, 1, 1, 0, 1, 0 },
  }
  local c = t.rim and t.rim.color or t.frame or T.border
  for i, v in ipairs(corners) do
    local tex = f:CreateTexture(nil, "BORDER", nil, 3)
    tex:SetTexture(THEME_MEDIA .. "ledger-filigree.tga")
    tex:SetSize(t.corner, t.corner)
    tex:SetPoint(v[1], f, v[1], v[2], v[3])
    tex:SetTexCoord(v[4], v[5], v[6], v[7])
    tex:SetVertexColor(c[1], c[2], c[3], 0.90)
    f.ledgerCorners[i] = tex
  end
end

-- The theme's dressing on a window: the bronze line along the top, a line under the
-- title bar, the bronze frame, a tinted footer below footerY (pixels from the bottom;
-- optional).
function T:DecorateWindow(f, footerY, bar)
  local t = T.theme
  T:WindowMaterial(f, bar)
  -- Under the title bar: a faint accent line (Default) or bronze (Gilded).
  if bar and (t.topLine or t.underLine) then
    local under = bar:CreateTexture(nil, "BORDER")
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
    local c = t.frame or T.accent
    under:SetColorTexture(c[1], c[2], c[3], t.frame and 0.75 or 0.55)
  end
  if t.frame then
    for _, e in ipairs(f.borders or {}) do e:SetColorTexture(t.frame[1], t.frame[2], t.frame[3], 0.9) end
    local inner = CreateFrame("Frame", nil, f)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    T:Border(inner, { t.frame[1], t.frame[2], t.frame[3], 0.5 })
  end
  if t.topLine then
    local line = f:CreateTexture(nil, "OVERLAY")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(2)
    line:SetColorTexture(t.topLine[1], t.topLine[2], t.topLine[3], 1)
  end
  if t.footer and footerY then
    local foot = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(footerY - 1)
    foot:SetColorTexture(0, 0, 0, 0.22)
    local line = f:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT", 1, footerY)
    line:SetPoint("BOTTOMRIGHT", -1, footerY)
    line:SetHeight(1)
    local c = t.frame or T.accent
    line:SetColorTexture(c[1], c[2], c[3], t.frame and 0.6 or 0.3)
  end
end

-- The accent as a colour code for text, for example "|cff0cd29d".
function T:AccentCode()
  local a = T.accent
  return ("|cff%02x%02x%02x"):format(a[1] * 255, a[2] * 255, a[3] * 255)
end

function T:Font(fs, size, color)
  local body = color == T.dim and T.theme.bodyFont
  fs:SetFont(body or T.font, (size or 12) + (body and (T.theme.bodyAdd or 0) or (T.fontAdd or 0)), "")
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetShadowOffset(1, -1)
  local c = color or T.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  return fs
end

function T:Text(parent, size, color, layer)
  return T:Font(parent:CreateFontString(nil, layer or "OVERLAY"), size, color)
end

function T:Fill(frame, color, layer)
  local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
  tex:SetAllPoints()
  tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  return tex
end

-- A 1-pixel border inside the frame's edges.
function T:Border(frame, color)
  local c = color or T.border
  local function edge(p1, p2, w, h)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    t:SetPoint(p1)
    t:SetPoint(p2)
    if w then t:SetWidth(w) else t:SetHeight(h) end
    return t
  end
  frame.borders = {
    edge("TOPLEFT", "TOPRIGHT", nil, 1), edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1),
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil), edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil),
  }
end

-- How a flat button looks: normal, hovered, or selected (a chosen option).
local function buttonLook(b, hover)
  local c, a = T.button, T.accent
  local borderAlpha
  if b.primary and not b.selected and not hover then
    -- The main action (Full scan): accent edge and a faint accent tint, like the mockup.
    b.bg:SetColorTexture(a[1] * 0.25 + c[1] * 0.75, a[2] * 0.25 + c[2] * 0.75, a[3] * 0.25 + c[3] * 0.75, 0.95)
    for _, e in ipairs(b.borders) do e:SetColorTexture(a[1], a[2], a[3], 0.75) end
    return
  end
  if b.selected then
    b.bg:SetColorTexture(a[1] * 0.3, a[2] * 0.3, a[3] * 0.3, 0.95)
    borderAlpha = 1
  elseif hover then
    b.bg:SetColorTexture(c[1] * 1.6, c[2] * 1.6, c[3] * 1.6, T.buttonHover)
    borderAlpha = 0.6
  else
    b.bg:SetColorTexture(c[1], c[2], c[3], c[4])
  end
  for _, e in ipairs(b.borders) do
    if borderAlpha then e:SetColorTexture(a[1], a[2], a[3], borderAlpha)
    else e:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4]) end
  end
end

-- A flat button. Supports SetText and SetEnabled like Blizzard's, plus SetSelected.
-- name: a global name, only for buttons a key binding clicks (the buy queue's Buy).
function T:Button(parent, label, width, onClick, height, name)
  local b = CreateFrame("Button", name, parent)
  b:SetSize(width, height or 24)
  b.bg = T:Fill(b, T.button)
  T:Border(b)
  local fs = T:Text(b, 12)
  fs:SetPoint("CENTER")
  b:SetFontString(fs)
  b:SetText(label)
  function b:SetSelected(on) self.selected = on; buttonLook(self, false) end
  -- The main action on a screen: accent edge and tint.
  function b:SetPrimary(on) self.primary = on; buttonLook(self, false) end
  b:SetScript("OnEnter", function(self) if self:IsEnabled() then buttonLook(self, true) end end)
  b:SetScript("OnLeave", function(self) buttonLook(self, false) end)
  b:SetScript("OnDisable", function(self) self:GetFontString():SetAlpha(0.35) end)
  b:SetScript("OnEnable", function(self) self:GetFontString():SetAlpha(1) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A text box in the same style.
local function editBox(parent, width, justify)
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetSize(width, 22)
  T:Fill(eb, T.button)
  T:Border(eb)
  eb:SetFont(T.font, 12, "")
  eb:SetTextColor(1, 1, 1, 1)
  eb:SetJustifyH(justify or "CENTER")
  eb:SetTextInsets(6, 6, 0, 0)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return eb
end

function T:EditBox(parent, width, justify) return editBox(parent, width, justify) end

-- A number with - and + buttons. opts: min, max, step, suffix.
-- SetValue shows a value; onChange(value) runs when the player changes it.
function T:Number(parent, opts, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(150, 22)
  local minus = T:Button(f, "-", 22, nil, 22)
  minus:SetPoint("LEFT")
  local eb = editBox(f, 54)
  eb:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  local plus = T:Button(f, "+", 22, nil, 22)
  plus:SetPoint("LEFT", eb, "RIGHT", 4, 0)
  local suffix = T:Text(f, 12, T.dim)
  suffix:SetPoint("LEFT", plus, "RIGHT", 6, 0)
  suffix:SetText(opts.suffix or "")
  -- As wide as it really is, suffix included (Settings lines controls up on the right).
  f:SetWidth(110 + ((opts.suffix or "") ~= "" and (suffix:GetStringWidth() + 6) or 0))

  function f:SetValue(v) self.value = v; eb:SetText(("%g"):format(v or 0)) end
  function f:IsEditing() return eb:HasFocus() end
  local function set(v)
    v = tonumber(v)
    if v then
      v = math.max(opts.min or -math.huge, math.min(opts.max or math.huge, v))
      if v ~= f.value then f:SetValue(v); onChange(v); return end
    end
    f:SetValue(f.value)
  end
  minus:SetScript("OnClick", function() set((f.value or 0) - (opts.step or 1)) end)
  plus:SetScript("OnClick", function() set((f.value or 0) + (opts.step or 1)) end)
  eb:SetScript("OnEscapePressed", function(self) f:SetValue(f.value); self:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function(self) set(self:GetText()) end)
  return f
end

-- A slider: a thin track, a knob in the accent colour, and the value beside it.
-- opts: min, max, step, suffix. SetValue shows a value; onChange(value) runs when the
-- player lets go (not while dragging: the Size slider rescales the window it's in).
function T:Slider(parent, opts, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(200, 22)
  local s = CreateFrame("Slider", nil, f)
  s:SetPoint("LEFT", 0, 0)
  s:SetSize(150, 14)
  s:SetOrientation("HORIZONTAL")
  s:SetMinMaxValues(opts.min or 0, opts.max or 100)
  s:SetValueStep(opts.step or 1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", 0, 0)
  track:SetPoint("RIGHT", 0, 0)
  track:SetHeight(4)
  track:SetColorTexture(1, 1, 1, 0.15)
  local thumb = s:CreateTexture(nil, "ARTWORK")
  thumb:SetSize(10, 14)
  thumb:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
  s:SetThumbTexture(thumb)
  local text = T:Text(f, 12)
  text:SetPoint("LEFT", s, "RIGHT", 10, 0)
  local function show(v) text:SetText(("%d%s"):format(v, opts.suffix or "")) end
  local quiet = false
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / (opts.step or 1) + 0.5) * (opts.step or 1)
    show(v)
  end)
  s:SetScript("OnMouseUp", function(self)
    local v = math.floor(self:GetValue() / (opts.step or 1) + 0.5) * (opts.step or 1)
    if not quiet and v ~= f.value then f.value = v; onChange(v) end
  end)
  function f:SetValue(v)
    self.value = v
    quiet = true
    s:SetValue(v or opts.min or 0)
    quiet = false
    show(v or opts.min or 0)
  end
  return f
end

-- While typing a price, a small tip shows what it will be saved as ("= 2g 50s").
function T:MoneyPreview(eb, plainUnit)
  eb:HookScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local v = ns.ParseMoneyLoose(self:GetText(), plainUnit)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if v == -1 then
      GameTooltip:AddLine("= any price", 1, 1, 1)
    elseif v then
      GameTooltip:AddLine("= " .. (v > 0 and ns.Money(v) or "off"), 1, 1, 1)
    else
      GameTooltip:AddLine("Not a price yet", 1, 0.5, 0.5)
    end
    GameTooltip:AddLine(("Enter saves. Examples: 2g 50s 25c, 2 50 25 or 2.50.25 (gold silver copper), 2 50 (gold silver), 25s, 75c%s%s."):format(
      plainUnit == "g" and ", or 3 for 3g" or "", self.allowAny and ", any" or ""), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  eb:HookScript("OnEditFocusLost", function() GameTooltip:Hide() end)
end

-- An amount of money. Type it any way ("2g 50s", "1.5g", "25s", a plain number in
-- plainUnit); it's tidied up when you press Enter or click away. 0 shows as "off".
-- allowAny: "any" is accepted (-1), for shopping lists.
-- offText: what 0 shows as ("off" unless given, e.g. "no limit").
-- eb.compact = true: a narrow box shows a short form while you're not typing in it
-- ("12g 40s", "123g"); clicking in shows the exact amount to edit, and hovering shows
-- it too (owner's test, October 3: big prices ran out of the shopping list's box).
-- The whole amount without spaces ("9999g99s99c", "1s48c"); the box shrinks its text to
-- fit (owner, October 6: "can we just make the text smaller when there are more numbers?").
local function shortPrice(c)
  local g, s, cp = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
  local out = ""
  if g > 0 then out = out .. g .. "g" end
  if s > 0 then out = out .. s .. "s" end
  if cp > 0 or out == "" then out = out .. cp .. "c" end
  return out
end
function T:MoneyBox(parent, onChange, plainUnit, allowAny, offText)
  local eb = editBox(parent, 100)
  eb.allowAny = allowAny
  -- A narrow box: smaller text when the amount is long, down to 7, so all of it shows.
  local measure = eb.CreateFontString and eb:CreateFontString(nil, "OVERLAY")
  if measure then measure:Hide() end
  -- Sets the box's text at the largest size (down to 7) where it fits. Still too wide
  -- (owner's AH9, October 6: "9999g99s99c" at 7 only showed its end), the next shorter
  -- form is tried: copper dropped, then silver (hovering shows the exact amount). The
  -- font is set before the text, and the cursor put at the start, so the start shows.
  local function fit(texts)
    local font, size, flags = eb:GetFont()
    if not eb.compact or not measure or not font or not size then eb:SetText(texts[1]); return end
    eb.baseSize = eb.baseSize or size
    local room = (eb:GetWidth() or 0) - 12
    local pick, pickSize = texts[#texts], 7
    for _, text in ipairs(texts) do
      size = eb.baseSize
      measure:SetFont(font, size, flags)
      measure:SetText(text)
      while room > 0 and measure:GetStringWidth() > room and size > 7 do
        size = size - 1
        measure:SetFont(font, size, flags)
      end
      if room <= 0 or measure:GetStringWidth() <= room then pick, pickSize = text, size; break end
    end
    eb:SetFont(font, pickSize, flags)
    eb:SetText(pick)
    if eb.SetCursorPosition and not eb:HasFocus() then eb:SetCursorPosition(0) end
  end
  local function show(v, exact)
    v = v or 0
    if v > 0 and eb.compact and not exact then
      local g, s = math.floor(v / 10000), math.floor(v % 10000 / 100)
      local texts = { shortPrice(v) }
      if v % 100 > 0 and v >= 100 then texts[#texts + 1] = shortPrice(v - v % 100) end
      if s > 0 and g > 0 then texts[#texts + 1] = shortPrice(g * 10000) end
      fit(texts)
    else
      fit({ (v < 0 and "any") or (v > 0 and ns.MoneyPlain(v)) or offText or "off" })
    end
  end
  function eb:SetValue(v) self.value = v; show(v, self:HasFocus()) end
  eb:HookScript("OnTextChanged", function(self, userInput)
    if userInput then self.priceEdited = true end
  end)
  eb:SetScript("OnEscapePressed", function(self) self.priceEdited = nil; show(self.value); self:ClearFocus() end)
  -- Clicking in shows the exact amount and selects it, so typing replaces it.
  eb:SetScript("OnEditFocusGained", function(self)
    if self.compact then show(self.value, true) end
    self:HighlightText()
  end)
  eb:HookScript("OnEnter", function(self)
    local v = self.value or 0
    if self.compact and v > 0 and not self:HasFocus() and shortPrice(v) ~= ns.MoneyPlain(v) then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(ns.Money(v), 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  eb:HookScript("OnLeave", function() GameTooltip:Hide() end)
  eb:SetScript("OnEditFocusLost", function(self)
    local v = ns.ParseMoneyLoose(self:GetText(), plainUnit)
    if v == -1 and not allowAny then v = nil end
    if not v then
      ns:Print(("Couldn't read that price. Try 2g 50s 25c, 2 50 25, 2.50.25, 25s or 75c%s."):format(allowAny and ", or any" or ""))
    elseif v ~= self.value or (self.confirmSame and self.priceEdited) then
      self.value = v
      onChange(v)
    end
    self.priceEdited = nil
    show(self.value)
  end)
  T:MoneyPreview(eb, plainUnit)
  return eb
end

-- A row of buttons, one of which is chosen. options: { { value, label }, ... }.
function T:Choice(parent, options, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f.buttons = {}
  local x = 0
  for _, o in ipairs(options) do
    local b = T:Button(f, o.label, 10, function() f:SetValue(o.value); onChange(o.value) end, 22)
    b:SetWidth(b:GetFontString():GetStringWidth() + 20)
    b:SetPoint("LEFT", x, 0)
    b.value = o.value
    x = x + b:GetWidth() + 4
    f.buttons[#f.buttons + 1] = b
  end
  f:SetSize(x, 22)
  function f:SetValue(v)
    for _, b in ipairs(self.buttons) do b:SetSelected(b.value == v) end
  end
  return f
end

-- A tab: plain text, with an accent underline when selected.
function T:Tab(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  local fs = T:Text(b, 12, T.dim)   -- (12, lighter, like the mockup)
  fs:SetPoint("CENTER")
  b:SetFontString(fs)
  b:SetText(label)
  b:SetSize(fs:GetStringWidth() + 20, 28)   -- 20, not 24: ten main tabs must fit the smallest window
  b.line = b:CreateTexture(nil, "OVERLAY")
  b.line:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
  b.line:SetPoint("BOTTOMLEFT", 8, 0)
  b.line:SetPoint("BOTTOMRIGHT", -8, 0)
  b.line:SetHeight(2)
  b.line:Hide()
  function b:SetSelected(on)
    self.selected = on
    self.line:SetShown(on)
    local col = on and T.text or T.dim
    self:GetFontString():SetTextColor(col[1], col[2], col[3], col[4] or 1)
  end
  b:SetScript("OnEnter", function(self) if not self.selected then self:GetFontString():SetTextColor(1, 1, 1, 0.85) end end)
  b:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A small square checkbox with a label. GetChecked/SetChecked like Blizzard's.
-- style "switch", on themes with toggles (Default, Gilded): a small switch instead, a
-- track in the accent when on, grey when off, with a knob that moves across. Same API
-- either way. Only roomy places ask for it (Settings); grids keep the tick box.
function T:Check(parent, onClick, style)
  local b = CreateFrame("Button", nil, parent)
  if T.theme.toggles and style == "switch" then
    -- A pill: a round cap at each end and a bar between, with a round knob (owner's
    -- test, October 4: the square blocks didn't look like the mockup). Rounded with the
    -- game's circle mask; square if masks aren't available.
    b:SetSize(28, 14)
    local round = b.CreateMaskTexture ~= nil
    local function circle(layer, size)
      local tex = b:CreateTexture(nil, layer)
      tex:SetSize(size, size)
      if round then
        local m = b:CreateMaskTexture()
        m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(tex)
        tex:AddMaskTexture(m)
      end
      return tex
    end
    b.capL = circle("BACKGROUND", 14)
    b.capL:SetPoint("LEFT")
    b.capR = circle("BACKGROUND", 14)
    b.capR:SetPoint("RIGHT")
    b.mid = b:CreateTexture(nil, "BACKGROUND")
    b.mid:SetPoint("TOPLEFT", 7, 0)
    b.mid:SetPoint("BOTTOMRIGHT", -7, 0)
    b.knob = circle("ARTWORK", 10)
    b.label = T:Text(b, 12)
    b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
    function b:SetChecked(on)
      self.checked = on and true or false
      local r, g, bl, a = 0.24, 0.23, 0.22, 1   -- (opaque: the pieces overlap)
      if self.checked then r, g, bl, a = T.accent[1], T.accent[2], T.accent[3], 1 end
      for _, part in ipairs({ self.capL, self.capR, self.mid }) do part:SetColorTexture(r, g, bl, a) end
      self.knob:SetColorTexture(1, 1, 1, self.checked and 1 or 0.75)
      self.knob:ClearAllPoints()
      self.knob:SetPoint(self.checked and "RIGHT" or "LEFT", self.checked and -2 or 2, 0)
    end
    function b:GetChecked() return self.checked end
    b:SetScript("OnClick", function(self) self:SetChecked(not self.checked); if onClick then onClick(self) end end)
    b:SetChecked(false)
    return b
  end
  b:SetSize(14, 14)
  T:Fill(b, T.button)
  T:Border(b, { 1, 1, 1, 0.25 })
  b.mark = b:CreateTexture(nil, "ARTWORK")
  b.mark:SetPoint("TOPLEFT", 3, -3)
  b.mark:SetPoint("BOTTOMRIGHT", -3, 3)
  b.mark:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
  b.label = T:Text(b, 12)
  b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
  function b:SetChecked(on) self.checked = on and true or false; self.mark:SetShown(self.checked) end
  function b:GetChecked() return self.checked end
  b:SetScript("OnClick", function(self) self:SetChecked(not self.checked); if onClick then onClick(self) end end)
  b:SetChecked(false)
  return b
end

-- A scroll area with a slim scroll bar and mouse wheel. Returns the scroll frame
-- and the content frame to put things in (set the content's height).
function T:Scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(10, 10)
  sf:SetScrollChild(content)
  sf:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w - 12) end)

  local track = CreateFrame("Frame", nil, sf)
  track:SetPoint("TOPRIGHT", 0, 0)
  track:SetPoint("BOTTOMRIGHT", 0, 0)
  track:SetWidth(4)
  T:Fill(track, { 1, 1, 1, 0.05 })
  local thumb = CreateFrame("Frame", nil, track)
  thumb:SetWidth(4)
  T:Fill(thumb, { T.accent[1], T.accent[2], T.accent[3], 0.7 })
  thumb:EnableMouse(true)

  local function update()
    local range = sf:GetVerticalScrollRange()
    local h = sf:GetHeight()
    if range <= 0 or h <= 0 then track:Hide(); sf:SetVerticalScroll(0); return end
    track:Show()
    local size = math.max(20, h * h / (h + range))
    thumb:SetHeight(size)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(h - size) * sf:GetVerticalScroll() / range)
  end
  local function scrollTo(v)
    sf:SetVerticalScroll(math.max(0, math.min(v, sf:GetVerticalScrollRange())))
    update()
  end
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta) scrollTo(self:GetVerticalScroll() - delta * 40) end)
  sf:SetScript("OnScrollRangeChanged", update)
  thumb:SetScript("OnMouseDown", function(self)
    local _, startY = GetCursorPosition()
    local start, scale = sf:GetVerticalScroll(), self:GetEffectiveScale()
    self:SetScript("OnUpdate", function()
      local _, y = GetCursorPosition()
      local h, range = sf:GetHeight(), sf:GetVerticalScrollRange()
      local travel = h - self:GetHeight()
      if travel > 0 then scrollTo(start + (startY - y) / scale * range / travel) end
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  sf.UpdateScrollBar = update
  return sf, content
end

-- A dropdown: a button showing the choice, and a list under it (scrolls past 12).
-- SetOptions({ { value, label }, ... }), SetValue(value); onChange(value) on a pick.
-- The list is drawn above everything (the shopping list menu showed buttons through it).
function T:Dropdown(parent, width, onChange)
  local d = T:Button(parent, "", width, nil, 22)
  d.options = {}
  d:GetFontString():ClearAllPoints()
  d:GetFontString():SetPoint("LEFT", 8, 0)
  d:GetFontString():SetPoint("RIGHT", -18, 0)
  d:GetFontString():SetJustifyH("LEFT")
  d:GetFontString():SetWordWrap(false)   -- (one line; a wide font wrapped it: Gilded, October 4)
  local arrow = T:Text(d, 11, T.dim)
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetText("v")
  -- On the screen, not inside the dropdown's parent: a dropdown low in a scroll area had
  -- its list cut off at the area's edge (owner's screenshot, October 5, Shuffles' list
  -- picker). Kept on screen, at the window's Size (scale set when opened).
  local menu = CreateFrame("Frame", nil, UIParent)
  menu:SetClampedToScreen(true)
  menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
  menu:SetWidth(width)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetToplevel(true)
  menu:EnableMouse(true)
  T:Fill(menu, { 0.05, 0.05, 0.05, 0.98 })
  T:Border(menu)
  menu.sf, menu.content = T:Scroll(menu)
  menu.sf:SetPoint("TOPLEFT", 2, -2)
  menu.sf:SetPoint("BOTTOMRIGHT", -2, 2)
  menu.rows = {}
  menu:Hide()
  d.menu = menu

  function d:SetValue(v)
    self.value = v
    for _, o in ipairs(self.options) do
      if o.value == v then self:SetText(o.label); return end
    end
    self:SetText(self.options[1] and self.options[1].label or "")
  end
  function d:SetOptions(opts) self.options = opts; self:SetValue(self.value) end

  -- The list follows the button's width (it can be narrowed to fit, Dashboard.lua).
  -- d.default: that option says "(default)" in the list (Settings, owner's test October 3).
  local measure = T:Text(menu, 12)   -- (hidden: sizes the list to its longest name)
  measure:Hide()
  local function fill()
    local top = 0
    -- At least the button's width, wider when a name needs it (owner's test, October 4:
    -- "Aukshaun Vondrizzle (Classic Beta PvP 2)" was cut off).
    local w = d:GetWidth()
    for _, o in ipairs(d.options) do
      measure:SetText(o.label .. ((d.default ~= nil and o.value == d.default) and " (default)" or ""))
      w = math.max(w, measure:GetStringWidth() + 32)
    end
    w = math.min(w, 420)
    menu:SetWidth(w)
    menu.content:SetWidth(w - 16)
    for i, o in ipairs(d.options) do
      local r = menu.rows[i]
      if not r then
        r = CreateFrame("Button", nil, menu.content)
        r:SetHeight(20)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
        r.text = T:Text(r, 12)
        r.text:SetPoint("LEFT", 6, 0)
        r.text:SetPoint("RIGHT", -6, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
          menu:Hide()
          d:SetValue(self.value)
          if onChange then onChange(self.value) end
        end)
        menu.rows[i] = r
      end
      r.value = o.value
      -- { heading = true, label = "" }: a gap (or a dim label) that can't be picked.
      r:EnableMouse(not o.heading)
      r:SetHeight(o.heading and o.label == "" and 8 or 20)
      r:SetPoint("TOPLEFT", 0, -(top or 0))
      top = (top or 0) + r:GetHeight()
      r:SetPoint("RIGHT", 0, 0)
      local label = o.label .. ((d.default ~= nil and o.value == d.default) and " |cff888888(default)|r" or "")
      r.text:SetText(o.value == d.value and (T:AccentCode() .. o.label .. "|r" .. label:sub(#o.label + 1)) or label)
      r:Show()
    end
    for i = #d.options + 1, #menu.rows do menu.rows[i]:Hide() end
    menu.content:SetHeight(math.max(top or 0, 20))
    menu:SetHeight(math.min(top or 0, 12 * 20) + 4)
    menu.sf.UpdateScrollBar()
  end
  d:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide(); return end
    menu:SetScale(d:GetEffectiveScale() / UIParent:GetEffectiveScale())
    fill()
    menu:SetFrameStrata("FULLSCREEN_DIALOG")   -- (a parent's layer change resets it)
    menu:Show()
    menu:Raise()
  end)
  d:HookScript("OnHide", function() menu:Hide() end)
  return d
end

-- A dropdown that picks several (owner, October 4: the Disenchant finder's item levels):
-- a tick per option, Select all and Deselect all on top. The list stays open while you
-- tick; a click anywhere else closes it. SetOptions({ { value, label }, ... });
-- SetSelected(set), a table of value = true, changed in place; onChange() after each change.
-- d.Summary(selected, options) gives the button's text. d.OnRowEnter(value), d.OnRowLeave():
-- hovering an option.
function T:MultiDropdown(parent, width, onChange)
  local d = T:Button(parent, "", width, nil, 22)
  d.options, d.selected = {}, {}
  local fs = d:GetFontString()
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", 8, 0)
  fs:SetPoint("RIGHT", -18, 0)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  local arrow = T:Text(d, 11, T.dim)
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetText("v")
  -- On the screen, not inside the dropdown's parent: a dropdown low in a scroll area had
  -- its list cut off at the area's edge (owner's screenshot, October 5, Shuffles' list
  -- picker). Kept on screen, at the window's Size (scale set when opened).
  local menu = CreateFrame("Frame", nil, UIParent)
  menu:SetClampedToScreen(true)
  menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
  menu:SetWidth(math.max(width, 190))
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetToplevel(true)
  menu:EnableMouse(true)
  T:Fill(menu, { 0.05, 0.05, 0.05, 0.98 })
  T:Border(menu)
  menu.rows = {}
  menu:Hide()
  menu:SetScript("OnHide", function() if d.OnRowLeave then d.OnRowLeave() end end)
  d.menu = menu

  function d:Refresh()
    self:SetText(self.Summary and self.Summary(self.selected, self.options) or "")
    for _, r in ipairs(menu.rows) do r.box:SetChecked(r.value ~= nil and self.selected[r.value]) end
  end
  function d:SetOptions(opts) self.options = opts; self:Refresh() end
  function d:SetSelected(set) self.selected = set; self:Refresh() end
  local function changed()
    d:Refresh()
    if onChange then onChange() end
  end

  local all = T:Button(menu, "Select all", 80, function()
    for _, o in ipairs(d.options) do d.selected[o.value] = true end
    changed()
  end, 20)
  all:SetPoint("TOPLEFT", 6, -6)
  local none = T:Button(menu, "Deselect all", 90, function()
    for k in pairs(d.selected) do d.selected[k] = nil end
    changed()
  end, 20)
  none:SetPoint("LEFT", all, "RIGHT", 4, 0)
  local line = menu:CreateTexture(nil, "BORDER")
  line:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 1, -31)
  line:SetPoint("TOPRIGHT", -1, -31)

  local function fill()
    local top = 34
    for i, o in ipairs(d.options) do
      local r = menu.rows[i]
      if not r then
        r = CreateFrame("Button", nil, menu)
        r:SetHeight(20)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
        r.box = T:Check(r)
        r.box:EnableMouse(false)   -- (the whole row ticks it)
        r.box:SetPoint("LEFT", 6, 0)
        r:SetScript("OnClick", function(self)
          d.selected[self.value] = (not d.selected[self.value]) or nil
          changed()
        end)
        r:SetScript("OnEnter", function(self) if d.OnRowEnter then d.OnRowEnter(self.value) end end)
        r:SetScript("OnLeave", function() if d.OnRowLeave then d.OnRowLeave() end end)
        menu.rows[i] = r
      end
      r.value = o.value
      r.box.label:SetText(o.label)
      r.box:SetChecked(d.selected[o.value])
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 2, -top)
      r:SetPoint("RIGHT", -2, 0)
      r:Show()
      top = top + 20
    end
    for i = #d.options + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetHeight(top + 4)
  end
  d:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide(); return end
    menu:SetScale(d:GetEffectiveScale() / UIParent:GetEffectiveScale())
    fill()
    menu:SetFrameStrata("FULLSCREEN_DIALOG")   -- (a parent's layer change resets it)
    menu:Show()
    menu:Raise()
  end)
  d:HookScript("OnHide", function() menu:Hide() end)
  ns:On("GLOBAL_MOUSE_DOWN", function()
    if menu:IsShown() and not (menu:IsMouseOver() or d:IsMouseOver()) then menu:Hide() end
  end)
  return d
end

ns:OnReady(function() T:Refresh() end)
ns:On("PLAYER_LOGIN", function() T:Refresh() end)
