-- The price ladder and buying costs: Crates.lua ns:CostToBuy, Prices.lua
-- ns:CheapListings and ns:RemoveBought. A ladder is "price:count,..." with running
-- totals: "100:5,120:10" is 5 at 100c and 5 more at 120c.
local T = ...
local ns = T.ns
local ID = 2589

-- Each test starts with just this price and no vendor price.
local function price(rec)
  ns.db.prices[ns.MarketKey()] = { [ID] = rec }
  ns.db.vendorBuy[ID] = nil
end

T.test("CostToBuy walks up the ladder", function()
  price({ m = 100, a = 150, q = 12, t = 1, l = "100:5,120:10,200:12" })
  T.eq(ns:CostToBuy(ID, 3), 300)
  T.eq(ns:CostToBuy(ID, 5), 500)
  T.eq(ns:CostToBuy(ID, 7), 500 + 2 * 120)
  T.eq(ns:CostToBuy(ID, 12), 500 + 600 + 400)
  T.eq(ns:CostToBuy(ID, 15), 1500 + 3 * 150, "past the ladder: the rest at the average")
end)

T.test("CostToBuy without a ladder", function()
  price({ m = 100, a = 150, q = 12, t = 1 })
  T.eq(ns:CostToBuy(ID, 4), 600, "the average price")
  price({ m = 100, q = 12, t = 1 })
  T.eq(ns:CostToBuy(ID, 4), 400, "or the cheapest")
end)

T.test("CostToBuy: a vendor when it's cheaper", function()
  price({ m = 100, a = 150, q = 12, t = 1, l = "100:5,120:10,200:12" })
  ns.db.vendorBuy[ID] = { p = 110 }
  T.eq(ns:CostToBuy(ID, 3), 300, "auction house cheaper")
  T.eq(ns:CostToBuy(ID, 10), 1100, "vendor cheaper than 500 + 600")
  ns.db.vendorBuy[ID] = { p = 90 }
  T.eq(ns:CostToBuy(ID, 3), 270)
end)

T.test("CostToBuy: nothing listed", function()
  price({ none = true, t = 1 })
  T.eq(ns:CostToBuy(ID, 3), nil)
  ns.db.vendorBuy[ID] = { p = 40 }
  T.eq(ns:CostToBuy(ID, 3), 120, "vendor only")
  ns.db.prices[ns.MarketKey()] = nil
  T.eq(ns:CostToBuy(ID, 2), 80, "never scanned, vendor only")
end)

T.test("CheapListings: how many at or under a price, and their average", function()
  price({ m = 100, a = 150, q = 12, t = 1, l = "100:5,120:10,200:12" })
  local n, avg = ns:CheapListings(ID, 120)
  T.eq(n, 10)
  T.eq(avg, 110)
  n, avg = ns:CheapListings(ID, 99)
  T.eq(n, 0)
  T.eq(avg, nil)
  T.eq((ns:CheapListings(ID, 1000)), 12)
  price({ m = 100, q = 4, t = 1 })
  n, avg = ns:CheapListings(ID, 100)
  T.eq(n, 4, "no ladder: the cheapest qualifies")
  T.eq(avg, 100)
  T.eq((ns:CheapListings(ID, 50)), 0)
  ns.db.prices[ns.MarketKey()] = nil
  T.eq(ns:CheapListings(ID, 50), nil, "never scanned")
end)

T.test("RemoveBought takes from the dearest level at or under the price paid", function()
  price({ m = 100, a = 110, q = 10, t = 1, l = "100:5,120:10" })
  ns:RemoveBought(ID, 3, 120)
  local rec = ns.db.prices[ns.MarketKey()][ID]
  T.eq(rec.l, "100:5,120:7")
  T.eq(rec.q, 7)
  T.eq(rec.m, 100)
end)

T.test("RemoveBought: buying out the cheapest level moves the cheapest up", function()
  price({ m = 100, a = 110, q = 10, t = 1, l = "100:5,120:10" })
  ns:RemoveBought(ID, 5, 100)
  local rec = ns.db.prices[ns.MarketKey()][ID]
  T.eq(rec.l, "120:5")
  T.eq(rec.m, 120)
  T.eq(rec.q, 5)
end)

T.test("RemoveBought: buying them all", function()
  price({ m = 100, a = 100, q = 5, t = 1, l = "100:5" })
  ns:RemoveBought(ID, 5, 100)
  local rec = ns.db.prices[ns.MarketKey()][ID]
  T.eq(rec.l, "")
  T.eq(rec.q, 0)
  T.eq(rec.none, true)
end)

-- Which items the flip watch re-checks (owner, October 7): busy items beat a rarely
-- posted one that's just as close to its vendor price.
T.test("Flip watch: busy and crafted items come before quiet ones", function()
  local S = ns.FlipWatchScore
  T.ok(S(0.9, 50) > S(0.9, 0.2), "same closeness: the busy one first")
  T.ok(S(1.2, 50) > S(0.9, 0.2), "a busy item a bit further off still beats a quiet close one")
  T.ok(S(0.5, 0.2) > S(1.4, 50), "but not when it's nearly at 150% of the vendor price")
  T.ok(S(1.0, 5, nil, true) > S(1.0, 5), "crafted items count extra")
  T.ok(S(1.0, nil, 100) > S(1.0, nil, 2), "no sell speed yet: how many are listed")
  T.eq(S(1.5, 50), 0, "150% of the vendor price: no chance")
end)

T.test("RemoveBought: nothing at that price changes nothing", function()
  price({ m = 100, a = 100, q = 5, t = 1, l = "100:5" })
  ns:RemoveBought(ID, 2, 50)
  T.eq(ns.db.prices[ns.MarketKey()][ID].l, "100:5")
end)
