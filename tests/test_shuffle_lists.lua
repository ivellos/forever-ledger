-- Shuffle quantities, price caps, alternatives, and preservation of list progress.
local T = ...
local ns, S = T.ns, T.S
local function price(id, ladder, cheapest, average)
  ns.db.prices[ns.MarketKey()] = ns.db.prices[ns.MarketKey()] or {}
  ns.db.prices[ns.MarketKey()][id] = { m = cheapest, a = average or cheapest, l = ladder, q = 100, t = S.now }
end
local function craft()
  price(88001, "10:2,15:10,40:100", 10, 20)
  price(88002, "3:10,8:100", 3, 5)
  return { key = "craft:test", id = 88001, units = 2, maxBuy = 18,
    buys = { { id = 88001, qty = 2, price = 15 }, { id = 88002, qty = 1, price = 5 } },
    opt = { kind = "craft", units = 2, rec = { n = "Test gloves", oq = 1 },
      next = { kind = "vendor" } } }
end
T.test("Crafts scale materials and use route caps independent of the ladder", function()
  local s = craft()
  local buys = ns:ShuffleShoppingItems(s, 3)
  T.eq(buys[1].qty, 6)
  T.eq(buys[1].max, 18, "the shuffle cap, not today's ladder")
  T.eq(buys[2].qty, 3)
  T.eq(buys[2].max, 5)
  local big = ns:ShuffleShoppingItems(s, 20)
  T.eq(big[1].max, 18, "never raise above the shuffle limit")
  T.eq(big[2].max, 5, "extra material stays within its cost assumption")
end)
T.test("A new list uses the shuffle name and starts with buying off", function()
  local list = assert(ns:ShuffleToShoppingList(craft(), nil, 2))
  T.eq(list.name, "Test gloves")
  T.eq(list.on, false)
  T.eq(list.countHave, nil, "normal buy quantities")
  T.eq(list.items[1].qty, 4)
  T.eq(ns:CurrentShoppingList(), list)
end)
T.test("Existing quantities add; purchased counts and stricter limits survive", function()
  local list = ns:NewShoppingList("Supplies")
  list.on = true
  list.items = { { id = 88001, qty = 5, max = 8, bought = 5, done = true },
    { id = 88099, qty = 7, max = 44, bought = 2 } }
  local untouched = list.items[2]
  T.eq(ns:ShuffleToShoppingList(craft(), list, 3), list)
  T.eq(list.items[1].qty, 11)
  T.eq(list.items[1].bought, 5)
  T.eq(list.items[1].max, 8)
  T.eq(list.items[1].done, nil)
  T.eq(list.items[2], untouched)
  T.eq(untouched.qty, 7)
  T.eq(list.on, true)
  T.eq(ns:ListStillWanted(88001), 6, "only the added purchases remain")
end)
T.test("Adding again increases quantities instead of resetting progress", function()
  local list = assert(ns:ShuffleToShoppingList(craft(), nil, 1))
  list.items[1].bought = 1
  ns:ShuffleToShoppingList(craft(), list, 1)
  T.eq(list.items[1].qty, 4)
  T.eq(list.items[1].bought, 1)
end)
T.test("Vendor flips use the chosen item count and never exceed the vendor-flip cap", function()
  price(88003, "20:1,25:10,40:100", 20, 30)
  local s = { key = "flip:test", id = 88003, units = 1, single = true, maxBuy = 29,
    buys = { { id = 88003, qty = 1, price = 25 } }, opt = { kind = "vendor" } }
  local list = assert(ns:ShuffleToShoppingList(s, nil, 5))
  T.eq(list.items[1].qty, 5)
  T.eq(list.items[1].max, 29)
  T.eq(ns:ShuffleShoppingItems(s, 20)[1].max, 29)
end)
T.test("A disenchant group adds only its cheapest alternative", function()
  local a = { id = 88004, units = 1, single = true, maxBuy = 50,
    buys = { { id = 88004, qty = 1, price = 20 } }, opt = { kind = "disenchant", mats = {} } }
  local b = { id = 88005, units = 1, single = true, maxBuy = 50,
    buys = { { id = 88005, qty = 1, price = 30 } }, opt = { kind = "disenchant", mats = {} } }
  local group = { key = "group:test", group = "Green armor", single = true, members = { a, b } }
  local list = assert(ns:ShuffleToShoppingList(group, nil, 4))
  T.eq(#list.items, 1)
  T.eq(list.items[1].id, 88004)
  T.eq(list.items[1].qty, 4)
end)
T.test("Later crafting steps add extra inputs and aggregate shared materials", function()
  local s = craft()
  s.opt.next = { kind = "craft", units = 1, rec = { oq = 1 },
    buys = { { id = 88002, qty = 2, cost = 5 }, { id = 88006, qty = 1, cost = 7 } },
    next = { kind = "vendor" } }
  local buys = ns:ShuffleShoppingItems(s, 2)
  T.eq(buys[2].qty, 6, "initial and later materials combined")
  T.eq(buys[3].qty, 2)
  T.eq(buys[3].max, 7, "fallback to known route cost when unlisted")
end)
T.test("Unknown cap and invalid amounts fail before creating a list", function()
  local n = #ns:ShoppingLists()
  local s = craft()
  s.maxBuy = nil
  T.eq(ns:ShuffleToShoppingList(s, nil, 1), nil)
  for _, runs in ipairs({ 0, -1, 1.5, 10001, math.huge }) do
    T.eq(ns:ShuffleToShoppingList(craft(), nil, runs), nil)
  end
  T.eq(#ns:ShoppingLists(), n)
end)
T.test("Crate, any-price, removed and conflicting craft lists remain untouched", function()
  for _, field in ipairs({ "countHave", "temp", "crateID", "anyPrice" }) do
    local list = ns:NewShoppingList("Special")
    list[field] = true
    T.eq(ns:ShuffleToShoppingList(craft(), list, 1), nil)
    T.eq(#list.items, 0)
  end
  T.eq(ns:ShuffleToShoppingList(craft(), { items = {} }, 1), nil)
  local list = ns:NewShoppingList("Craft instead")
  list.items[1] = { id = 88002, qty = 9, mode = "craft", max = 1 }
  T.eq(ns:ShuffleToShoppingList(craft(), list, 1), nil)
  T.eq(#list.items, 1, "no partial first-material addition")
  T.eq(list.items[1].qty, 9)
end)
T.test("Gear versions and unrelated entries keep their own quantities", function()
  local list = ns:NewShoppingList("Gear")
  list.items[1] = { id = 88001, suffix = "of the Monkey", qty = 3, max = 100 }
  ns:ShuffleToShoppingList(craft(), list, 1)
  T.eq(list.items[1].qty, 3)
  T.eq(list.items[2].id, 88001)
  T.eq(list.items[2].suffix, nil)
end)

T.test("Material limits retain the route cost assumption rather than changing with the ladder", function()
  local s = craft()
  ns.db.vendorBuy[88002] = { p = 2, t = S.now }
  T.eq(ns:ShuffleShoppingItems(s, 3)[2].max, 5)
  ns.db.vendorBuy[88002] = nil
end)
T.test("Done entries with no bought count still request the newly added amount", function()
  local list = ns:NewShoppingList("Completed")
  list.items[1] = { id = 88001, qty = 5, max = 8, done = true }
  ns:ShuffleToShoppingList(craft(), list, 1)
  T.eq(list.items[1].bought, 5, "old completed amount stays completed")
  T.eq(list.items[1].qty, 7)
end)
