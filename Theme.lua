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

-- Read EllesmereUI's font and accent. Safe to call any time; does nothing without it.
function T:Refresh()
  local E = EllesmereUI
  if type(E) ~= "table" then return end
  if type(E.GetFontPath) == "function" then
    local ok, path = pcall(E.GetFontPath)
    if ok and type(path) == "string" and path ~= "" then T.font = path end
  end
  if type(E.ResolveProfileAccent) == "function" and type(E.GetActiveProfileData) == "function" then
    local ok, _, r, g, b = pcall(function() return E.ResolveProfileAccent(E.GetActiveProfileData()) end)
    if ok and r then T.accent = { r, g, b }; return end
  end
  local green = E.ELLESMERE_GREEN
  if type(green) == "table" and green.r then T.accent = { green.r, green.g, green.b } end
end

-- The accent as a colour code for text, for example "|cff0cd29d".
function T:AccentCode()
  local a = T.accent
  return ("|cff%02x%02x%02x"):format(a[1] * 255, a[2] * 255, a[3] * 255)
end

function T:Font(fs, size, color)
  fs:SetFont(T.font, size or 12, "")
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

  function f:SetValue(v) self.value = v; eb:SetText(("%g"):format(v or 0)) end
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

-- An amount of money typed as "1g 50s", "25s" or "75c". 0 shows as "off".
function T:MoneyBox(parent, onChange)
  local eb = editBox(parent, 100)
  local function show(v) eb:SetText((v or 0) > 0 and ns.MoneyPlain(v) or "off") end
  function eb:SetValue(v) self.value = v; show(v) end
  eb:SetScript("OnEscapePressed", function(self) show(self.value); self:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function(self)
    local text = self:GetText():lower()
    local v = (text == "off" or text == "") and 0 or ns.ParseMoney(text)
    if v and v ~= self.value then self.value = v; onChange(v) end
    show(self.value)
  end)
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
  local fs = T:Text(b, 13, T.dim)
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
function T:Check(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
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

ns:OnReady(function() T:Refresh() end)
ns:On("PLAYER_LOGIN", function() T:Refresh() end)
