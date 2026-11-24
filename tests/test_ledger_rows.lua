-- The Ledger draws only the rows in view, the rest as you scroll (Frank's tenth /fl perf,
-- November 21). Rows are made as they come into view, so a jump down the scroll bar leaves
-- gaps in the pool: a refresh and the selection marks must cope (Codex review, November 21:
-- rows[21]:Hide() on a missing row).
local T = ...
local ns, S = T.ns, T.S
local L = ns._ledgerTest
local ME = ns.CharKey()

T.test("Ledger rows: a jump down the list and back, then a refresh, with gaps in the rows", function()
  local real = { ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths, ns.db.settings.ledger }
  -- (Dashboard.lua's character choices aren't loaded in the tests: everyone counts.)
  local realChoice = { ns.IsCharChoice, ns.CharChoiceHas, ns.CharacterOptions }
  ns.IsCharChoice = ns.IsCharChoice or function() return true end
  ns.CharChoiceHas = ns.CharChoiceHas or function() return true end
  ns.CharacterOptions = ns.CharacterOptions or function() return { { value = "all", label = "All" } } end
  local ok, err = pcall(function()
    ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = {}, {}, {}
    ns.db.sales = {}
    -- (Each an hour apart, so none are grouped into one row.)
    for i = 1, 120 do ns.db.sales[i] = { t = S.now - i * 3600, c = ME, n = "Row Test " .. i, q = 1, a = 10 } end
    ns.db.settings.ledger = { tab = "sales", range = "all", char = "all", sort = {}, group = "all", rarity = "all" }
    if not L.frame() then ns:BuildLedger(S.dummy()) end
    local F = L.frame()
    F.IsShown = function() return true end
    local top = 0
    F.sf.GetVerticalScroll = function() return top end
    F.sf.GetHeight = function() return 200 end   -- (10 rows of 20)
    ns:RefreshLedger()
    T.runTimers()   -- (the list is built over several frames, then drawn)
    local function made()
      local n, max = 0, 0
      for i in pairs(L.rows()) do n = n + 1; if i > max then max = i end end
      return n, max
    end
    local n = made()
    T.ok(n > 0 and n < 120, "only the rows in view and a few more: " .. n)
    top = 64 * 20
    L.drawVisible()
    top = 43 * 20
    L.drawVisible()
    local _, max = made()
    T.ok(max >= 80, "rows far down made: " .. max)
    T.eq(L.rows()[25], nil, "a gap in the rows")
    for _, r in pairs(L.rows()) do r.Hide = function(self) self.hidden = true end end
    ns:RefreshLedger()   -- (hid every row with rows[i]:Hide(): an error at the gap, or stopped there)
    T.runTimers()
    T.ok(L.rows()[80] and L.rows()[80].hidden, "a far row out of view is hidden too")
  end)
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths, ns.db.settings.ledger =
    real[1], real[2], real[3], real[4], real[5]
  ns.IsCharChoice, ns.CharChoiceHas, ns.CharacterOptions = realChoice[1], realChoice[2], realChoice[3]
  local F = L.frame()
  if F then F.IsShown = function() return false end end
  T.runTimers()
  assert(ok, err)
end)

-- Frank's twenty-first /fl perf, November 22: each build of the Ledger list made a new row
-- for every trade, 294 MB of leftovers in 7 minutes while the other account synced. Rows
-- are kept between builds now; grouping and the All tab work on copies.
T.test("Ledger rows: kept between builds, and grouping never changes a kept row", function()
  local T0 = time() - 3600
  local savedSales, savedBuys, savedVendor = ns.db.sales, ns.db.purchases, ns.db.vendorLog
  local ok, err = pcall(function()
    ns.db.sales, ns.db.vendorLog = {}, {}
    ns.db.purchases = {
      { t = T0, c = "Row Tester-Testrealm", id = 97801, q = 2, a = 100 },
      { t = T0 + 10, c = "Row Tester-Testrealm", id = 97801, q = 3, a = 150 },   -- (grouped with the first)
    }
    local all = function() return true end
    local first = ns.LedgerRecords("purchases", 0, all, "")
    T.eq(#first, 1, "two purchases close together as one row")
    T.eq(first[1].qty, 5); T.eq(first[1].total, 250)
    local again = ns.LedgerRecords("purchases", 0, all, "")
    T.eq(again[1].qty, 5, "the kept rows weren't changed by the first grouping")
    T.eq(again[1].total, 250)
    local both = ns.LedgerRecords("all", 0, all, "")
    local buy
    for _, r in ipairs(both) do if r.kind == "Auction purchase" then buy = r end end
    T.eq(buy and L.amountOf(buy), -250, "All: money out (worked out where shown)")
    T.eq(buy and buy.amount, nil, "not written on the kept row")
    local after = ns.LedgerRecords("purchases", 0, all, "")
    T.eq(after[1].amount, nil, "Purchases: the All tab's sign isn't on its row")
    -- A changed entry (a vendor trade merged into it) gets a new row.
    ns.db.purchases[2] = nil
    local one = ns.LedgerRecords("purchases", 0, all, "")
    T.eq(one[1].qty, 2)
    ns.db.purchases[1].q, ns.db.purchases[1].a = 4, 200
    one = ns.LedgerRecords("purchases", 0, all, "")
    T.eq(one[1].qty, 4, "the entry changed: its row too"); T.eq(one[1].total, 200)
  end)
  ns.db.sales, ns.db.purchases, ns.db.vendorLog = savedSales, savedBuys, savedVendor
  assert(ok, err)
end)

-- Frank's twenty-second /fl perf, November 22: each build made a new row for every group of
-- similar trades. A group is reused while its trades are the same rows.
T.test("Ledger rows: a group of trades is reused between builds, and rebuilt when one changes", function()
  local T0 = time() - 3600
  local saved = { ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths }
  local ok, err = pcall(function()
    ns.db.sales, ns.db.vendorLog, ns.db.ledgerMonths = {}, {}, {}
    ns.db.purchases = {
      { t = T0, c = "Group Tester-Testrealm", id = 97811, q = 1, a = 50 },
      { t = T0 + 5, c = "Group Tester-Testrealm", id = 97811, q = 1, a = 50 },
      { t = T0 + 9, c = "Group Tester-Testrealm", id = 97811, q = 2, a = 100 },
    }
    local all = function() return true end
    local a = ns.LedgerRecords("purchases", 0, all, "")
    local b = ns.LedgerRecords("purchases", 0, all, "")
    T.eq(#a, 1); T.eq(a[1].qty, 4); T.eq(a[1].total, 200)
    T.ok(a[1] == b[1], "the same group row, not a new one")
    ns.LedgerRecords("all", 0, all, "")
    local c = ns.LedgerRecords("purchases", 0, all, "")
    T.ok(c[1] == a[1], "still the same after the All tab")
    T.eq(c[1].amount, nil, "the All tab's sign isn't written on it")
    ns.db.purchases[3].q, ns.db.purchases[3].a = 3, 150
    local d = ns.LedgerRecords("purchases", 0, all, "")
    T.eq(d[1].qty, 5, "a trade in it changed: worked out again"); T.eq(d[1].total, 250)
  end)
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = saved[1], saved[2], saved[3], saved[4]
  assert(ok, err)
end)

-- Frank's twenty-third /fl perf, November 22: the All tab copied every kept row to sign it,
-- 88 MB in 7 builds. Its rows are the kept rows now, the same objects as in Purchases.
T.test("Ledger rows: the All tab shows the kept rows themselves, signed where shown", function()
  local T0 = time() - 3600
  local saved = { ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths }
  local ok, err = pcall(function()
    ns.db.vendorLog, ns.db.ledgerMonths = {}, {}
    ns.db.sales = { { t = T0, c = "All Tester-Testrealm", n = "All Test Ore", q = 1, a = 300 } }
    ns.db.purchases = { { t = T0 + 100, c = "All Tester-Testrealm", id = 97821, q = 1, a = 70 } }
    local all = function() return true end
    local buys = ns.LedgerRecords("purchases", 0, all, "")
    local rows = ns.LedgerRecords("all", 0, all, "")
    local sale, buy
    for _, r in ipairs(rows) do
      if r.kind == "Auction sale" then sale = r elseif r.kind == "Auction purchase" then buy = r end
    end
    T.ok(buy == buys[1], "the same row as the Purchases tab's")
    T.eq(L.amountOf(sale), 300); T.eq(L.amountOf(buy), -70)
  end)
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = saved[1], saved[2], saved[3], saved[4]
  assert(ok, err)
end)

-- Frank, November 22: "can the ledger update while im on the page as the other account or
-- the account im on does things without causing major lag?" A trade logged here refreshes
-- an open Ledger a second later, once for a burst; a closed one isn't touched.
T.test("Ledger: a trade logged here refreshes it while it's open, once for a burst", function()
  if not L.frame() then ns:BuildLedger(S.dummy()) end
  local F = L.frame()
  local realVisible, realRefresh = F.IsVisible, ns.RefreshLedger
  local refreshes = 0
  local ok, err = pcall(function()
    ns.RefreshLedger = function() refreshes = refreshes + 1 end
    F.IsVisible = function() return true end
    ns:LedgerChanged(); ns:LedgerChanged(); ns:LedgerChanged()
    T.eq(refreshes, 0, "not at once")
    T.runTimers()
    T.eq(refreshes, 1, "once, a second later")
    F.IsVisible = function() return false end
    ns:LedgerChanged()
    T.runTimers()
    T.eq(refreshes, 1, "closed: nothing")
  end)
  F.IsVisible, ns.RefreshLedger = realVisible, realRefresh
  T.runTimers()
  assert(ok, err)
end)

-- Frank's screenshot, November 22: the other account's day totals (mail sent, deposits back)
-- sat at the top of the day, above that morning's trades, as they were dated noon. They're
-- dated to the very start of their day now: the same date, below the day's own times.
T.test("Ledger: a day total sits at the start of its day, below that morning's entries", function()
  local saved = { ns.db.money, ns.db.otherLog, ns.db.otherLogSince, ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths }
  local ok, err = pcall(function()
    ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = {}, {}, {}, {}
    local morning = time({ year = 2026, month = 11, day = 22, hour = 8, min = 30 })
    local partner = "Day Tester-Testrealm"
    ns.db.money = { [partner] = { [ns.LocalDay(morning)] = { mailOut = 1080 } } }
    ns.db.otherLog = { { t = morning, c = ME, s = "quest", a = 250 } }
    ns.db.otherLogSince = { [ME] = morning - 86400 * 2 }
    local rows = ns.LedgerRecords("other", 0, function() return true end, "")
    local total, quest
    for _, r in ipairs(rows) do if r.day then total = r elseif r.kind then quest = r end end
    T.ok(total and quest, "both rows")
    T.ok(total.t < quest.t, "the day total is dated before that morning's quest")
    T.eq(date("%Y-%m-%d", total.t), date("%Y-%m-%d", morning), "on the same day")
  end)
  ns.db.money, ns.db.otherLog, ns.db.otherLogSince = saved[1], saved[2], saved[3]
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = saved[4], saved[5], saved[6], saved[7]
  assert(ok, err)
end)
