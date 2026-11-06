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
  Q.plan.cost = cost
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
    T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
    T.eq(Q.lateBuys[1].paid, true, "gold had already left when the error came")
    T.eq(Q.visitLeft(), 100, "so nothing more is held")
    T.fire("PLAYER_MONEY")
    T.eq(Q.spent, 100)
    T.eq(Q.visitLeft(), 0)
  end)
end)

T.test("Buy queue: no answer at all is treated like an unclear error", function()
  local a = buying(91016)
  Q.noReply()
  T.eq(#Q.lateBuys, 1, "kept")
  local b = { id = 91017, lane = "flips", want = 10, limit = 9 }
  S.items[b.id] = { name = "Item B", sell = 1 }
  Q.cur, Q.plan, Q.state = b, { kind = "commodity", qty = 5, cost = 45, total = 45 }, "confirm"
  ns:BuyQueueAct()
  T.eq(Q.note, HEARING_BACK, "the next purchase waits")
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(a.want, 7, "the success goes to the first")
  T.eq(b.want, 10)
end)

T.test("Buy queue: nothing else is bought until a late purchase is settled", function()
  local a = buying(91007)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  local b = { id = 91008, lane = "flips", want = 10, limit = 9 }
  S.items[b.id] = { name = "Item B", sell = 1 }
  Q.cur, Q.plan, Q.state = b, { kind = "commodity", qty = 5, cost = 45, total = 45 }, "confirm"
  ns:BuyQueueAct()
  T.eq(Q.state, "confirm", "still waiting")
  T.eq(Q.note, HEARING_BACK)
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(a.want, 7, "the success went to the first purchase")
  T.eq(b.want, 10)
  ns:BuyQueueAct()
  T.ok(Q.note ~= HEARING_BACK, "and buying can go on")
  buying(91009)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  S.now = S.now + 61
  Q.state, Q.plan = "confirm", { kind = "commodity", qty = 1, cost = 9, total = 9 }
  ns:BuyQueueAct()
  T.ok(Q.note ~= HEARING_BACK, "not for ever")
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

T.test("Buy queue: closing the auction house doesn't skip the wait", function()
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
