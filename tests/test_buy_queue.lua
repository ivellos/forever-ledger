-- BuyQueue.lua: a purchase with no clear answer stays open until it's settled (Codex
-- reviews, November 5 and 6).
local T = ...
local ns = T.ns
local S = T.S
local Q = ns.buyQueueState
local HEARING_BACK = "Waiting to hear whether the last purchase went through."

local function buying(id, qty)
  S.items[id] = { name = "Item " .. id, sell = 1 }
  local e = { id = id, lane = "flips", want = 10, limit = 9 }
  Q.lanes.flips = { e }
  Q.cur, Q.plan, Q.state, Q.bought, Q.lateBuys = e, { kind = "commodity", qty = qty or 3, cost = 27 }, "buying", 0, {}
  Q.buyFrom = nil
  return e
end

local function buyingItem(id, auctionID)
  local e = buying(id)
  Q.plan = { kind = "item", auctionID = auctionID, price = 9 }
  return e
end

-- A purchase of `cost` under way, with Spend at most set to the same.
local function budget(cost)
  ns.db.settings.buyQueue.limit = cost
  Q.spent, Q.lastMoney, Q.buyAt, Q.buyFrom, S.money = 0, 1000, GetTime(), 1000, 1000
  Q.plan.cost, Q.lastPlan = cost, Q.plan
end

local function withAHOpen(fn)
  local real = ns.IsAHOpen
  ns.IsAHOpen = function() return true end
  fn()
  ns.IsAHOpen = real
  ns.db.settings.buyQueue.limit = nil
end

T.test("Buy queue: a purchase that goes through after an error is counted", function()
  local e = buying(91001)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.eq(Q.state, "wait")
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(Q.bought, 3)
  T.eq(e.want, 7)
  T.eq(#Q.lateBuys, 0)
end)

T.test("Buy queue: a real failure isn't counted", function()
  buying(91003)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.fire("COMMODITY_PURCHASE_FAILED")
  T.eq(#Q.lateBuys, 0)
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(Q.bought, 0, "failed")
end)

T.test("Buy queue: a success after the item was set aside still counts", function()
  local e = buying(91004)
  e.refused = 1
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.eq(Q.cur, nil, "set aside")
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(Q.bought, 3)
  T.eq(e.want, 7)
end)

T.test("Buy queue: a late purchase's gold counts once, before or after its success", function()
  withAHOpen(function()
    buying(91005)
    budget(100)
    S.now = S.now + 12
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    S.now = S.now + 4
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    S.money = 900
    T.fire("PLAYER_MONEY")
    T.eq(Q.bought, 3)
    T.eq(Q.spent, 100, "gold that left after the success")
    T.eq(Q.visitLeft(), 0)
    buying(91006)
    budget(100)
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    S.now = S.now + 4
    S.money = 900
    T.fire("PLAYER_MONEY")
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    T.eq(Q.spent, 100, "gold that left before the success")
    T.eq(Q.visitLeft(), 0)
  end)
end)

T.test("Buy queue: an unsettled purchase stays held against Spend at most, however late", function()
  withAHOpen(function()
    local e = buying(91013)
    budget(100)
    S.now = S.now + 12
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    T.eq(Q.visitLeft(), 0, "held while unsettled")
    S.now = S.now + 500
    T.eq(Q.visitLeft(), 0, "still held after the wait is over")
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    S.money = 900
    T.fire("PLAYER_MONEY")
    T.eq(Q.bought, 3, "counted, however late")
    T.eq(e.want, 7)
    T.eq(Q.spent, 100, "and so is its gold")
    T.eq(Q.visitLeft(), 0)
  end)
end)

T.test("Buy queue: gold leaving settles a purchase with no reply", function()
  withAHOpen(function()
    buying(91014)
    budget(100)
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    S.now = S.now + 30
    S.money = 900
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 100)
    T.eq(Q.visitLeft(), 0, "counted once, not held as well")
    Q.state, Q.plan = "confirm", { kind = "commodity", qty = 1, cost = 9, total = 9 }
    ns:BuyQueueAct()
    T.ok(Q.note ~= HEARING_BACK, "no more waiting")
    buying(91015)
    budget(100)
    S.money = 900
    T.fire("PLAYER_MONEY")
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    T.eq(Q.lateBuys[1].left, 0, "gold had already left when the error came")
    T.eq(Q.spent, 100)
    T.eq(Q.visitLeft(), 0, "counted once")
    buying(91026)
    budget(100)
    S.money = 900
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    T.eq(Q.lateBuys[1].left, 100, "gold gone, but not reported yet")
    T.fire("PLAYER_MONEY")
    T.eq(Q.lateBuys[1].left, 0)
    T.eq(Q.spent, 100)
    T.eq(Q.visitLeft(), 0, "still once")
  end)
end)

T.test("Buy queue: a small gold loss frees only that much of what's held", function()
  withAHOpen(function()
    buying(91027)
    budget(100)
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    S.money = 999            -- a deposit, say
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 1)
    T.eq(Q.lateBuys[1].left, 99)
    T.eq(Q.visitLeft(), 0, "the rest stays held")
    buying(91028)
    budget(100)
    S.money = 999
    T.fire("PLAYER_MONEY")   -- before the error this time
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    T.eq(Q.lateBuys[1].left, 99)
    T.eq(Q.visitLeft(), 0)
  end)
end)

T.test("Buy queue: a newer purchase's gold frees nothing held for an older one", function()
  withAHOpen(function()
    buying(91029)
    budget(100)
    Q.plan.cost = 40
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    S.now = S.now + 61
    local b = { id = 91030, lane = "flips", want = 10, limit = 9 }
    S.items[b.id] = { name = "Item B", sell = 1 }
    Q.cur, Q.plan, Q.state = b, { kind = "commodity", qty = 5, cost = 50 }, "buying"
    Q.buyAt, Q.lastPlan = GetTime(), Q.plan
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    S.money = 950
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 50)
    T.eq(Q.lateBuys[1].left, 40)
    T.eq(Q.visitLeft(), 10)
  end)
end)

T.test("Buy queue: a purchase on its way stays open if you click elsewhere", function()
  local a = buying(91031)
  Q.dropCurrent()
  T.eq(#Q.lateBuys, 1, "a row or section click")
  T.eq(Q.lateBuys[1].cur, a)
  local b = buying(91032)
  T.fire("AUCTION_HOUSE_CLOSED")
  T.eq(#Q.lateBuys, 1, "closing the auction house")
  T.eq(Q.lateBuys[1].cur, b)
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(b.want, 7)
  buying(91033)
  Q.state = "ready"
  Q.dropCurrent()
  T.eq(#Q.lateBuys, 0, "nothing sent, nothing to keep")
end)

T.test("Buy queue: skipping an item with a purchase on its way keeps that purchase", function()
  local a = buying(91034)
  Q.skip(a)
  T.eq(Q.cur, nil, "skipped")
  T.eq(#Q.lateBuys, 1)
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(Q.bought, 3)
  T.eq(a.want, 7)
  local b = buying(91035)
  Q.state = "ready"
  Q.skip(b)
  T.eq(#Q.lateBuys, 0, "nothing sent, nothing to keep")
end)

T.test("Buy queue: scans wait while a purchase is ready for your click", function()
  buying(91040)
  ns.queueBusyUntil = 0
  Q.setState("search")
  T.eq(ns.queueBusyUntil, 0, "looking something up doesn't hold them here")
  Q.setState("ready")
  T.ok(ns.queueBusyUntil > GetTime(), "ready holds them")
  ns.queueBusyUntil = 0
  Q.setState("confirm")
  T.ok(ns.queueBusyUntil > GetTime(), "so does the final price")
  -- A click held back (the queue isn't on screen here, as it isn't when anything stops it)
  -- still makes room, or the scan takes the next gap and the one after.
  ns.queueBusyUntil = 0
  ns:BuyQueueAct()
  T.ok(ns.queueBusyUntil > GetTime(), "a click that's held back holds them too")
  ns.queueBusyUntil = 0
  Q.state = "idle"
  ns:BuyQueueAct()
  T.eq(ns.queueBusyUntil, 0, "nothing ready: scans carry on")
end)

T.test("Full scan: no reply isn't asked for again at every flip watch pass", function()
  wipe(S.timers)
  ns.db.lastFullScan, ns.Scan.heldUntil = nil, nil
  T.eq(ns.Scan:FullWait(), 0)
  ns.Scan:StartFull(false)
  T.ok(ns.Scan.active and ns.Scan.full, "asked")
  T.runTimers()
  T.ok(not ns.Scan.active and not ns.Scan.full, "gave up waiting")
  T.eq(ns.Scan:FullWait(), 300, "five minutes before the next try")
  S.now = S.now + 300
  T.eq(ns.Scan:FullWait(), 0, "then it can ask again")
  ns.Scan.heldUntil = nil
end)

T.test("Full scan: one that arrives minutes late is still read and counted", function()
  wipe(S.timers)
  ns.db.lastFullScan, ns.Scan.heldUntil, ns.db.fullScanLog = nil, nil, nil
  ns.db.settings.debug = true
  ns.Scan:StartFull(false)
  T.runTimers()
  S.now = S.now + 211
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  wipe(S.timers)
  local log = ns.db.fullScanLog
  T.eq(log[#log].what, "done: 0 listings, 211 seconds after asking")
  T.ok(ns.db.lastFullScan, "counts as a finished scan")
  ns.db.settings.debug, ns.Scan.heldUntil = false, nil
end)

-- Codex review, November 7: the time is taken when it arrives, not after reading it.
T.test("Full scan: a big one arriving just inside the late window counts as late, however long it takes to read", function()
  wipe(S.timers)
  ns.db.lastFullScan, ns.Scan.heldUntil, ns.db.fullScanLog = nil, nil, nil
  ns.db.settings.debug = true
  ns.Scan:StartFull(false)
  T.runTimers()
  S.now = S.now + 595
  rawset(C_AuctionHouse, "GetNumReplicateItems", function() return 2500 end)
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  S.now = S.now + 10   -- the second part is read after the 10 minutes are up
  T.runTimers()
  rawset(C_AuctionHouse, "GetNumReplicateItems", nil)
  local log = ns.db.fullScanLog
  T.eq(log[#log].what, "done: 2500 listings, 595 seconds after asking")
  ns.db.settings.debug, ns.Scan.heldUntil = false, nil
end)

T.test("Buy queue: no answer at all is treated like an unclear error", function()
  local a = buying(91016)
  Q.noReply()
  T.eq(#Q.lateBuys, 1, "kept")
  local b = { id = 91017, lane = "flips", want = 10, limit = 9 }
  S.items[b.id] = { name = "Item B", sell = 1 }
  Q.cur, Q.plan, Q.state = b, { kind = "commodity", qty = 5, cost = 45, total = 45 }, "confirm"
  ns:BuyQueueAct()
  T.ok(Q.note ~= HEARING_BACK, "the next purchase isn't held")
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(a.want, 7, "the success goes to the first")
  T.eq(b.want, 10)
end)

-- Owner, November 9: as in the beta. The minute's wait (November 6) held every tick after a
-- Red Woolen Bag purchase that got no answer, and the rest of the row sold meanwhile.
T.test("Buy queue: buying goes on while an earlier purchase is unsettled", function()
  for _, reason in ipairs({ "flip", "list" }) do
    local a = buying(91007)
    a.reason = reason
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    local b = { id = 91008, lane = "flips", reason = reason, want = 10, limit = 9 }
    S.items[b.id] = { name = "Item B", sell = 1 }
    Q.cur, Q.plan, Q.state = b, { kind = "commodity", qty = 5, cost = 45, total = 45 }, "confirm"
    ns.db.settings.debug, ns.db.buyTrace = true, nil
    ns:BuyQueueAct()
    local log = ns.db.buyTrace or {}
    T.ok(log[#log] and log[#log]:find("click ignored", 1, true), "not held (" .. reason .. ")")
    ns.db.settings.debug, ns.db.buyTrace = false, nil
    T.ok(Q.note ~= HEARING_BACK)
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    T.eq(a.want, 7, "a success before the next is sent goes to the first purchase")
    T.eq(b.want, 10)
  end
end)

T.test("Buy queue: after the wait, a purchase under way takes its own success", function()
  local a = buying(91018)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  S.now = S.now + 61
  local b = { id = 91019, lane = "flips", want = 10, limit = 9 }
  S.items[b.id] = { name = "Item B", sell = 1 }
  Q.cur, Q.plan, Q.state = b, { kind = "commodity", qty = 5, cost = 45 }, "buying"
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(b.want, 5)
  T.eq(a.want, 10)
  T.eq(#Q.lateBuys, 1, "the first stays open")
end)

T.test("Buy queue: a success goes to one whose gold has left before one under way", function()
  withAHOpen(function()
    local a = buying(91020)
    budget(100)
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    S.money = 900
    T.fire("PLAYER_MONEY")
    local b = { id = 91021, lane = "flips", want = 10, limit = 9 }
    S.items[b.id] = { name = "Item B", sell = 1 }
    Q.cur, Q.plan, Q.state = b, { kind = "commodity", qty = 5, cost = 45 }, "buying"
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    T.eq(a.want, 7)
    T.eq(b.want, 10)
    T.eq(Q.state, "buying", "the second still has its own answer to come")
  end)
end)

T.test("Buy queue: an unrelated purchase leaves an open one alone", function()
  buying(91022)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 555)
  T.eq(#Q.lateBuys, 1, "another kind")
  local a = buyingItem(91023, 777)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 555)
  T.eq(#Q.lateBuys, 1, "another auction")
  T.eq(a.want, 10)
  T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 777)
  T.eq(#Q.lateBuys, 0, "its own")
  T.eq(Q.bought, 1)
  local b = buyingItem(91024, 888)
  T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 555)
  T.eq(Q.state, "buying", "the one under way keeps waiting")
  T.eq(b.want, 10)
end)

-- Owner, November 9: 2 Red Woolen Bags in one row at 5s were left "for the page", so the
-- flip left the queue while still listed; the game's Buy button took 5s a click.
T.test("Buy queue: a row of several is bought one at a time, and looked at again after", function()
  local e = buyingItem(91026, 1)
  e.limit, Q.state, Q.plan = 600, "search", nil
  ns.db.settings.buyQueue.limit = nil
  S.money = 100000
  rawset(C_AuctionHouse, "GetNumItemSearchResults", function() return 1 end)
  rawset(C_AuctionHouse, "GetItemSearchResultInfo", function()
    return { auctionID = 5, buyoutAmount = 500, quantity = 2 }
  end)
  Q.planItem({ itemID = 91026 })
  rawset(C_AuctionHouse, "GetNumItemSearchResults", nil)
  rawset(C_AuctionHouse, "GetItemSearchResultInfo", nil)
  T.eq(Q.state, "ready", "not left for the page")
  T.eq(Q.plan.price, 500, "the price for one")
  T.eq(Q.plan.stack, 2)
  T.eq(Q.plan.count, 2, "both counted")
  Q.state = "buying"
  T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 5)
  T.eq(Q.bought, 1)
  T.eq(e.boughtIDs and e.boughtIDs[5], nil, "the rest of the row isn't set aside")
end)

T.test("Buy queue: closing the auction house keeps a recent unsettled purchase", function()
  buying(91025)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.fire("AUCTION_HOUSE_SHOW")
  T.eq(#Q.lateBuys, 1, "still recent")
  S.now = S.now + 61
  T.fire("AUCTION_HOUSE_SHOW")
  T.eq(#Q.lateBuys, 0, "an old one ends with the visit")
end)

T.test("Buy queue: a listing that's gone leaves nothing to wait for", function()
  local real = ERR_ITEM_NOT_FOUND
  ERR_ITEM_NOT_FOUND = "The item was not found."
  buying(91010)
  T.fire("UI_ERROR_MESSAGE", 1, ERR_ITEM_NOT_FOUND)
  T.eq(#Q.lateBuys, 0)
  T.eq(Q.state, "wait")
  ERR_ITEM_NOT_FOUND = real
end)

T.test("Buy queue: its logs are only kept with debug on", function()
  ns.db.buyTrace, ns.db.buyErrors = nil, nil
  buying(91011)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.eq(ns.db.buyTrace, nil)
  T.eq(ns.db.buyErrors, nil)
  ns.db.settings.debug = true
  buying(91012)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.eq(#ns.db.buyErrors, 1)
  T.ok(#ns.db.buyTrace > 0, "steps logged")
  ns.db.settings.debug = false
  ns.db.buyTrace, ns.db.buyErrors = nil, nil
end)

Q.cur, Q.plan, Q.state, Q.lateBuys = nil, nil, "idle", {}
