-- Price history for graphs (History.lua, owner, November 7): items you've dealt with keep
-- 90 days day by day, gear versions get a history of their own, and ns:PriceSeries
-- gives a graph every saved point, oldest first.
local T = ...
local ns, S = T.ns, T.S

local function market(name) local k = ns.MarketKey(); ns.db[name][k] = ns.db[name][k] or {}; return ns.db[name][k] end
local function start()
  T.resetDB()
  ns:ForgetDealtWith()
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

T.test("Price history: items you've dealt with keep 90 days day by day, others 14", function()
  start()
  ns.db.purchases = { { t = time(), c = "x", id = 70001, q = 1, a = 100 } }
  ns:ForgetDealtWith()
  daily(70001, 100)
  daily(70002, 100)
  T.eq(count(market("history")[70001]), 90, "bought: 90 days")
  T.eq(count(market("history")[70002]), 14, "never touched: 14 days")
  T.ok(market("historyWeekly")[70001], "older days fold into weeks")
end)

T.test("Price history: what counts as dealt with", function()
  start()
  ns.db.itemNames[70011] = "Sold Thing"
  ns.db.sales = { { t = time(), c = "x", n = "Sold Thing", a = 5 } }
  ns.db.vendorLog = { { t = time(), c = "x", id = 70012, q = 1, a = 5, s = "buy" }, { t = time(), c = "x", id = 70013, q = 1, a = 5, s = "sell" } }
  ns.db.shopping.lists = { { name = "L", items = { { id = 70014 } } } }
  ns.db.settings.watch[70015] = true
  ns.db.chars.x = { profs = { Tailoring = { recipes = { [1] = { out = 70016, r = { { 70017, 2 } } } } } } }
  ns.db.inventory.x = { bags = { [70018] = 3 }, bank = { [70019] = 1 } }
  for id = 70011, 70019 do
    T.eq(ns.DailyDays(id), id == 70013 and 14 or 90, "item " .. id)
  end
  ns.db.settings.watch[70015] = nil
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
  ns.db.purchases = { { t = time(), c = "x", id = 70051, q = 1, a = 100 } }
  ns:ForgetDealtWith()
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
