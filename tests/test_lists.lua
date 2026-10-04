-- Shopping lists and the buying maths (ShoppingLists.lua): what you own, the most to pay
-- for an item, your usual price, and how many more a list still wants (the Buy queue's
-- guard against buying too many).
local T = ...
local ns, S = T.ns, T.S
local ME = ns.CharKey()

-- A list you buy from, with one item. Fresh lists each time.
local function buyList(item, extra)
  ns.db.shopping.lists = {}
  local list = ns:NewShoppingList("Raid")
  list.on = true
  for k, v in pairs(extra or {}) do list[k] = v end
  list.items[1] = item
  return list
end

local function price(id, rec)
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  rec.t = rec.t or S.now
  ns.db.prices[key][id] = rec
end

-- Three days of history (before today) with this typical price, so the month's usual
-- price is known (it needs 3 points).
local function history(id, typical)
  local d = ns.LocalDay()
  local key = ns.MarketKey()
  ns.db.history[key] = ns.db.history[key] or {}
  ns.db.history[key][id] = ("%d:%d:%d|%d:%d:%d|%d:%d:%d"):format(d - 3, typical, typical, d - 2, typical, typical,
    d - 1, typical, typical)
end

---------------------------------------------------------------------------
-- What you own
---------------------------------------------------------------------------
T.test("OwnedCount: bags, bank, mail on the way and alts on this realm and faction", function()
  local ID = 50001
  ns.db.chars[ME] = { name = "Tester", realm = "Testrealm", faction = "Alliance" }
  ns.db.chars["Alt-Testrealm"] = { name = "Alt", realm = "Testrealm", faction = "Alliance" }
  ns.db.chars["Hordie-Testrealm"] = { name = "Hordie", realm = "Testrealm", faction = "Horde" }
  ns.db.chars["Far-Otherrealm"] = { name = "Far", realm = "Otherrealm", faction = "Alliance" }
  S.bags[ID], S.bank[ID] = 3, 4
  ns.db.inventory[ME] = { bags = { [ID] = 3 }, bank = { [ID] = 4 } }
  ns.db.inventory["Alt-Testrealm"] = { bags = { [ID] = 5 }, bank = { [ID] = 1 } }
  ns.db.inventory["Hordie-Testrealm"] = { bags = { [ID] = 10 }, bank = {} }
  ns.db.inventory["Far-Otherrealm"] = { bags = { [ID] = 20 }, bank = {} }
  ns.db.onTheWay = { [ME] = { [ID] = { n = 2, base = 7, t = S.now } } }
  local total, alts = ns:OwnedCount(ID)
  T.eq(alts, 6, "only the alt on this realm and faction")
  T.eq(total, 3 + 4 + 2 + 6)
end)

T.test("Mail on the way goes down as it reaches your bags", function()
  local ID = 50002
  S.bags[ID] = 1
  ns.db.onTheWay = { [ME] = { [ID] = { n = 5, base = 1, t = S.now } } }
  T.eq(ns:InTheMail(ID), 5)
  S.bags[ID] = 3
  T.eq(ns:InTheMail(ID), 3, "2 taken from the mail")
  S.bags[ID] = 10
  T.eq(ns:InTheMail(ID), 0, "all taken")
end)

T.test("Mail on the way is forgotten after 31 days", function()
  local ID = 50003
  ns.db.onTheWay = { [ME] = { [ID] = { n = 5, base = 0, t = S.now - 32 * 86400 } } }
  T.eq(ns:InTheMail(ID), 0)
end)

---------------------------------------------------------------------------
-- The most to pay
---------------------------------------------------------------------------
T.test("ItemLimit: what's in Up to, or nothing when it's off", function()
  local list = buyList({ id = 50010, max = 0 })
  T.eq(ns:ItemLimit(list, list.items[1]), nil, "off")
  list.items[1].max = 1500
  T.eq(ns:ItemLimit(list, list.items[1]), 1500)
end)

T.test("ItemLimit: any price is 3 times the usual price", function()
  local list = buyList({ id = 50011, max = -1 })
  price(50011, { m = 150, a = 200, q = 30 })
  local limit, how = ns:ItemLimit(list, list.items[1])
  T.eq(limit, 600)
  T.eq(how, "any")
  list.items[1].max = 500
  list.anyPrice = true
  T.eq((ns:ItemLimit(list, list.items[1])), 600, "the whole list at any price")
end)

T.test("AnyPriceLimit: no price means no limit (nil, not a huge number)", function()
  T.eq(ns:AnyPriceLimit(50020), nil, "never scanned")
  price(50020, { none = true })
  T.eq(ns:AnyPriceLimit(50020), nil, "none listed")
end)

T.test("AnyPriceLimit: 3 times the base price", function()
  price(50021, { m = 100, q = 30 })
  T.eq(ns:AnyPriceLimit(50021), 300, "from the cheapest when there's no average")
  price(50022, { m = 100, a = 120, q = 30 })
  T.eq(ns:AnyPriceLimit(50022), 360, "from the average of the cheapest")
end)

T.test("AnyPriceLimit: the usual price wins over today's", function()
  price(50023, { m = 900, a = 1000, q = 30 })
  history(50023, 200)
  T.eq(ns:AnyPriceLimit(50023), 600)
end)

T.test("AnyPriceLimit is never raised to a lone dear listing", function()
  price(50024, { m = 99999, a = 99999, q = 1 })
  history(50024, 100)
  T.eq(ns:AnyPriceLimit(50024), 300)
end)

---------------------------------------------------------------------------
-- Usual prices filled into Up to
---------------------------------------------------------------------------
T.test("UsualPriceFor rounds up to the silver", function()
  price(50030, { m = 1200, a = 1234, q = 30 })
  T.eq(ns:UsualPriceFor(50030), 1300)
  price(50031, { m = 50, a = 55, q = 30 })
  T.eq(ns:UsualPriceFor(50031), 55, "under a silver: to the copper")
  history(50032, 250)
  T.eq(ns:UsualPriceFor(50032), 300, "from history")
  T.eq(ns:UsualPriceFor(50033), nil, "no price")
end)

T.test("FillUsualPrices fills only items at off, never a price set by hand", function()
  price(50040, { m = 500, a = 500, q = 30 })
  price(50041, { m = 500, a = 500, q = 30 })
  price(50042, { m = 500, a = 500, q = 30 })
  price(50043, { m = 500, a = 500, q = 30 })
  local list = buyList({ id = 50040, max = 0 })
  list.items[2] = { id = 50041, max = 0, offSet = true }   -- set to off by hand
  list.items[3] = { id = 50042, max = 777 }                 -- a price typed in
  list.items[4] = { id = 50043, max = 0, mode = "craft" }  -- crafted, not bought
  list.items[5] = { id = 50044, max = 0 }                   -- no price known
  T.eq(ns:FillUsualPrices(list), 1)
  T.eq(list.items[1].max, 500)
  T.eq(list.items[2].max, 0, "off by hand stays off")
  T.eq(list.items[3].max, 777, "a typed price stays")
  T.eq(list.items[4].max, 0, "craft items aren't priced")
  T.eq(list.items[5].max, 0)
  ns:FillUsualPrices(list)
  T.eq(list.items[2].max, 0, "and again: still off")
end)

---------------------------------------------------------------------------
-- How many more a list wants (the overbuy guard)
---------------------------------------------------------------------------
T.test("ListStillWanted counts down as you buy, then says no more", function()
  buyList({ id = 50050, max = 1000, qty = 5 })
  T.eq(ns:ListStillWanted(50050), 5)
  ns:NoteListPurchase(50050, 3)
  T.eq(ns:ListStillWanted(50050), 2)
  ns:NoteListPurchase(50050, 10)
  T.eq(ns:ListStillWanted(50050), 0, "bought more than wanted: none more")
  T.eq(ns.db.shopping.lists[1].items[1].bought, 5, "only what was wanted counts for the list")
end)

T.test("ListStillWanted: without a Want number, one", function()
  buyList({ id = 50051, max = 1000 })
  T.eq(ns:ListStillWanted(50051), 1)
  ns:NoteListPurchase(50051, 1)
  T.eq(ns:ListStillWanted(50051), 0)
end)

T.test("ListStillWanted: counts above 1000", function()
  buyList({ id = 50052, max = 10, qty = 5000 })
  T.eq(ns:ListStillWanted(50052), 5000)
  ns:NoteListPurchase(50052, 1200)
  T.eq(ns:ListStillWanted(50052), 3800)
  ns:NoteListPurchase(50052, 3800)
  T.eq(ns:ListStillWanted(50052), 0)
  ns:NoteListPurchase(50052, 1500)
  T.eq(ns:ListStillWanted(50052), 0, "buying more never makes it want more")
end)

T.test("ListStillWanted: any price items stop too", function()
  price(50053, { m = 100, a = 100, q = 50 })
  buyList({ id = 50053, max = -1, qty = 20 })
  T.eq(ns:ListStillWanted(50053), 20)
  ns:NoteListPurchase(50053, 20)
  T.eq(ns:ListStillWanted(50053), 0)
end)

T.test("ListStillWanted: any price with no price known wants nothing yet", function()
  buyList({ id = 50054, max = 0, qty = 3 }, { anyPrice = true })
  T.eq(ns:ListStillWanted(50054), 0)
end)

T.test("ListStillWanted: off and unticked lists want nothing", function()
  buyList({ id = 50055, max = 0, qty = 3 })
  T.eq(ns:ListStillWanted(50055), 0, "Up to off")
  local list = buyList({ id = 50056, max = 100, qty = 3 })
  list.on = false
  T.eq(ns:ListStillWanted(50056), 0, "not ticked to buy from")
end)

T.test("ListStillWanted: what you already own doesn't count on a normal list", function()
  S.bags[50057] = 50
  buyList({ id = 50057, max = 100, qty = 3 })
  T.eq(ns:ListStillWanted(50057), 3, "Want is how many to buy, whatever you have")
end)

T.test("Crate lists count what you have", function()
  local ID = 50060
  buyList({ id = ID, max = 100, qty = 10 }, { countHave = true })
  S.bags[ID] = 4
  T.eq(ns:ListStillWanted(ID), 6)
  ns:NoteListPurchase(ID, 6)
  T.eq(ns:ListStillWanted(ID), 6, "a purchase only counts once it's yours")
  S.bags[ID], S.bank[ID] = 7, 3
  T.eq(ns:ListStillWanted(ID), 0, "bags and bank")
end)

T.test("Crate lists count purchases still in the mail", function()
  local ID = 50061
  buyList({ id = ID, max = 100, qty = 10 }, { countHave = true })
  S.bags[ID] = 4
  ns.db.onTheWay = { [ME] = { [ID] = { n = 6, base = 4, t = S.now } } }
  T.eq(ns:ListStillWanted(ID), 0)
end)
