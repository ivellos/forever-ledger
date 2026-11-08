local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- The price window (owner, November 8, from the mockup he approved): one item's price
-- graph and everything about it at a glance. Alt-click an item (bags, chat links) or
-- /fl price <item>.
--   top:    icon, name, Search on the auction house
--   strip:  usual price, trend, listed now, you have, posted
--   graph:  cheapest and typical price per day (weeks past 90 days), listed counts as
--           bars, flat lines for the vendor price, disenchant value and cost to craft;
--           2 weeks, 3 months or 1 year; a version picker for random-stat gear
--   side:   your last 7 days with it, worth to you, Add to shopping list
--   craft:  when a recipe makes it: the materials at auction house prices, cost to
--           craft against what it sells for after the cut, and Add materials to a
--           shopping list for any number of crafts
-- Data comes from ns:ItemPriceSummary (tested); the drawing is here.
---------------------------------------------------------------------------
local DAY = 86400

local function today() return ns.LocalDay(time()) end
local function median(t)
  if #t == 0 then return nil end
  table.sort(t)
  return t[math.floor((#t + 1) / 2)]
end

-- Everything the window shows about an item, worked out from saved data. suffix: one
-- version of a gear item (nil = all of them). Returns a table:
--   usual, cheapest, listed, scanned (time), trend (fraction, + up), have = { total, here, alts },
--   posted, week = { sold = { n, a }, bought = { n, a }, vendorSold = { n, a } },
--   craft = { prof, who, classic, oq, mats = { { id, qty, cost, have } }, cost (per item),
--     missing (a material without a price), sells (each, after the cut), profit (each) } or nil
function ns:ItemPriceSummary(id, suffix)
  local s = { week = { sold = { n = 0, a = 0 }, bought = { n = 0, a = 0 }, vendorSold = { n = 0, a = 0 } } }
  if not (id and ns.db) then return s end
  local d = today()
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]

  -- Prices now and usual
  if suffix then
    local m, q = ns:SuffixPrice(id, suffix)
    s.cheapest, s.listed = (m and m > 0) and m or nil, q or (m == 0 and 0) or nil
    local month = {}
    for _, p in ipairs(ns:PriceSeries(id, suffix, 30)) do
      if not p.week and p.day < d then month[#month + 1] = p.cheapest end
    end
    s.usual = #month >= 3 and median(month) or nil
  else
    s.cheapest = rec and not rec.none and rec.m or nil
    s.listed = rec and (rec.none and 0 or rec.q) or nil
    -- The month's usual price, as shopping lists and deals use it (3 days of scans at least).
    local st = ns.PriceStats and ns:PriceStats(id, "month")
    s.usual = st and st.points >= 3 and st.usual or nil
  end
  s.scanned = rec and rec.t

  -- Trend: this week's average against the two weeks before it (typical prices; the
  -- cheapest for a version, the only price full scans keep for one).
  local recent, before = {}, {}
  for _, p in ipairs(ns:PriceSeries(id, suffix, 21)) do
    local v = suffix and p.cheapest or p.typical
    if not p.week and v then
      if p.day > d - 7 then recent[#recent + 1] = v elseif p.day > d - 21 then before[#before + 1] = v end
    end
  end
  local function avg(t) local sum = 0; for _, v in ipairs(t) do sum = sum + v end; return sum / #t end
  if #recent >= 2 and #before >= 3 then
    local b = avg(before)
    if b > 0 then s.trend = (avg(recent) - b) / b end
  end

  -- What you have, and have posted
  local bags, bank, alts = ns:ItemLocations(id)
  s.have = { total = bags + bank + alts, here = bags + bank, alts = alts }
  local posted = 0
  for key, mine in pairs(ns.db.myAuctions or {}) do
    local char = key:gsub(" %(neutral%)$", "")
    if ns:SameMarketChar(char) then
      for _, e in ipairs(mine.list or {}) do
        if e.id == id and not e.sold then posted = posted + (e.q or 1) end
      end
    end
  end
  s.posted = posted

  -- Your last 7 days with it, on characters at this auction house
  local since, name = time() - 7 * DAY, ns.ItemName(id)
  local w = s.week
  local function add(t, q, a) t.n, t.a = t.n + (q or 1), t.a + (a or 0) end
  for _, e in ipairs(ns.db.sales or {}) do
    if e.t >= since and (e.id == id or (name and e.n == name)) and ns:SameMarketChar(e.c) then add(w.sold, e.q, e.a) end
  end
  for _, e in ipairs(ns.db.purchases or {}) do
    if e.t >= since and e.id == id and ns:SameMarketChar(e.c) then add(w.bought, e.q, e.a) end
  end
  for _, e in ipairs(ns.db.vendorLog or {}) do
    if e.t >= since and e.id == id and ns:SameMarketChar(e.c) then
      if e.s == "sell" then add(w.vendorSold, e.q, e.a) else add(w.bought, e.q, e.a) end
    end
  end

  -- Crafting it: materials at what buying them costs today (auction house, or a vendor
  -- where that's cheaper), against selling it at the usual price after the cut.
  local recipe = ns.RecipeFor and ns:RecipeFor(id)
  if recipe and recipe.r and #recipe.r > 0 then
    local c = { prof = recipe.prof, who = recipe.who, classic = recipe.classic, oq = math.max(recipe.oq or 1, 1), mats = {} }
    local total = 0
    for _, r in ipairs(recipe.r) do
      local qty = r[2] or 1
      local cost = ns.CostToBuy and ns:CostToBuy(r[1], qty)
      local mb, mk, ma = ns:ItemLocations(r[1])
      c.mats[#c.mats + 1] = { id = r[1], qty = qty, cost = cost, have = mb + mk + ma }
      if cost then total = total + cost else c.missing = c.missing or r[1] end
    end
    if not c.missing then c.cost = total / c.oq end
    local price = s.usual or s.cheapest
    if price then c.sells = ns:AfterCut(price) end
    if c.cost and c.sells then c.profit = c.sells - c.cost end
    s.craft = c
  end
  return s
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local W, SIDE, GAP = 780, 230, 8
local GRAPH_H = 250
local PAD_L, PAD_R, PAD_T, PAD_B = 56, 10, 8, 20
local GOLD, BLUE = { 0.95, 0.78, 0.35 }, { 0.47, 0.58, 0.88 }
local GREEN, PURPLE, BAR = { 0.5, 0.83, 0.61 }, { 0.80, 0.56, 0.90 }, { 1, 1, 1, 0.07 }
local RANGES = { { value = 14, label = "2 weeks" }, { value = 90, label = "3 months" }, { value = 365, label = "1 year" } }
local MAX_MATS = 8

local win
local state = { range = 90 }

local function dim(t) return "|cff888888" .. t .. "|r" end
local function count(n)
  if not n then return "?" end
  return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end
local function signedMoney(v)
  if v >= 0 then return "|cff7fd39c" .. ns.Money(v) .. "|r" end
  return "|cffee8597-" .. ns.Money(-v) .. "|r"
end
-- "1g 20s" or "85s" for the graph's scale.
local function short(c)
  if c >= 10000 then
    local g, s = math.floor(c / 10000), math.floor(c % 10000 / 100)
    if g < 100 and s > 0 then return ("%dg %ds"):format(g, s) end
    return ("%dg"):format(g)
  end
  if c >= 100 then return ("%ds"):format(math.floor(c / 100)) end
  return ("%dc"):format(math.floor(c))
end
local function dayTime(day) return time() - (today() - day) * DAY end

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

local function text(parent, size, color, justify)
  local fs = T:Text(parent, size, color)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function place(fs, x, y, w)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", fs:GetParent(), "TOPLEFT", x, -y)
  if w then fs:SetWidth(w) end
end

-- The graph: pts from ns:PriceSeries, flats = { { value, color, label } }. Returns the
-- flat lines it drew (one far off the prices would squash them, so it's left out).
local function drawGraph(g, pts, flats)
  local shownFlats = {}
  local w, h = g:GetWidth(), g:GetHeight()
  local plotW, plotH = w - PAD_L - PAD_R, h - PAD_T - PAD_B
  local d = today()
  local nextLine, doneLines = pool(g, "lines", function()
    local l = g.CreateLine and g:CreateLine(nil, "OVERLAY")
    if l then l:SetThickness(2) end
    return l or g:CreateTexture(nil, "OVERLAY")
  end)
  local nextTex, doneTex = pool(g, "texs", function()
    local t = g:CreateTexture(nil, "ARTWORK")
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    return t
  end)
  local nextLabel, doneLabels = pool(g, "labels", function() return T:Text(g, 10, T.dim) end)
  g.pts = {}

  local lo, hi, qmax, first
  for _, p in ipairs(pts) do
    for _, v in ipairs({ p.cheapest, p.typical }) do
      lo, hi = lo and math.min(lo, v) or v, hi and math.max(hi, v) or v
    end
    if p.listed then qmax = math.max(qmax or 0, p.listed) end
    first = first or p.day
  end
  g.empty:SetShown(lo == nil)
  if lo then
    -- Flat lines that would squash the prices into a sliver are left out (a vendor price
    -- far under the auction price says nothing here). Judged against the prices alone.
    local plo, phi = lo, hi
    for _, f in ipairs(flats) do
      if f[1] and f[1] > 0 and f[1] >= plo * 0.5 and f[1] <= phi * 2 then
        shownFlats[#shownFlats + 1] = f
        lo, hi = math.min(lo, f[1]), math.max(hi, f[1])
      end
    end
    local span = hi - lo
    if span <= 0 then span = math.max(hi * 0.2, 1) end
    local bottom = math.max(0, lo - span * 0.15)
    local top = hi + span * 0.1
    local from = math.max(d - state.range + 1, first)
    if d - from < 6 then from = d - 6 end
    local function x(day) return PAD_L + (day - from) / (d - from) * plotW end
    local function y(v) return PAD_B + (v - bottom) / (top - bottom) * plotH end
    -- A week is drawn at its middle; one whose middle is before the range is left out.
    local inRange = {}
    for _, p in ipairs(pts) do
      if (p.week and p.day + 3 or p.day) >= from then inRange[#inRange + 1] = p end
    end
    pts = inRange

    -- Scale and grid
    for i = 0, 3 do
      local v = bottom + (top - bottom) * i / 3
      local t = nextTex()
      t:SetColorTexture(1, 1, 1, 0.06)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", PAD_L, y(v))
      t:SetSize(plotW, 1)
      local l = nextLabel()
      l:ClearAllPoints()
      l:SetPoint("RIGHT", g, "BOTTOMLEFT", PAD_L - 6, y(v))
      l:SetText(short(v))
    end

    -- How many were listed, as faint bars along the bottom fifth
    if qmax and qmax > 0 then
      local bw = math.max(1, plotW / math.max(d - from + 1, 1) * 0.7)
      for _, p in ipairs(pts) do
        if p.listed and p.listed > 0 then
          local t = nextTex()
          t:SetColorTexture(BAR[1], BAR[2], BAR[3], BAR[4])
          t:ClearAllPoints()
          local cx = p.week and x(p.day + 3) or x(p.day)
          local width = p.week and math.max(bw, plotW / math.max(d - from + 1, 1) * 6) or bw
          t:SetPoint("BOTTOM", g, "BOTTOMLEFT", cx, PAD_B)
          t:SetSize(width, math.max(1, p.listed / qmax * plotH * 0.2))
        end
      end
    end

    -- Flat lines, dashed
    for _, f in ipairs(shownFlats) do
      local c = f[2]
      for sx = 0, plotW - 6, 10 do
        local t = nextTex()
        t:SetColorTexture(c[1], c[2], c[3], 0.8)
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", PAD_L + sx, y(f[1]))
        t:SetSize(6, 1)
      end
    end

    -- The price lines: typical first, cheapest on top. Days more than 8 apart (no scans
    -- in between) aren't joined.
    for _, key in ipairs({ "typical", "cheapest" }) do
      local c = key == "cheapest" and GOLD or BLUE
      local prev
      for _, p in ipairs(pts) do
        local v = p[key]
        if v then
          local px, py = p.week and x(p.day + 3) or x(p.day), y(v)
          if prev and p.day - prev.day <= 8 and g.CreateLine then
            local l = nextLine()
            l:SetColorTexture(c[1], c[2], c[3], key == "cheapest" and 1 or 0.8)
            l:SetStartPoint("BOTTOMLEFT", g, prev.x, prev.y)
            l:SetEndPoint("BOTTOMLEFT", g, px, py)
          elseif not (prev and p.day - prev.day <= 8) then
            -- A point on its own: a small dot, so a single day still shows.
            local t = nextTex()
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:ClearAllPoints()
            t:SetPoint("CENTER", g, "BOTTOMLEFT", px, py)
            t:SetSize(3, 3)
          end
          prev = { day = p.day, x = px, y = py }
          if key == "cheapest" then g.pts[#g.pts + 1] = { x = px, p = p } end
        end
      end
    end

    -- The line between weekly and daily points, on a year
    local firstDaily
    for _, p in ipairs(pts) do if not p.week then firstDaily = p.day; break end end
    if firstDaily and pts[1] and pts[1].week and firstDaily > from then
      local t = nextTex()
      t:SetColorTexture(1, 1, 1, 0.15)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", x(firstDaily) - 2, PAD_B)
      t:SetSize(1, plotH)
      local l1, l2 = nextLabel(), nextLabel()
      l1:ClearAllPoints(); l1:SetPoint("TOPRIGHT", g, "BOTTOMLEFT", x(firstDaily) - 6, PAD_B + plotH)
      l1:SetText("weekly")
      l2:ClearAllPoints(); l2:SetPoint("TOPLEFT", g, "BOTTOMLEFT", x(firstDaily) + 2, PAD_B + plotH)
      l2:SetText("daily")
    end

    -- Dates along the bottom
    for i = 0, 3 do
      local day = math.floor(from + (d - from) * i / 3 + 0.5)
      local l = nextLabel()
      l:ClearAllPoints()
      l:SetPoint("TOP", g, "BOTTOMLEFT", x(day), PAD_B - 4)
      l:SetText(day == d and "Today" or date("%b %d", dayTime(day)))
    end
  end
  doneLines(); doneTex(); doneLabels()
  return shownFlats
end

-- Hovering the graph: the nearest point's day, prices and listed count.
local function hoverGraph(g)
  if not g.pts or #g.pts == 0 then return end
  local mx = GetCursorPosition() / g:GetEffectiveScale() - g:GetLeft()
  local best
  for _, q in ipairs(g.pts) do
    if not best or math.abs(q.x - mx) < math.abs(best.x - mx) then best = q end
  end
  local p = best.p
  g.marker:ClearAllPoints()
  g.marker:SetPoint("BOTTOM", g, "BOTTOMLEFT", best.x, PAD_B)
  g.marker:SetHeight(g:GetHeight() - PAD_T - PAD_B)
  g.marker:Show()
  GameTooltip:SetOwner(g, "ANCHOR_CURSOR")
  local when = p.week and ("Week of " .. date("%b %d", dayTime(p.day))) or (p.day == today() and "Today" or date("%a %b %d", dayTime(p.day)))
  GameTooltip:AddLine(when, 1, 1, 1)
  GameTooltip:AddDoubleLine("Cheapest", ns.Money(p.cheapest), 0.7, 0.7, 0.7, GOLD[1], GOLD[2], GOLD[3])
  if p.typical then GameTooltip:AddDoubleLine("Typical", ns.Money(p.typical), 0.7, 0.7, 0.7, BLUE[1], BLUE[2], BLUE[3]) end
  if p.listed then GameTooltip:AddDoubleLine(p.week and "Listed, on average" or "Listed", count(p.listed), 0.7, 0.7, 0.7, 1, 1, 1) end
  GameTooltip:Show()
end

local function itemTooltip(owner, id, link)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(link)
  elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(id) end
  GameTooltip:Show()
end

local function build()
  win = ns.ThemedWindow("ForeverLedgerPriceWindow", W, 600, T:TitleCode() .. "Price history|r")
  local f = win

  -- Top: icon, name, kind, search
  f.icon = CreateFrame("Button", nil, f)
  f.icon:SetSize(36, 36)
  f.icon:SetPoint("TOPLEFT", 12, -40)
  f.icon.tex = f.icon:CreateTexture(nil, "ARTWORK")
  f.icon.tex:SetAllPoints()
  T:Border(f.icon, { 1, 1, 1, 0.25 })
  f.icon:SetScript("OnEnter", function(self) itemTooltip(self, f.id, f.link) end)
  f.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.name = text(f, 15)
  f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
  f.name:SetWidth(W - 300)
  f.kind = text(f, 11, T.dim)
  f.kind:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
  f.kind:SetWidth(W - 300)
  f.search = T:Button(f, "Search on the auction house", 200, function()
    if not ns:SearchAuctionHouse(f.id) then ns:Print("Open the auction house first, then click Search again.") end
  end, 24)
  f.search:SetPrimary(true)
  f.search:SetPoint("TOPRIGHT", -12, -46)
  f.search:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Search on the auction house", 1, 1, 1)
    GameTooltip:AddLine(ns:IsAHOpen() and "Shows this item on the auction house's Buy tab."
      or "Works while the auction house is open.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  f.search:HookScript("OnLeave", function() GameTooltip:Hide() end)

  -- Strip: five numbers
  f.tiles = {}
  for i = 1, 5 do f.tiles[i] = { label = text(f, 11, T.dim), value = text(f, 16), sub = text(f, 10, T.dim) } end

  -- Graph card
  f.graphHead = text(f, 11)
  f.range = T:Choice(f, RANGES, function(v) state.range = v; ns:RefreshPriceWindow() end)
  f.version = T:Dropdown(f, 170, function(v) state.suffix = v ~= "all" and v or nil; ns:RefreshPriceWindow() end)
  local g = CreateFrame("Frame", nil, f)
  g.empty = T:Text(g, 12, T.dim)
  g.empty:SetPoint("CENTER")
  g.empty:SetText("No price history yet. Each scan saves one point a day.")
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
  f.legend = text(f, 11, T.dim)

  -- Side: your last 7 days, worth to you, add to shopping list
  f.weekHead, f.worthHead = text(f, 11), text(f, 11)
  f.weekRows, f.worthRows = {}, {}
  for i = 1, 3 do
    f.weekRows[i] = { l = text(f, 12), v = text(f, 12, nil, "RIGHT") }
    f.worthRows[i] = { l = text(f, 11), v = text(f, 12, nil, "RIGHT") }
  end
  f.addItem = T:Button(f, "Add to shopping list", SIDE - 24, function()
    local list = ns:QuickAddToShoppingList(f.id, state.suffix)
    ns:Print(("Added %s to shopping list \"%s\" (/fl lists)."):format(ns.ItemName(f.id) or "it", list.name))
  end, 22)
  f.addItem:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Add to shopping list", 1, 1, 1)
    GameTooltip:AddLine("Puts this item on the shopping list you're on (or a new one), at your usual price plus the list's allowance. Change Want and Up to there.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  f.addItem:HookScript("OnLeave", function() GameTooltip:Hide() end)

  -- Craft card
  f.craftHead, f.craftWho = text(f, 11), text(f, 11, T.dim)
  f.matCols = {}
  for i, label in ipairs({ "Material", "Need", "Each", "Per craft", "You have" }) do
    f.matCols[i] = text(f, 10, T.dim, i == 1 and "LEFT" or "RIGHT")
    f.matCols[i]:SetText(label)
  end
  f.mats = {}
  for i = 1, MAX_MATS do
    local r = CreateFrame("Button", nil, f)
    r:SetHeight(18)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.12)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 2, 0)
    r.cells = {}
    for k = 1, 5 do r.cells[k] = text(r, 12, nil, k == 1 and "LEFT" or "RIGHT") end
    -- Click a material: its own price window (Back isn't needed: Alt-click the item again).
    r:SetScript("OnClick", function(self) if self.id then ns:ShowPriceWindow(self.id) end end)
    r:SetScript("OnEnter", function(self)
      if not self.id then return end
      itemTooltip(self, self.id)
      GameTooltip:AddLine("Click for this material's price history", 0.5, 0.83, 0.61)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.mats[i] = r
  end
  f.matTotal = { l = text(f, 11, T.dim), v = text(f, 12, nil, "RIGHT") }
  f.sum = {}
  for i = 1, 4 do f.sum[i] = { l = text(f, 11, T.dim), v = text(f, 12, nil, "RIGHT") } end
  f.crafts = T:Number(f, { min = 1, max = 10000, step = 1 }, function(v) state.crafts = math.floor(v) end)
  f.craftsLabel = text(f, 11, T.dim)
  f.craftsLabel:SetText("Crafts")
  f.listPick = T:Dropdown(f, 190, function(v) state.target = v end)
  f.addMats = T:Button(f, "Add materials to shopping list", 210, function()
    local target = state.target ~= "new" and state.target or nil
    local list, err = ns:CraftToShoppingList(f.id, state.crafts or 1, target)
    if not list then ns:Print(err); return end
    state.target = list
    ns:RefreshPriceWindow()
  end, 22)
  f.addMats:SetPrimary(true)
  f.addMats:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Add materials to shopping list", 1, 1, 1)
    GameTooltip:AddLine("Everything this many crafts need, added to what the list already wants. Up to starts at your usual price plus the list's allowance; prices you typed stay. What you already have isn't taken off: check Want on the list.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  f.addMats:HookScript("OnLeave", function() GameTooltip:Hide() end)

  f:SetScript("OnHide", function() GameTooltip:Hide() end)
end

-- Lays the window out and fills it in.
function ns:RefreshPriceWindow()
  local f = win
  if not (f and f:IsShown() and f.id) then return end
  local id = f.id
  local s = ns:ItemPriceSummary(id, state.suffix)
  local card = 0
  local function nextCard(top, bottom, x, w)
    card = card + 1
    T:PlaceCard(f, card, top, bottom, w + 4, x, true)
  end

  -- Top
  local name, link, quality, ilvl, _, itemType, subType, _, _, icon, _, classID = ns.GetItemInfo(id)
  f.link = f.link or link
  f.icon.tex:SetTexture(icon or ns:ItemIcon(id))
  local colour = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  local shown = (name or ns.ItemName(id) or ("item " .. id)) .. (state.suffix and (" " .. (ns:VersionName(state.suffix) or "")) or "")
  f.name:SetText(colour and colour.hex and (colour.hex .. shown .. "|r") or shown)
  local kind = {}
  if itemType and itemType ~= "" then kind[#kind + 1] = itemType end
  if subType and subType ~= "" and subType ~= itemType then kind[#kind + 1] = subType end
  if (classID == 2 or classID == 4) and ilvl then kind[#kind + 1] = "item level " .. ilvl end
  f.kind:SetText(table.concat(kind, ", "))
  ns:PriceWindowSearchState()

  -- Strip
  local x0, stripTop, stripH = 12, 88, 54
  local inner = W - 24
  local tw = math.floor((inner - 4 * GAP) / 5)
  local trend = s.trend and (s.trend >= 0 and ("|cff7fd39cup %.1f%%|r"):format(s.trend * 100)
    or ("|cffee8597down %.1f%%|r"):format(-s.trend * 100))
  local haveSub = s.have.alts > 0 and ("%s here, %s on alts"):format(count(s.have.here), count(s.have.alts)) or "bags and bank"
  local tiles = {
    { state.suffix and "Usual cheapest" or "Usual price", s.usual and ns.Money(s.usual) or dim("not enough scans"), "this month" },
    { "Trend", trend or dim("not enough scans"), "this week vs the 2 before" },
    { "Listed now", s.listed and count(s.listed) or dim("not scanned"), s.scanned and ns.Age(s.scanned) or "" },
    { "You have", count(s.have.total), haveSub },
    { "Posted", count(s.posted), "your auctions" },
  }
  for i, t in ipairs(f.tiles) do
    local x = x0 + (i - 1) * (tw + GAP)
    nextCard(stripTop, stripTop + stripH, x, tw)
    place(t.label, x + 10, stripTop + 7, tw - 20)
    place(t.value, x + 10, stripTop + 21, tw - 20)
    place(t.sub, x + 10, stripTop + 40, tw - 20)
    t.label:SetText(tiles[i][1])
    t.value:SetText(tiles[i][2])
    t.sub:SetText(tiles[i][3])
  end

  -- Graph card
  local gTop = stripTop + stripH + GAP
  local gw = inner - SIDE - GAP
  nextCard(gTop, gTop + GRAPH_H, x0, gw)
  T:StyleHeading(f.graphHead, "Price history")
  place(f.graphHead, x0 + 12, gTop + 10)
  f.range:ClearAllPoints()
  f.range:SetPoint("TOPRIGHT", f, "TOPLEFT", x0 + gw - 8, -(gTop + 6))
  f.range:SetValue(state.range)
  local versions = ns:PriceVersions(id)
  f.version:SetShown(#versions > 0)
  if #versions > 0 then
    local opts = { { value = "all", label = "All versions" } }
    for _, v in ipairs(versions) do opts[#opts + 1] = { value = v, label = ns:VersionName(v) or "other stats" } end
    f.version:SetOptions(opts)
    f.version:SetValue(state.suffix or "all")
    f.version:ClearAllPoints()
    f.version:SetPoint("RIGHT", f.range, "LEFT", -8, 0)
  end
  f.graph:ClearAllPoints()
  f.graph:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + 4, -(gTop + 34))
  f.graph:SetSize(gw - 8, GRAPH_H - 34 - 24)

  local flats, legend = {}, { "|cfff2c759--|r cheapest" }
  if not state.suffix then legend[#legend + 1] = "|cff7894e0--|r typical" end
  legend[#legend + 1] = "|cff555555[]|r listed"
  local vendor = ns:GetSellPrice(id)
  local de = ns.DisenchantSaleValue and ns:DisenchantSaleValue(id)
  if de and de > 0 then flats[#flats + 1] = { de, GREEN, "disenchant value" }
  elseif vendor and vendor > 0 then flats[#flats + 1] = { vendor, GREEN, "vendor price" } end
  if s.craft and s.craft.cost then flats[#flats + 1] = { s.craft.cost, PURPLE, "cost to craft" } end
  local pts = ns:PriceSeries(id, state.suffix, state.range)
  -- Only the flat lines the graph drew go in the legend.
  for _, fl in ipairs(drawGraph(f.graph, pts, flats)) do
    legend[#legend + 1] = (fl[2] == PURPLE and "|cffcc8fe6- -|r " or "|cff7fd39c- -|r ") .. fl[3]
  end
  place(f.legend, x0 + 12, gTop + GRAPH_H - 18, gw - 24)
  f.legend:SetText(table.concat(legend, "    ") .. dim("    hover for each day"))

  -- Side
  local sx = x0 + gw + GAP
  nextCard(gTop, gTop + GRAPH_H, sx, SIDE)
  T:StyleHeading(f.weekHead, "Your last 7 days")
  place(f.weekHead, sx + 12, gTop + 10)
  local wk = s.week
  local weekLines = {}
  if wk.sold.n > 0 then weekLines[#weekLines + 1] = { "Sold " .. count(wk.sold.n), ns.Money(wk.sold.a) } end
  if wk.bought.n > 0 then weekLines[#weekLines + 1] = { "Bought " .. count(wk.bought.n), ns.Money(wk.bought.a) } end
  if wk.vendorSold.n > 0 then weekLines[#weekLines + 1] = { "To vendors " .. count(wk.vendorSold.n), ns.Money(wk.vendorSold.a) } end
  if #weekLines == 0 then weekLines[1] = { dim("Nothing bought or sold"), "" } end
  for i, r in ipairs(f.weekRows) do
    local line = weekLines[i]
    r.l:SetShown(line ~= nil); r.v:SetShown(line ~= nil)
    if line then
      place(r.l, sx + 12, gTop + 30 + (i - 1) * 18, SIDE - 24)
      r.v:ClearAllPoints()
      r.v:SetPoint("TOPRIGHT", f, "TOPLEFT", sx + SIDE - 12, -(gTop + 30 + (i - 1) * 18))
      r.l:SetText(line[1]); r.v:SetText(line[2])
    end
  end
  local wTop = gTop + 30 + 3 * 18 + 10
  T:StyleHeading(f.worthHead, "Worth to you")
  place(f.worthHead, sx + 12, wTop)
  local _, options = ns:GetValue(id, true)
  for i, r in ipairs(f.worthRows) do
    local o = options and options[i]
    r.l:SetShown(o ~= nil); r.v:SetShown(o ~= nil)
    if o then
      local y = wTop + 20 + (i - 1) * 30
      place(r.l, sx + 12, y, SIDE - 24)
      r.l:SetWordWrap(true)
      if r.l.SetMaxLines then r.l:SetMaxLines(2) end
      r.l:SetHeight(28)
      r.l:SetJustifyV("TOP")
      r.l:SetText(o.label or ns:OptionLabel(o))
      r.l:SetTextColor(i == 1 and 0.5 or 0.75, i == 1 and 0.83 or 0.75, i == 1 and 0.61 or 0.75, 1)
      r.v:ClearAllPoints()
      r.v:SetPoint("TOPRIGHT", f, "TOPLEFT", sx + SIDE - 12, -y)
      r.v:SetText(ns.Money(o.value))
      r.l:SetWidth(SIDE - 24 - 74)
    end
  end
  if not (options and options[1]) then
    local r = f.worthRows[1]
    r.l:Show(); place(r.l, sx + 12, wTop + 20, SIDE - 24); r.l:SetHeight(28)
    r.l:SetText(dim("Needs a price first: scan at the auction house."))
  end
  f.addItem:ClearAllPoints()
  f.addItem:SetPoint("TOPLEFT", f, "TOPLEFT", sx + 12, -(gTop + GRAPH_H - 32))

  -- Craft card
  local c = s.craft
  local cTop = gTop + GRAPH_H + GAP
  local shownCraft = c ~= nil
  for _, w in ipairs({ f.craftHead, f.craftWho, f.matTotal.l, f.matTotal.v, f.crafts, f.craftsLabel, f.listPick, f.addMats }) do
    w:SetShown(shownCraft)
  end
  for _, fs in ipairs(f.matCols) do fs:SetShown(shownCraft) end
  for _, r in ipairs(f.sum) do r.l:SetShown(shownCraft); r.v:SetShown(shownCraft) end
  local height = cTop + 10
  if shownCraft then
    local rows = math.min(#c.mats, MAX_MATS)
    -- Heading, column names, materials, the total, then the Add materials row; at least
    -- tall enough for the sums box beside them.
    local cH = math.max(30 + 14 + rows * 18 + 26 + 40, 28 + 92 + 8 + 40)
    nextCard(cTop, cTop + cH, x0, inner)
    T:StyleHeading(f.craftHead, "Craft it")
    place(f.craftHead, x0 + 12, cTop + 10)
    f.craftWho:ClearAllPoints()
    f.craftWho:SetPoint("LEFT", f.craftHead, "RIGHT", 10, 0)
    f.craftWho:SetText((c.prof or "") .. (c.who and (", known by " .. c.who) or "")
      .. (c.classic and ", none of your characters knows this recipe yet" or "")
      .. (c.oq > 1 and (", makes " .. c.oq) or ""))
    -- Materials table, left (each column's right edge and width, from the row's left);
    -- the sums, right.
    local tableW = inner - SIDE - GAP - 4
    local COLS = { { nil, tableW - 300 - 26 }, { tableW - 250, 46 }, { tableW - 140, 106 }, { tableW - 60, 76 }, { tableW - 4, 52 } }
    local rowX = x0 + 10
    local headY = cTop + 30
    for i, fs in ipairs(f.matCols) do
      fs:ClearAllPoints()
      if i == 1 then fs:SetPoint("TOPLEFT", f, "TOPLEFT", rowX + 22, -headY)
      else fs:SetPoint("TOPRIGHT", f, "TOPLEFT", rowX + COLS[i][1], -headY) end
      fs:SetWidth(COLS[i][2])
    end
    for i, r in ipairs(f.mats) do
      local m = c.mats[i]
      r:SetShown(m ~= nil and i <= rows)
      if m and i <= rows then
        r.id = m.id
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f, "TOPLEFT", rowX, -(headY + 14 + (i - 1) * 18))
        r:SetWidth(tableW)
        r.icon:SetTexture(ns:ItemIcon(m.id))
        local each = m.cost and math.floor(m.cost / m.qty + 0.5)
        local cells = {
          ns.ItemName(m.id) or ("item " .. m.id), "x" .. m.qty,
          each and ns.Money(each) or dim("no price"), m.cost and ns.Money(m.cost) or dim("?"),
          m.have > 0 and count(m.have) or dim("0"),
        }
        for k, fs in ipairs(r.cells) do
          fs:ClearAllPoints()
          if k == 1 then fs:SetPoint("LEFT", r, "LEFT", 22, 0)
          else fs:SetPoint("RIGHT", r, "LEFT", COLS[k][1], 0) end
          fs:SetWidth(COLS[k][2])
          fs:SetText(cells[k])
        end
      end
    end
    local totalY = headY + 14 + rows * 18 + 6
    place(f.matTotal.l, rowX + 22, totalY, COLS[3][1] - 22)
    f.matTotal.l:SetText("One craft at today's prices (vendor where cheaper)")
    f.matTotal.v:ClearAllPoints()
    f.matTotal.v:SetPoint("TOPRIGHT", f, "TOPLEFT", rowX + COLS[4][1], -totalY)
    f.matTotal.v:SetWidth(COLS[4][2])
    local craftTotal = 0
    for _, m in ipairs(c.mats) do craftTotal = craftTotal + (m.cost or 0) end
    f.matTotal.v:SetText(c.missing and dim("?") or ns.Money(craftTotal))

    -- Sums, in a box on the right
    local bx = x0 + inner - SIDE
    nextCard(cTop + 28, cTop + 28 + 92, bx, SIDE - 8)
    local sums = {
      { c.oq > 1 and "Cost to craft, each" or "Cost to craft", c.cost and ns.Money(c.cost) or dim("a material has no price") },
      { "Sells for, after cut", c.sells and ns.Money(c.sells) or dim("no price yet") },
      { "Profit each", c.profit and signedMoney(c.profit) or dim("?") },
      { "", c.profit and (c.profit > 0 and c.cost > 0 and dim(("%d%% on what you spend"):format(math.floor(c.profit / c.cost * 100 + 0.5)))
        or c.profit < 0 and "|cffee8597Cheaper to buy it|r" or "") or "" },
    }
    for i, r in ipairs(f.sum) do
      local y = cTop + 36 + (i - 1) * 20
      place(r.l, bx + 10, y, SIDE - 30)
      r.v:ClearAllPoints()
      r.v:SetPoint("TOPRIGHT", f, "TOPLEFT", bx + SIDE - 20, -y)
      r.l:SetText(sums[i][1]); r.v:SetText(sums[i][2])
    end

    -- Add materials: how many crafts, which list
    local aY = cTop + cH - 32
    f.craftsLabel:ClearAllPoints()
    f.craftsLabel:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + 12, -(aY + 5))
    f.crafts:ClearAllPoints()
    f.crafts:SetPoint("LEFT", f.craftsLabel, "RIGHT", 8, 0)
    if f.craftsFor ~= id then f.craftsFor, state.crafts, state.target = id, 1, "new" end
    f.crafts:SetValue(state.crafts or 1)
    local opts = { { value = "new", label = "New list: " .. (ns.ItemName(id) or "this item") } }
    local found = state.target == "new"
    for _, l in ipairs(ns:ShoppingLists()) do
      if not l.countHave and not l.temp and not l.crateID then
        opts[#opts + 1] = { value = l, label = l.name }
        if l == state.target then found = true end
      end
    end
    if not found then state.target = "new" end
    f.listPick:SetOptions(opts)
    f.listPick:SetValue(state.target)
    f.listPick:ClearAllPoints()
    f.listPick:SetPoint("LEFT", f.crafts, "LEFT", 118, 0)
    f.addMats:ClearAllPoints()
    f.addMats:SetPoint("LEFT", f.listPick, "RIGHT", 8, 0)
    height = cTop + cH + 12
  else
    for _, r in ipairs(f.mats) do r:Hide() end
  end
  T:HideCards(f, card + 1)
  f:SetHeight(height)
end

ns.RefreshPriceWindow = ns.Timed("Price window", ns.RefreshPriceWindow)

-- Opens the window on an item. link: the item's link, for its version and tooltip.
function ns:ShowPriceWindow(id, link)
  id = tonumber(id)
  if not (id and ns.db) then return end
  if not win then build() end
  if win.id ~= id then state.suffix = nil end
  win.id, win.link = id, link
  local suffix = link and ns.VersionOfLink and ns:VersionOfLink(id, link)
  if suffix then state.suffix = suffix end
  ns:RememberItem(id)
  win:Show()
  ns:RefreshPriceWindow()
end

-- The Search button says whether it can search now (the auction house must be open).
function ns:PriceWindowSearchState()
  if not win then return end
  local open = ns:IsAHOpen()
  win.search:SetEnabled(open)
  win.search:SetText(open and "Search on the auction house" or "Search: open the auction house")
end
ns:On("AUCTION_HOUSE_SHOW", function() C_Timer.After(0, function() ns:PriceWindowSearchState() end) end)
ns:On("AUCTION_HOUSE_CLOSED", function() C_Timer.After(0, function() ns:PriceWindowSearchState() end) end)

-- New prices from a scan show while it's open: at most every 5 seconds.
local refreshPending
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  if refreshPending or not (win and win:IsShown()) then return end
  refreshPending = true
  C_Timer.After(5, function() refreshPending = nil; ns:RefreshPriceWindow() end)
end)

-- Alt-click an item in your bags or a chat link (Settings, Tooltips: priceWindow).
local function onModifiedClick(link)
  if not (ns.db and ns.db.settings.priceWindow ~= false) then return end
  if not (IsAltKeyDown and IsAltKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then return end
  local id = ns.ItemIDFromLink(link)
  if id then ns:ShowPriceWindow(id, link) end
end
if HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", onModifiedClick) end
