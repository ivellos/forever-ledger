local _, ns = ...
local T = ns.Theme

local CLASS_COLORS = RAID_CLASS_COLORS or {}

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
-- footerY: pixels from the bottom where a footer starts (the theme tints it).
local function themedWindow(name, w, h, titleText, footerY)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  -- Clicking a window brings all of it in front of the other, instead of the two
  -- windows' contents mixing where they overlap.
  f:SetToplevel(true)
  f:SetScript("OnShow", function(self) self:Raise() end)
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
  if T.theme.serif then f.title:SetFont(T.SERIF, 16, "") end
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
  T:DecorateWindow(f, footerY, bar)
  return f
end

ns.ThemedWindow = themedWindow

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
local setView, layoutShuffles, buildTable

local TABS = {
  { key = "dashboard", label = "Dashboard" },
  { key = "shuffles", label = "Shuffles" },
  -- Vendor flips moved to the Buy queue beside the auction house (owner, October 2).
  { key = "deals", label = "Deals" },
  { key = "ledger", label = "Ledger" },
  { key = "crates", label = "Crates", setting = "crates" },
  { key = "recipes", label = "Recipes" },
  { key = "characters", label = "Characters" },
  { key = "settings", label = "Settings" },
  { key = "help", label = "Help" },
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

-- Line the tabs up, leaving out any turned off in Settings (the Crates tab).
function ns:LayoutTabs()
  if not main then return end
  local prev
  for _, tab in ipairs(TABS) do
    local b = main.tabs[tab.key]
    local on = not tab.setting or ns.db.settings[tab.setting]
    b:ClearAllPoints()
    b:SetShown(on)
    if on then
      if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("TOPLEFT", 6, -32) end
      prev = b
    end
  end
  if main.view and not main.tabs[main.view]:IsShown() then setView("dashboard") end
end

local function buildMain()
  if main then return main end
  main = themedWindow("ForeverLedgerFrame", 760, 520,
    T:TitleCode() .. "Forever Ledger|r  " .. dim(ns.VERSION), 46)
  -- Shopping lists away from the auction house, to plan ahead (owner, October 3).
  local lists = T:Button(main.bar, "Shopping lists", 110, function() ns:ShowSidePanel("lists") end, 22)
  lists:SetPoint("RIGHT", main.bar, "RIGHT", -36, 0)

  -- Tabs
  main.tabs = {}
  for _, tab in ipairs(TABS) do
    main.tabs[tab.key] = T:Tab(main, tab.label, function() setView(tab.key) end)
  end
  ns:LayoutTabs()
  rule(main, "TOP", -61)

  -- Content area and footer
  main.body = CreateFrame("Frame", nil, main)
  main.body:SetPoint("TOPLEFT", 14, -72)
  main.body:SetPoint("BOTTOMRIGHT", -10, 52)
  rule(main, "BOTTOM", 46)

  main.views = {
    dashboard = ns:BuildDashboard(main.body),
    ledger = ns:BuildLedger(main.body),
    deals = ns:BuildDeals(main.body),
    crates = ns:BuildCrates(main.body),
    recipes = ns:BuildRecipes(main.body),
    characters = ns:BuildCharacters(main.body),   -- Characters.lua
    help = ns:BuildHelp(main.body),   -- Help.lua
  }
  main.views.settings = ns:BuildSettings(main.body)   -- Settings.lua
  main.table = buildTable()
  main.views.shuffles, main.views.flips = main.table, main.table

  -- Footer buttons. Scan buttons show on Dashboard and Characters.
  local full = T:Button(main, "Full scan", 140, function() ns.Scan:Start("full") end)
  full:SetPoint("BOTTOMLEFT", 12, 12)
  full:SetPrimary(true)
  local scan = T:Button(main, "Scan materials", 120, function() ns.Scan:Start("watch") end)
  scan:SetPoint("LEFT", full, "RIGHT", 6, 0)
  -- One button for copying data across (owner's test, October 4: like the shopping
  -- lists' Share/import); Export, Import and Prices as text are tabs in its window.
  local dataBtn = T:Button(main, "Export / import", 120, function() ns:ShowExport() end)
  dataBtn:SetPoint("LEFT", scan, "RIGHT", 18, 0)
  main.scanBtn, main.fullBtn = scan, full
  main.footer = {
    dashboard = { full, scan },
    deals = { full, scan },
    characters = { full, scan, dataBtn },
  }

  main.refreshBtn = T:Button(main, "Refresh", 90, function() ns:RefreshShuffles() end)
  main.refreshBtn:SetPoint("BOTTOMLEFT", 12, 12)
  main.footer.shuffles = { main.refreshBtn }
  main.footer.flips = { main.refreshBtn }
  main.shuffleInfo = T:Text(main, 11, T.dim)
  main.shuffleInfo:SetPoint("LEFT", main.refreshBtn, "RIGHT", 12, 0)

  main.status = T:Text(main, 11, T.accent)
  main.status:SetPoint("BOTTOMRIGHT", -26, 18)
  -- The info line stops short of the scan status, and cuts off rather than running under it.
  main.shuffleInfo:SetPoint("RIGHT", main.status, "LEFT", -12, 0)
  main.shuffleInfo:SetJustifyH("LEFT")
  main.shuffleInfo:SetWordWrap(false)

  -- Resizing: drag the grip in the bottom-right corner. The starting size is the smallest.
  local MIN_W, MIN_H = 760, 520
  main:SetResizable(true)
  if main.SetResizeBounds then main:SetResizeBounds(MIN_W, MIN_H, 1800, 1300)
  elseif main.SetMinResize then main:SetMinResize(MIN_W, MIN_H) end
  local saved = ns.db.settings.window
  if saved.w and saved.h then main:SetSize(math.max(saved.w, MIN_W), math.max(saved.h, MIN_H)) end
  local grip = CreateFrame("Button", nil, main)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  -- Never size past the screen edge: the window is kept on screen, so the game would
  -- push it upwards instead, a little more each time.
  grip:SetScript("OnMouseDown", function()
    local maxW = math.max(MIN_W, UIParent:GetRight() / main:GetEffectiveScale() * UIParent:GetEffectiveScale() - main:GetLeft())
    local maxH = math.max(MIN_H, main:GetTop() - UIParent:GetBottom() / main:GetEffectiveScale() * UIParent:GetEffectiveScale())
    if main.SetResizeBounds then main:SetResizeBounds(MIN_W, MIN_H, maxW, maxH)
    elseif main.SetMaxResize then main:SetMaxResize(maxW, maxH) end
    main:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    main:StopMovingOrSizing()
    saved.w, saved.h = main:GetWidth(), main:GetHeight()
  end)
  -- Lay the current tab out again while the size changes, at most every 0.1 seconds.
  local queued = false
  main:SetScript("OnSizeChanged", function()
    if queued or not main.view then return end
    queued = true
    C_Timer.After(0.1, function()
      queued = false
      if main.view == "shuffles" or main.view == "flips" then layoutShuffles() else ns:RefreshUI() end
    end)
  end)

  setView("dashboard")
  return main
end

setView = function(view)
  main.view = view
  main.lastRefresh = nil   -- a tab you clicked draws at once
  -- Help opens on Getting started, Settings on its first section, searches cleared.
  if view == "help" then
    ns.helpTopic, ns.helpQuery = nil, nil
    local h = main.views.help
    if h and h.search then h.search:SetText("") end
  end
  -- The Ledger opens on All each time (owner's test, October 3), like Help and Settings.
  if view == "ledger" and ns.db and ns.db.settings.ledger then ns.db.settings.ledger.tab = "all" end
  if view == "settings" then
    ns:ResetSettingsView()
  end
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

-- The flip watch and price saves call this: if the Vendor flips tab is on screen, work
-- out just the flips again (not every shuffle, which took 195 ms each time), at most
-- every 2 seconds.
local flipsQueued = false
function ns:RefreshFlipsIfShown()
  if not (main and main:IsShown() and main.view == "flips") or flipsQueued then return end
  flipsQueued = true
  C_Timer.After(2, function()
    flipsQueued = false
    if not (main:IsShown() and main.view == "flips") then return end
    if not main.shuffles then ns:RefreshShuffles(); return end
    main.shuffles.flips = ns:FindVendorFlips()
    main.shuffleInfo:SetText(("%d shuffles, %d vendor flips (%s). Click to search the AH, right-click for details."):format(
      #main.shuffles.vendor + #main.shuffles.ah + #main.shuffles.oneOff, #main.shuffles.flips, date("%H:%M")))
    layoutShuffles()
  end)
end

function ns:RefreshDealsIfShown()
  if main and main:IsShown() and main.view == "deals" then ns:RefreshDeals() end
end

-- After a full scan finds vendor flips: open the Buy queue beside the auction house, if
-- it's closed. It never switches a tab you're on (a shopping list you're working on),
-- and the flip watch's quick checks don't open anything (owner, October 2).
function ns:OpenFlips()
  if ns.OpenBuyQueueGently then ns:OpenBuyQueueGently() end
end

function ns:ToggleUI(view)
  local f = buildMain()
  if f:IsShown() and not view then f:Hide(); return end
  ns:ScanSkillLines()
  T:Refresh()
  f:Show()
  setView(view or f.view or "dashboard")
  -- The first time: a short welcome over the window (Welcome.lua).
  if ns.ShowWelcome and not ns.db.settings.welcomeSeen then ns:ShowWelcome() end
end

-- For Welcome.lua: the main window's content area, and switching tabs.
function ns:MainBody() return main and main.body end
function ns:ShowTab(view) ns:ToggleUI(view) end

local TEXT_VIEWS = {}   -- (the Characters tab is Characters.lua now)

-- (The Settings tab is Settings.lua.)

function ns:RefreshUI()
  if not main or not main:IsShown() or not ns.db then return end
  -- Scans, crafts and skill updates each ask for a redraw, often several a second; the
  -- Deals tab took about 0.1 s each (/fl perf, October 3: 75 redraws in 9 minutes).
  -- At most one a second: a burst gets one redraw now and one when it's over.
  local now = GetTime()
  if main.lastRefresh and now - main.lastRefresh < 1 then
    if not main.refreshQueued then
      main.refreshQueued = true
      C_Timer.After(1 - (now - main.lastRefresh), function()
        main.refreshQueued = false
        ns:RefreshUI()
      end)
    end
    return
  end
  main.lastRefresh = now
  local build = TEXT_VIEWS[main.view]
  if main.view == "settings" then
    ns:RefreshSettings()
  elseif main.view == "dashboard" then
    ns:RefreshDashboard(main.views.dashboard)
  elseif main.view == "ledger" then
    ns:RefreshLedger()
  elseif main.view == "crates" then
    ns:RefreshCrates()
  elseif main.view == "deals" then
    ns:RefreshDeals()
  elseif main.view == "help" then
    ns:RefreshHelp()
  elseif main.view == "recipes" then
    ns:RefreshRecipes()
  elseif main.view == "characters" then
    ns:RefreshCharacters()
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
    if IsShiftKeyDown() then ns:ShowSidePanel("lists")
    elseif IsControlKeyDown() then
      if ns:GeneralSessionRunning() then ns:StopGeneralSession() else ns:StartGeneralSession() end
    elseif which == "RightButton" then ns:ToggleUI("shuffles") else ns:ToggleUI() end
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
    GameTooltip:AddLine("Shift-click for shopping lists.", 1, 1, 1)
    GameTooltip:AddLine(ns:GeneralSessionRunning() and "Ctrl-click to stop the session." or "Ctrl-click to start a session.", 1, 1, 1)
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
-- Shuffles and Vendor flips: a table with sortable columns. Click a row to open
-- what to buy (left) and the steps (right) underneath it.
---------------------------------------------------------------------------
local ROW_HEIGHT = 26
local MAX_ROWS = 60
local SUBTABS = {
  { key = "vendor", label = "Sells to a vendor" },
  { key = "ah", label = "Sells on the auction house" },
  { key = "oneOff", label = "Limited supply" },
}
local COLUMNS = {
  shuffles = {
    { key = "route", label = "Route", width = 116, tip = "An icon for each step. Hover an icon to read that step." },
    { key = "name", label = "Shuffle", tip = "What you buy or craft first. Click a row for what to buy and every step." },
    { key = "steps", label = "Steps", width = 44, tip = "How many steps, including the sale." },
    { key = "profit", label = "Profit", width = 90, tip = "Profit each time you do it (per craft, or per item bought)." },
    { key = "ret", label = "Return", width = 58, tip = "Profit as a share of what you spend." },
    { key = "hour", label = "Per hour", width = 96, tip = "Rough profit per hour, counting only crafting time (see Seconds per craft in Settings)." },
    { key = "runs", label = "Runs", width = 62, tip = "How many times you could do it profitably with what's listed now: only listings cheap enough count, and the scarcest thing you buy on the auction house sets the limit. \"no limit\" when everything comes from vendors." },
  },
  flips = {
    { key = "name", label = "Item", tip = "Listed for less than a vendor pays." },
    { key = "profit", label = "Profit each", width = 90, tip = "What a vendor pays, minus what it costs." },
    { key = "ret", label = "Return", width = 58, tip = "Profit as a share of what you spend." },
    { key = "runs", label = "Listed", width = 62, tip = "How many are listed cheaply enough to make a profit." },
    { key = "total", label = "If all bought", width = 110, tip = "Profit each times the number listed cheaply enough: about the most you could make." },
  },
}
local SORT_VALUE = {
  route = function(s) return #ns:StepIcons(s.opt) end,
  steps = function(s) return #ns:StepIcons(s.opt) end,
  name = function(s) return ns:ShuffleName(s):lower() end,
  profit = function(s) return s.profit end,
  ret = function(s) return ns:ShuffleReturn(s) end,
  hour = function(s) return s.perHour end,
  runs = function(s) return ns:ShuffleRuns(s) or math.huge end,
  total = function(s) return s.profit * (ns:ShuffleRuns(s) or 0) end,
}
local sortBy = { shuffles = { key = "hour", desc = true }, flips = { key = "total", desc = true } }
local subtab = "vendor"
local openKeys = {}
local rows, details, boxes, headerCells = {}, {}, {}, {}

local function itemName(id) return ns.ItemName(id) end

-- x position and width of each column for a table this wide.
local function columnLayout(cols, width)
  local fixed = 0
  for _, c in ipairs(cols) do fixed = fixed + (c.width or 0) + 8 end
  local x, out = 4, {}
  for _, c in ipairs(cols) do
    local w = c.width or math.max(140, width - fixed - 4)
    out[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  return out
end

-- The item whose icon a row shows: what you buy, or what you craft.
local function mainItem(s)
  if s.group then return s.members[1].id end
  if s.single then return s.id end
  return s.opt.rec and s.opt.rec.out or s.id
end

buildTable = function()
  local f = CreateFrame("Frame", nil, main.body)
  f:SetAllPoints()

  f.subtabs = {}
  local prev
  for _, st in ipairs(SUBTABS) do
    local b = T:Tab(f, st.label, function() subtab = st.key; layoutShuffles() end)
    b.base = st.label
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("TOPLEFT", -6, 4) end
    f.subtabs[st.key] = b
    prev = b
  end

  -- A line under the sub-tabs, setting them apart from the rest (owner's test, October 4).
  f.subLine = f:CreateTexture(nil, "BORDER")
  f.subLine:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
  f.subLine:SetHeight(1)
  f.subLine:SetPoint("TOPLEFT", 0, -30)
  f.subLine:SetPoint("TOPRIGHT", 0, -30)

  -- Whose recipes count: one dropdown with a tick box per character on this realm and
  -- faction (owner's test, October 4: a row of boxes grows with every alt, and it listed
  -- a character from another realm, whose recipes don't count anyway).
  f.charLabel = T:Text(f, 12, T.dim)
  f.charLabel:SetText("Recipes from")
  f.charBtn = T:Button(f, "", 220, function() f.charMenu:SetShown(not f.charMenu:IsShown()) end, 22)
  f.charBtn:GetFontString():ClearAllPoints()
  f.charBtn:GetFontString():SetPoint("LEFT", 8, 0)
  f.charBtn:GetFontString():SetPoint("RIGHT", -18, 0)
  f.charBtn:GetFontString():SetJustifyH("LEFT")
  f.charBtn:GetFontString():SetWordWrap(false)
  local arrow = T:Text(f.charBtn, 11, T.dim)
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetText("v")
  f.charMenu = CreateFrame("Frame", nil, f.charBtn)
  f.charMenu:SetPoint("TOPLEFT", f.charBtn, "BOTTOMLEFT", 0, -2)
  f.charMenu:SetFrameStrata("FULLSCREEN_DIALOG")
  f.charMenu:EnableMouse(true)
  T:Fill(f.charMenu, { 0.05, 0.05, 0.05, 0.98 })
  T:Border(f.charMenu)
  f.charMenu:Hide()
  f.charBtn:HookScript("OnHide", function() f.charMenu:Hide() end)
  -- A click anywhere else closes it (owner's test, October 4).
  ns:On("GLOBAL_MOUSE_DOWN", function()
    if f.charMenu:IsShown() and not (f.charMenu:IsMouseOver() or f.charBtn:IsMouseOver()) then f.charMenu:Hide() end
  end)

  f.header = CreateFrame("Frame", nil, f)
  f.header:SetHeight(22)
  T:Fill(f.header, { 1, 1, 1, 0.05 })

  f.sf, f.content = T:Scroll(f)
  f.empty = T:Text(f.content, 12, T.dim)
  f.empty:SetPoint("TOPLEFT", 8, -8)
  f.empty:SetText("None at current prices. Scan the auction house, then click Refresh.")
  return f
end

local function getBox(i)
  if not boxes[i] then
    boxes[i] = T:Check(main.table.charMenu, function(self)
      ns.db.settings.skipChars[self.charKey] = (not self:GetChecked()) or nil
      ns:InvalidateValues(true)
      ns:RefreshShuffles()
    end)
    boxes[i]:SetHitRectInsets(0, -170, -3, -3)   -- the name ticks it too
  end
  return boxes[i]
end

local function getHeaderCell(i)
  local h = headerCells[i]
  if not h then
    h = CreateFrame("Button", nil, main.table.header)
    h.fs = T:Text(h, 11, T.dim)
    h.fs:SetAllPoints()
    h:SetScript("OnEnter", function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(self.label, 1, 1, 1)
      GameTooltip:AddLine(self.tip, 0.85, 0.85, 0.85, true)
      GameTooltip:AddLine("Click to sort.", T.accent[1], T.accent[2], T.accent[3])
      GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h:SetScript("OnClick", function(self)
      local sort = sortBy[main.view == "flips" and "flips" or "shuffles"]
      if sort.key == self.key then
        sort.desc = not sort.desc
      else
        sort.key, sort.desc = self.key, self.key ~= "name"
      end
      layoutShuffles()
    end)
    headerCells[i] = h
  end
  return h
end

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, main.table.content)
  r:SetHeight(ROW_HEIGHT)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
  r.openBar = r:CreateTexture(nil, "ARTWORK")
  r.openBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
  r.openBar:SetPoint("TOPLEFT")
  r.openBar:SetPoint("BOTTOMLEFT")
  r.openBar:SetWidth(2)
  r.steps = {}
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = T:Text(r, 12)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.cells = {}
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, button)
    -- Vendor flips: the only step is buying, so a click goes straight to the item on
    -- the auction house. Right-click (or shift-click) opens the details as before.
    local s = self.shuffle
    if main.view == "flips" and button == "LeftButton" and not IsShiftKeyDown() and s.buys and s.buys[1] then
      local b = s.buys[1]
      if ns:SearchAuctionHouse(b.id) then
        ns:Print(("%s: buy up to %s at %s or less each."):format(ns.ItemName(b.id) or "?", b.listed or "?",
          ns.Money(s.maxBuy or b.price)))
      else
        ns:Print("Open the auction house, then click a flip to search for it. Right-click a flip for details.")
      end
      return
    end
    openKeys[s.key] = not openKeys[s.key]
    layoutShuffles()
  end)
  rows[i] = r
  return r
end

-- A step icon. Hovering it names that step; clicking it opens the row like the rest.
local function stepIcon(r, j)
  if not r.steps[j] then
    local b = CreateFrame("Frame", nil, r)
    b:SetSize(16, 16)
    b:EnableMouse(true)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.text or "", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnMouseUp", function() r:Click() end)
    r.steps[j] = b
  end
  return r.steps[j]
end

local function cell(r, key)
  if not r.cells[key] then
    local fs = T:Text(r, 12)
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    r.cells[key] = fs
  end
  return r.cells[key]
end

local function fillRow(r, s, lay, index, width)
  r:SetWidth(width)
  r.shuffle = s
  r.stripe:SetShown(index % 2 == 0)
  r.openBar:SetShown(openKeys[s.key] or false)

  local icons = lay.route and ns:StepIcons(s.opt) or {}
  local fit = lay.route and math.floor(lay.route.w / 19) or 0
  for j, st in ipairs(icons) do
    local b = stepIcon(r, j)
    b.tex:SetTexture(st[1])
    b.text = ("%d. %s"):format(j, st[2])
    b:ClearAllPoints()
    b:SetPoint("LEFT", r, "LEFT", lay.route.x + (j - 1) * 19, 0)
    b:SetShown(j <= fit)
  end
  for j = #icons + 1, #r.steps do r.steps[j]:Hide() end

  r.icon:SetTexture(ns:ItemIcon(mainItem(s)))
  r.icon:ClearAllPoints()
  r.icon:SetPoint("LEFT", r, "LEFT", lay.name.x, 0)
  r.name:ClearAllPoints()
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetWidth(lay.name.w - 26)
  r.name:SetText(ns:ShuffleName(s))

  local runs = ns:ShuffleRuns(s)
  local values = {
    steps = tostring(#ns:StepIcons(s.opt)),
    profit = "|cff7fd39c" .. ns.Money(s.profit) .. "|r",
    ret = ("%d%%"):format(math.floor(ns:ShuffleReturn(s) * 100 + 0.5)),
    hour = ns.Money(math.floor(s.perHour / 100) * 100),
    runs = runs and tostring(runs) or dim("no limit"),
    total = runs and ns.Money(s.profit * runs) or "",
  }
  for key, fs in pairs(r.cells) do fs:SetShown(lay[key] ~= nil) end
  for key, text in pairs(values) do
    if lay[key] then
      local fs = cell(r, key)
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", r, "LEFT", lay[key].x, 0)
      fs:SetWidth(lay[key].w)
      fs:SetText(text)
      fs:Show()
    end
  end
end

-- The opened part under a row: what to buy on the left, the steps on the right.
local function getDetail(i)
  local d = details[i]
  if d then return d end
  d = CreateFrame("Frame", nil, main.table.content)
  T:Fill(d, { 1, 1, 1, 0.035 })
  d.buyTitle = T:Text(d, 11, T.accent)
  d.buyTitle:SetText("What to buy")
  d.stepTitle = T:Text(d, 11, T.accent)
  d.stepTitle:SetText("Steps")
  d.steps = T:Text(d, 11, { 1, 1, 1, 0.85 })
  d.steps:SetJustifyH("LEFT")
  d.steps:SetJustifyV("TOP")
  d.steps:SetSpacing(3)
  d.profit = T:Text(d, 11)
  d.profit:SetJustifyH("LEFT")
  d.lines = {}
  details[i] = d
  return d
end

local function detailLine(d, j)
  local l = d.lines[j]
  if not l then
    l = { icon = d:CreateTexture(nil, "ARTWORK"), text = T:Text(d, 11) }
    l.icon:SetSize(14, 14)
    l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    l.text:SetJustifyH("LEFT")
    l.text:SetWordWrap(false)
    d.lines[j] = l
  end
  return l
end

local MAX_BUY_LINES = 12

-- noSteps: vendor flips, where the only step is always "sell to a vendor".
local function fillDetail(d, s, width, noSteps)
  d:SetWidth(width)
  d.shuffle = s
  local half = noSteps and (width - 8) or math.floor(width * 0.5)
  d.stepTitle:SetShown(not noSteps)
  d.steps:SetShown(not noSteps)
  d.buyTitle:ClearAllPoints()
  d.buyTitle:SetPoint("TOPLEFT", 14, -8)
  d.stepTitle:ClearAllPoints()
  d.stepTitle:SetPoint("TOPLEFT", half + 8, -8)

  local buys, y = ns:ShuffleBuys(s), 26
  local shown = 0
  for j, b in ipairs(buys) do
    if j > MAX_BUY_LINES then break end
    shown = j
    local l = detailLine(d, j)
    l.icon:SetTexture(ns:ItemIcon(b.id))
    l.icon:ClearAllPoints()
    l.icon:SetPoint("TOPLEFT", 14, -y)
    l.icon:Show()
    l.text:ClearAllPoints()
    l.text:SetPoint("LEFT", l.icon, "RIGHT", 6, 0)
    l.text:SetWidth(half - 44)
    l.text:SetText(("%s%s at %s  %s"):format(b.qty > 1 and (b.qty .. " x ") or "", itemName(b.id),
      ns.Money(b.price), dim(b.listed and (b.listed .. " listed") or "from a vendor")))
    l.text:Show()
    y = y + 18
  end
  if #buys > MAX_BUY_LINES then
    shown = shown + 1
    local l = detailLine(d, shown)
    l.icon:Hide()
    l.text:ClearAllPoints()
    l.text:SetPoint("TOPLEFT", 34, -y)
    l.text:SetText(dim(("and %d more"):format(#buys - MAX_BUY_LINES)))
    l.text:Show()
    y = y + 18
  end
  for j = shown + 1, #d.lines do d.lines[j].icon:Hide(); d.lines[j].text:Hide() end

  d.steps:ClearAllPoints()
  d.steps:SetPoint("TOPLEFT", half + 8, -26)
  d.steps:SetWidth(width - half - 20)
  d.steps:SetText(noSteps and "" or ns:ShuffleSteps(s))

  local h = math.max(y, noSteps and 0 or (26 + d.steps:GetStringHeight())) + 8
  d.profit:ClearAllPoints()
  d.profit:SetPoint("TOPLEFT", 14, -h)
  d.profit:SetWidth(width - 28)
  d.profit:SetText(ns:ShuffleProfitLine(s))
  d:SetHeight(h + 22)
end

layoutShuffles = function()
  local f, data = main.table, main.shuffles
  if not data then return end
  local flips = main.view == "flips"
  local view = flips and "flips" or "shuffles"
  local width = math.max(f:GetWidth(), 500)
  local top = 0

  -- Sub-tabs with counts, and "use recipes from" (Shuffles only)
  for key, b in pairs(f.subtabs) do
    b:SetShown(not flips)
    b:SetText(("%s  %s"):format(b.base, dim(#data[key])))
    b:SetWidth(b:GetFontString():GetStringWidth() + 24)
    b:SetSelected(key == subtab)
  end
  f.charLabel:SetShown(not flips)
  f.charBtn:SetShown(not flips)
  f.subLine:SetShown(not flips)
  if not flips then
    top = 38
    f.charLabel:ClearAllPoints()
    f.charLabel:SetPoint("TOPLEFT", 4, -(top + 4))
    f.charBtn:ClearAllPoints()
    f.charBtn:SetPoint("LEFT", f.charLabel, "RIGHT", 10, 0)
    -- This realm and faction only, you first.
    local keys, on = {}, 0
    for _, key in ipairs(sortedCharKeys()) do
      if ns:SameMarketChar(key) then keys[#keys + 1] = key end
    end
    for i, key in ipairs(keys) do
      local cb = getBox(i)
      cb.label:SetText(classColored(ns.db.chars[key]))
      cb:ClearAllPoints()
      cb:SetPoint("TOPLEFT", f.charMenu, "TOPLEFT", 10, -(8 + (i - 1) * 22))
      cb:SetChecked(not ns.db.settings.skipChars[key])
      cb.charKey = key
      cb:Show()
      if cb:GetChecked() then on = on + 1 end
    end
    for i = #keys + 1, #boxes do boxes[i]:Hide() end
    f.charMenu:SetSize(220, 12 + #keys * 22)
    f.charBtn:SetText(on == #keys and ("All %d characters"):format(#keys)
      or (on == 0 and "|cffee8597No characters|r" or ("%d of %d characters"):format(on, #keys)))
    top = top + 32
  end

  -- Header
  local cols = COLUMNS[view]
  local lay = columnLayout(cols, width - 12)
  local sort = sortBy[view]
  f.header:ClearAllPoints()
  f.header:SetPoint("TOPLEFT", 0, -top)
  f.header:SetPoint("TOPRIGHT", 0, -top)
  for i, c in ipairs(cols) do
    local h = getHeaderCell(i)
    h.key, h.label, h.tip = c.key, c.label, c.tip
    h:ClearAllPoints()
    h:SetPoint("LEFT", f.header, "LEFT", lay[c.key].x, 0)
    h:SetSize(lay[c.key].w, 22)
    local sorted = sort.key == c.key
    h.fs:SetJustifyH(c.width and c.key ~= "route" and "RIGHT" or "LEFT")
    h.fs:SetText(c.label .. (sorted and (sort.desc and " v" or " ^") or ""))
    local col = sorted and { T.accent[1], T.accent[2], T.accent[3], 1 } or T.dim
    h.fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    h:Show()
  end
  for i = #cols + 1, #headerCells do headerCells[i]:Hide() end
  top = top + 24

  -- Rows, sorted
  f.sf:ClearAllPoints()
  f.sf:SetPoint("TOPLEFT", 0, -top)
  f.sf:SetPoint("BOTTOMRIGHT")
  local content = f.content
  content:SetWidth(width - 12)
  local list = flips and data.flips or data[subtab]
  local items = {}
  for i, s in ipairs(list) do items[i] = s end
  local get = SORT_VALUE[sort.key]
  table.sort(items, function(a, b)
    local va, vb = get(a), get(b)
    if va == vb then return a.key < b.key end
    if sort.desc then return va > vb end
    return va < vb
  end)

  local y, nRows, nDetails = 0, 0, 0
  for i = 1, math.min(#items, MAX_ROWS) do
    local s = items[i]
    nRows = nRows + 1
    local r = getRow(nRows)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    fillRow(r, s, lay, i, width - 12)
    r:Show()
    y = y + ROW_HEIGHT
    if openKeys[s.key] then
      nDetails = nDetails + 1
      local d = getDetail(nDetails)
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      fillDetail(d, s, width - 12, flips)
      d:Show()
      y = y + d:GetHeight() + 4
    end
  end
  for i = nRows + 1, #rows do rows[i]:Hide() end
  for i = nDetails + 1, #details do details[i]:Hide() end
  f.empty:SetShown(#items == 0)
  content:SetHeight(math.max(y, 30))
  f.sf.UpdateScrollBar()
end

-- Item names and icons arrive from the game a moment after they're first asked for.
-- Redraw the table once they do, so "item 4470" becomes "Simple Wood".
local redrawQueued = false
ns:On("GET_ITEM_INFO_RECEIVED", function(id)
  -- Only for names this addon showed as "item N" (other addons load items all the time).
  if not ns.nameWanted[id] then return end
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
  -- Short, so it fits the smallest window (the tabs' own tips say the rest).
  main.shuffleInfo:SetText(("%d shuffles, %d vendor flips (%s). %s"):format(
    #vendor + #ah + #oneOff, #flips, date("%H:%M"),
    main.view == "flips" and "Click to search the AH, right-click for details." or "Click a column to sort, a row for details."))
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
    -- "in": it's a countdown to the next one Blizzard allows, not how long a scan takes.
    label = ("Full scan in %d:%02d"):format(math.floor(wait / 60), wait % 60)
  end
  for _, b in ipairs({ main and main.fullBtn or false, ns.ahFullButton or false, ns.panelFullButton or false }) do
    if b then
      b:SetText(label)
      b:SetEnabled(ready and ns:IsAHOpen() and not ns.Scan.active)
    end
  end
end

-- Tick the countdown once a second while a button showing it is on screen.
ns:OnReady(function()
  C_Timer.NewTicker(1, function()
    if (main and main:IsShown()) or (ns.ahFullButton and ns.ahFullButton:IsVisible())
      or (ns.panelFullButton and ns.panelFullButton:IsVisible()) then
      ns:UpdateFullScanButtons()
    end
  end)
end)

-- Plain text in the status corner (the flip watch's countdown between checks).
-- The Buy queue panel shows the same line (ns.statusText).
function ns:SetStatusText(text)
  ns.statusText = text or ""
  if main and main.status then main.status:SetText(ns.statusText) end
  if ns.RefreshQueueView then ns:RefreshQueueView() end
end

function ns:UpdateScanStatus(done, total)
  ns:SetStatusText(total and total > 0 and ("Scanning: %d of %d"):format(done, total) or "")
  if done and total and done >= total then
    C_Timer.After(3, function() ns:SetStatusText("") end)
  end
end

-- While the Buy queue panel is open beside the auction house, its own scan buttons do
-- the job, so the ones under the auction house window are hidden (owner, October 3).
function ns:UpdateAHScanButtons()
  local docked = ns.SidePanelDocked and ns:SidePanelDocked()
  for _, b in ipairs({ ns.ahButton or false, ns.ahFullButton or false, ns.ahWatchButton or false }) do
    if b then b:SetShown(not docked) end
  end
  -- The Buy queue button says it closes the panel while it's open, and stays lit.
  local b = ns.ahFinderButton
  if b then
    b:SetText(docked and "Close buy queue" or "Buy queue")
    if docked then b:LockHighlight() else b:UnlockHighlight() end
  end
end

-- Scan buttons on the auction house window itself, in Blizzard's style to match it.
function ns:OnAHShow()
  local ah = AuctionHouseFrame or AuctionFrame
  if ah and not ns.ahButton then
    -- Just below the window's bottom-right corner, level with Blizzard's Buy/Sell/Auctions
    -- tabs. Inside the window they covered the bid and buyout boxes on item pages.
    ns.ahButton = blizzButton(ah, "Scan materials", 120, function() ns.Scan:Start("watch") end)
    -- Auctionator adds its own tabs (Shopping, Selling, Cancelling, Auctionator) along the
    -- bottom, reaching the right side: go one row lower so we don't cover them.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local auctionator = Auctionator ~= nil or (isLoaded and isLoaded("Auctionator"))
    ns.ahButton:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", -4, auctionator and -34 or -2)
    ns.ahButton:SetFrameLevel(ah:GetFrameLevel() + 20)
    ns.ahFullButton = blizzButton(ah, "Full scan", 130, function() ns.Scan:Start("full") end)
    ns.ahFullButton:SetPoint("RIGHT", ns.ahButton, "LEFT", -4, 0)
    ns.ahFullButton:SetFrameLevel(ah:GetFrameLevel() + 20)
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

  -- The text in a framed box under the help, with the addon's own scroll bar (owner's
  -- test, October 3: the text ran over the help, and the old scroll bar looked out of
  -- place). A click anywhere in the box puts the cursor in it.
  local box = CreateFrame("Frame", nil, io)
  box:SetPoint("TOPLEFT", io.help, "BOTTOMLEFT", 0, -10)
  box:SetPoint("BOTTOMRIGHT", -14, 48)
  T:Fill(box, { 0, 0, 0, 0.35 })
  T:Border(box)
  local sf, content = T:Scroll(box)
  sf:SetPoint("TOPLEFT", 8, -8)
  sf:SetPoint("BOTTOMRIGHT", -4, 8)
  local eb = CreateFrame("EditBox", nil, content)
  eb:SetMultiLine(true)
  eb:SetFont(T.font, 12, "")
  eb:SetTextColor(1, 1, 1, 1)
  eb:SetPoint("TOPLEFT")
  eb:SetPoint("RIGHT", content, "RIGHT", -6, 0)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(0)
  eb:SetScript("OnEscapePressed", function() io:Hide() end)
  local hint = T:Text(box, 12, T.section)
  hint:SetPoint("TOPLEFT", 10, -9)
  hint:SetText("Paste here (Ctrl+V)")
  local function fit()
    content:SetHeight(math.max(eb:GetHeight(), sf:GetHeight()))
    sf.UpdateScrollBar()
    hint:SetShown(eb:GetText() == "" and not eb:HasFocus())
  end
  eb:SetScript("OnTextChanged", fit)
  eb:SetScript("OnEditFocusGained", fit)
  eb:SetScript("OnEditFocusLost", fit)
  -- Keep the cursor in view while typing or pasting past the bottom.
  eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
    local top, view = sf:GetVerticalScroll(), sf:GetHeight()
    y = -y
    if y < top then sf:SetVerticalScroll(y)
    elseif y + h > top + view then sf:SetVerticalScroll(math.min(y + h - view, sf:GetVerticalScrollRange())) end
    sf.UpdateScrollBar()
  end)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() eb:SetFocus() end)
  io.eb = eb

  io.action = T:Button(io, "Import", 110, function() end)
  io.action:SetPoint("BOTTOMRIGHT", -14, 12)
  return io
end

-- The same text window for other things to copy or paste (shopping lists). With
-- actionLabel and onAction(text), a button acts on what was pasted; onAction returns
-- ok, message.
-- Tabs along the top of the window (a shopping list's Share and Import, owner's test
-- October 3: one window for both): tabs = { current = index, { label, fn }, ... }, or
-- nil for none. The help moves down under them.
local function setTabs(f, tabs)
  f.tabChoices = f.tabChoices or {}
  for _, c in pairs(f.tabChoices) do c:Hide() end
  f.help:ClearAllPoints()
  f.help:SetPoint("RIGHT", f, "RIGHT", -14, 0)
  if not tabs then
    f.help:SetPoint("TOPLEFT", 14, -42)
    return
  end
  local labels = {}
  for i, t in ipairs(tabs) do labels[i] = t[1] end
  local key = table.concat(labels, "|")
  local c = f.tabChoices[key]
  if not c then
    local opts = {}
    for i, t in ipairs(tabs) do opts[i] = { value = i, label = t[1] } end
    c = T:Choice(f, opts, function(i) if c.tabs and c.tabs[i] then c.tabs[i][2]() end end)
    c:SetPoint("TOPLEFT", 14, -40)
    f.tabChoices[key] = c
  end
  c.tabs = tabs
  c:SetValue(tabs.current or 1)
  c:Show()
  f.help:SetPoint("TOPLEFT", 14, -70)
end

function ns:ShowTextWindow(title, help, text, actionLabel, onAction, tabs)
  local f = ioWindow()
  setTabs(f, tabs)
  f.title:SetText(title)
  f.help:SetText(help)
  f.eb:SetText(text or "")
  if actionLabel then
    f.action:SetText(actionLabel)
    f.action:SetScript("OnClick", function()
      local ok, msg = onAction(f.eb:GetText())
      if msg then ns:Print(msg) end
      if ok then f:Hide() end
    end)
    f.action:Show()
  else
    f.action:Hide()
  end
  f:Show()
  f:Raise()   -- in front of the main window, even when already open (owner's test, October 4)
  f.eb:SetFocus()
  if text and text ~= "" then f.eb:HighlightText() end
end

-- Export, Import and Prices as text share one window, with tabs to switch.
local function dataTabs(current)
  return { current = current,
    { "Export", function() ns:ShowExport() end },
    { "Import", function() ns:ShowImport() end },
    { "Prices as text", function() ns:ShowPricesCSV() end } }
end

function ns:ShowExport()
  local f = ioWindow()
  setTabs(f, dataTabs(1))
  f.title:SetText("Export")
  f.help:SetText("Press Ctrl+A, then Ctrl+C to copy. Paste it into Import on your other account, or send it to Claude.")
  f.eb:SetText(ns:Export())
  f.action:Hide()
  f:Show()
  f:Raise()   -- in front of the main window, even when already open (owner's test, October 4)
  f.eb:SetFocus()
  f.eb:HighlightText()
end

function ns:ShowImport()
  local f = ioWindow()
  setTabs(f, dataTabs(2))
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
  f:Raise()   -- in front of the main window, even when already open (owner's test, October 4)
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
  setTabs(f, dataTabs(3))
  f.title:SetText("Prices as text")
  f.help:SetText("Press Ctrl+A, then Ctrl+C. Paste this into a chat with Claude to check flips at today's prices.")
  f.eb:SetText(ns:PricesCSV())
  f.action:Hide()
  f:Show()
  f:Raise()   -- in front of the main window, even when already open (owner's test, October 4)
  f.eb:SetFocus()
  f.eb:HighlightText()
end
ns.RefreshShuffles = ns.Timed("Shuffles table", ns.RefreshShuffles)
ns.RefreshUI = ns.Timed("Ledger window", ns.RefreshUI)
