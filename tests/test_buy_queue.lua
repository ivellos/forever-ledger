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

Q.cur, Q.plan, Q.state, Q.lateBuy = nil, nil, "idle", nil
