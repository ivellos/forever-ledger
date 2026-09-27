local _, ns = ...
local T = ns.Theme

local CLASS_COLORS = RAID_CLASS_COLORS or {}

local KEY_ITEMS = {
  { 2589, "Linen Cloth" }, { 2592, "Wool Cloth" }, { 10940, "Strange Dust" },
  { 10938, "Lesser Magic Essence" }, { 10939, "Greater Magic Essence" },
  { 10998, "Lesser Astral Essence" }, { 11082, "Greater Astral Essence" }, { 10978, "Small Glimmering Shard" },
}

local function heading(text) return T:AccentCode() .. text .. "|r" end
local function dim(text) return "|cff888888" .. text .. "|r" end

local function classColored(c)
  local cc = CLASS_COLORS[c.class or ""]
  return cc and ("|c" .. (cc.colorStr or "ffffffff") .. (c.name or "?") .. "|r") or (c.name or "?")
end

local function sortedCharKeys()
  local keys = {}
  for k in pairs(ns.db.chars) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- Blizzard-style button, used on Blizzard's own auction house window.
local function blizzButton(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 24)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

-- A dark, flat window with a title bar you can drag and a close button.
local function themedWindow(name, w, h, titleText)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:Hide()
  tinsert(UISpecialFrames, name)
  T:Fill(f, T.bg)
  T:Border(f)

  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(30)
  T:Fill(bar, T.header)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  f.title = T:Text(bar, 14)
  f.title:SetPoint("LEFT", 12, 0)
  f.title:SetText(titleText)

  local close = CreateFrame("Button", nil, bar)
  close:SetSize(30, 30)
  close:SetPoint("RIGHT")
  local x = T:Text(close, 16, T.dim)
  x:SetPoint("CENTER")
  x:SetText("x")
  close:SetScript("OnEnter", function() x:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1) end)
  close:SetScript("OnLeave", function() x:SetTextColor(T.dim[1], T.dim[2], T.dim[3], T.dim[4]) end)
  close:SetScript("OnClick", function() f:Hide() end)
  f.bar = bar
  return f
end

-- A thin horizontal line.
local function rule(parent, anchor, y)
  local t = parent:CreateTexture(nil, "BORDER")
  t:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
  t:SetPoint("LEFT", parent, "LEFT", 1, 0)
  t:SetPoint("RIGHT", parent, "RIGHT", -1, 0)
  t:SetPoint("TOP", parent, anchor, 0, y)
  t:SetHeight(1)
  return t
end

---------------------------------------------------------------------------
-- Main window: title bar, tabs, a content area and a footer with buttons
---------------------------------------------------------------------------
local main
local setView, layoutShuffles, buildSettings

local TABS = {
  { key = "dashboard", label = "Dashboard" },
  { key = "shuffles", label = "Shuffles" },
  { key = "flips", label = "Vendor flips" },
  { key = "characters", label = "Characters" },
  { key = "settings", label = "Settings" },
}

-- A scroll area filling the content area, with one text block in it.
local function textArea()
  local sf, content = T:Scroll(main.body)
  sf:SetAllPoints()
  local text = T:Text(content, 12)
  text:SetPoint("TOPLEFT", 2, -2)
  text:SetPoint("RIGHT", content, "RIGHT", -4, 0)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetSpacing(4)
  sf.text, sf.content = text, content
  return sf
end

local function buildMain()
  if main then return main end
  main = themedWindow("ForeverLedgerFrame", 760, 520,
    T:AccentCode() .. "Forever Ledger|r  " .. dim(ns.VERSION))

  -- Tabs
  main.tabs = {}
  local prev
  for _, tab in ipairs(TABS) do
    local b = T:Tab(main, tab.label, function() setView(tab.key) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("TOPLEFT", 6, -32) end
    main.tabs[tab.key] = b
    prev = b
  end
  rule(main, "TOP", -61)

  -- Content area and footer
  main.body = CreateFrame("Frame", nil, main)
  main.body:SetPoint("TOPLEFT", 14, -72)
  main.body:SetPoint("BOTTOMRIGHT", -10, 52)
  rule(main, "BOTTOM", 46)

  main.views = {
    dashboard = textArea(),
    characters = textArea(),
  }
  main.views.settings = buildSettings()
  main.shuffleSF, main.shuffleContent = T:Scroll(main.body)
  main.shuffleSF:SetAllPoints()
  main.views.shuffles, main.views.flips = main.shuffleSF, main.shuffleSF

  -- Footer buttons. Scan buttons show on Dashboard and Characters.
  local full = T:Button(main, "Full scan", 140, function() ns.Scan:Start("full") end)
  full:SetPoint("BOTTOMLEFT", 12, 12)
  local scan = T:Button(main, "Scan materials", 120, function() ns.Scan:Start("watch") end)
  scan:SetPoint("LEFT", full, "RIGHT", 6, 0)
  local exp = T:Button(main, "Export", 70, function() ns:ShowExport() end)
  exp:SetPoint("LEFT", scan, "RIGHT", 18, 0)
  local imp = T:Button(main, "Import", 70, function() ns:ShowImport() end)
  imp:SetPoint("LEFT", exp, "RIGHT", 6, 0)
  local csv = T:Button(main, "Prices as text", 110, function() ns:ShowPricesCSV() end)
  csv:SetPoint("LEFT", imp, "RIGHT", 6, 0)
  main.scanBtn, main.fullBtn = scan, full
  main.footer = {
    dashboard = { full, scan },
    characters = { full, scan, exp, imp, csv },
  }

  main.refreshBtn = T:Button(main, "Refresh", 90, function() ns:RefreshShuffles() end)
  main.refreshBtn:SetPoint("BOTTOMLEFT", 12, 12)
  main.footer.shuffles = { main.refreshBtn }
  main.footer.flips = { main.refreshBtn }
  main.shuffleInfo = T:Text(main, 11, T.dim)
  main.shuffleInfo:SetPoint("LEFT", main.refreshBtn, "RIGHT", 12, 0)

  main.status = T:Text(main, 11, T.accent)
  main.status:SetPoint("BOTTOMRIGHT", -14, 18)

  setView("dashboard")
  return main
end

setView = function(view)
  main.view = view
  for key, tab in pairs(main.tabs) do tab:SetSelected(key == view) end
  local shown = main.views[view]
  for _, v in pairs(main.views) do v:SetShown(v == shown) end
  local wanted = {}
  for _, b in ipairs(main.footer[view] or {}) do wanted[b] = true end
  for _, list in pairs(main.footer) do
    for _, b in ipairs(list) do b:SetShown(wanted[b] or false) end
  end
  main.shuffleInfo:SetShown(view == "shuffles" or view == "flips")
  if view == "shuffles" or view == "flips" then
    if main.shuffles then layoutShuffles() else ns:RefreshShuffles() end
  else
    ns:RefreshUI()
  end
end

function ns:ToggleUI(view)
  local f = buildMain()
  if f:IsShown() and not view then f:Hide(); return end
  ns:ScanSkillLines()
  T:Refresh()
  f:Show()
  setView(view or f.view or "dashboard")
end

---------------------------------------------------------------------------
-- Text views: Dashboard (for now), Characters, Settings
---------------------------------------------------------------------------
local function dashboardText(add)
  add(heading("Dashboard"))
  add("A gold graph and sales, expenses and profit are coming here.")
  local since = ns:RecordingSince()
  add(dim(since and ("History has been recorded since " .. since .. ".") or "History starts recording now."))
  add("")

  add(heading("Gold"))
  local total = 0
  for _, key in ipairs(sortedCharKeys()) do
    local hours, latest, gold = ns.db.gold[key], nil, nil
    for h, g in pairs(hours or {}) do if not latest or h > latest then latest, gold = h, g end end
    if gold then
      total = total + gold
      add(("  %s: %s"):format(classColored(ns.db.chars[key]), ns.Money(gold)))
    end
  end
  add(("  All characters: %s"):format(ns.Money(total)))
  add("")

  add(heading("Today for " .. (UnitName("player") or "?")))
  local lines, net = ns:MoneyToday()
  if lines then
    for _, line in ipairs(lines) do add("  " .. line) end
    add(("  Net: %s%s"):format(net >= 0 and "+" or "-", ns.Money(math.abs(net))))
  else
    add(dim("  Nothing in or out yet today."))
  end
end

local function charactersText(add)
  add(heading("Your characters"))
  local keys = sortedCharKeys()
  if #keys == 0 then add("  None yet. Log in on each character once.") end
  for _, k in ipairs(keys) do
    local c = ns.db.chars[k]
    add(("  %s, level %s %s"):format(classColored(c), c.level or "?", c.faction or ""))
    local profNames = {}
    for p in pairs(c.profs or {}) do profNames[#profNames + 1] = p end
    table.sort(profNames)
    if #profNames == 0 then add("      No professions saved yet.") end
    for _, p in ipairs(profNames) do
      local info = c.profs[p]
      local n = info.recipeCount or 0
      local recipes = n > 0 and (n .. " recipes saved") or "|cffee8597open this profession's window to save its recipes|r"
      add(("      %s %s/%s, %s"):format(p, info.rank or "?", info.max or "?", recipes))
    end
  end

  add("")
  add(heading("Key prices") .. "  " .. dim("(" .. ns.MarketKey() .. ")"))
  for _, item in ipairs(KEY_ITEMS) do
    local price, src, t = ns:GetPrice(item[1])
    if price then
      add(("  %s: %s %s"):format(item[2], ns.Money(price), dim((src or "") .. " " .. (t and ns.Age(t) or ""))))
    else
      add(("  %s: %s"):format(item[2], dim("no price yet")))
    end
  end

  add("")
  add(heading("Price data"))
  local market = ns.db.prices[ns.MarketKey()] or {}
  local count, newest, oldest = 0, 0, nil
  for _, rec in pairs(market) do
    count = count + 1
    if rec.t then
      newest = math.max(newest, rec.t)
      oldest = oldest and math.min(oldest, rec.t) or rec.t
    end
  end
  add(("  %d items priced. Newest %s, oldest %s."):format(count, newest > 0 and ns.Age(newest) or "never", oldest and ns.Age(oldest) or "never"))
  local ext = ns:ExternalSources()
  add("  Other auction addons: " .. (#ext > 0 and table.concat(ext, ", ") or "none found"))
  add("  Price source: " .. ns.db.settings.source)
  local vb = 0
  for _ in pairs(ns.db.vendorBuy) do vb = vb + 1 end
  add(("  %d vendor prices saved. Open any vendor to add theirs."):format(vb))
end

local TEXT_VIEWS = { dashboard = dashboardText, characters = charactersText }

---------------------------------------------------------------------------
-- Settings tab: a control for each setting. Changes apply straight away.
---------------------------------------------------------------------------
local function recalc() ns:InvalidateValues(true) end

local SETTINGS = {
  { section = "Values and shuffles" },
  { key = "ahCut", label = "Auction house cut", kind = "number", suffix = "%", min = 0, max = 99, after = recalc,
    help = "Taken off every auction house sale in values and shuffles." },
  { key = "margin", label = "Safety margin", kind = "number", suffix = "%", min = 0, max = 99,
    help = "Shuffles and \"buy at or below\" keep this much below an item's worth." },
  { key = "actionSeconds", label = "Seconds per craft", kind = "number", suffix = "seconds", min = 1, max = 60,
    help = "Used for the rough profit per hour." },
  { key = "source", label = "Auction house prices from", kind = "choice", after = recalc, options = {
      { "auto", "Auto" }, { "own", "My scans" }, { "Auctionator", "Auctionator" }, { "TSM", "TSM" }, { "Auctioneer", "Auctioneer" } },
    help = "Auto uses your own scans while they're fresh, then other auction addons." },

  { section = "Deal alerts", rules = true },
  { key = "dealUsualPct", label = "Below usual price by", kind = "number", suffix = "% or more", min = 1, max = 99 },
  { key = "dealWindow", label = "Usual price over", kind = "choice", options = {
      { "week", "Week" }, { "month", "Month" }, { "3months", "3 months" }, { "6months", "6 months" },
      { "year", "Year" }, { "all", "All time" } } },
  { key = "dealHistory", label = "Usual prices from", kind = "choice", options = {
      { "auto", "Auto" }, { "local", "My scans" }, { "tsm", "TSM" } },
    help = "Auto uses TSM's history where it has a price, otherwise your own scans." },
  { key = "dealVendorPct", label = "Below vendor price by", kind = "number", suffix = "% or more", min = 0, max = 99 },
  { key = "dealVendorMin", label = "Least vendor profit each", kind = "money",
    help = "For example 1s or 50c. \"off\" for no minimum." },
  { key = "dealSound", label = "Chime", kind = "check", help = "Plays the raid warning sound when a scan finds new deals." },

  { section = "Other" },
  { key = "minimap", label = "Minimap button", kind = "check", after = function() ns:UpdateMinimapButton() end },
  { key = "tooltip", label = "Tooltip lines", kind = "check" },
  { key = "debug", label = "Debug messages", kind = "check", help = "Extra chat lines for testing." },
}

local LABEL_WIDTH, CONTROL_X = 210, 220

buildSettings = function()
  local sf, content = T:Scroll(main.body)
  sf:SetAllPoints()
  sf.controls = {}
  local y = 0
  for _, def in ipairs(SETTINGS) do
    if def.section then
      if y > 0 then y = y + 14 end
      local h = T:Text(content, 13, T.accent)
      h:SetPoint("TOPLEFT", 4, -y)
      h:SetText(def.section)
      y = y + 22
      if def.rules then
        sf.rules = T:Text(content, 11, T.dim)
        sf.rules:SetPoint("TOPLEFT", 4, -y)
        sf.rules:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        sf.rules:SetJustifyH("LEFT")
        y = y + 34
      end
    else
      local label = T:Text(content, 12)
      label:SetPoint("TOPLEFT", 4, -(y + 4))
      label:SetWidth(LABEL_WIDTH)
      label:SetJustifyH("LEFT")
      label:SetText(def.label)

      local function changed(v)
        ns.db.settings[def.key] = v
        if def.after then def.after() end
        if sf.rules then sf.rules:SetText("Deals are listings " .. ns:DealRules() .. ".") end
      end
      local control
      if def.kind == "number" then
        control = T:Number(content, def, changed)
      elseif def.kind == "money" then
        control = T:MoneyBox(content, changed)
      elseif def.kind == "choice" then
        local opts = {}
        for _, o in ipairs(def.options) do opts[#opts + 1] = { value = o[1], label = o[2] } end
        control = T:Choice(content, opts, changed)
      elseif def.kind == "check" then
        control = T:Check(content, function(self) changed(self:GetChecked()) end)
        control:SetPoint("TOPLEFT", CONTROL_X, -(y + 4))
      end
      if def.kind ~= "check" then control:SetPoint("TOPLEFT", CONTROL_X, -y) end
      sf.controls[#sf.controls + 1] = { def = def, control = control }
      y = y + 28
      if def.help then
        local help = T:Text(content, 11, T.dim)
        help:SetPoint("TOPLEFT", CONTROL_X, -(y - 4))
        help:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        help:SetJustifyH("LEFT")
        help:SetText(def.help)
        y = y + 16
      end
    end
  end
  content:SetHeight(y + 10)
  return sf
end

local function refreshSettings()
  local sf = main.views.settings
  sf:GetScrollChild():SetWidth(math.max(sf:GetWidth() - 12, 300))
  for _, c in ipairs(sf.controls) do
    local v = ns.db.settings[c.def.key]
    if c.def.kind == "check" then c.control:SetChecked(v) else c.control:SetValue(v) end
  end
  if sf.rules then sf.rules:SetText("Deals are listings " .. ns:DealRules() .. ".") end
  sf.UpdateScrollBar()
end

function ns:RefreshUI()
  if not main or not main:IsShown() or not ns.db then return end
  local build = TEXT_VIEWS[main.view]
  if main.view == "settings" then
    refreshSettings()
  elseif build then
    local L = {}
    build(function(s) L[#L + 1] = s or "" end)
    local sf = main.views[main.view]
    sf.content:SetWidth(math.max(sf:GetWidth() - 12, 300))
    sf.text:SetText(table.concat(L, "\n"))
    sf.content:SetHeight(sf.text:GetStringHeight() + 12)
    sf.UpdateScrollBar()
  end
  main.scanBtn:SetEnabled(ns:IsAHOpen() and not ns.Scan.active)
  ns:UpdateFullScanButtons()
end

---------------------------------------------------------------------------
-- Minimap button: click to open the ledger, right-click for shuffles, drag to move
---------------------------------------------------------------------------
local mm

local function placeMinimapButton()
  local a = math.rad(ns.db.settings.minimapAngle or 200)
  local r = Minimap:GetWidth() / 2 + 5
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function buildMinimapButton()
  if mm or not Minimap then return end
  mm = CreateFrame("Button", "ForeverLedgerMinimapButton", Minimap)
  mm:SetSize(31, 31)
  mm:SetFrameStrata("MEDIUM")
  mm:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mm:RegisterForDrag("LeftButton")
  mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = mm:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = mm:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = mm:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  mm:SetScript("OnClick", function(_, which)
    if which == "RightButton" then ns:ToggleUI("shuffles") else ns:ToggleUI() end
  end)
  mm:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      ns.db.settings.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
      placeMinimapButton()
    end)
  end)
  mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Forever Ledger")
    GameTooltip:AddLine("Click to open or close.", 1, 1, 1)
    GameTooltip:AddLine("Right-click for shuffles.", 1, 1, 1)
    GameTooltip:AddLine("Drag to move. /fl minimap hides it.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
  placeMinimapButton()
end

function ns:UpdateMinimapButton()
  if ns.db.settings.minimap then
    buildMinimapButton()
    if mm then mm:Show() end
  elseif mm then
    mm:Hide()
  end
end
ns:OnReady(function() ns:UpdateMinimapButton() end)

---------------------------------------------------------------------------
-- Shuffles and Vendor flips: a list of rows; click one to show its steps underneath
---------------------------------------------------------------------------
local MAX_ROWS = 25       -- per section
local ROW_HEIGHT = 22
local rows, details, openKeys = {}, {}, {}

local function getRow(i)
  local r = rows[i]
  if not r then
    r = CreateFrame("Button", nil, main.shuffleContent)
    r:SetHeight(ROW_HEIGHT)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
    r.right = T:Text(r, 12)
    r.right:SetPoint("RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")
    r.left = T:Text(r, 12)
    r.left:SetPoint("LEFT", 4, 0)
    r.left:SetPoint("RIGHT", r.right, "LEFT", -12, 0)
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
      if self.shuffle then
        openKeys[self.shuffle.key] = not openKeys[self.shuffle.key]
        layoutShuffles()
      end
    end)
    rows[i] = r
  end
  return r
end

local function getDetail(i)
  local fs = details[i]
  if not fs then
    fs = T:Text(main.shuffleContent, 11, { 1, 1, 1, 0.85 })
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(3)
    details[i] = fs
  end
  return fs
end

-- "Use recipes from" checkboxes, one per character.
local boxes = {}
local function getBox(i)
  local cb = boxes[i]
  if not cb then
    cb = T:Check(main.shuffleContent, function(self)
      ns.db.settings.skipChars[self.charKey] = (not self:GetChecked()) or nil
      ns:InvalidateValues(true)
      ns:RefreshShuffles()
    end)
    boxes[i] = cb
  end
  return cb
end

-- Returns the height used.
local function layoutCharBoxes(content, width)
  if not main.charLabel then
    main.charLabel = T:Text(content, 12, T.dim)
    main.charLabel:SetText("Use recipes from:")
  end
  main.charLabel:ClearAllPoints()
  main.charLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
  main.charLabel:Show()

  local keys = sortedCharKeys()
  local x, y = main.charLabel:GetStringWidth() + 16, 0
  for i, key in ipairs(keys) do
    local cb = getBox(i)
    cb.label:SetText(classColored(ns.db.chars[key]))
    local w = 14 + 6 + cb.label:GetStringWidth() + 18
    if x + w > width then x, y = 4, y + 22 end
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", x, -(y + 2))
    cb:SetChecked(not ns.db.settings.skipChars[key])
    cb.charKey = key
    cb:Show()
    x = x + w
  end
  for i = #keys + 1, #boxes do boxes[i]:Hide() end
  return y + 30
end

layoutShuffles = function()
  local content, data = main.shuffleContent, main.shuffles
  content:SetWidth(math.max(main.shuffleSF:GetWidth() - 12, 400))
  local width = content:GetWidth()
  local flipsView = main.view == "flips"
  local y, nRows, nDetails = 0, 0, 0
  -- Recipes don't matter for vendor flips, so only the Shuffles tab has the checkboxes.
  if flipsView then
    if main.charLabel then main.charLabel:Hide() end
    for _, cb in ipairs(boxes) do cb:Hide() end
  else
    y = layoutCharBoxes(content, width)
  end

  local function row(left, right, s)
    nRows = nRows + 1
    local r = getRow(nRows)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r.left:SetText(left)
    r.right:SetText(right or "")
    r.shuffle = s
    r:SetEnabled(s ~= nil)
    r:Show()
    y = y + ROW_HEIGHT
  end

  local function detail(text)
    nDetails = nDetails + 1
    local fs = getDetail(nDetails)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -(y + 2))
    fs:SetWidth(width - 28)
    fs:SetText(text)
    fs:Show()
    y = y + fs:GetStringHeight() + 12
  end

  local function section(title, list)
    row(heading(title))
    if #list == 0 then row(dim("  None at current prices.")) end
    for i = 1, math.min(#list, MAX_ROWS) do
      local s = list[i]
      local open = openKeys[s.key]
      row(dim(open and "-" or "+") .. " " .. ns:ShuffleTitle(s), ns:ShuffleSummary(s), s)
      if open then detail(ns:ShuffleDetails(s)) end
    end
    y = y + 12
  end

  if flipsView then
    section("Buy on the auction house, sell straight to a vendor", data.flips)
  else
    section("Sells to a vendor (safe)", data.vendor)
    section("Sells on the auction house (depends on buyers)", data.ah)
    if #data.oneOff > 0 then section("Limited supply (fewer than 5 listed)", data.oneOff) end
  end

  for i = nRows + 1, #rows do rows[i]:Hide() end
  for i = nDetails + 1, #details do details[i]:Hide() end
  content:SetHeight(math.max(y, 10))
  main.shuffleSF.UpdateScrollBar()
end

-- Item names arrive from the game a moment after they're first asked for.
-- Redraw the list once they do, so "item 4470" becomes "Simple Wood".
local redrawQueued = false
ns:On("GET_ITEM_INFO_RECEIVED", function()
  if redrawQueued or not main or not main:IsShown() or not main.shuffles then return end
  if main.view ~= "shuffles" and main.view ~= "flips" then return end
  redrawQueued = true
  C_Timer.After(0.5, function()
    redrawQueued = false
    if main:IsShown() and (main.view == "shuffles" or main.view == "flips") then layoutShuffles() end
  end)
end)

function ns:RefreshShuffles()
  if not main then return end
  local vendor, ah, oneOff, flips = ns:FindShuffles()

  -- Debug: name the shuffles that came or went since the last refresh.
  if ns.db.settings.debug then
    local now, before = {}, main.shuffleKeys
    for _, list in ipairs({ vendor, ah, oneOff, flips }) do
      for _, s in ipairs(list) do now[s.key] = ns:ShuffleTitle(s) .. " (" .. ns.Money(s.profit) .. ")" end
    end
    if before then
      for k, title in pairs(now) do if not before[k] then ns:Debug("New since last refresh:", title) end end
      for k, title in pairs(before) do if not now[k] then ns:Debug("Gone since last refresh:", title) end end
    end
    main.shuffleKeys = now
  end

  main.shuffles = { vendor = vendor, ah = ah, oneOff = oneOff, flips = flips }
  main.shuffleInfo:SetText(("%d shuffles and %d vendor flips, worked out at %s. Click a row for details."):format(
    #vendor + #ah + #oneOff, #flips, date("%H:%M")))
  if main.view == "shuffles" or main.view == "flips" then layoutShuffles() end
end

---------------------------------------------------------------------------
-- Scan buttons and status
---------------------------------------------------------------------------
-- "Full scan: Ready", or a countdown until Blizzard allows the next one.
function ns:UpdateFullScanButtons()
  if not ns.db then return end
  local wait = ns.Scan:FullWait()
  local label, ready = "Full scan", false
  if wait == 0 then
    label, ready = "Full scan: Ready", true
  elseif wait < math.huge then
    label = ("Full scan: %d:%02d"):format(math.floor(wait / 60), wait % 60)
  end
  for _, b in ipairs({ main and main.fullBtn or false, ns.ahFullButton or false }) do
    if b then
      b:SetText(label)
      b:SetEnabled(ready and ns:IsAHOpen() and not ns.Scan.active)
    end
  end
end

-- Tick the countdown once a second while a button showing it is on screen.
ns:OnReady(function()
  C_Timer.NewTicker(1, function()
    if (main and main:IsShown()) or (ns.ahFullButton and ns.ahFullButton:IsVisible()) then
      ns:UpdateFullScanButtons()
    end
  end)
end)

function ns:UpdateScanStatus(done, total)
  if main and main.status then
    main.status:SetText(total and total > 0 and ("Scanning: %d of %d"):format(done, total) or "")
    if done and total and done >= total then
      C_Timer.After(3, function() if main then main.status:SetText("") end end)
    end
  end
end

-- Scan buttons on the auction house window itself, in Blizzard's style to match it.
function ns:OnAHShow()
  local ah = AuctionHouseFrame or AuctionFrame
  if ah and not ns.ahButton then
    ns.ahButton = blizzButton(ah, "Scan materials", 120, function() ns.Scan:Start("watch") end)
    ns.ahButton:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -30, -28)
    ns.ahFullButton = blizzButton(ah, "Full scan", 130, function() ns.Scan:Start("full") end)
    ns.ahFullButton:SetPoint("RIGHT", ns.ahButton, "LEFT", -4, 0)
  end
  ns:UpdateFullScanButtons()
  ns:RefreshUI()
end

---------------------------------------------------------------------------
-- Text window for export, import and CSV
---------------------------------------------------------------------------
local io
local function ioWindow()
  if io then return io end
  io = themedWindow("ForeverLedgerIO", 580, 400, "Forever Ledger")
  io.help = T:Text(io, 12, T.dim)
  io.help:SetPoint("TOPLEFT", 14, -42)
  io.help:SetPoint("RIGHT", io, "RIGHT", -14, 0)
  io.help:SetJustifyH("LEFT")

  local sf = CreateFrame("ScrollFrame", nil, io, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 14, -72)
  sf:SetPoint("BOTTOMRIGHT", -32, 48)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(520)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(0)
  eb:SetScript("OnEscapePressed", function() io:Hide() end)
  sf:SetScrollChild(eb)
  io.eb = eb

  io.action = T:Button(io, "Import", 110, function() end)
  io.action:SetPoint("BOTTOMRIGHT", -14, 12)
  return io
end

function ns:ShowExport()
  local f = ioWindow()
  f.title:SetText("Export")
  f.help:SetText("Press Ctrl+A, then Ctrl+C to copy. Paste it into Import on your other account, or send it to Claude.")
  f.eb:SetText(ns:Export())
  f.action:Hide()
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

function ns:ShowImport()
  local f = ioWindow()
  f.title:SetText("Import")
  f.help:SetText("Paste an export from your other account with Ctrl+V, then click Import. Newer data replaces older data.")
  f.eb:SetText("")
  f.action:SetText("Import")
  f.action:SetScript("OnClick", function()
    local ok, msg = ns:Import(f.eb:GetText())
    ns:Print(msg)
    if ok then f:Hide(); ns:RefreshUI() end
  end)
  f.action:Show()
  f:Show()
  f.eb:SetFocus()
end

-- Readable price list for the web calculator or a chat with Claude.
function ns:PricesCSV()
  local lines = { "item_id,name,price_copper,cheapest_copper,listed,source,age_minutes,vendor_pays_copper,vendor_charges_copper" }
  local market = ns.db.prices[ns.MarketKey()] or {}
  local ids, seen = {}, {}
  for id in pairs(market) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  for _, id in ipairs(ns:WatchList()) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local rec = market[id]
    local name = ns.GetItemInfo(id) or ("item " .. id)
    local sell = ns:GetSellPrice(id)
    local buy = ns.db.vendorBuy[id]
    if rec or buy then
      lines[#lines + 1] = table.concat({
        id, (name:gsub(",", "")),
        rec and rec.a or "", rec and rec.m or "", rec and rec.q or "",
        rec and rec.src or "", rec and rec.t and math.floor((time() - rec.t) / 60) or "",
        sell or "", buy and buy.p or "",
      }, ",")
    end
  end
  return table.concat(lines, "\n")
end

function ns:ShowPricesCSV()
  local f = ioWindow()
  f.title:SetText("Prices as text")
  f.help:SetText("Press Ctrl+A, then Ctrl+C. Paste this into a chat with Claude to check flips at today's prices.")
  f.eb:SetText(ns:PricesCSV())
  f.action:Hide()
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end
