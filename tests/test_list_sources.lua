-- Spending-limit provenance, refresh points and schema 6 migration.
local T = ...
local ns, S = T.ns, T.S
local ID, EXTRA, OUT = 89001, 89002, 89003
local function price(id, p)
  ns.db.prices[ns.MarketKey()] = ns.db.prices[ns.MarketKey()] or {}
  ns.db.prices[ns.MarketKey()][id] = { m = p, a = p, q = 100, t = S.now }
end
local function fresh()
  T.resetDB()
  ns:InvalidateValues(true)
  price(ID, 1234)
  return ns:NewShoppingList("Materials")
end
local function shuffle(cap, name)
  return { id = ID, key = name, units = 1, single = true, maxBuy = cap,
    buys = { { id = ID, qty = 1, price = 1234 } },
    opt = { kind = "convert", id = ID, per = 1, next = { kind = "vendor", id = name, value = 5000 } } }
end
T.test("A hand-added item uses the list's default 10 percent allowance", function()
  local l = fresh()
  local e = ns:AddToShoppingList(l, ID)
  T.eq(e.src, "usual"); T.eq(e.max, 0, "not filled before buying")
  ns:FillUsualPrices(l)
  T.eq(e.max, 1357, "exact usual + 10 percent, floored to copper")
  T.eq(l.allowance, 10)
end)
T.test("Each list has its own allowance; it applies only at refresh points", function()
  local a = fresh(); local b = ns:NewShoppingList("Other")
  local ea = ns:AddToShoppingList(a, ID); local eb = ns:AddToShoppingList(b, ID)
  for _, pct in ipairs({ 0, 5, 10, 25 }) do
    a.allowance = pct; ns:FillUsualPrices(a)
    T.eq(ea.max, math.floor(1234 * (100 + pct) / 100))
  end
  ns:FillUsualPrices(b); T.eq(eb.max, 1357)
  price(ID, 2000); a.allowance = 0
  T.eq(ea.max, 1542, "price and allowance changes alone don't authorize more")
  ns:BuyListAgain(a); T.eq(ea.max, 2000)
  T.eq(eb.max, 1357, "another list stays as it was")
end)
T.test("Automatic usual limits refresh down and up; missing price turns them off", function()
  local l = fresh(); local e = ns:AddToShoppingList(l, ID)
  ns:FillUsualPrices(l); price(ID, 100); ns:FillUsualPrices(l); T.eq(e.max, 110)
  price(ID, 300); ns:BuyListAgain(l); T.eq(e.max, 330)
  ns.db.prices[ns.MarketKey()][ID] = nil
  ns:BuyListAgain(l); T.eq(e.max, 0); T.eq(e.src, "usual")
end)
T.test("Typed prices always win, including higher, off, any and the same price", function()
  for _, v in ipairs({ 1, 9999, 0, -1, 1357 }) do
    local l = fresh(); local e = ns:AddToShoppingList(l, ID)
    ns:FillUsualPrices(l); ns:SetListItemPrice(e, v)
    price(ID, 2500); ns:FillUsualPrices(l); ns:BuyListAgain(l)
    T.eq(e.max, v); T.eq(e.src, "you")
    ns:ShuffleToShoppingList(shuffle(2000, "A"), l, 1)
    T.eq(e.max, v, "adding a shuffle never overwrites you")
    T.eq(e.src, "you")
  end
end)
T.test("A shuffle replaces a usual limit; two shuffles use the lower cap", function()
  local l = fresh(); local e = ns:AddToShoppingList(l, ID)
  ns:FillUsualPrices(l)
  ns:ShuffleToShoppingList(shuffle(2200, "A"), l, 1)
  T.eq(e.src, "shuffle"); T.eq(e.max, 2200)
  ns:ShuffleToShoppingList(shuffle(1800, "B"), l, 1); T.eq(e.max, 1800)
  ns:ShuffleToShoppingList(shuffle(2400, "B"), l, 1)
  T.eq(e.max, 2200, "same shuffle refreshes rather than retaining its old lower cap")
  T.ok(e.shuffleName:find("item 89001", 1, true), "name saved")
  T.eq(e.qty, 4, "hand item plus three additions")
end)
T.test("Buy again refreshes the same vendor route with live values", function()
  local l = fresh(); price(ID, 20); ns.db.vendorSell[ID] = 100
  local f = assert(ns:VendorFlip(ID))
  ns:ShuffleToShoppingList(f, l, 2)
  local e = l.items[1]
  T.eq(e.max, ns:VendorFlipLimit(100))
  ns.db.vendorSell[ID] = 80; e.bought, e.done = 2, true
  ns:BuyListAgain(l)
  T.eq(e.max, ns:VendorFlipLimit(80)); T.eq(e.src, "shuffle")
  T.eq(e.bought, nil); T.eq(e.done, nil); T.eq(e.qty, 2)
  ns.db.vendorSell[ID] = nil; ns:BuyListAgain(l); T.eq(e.max, 0)
end)
T.test("A saved crafting route refreshes caps after reload serialization", function()
  local l = fresh(); price(ID, 10); price(EXTRA, 5)
  ns.db.vendorSell[OUT] = 100
  ns.db.chars[ns.CharKey()] = { name = "Tester", realm = "Testrealm", faction = "Alliance",
    profs = { Tailoring = { rank = 300, recipes = { [9876] = { n = "Test robe", out = OUT, oq = 1,
      r = { { ID, 2 }, { EXTRA, 1 } } } } } } }
  ns:BuildUsageIndex(); ns:InvalidateValues(true)
  local selected
  local vendor, ah, thin = ns:FindShuffles()
  for _, section in ipairs({ vendor, ah, thin }) do
    for _, s in ipairs(section) do if s.id == ID and s.opt.kind == "craft" then selected = s end end
  end
  T.ok(selected, "crafting route found")
  ns:ShuffleToShoppingList(selected, l, 3)
  local saved = assert(ns.Deserialize(ns.Serialize(l)))
  price(EXTRA, 10); ns.db.vendorSell[OUT] = 80
  ns:BuyListAgain(saved)
  T.eq(saved.items[1].max, math.floor((80 - 10) / 2 * 0.9))
  T.eq(saved.items[2].max, 10, "extra material's current cost assumption")
  ns.db.chars[ns.CharKey()].profs = {}; ns:BuildUsageIndex(); ns:BuyListAgain(saved)
  T.eq(saved.items[1].max, 0, "unavailable recipe does not silently change route")
end)
T.test("Buy again takes the lower freshly valued cap across two routes", function()
  local l = fresh()
  local a, b = shuffle(2400, "A"), shuffle(1800, "B")
  ns:ShuffleToShoppingList(a, l, 1); ns:ShuffleToShoppingList(b, l, 1)
  local real = ns.RefreshShuffleShoppingSource
  ns.RefreshShuffleShoppingSource = function(_, source)
    return { [ID] = source.route == ns:ShuffleRouteKey(a.opt) and 1700 or 2100 }
  end
  local ok, err = pcall(ns.BuyListAgain, ns, l)
  ns.RefreshShuffleShoppingSource = real
  assert(ok, err); T.eq(l.items[1].max, 1700)
end)
T.test("Source hover text distinguishes player, usual and named shuffle limits", function()
  local l = fresh(); local e = ns:AddToShoppingList(l, ID)
  T.ok(ns:ListPriceSourceText(l, e):find("10%", 1, true))
  ns:ShuffleToShoppingList(shuffle(2200, "A"), l, 1)
  T.ok(ns:ListPriceSourceText(l, e):find(e.shuffleName, 1, true))
  ns:SetListItemPrice(e, 1200)
  T.ok(ns:ListPriceSourceText(l, e):find("Set by you", 1, true))
end)
T.test("Schema 6 protects every legacy nonzero limit and explicit off", function()
  local l = fresh()
  l.allowance = nil
  l.items = { { id = ID, max = 777, bought = 2, qty = 4 }, { id = EXTRA, max = -1 },
    { id = OUT, max = 0 }, { id = 89004, max = 0, offSet = true } }
  local db = ns.db; db.schema = 5
  ForeverLedgerDB = db; ns.accountSettings = nil
  local real = hooksecurefunc; hooksecurefunc = function() end
  T.fire("ADDON_LOADED", "ForeverLedger"); hooksecurefunc = real
  T.eq(ns.db.schema, 7); T.eq(l.allowance, 10)
  T.eq(l.items[1].src, "you"); T.eq(l.items[2].src, "you")
  T.eq(l.items[3].src, "usual"); T.eq(l.items[4].src, "you")
  ns:FillUsualPrices(l)
  T.eq(l.items[1].max, 777); T.eq(l.items[1].bought, 2)
  T.eq(l.items[2].max, -1); T.eq(l.items[4].max, 0)
  -- Existing new-style source records survive future logins unchanged.
  l.items[3].src = "shuffle"; l.allowance = 25
  ForeverLedgerDB = ns.db; ns.accountSettings = nil
  real = hooksecurefunc; hooksecurefunc = function() end
  T.fire("ADDON_LOADED", "ForeverLedger"); hooksecurefunc = real
  T.eq(l.items[3].src, "shuffle"); T.eq(l.allowance, 25)
end)
T.test("Craft material automatic limits use the allowance, with typed overrides", function()
  local l = fresh()
  T.eq((ns:MaterialLimit(l, ID)), 1357)
  l.allowance = 25; T.eq((ns:MaterialLimit(l, ID)), 1357, "snapshot")
  l.items[1] = { id = OUT, mode = "craft" }
  local real = ns.RecipeFor
  ns.RecipeFor = function() return { r = { { ID, 2 } } } end
  local ok, err = pcall(ns.FillUsualPrices, ns, l); ns.RecipeFor = real; assert(ok, err)
  T.eq((ns:MaterialLimit(l, ID)), 1542)
  l.matMax = { [ID] = 999 }; ns:BuyListAgain(l)
  T.eq((ns:MaterialLimit(l, ID)), 999)
  l.matMax[ID] = 0; ns:BuyListAgain(l)
  T.eq((ns:MaterialLimit(l, ID)), nil, "typed off remains off")
end)
