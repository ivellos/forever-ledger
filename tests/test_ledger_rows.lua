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
    T.eq(buy and buy.amount, -250, "All: money out")
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
    T.eq(c[1].amount, nil, "the All tab's sign went on a copy")
    ns.db.purchases[3].q, ns.db.purchases[3].a = 3, 150
    local d = ns.LedgerRecords("purchases", 0, all, "")
    T.eq(d[1].qty, 5, "a trade in it changed: worked out again"); T.eq(d[1].total, 250)
  end)
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = saved[1], saved[2], saved[3], saved[4]
  assert(ok, err)
end)
