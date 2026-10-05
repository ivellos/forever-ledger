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
local PAD_LEFT, PAD_RIGHT, PAD_TOP, PAD_BOTTOM = 58, 12, 8, 22

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
    if ns:CharChoiceHas(want, k) then keys[#keys + 1] = k end
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
          if SALES[s] then sales = sales + amt elseif EXPENSES[s] then expenses = expenses + amt
          elseif s == "ahDepositBack" then expenses = expenses - amt end   -- a deposit back offsets the fee paid
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
  local UP, DOWN, FLAT = { 0.5, 0.83, 0.61 }, { 0.93, 0.52, 0.59 }, T.theme.title or T.accent
  local nextCol, doneCols = pool(g, "cols", function()
    local t = g:CreateTexture(nil, "ARTWORK")
    -- Not rounded to whole screen pixels, or neighbouring strips can round apart and leave
    -- thin seams at some Size settings (owner's test, October 4).
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
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

    -- The fill and the line. One soft gold fill under the line (the mockup); the line
    -- keeps the direction colours (owner, October 3). The fill is drawn strip by strip
    -- between neighbouring points, so it starts and ends where the line does (owner's
    -- test, October 4: it overhung both ends), in a solid colour (gold blended into the
    -- background) so strips can overlap a pixel without seams.
    local gold = T.theme.title or T.accent
    local bg = T.bg
    local fr, fgc, fb = bg[1] * 0.88 + gold[1] * 0.12, bg[2] * 0.88 + gold[2] * 0.12, bg[3] * 0.88 + gold[3] * 0.12
    local lastI = 0
    for i, p in ipairs(pts) do if p.v then lastI = i end end
    local prevX, prevY, prevV
    for i, p in ipairs(pts) do
      if p.v then
        local c = (prevV and p.v > prevV and UP) or (prevV and p.v < prevV and DOWN) or FLAT
        prevV = p.v
        if prevX then
          local col = nextCol()
          col:SetColorTexture(fr, fgc, fb, 1)
          col:ClearAllPoints()
          col:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", prevX, PAD_BOTTOM)
          -- Its top follows the line: the strip reaches the higher point, and the corner
          -- under the lower one is pulled down to it (vertex offsets), so slopes leave no
          -- dark wedges (owner's test, October 4). Without vertex offsets: the lower height.
          local cy = y(p.v)
          local w = math.max(1, x(i) - prevX + (i < lastI and 2 or 0))
          local skew = col.SetVertexOffset ~= nil
          col:SetSize(w, math.max(1, (skew and math.max(prevY, cy) or math.min(prevY, cy)) - PAD_BOTTOM))
          if skew then
            -- 1 = upper left, 3 = upper right
            col:SetVertexOffset(1, 0, prevY < cy and -(cy - prevY) or 0)
            col:SetVertexOffset(3, 0, cy < prevY and -(prevY - cy) or 0)
          end
        end
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
-- The tab (redesign, October 4, from the owner-approved mockup): the character
-- dropdown, Start a session and the range on top; four headline tiles (gold now, profit,
-- sales, expenses); the gold graph in a card; Best and biggest and Activity cards; the
-- sessions as a table. Laid out for the fixed window (880 x 620); cards on every theme.
---------------------------------------------------------------------------
local function text(parent, size, color, justify)
  local fs = T:Text(parent, size, color)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

-- How the chosen range reads in words.
local PHRASE = { day = "today", week = "this week", month = "this month", ["3months"] = "in 3 months", year = "this year", all = "all time" }
local OVER = { day = "the day", week = "the week", month = "the month", ["3months"] = "3 months", year = "the year", all = "all time" }

local SESSION_COLS = {   -- x (left edge), width, justify
  { "When", 10, 110, "LEFT" }, { "Length", 124, 80, "LEFT" }, { "Gold", 210, 100, "RIGHT" },
  { "Looted", 320, 100, "RIGHT" }, { "An hour", 430, 100, "RIGHT" },
}

function ns:BuildDashboard(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  f.rangeChoice = T:Choice(f, (function()
    local o = {}
    for _, r in ipairs(RANGES) do o[#o + 1] = { value = r.key, label = r.label } end
    return o
  end)(), function(v) settings().range = v; ns:RefreshDashboard(f) end)
  f.rangeChoice:SetPoint("TOPRIGHT", 0, 0)
  -- Start or stop a session (Sessions.lua), beside the character dropdown, as the main action.
  f.sessionBtn = T:Button(f, "Start a session", 120, function()
    if ns:GeneralSessionRunning() then ns:StopGeneralSession() else ns:StartGeneralSession() end
    ns:RefreshDashboard(f)
  end, 22)
  f.sessionBtn:SetPrimary(true)

  -- Headline tiles
  f.tiles = {}
  for i = 1, 4 do f.tiles[i] = { label = text(f, 11, T.dim), value = text(f, 18), sub = text(f, 11, T.dim) } end

  -- The graph, in its card
  f.graphHead = text(f, 11)
  f.graphNote = text(f, 11, T.dim, "RIGHT")
  local g = CreateFrame("Frame", nil, f)
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

  -- Best and biggest, Activity
  local function rows(n)
    local list = {}
    for i = 1, n do list[i] = { l = text(f, 12), v = text(f, 12, nil, "RIGHT") } end
    return list
  end
  f.bestHead, f.actHead = text(f, 11), text(f, 11)
  f.best, f.act = rows(3), rows(3)

  -- Sessions
  f.sesHead = text(f, 11)
  f.sesNote = text(f, 11, T.dim, "RIGHT")
  f.sesCols = {}
  for i, c in ipairs(SESSION_COLS) do
    local fs = text(f, 11, T.dim, c[4])
    fs:SetText(c[1])
    f.sesCols[i] = fs
  end
  f.sesRows = {}
  f.sesEmpty = text(f, 12, T.dim)
  f.sesEmpty:SetText("None yet. Start a session to count what your time is worth.")
  return f
end

-- Which characters a choice in the dropdowns below covers: "all" = your faction on this
-- realm, "faction:Horde" = that faction on this realm, "realm" = this realm, both
-- factions; anything else is one character's key. Other realms never count (owner,
-- October 4: another ruleset is another economy).
function ns:CharChoiceHas(choice, key)
  local c = ns.db.chars[key]
  if not c then return false end
  local realm = GetRealmName and GetRealmName()
  local sameRealm = not c.realm or not realm or c.realm == realm
  if choice == "all" then return ns:SameMarketChar(key) end
  if choice == "realm" then return sameRealm end
  local fac = type(choice) == "string" and choice:match("^faction:(.+)$")
  if fac then return sameRealm and (c.faction or UnitFactionGroup("player")) == fac end
  return choice == key
end

function ns:IsCharChoice(choice)
  return choice == "all" or choice == "realm" or (type(choice) == "string" and choice:match("^faction:") ~= nil)
    or (ns.db.chars[choice] ~= nil and ns:CharChoiceHas("realm", choice))
end

-- The character list for dropdowns (Dashboard, Ledger), this realm only (owner, October
-- 4): all of your faction, its characters (you first); a gap; all of the other faction
-- and its characters; the whole realm, both factions.
function ns:CharacterOptions()
  local me, mine = ns.CharKey(), UnitFactionGroup("player") or "?"
  local own, other, otherName = {}, {}, nil
  for k, c in pairs(ns.db.chars) do
    if k ~= me and ns:CharChoiceHas("realm", k) then
      local fac = c.faction or mine
      if fac == mine then own[#own + 1] = k else other[#other + 1] = k; otherName = fac end
    end
  end
  local function name(k) return (ns.db.chars[k] and ns.db.chars[k].name) or k end
  local function byName(a, b) return name(a):lower() < name(b):lower() end
  table.sort(own, byName)
  table.sort(other, byName)
  local opts = { { value = "all", label = ("All %s characters"):format(mine) } }
  if ns.db.chars[me] then opts[#opts + 1] = { value = me, label = "  " .. name(me) .. " |cff888888(this one)|r" } end
  for _, k in ipairs(own) do opts[#opts + 1] = { value = k, label = "  " .. name(k) } end
  if #other > 0 then
    opts[#opts + 1] = { heading = true, label = "" }
    opts[#opts + 1] = { value = "faction:" .. otherName, label = ("All %s characters"):format(otherName) }
    for _, k in ipairs(other) do opts[#opts + 1] = { value = k, label = "  " .. name(k) } end
    local realm = (GetRealmName() or "this"):gsub("^Classic Beta%s+", "")
    opts[#opts + 1] = { heading = true, label = "" }
    opts[#opts + 1] = { value = "realm", label = ("Whole %s realm, both factions"):format(realm) }
  end
  return opts
end

local function charChoice(f)
  if not f.charChoice then
    f.charChoice = T:Dropdown(f, 230, function(v) settings().char = v; ns:RefreshDashboard(f) end)
    f.charChoice:SetPoint("TOPLEFT", 0, 0)
    f.sessionBtn:SetPoint("LEFT", f.charChoice, "RIGHT", 8, 0)
  end
  if not ns:IsCharChoice(settings().char) then settings().char = "all" end   -- (another realm's, from before)
  f.charChoice:SetOptions(ns:CharacterOptions())
end

local function signed(v, colour)
  local s = (v > 0 and "+" or (v < 0 and "-" or "")) .. ns.Money(math.abs(v))
  if not colour or v == 0 then return s end
  return (v > 0 and "|cff7fd39c" or "|cffee8597") .. s .. "|r"
end

local function place(fs, x, y, w)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", fs:GetParent(), "TOPLEFT", x, -y)
  if w then fs:SetWidth(w) end
end

function ns:RefreshDashboard(f)
  if not f or not ns.db then return end
  local s = settings()
  charChoice(f)
  f.charChoice:SetValue(s.char)
  f.rangeChoice:SetValue(s.range)
  local running = ns.GeneralSessionRunning and ns:GeneralSessionRunning()
  f.sessionBtn:SetText(running and "Stop the session" or "Start a session")

  -- Numbers
  local keys = chosenKeys()
  local from, to = timeRange(keys)
  local pts = goldSeries(keys, from, to)
  local n = totals(keys, from, to)
  local lo, hi, first, last
  for _, p in ipairs(pts) do
    if p.v then
      lo = lo and math.min(lo, p.v) or p.v
      hi = hi and math.max(hi, p.v) or p.v
      first = first or p.v
      last = p.v
    end
  end
  local phrase = PHRASE[s.range] or "this week"

  -- Layout, for the fixed window
  local W, H = f:GetWidth(), f:GetHeight()
  local gap, card = 8, 0
  local function nextCard(top, bottom, x, w)
    card = card + 1
    T:PlaceCard(f, card, top, bottom, w + 4, x, true)
  end

  -- Headline tiles
  local tileY, tileH = 32, 64
  local tw = math.floor((W - 3 * gap) / 4)
  local tiles = {
    { "Gold now", last and ns.Money(last) or dim("no record yet"), first and last and (signed(last - first, true) .. " " .. phrase) or "" },
    { "Profit " .. phrase, signed(n.profit, true), money(math.floor(n.profit / n.days)) .. " a day" },
    { "Sales", ns.Money(n.sales), n.topSold and ("top: " .. n.topSold) or "" },
    { "Expenses", ns.Money(n.expenses), n.topBought and ("top: " .. n.topBought) or "" },
  }
  for i, t in ipairs(f.tiles) do
    local x = (i - 1) * (tw + gap)
    nextCard(tileY, tileY + tileH, x, tw)
    place(t.label, x + 10, tileY + 8, tw - 20)
    place(t.value, x + 10, tileY + 23, tw - 20)
    place(t.sub, x + 10, tileY + 45, tw - 20)
    t.label:SetText(tiles[i][1])
    t.value:SetText(tiles[i][2])
    t.sub:SetText(tiles[i][3])
  end

  -- The graph card
  local gTop = tileY + tileH + gap
  local gBottom = gTop + 172
  nextCard(gTop, gBottom, 0, W)
  T:StyleHeading(f.graphHead, "Gold over " .. (OVER[s.range] or "the week"))
  place(f.graphHead, 12, gTop + 9)
  f.graphNote:ClearAllPoints()
  f.graphNote:SetPoint("TOPRIGHT", f, "TOPLEFT", W - 12, -(gTop + 9))
  f.graphNote:SetText(hi and ("high %s,  low %s"):format(ns.Money(hi), ns.Money(lo)) or "")
  f.graph:ClearAllPoints()
  f.graph:SetPoint("TOPLEFT", 4, -(gTop + 26))
  f.graph:SetSize(W - 8, gBottom - gTop - 30)
  drawGraph(f.graph, pts, from, to, s.range)

  -- Best and biggest, Activity
  local dTop = gBottom + gap
  local dBottom = dTop + 84
  local hw = math.floor((W - gap) / 2)
  local function detail(head, list, x, title, lines)
    nextCard(dTop, dBottom, x, hw)
    T:StyleHeading(head, title)
    place(head, x + 12, dTop + 9)
    for i, r in ipairs(list) do
      local y = dTop + 27 + (i - 1) * 18
      place(r.l, x + 12, y, hw * 0.45)
      r.v:ClearAllPoints()
      r.v:SetPoint("TOPRIGHT", f, "TOPLEFT", x + hw - 12, -y)
      r.v:SetWidth(hw * 0.55 - 24)
      r.l:SetText(lines[i][1])
      r.v:SetText(lines[i][2])
    end
  end
  detail(f.bestHead, f.best, 0, "Best and biggest", {
    { "Most profitable", n.topProfit or dim("none yet") },
    { "Biggest sale", n.bigSale and (ns.Money(n.bigSale.a) .. "  " .. dim(n.bigSale.n)) or dim("none yet") },
    { "Biggest purchase", n.bigBuy and (ns.Money(n.bigBuy.a) .. "  " .. dim(n.bigBuy.n)) or dim("none yet") },
  })
  detail(f.actHead, f.act, hw + gap, "Activity", {
    { "Auction sales a day", tostring(math.floor(n.nSales / n.days + 0.5)) },
    { "Auction purchases a day", tostring(math.floor(n.nBuys / n.days + 0.5)) },
    { "Sales a day", ns.Money(math.floor(n.sales / n.days)) },
  })

  -- Sessions, as a table
  local sTop = dBottom + gap
  local sBottom = H - 2
  nextCard(sTop, sBottom, 0, W)
  T:StyleHeading(f.sesHead, "Sessions")
  place(f.sesHead, 12, sTop + 9)
  f.sesNote:ClearAllPoints()
  f.sesNote:SetPoint("TOPRIGHT", f, "TOPLEFT", W - 12, -(sTop + 9))
  local gs = ns.SessionTotals and ns:SessionTotals()
  f.sesNote:SetText(gs and ("running: %d min, gold %s"):format(math.floor(gs.secs / 60), signed(gs.gained, true)) or "")
  local headY = sTop + 28
  for i, c in ipairs(SESSION_COLS) do place(f.sesCols[i], c[2] + 2, headY, c[3]) end
  local list = ns.db.sessions
  local fit = math.max(0, math.floor((sBottom - (headY + 18) - 4) / 18))
  local shown = 0
  for i = #list, 1, -1 do
    if shown >= fit then break end
    shown = shown + 1
    local x = list[i]
    local row = f.sesRows[shown]
    if not row then
      row = {}
      for k, c in ipairs(SESSION_COLS) do row[k] = text(f, 12, nil, c[4]) end
      f.sesRows[shown] = row
    end
    local secs = x.secs or ((x.stop or x.t) - x.t)
    local mins = math.floor(secs / 60)
    local gained = (x.earned or 0) - (x.spent or 0)
    local cells = {
      dim(date("%b %d %H:%M", x.t)),
      mins < 1 and "under a minute" or (mins .. " min"),
      signed(gained, true),
      x.kind == "general" and ns.Money(x.loot or 0) or dim(x.name or "-"),
      secs >= 120 and signed(math.floor(gained / secs * 3600), false) or dim("-"),
    }
    for k, c in ipairs(SESSION_COLS) do
      place(row[k], c[2] + 2, headY + 18 * shown, c[3])
      row[k]:SetText(cells[k])
      row[k]:Show()
    end
  end
  for i = shown + 1, #f.sesRows do for _, fs in ipairs(f.sesRows[i]) do fs:Hide() end end
  f.sesEmpty:SetShown(#list == 0)
  place(f.sesEmpty, 12, headY + 18)
  T:HideCards(f, card + 1)
end

ns.RefreshDashboard = ns.Timed("Dashboard", ns.RefreshDashboard)
