-- Price history for graphs (History.lua, owner, November 7): every item keeps 90 days day
-- by day, gear versions get a history of their own, and ns:PriceSeries gives a graph
-- every saved point, oldest first.
local T = ...
local ns, S = T.ns, T.S

local function market(name) local k = ns.MarketKey(); ns.db[name][k] = ns.db[name][k] or {}; return ns.db[name][k] end
local function start()
  T.resetDB()
  ns.neutralAH = nil
end
local function today() return ns.LocalDay(time()) end
local function count(s) local n = 0; for _ in (s or ""):gmatch("[^|]+") do n = n + 1 end; return n end

-- A price recorded every day for `n` days up to today.
local function daily(id, n)
  local now = S.now
  for i = n - 1, 0, -1 do
    S.now = now - i * 86400
    ns:RecordPriceHistory(id, 100 + i, 120 + i, 5)
  end
  S.now = now
end

-- Frank, November 7: every item, not only ones you've dealt with.
T.test("Price history: every item keeps 90 days day by day", function()
  start()
  daily(70001, 100)
  T.eq(count(market("history")[70001]), 90, "90 days")
  T.ok(market("historyWeekly")[70001], "older days fold into weeks")
end)

-- Codex review, November 7: the trim runs over several frames, and closing the neutral
-- auction house in between used to send the rest into your faction's history.
T.test("Price history: a trim stays in the market it started in", function()
  start()
  local d = today()
  ns.neutralAH = true
  local nHist, nVer = market("history"), market("historyVersions")
  for id = 1, 450 do
    nHist[id] = (d - 100) .. ":100:100|" .. d .. ":100:100"
    nVer[id] = { [1019] = (d - 100) .. ":100:1|" .. d .. ":100:1" }
  end
  local neutral = ns.MarketKey()
  wipe(S.timers)
  ns:TrimMarketHistory()
  ns.neutralAH = nil   -- the auction house closes
  T.runTimers()
  local home = ns.MarketKey()
  T.ok(neutral ~= home)
  local function n(t) local c = 0; for _ in pairs(t or {}) do c = c + 1 end; return c end
  T.eq(n(ns.db.historyWeekly[neutral]), 450, "every item's old day in the neutral weeks")
  T.eq(n(ns.db.historyVersionsWeekly[neutral]), 450, "and every version's")
  T.eq(n(ns.db.historyWeekly[home]), 0, "nothing in your faction's")
  T.eq(n(ns.db.historyVersionsWeekly[home]), 0)
  T.eq(nHist[450], d .. ":100:100", "today kept")
end)

T.test("Price history: a version of random-stat gear keeps its own days", function()
  start()
  local d = today()
  ns:RecordVersionHistory(70021, { [1019] = { m = 500, q = 2 }, [1200] = { m = 900, q = 1 } })
  ns:RecordVersionHistory(70021, { [1019] = { m = 450, q = 1 } })
  T.eq(market("historyVersions")[70021][1019], d .. ":450:2", "cheapest and most listed that day")
  T.eq(market("historyVersions")[70021][1200], d .. ":900:1")
  T.same(ns:PriceVersions(70021), { 1019, 1200 })
end)

T.test("Price history: a full scan saves each version's price", function()
  start()
  ns.RecordPrice(70031, { { 300, 1, 1019, 4 }, { 400, 2, 1019, 4 }, { 800, 1, 1200, 4 }, { 350, 1, nil, 4 } }, "full")
  local v = market("historyVersions")[70031]
  T.eq(v[1019], today() .. ":300:3")
  T.eq(v[1200], today() .. ":800:1")
end)

T.test("Price history: versions keep 90 days, then weeks, then 52 weeks", function()
  start()
  local now = S.now
  for i = 99, 0, -1 do
    S.now = now - i * 86400
    ns:RecordVersionHistory(70041, { [1019] = { m = 1000 + i, q = 1 } })
  end
  S.now = now
  T.eq(count(market("historyVersions")[70041][1019]), 90)
  T.ok(market("historyVersionsWeekly")[70041][1019])
  -- A version no longer listed is still trimmed once a day.
  S.now = now + 400 * 86400
  ns.db.lastTrim = nil
  T.ready("History.lua")
  T.runTimers()
  T.eq(market("historyVersions")[70041], nil, "old days gone")
  T.eq(market("historyVersionsWeekly")[70041], nil, "and old weeks")
  S.now = now
end)

T.test("Price series: weeks, then days, oldest first, with listed counts", function()
  start()
  daily(70051, 100)
  local all = ns:PriceSeries(70051)
  T.ok(all[1].week, "starts with weeks")
  T.ok(not all[#all].week, "ends with days")
  for i = 2, #all do T.ok(all[i].day > all[i - 1].day, "in order") end
  local last = all[#all]
  T.eq(last.day, today())
  T.eq(last.cheapest, 100)
  T.eq(last.typical, 120)
  T.eq(last.listed, 5)
  local week = ns:PriceSeries(70051, nil, 7)
  T.eq(#week, 8, "the last 7 days and today")
  T.same(ns:PriceSeries(70052), {}, "nothing saved")
end)

-- Codex review, November 7: listed 1,1,2,2,2,2,2 averaged 1 with rounding at each step.
T.test("Price history: a version's weekly listed count is a true average", function()
  start()
  local now, d0 = S.now, today()
  local week = math.floor(d0 / 7) - 20
  for i, q in ipairs({ 1, 1, 2, 2, 2, 2, 2 }) do
    S.now = now + ((week * 7 + i - 1) - d0) * 86400
    ns:RecordVersionHistory(70071, { [1019] = { m = 100, q = q } })
  end
  S.now = now
  ns:RecordVersionHistory(70071, { [1019] = { m = 100, q = 1 } })   -- folds the old days
  T.eq(market("historyVersionsWeekly")[70071][1019], week .. ":100:12:7", "the sum and the days")
  local s = ns:PriceSeries(70071, 1019)
  T.ok(s[1].week)
  T.eq(s[1].listed, 2, "12 / 7 rounds to 2")
end)

T.test("Price history: versions are trimmed a little at a time", function()
  start()
  local d = today()
  local hist = market("historyVersions")
  for id = 1, 450 do hist[id] = { [1019] = (d - 100) .. ":100:1|" .. d .. ":100:1" } end
  local function done()
    local n = 0
    for id = 1, 450 do if hist[id][1019] == d .. ":100:1" then n = n + 1 end end
    return n
  end
  wipe(S.timers)
  ns:TrimMarketHistory()
  T.eq(done(), 200, "200 in the first frame")
  T.runTimers()
  T.eq(done(), 450, "the rest in the next frames")
end)

T.test("Price history: two copies of a version's history merge field by field", function()
  local into = { [1019] = "10:50:1|11:70:2", [1200] = "10:5:5" }
  ns.CombineVersions(into, { [1019] = "10:60:10|12:80:3", [1300] = "11:9:9" }, "day")
  T.eq(into[1019], "10:50:10|11:70:2|12:80:3", "cheaper price, most listed, every day")
  T.eq(into[1200], "10:5:5")
  T.eq(into[1300], "11:9:9")
  local weeks = { [1019] = "3:50:1:1" }
  ns.CombineVersions(weeks, { [1019] = "3:60:10:6" }, "week")
  T.eq(weeks[1019], "3:50:10:6", "the fuller week, with the cheaper price")
end)

-- Codex review, November 7: with 90 days kept, a month's usual price counted every day,
-- so a price that fell 16 days ago still looked like 10,000c. Pricing keeps seeing the
-- last 14 days one by one and older days as weeks, as before.
T.test("Price history: usual prices see days and weeks as before graphs", function()
  start()
  local now = S.now
  for i = 29, 0, -1 do
    S.now = now - i * 86400
    local p = i >= 14 and 10000 or 100
    ns:RecordPriceHistory(70081, p, p, 5)
  end
  S.now = now
  T.eq(count(market("history")[70081]), 30, "all 30 days kept for the graph")
  T.eq(ns:UsualPrice(70081, "month"), 100, "13 days at 100c outweigh 3 weeks at 10,000c")
  local daily, weekly = ns.PricingPoints(70081)
  T.eq(#daily, 14)
  T.ok(#weekly >= 3 and #weekly <= 4, "16 older days as 3 or 4 weeks")
  T.eq(#ns:PriceHistory(70081), 14, "the tooltip still shows 14 days")
end)

T.test("Price series: a version's points", function()
  start()
  local now = S.now
  for i = 2, 0, -1 do
    S.now = now - i * 86400
    ns:RecordVersionHistory(70061, { [1019] = { m = 500 - i, q = i + 1 } })
  end
  S.now = now
  local s = ns:PriceSeries(70061, 1019)
  T.eq(#s, 3)
  T.eq(s[3].cheapest, 500)
  T.eq(s[3].listed, 1)
  T.eq(s[3].typical, nil, "versions have no typical price")
  T.same(ns:PriceSeries(70061, 9999), {})
end)
