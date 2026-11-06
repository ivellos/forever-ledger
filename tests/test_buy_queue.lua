-- BuyQueue.lua: a purchase that succeeds after an auction house error still counts
-- (Codex review, November 5).
local T = ...
local ns = T.ns
local S = T.S
local Q = ns.buyQueueState

local function buying(id)
  S.items[id] = { name = "Item " .. id, sell = 1 }
  local e = { id = id, lane = "flips", want = 10, limit = 9 }
  Q.lanes.flips = { e }
  Q.cur, Q.plan, Q.state, Q.bought, Q.lateBuy = e, { kind = "commodity", qty = 3, cost = 27 }, "buying", 0, nil
  return e
end

T.test("Buy queue: a purchase that goes through after an error is counted", function()
  local e = buying(91001)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.eq(Q.state, "wait")
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(Q.bought, 3)
  T.eq(e.want, 7)
  T.eq(Q.lateBuy, nil)
end)

T.test("Buy queue: too late, or a real failure, isn't counted", function()
  buying(91002)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  S.now = S.now + 20
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(Q.bought, 0, "too late")
  buying(91003)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  T.fire("COMMODITY_PURCHASE_FAILED")
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

T.test("Buy queue: a late purchase's gold counts against Spend at most", function()
  local realOpen = ns.IsAHOpen
  ns.IsAHOpen = function() return true end
  buying(91005)
  Q.spent, Q.lastMoney, Q.buyAt, S.money = 0, 1000, GetTime(), 1000
  S.now = S.now + 12
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  S.now = S.now + 4          -- 16 seconds after the purchase, 4 after the error
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  S.money = 900
  T.fire("PLAYER_MONEY")
  T.eq(Q.bought, 3)
  T.eq(Q.spent, 100, "gold that left after the success")
  buying(91006)
  Q.spent, Q.lastMoney, Q.buyAt, S.money = 0, 1000, GetTime(), 1000
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  S.now = S.now + 4
  S.money = 900
  T.fire("PLAYER_MONEY")
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(Q.spent, 100, "gold that left before the success, counted once")
  ns.IsAHOpen = realOpen
end)

T.test("Buy queue: nothing else is bought until a late purchase is settled", function()
  local a = buying(91007)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  local b = { id = 91008, lane = "flips", want = 10, limit = 9 }
  S.items[b.id] = { name = "Item B", sell = 1 }
  Q.cur, Q.plan, Q.state = b, { kind = "commodity", qty = 5, cost = 45, total = 45 }, "confirm"
  ns:BuyQueueAct()
  T.eq(Q.state, "confirm", "still waiting")
  T.eq(Q.note, "Waiting to hear whether the last purchase went through.")
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(a.want, 7, "the success went to the first purchase")
  T.eq(b.want, 10)
  ns:BuyQueueAct()
  T.ok(Q.note ~= "Waiting to hear whether the last purchase went through.", "and buying can go on")
  S.now = S.now + 20
  buying(91009)
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 10)
  S.now = S.now + 20
  Q.state, Q.plan = "confirm", { kind = "commodity", qty = 1, cost = 9, total = 9 }
  ns:BuyQueueAct()
  T.ok(Q.note ~= "Waiting to hear whether the last purchase went through.", "not for ever")
end)

T.test("Buy queue: a listing that's gone leaves nothing to wait for", function()
  local real = ERR_ITEM_NOT_FOUND
  ERR_ITEM_NOT_FOUND = "The item was not found."
  buying(91010)
  T.fire("UI_ERROR_MESSAGE", 1, ERR_ITEM_NOT_FOUND)
  T.eq(Q.lateBuy, nil)
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

Q.cur, Q.plan, Q.state, Q.lateBuy = nil, nil, "idle", nil
