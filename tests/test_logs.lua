-- The ledger's logs as they're written (History.lua addLog, through the game's own
-- events): vendor trades of the same item within a minute become one entry, and the
-- size limit on the logs.
local T = ...
local ns, S = T.ns, T.S
local ME = ns.CharKey()
local NOW = os.time({ year = 2026, month = 3, day = 15, hour = 12 })

-- At a vendor with 1000g. History.lua notes the gold at login.
local function atVendor(item)
  S.now, S.money = NOW, 10000000
  S.merchant[1] = item
  ns.db.vendorLog = {}
  T.fire("PLAYER_ENTERING_WORLD")
  T.fire("MERCHANT_SHOW")
end

-- Buy from the vendor's first slot: the game takes the gold a moment later.
local function buy(qty, copper)
  BuyMerchantItem(1, qty)
  S.money = S.money - copper
  T.fire("PLAYER_MONEY")
end

T.test("A vendor purchase is logged", function()
  atVendor(159)
  buy(5, 125)
  T.eq(#ns.db.vendorLog, 1)
  local e = ns.db.vendorLog[1]
  T.same(e, { t = NOW, c = ME, id = 159, q = 5, a = 125, s = "buy" })
end)

T.test("The same item at the same price within a minute is one entry", function()
  atVendor(159)
  buy(5, 125)
  S.now = NOW + 60
  buy(3, 75)
  T.eq(#ns.db.vendorLog, 1)
  local e = ns.db.vendorLog[1]
  T.eq(e.q, 8)
  T.eq(e.a, 200)
  T.eq(e.t, NOW + 60, "the time of the last one")
end)

T.test("More than a minute apart: two entries", function()
  atVendor(159)
  buy(5, 125)
  S.now = NOW + 61
  buy(3, 75)
  T.eq(#ns.db.vendorLog, 2)
end)

T.test("A different price each: two entries", function()
  atVendor(159)
  buy(5, 125)
  buy(5, 150)
  T.eq(#ns.db.vendorLog, 2)
end)

-- Past LOG_SIZE (10,000) entries the oldest goes into its month's total (History.lua
-- addLog; found by this test as a copper loss, fixed October 4).
T.test("A full log doesn't lose an entry from the last 30 days", function()
  atVendor(159)
  local log = ns.db.vendorLog
  for i = 1, 10000 do log[i] = { t = NOW - 20 * 86400 + i * 60, c = ME, id = 100000 + i, q = 1, a = 1, s = "buy" } end
  S.now = NOW + 10000 * 60
  buy(1, 100)
  local total = 0
  for _, e in ipairs(ns.db.vendorLog) do total = total + e.a end
  for _, m in ipairs(ns.db.ledgerMonths) do total = total + m.a end
  T.eq(total, 10000 + 100, "every copper still counted")
end)
