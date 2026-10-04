-- How long History.lua keeps things, and how old data is folded (the owner's rules):
--   ledger logs one by one for 30 days, then monthly totals per item for a year;
--   gold hourly for 14 days, then daily for a year, then monthly;
--   money in and out daily for a year, then on the 1st of its month;
--   prices daily for 14 days, weekly for 52 weeks; listed counts and sell speed 30 days.
-- Folding happens in History.lua's login callback (T.ready) and TrimMarketHistory.
local T = ...
local ns, S = T.ns, T.S
local ME = ns.CharKey()
local DAY, HOUR = 86400, 3600

local function at(y, m, d, h) return os.time({ year = y, month = m, day = d, hour = h or 12 }) end
local NOW = at(2026, 3, 15, 12)
local function copy(t) return ns.Deserialize(ns.Serialize(t)) end

-- History.lua's login tidy-up: gold, ledger and money folded; prices trimmed (on a timer).
local function tidy()
  ns.db.lastTrim = nil
  T.ready("History.lua")
  T.runTimers()
end

local function start()
  T.resetDB()
  S.now = NOW
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = {}, {}, {}, {}
  ns.db.gold, ns.db.money = {}, {}
end

-- Copper and items over the logs and the monthly totals together.
local function ledgerTotals()
  local a, q = 0, 0
  for _, list in ipairs({ ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths }) do
    for _, e in ipairs(list) do a, q = a + (e.a or 0), q + (e.q or 1) end
  end
  return a, q
end

---------------------------------------------------------------------------
-- Ledger
---------------------------------------------------------------------------
local function someLedger()
  ns.db.sales = {
    { t = NOW - 40 * DAY, c = ME, n = "Linen Cloth", a = 100, q = 2 },
    { t = NOW - 30 * DAY - 1, c = ME, n = "Linen Cloth", a = 50, q = 1 },
    { t = NOW - 30 * DAY, c = ME, n = "Linen Cloth", a = 70, q = 1 },   -- exactly 30 days: kept
    { t = NOW - DAY, c = ME, n = "Silk Cloth", a = 10, q = 1 },
  }
  ns.db.purchases = {
    { t = NOW - 35 * DAY, c = ME, id = 2589, a = 300, q = 20 },
    { t = NOW - 2 * DAY, c = ME, id = 2589, a = 40, q = 2 },
  }
  ns.db.vendorLog = {
    { t = NOW - 33 * DAY, c = ME, id = 159, a = 25, q = 5, s = "buy" },
    { t = NOW - 32 * DAY, c = ME, id = 2589, a = 9, q = 3, s = "sell" },
    { t = NOW - 3 * DAY, c = ME, id = 159, a = 5, q = 1, s = "buy" },
  }
end

T.test("Ledger: entries inside 30 days are kept as they are", function()
  start()
  someLedger()
  local sales, buys, vendor = copy(ns.db.sales), copy(ns.db.purchases), copy(ns.db.vendorLog)
  tidy()
  T.same(ns.db.sales, { sales[3], sales[4] }, "sales")
  T.same(ns.db.purchases, { buys[2] }, "purchases")
  T.same(ns.db.vendorLog, { vendor[3] }, "vendor")
end)

T.test("Ledger: older entries become monthly totals per item, nothing lost", function()
  start()
  someLedger()
  local a, q = ledgerTotals()
  tidy()
  local a2, q2 = ledgerTotals()
  T.eq(a2, a, "copper")
  T.eq(q2, q, "items")
  local feb = at(2026, 2, 1, 12)
  local linen
  for _, m in ipairs(ns.db.ledgerMonths) do if m.n == "Linen Cloth" then linen = m end end
  T.same(linen, { t = feb, c = ME, k = "sale", n = "Linen Cloth", q = 3, a = 150, cnt = 2, mx = 100 })
  T.eq(#ns.db.ledgerMonths, 4, "Linen sales, the purchase, a vendor buy, a vendor sale")
end)

T.test("Ledger: folding twice is the same as once", function()
  start()
  someLedger()
  tidy()
  local once = copy({ ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths })
  tidy()
  T.same({ ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths }, once)
end)

T.test("Ledger: a later fold adds to the month already there", function()
  start()
  someLedger()
  tidy()
  -- The Linen sale kept at exactly 30 days (February 13) and one more in March.
  ns.db.sales[#ns.db.sales + 1] = { t = NOW + 10 * DAY, c = ME, n = "Linen Cloth", a = 1, q = 1 }
  local a = ledgerTotals()
  S.now = at(2026, 4, 30, 12)   -- now they're all older than 30 days
  tidy()
  T.eq((ledgerTotals()), a, "copper")
  local n = 0
  for _, m in ipairs(ns.db.ledgerMonths) do if m.n == "Linen Cloth" and m.t == at(2026, 2, 1, 12) then n = n + 1; T.eq(m.a, 220) end end
  T.eq(n, 1, "one February total for Linen")
end)

T.test("Ledger: across a year change, each entry goes to its own month", function()
  start()
  ns.db.sales = {
    { t = at(2025, 12, 31, 23), c = ME, n = "Wool Cloth", a = 30, q = 1 },
    { t = at(2026, 1, 1, 1), c = ME, n = "Wool Cloth", a = 40, q = 1 },
  }
  tidy()
  local byMonth = {}
  for _, m in ipairs(ns.db.ledgerMonths) do byMonth[m.t] = m.a end
  T.eq(byMonth[at(2025, 12, 1, 12)], 30, "December 2025")
  T.eq(byMonth[at(2026, 1, 1, 12)], 40, "January 2026")
end)

T.test("Ledger: monthly totals are kept a year", function()
  start()
  ns.db.ledgerMonths = {
    { t = NOW - 365 * DAY, c = ME, k = "sale", n = "A", q = 1, a = 1, cnt = 1, mx = 1 },
    { t = NOW - 365 * DAY - 1, c = ME, k = "sale", n = "B", q = 1, a = 1, cnt = 1, mx = 1 },
    { t = NOW - 100 * DAY, c = ME, k = "sale", n = "C", q = 1, a = 1, cnt = 1, mx = 1 },
  }
  tidy()
  local names = {}
  for _, m in ipairs(ns.db.ledgerMonths) do names[#names + 1] = m.n end
  T.eq(table.concat(names, ","), "A,C")
end)

---------------------------------------------------------------------------
-- Gold over time: a reading each hour; older ones thinned to the last of each day,
-- then of each month. (Readings aren't added up, so "nothing lost" means the last
-- reading of each day and month is kept as it was.)
---------------------------------------------------------------------------
local H = math.floor(NOW / HOUR)
local function gold(hours)
  ns.db.gold[ME] = {}
  for h, v in pairs(hours) do ns.db.gold[ME][h] = v end
end
local function hourOf(y, m, d, h) return math.floor(at(y, m, d, h) / HOUR) end

T.test("Gold: hourly readings inside 14 days are kept", function()
  start()
  gold({ [H] = 1, [H - 1] = 2, [H - 300] = 3, [H - 336] = 4 })
  tidy()
  T.same(ns.db.gold[ME], { [H] = 1, [H - 1] = 2, [H - 300] = 3, [H - 336] = 4 })
end)

T.test("Gold: older than 14 days, the last reading of each day", function()
  start()
  local day = math.floor((H - 400) / 24) * 24   -- the first hour of a day 16-17 days ago
  gold({ [H - 336] = 9, [H - 337] = 8, [H - 340] = 7, [day + 1] = 1, [day + 5] = 2, [day + 23] = 3 })
  tidy()
  T.same(ns.db.gold[ME], { [H - 336] = 9, [H - 337] = 8, [day + 23] = 3 },
    "14 days exactly stays hourly; the rest one per day")
end)

T.test("Gold: older than a year, the last reading of each month", function()
  start()
  gold({
    [hourOf(2025, 1, 10, 5)] = 1, [hourOf(2025, 1, 31, 23)] = 2,
    [hourOf(2025, 2, 1, 1)] = 3, [hourOf(2025, 2, 20, 8)] = 4,
    [hourOf(2025, 6, 1, 1)] = 5, [hourOf(2025, 6, 1, 9)] = 6,   -- inside the year: daily
  })
  tidy()
  T.same(ns.db.gold[ME], { [hourOf(2025, 1, 31, 23)] = 2, [hourOf(2025, 2, 20, 8)] = 4, [hourOf(2025, 6, 1, 9)] = 6 })
end)

T.test("Gold: thinning twice is the same as once", function()
  start()
  local g = {}
  for h = H - 24 * 500, H, 7 do g[h] = h % 1000 + 1 end
  gold(g)
  tidy()
  local once = copy(ns.db.gold)
  tidy()
  T.same(ns.db.gold, once)
end)

---------------------------------------------------------------------------
-- Money in and out by source per day; older than a year, onto the 1st of its month.
---------------------------------------------------------------------------
local TODAY = ns.LocalDay(NOW)
local function dayOf(y, m, d) return ns.LocalDay(at(y, m, d, 12)) end
local function moneyTotals()
  local out = {}
  for _, days in pairs(ns.db.money) do
    for _, src in pairs(days) do for s, amt in pairs(src) do out[s] = (out[s] or 0) + amt end end
  end
  return out
end

local function someMoney()
  ns.db.money[ME] = {
    [TODAY - 1] = { repair = 100, loot = 5 },
    [TODAY - 365] = { repair = 7 },              -- a year exactly: kept as a day
    [TODAY - 366] = { repair = 11, quest = 3 },  -- March 14 2025
    [dayOf(2025, 3, 1)] = { repair = 2 },
    [dayOf(2025, 2, 1)] = { loot = 1 },
    [dayOf(2025, 2, 17)] = { loot = 10 },
    [dayOf(2024, 12, 31)] = { otherOut = 50 },
    [dayOf(2025, 1, 1)] = { otherOut = 60 },
  }
end

T.test("Money: days inside a year are kept as they are", function()
  start()
  someMoney()
  tidy()
  local m = ns.db.money[ME]
  T.same(m[TODAY - 1], { repair = 100, loot = 5 })
  T.same(m[TODAY - 365], { repair = 7 })
end)

T.test("Money: older days go onto the 1st of their month, nothing lost", function()
  start()
  someMoney()
  local before = moneyTotals()
  tidy()
  T.same(moneyTotals(), before, "totals by source")
  local m = ns.db.money[ME]
  T.eq(m[TODAY - 366], nil, "folded")
  T.same(m[dayOf(2025, 3, 1)], { repair = 13, quest = 3 }, "March 2025")
  T.same(m[dayOf(2025, 2, 1)], { loot = 11 }, "February 2025")
  T.same(m[dayOf(2024, 12, 1)], { otherOut = 50 }, "December 2024, across the year change")
  T.same(m[dayOf(2025, 1, 1)], { otherOut = 60 }, "January 2025")
end)

T.test("Money: folding twice is the same as once", function()
  start()
  someMoney()
  tidy()
  local once = copy(ns.db.money)
  tidy()
  T.same(ns.db.money, once)
end)

---------------------------------------------------------------------------
-- Prices (TrimMarketHistory, once a day at login, 200 items at a time)
---------------------------------------------------------------------------
local D = TODAY
local W = math.floor(D / 7)
local function market(name) local k = ns.MarketKey(); ns.db[name][k] = ns.db[name][k] or {}; return ns.db[name][k] end
local function days(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = table.concat(e, ":") end
  return table.concat(out, "|")
end

local function somePrices(id)
  market("history")[id] = days({ { D - 28, 100, 110 }, { D - 21, 200, 210 }, { D - 14, 300, 310 },
    { D - 13, 400, 410 }, { D - 1, 500, 510 }, { D, 600, 610 } })
  market("historyQty")[id] = days({ { D - 31, 5 }, { D - 30, 6 }, { D - 29, 7 }, { D, 8 } })
  market("historySold2")[id] = days({ { D - 30, 1, 2, 3 }, { D - 29, 4, 5, 6 } })
end
local function trimmed(id)
  return { market("history")[id], market("historyWeekly")[id], market("historyQty")[id], market("historySold2")[id],
    market("historyAll")[id] }
end

T.test("Prices: the last 14 days stay daily, older days become weekly", function()
  start()
  somePrices(60001)
  tidy()
  T.eq(market("history")[60001], days({ { D - 13, 400, 410 }, { D - 1, 500, 510 }, { D, 600, 610 } }))
  T.eq(market("historyWeekly")[60001], ("%d:100:110:1|%d:200:210:1|%d:300:310:1"):format(
    math.floor((D - 28) / 7), math.floor((D - 21) / 7), math.floor((D - 14) / 7)))
end)

T.test("Prices: listed counts and sell speed keep 30 days", function()
  start()
  somePrices(60002)
  tidy()
  T.eq(market("historyQty")[60002], days({ { D - 29, 7 }, { D, 8 } }))
  T.eq(market("historySold2")[60002], days({ { D - 29, 4, 5, 6 } }))
end)

T.test("Prices: weekly averages keep 52 weeks", function()
  start()
  market("historyWeekly")[60003] = days({ { W - 53, 1, 1, 7 }, { W - 52, 2, 2, 7 }, { W - 51, 3, 3, 7 }, { W - 1, 4, 4, 7 } })
  tidy()
  T.eq(market("historyWeekly")[60003], days({ { W - 51, 3, 3, 7 }, { W - 1, 4, 4, 7 } }))
end)

T.test("Prices: a day joining a week already there is averaged in", function()
  start()
  local w = math.floor((D - 20) / 7)
  market("historyWeekly")[60004] = days({ { w, 150, 200, 2 } })
  market("history")[60004] = days({ { w * 7, 120, 500 }, { D, 1, 1 } })
  tidy()
  T.eq(market("historyWeekly")[60004], days({ { w, 120, 300, 3 } }), "(200 x 2 + 500) / 3")
end)

T.test("Prices: an item no longer listed still counts its last day for all time", function()
  start()
  market("history")[60005] = days({ { D - 20, 100, 150 } })
  market("historyAll")[60005] = "90:1000:10"
  tidy()
  T.eq(market("history")[60005], nil)
  T.eq(market("historyAll")[60005], "90:1150:11")
end)

T.test("Prices: trimming twice is the same as once", function()
  start()
  somePrices(60006)
  market("history")[60007] = days({ { D - 20, 100, 150 } })
  tidy()
  local once = copy({ trimmed(60006), trimmed(60007) })
  tidy()
  T.same({ trimmed(60006), trimmed(60007) }, once)
end)

T.test("Prices: trimmed a little at a time, the end is the same as all at once", function()
  start()
  somePrices(1)
  tidy()
  local one = trimmed(1)   -- one item: done in a single step
  start()
  for id = 1, 450 do somePrices(id) end
  ns:TrimMarketHistory()
  local done = 0
  for id = 1, 450 do if market("historyQty")[id] == one[3] then done = done + 1 end end
  T.eq(done, 200, "200 items in the first step")
  T.runTimers()
  for id = 1, 450 do T.same(trimmed(id), one, "item " .. id) end
end)

T.test("Prices: trimmed once a day, at login", function()
  start()
  ns.db.lastTrim = nil
  T.ready("History.lua")
  T.eq(#S.timers, 1, "a trim waits a few seconds after login")
  T.runTimers()
  T.ready("History.lua")
  T.eq(#S.timers, 0, "not again the same day")
  S.now = NOW + DAY
  T.ready("History.lua")
  T.eq(#S.timers, 1, "again the next day")
end)

---------------------------------------------------------------------------
-- Reference data is never trimmed
---------------------------------------------------------------------------
T.test("Recipes, vendors, vendor prices, item names and characters are untouched", function()
  start()
  local old = NOW - 3 * 365 * DAY
  ns.db.recipeBook = { Tailoring = { [1] = { n = "Bolt", out = 2996, r = { { 2589, 2 } } } } }
  ns.db.recipeSources = { bolt = { trainer = { kind = "trainer", t = old } } }
  ns.db.vendors = { [123] = { name = "Vendor", t = old } }
  ns.db.vendorBuy[2320] = { p = 10, t = old }
  ns.db.vendorSell[2589] = 3
  ns.db.vendorSellChanged[2589] = ns.LocalDay(old)
  ns.db.itemNames[2589] = "Linen Cloth"
  ns.db.recipeTypes[1] = "sells"
  ns.db.chars[ME] = { name = "Tester", realm = "Testrealm", updated = old,
    profs = { Tailoring = { rank = 1, recipes = { [1] = { n = "Bolt", out = 2996, r = { { 2589, 2 } } } } } } }
  ns.db.crates[5] = { name = "Crate", bundles = {} }
  someLedger(); someMoney(); somePrices(60008)
  local names = { "recipeBook", "recipeSources", "vendors", "vendorBuy", "vendorSell", "vendorSellChanged",
    "itemNames", "recipeTypes", "chars", "crates" }
  local before = {}
  for _, k in ipairs(names) do before[k] = copy(ns.db[k]) end
  tidy()
  S.now = NOW + 400 * DAY
  tidy()
  for _, k in ipairs(names) do T.same(ns.db[k], before[k], k) end
end)

---------------------------------------------------------------------------
-- Logs with a size limit
---------------------------------------------------------------------------
T.test("Sessions: the last 100 are kept", function()
  start()
  ns.db.sessions = {}
  for i = 1, 100 do ns.db.sessions[i] = { kind = "general", t = i } end
  ns.db.liveSession = { t = NOW - HOUR, char = ME, money = { vendorSell = 500 }, loot = {} }
  T.ok(ns:StopGeneralSession(true), "kept")
  T.eq(#ns.db.sessions, 100)
  T.eq(ns.db.sessions[1].t, 2, "the oldest went")
  T.eq(ns.db.sessions[100].earned, 500, "the new one is last")
end)

T.test("Disenchants: the last 1,000 are kept", function()
  start()
  ns.db.disenchants = {}
  for i = 1, 1000 do ns.db.disenchants[i] = { t = i, mats = {} } end
  GetNumLootItems = function() return 1 end
  GetLootSlotInfo = function() return nil, nil, 2 end
  GetLootSlotLink = function() return "|cffffffff|Hitem:10940::::::::|h[Strange Dust]|h|r" end
  T.fire("UNIT_SPELLCAST_START", "player", nil, 13262)
  T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 13262)
  T.fire("LOOT_OPENED")
  T.runTimers()
  GetNumLootItems, GetLootSlotInfo, GetLootSlotLink = nil, nil, nil
  T.eq(#ns.db.disenchants, 1000)
  T.eq(ns.db.disenchants[1].t, 2, "the oldest went")
  T.eq(ns.db.disenchants[1000].mats[10940], 2, "the new one is last")
end)
