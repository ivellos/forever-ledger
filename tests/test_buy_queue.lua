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
  Q.buyFrom, Q.wonDue = nil, {}
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

-- A second purchase sent now, as the Buy button does, while earlier ones are unanswered.
local function sending(id, plan)
  local e = { id = id, lane = "flips", reason = "flip", want = 10, limit = 99 }
  S.items[id] = { name = "Item " .. id, sell = 1 }
  Q.cur, Q.plan, Q.state = e, plan, "buying"
  Q.buyAt, Q.lastMoney, Q.buyFrom, Q.lastPlan = GetTime(), GetMoney(), GetMoney(), plan
  return e
end

-- A first purchase of `cost` that got no answer, with Spend at most at 100c.
local function unansweredFirst(id, cost, item)
  if item then buyingItem(id, 1) else buying(id) end
  budget(100)
  Q.plan.cost = cost
  Q.noReply()
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

-- Codex, November 9: with no wait, five unanswered tries for a Want of 1 brought five.
T.test("Buy queue: a shopping list counts purchases still waiting for an answer", function()
  local real = ns.ListStillWanted
  ns.ListStillWanted = function() return 1 end
  local e = buyingItem(91040, 7)
  e.reason = "list"
  T.eq(Q.listLeft(91040), 1, "nothing on its way yet")
  Q.noReply()
  T.eq(Q.listLeft(91040), 0, "the unanswered one counts")
  Q.cur, Q.plan, Q.state = e, nil, "search"
  Q.planItem({ itemID = 91040 })
  T.eq(Q.cur, nil, "no second one")
  T.ok(Q.note and Q.note:find("counting 1 still waiting for an answer", 1, true), tostring(Q.note))
  S.now = S.now + 61
  T.eq(Q.listLeft(91040), 1, "taken as lost after a minute, so the list can buy again")
  ns.ListStillWanted = real
  Q.lateBuys = {}
end)

-- Codex review, November 9: a right-click on a list row didn't count as using the list.
T.test("Buy queue: using Shopping lists keeps a new flip from switching the view for 30 seconds", function()
  local buyQueue = ns.db.settings.buyQueue
  local realView = buyQueue.view
  buyQueue.view, Q.listTouched = "flips", nil
  Q.noteListUse()
  T.eq(Q.listInUse(), false, "only on Shopping lists")
  buyQueue.view = "lists"
  local e = { id = 91041, lane = "lists", limit = 9 }
  S.items[e.id] = { name = "Item E", sell = 1 }
  Q.cur, Q.state = nil, "idle"
  Q.skip(e)
  T.eq(Q.listInUse(), true, "a right-click on a row counts")
  S.now = S.now + 29
  T.eq(Q.listInUse(), true)
  S.now = S.now + 1
  T.eq(Q.listInUse(), false, "30 seconds later it doesn't")
  Q.noteListUse()
  T.eq(Q.listInUse(), true, "and any later use starts it again")
  buyQueue.view, Q.listTouched = realView, nil
end)

-- The next five: Codex's review of November 9, with no wait between purchases.
T.test("Buy queue: an older purchase's gold doesn't make the one under way look paid", function()
  withAHOpen(function()
    unansweredFirst(91050, 40, true)
    T.eq(Q.lateBuys[1].left, 40)
    sending(91051, { kind = "item", auctionID = 2, price = 50, cost = 50 })
    S.money = 960
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 40)
    T.eq(Q.lateBuys[1].left, 0, "the older one's")
    Q.noReply()
    T.eq(Q.lateBuys[2].left, 50, "the newer one still owes all of it")
    T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 1)
    T.eq(#Q.lateBuys, 1, "the older one is settled")
    T.eq(Q.visitLeft(), 10, "100 less 40 spent and 50 still held")
  end)
end)

T.test("Buy queue: gold that matches nothing frees nothing while several are open", function()
  withAHOpen(function()
    unansweredFirst(91052, 40, true)
    sending(91053, { kind = "item", auctionID = 2, price = 50, cost = 50 })
    S.money = 993   -- a deposit, say
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 7)
    T.eq(Q.lateBuys[1].left, 40)
    Q.noReply()
    T.eq(Q.lateBuys[2].left, 50, "not taken as a part payment")
    T.eq(Q.visitLeft(), 3)
  end)
end)

T.test("Buy queue: a list counts a purchase still open even when gold of its price left", function()
  withAHOpen(function()
    local real = ns.ListStillWanted
    ns.ListStillWanted = function() return 1 end
    unansweredFirst(91054, 40, true)
    sending(91055, { kind = "item", auctionID = 2, price = 40, cost = 40 })
    S.money = 960
    T.fire("PLAYER_MONEY")      -- goes to the older one, which may be wrong
    Q.noReply()
    T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 1)
    T.eq(Q.listLeft(91055), 0, "the second is still on its way")
    ns.ListStillWanted = real
  end)
end)

T.test("Buy queue: a late commodity failure leaves an item purchase on its way alone", function()
  withAHOpen(function()
    unansweredFirst(91056, 40)
    local b = sending(91057, { kind = "item", auctionID = 2, price = 50, cost = 50 })
    T.fire("COMMODITY_PURCHASE_FAILED")
    T.eq(Q.state, "buying")
    T.eq(Q.cur, b)
    T.eq(Q.plan.auctionID, 2)
    T.eq(#Q.lateBuys, 0, "the commodity one has its answer")
  end)
end)

T.test("Buy queue: an answer that could be either commodity purchase's frees neither", function()
  withAHOpen(function()
    unansweredFirst(91058, 40)
    sending(91059, { kind = "commodity", qty = 5, cost = 50 })
    T.fire("COMMODITY_PURCHASE_FAILED")
    T.eq(#Q.lateBuys, 2, "a failure lets neither go")
    T.eq(Q.visitLeft(), 10)
    unansweredFirst(91060, 40)
    local b = sending(91061, { kind = "commodity", qty = 5, cost = 50 })
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    T.eq(b.want, 5, "a success is counted for the one under way")
    T.eq(Q.visitLeft(), 10, "with its cost held until the gold leaves")
    S.money = 950
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 50)
    T.eq(#Q.wonDue, 0)
    T.eq(Q.lateBuys[1].left, 40, "the other is still held")
    T.eq(Q.visitLeft(), 10)
  end)
end)

T.test("Buy queue: a success with gold still to come stays held until it leaves", function()
  withAHOpen(function()
    unansweredFirst(91062, 40, true)
    T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 1)
    T.eq(#Q.lateBuys, 0)
    T.eq(Q.visitLeft(), 60, "not freed by the news alone")
    S.money = 960
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 40)
    T.eq(Q.visitLeft(), 60, "once")
  end)
end)

T.test("Buy queue: a not-found error with an earlier purchase open lets nothing go", function()
  local real = ERR_ITEM_NOT_FOUND
  ERR_ITEM_NOT_FOUND = "The item was not found."
  unansweredFirst(91063, 40, true)
  sending(91064, { kind = "item", auctionID = 2, price = 50, cost = 50 })
  T.fire("UI_ERROR_MESSAGE", 1, ERR_ITEM_NOT_FOUND)
  T.eq(#Q.lateBuys, 2)
  ERR_ITEM_NOT_FOUND = real
  ns.db.settings.buyQueue.limit = nil
end)

T.test("Buy queue: the chat line for another item's win isn't this purchase's", function()
  local real = rawget(_G, "ERR_AUCTION_WON_S")
  rawset(_G, "ERR_AUCTION_WON_S", "You won an auction for %s")
  buyingItem(91065, 3)
  T.fire("CHAT_MSG_SYSTEM", "You won an auction for Something Else")
  T.eq(Q.state, "buying")
  T.eq(Q.bought, 0)
  T.fire("CHAT_MSG_SYSTEM", "You won an auction for Item 91065")
  T.eq(Q.bought, 1)
  rawset(_G, "ERR_AUCTION_WON_S", real)
end)

-- Gold audit, November 9: "of the Eagle" was bought for a list that wanted "of the Monkey".
T.test("Buy queue: a list's one version buys only that version", function()
  local function rows(list)
    rawset(C_AuctionHouse, "GetNumItemSearchResults", function() return #list end)
    rawset(C_AuctionHouse, "GetItemSearchResultInfo", function(_, i) return list[i] end)
  end
  local eagle = { auctionID = 5, buyoutAmount = 400, quantity = 1, itemLink = "|cff1eff00|Hitem:91070:::|h[Armor of the Eagle]|h|r" }
  local monkey = { auctionID = 6, buyoutAmount = 500, quantity = 1, itemLink = "|cff1eff00|Hitem:91070:::|h[Armor of the Monkey]|h|r" }
  local e = buyingItem(91070, 1)
  e.limit, e.suffix, Q.state, Q.plan = 600, "of the Monkey", "search", nil
  ns.db.settings.buyQueue.limit = nil
  S.money = 100000
  rows({ eagle, monkey })
  Q.planItem({ itemID = 91070 })
  T.eq(Q.plan.auctionID, 6, "the Monkey, though the Eagle is cheaper")
  Q.state, Q.plan = "search", nil
  rows({ eagle, { auctionID = 7, buyoutAmount = 400, quantity = 1 } })
  Q.planItem({ itemID = 91070 })
  T.eq(Q.plan, nil, "not the Eagle, nor a row with no name to read")
  T.eq(Q.cur, nil)
  e = buyingItem(91071, 1)
  e.limit, Q.state, Q.plan = 600, "search", nil
  rows({ eagle })
  Q.planItem({ itemID = 91071 })
  T.eq(Q.plan.auctionID, 5, "no version asked for: any will do")
  rawset(C_AuctionHouse, "GetNumItemSearchResults", nil)
  rawset(C_AuctionHouse, "GetItemSearchResultInfo", nil)
end)

-- Gold audit, November 9: a sold-out item kept its last price for good.
T.test("Full scan: what it didn't see is marked none listed, if the scan looks whole", function()
  wipe(S.timers)
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  local market = ns.db.prices[key]
  local function old(id, src) market[id] = { m = 100, a = 100, q = 12, t = S.now - 5000, src = src } end
  old(91100, "full"); old(91101, "full"); old(91102, "Auctionator")
  market[91103] = { m = 100, a = 100, q = 12, t = S.now + 190, src = "scan" }   -- newer than the scan
  S.now = S.now + 200
  rawset(C_AuctionHouse, "GetNumReplicateItems", function() return 1 end)
  rawset(C_AuctionHouse, "GetReplicateItemInfo", function()
    return nil, nil, 1, nil, nil, nil, nil, nil, nil, 500, nil, nil, nil, nil, nil, nil, 91101
  end)
  ns.db.lastFullListings = { [key] = 2 }
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  T.eq(market[91100].none, true, "not seen, so gone")
  T.eq(market[91101].m, 500, "seen")
  T.eq(market[91102].m, 100, "another addon's price is left alone")
  T.eq(market[91103].m, 100, "a price newer than the scan is left alone")
  T.eq(ns.db.lastFullListings[key].n, 1)
  ns.db.lastFullListings[key] = { n = 100, t = S.now }
  old(91104, "full")
  S.now = S.now + 200
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  T.eq(market[91104].m, 100, "a scan far smaller than the last one proves nothing")
  ns.db.lastFullListings = nil
  old(91105, "full")
  S.now = S.now + 200
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  T.eq(market[91105].m, 100, "nor the first one, with nothing to compare it to")
  rawset(C_AuctionHouse, "GetNumReplicateItems", nil)
  rawset(C_AuctionHouse, "GetReplicateItemInfo", nil)
  ns.db.lastFullListings = nil
  wipe(S.timers)
end)

T.test("Buy queue: what can't be taken back takes two clicks on the same thing", function()
  local text
  local b = { SetText = function(_, t) text = t end }
  T.eq(Q.clickTwice(b, "a", "x", "?"), false, "the first only asks")
  T.eq(text, "?")
  T.eq(Q.clickTwice(b, "b", "x", "?"), false, "another row's entry starts over")
  T.eq(Q.clickTwice(b, "b", "x", "?"), true, "the second goes ahead")
  T.eq(text, "x")
  T.eq(Q.clickTwice(b, "b", "x", "?"), false)
  S.now = S.now + 5
  T.eq(Q.clickTwice(b, "b", "x", "?"), false, "too late: it asks again")
  wipe(S.timers)
end)

-- The next four: Codex's verification of b8844dd, November 9.
T.test("Buy queue: a success only guessed to be one purchase's frees nothing on a failure", function()
  withAHOpen(function()
    unansweredFirst(91090, 40)
    sending(91091, { kind = "commodity", qty = 5, cost = 50 })
    Q.noReply()
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")   -- put down to the 40, but could be the 50's
    T.eq(#Q.wonDue, 1)
    T.eq(Q.wonDue[1].guess, true)
    T.fire("COMMODITY_PURCHASE_FAILED")
    T.eq(#Q.lateBuys, 1, "no telling which failed")
    T.eq(#Q.wonDue, 1)
    T.eq(Q.visitLeft(), 10, "both still held")
    S.money = 950
    T.fire("PLAYER_MONEY")
    T.eq(Q.lateBuys[1].left, 0, "the 50 paid, so it's the one that went through")
    T.fire("COMMODITY_PURCHASE_FAILED")
    T.eq(#Q.wonDue, 0, "so the failure was the 40's")
    T.eq(Q.visitLeft(), 50)
  end)
end)

T.test("Buy queue: a list's version can be a number from the price window", function()
  rawset(C_AuctionHouse, "GetNumItemSearchResults", function() return 2 end)
  rawset(C_AuctionHouse, "GetItemSearchResultInfo", function(_, i)
    return ({ { auctionID = 5, buyoutAmount = 400, quantity = 1, itemLink = "|Hitem:91092::::::12718:|h[Armor of the Eagle]|h" },
      { auctionID = 6, buyoutAmount = 500, quantity = 1, itemLink = "|Hitem:91092::::::12719:|h[Armor of the Whale]|h" } })[i]
  end)
  local e = buyingItem(91092, 1)
  e.limit, e.suffix, Q.state, Q.plan = 600, 12719, "search", nil
  ns.db.settings.buyQueue.limit = nil
  S.money = 100000
  Q.planItem({ itemID = 91092 })
  T.eq(Q.plan.auctionID, 6, "by its number")
  rawset(C_AuctionHouse, "GetNumItemSearchResults", nil)
  rawset(C_AuctionHouse, "GetItemSearchResultInfo", nil)
  T.eq(ns:VersionLabel(99999), "(other stats)")
  T.eq(ns:VersionLabel("of the Whale"), "of the Whale")
end)

T.test("Full scan: small scans in a row can't vouch for each other", function()
  wipe(S.timers)
  local key = ns.MarketKey()
  local market = ns.db.prices[key]
  market[91110] = { m = 100, a = 100, q = 12, t = S.now - 5000, src = "full" }
  ns.db.lastFullListings = { [key] = { n = 100, t = S.now } }
  rawset(C_AuctionHouse, "GetNumReplicateItems", function() return 1 end)
  rawset(C_AuctionHouse, "GetReplicateItemInfo", function()
    return nil, nil, 1, nil, nil, nil, nil, nil, nil, 500, nil, nil, nil, nil, nil, nil, 91111
  end)
  for _ = 1, 2 do
    S.now = S.now + 200
    T.fire("REPLICATE_ITEM_LIST_UPDATE")
  end
  T.eq(market[91110].m, 100, "still listed, as far as anyone can tell")
  T.eq(ns.db.lastFullListings[key].n, 100, "the size to compare with stays")
  S.now = S.now + 86401
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  T.eq(ns.db.lastFullListings[key].n, 1, "a day on, the market really has shrunk")
  T.eq(market[91110].m, 100, "and that scan marks nothing")
  rawset(C_AuctionHouse, "GetNumReplicateItems", nil)
  rawset(C_AuctionHouse, "GetReplicateItemInfo", nil)
  ns.db.lastFullListings = nil
  wipe(S.timers)
end)

T.test("Full scan: a listing with no buyout counts as listed, and unread rows prove nothing", function()
  wipe(S.timers)
  local key = ns.MarketKey()
  local market = ns.db.prices[key]
  market[91112] = { m = 100, a = 100, q = 12, t = S.now - 5000, src = "full" }
  market[91113] = { m = 100, a = 100, q = 12, t = S.now - 5000, src = "full" }
  ns.db.lastFullListings = { [key] = { n = 1, t = S.now } }
  rawset(C_AuctionHouse, "GetNumReplicateItems", function() return 1 end)
  rawset(C_AuctionHouse, "GetReplicateItemInfo", function()
    return nil, nil, 1, nil, nil, nil, nil, nil, nil, 0, nil, nil, nil, nil, nil, nil, 91112
  end)
  S.now = S.now + 200
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  T.ok(not market[91112].none, "bids only is still listed")
  T.eq(market[91113].none, true, "the one it didn't see")
  market[91114] = { m = 100, a = 100, q = 12, t = S.now - 5000, src = "full" }
  rawset(C_AuctionHouse, "GetReplicateItemInfo", function() end)
  S.now = S.now + 200
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  T.eq(market[91114].m, 100, "a row it couldn't read could have been this")
  -- Codex's verification of e0aece8: even one unreadable row among many.
  ns.db.lastFullListings = { [key] = { n = 200, t = S.now } }
  rawset(C_AuctionHouse, "GetNumReplicateItems", function() return 200 end)
  rawset(C_AuctionHouse, "GetReplicateItemInfo", function(idx)
    if idx == 5 then return end
    return nil, nil, 1, nil, nil, nil, nil, nil, nil, 500, nil, nil, nil, nil, nil, nil, 91112
  end)
  S.now = S.now + 200
  T.fire("REPLICATE_ITEM_LIST_UPDATE")
  T.eq(market[91114].m, 100, "one in two hundred is still one that could be it")
  rawset(C_AuctionHouse, "GetNumReplicateItems", nil)
  rawset(C_AuctionHouse, "GetReplicateItemInfo", nil)
  ns.db.lastFullListings = nil
  wipe(S.timers)
end)

-- The next three: Codex's verification of b942892, November 9.
T.test("Buy queue: an ordinary success keeps its cost held until the gold leaves", function()
  withAHOpen(function()
    buyingItem(91080, 1)
    budget(100)
    Q.plan.cost = 40
    T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 1)
    T.eq(Q.visitLeft(), 60, "an item: not freed by the news alone")
    S.money = 960
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 40)
    T.eq(#Q.wonDue, 0)
    T.eq(Q.visitLeft(), 60, "counted once")
    buying(91081)
    budget(100)
    Q.plan.cost = 40
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    T.eq(Q.visitLeft(), 60, "a commodity, with no other open")
    buying(91082)
    budget(100)
    Q.plan.cost = 40
    S.money = 960
    T.fire("PLAYER_MONEY")
    T.fire("COMMODITY_PURCHASE_SUCCEEDED")
    T.eq(#Q.wonDue, 0, "gold that already left isn't held again")
    T.eq(Q.visitLeft(), 60)
  end)
end)

T.test("Buy queue: a failure with two unanswered commodity purchases lets neither go", function()
  withAHOpen(function()
    unansweredFirst(91083, 50)
    sending(91084, { kind = "commodity", qty = 5, cost = 40 })
    Q.noReply()
    T.eq(#Q.lateBuys, 2)
    T.fire("COMMODITY_PURCHASE_FAILED")
    T.eq(#Q.lateBuys, 2, "no telling whose")
    T.eq(Q.visitLeft(), 10)
    S.money = 950
    T.fire("PLAYER_MONEY")
    T.eq(Q.lateBuys[1].left, 0, "the 50 has paid, so it can't fail now")
    T.fire("COMMODITY_PURCHASE_FAILED")
    T.eq(#Q.lateBuys, 1, "so this failure is the other one's")
    T.eq(Q.lateBuys[1].plan.cost, 50)
    T.eq(Q.visitLeft(), 50)
  end)
end)

T.test("Buy queue: a list full only of unanswered purchases comes back when they expire", function()
  local real = ns.ListStillWanted
  ns.ListStillWanted = function() return 1 end
  local e = buyingItem(91085, 7)
  e.reason = "list"
  Q.noReply()
  Q.cur, Q.plan, Q.state = e, nil, "search"
  Q.planItem({ itemID = 91085 })
  T.eq(Q.isSetAside(91085), true)
  S.now = S.now + 60
  T.eq(Q.isSetAside(91085), true, "still counted")
  S.now = S.now + 2
  T.eq(Q.isSetAside(91085), false, "back after a minute, not two")
  T.eq(Q.listLeft(91085), 1)
  ns.ListStillWanted = real
  Q.lateBuys = {}
  wipe(S.timers)
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

-- Owner, November 9: a Nomad Trousers listing at 2s and a Rough Bronze Leggings one at 5s
-- were refused with "There is already a higher bid on that item" at every try, and came
-- back every two minutes from a 13-minute-old price.
local function searchRows(list)
  rawset(C_AuctionHouse, "GetNumItemSearchResults", function() return #list end)
  rawset(C_AuctionHouse, "GetItemSearchResultInfo", function(_, i) return list[i] end)
end
local function noSearchRows()
  rawset(C_AuctionHouse, "GetNumItemSearchResults", nil)
  rawset(C_AuctionHouse, "GetItemSearchResultInfo", nil)
end

T.test("Buy queue: a listing the auction house won't sell at its price is passed over", function()
  local e = buyingItem(91120, 11)
  e.limit = 600
  ns.db.settings.buyQueue.limit = nil
  S.money = 100000
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 1)   -- HigherBid
  T.eq(ns:AuctionRefused(11), true)
  T.eq(Q.state, "wait", "looked at again")
  searchRows({ { auctionID = 11, buyoutAmount = 500, quantity = 1 }, { auctionID = 12, buyoutAmount = 550, quantity = 1 } })
  Q.state, Q.plan = "search", nil
  Q.planItem({ itemID = 91120 })
  noSearchRows()
  T.eq(Q.plan.auctionID, 12, "the next listing instead")
  Q.state = "buying"
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.eq(ns:AuctionRefused(12), false, "another error doesn't mark it")
  buyingItem(91121, 13)
  Q.lateBuys = { { plan = { kind = "item", auctionID = 99, price = 5 }, cur = {}, at = GetTime(), left = 5 } }
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 1)
  T.eq(ns:AuctionRefused(13), false, "nor one that could be an earlier purchase's")
  buyingItem(91123, 15)
  Q.lateBuys = { { plan = { kind = "item", auctionID = 99, price = 5 }, cur = {}, at = GetTime() - 61, left = 5 },
    { plan = { kind = "item", auctionID = 15, price = 9 }, cur = {}, at = GetTime(), left = 9 } }
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 1)
  T.eq(ns:AuctionRefused(15), true, "an old unanswered one and its own earlier try don't stop it")
  Q.lateBuys = {}
  wipe(S.timers)
end)

T.test("Buy queue: a listing the auction house won't sell isn't saved as a price", function()
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  Q.cur = nil
  searchRows({ { auctionID = 11, buyoutAmount = 500, quantity = 1 }, { auctionID = 14, buyoutAmount = 700, quantity = 1 } })
  T.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 91120, itemSuffix = 0 })
  noSearchRows()
  T.eq(ns.db.prices[key][91120].m, 700, "auction 11 was refused above")
  wipe(S.timers)
end)

T.test("Buy queue: a flip found gone stays out until a newer price", function()
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  local market = ns.db.prices[key]
  market[91122] = { m = 200, a = 200, q = 1, t = time() - 400, src = "full" }
  local buyQueue, realFlip = ns.db.settings.buyQueue, ns.VendorFlip
  local realView = buyQueue.view
  buyQueue.view = "flips"
  ns.VendorFlip = function(_, id)
    if id ~= 91122 then return end
    return { maxBuy = 264, opt = { value = 294 }, buys = { { listed = 1 } }, cost = 200, t = market[id].t }
  end
  local function listed()
    for _, x in ipairs(Q.buildQueue().flips) do if x.id == 91122 then return true end end
    return false
  end
  T.eq(listed(), true)
  local e = buyingItem(91122, 21)
  e.limit, Q.state, Q.plan, Q.keys = 264, "search", nil, nil
  searchRows({ { auctionID = 21, buyoutAmount = 300, quantity = 1 } })
  Q.planItem({ itemID = 91122 })
  noSearchRows()
  T.eq(Q.cur, nil, "none left")
  S.now = S.now + 200
  T.eq(listed(), false, "the same old price doesn't bring it back")
  market[91122].t = time()
  T.eq(listed(), true, "a newer one does")
  ns.VendorFlip, buyQueue.view, market[91122] = realFlip, realView, nil
  wipe(S.timers)
end)

Q.cur, Q.plan, Q.state, Q.lateBuys = nil, nil, "idle", {}
