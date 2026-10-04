local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Dashboard: a gold graph, and Sales / Expenses / Profit for a range of time,
-- for one character or all of them. Built from History.lua's records.
---------------------------------------------------------------------------
local DAY = 86400
local RANGES = {
  { key = "day", label = "Day", secs = DAY },
  { key = "week", label = "Week", secs = 7 * DAY },
  { key = "month", label = "Month", secs = 30 * DAY },
  { key = "3months", label = "3 months", secs = 91 * DAY },
  { key = "year", label = "Year", secs = 365 * DAY },
  { key = "all", label = "All time" },
}
local SALES = { ahSale = true, vendorSell = true }
local EXPENSES = { ahBuy = true, ahFee = true, vendorBuy = true, repair = true }
local POINTS = 60
local PAD_LEFT, PAD_RIGHT, PAD_TOP, PAD_BOTTOM = 58, 12, 28, 22

local function dim(t) return "|cff888888" .. t .. "|r" end

-- "12g", "11g 20s", "85s" or "40c", for graph labels. Silver is kept under 100g, so a
-- day where gold only moved between 11g 11s and 11g 35s doesn't label every line "11g".
local function short(c)
  if c >= 10000 then
    local g, s = math.floor(c / 10000), math.floor(c % 10000 / 100)
    if g < 100 and s > 0 then return ("%dg %ds"):format(g, s) end
    return ("%dg"):format(g)
  end
  if c >= 100 then return ("%ds"):format(math.floor(c / 100)) end
  return ("%dc"):format(c)
end

local function settings()
  local d = ns.db.settings.dashboard
  d.char = d.char or "all"
  d.range = d.range or "week"
  return d
end

local function chosenKeys()
  local want, keys = settings().char, {}
  for k in pairs(ns.db.chars) do
    -- All: this ruleset and faction only (CharacterOptions).
    if (want == "all" and ns:SameMarketChar(k)) or want == k then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

-- Start and end of the chosen range, in seconds.
local function timeRange(keys)
  local now, secs = time(), nil
  for _, r in ipairs(RANGES) do if r.key == settings().range then secs = r.secs end end
  if secs then return now - secs, now end
  local first
  for _, k in ipairs(keys) do
    for h in pairs(ns.db.gold[k] or {}) do if not first or h < first then first = h end end
  end
  return first and math.min(first * 3600, now - 3600) or now - DAY, now
end

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
-- Gold at POINTS evenly spaced times: the last known value for each character, added up.
local function goldSeries(keys, from, to)
  local sorted = {}
  for _, k in ipairs(keys) do
    local hs = {}
    for h in pairs(ns.db.gold[k] or {}) do hs[#hs + 1] = h end
    table.sort(hs)
    sorted[k] = hs
  end
  local pts = {}
  for i = 0, POINTS - 1 do
    local t = from + (to - from) * i / (POINTS - 1)
    local hour = math.floor(t / 3600)
    local total, any = 0, false
    for _, k in ipairs(keys) do
      local hs, lo, hi, found = sorted[k], 1, #sorted[k], nil
      while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if hs[mid] <= hour then found, lo = mid, mid + 1 else hi = mid - 1 end
      end
      if found then total, any = total + ns.db.gold[k][hs[found]], true end
    end
    pts[#pts + 1] = { t = t, v = any and total or nil }
  end
  return pts
end

local function itemLabel(id) return id and ns.ItemName(id) or "Unknown item" end

-- Sales, expenses, days covered, and the top items for each.
local function totals(keys, from, to)
  local keyset = {}
  for _, k in ipairs(keys) do keyset[k] = true end
  local fromDay, toDay = ns.LocalDay(from), ns.LocalDay(to)
  local sales, expenses, firstDay = 0, 0, nil
  for _, k in ipairs(keys) do
    for day, src in pairs(ns.db.money[k] or {}) do
      if day >= fromDay and day <= toDay then
        if not firstDay or day < firstDay then firstDay = day end
        for s, amt in pairs(src) do
          if SALES[s] then sales = sales + amt elseif EXPENSES[s] then expenses = expenses + amt end
        end
      end
    end
  end

  local sold, bought = {}, {}
  local function add(t, name, amt) t[name] = (t[name] or 0) + amt end
  for _, e in ipairs(ns.db.sales) do
    if e.t >= from and keyset[e.c] and e.n then add(sold, e.n, e.a) end
  end
  for _, e in ipairs(ns.db.vendorLog) do
    if e.t >= from and keyset[e.c] and e.id then add(e.s == "sell" and sold or bought, itemLabel(e.id), e.a) end
  end
  for _, e in ipairs(ns.db.purchases) do
    if e.t >= from and keyset[e.c] then add(bought, itemLabel(e.id), e.a) end
  end
  -- Older than 30 days: monthly totals per item (History.lua foldLedger).
  local months = {}
  for _, m in ipairs(ns.db.ledgerMonths or {}) do
    if m.t >= from and keyset[m.c] then
      months[#months + 1] = m
      local name = m.id and itemLabel(m.id) or m.n
      if name then add((m.k == "sale" or m.k == "vsell") and sold or bought, name, m.a) end
    end
  end
  local function top(t)
    local name, best
    for n, v in pairs(t) do if not best or v > best then name, best = n, v end end
    return name
  end
  local net = {}
  for n, v in pairs(sold) do net[n] = v - (bought[n] or 0) end

  -- Auction house only (as in TSM): how many sales and purchases, and the biggest
  -- single one of each. Vendor trades would swamp these (every oil sold counts).
  local nSales, nBuys, bigSale, bigBuy = 0, 0, nil, nil
  for _, e in ipairs(ns.db.sales) do
    if e.t >= from and keyset[e.c] and e.n then
      nSales = nSales + 1
      if not bigSale or e.a > bigSale.a then bigSale = { n = e.n, a = e.a } end
    end
  end
  for _, e in ipairs(ns.db.purchases) do
    if e.t >= from and keyset[e.c] then
      nBuys = nBuys + 1
      if not bigBuy or e.a > bigBuy.a then bigBuy = { n = itemLabel(e.id), a = e.a } end
    end
  end
  for _, m in ipairs(months) do
    local name = m.id and itemLabel(m.id) or m.n
    if m.k == "sale" then
      nSales = nSales + m.cnt
      if not bigSale or m.mx > bigSale.a then bigSale = { n = name, a = m.mx } end
    elseif m.k == "buy" then
      nBuys = nBuys + m.cnt
      if not bigBuy or m.mx > bigBuy.a then bigBuy = { n = name, a = m.mx } end
    end
  end

  local days = math.max(1, toDay - math.max(fromDay, firstDay or toDay) + 1)
  return {
    sales = sales, expenses = expenses, profit = sales - expenses, days = days,
    topSold = top(sold), topBought = top(bought), topProfit = top(net),
    nSales = nSales, nBuys = nBuys, bigSale = bigSale, bigBuy = bigBuy,
  }
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
local function box(parent, title, rows)
  local b = CreateFrame("Frame", nil, parent)
  T:Fill(b, { 1, 1, 1, 0.03 })
  T:Border(b)
  b.title = T:Text(b, 12, T.accent)
  b.title:SetPoint("TOPLEFT", 10, -8)
  b.title:SetText(title)
  b.rows = {}
  for i = 1, rows or 3 do
    local label = T:Text(b, 11, T.dim)
    label:SetPoint("TOPLEFT", 10, -10 - i * 18)
    local value = T:Text(b, 12)
    value:SetPoint("TOPRIGHT", -10, -10 - i * 18)
    value:SetPoint("LEFT", label, "RIGHT", 8, 0)
    value:SetJustifyH("RIGHT")
    value:SetWordWrap(false)
    b.rows[i] = { label = label, value = value }
  end
  function b:Set(lines)
    for i, row in ipairs(self.rows) do
      row.label:SetText(lines[i] and lines[i][1] or "")
      row.value:SetText(lines[i] and lines[i][2] or "")
    end
  end
  return b
end

local function money(v) return (v < 0 and "-" or "") .. ns.Money(math.abs(v)) end

---------------------------------------------------------------------------
-- The graph
---------------------------------------------------------------------------
local function pool(g, name, make)
  g[name] = g[name] or {}
  local p, used = g[name], 0
  return function()
    used = used + 1
    if not p[used] then p[used] = make() end
    p[used]:Show()
    return p[used]
  end, function()
    for i = used + 1, #p do p[i]:Hide() end
  end
end

local function drawGraph(g, pts, from, to, rangeKey)
  local w, h = g:GetWidth(), g:GetHeight()
  local plotW, plotH = w - PAD_LEFT - PAD_RIGHT, h - PAD_TOP - PAD_BOTTOM
  g.pts, g.plot = pts, { x = PAD_LEFT, w = plotW, h = plotH }

  local lo, hi, first, last
  for _, p in ipairs(pts) do
    if p.v then
      lo = lo and math.min(lo, p.v) or p.v
      hi = hi and math.max(hi, p.v) or p.v
      first = first or p.v
      last = p.v
    end
  end
  g.empty:SetShown(lo == nil)
  -- Each step is coloured by its own direction: green where gold went up, red where it
  -- went down, the accent where it stayed the same (owner: not the whole graph one colour).
  local UP, DOWN, FLAT = { 0.5, 0.83, 0.61 }, { 0.93, 0.52, 0.59 }, T.accent
  local nextCol, doneCols = pool(g, "cols", function()
    local t = g:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
    return t
  end)
  local nextLine, doneLines = pool(g, "lines", function()
    local l = g.CreateLine and g:CreateLine(nil, "OVERLAY")
    if l then l:SetThickness(2); l:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1) end
    return l or g:CreateTexture(nil, "OVERLAY")
  end)
  local nextLabel, doneLabels = pool(g, "labels", function() return T:Text(g, 10, T.dim) end)
  local nextGrid, doneGrid = pool(g, "grid", function()
    local t = g:CreateTexture(nil, "BORDER")
    t:SetColorTexture(1, 1, 1, 0.06)
    t:SetHeight(1)
    return t
  end)

  if lo then
    -- The scale always starts at 0g (owner's choice), so small moves look small.
    lo, hi = 0, math.max(hi * 1.1, 10000)
    g.scale = { lo = lo, hi = hi }
    local function y(v) return PAD_BOTTOM + (v - lo) / (hi - lo) * plotH end
    local function x(i) return PAD_LEFT + (i - 1) / (#pts - 1) * plotW end

    -- Grid lines and gold labels
    for i = 0, 3 do
      local v = lo + (hi - lo) * i / 3
      local line = nextGrid()
      line:ClearAllPoints()
      line:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", PAD_LEFT, y(v))
      line:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -PAD_RIGHT, y(v))
      local label = nextLabel()
      label:ClearAllPoints()
      label:SetPoint("RIGHT", g, "BOTTOMLEFT", PAD_LEFT - 6, y(v))
      label:SetText(short(v))
    end

    -- Filled columns and the line
    local colW = math.max(1, plotW / #pts)
    local prevX, prevY, prevV
    for i, p in ipairs(pts) do
      if p.v then
        local c = (prevV and p.v > prevV and UP) or (prevV and p.v < prevV and DOWN) or FLAT
        prevV = p.v
        local col = nextCol()
        col:SetColorTexture(c[1], c[2], c[3], 0.18)
        col:ClearAllPoints()
        col:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", x(i) - colW / 2, PAD_BOTTOM)
        col:SetSize(colW, math.max(1, y(p.v) - PAD_BOTTOM))
        if prevX and g.CreateLine then
          local l = nextLine()
          l:SetColorTexture(c[1], c[2], c[3], 1)
          l:SetStartPoint("BOTTOMLEFT", g, prevX, prevY)
          l:SetEndPoint("BOTTOMLEFT", g, x(i), y(p.v))
        end
        prevX, prevY = x(i), y(p.v)
      end
    end
  end

  -- Dates along the bottom
  local fmt = rangeKey == "day" and "%H:%M" or "%b %d"
  for i = 0, 3 do
    local t = from + (to - from) * i / 3
    local label = nextLabel()
    label:ClearAllPoints()
    label:SetPoint("TOP", g, "BOTTOMLEFT", PAD_LEFT + plotW * i / 3, PAD_BOTTOM - 4)
    label:SetText(date(fmt, t))
  end

  doneCols(); doneLines(); doneLabels(); doneGrid()
end

-- While the mouse is over the graph: a marker and the gold at that point.
local function hoverGraph(g)
  local mx = GetCursorPosition() / g:GetEffectiveScale() - g:GetLeft()
  local pts, plot = g.pts, g.plot
  if not pts or not plot or not g.scale then return end
  local i = math.floor((mx - plot.x) / plot.w * (#pts - 1) + 1.5)
  i = math.max(1, math.min(#pts, i))
  local p = pts[i]
  g.marker:ClearAllPoints()
  g.marker:SetPoint("BOTTOM", g, "BOTTOMLEFT", plot.x + (i - 1) / (#pts - 1) * plot.w, PAD_BOTTOM)
  g.marker:SetHeight(plot.h)
  g.marker:Show()
  GameTooltip:SetOwner(g, "ANCHOR_CURSOR")
  GameTooltip:AddLine(date("%b %d %H:%M", p.t), 1, 1, 1)
  GameTooltip:AddLine(p.v and ns.Money(p.v) or "No record yet", 0.85, 0.85, 0.85)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function ns:BuildDashboard(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  f.charLabel = T:Text(f, 12, T.dim)
  f.charLabel:SetPoint("TOPLEFT", 2, -4)
  f.charLabel:SetText("Characters")
  f.rangeChoice = T:Choice(f, (function()
    local o = {}
    for _, r in ipairs(RANGES) do o[#o + 1] = { value = r.key, label = r.label } end
    return o
  end)(), function(v) settings().range = v; ns:RefreshDashboard(f) end)
  f.rangeChoice:SetPoint("TOPRIGHT", 0, 0)

  local g = CreateFrame("Frame", nil, f)
  T:Fill(g, { 1, 1, 1, 0.03 })
  T:Border(g)
  g.title = T:Text(g, 12, T.accent)
  g.title:SetPoint("TOPLEFT", 10, -8)
  g.title:SetText("Gold")
  g.empty = T:Text(g, 12, T.dim)
  g.empty:SetPoint("CENTER")
  g.empty:SetText("No gold recorded in this range yet.")
  g.marker = g:CreateTexture(nil, "OVERLAY")
  g.marker:SetColorTexture(1, 1, 1, 0.25)
  g.marker:SetWidth(1)
  g.marker:Hide()
  g:EnableMouse(true)
  g:SetScript("OnEnter", function(self) self:SetScript("OnUpdate", hoverGraph) end)
  g:SetScript("OnLeave", function(self)
    self:SetScript("OnUpdate", nil)
    self.marker:Hide()
    GameTooltip:Hide()
  end)
  f.graph = g

  f.goldStats = box(f, "Gold", 2)
  f.activity = box(f, "Activity", 2)
  f.biggest = box(f, "Biggest on the auction house", 2)
  f.sales = box(f, "Sales")
  f.expenses = box(f, "Expenses")
  f.profit = box(f, "Profit")

  f.sessions = T:Text(f, 11)
  f.sessions:SetJustifyH("LEFT")
  f.sessions:SetJustifyV("TOP")
  f.sessions:SetSpacing(3)
  -- Start or stop a session (Sessions.lua) from here too.
  f.sessionBtn = T:Button(f, "Start a session", 120, function()
    if ns:GeneralSessionRunning() then ns:StopGeneralSession() else ns:StartGeneralSession() end
    ns:RefreshDashboard(f)
  end, 20)
  f.sessionBtn:GetFontString():SetFont(T.font, 11, "")
  return f
end

-- The character list for dropdowns (Dashboard, Ledger): All, then the character you're
-- on, then the rest by name (owner, October 3: a button each didn't fit).
function ns:CharacterOptions()
  -- "All characters" is this ruleset and faction: gold on another ruleset is another
  -- economy (owner's test, October 4: a PvP Orc's gold was in the totals). Characters
  -- elsewhere come last, with their realm or faction, to look at on their own.
  local me = ns.CharKey()
  local here, away = {}, {}
  for k in pairs(ns.db.chars) do
    if k ~= me then
      if ns:SameMarketChar(k) then here[#here + 1] = k else away[#away + 1] = k end
    end
  end
  local function name(k) return (ns.db.chars[k] and ns.db.chars[k].name) or k end
  local function byName(a, b) return name(a):lower() < name(b):lower() end
  table.sort(here, byName)
  table.sort(away, byName)
  local opts = { { value = "all", label = "All characters (this realm)" } }
  if ns.db.chars[me] then opts[#opts + 1] = { value = me, label = name(me) .. " (this one)" } end
  for _, k in ipairs(here) do opts[#opts + 1] = { value = k, label = name(k) } end
  local myRealm = GetRealmName and GetRealmName()
  for _, k in ipairs(away) do
    local c = ns.db.chars[k]
    local where = (c.realm and c.realm ~= myRealm and c.realm) or c.faction or "elsewhere"
    opts[#opts + 1] = { value = k, label = ("%s |cff888888(%s)|r"):format(name(k), where) }
  end
  return opts
end

local function charChoice(f)
  if not f.charChoice then
    f.charChoice = T:Dropdown(f, 200, function(v) settings().char = v; ns:RefreshDashboard(f) end)
    f.charChoice:SetPoint("LEFT", f.charLabel, "RIGHT", 10, 0)
  end
  f.charChoice:SetOptions(ns:CharacterOptions())
end

function ns:RefreshDashboard(f)
  if not f or not ns.db then return end
  local s = settings()
  if s.char ~= "all" and not ns.db.chars[s.char] then s.char = "all" end
  charChoice(f)
  f.charChoice:SetValue(s.char)
  f.rangeChoice:SetValue(s.range)

  -- Layout for the current size
  local W, H = f:GetWidth(), f:GetHeight()
  local top = 32
  -- The graph takes whatever the boxes and sessions don't need, so a bigger window
  -- shows a bigger graph instead of empty space (owner, October 3). Sessions get a
  -- fifth of the height, at least four lines.
  local sessionsH = math.max(70, math.floor(H * 0.2))
  local graphH = math.max(110, H - top - 10 - 76 - 98 - sessionsH)
  f.graph:ClearAllPoints()
  f.graph:SetPoint("TOPLEFT", 0, -top)
  f.graph:SetSize(W, graphH)
  local boxW = math.floor((W - 20) / 3)
  local function row(boxes, y, h)
    for i, b in ipairs(boxes) do
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", (i - 1) * (boxW + 10), -y)
      b:SetSize(boxW, h)
    end
  end
  local statsY = top + graphH + 10
  row({ f.goldStats, f.activity, f.biggest }, statsY, 66)
  local boxY = statsY + 76
  row({ f.sales, f.expenses, f.profit }, boxY, 88)
  f.sessions:ClearAllPoints()
  f.sessions:SetPoint("TOPLEFT", 2, -(boxY + 98))
  f.sessions:SetPoint("RIGHT", f, "RIGHT", -2, 0)
  -- In the top row beside the date range, lit while one runs (owner's test, October 3:
  -- "took me a second to find Start a session" down by the sessions list).
  local running = ns.GeneralSessionRunning and ns:GeneralSessionRunning()
  f.sessionBtn:ClearAllPoints()
  f.sessionBtn:SetPoint("RIGHT", f.rangeChoice, "LEFT", -12, 0)
  -- The character list narrows to fit before the button (owner's test, October 3: they
  -- overlapped at the smallest window size).
  local room = f:GetWidth() - f.rangeChoice:GetWidth() - 12 - f.sessionBtn:GetWidth() - 12
    - (f.charLabel:GetStringWidth() + 2 + 10)
  f.charChoice:SetWidth(math.max(110, math.min(200, room)))
  f.sessionBtn:SetText(running and "Stop the session" or "Start a session")
  f.sessionBtn:SetSelected(running)

  -- Numbers
  local keys = chosenKeys()
  local from, to = timeRange(keys)
  local pts = goldSeries(keys, from, to)
  drawGraph(f.graph, pts, from, to, s.range)
  local n = totals(keys, from, to)

  local lo, hi
  for _, p in ipairs(pts) do
    if p.v then lo = lo and math.min(lo, p.v) or p.v; hi = hi and math.max(hi, p.v) or p.v end
  end
  f.goldStats:Set({
    { "Highest", hi and ns.Money(hi) or dim("no record yet") },
    { "Lowest", lo and ns.Money(lo) or dim("no record yet") },
  })
  f.activity:Set({
    { "Auction sales per day", tostring(math.floor(n.nSales / n.days + 0.5)) },
    { "Auction purchases per day", tostring(math.floor(n.nBuys / n.days + 0.5)) },
  })
  f.biggest:Set({
    { "Sale", n.bigSale and (ns.Money(n.bigSale.a) .. " " .. dim(n.bigSale.n)) or dim("none yet") },
    { "Purchase", n.bigBuy and (ns.Money(n.bigBuy.a) .. " " .. dim(n.bigBuy.n)) or dim("none yet") },
  })
  f.sales:Set({
    { "Total", ns.Money(n.sales) },
    { "Per day", ns.Money(math.floor(n.sales / n.days)) },
    { "Top item", n.topSold or dim("none yet") },
  })
  f.expenses:Set({
    { "Total", ns.Money(n.expenses) },
    { "Per day", ns.Money(math.floor(n.expenses / n.days)) },
    { "Top item", n.topBought or dim("none yet") },
  })
  f.profit:Set({
    { "Total", "|cff" .. (n.profit >= 0 and "7fd39c" or "ee8597") .. money(n.profit) .. "|r" },
    { "Per day", money(math.floor(n.profit / n.days)) },
    { "Most profitable", n.topProfit or dim("none yet") },
  })

  -- Sessions
  local lines = { T:AccentCode() .. "Sessions|r" }
  local gs = ns.SessionTotals and ns:SessionTotals()
  if gs then
    lines[#lines + 1] = ("Running: %d min so far, gold %s, looted about %s."):format(math.floor(gs.secs / 60),
      money(gs.gained), ns.Money(gs.loot))
  end
  local st = ns.SessionStats and ns:SessionStats()
  if st then
    lines[#lines + 1] = ("Running: %s, %d runs, profit %s so far. %s"):format(
      ns.db.session.name, st.runs, money(st.profit), dim("/fl session to open it"))
  end
  local list = ns.db.sessions
  for i = #list, math.max(1, #list - 20), -1 do   -- as many as fit (trimmed below)
    local x = list[i]
    local mins = math.floor((x.stop - x.t) / 60)
    if x.kind == "general" then
      lines[#lines + 1] = ("%s  Session: %s, gold %s, looted about %s"):format(dim(date("%b %d %H:%M", x.t)),
        mins < 1 and "under a minute" or (mins .. " min"), money(x.earned - x.spent), ns.Money(x.loot or 0))
    else
      lines[#lines + 1] = ("%s  %s: %d runs in %d min, profit %s"):format(dim(date("%b %d %H:%M", x.t)),
        x.name, x.runs, mins, money(x.earned - x.spent))
    end
  end
  if #list == 0 and not st and not gs then
    lines[#lines + 1] = dim("None yet. Start a session to count what your time is worth, or click Work it on a shuffle.")
  end
  -- Only as many lines as fit below the boxes.
  local fit = math.max(1, math.floor((H - (boxY + 98)) / 14))
  while #lines > fit do table.remove(lines) end
  f.sessions:SetText(table.concat(lines, "\n"))
end

ns.RefreshDashboard = ns.Timed("Dashboard", ns.RefreshDashboard)
