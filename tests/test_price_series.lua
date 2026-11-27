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

T.test("Price history: a gear version listed at 1,500,000g is saved (GitHub #22)", function()
  -- The game's %d stops at 2^31 copper (about 214,748g): "integer overflow attempting to
  -- store 15000000300" stopped every full scan short of done. Plain Lua's doesn't, so act
  -- like the game's here.
  start()
  local real = string.format
  string.format = function(fmt, ...)
    if type(fmt) == "string" and fmt:find("%d", 1, true) then
      for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "number" and math.abs(v) >= 2 ^ 31 then error("integer overflow attempting to store " .. v) end
      end
    end
    return real(fmt, ...)
  end
  local ok, err = pcall(ns.RecordPrice, 70051, { { 15000000300, 1, 1019, 4 }, { 500, 1, 1020, 4 } }, "full")
  string.format = real
  T.ok(ok, err)
  local rec = ns.db.prices[ns.MarketKey()][70051]
  T.ok(rec and rec.sx and rec.sx:find("1019:15000000300:1", 1, true), rec and rec.sx)
  T.eq(ns:SuffixPrice(70051, 1019), 15000000300)
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
  -- Hours (Codex review, November 24): the cheaper price, the most listed and the typical
  -- price of the row that saw more, in either order.
  local h1 = { [5] = "400:100:200:2" }
  ns.CombineVersions(h1, { [5] = "400:90:120:50" }, "hour")
  local h2 = { [5] = "400:90:120:50" }
  ns.CombineVersions(h2, { [5] = "400:100:200:2" }, "hour")
  T.eq(h1[5], "400:90:120:50"); T.eq(h2[5], "400:90:120:50")
  local h3, h4 = { [5] = "400:100:200:3" }, { [5] = "400:90:150:3" }
  ns.CombineVersions(h3, { [5] = "400:90:150:3" }, "hour"); ns.CombineVersions(h4, { [5] = "400:100:200:3" }, "hour")
  T.eq(h3[5], "400:90:150:3", "the same count: the lower typical"); T.eq(h4[5], h3[5])
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

-- Frank's /fl perf, November 21: kept per item and day (History.lua pastEntry).
T.test("Price history: usual prices are kept for the day, and follow earlier days' changes", function()
  start()
  local id, d = 70091, today()
  local h = market("history")
  h[id] = ("%d:100:100|%d:100:100|%d:100:100"):format(d - 3, d - 2, d - 1)
  T.eq(ns:UsualPrice(id, "month"), 100)
  local stats = ns:PriceStats(id, "month")
  T.eq(stats and stats.usual, 100)
  -- Today's price comes and changes: today doesn't count, the kept answer stands.
  ns:RecordPriceHistory(id, 900, 900, 5)
  T.eq(ns:UsualPrice(id, "month"), 100)
  T.ok(ns:PriceStats(id, "month") == stats, "the same answer, not worked out again")
  ns:RecordPriceHistory(id, 800, 800, 5)
  T.ok(ns:PriceStats(id, "month") == stats, "still the same after today's price changes again")
  -- An earlier day changes (a partner's day, by hand here): worked out again.
  h[id] = ("%d:300:300|%d:300:300|%d:300:300|%d:800:800"):format(d - 3, d - 2, d - 1, d)
  T.eq(ns:UsualPrice(id, "month"), 300, "an earlier day changed")
  T.eq(ns:PriceStats(id, "month").usual, 300)
  -- A day added before today, after today's entry (out of order): not taken as today's.
  h[id] = h[id] .. ("|%d:500:500"):format(d - 4)
  T.eq(ns:UsualPrice(id, "month"), 300, "median of 300, 300, 300 and 500")
  h[id] = ("%d:300:300|%d:700:700|%d:700:700"):format(d - 3, d - 2, d - 1)
  T.eq(ns:UsualPrice(id, "month"), 700, "a whole new text")
  -- A vendor price change today: only today on, so no usual price yet.
  ns.db.vendorSellChanged[id] = d
  T.eq(ns:UsualPrice(id, "month"), nil, "history before the change left out")
  ns.db.vendorSellChanged[id] = nil
  T.eq(ns:UsualPrice(id, "month"), 700, "and back")
  -- Today's entry at 100 doesn't count today; the next day it does.
  h[id] = h[id] .. ("|%d:100:100"):format(d)
  T.eq(ns:UsualPrice(id, "month"), 700)
  S.now = S.now + 86400
  T.eq(ns:UsualPrice(id, "month"), 300, "median of 100, 300, 700 and 700")
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

-- Frank's eighteenth /fl perf, November 22: after a reload every item's history is read
-- once for the values (thousands of items), and the tables made per day and week were most
-- of Gold making's 86 MB of leftovers. They're read into lists kept between items now: an
-- item with less history after one with more gets only its own days, and little is left.
T.test("Price history: items read one after another keep to their own days, with little left", function()
  start()
  local d, h = today(), market("history")
  local function days(n, price)
    local parts = {}
    for i = n, 1, -1 do parts[#parts + 1] = ("%d:%d:%d"):format(d - i, price, price) end
    return table.concat(parts, "|")
  end
  h[70201] = days(40, 500)   -- 13 days one by one, older ones as weeks
  h[70202] = days(3, 200)
  T.eq(ns:PriceStats(70201, "month").points >= 14, true)
  local st = ns:PriceStats(70202, "month")
  T.eq(st.points, 3, "only its own 3 days")
  T.eq(st.usual, 200); T.eq(st.low, 200)
  T.eq(ns:UsualPrice(70202, "week"), 200)
  local daily, weekly = ns.PricingPoints(70202)
  T.eq(#daily, 3); T.eq(#weekly, 0, "no weeks left over from the item before")

  for i = 1, 100 do h[70300 + i] = days(40, 300 + i) end
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, 100 do
    ns:PriceStats(70300 + i, "month"); ns:UsualPrice(70300 + i, "week")
  end
  local kb = collectgarbage("count") - before
  collectgarbage("restart")
  T.eq(ns:PriceStats(70350, "month").usual, 350)
  T.ok(kb < 500, ("%.0f KB for 100 items' first look (the answers kept for the day included)"):format(kb))
end)

-- Frank, November 24: a day's graph hour by hour, and a week's; hours kept for 7 days.
T.test("Price history: the last week hour by hour", function()
  start()
  local now = S.now
  local h0 = math.floor(now / 3600)
  -- Two scans in one hour: the lower cheapest, the latest typical, the most listed.
  ns:RecordPriceHistory(70061, 500, 600, 4)
  ns:RecordPriceHistory(70061, 450, 650, 2)
  local pts = ns:PriceSeriesHourly(70061)
  T.eq(#pts, 1)
  T.eq(pts[1].hour, h0); T.eq(pts[1].cheapest, 450); T.eq(pts[1].typical, 650); T.eq(pts[1].listed, 4)
  -- Every hour for 8 days: 7 days' worth are kept.
  for i = 8 * 24, 1, -1 do
    S.now = now + 3600 - i * 3600 + 3600 * 8 * 24
    ns:RecordPriceHistory(70062, 100 + i, 110 + i)
  end
  local all = ns:PriceSeriesHourly(70062)
  T.ok(#all <= ns.HOURLY_PRICE_HOURS + 1 and #all >= ns.HOURLY_PRICE_HOURS, "a week of hours: " .. #all)
  for i = 2, #all do T.eq(all[i].hour, all[i - 1].hour + 1, "in order") end
  T.eq(all[#all].listed, nil, "no listed count: none")
  local later = ns:PriceSeriesHourly(70062, all[#all].hour - 2)
  T.eq(#later, 3, "from an hour on")
  -- An item no longer scanned loses its hours at the daily trim.
  S.now = now + 9 * 86400
  ns.db.lastTrim = nil
  T.ready("History.lua")
  T.runTimers()
  T.eq(market("historyHourly")[70061], nil)
  S.now = now
end)

T.test("Price window: hour by hour ranges", function()
  local DAY = 86400
  local now = time({ year = 2026, month = 11, day = 25, hour = 15, min = 20 })   -- a Wednesday
  local from, to, marks = ns.PriceHourAxis("today", now)
  T.eq(date("%H:%M", from), "00:00"); T.eq(to - from, DAY)
  T.eq(#marks, 25, "a mark each hour, both midnights")
  local labels = 0
  for _, m in ipairs(marks) do if m.label then labels = labels + 1 end end
  T.eq(labels, 8, "a label every three hours")
  from, to = ns.PriceHourAxis("24h", now)
  T.eq(to, now); T.eq(from, now - DAY)
  from, to, marks = ns.PriceHourAxis("week", now)
  T.eq(date("%a %H:%M", from), "Mon 00:00"); T.eq(date("%a %H:%M", to), "Mon 00:00"); T.eq(to - from, 7 * DAY)
  local days, noons = 0, 0
  for _, m in ipairs(marks) do if m.strong then days = days + 1 elseif m.label then noons = noons + 1 end end
  T.eq(days, 8); T.eq(noons, 7, "Monday to Sunday at noon")
  from, to = ns.PriceHourAxis("7d", now)
  T.eq(to - from, 7 * DAY)
  -- A Monday is the week's first day, a Sunday its last.
  local sun = time({ year = 2026, month = 11, day = 29, hour = 23 })
  from = ns.PriceHourAxis("week", sun)
  T.eq(date("%d", from), "23")
  T.eq(ns.PriceClock(time({ year = 2026, month = 11, day = 25, hour = 0 })), "12 AM")
  T.eq(ns.PriceClock(time({ year = 2026, month = 11, day = 25, hour = 15 })), "3 PM")
  T.eq(#ns.PRICE_RANGES, 8)
end)

-- Frank, November 25: the day and week graphs were empty until a month (no hours saved
-- before November 24): days with no hours show that day's own point.
T.test("Price window: days before hour by hour saving show their day's point", function()
  local now = time({ year = 2026, month = 11, day = 25, hour = 9, min = 30 })   -- a Wednesday
  local d0 = ns.LocalDay(now)
  local from, to = ns.PriceHourAxis("week", now)
  local h = math.floor(now / 3600)
  local hours = { { hour = h - 1, cheapest = 90, typical = 95 }, { hour = h, cheapest = 80, typical = 85 } }
  local days = {
    { day = d0 - 3, cheapest = 120, typical = 130, listed = 7 },   -- Sunday: before the week
    { day = d0 - 2, cheapest = 110, typical = 115 },               -- Monday
    { day = d0 - 1, cheapest = 100, typical = 105, listed = 4 },   -- Tuesday
    { day = d0, cheapest = 80, typical = 85 },                     -- today: has hours
    { day = d0 - 40, week = true, cheapest = 1, typical = 1 },
  }
  local pts = ns.PriceHourPoints(hours, days, from, to, now)
  T.eq(#pts, 4, "Monday, Tuesday, and today's two hours")
  T.ok(pts[1].allDay and pts[1].day == d0 - 2, "Monday first")
  T.eq(date("%a %H:%M", pts[1].at), "Mon 12:00", "at noon")
  T.eq(pts[2].listed, 4)
  T.eq(pts[3].hour, h - 1); T.eq(pts[4].hour, h)
  -- Today with no hours yet: today's point, not after the time now.
  pts = ns.PriceHourPoints({}, { { day = d0, cheapest = 80, typical = 85 } }, ns.PriceHourAxis("today", now), select(2, ns.PriceHourAxis("today", now)), now)
  T.eq(#pts, 1); T.eq(pts[1].at, now)
end)
