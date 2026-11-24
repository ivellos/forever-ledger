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

-- Codex review, November 5: folded here, then sent again by the partner, it counted twice.
T.test("A full log folds your own entries, never a partner's", function()
  atVendor(159)
  ns.db.booksFrom = { ["Partner-Testrealm"] = "Partner" }
  ns.db.ledgerMonths = {}
  local log = ns.db.vendorLog
  log[1] = { t = NOW - 25 * 86400, c = "Partner-Testrealm", id = 99, q = 1, a = 100, s = "buy" }
  for i = 1, 10000 do log[i + 1] = { t = NOW - 20 * 86400 + i * 60, c = ME, id = 100000 + i, q = 1, a = 1, s = "buy" } end
  S.now = NOW + 10000 * 60
  buy(1, 100)
  T.eq(ns.db.vendorLog[1].c, "Partner-Testrealm", "theirs stays")
  T.eq(ns.db.vendorLog[2].id, 100002, "your oldest went")
  T.eq(#ns.db.ledgerMonths, 1)
  T.eq(ns.db.ledgerMonths[1].c, ME)
end)

---------------------------------------------------------------------------
-- Auction house purchases: which gold is which (History.lua takeHints)
---------------------------------------------------------------------------
-- At the auction house with 1000g, every earlier hint long gone (GetTime over 99000).
local function atAH()
  S.now, S.money = math.max(S.now, 1800099000) + 100, 10000000
  T.fire("MERCHANT_CLOSED")
  S.now = S.now + 2
  ns.db.purchases = {}
  T.fire("PLAYER_ENTERING_WORLD")
end
-- A purchase sent the way the Buy queue sends it (it names the item).
local function bid(item, copper)
  ns.queueBidItem = item
  C_AuctionHouse.PlaceBid(1, copper)
  ns.queueBidItem = nil
end
local function pay(copper)
  S.now = S.now + 1
  S.money = S.money - copper
  T.fire("PLAYER_MONEY")
end

-- Owner's log, November 10: two Rough Bronze Leggings purchases at 5s were refused, then
-- a 9s purchase and a 22c deposit were put down as Rough Bronze Leggings.
T.test("A refused purchase doesn't name the next gold to leave", function()
  atAH()
  bid(2865, 500)   -- refused twice: no gold leaves
  bid(2865, 500)
  bid(4561, 900)
  pay(900)
  T.eq(#ns.db.purchases, 1)
  T.eq(ns.db.purchases[1].id, 4561, "the one that cost 9s")
  T.eq(ns.db.purchases[1].a, 900)
  C_Item = { GetItemID = function(loc) return loc.id end }
  C_AuctionHouse.PostItem({ id = 2589 }, 1, 1, 100)
  C_Item = nil
  pay(22)
  T.eq(#ns.db.purchases, 1, "a deposit isn't a purchase")
  T.eq(ns.db.money[ME][ns.LocalDay()].ahFee, 22)
end)

T.test("Two purchases at one price: the gold goes to the newer", function()
  atAH()
  bid(2865, 500)   -- refused
  bid(4561, 500)
  pay(500)
  T.eq(#ns.db.purchases, 1)
  T.eq(ns.db.purchases[1].id, 4561)
end)

-- Frank, November 15: 20 Runecloth bought for 72s 80c was put down as 1 Red Wolf Meat, the
-- oldest purchase still waiting. A stack purchase carries the total the game quoted.
local function stack(item, qty, total, failed)
  C_AuctionHouse.StartCommoditiesPurchase(item, qty)
  T.fire("COMMODITY_PRICE_UPDATED", math.floor(total / qty), total)
  C_AuctionHouse.ConfirmCommoditiesPurchase(item, qty)
  if failed then T.fire("COMMODITY_PURCHASE_FAILED") end
end

T.test("Stack purchases: each one's gold goes to the item it bought", function()
  atAH()
  stack(12208, 1, 178)       -- Red Wolf Meat, its gold not in yet
  stack(14047, 20, 7280)     -- Runecloth
  pay(7280)
  T.eq(#ns.db.purchases, 1)
  T.eq(ns.db.purchases[1].id, 14047, "Runecloth's gold is Runecloth's")
  T.eq(ns.db.purchases[1].q, 20)
  pay(178)
  T.eq(ns.db.purchases[2].id, 12208); T.eq(ns.db.purchases[2].q, 1)
end)

T.test("Stack purchases: a refused one takes no gold; two in one gold change are logged apart", function()
  atAH()
  stack(12208, 3, 534, true)   -- refused
  stack(14047, 21, 7644)
  pay(7644)
  T.eq(#ns.db.purchases, 1); T.eq(ns.db.purchases[1].id, 14047)
  stack(12208, 4, 664)
  stack(14047, 2, 728)
  pay(664 + 728)
  T.eq(#ns.db.purchases, 3)
  T.eq(ns.db.purchases[2].id, 12208); T.eq(ns.db.purchases[2].a, 664)
  T.eq(ns.db.purchases[3].id, 14047); T.eq(ns.db.purchases[3].a, 728)
end)

-- Codex review of 60da6ce, three cases from the Buy queue's real order of events.
T.test("Stack purchases: a refused second stack leaves the first one's hint", function()
  atAH()
  stack(12208, 1, 100)                       -- went through, its gold still to come
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  stack(14047, 20, 200, true)                -- refused
  pay(100)
  T.eq(#ns.db.purchases, 1)
  T.eq(ns.db.purchases[1].id, 12208, "the first stack's gold, not the refused Runecloth")
  T.eq(ns.db.purchases[1].q, 1); T.eq(ns.db.purchases[1].a, 100)
end)

T.test("Stack purchases: an older unanswered one doesn't hide two that add up", function()
  atAH()
  stack(90001, 1, 10)    -- no answer
  stack(90002, 1, 20)
  stack(90003, 1, 30)
  pay(50)
  T.eq(#ns.db.purchases, 2)
  T.eq(ns.db.purchases[1].id, 90002); T.eq(ns.db.purchases[1].a, 20)
  T.eq(ns.db.purchases[2].id, 90003); T.eq(ns.db.purchases[2].a, 30)
end)

T.test("Stack purchases: gold that comes late (16 s) still finds its stack", function()
  atAH()
  stack(14047, 20, 200)
  S.now = S.now + 16
  pay(200)
  T.eq(#ns.db.purchases, 1)
  T.eq(ns.db.purchases[1].id, 14047); T.eq(ns.db.purchases[1].q, 20)
end)

-- Frank, November 14: flights, loot, other income and the rest were only day totals, so
-- they sorted oddly among the Ledger's timed entries. Now each has its own time too.
T.test("Other money is logged with its time; the same kind within 5 minutes is one entry", function()
  ns.db.otherLog, ns.db.otherLogSince = {}, {}
  local log = ns.LogOtherMoney
  log("flight", 500, ME, NOW)
  T.same(ns.db.otherLog[1], { t = NOW, c = ME, s = "flight", a = 500 })
  T.eq(ns.db.otherLogSince[ME], NOW)
  log("flight", 200, ME, NOW + 120)
  T.eq(#ns.db.otherLog, 1, "two minutes later: the same entry")
  T.eq(ns.db.otherLog[1].a, 700); T.eq(ns.db.otherLog[1].t, NOW + 120)
  log("loot", 50, ME, NOW + 130)
  T.eq(#ns.db.otherLog, 2, "another kind: its own entry")
  log("loot", 10, ME, NOW + 130 + 301)
  T.eq(#ns.db.otherLog, 3, "over 5 minutes later: a new entry")
  log("ahSale", 999, ME, NOW + 500)
  log("vendorSell", 999, ME, NOW + 500)
  T.eq(#ns.db.otherLog, 3, "sales and vendor trades have their own logs")
  log("repair", 0, ME, NOW + 600)
  T.eq(#ns.db.otherLog, 3, "nothing for nothing")
  T.eq(ns.db.otherLogSince[ME], NOW, "since its first entry")
end)

-- Codex review of 211a277: what the Ledger shows for other money, not just the log.
local function ledgerOther()
  local total, rows = 0, ns.LedgerRecords("other", 0, function() return true end, "")
  for _, r in ipairs(rows) do total = total + r.total end
  return total, rows
end

T.test("Ledger: money a minute either side of midnight is counted once", function()
  local late = os.time({ year = 2026, month = 3, day = 15, hour = 23, min = 59 })
  local D = ns.LocalDay(late)
  ns.db.otherLog, ns.db.otherLogSince, ns.db.otherLogCut = {}, {}, {}
  ns.db.money = { [ME] = { [D] = { otherIn = 100 }, [D + 1] = { otherIn = 10 } } }
  S.now = late + 300
  ns.LogOtherMoney("otherIn", 100, ME, late)
  ns.LogOtherMoney("otherIn", 10, ME, late + 120)
  T.eq(#ns.db.otherLog, 2, "not merged across midnight")
  local total, rows = ledgerOther()
  T.eq(total, 110)
  T.eq(#rows, 2, "two timed entries, no 'earlier' line")
end)

T.test("Ledger: a day the size limit cut into shows its day totals, nothing lost", function()
  local noon = os.time({ year = 2026, month = 3, day = 15, hour = 12 })
  local D = ns.LocalDay(noon)
  local nextDay = os.time({ year = 2026, month = 3, day = 16, hour = 0, min = 10 })
  ns.db.otherLog, ns.db.otherLogSince, ns.db.otherLogCut = {}, {}, {}
  ns.db.money = { [ME] = { [D] = { otherIn = 5 }, [D + 1] = { loot = 5001, quest = 5000 } } }
  ns.LogOtherMoney("otherIn", 5, ME, noon)
  for i = 1, 10001 do ns.LogOtherMoney(i % 2 == 1 and "loot" or "quest", 1, ME, nextDay + i) end
  T.eq(#ns.db.otherLog, 10000, "the size limit")
  T.ok(ns.db.otherLogCut[ME] and ns.LocalDay(ns.db.otherLogCut[ME]) == D + 1, "the cut reached the next day")
  S.now = nextDay + 20000
  local total = ledgerOther()
  T.eq(total, 10006, "all of it, from the day totals")
end)

-- Frank, November 16 (TSM's item view): By item lists every item bought or sold.
T.test("Ledger by item: averages, profit on the resold ones, exact search, item filter", function()
  local real = { ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths }
  local ORE, BAR = 97001, 97002
  ns.db.itemNames[ORE], ns.db.itemNames[BAR] = "Test Ore", "Test Ore Bar"
  ns.db.purchases = { { t = NOW, c = ME, id = ORE, q = 10, a = 100 }, { t = NOW + 300, c = ME, id = ORE, q = 10, a = 140 },
    { t = NOW, c = ME, id = BAR, q = 2, a = 50 } }
  ns.db.sales = { { t = NOW + 3600, c = ME, n = "Test Ore", q = 5, a = 100 } }   -- (sales are saved by name)
  ns.db.vendorLog, ns.db.ledgerMonths = {}, {}
  local all = function() return true end
  local rows = ns.LedgerRecords("resale", 0, all, "")
  T.eq(#rows, 2, "the bar was never sold but is listed too")
  local by = {}
  for _, r in ipairs(rows) do by[r.item] = r end
  local ore, bar = by["Test Ore"], by["Test Ore Bar"]
  T.eq(ore.id, ORE, "the sale's ID found from its name")
  T.eq(ore.bought, 20); T.eq(ore.avgBuy, 12); T.eq(ore.sold, 5); T.eq(ore.avgSell, 20)
  T.eq(ore.avgProfit, 8); T.eq(ore.profit, 40, "8 each on the 5 resold")
  T.eq(ore.where.boughtAuction, 20); T.eq(ore.where.soldAuction, 5)
  T.eq(ore.first, NOW); T.eq(ore.last, NOW + 3600)
  T.eq(bar.bought, 2); T.eq(bar.sold, nil); T.eq(bar.profit, nil)
  T.eq(#ns.LedgerRecords("resale", 0, all, "test ore"), 2, "a plain search finds both")
  T.eq(#ns.LedgerRecords("resale", 0, all, '"test ore"'), 1, "in quotes, that item only")
  T.eq(#ns.LedgerRecords("all", 0, all, '"test ore"'), 3, "its three trades in All, not the bar's")
  local seen = {}
  rows = ns.LedgerRecords("resale", 0, all, "", { seen = seen, itemOK = function(id) return id == BAR end })
  T.eq(#rows, 1); T.eq(rows[1].item, "Test Ore Bar")
  T.ok(seen[ORE] and seen[BAR], "the choices see every item")
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = real[1], real[2], real[3], real[4]
  ns.db.itemNames[ORE], ns.db.itemNames[BAR] = nil, nil
end)

T.test("The local day: the same answer, and the clock's tables read once a second", function()
  local realDate, looks = date, 0
  date = function(...) looks = looks + 1; return realDate(...) end
  local t = os.time({ year = 2026, month = 3, day = 15, hour = 23, min = 59, sec = 59 })
  local first = ns.LocalDay(t)
  local before = looks
  for _ = 1, 50 do T.eq(ns.LocalDay(t), first) end
  T.eq(looks, before, "no new date tables for the same second")
  T.eq(ns.LocalDay(t + 1), first + 1, "the next second is the next day")
  T.eq(ns.LocalDay(t), first, "and back again")
  date = realDate
end)

T.test("The local day: entries at different times in one quarter hour read the clock's tables once", function()
  local realDate, looks = date, 0
  date = function(...) looks = looks + 1; return realDate(...) end
  local t0 = math.floor(os.time({ year = 2026, month = 3, day = 15, hour = 12 }) / 900) * 900 + 1000 * 900
  local want = ns.LocalDay(t0)
  local before = looks
  for i = 1, 100 do T.eq(ns.LocalDay(t0 + i * 8), want) end
  T.eq(looks, before, "the same quarter hour: no new date tables")
  date = realDate
end)

T.test("Ledger: an item's old name never takes a sale from the item that has that name now", function()
  -- (Codex review, November 21: item A renamed, then item B named what A was called.)
  local real = { ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths }
  local A, B = 97501, 97502
  local all = function() return true end
  local function saleId()
    local rows = ns.LedgerRecords("sales", 0, all, "")
    return rows[1] and rows[1].id
  end
  ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = {}, {}, {}
  ns.db.sales = { { t = NOW, c = ME, n = "Review Old Ore", q = 1, a = 10 } }
  ns.db.itemNames[A] = "Review Old Ore"
  T.eq(saleId(), A, "A's name")
  ns.db.itemNames[A] = "Review New Ore"
  T.eq(saleId(), A, "A's old name still finds it while nothing else has it")
  ns.db.itemNames[B] = "Review Old Ore"
  T.eq(saleId(), B, "B has that name now")
  ns.db.sales = { { t = NOW, c = ME, n = "Review New Ore", q = 1, a = 10 } }
  T.eq(saleId(), A, "A's new name")
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = real[1], real[2], real[3], real[4]
  ns.db.itemNames[A], ns.db.itemNames[B] = nil, nil
end)

-- Codex review, November 22: a second vendor purchase in the same second merges into the
-- first entry, so the log's length and last time stay the same, and the Ledger's kept list
-- went on showing the old total. Every write to the logs counts now (ns.ledgerRev).
T.test("Ledger: a vendor trade merged into the one before it shows its new total", function()
  local L = ns._ledgerTest
  local real = { ns.db.sales, ns.db.purchases, ns.db.ledgerMonths, ns.db.settings.ledger,
    ns.IsCharChoice, ns.CharChoiceHas, ns.CharacterOptions }
  local ok, err = pcall(function()
    ns.IsCharChoice = ns.IsCharChoice or function() return true end
    ns.CharChoiceHas = ns.CharChoiceHas or function() return true end
    ns.CharacterOptions = ns.CharacterOptions or function() return { { value = "all", label = "All" } } end
    ns.db.sales, ns.db.purchases, ns.db.ledgerMonths = {}, {}, {}
    ns.db.settings.ledger = { tab = "all", range = "all", char = "all", sort = {}, group = "all", rarity = "all" }
    atVendor(159)
    buy(1, 10)
    if not L.frame() then ns:BuildLedger(S.dummy()) end
    local F = L.frame()
    F.IsShown = function() return true end
    F.sf.GetVerticalScroll = function() return 0 end
    F.sf.GetHeight = function() return 200 end
    ns:RefreshLedger(); T.runTimers()
    local function total()
      for _, r in ipairs(F.cache and F.cache.list or {}) do if r.id == 159 then return r.total end end
    end
    T.eq(total(), 10)
    buy(1, 10)   -- (the same second: merged into the first)
    T.eq(#ns.db.vendorLog, 1); T.eq(ns.db.vendorLog[1].q, 2)
    ns:RefreshLedger(); T.runTimers()
    T.eq(total(), 20, "the merged total, not the kept list's")
  end)
  ns.db.sales, ns.db.purchases, ns.db.ledgerMonths, ns.db.settings.ledger = real[1], real[2], real[3], real[4]
  ns.IsCharChoice, ns.CharChoiceHas, ns.CharacterOptions = real[5], real[6], real[7]
  T.runTimers()
  assert(ok, err)
end)

-- Frank, November 22: sold to a vendor on one account, "over a minute and nothing" on the
-- other's open Ledger. Gold at a vendor with no bag click (Sell junk, another addon) still
-- goes to the partner within seconds, as a trade.
T.test("Gold at a vendor with no logged sale still counts as a trade for the partner", function()
  atVendor(159)
  local real, got = ns.BooksChanged, {}
  ns.BooksChanged = function(_, trade) got[#got + 1] = trade or false end
  S.money = S.money + 500
  local ok, err = pcall(T.fire, "PLAYER_MONEY")
  ns.BooksChanged = real
  assert(ok, err)
  T.eq(#ns.db.vendorLog, 0, "nothing to log")
  T.eq(got[#got], true, "sent as a trade")
end)

-- Frank, November 22: right-clicked vendor sales on his bank account were never logged (no
-- bag click the addon saw), only the gold. The item comes from the vendor's buyback list.
local BUYBACK = {}
GetNumBuybackItems = function() return #BUYBACK end
GetBuybackItemInfo = function(i) local b = BUYBACK[i]; return "x", 1, b.price, b.qty end
GetBuybackItemLink = function(i) return ("|cffffffff|Hitem:%d::::::::|h[x]|h|r"):format(BUYBACK[i].id) end

local function soldNoClick(id, qty, price, listFirst)
  if listFirst then BUYBACK[#BUYBACK + 1] = { id = id, qty = qty, price = price } end
  S.money = S.money + price
  T.fire("PLAYER_MONEY")
  if not listFirst then
    BUYBACK[#BUYBACK + 1] = { id = id, qty = qty, price = price }
    T.fire("MERCHANT_UPDATE")
  end
end

T.test("A vendor sale with no bag click is read from the buyback list", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  BUYBACK[1] = { id = 2589, qty = 5, price = 50 }   -- (sold on an earlier visit)
  atVendor(159)
  soldNoClick(2592, 3, 90, true)          -- the list first, then the gold
  soldNoClick(4306, 2, 400, false)        -- the gold first, then the list
  T.eq(#ns.db.vendorLog, 2)
  T.same(ns.db.vendorLog[1], { t = NOW, c = ME, id = 2592, q = 3, a = 90, s = "sell" })
  T.same(ns.db.vendorLog[2], { t = NOW, c = ME, id = 4306, q = 2, a = 400, s = "sell" })
end)

-- Frank, November 22: still nothing after the fix above. The game can change the list (and
-- say so) before the gold arrives; the entry was then noted as already seen.
T.test("A vendor sale whose buyback entry is announced before its gold is logged", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  atVendor(159)
  BUYBACK[1] = { id = 2592, qty = 3, price = 90 }
  T.fire("MERCHANT_UPDATE")
  S.money = S.money + 90
  T.fire("PLAYER_MONEY")
  T.runTimers()
  T.eq(#ns.db.vendorLog, 1)
  T.same(ns.db.vendorLog[1], { t = NOW, c = ME, id = 2592, q = 3, a = 90, s = "sell" })
end)

T.test("A sale logged from its bag click isn't logged again from the buyback list", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  atVendor(159)
  local realC = C_Container
  C_Container = { GetContainerItemInfo = function() return { itemID = 2592, stackCount = 3 } end }
  local ok, err = pcall(ns._historyTest.sellHint, 0, 1)
  C_Container = realC
  assert(ok, err)
  BUYBACK[1] = { id = 2592, qty = 3, price = 90 }
  T.fire("MERCHANT_UPDATE")
  S.money = S.money + 90
  T.fire("PLAYER_MONEY")
  T.eq(#ns.db.vendorLog, 1, "logged once, from the click")
  soldNoClick(4306, 2, 90, false)          -- the same gold, no click, its list after
  T.runTimers()
  T.eq(#ns.db.vendorLog, 2)
  T.eq(ns.db.vendorLog[2].id, 4306, "not the clicked sale again")
end)

-- Codex review, November 22: the list holds 12; a sale can push its twin off the far end,
-- so nothing looks new. Only the list's new order can show it; an unchanged list proves
-- nothing, and then only the gold counts.
local function sellOnList(id, price)
  S.money = S.money + price
  T.fire("PLAYER_MONEY")
  if #BUYBACK == 12 then table.remove(BUYBACK, 1) end
  BUYBACK[#BUYBACK + 1] = { id = id, qty = 1, price = price }
  T.fire("MERCHANT_UPDATE")
  S.now = S.now + 3
  T.runTimers()
end
local function fullList(fill)
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  atVendor(159)
  for n = 1, 12 do BUYBACK[n] = fill(n) end
  T.fire("MERCHANT_SHOW")
end

T.test("The 13th identical sale on a full buyback list counts as gold only", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  atVendor(159)
  for _ = 1, 13 do sellOnList(2589, 10) end
  S.now = NOW
  T.eq(#ns.db.vendorLog, 1, "one entry (the same item within a minute)")
  T.eq(ns.db.vendorLog[1].q, 12, "the 13th can't be told from nothing")
end)

T.test("A full list's new order shows a sale that pushed its twin off", function()
  fullList(function(n) return { id = n % 2 == 0 and 2589 or 2592, qty = 1, price = 10 } end)
  sellOnList(2589, 10)   -- (a 2592 leaves, a 2589 comes: new)
  sellOnList(2589, 10)   -- (a 2589 leaves, a 2589 comes: the same entries, moved along one)
  S.now = NOW
  T.eq(#ns.db.vendorLog, 1)
  T.eq(ns.db.vendorLog[1].id, 2589)
  T.eq(ns.db.vendorLog[1].q, 2)
end)

T.test("Two sales paid together that push their twins off are found by the new order", function()
  fullList(function(n) return n <= 2 and { id = 2589, qty = 1, price = 10 } or { id = 2592, qty = 1, price = 20 } end)
  S.money = S.money + 20
  T.fire("PLAYER_MONEY")
  table.remove(BUYBACK, 1); table.remove(BUYBACK, 1)
  BUYBACK[11] = { id = 2589, qty = 1, price = 10 }
  BUYBACK[12] = { id = 2589, qty = 1, price = 10 }
  T.fire("MERCHANT_UPDATE")
  S.now = S.now + 6
  T.runTimers()
  S.now = NOW
  T.eq(#ns.db.vendorLog, 1)
  T.same(ns.db.vendorLog[1], { t = NOW, c = ME, id = 2589, q = 2, a = 20, s = "sell" }, "two of the 10c item, not one 20c")
end)

T.test("A full list that didn't change doesn't name an old item for vendor gold", function()
  fullList(function() return { id = 2589, qty = 1, price = 10 } end)
  T.fire("MERCHANT_UPDATE")   -- (an update with nothing changed)
  S.money = S.money + 10
  T.fire("PLAYER_MONEY")
  S.now = S.now + 6
  T.runTimers()
  S.now = NOW
  T.eq(#ns.db.vendorLog, 0)
end)

T.test("A bag click's sale bought back doesn't take a later sale's entry", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  atVendor(159)
  local realC = C_Container
  C_Container = { GetContainerItemInfo = function() return { itemID = 2592, stackCount = 1 } end }
  local ok, err = pcall(ns._historyTest.sellHint, 0, 1)
  C_Container = realC
  assert(ok, err)
  S.money = S.money + 10
  T.fire("PLAYER_MONEY")      -- (logged from the click; its entry is never read)
  BUYBACK[1] = { id = 2592, qty = 1, price = 10 }
  BuybackItem(1)
  BUYBACK[1] = nil
  S.money = S.money - 10
  T.fire("PLAYER_MONEY")
  BUYBACK[1] = { id = 2592, qty = 1, price = 10 }   -- (sold again, no click)
  T.fire("MERCHANT_UPDATE")
  S.money = S.money + 10
  T.fire("PLAYER_MONEY")
  T.runTimers()
  local sold = 0
  for _, e in ipairs(ns.db.vendorLog) do if e.s == "sell" then sold = sold + e.q end end
  T.eq(sold, 2, "both sales")
end)

local function clicked(id, qty, price)
  local realC = C_Container
  C_Container = { GetContainerItemInfo = function() return { itemID = id, stackCount = qty } end }
  local ok, err = pcall(ns._historyTest.sellHint, 0, 1)
  C_Container = realC
  assert(ok, err)
  S.money = S.money + price
  T.fire("PLAYER_MONEY")
end
local function soldBy(id)
  local q = 0
  for _, e in ipairs(ns.db.vendorLog) do if e.s == "sell" and e.id == id then q = q + e.q end end
  return q
end

T.test("Buying back another item keeps a bag click's sale from taking a later sale's gold", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  BUYBACK[1] = { id = 4306, qty = 1, price = 50 }   -- (sold on an earlier visit)
  atVendor(159)
  clicked(2592, 3, 90)                 -- (logged from the click; its entry comes late)
  BuybackItem(1)                       -- (the old one bought back)
  table.remove(BUYBACK, 1)
  S.money = S.money - 50
  T.fire("PLAYER_MONEY")
  T.fire("MERCHANT_UPDATE")
  BUYBACK[#BUYBACK + 1] = { id = 2592, qty = 3, price = 90 }   -- (the clicked sale's entry)
  T.fire("MERCHANT_UPDATE")
  S.money = S.money + 90               -- (another sale, no click, its entry after the gold)
  T.fire("PLAYER_MONEY")
  BUYBACK[#BUYBACK + 1] = { id = 2589, qty = 2, price = 90 }
  T.fire("MERCHANT_UPDATE")
  T.runTimers()
  T.eq(soldBy(2592), 3, "the clicked sale once")
  T.eq(soldBy(2589), 2, "the other sale named")
end)

T.test("A bag click's sale that reorders a full list doesn't name a later sale", function()
  fullList(function(n) return n == 1 and { id = 2592, qty = 1, price = 10 } or { id = 2589, qty = 1, price = 20 } end)
  clicked(2592, 1, 10)
  table.remove(BUYBACK, 1)
  BUYBACK[12] = { id = 2592, qty = 1, price = 10 }   -- (pushed its twin off: a new order)
  T.fire("MERCHANT_UPDATE")
  S.money = S.money + 10               -- (another 10c sale, no click, its entry after)
  T.fire("PLAYER_MONEY")
  table.remove(BUYBACK, 1)
  BUYBACK[12] = { id = 2770, qty = 1, price = 10 }
  T.fire("MERCHANT_UPDATE")
  S.now = S.now + 6
  T.runTimers()
  S.now = NOW
  T.eq(soldBy(2592), 1, "the clicked sale once")
  T.eq(soldBy(2770), 1, "the other sale named")
end)

-- Codex review, November 22: a bag click's sale of one copy (20c) mustn't explain another
-- copy's sale for other gold (10c) that reorders a full list before its own entry comes.
T.test("A bag click's sale doesn't explain another copy sold for other gold", function()
  fullList(function(n) return n == 1 and { id = 2592, qty = 1, price = 10 } or { id = 2589, qty = 1, price = 30 } end)
  ns.db.vendorSell[2592] = 20
  clicked(2592, 1, 20)                 -- (logged from the click; its entry comes late)
  sellOnList(2592, 10)                 -- (another copy, no click: pushes its twin off)
  table.remove(BUYBACK, 1)
  BUYBACK[12] = { id = 2592, qty = 1, price = 20 }   -- (the clicked sale's entry)
  T.fire("MERCHANT_UPDATE")
  S.now = S.now + 6
  T.runTimers()
  S.now = NOW
  T.eq(soldBy(2592), 2, "both copies")
  local gold = 0
  for _, e in ipairs(ns.db.vendorLog) do if e.s == "sell" then gold = gold + e.a end end
  T.eq(gold, 30)
end)

-- Codex review, November 22: a buyback in the same gold change as a bag click's sale (net
-- +5c for a 10c sale): the sale's own 10c entry is still its, not another sale's.
T.test("A bag click's sale paid with a buyback's gold taken off still finds its entry", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  BUYBACK[1] = { id = 4306, qty = 1, price = 5 }   -- (sold on an earlier visit)
  atVendor(159)
  ns.db.vendorSell[2770] = 10
  local realC = C_Container
  C_Container = { GetContainerItemInfo = function() return { itemID = 2770, stackCount = 1 } end }
  local ok, err = pcall(ns._historyTest.sellHint, 0, 1)
  C_Container = realC
  assert(ok, err)
  BuybackItemNow = function(i) table.remove(BUYBACK, i) end
  BuybackItem(1)                       -- (the old one bought back, before the sale's gold)
  BuybackItemNow = nil
  S.money = S.money + 5                -- (10c in, 5c out, in one change)
  T.fire("PLAYER_MONEY")
  BUYBACK[#BUYBACK + 1] = { id = 2770, qty = 1, price = 10 }   -- (the clicked sale's entry)
  T.fire("MERCHANT_UPDATE")
  S.money = S.money + 10               -- (another sale, no click, its entry after the gold)
  T.fire("PLAYER_MONEY")
  BUYBACK[#BUYBACK + 1] = { id = 2589, qty = 1, price = 10 }
  T.fire("MERCHANT_UPDATE")
  T.runTimers()
  T.eq(soldBy(2770), 1, "the clicked sale once")
  T.eq(soldBy(2589), 1, "the other sale named")
end)

-- Codex review, November 22: the game may take a bought-back entry off (and move the rest
-- up) before the hook runs; the item is the one that was clicked, as last read.
T.test("Buying back reads the clicked item even if the list moved up during the call", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  BUYBACK[1] = { id = 4306, qty = 1, price = 50 }   -- (sold on an earlier visit)
  atVendor(159)
  clicked(2592, 3, 90)                 -- (logged from the click)
  BUYBACK[2] = { id = 2592, qty = 3, price = 90 }   -- (its entry, not read yet)
  BuybackItemNow = function(i) table.remove(BUYBACK, i) end
  BuybackItem(1)                       -- (the old one bought back; the clicked one moves up)
  BuybackItemNow = nil
  S.money = S.money - 50
  T.fire("PLAYER_MONEY")
  T.fire("MERCHANT_UPDATE")
  S.money = S.money + 90               -- (another sale, no click, its entry after the gold)
  T.fire("PLAYER_MONEY")
  BUYBACK[#BUYBACK + 1] = { id = 2589, qty = 2, price = 90 }
  T.fire("MERCHANT_UPDATE")
  T.runTimers()
  T.eq(soldBy(2592), 3, "the clicked sale once")
  T.eq(soldBy(2589), 2, "the other sale named")
end)

T.test("An item that left the buyback list is new when sold again", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  atVendor(159)
  soldNoClick(2592, 3, 90, false)
  BUYBACK[1] = nil   -- (bought back)
  T.fire("MERCHANT_UPDATE")
  soldNoClick(2592, 3, 90, false)
  T.runTimers()
  T.eq(#ns.db.vendorLog, 1)
  T.eq(ns.db.vendorLog[1].q, 6, "both sales, merged")
end)

T.test("A buyback entry older than a few seconds doesn't take later vendor gold", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  atVendor(159)
  BUYBACK[1] = { id = 2592, qty = 3, price = 90 }
  T.fire("MERCHANT_UPDATE")                 -- (its gold went elsewhere)
  S.now = S.now + 10
  S.money = S.money + 90
  T.fire("PLAYER_MONEY")
  T.runTimers()
  T.eq(#ns.db.vendorLog, 0)
  S.now = NOW
end)

T.test("Vendor gold with nothing new on the buyback list logs nothing", function()
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
  atVendor(159)
  S.money = S.money + 77
  T.fire("PLAYER_MONEY")
  T.runTimers()
  T.eq(#ns.db.vendorLog, 0)
  for i = #BUYBACK, 1, -1 do BUYBACK[i] = nil end
end)
