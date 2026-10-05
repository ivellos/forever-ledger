-- Unlimited vendor stock follows the same policy for items and craft materials.
local T = ...
local ns, S = T.ns, T.S
local ID, EXTRA, OUT = 89101, 89102, 89103
local function price(id, p)
  ns.db.prices[ns.MarketKey()] = ns.db.prices[ns.MarketKey()] or {}
  ns.db.prices[ns.MarketKey()][id] = { m = p, a = p, q = 100, t = S.now }
end
local function fresh()
  T.resetDB(); ns:InvalidateValues(true)
  local l = ns:NewShoppingList("Vendor test"); l.on = true
  ns.db.vendorBuy[ID] = { p = 100 }
  price(ID, 10)
  return l
end
T.test("Unlimited vendor stock excludes hand-added items by default", function()
  local l = fresh(); T.eq(ns.db.settings.vendorItemsAH, false)
  local e = ns:AddToShoppingList(l, ID); ns:SetListItemPrice(e, 1000000)
  T.eq(ns:ListVendorPrice(ID), 100)
  T.eq((ns:ItemLimit(l, e)), nil); T.eq(#ns:ShoppingTargets(), 0)
  ns:BuyListAgain(l); T.eq(e.max, 1000000); T.eq(e.src, "you")
end)
T.test("Vendor opt-in caps spending and preserves typed prices, including off", function()
  local l = fresh(); local e = ns:AddToShoppingList(l, ID)
  ns.db.settings.vendorItemsAH = true
  ns:SetListItemPrice(e, 1000000)
  T.eq((ns:ItemLimit(l, e)), 100); T.eq(ns:ShoppingTargets()[1].limit, 100)
  ns.db.vendorBuy[ID].p = 80; ns:BuyListAgain(l)
  T.eq((ns:ItemLimit(l, e)), 80); T.eq(e.max, 1000000); T.eq(e.src, "you")
  ns:SetListItemPrice(e, 20); T.eq((ns:ItemLimit(l, e)), 20)
  ns:SetListItemPrice(e, 0); T.eq(#ns:ShoppingTargets(), 0)
  ns:SetListItemPrice(e, -1); T.eq((ns:ItemLimit(l, e)), 80)
end)
T.test("Limited vendor stock stays an ordinary auction item", function()
  local l = fresh(); ns.db.vendorBuy[ID].lim = true
  local e = ns:AddToShoppingList(l, ID); ns:SetListItemPrice(e, 500)
  T.eq(ns:ListVendorPrice(ID), nil); T.eq(ns:ShoppingTargets()[1].limit, 500)
  ns.db.settings.vendorItemsAH = true; T.eq((ns:ItemLimit(l, e)), 500)
end)
local function recipe()
  ns.db.vendorSell[OUT] = 344
  ns.db.chars[ns.CharKey()] = { name = "Tester", realm = "Testrealm", faction = "Alliance",
    profs = { Tailoring = { rank = 300, recipes = { [9877] = { n = "Test cloth", out = OUT, oq = 1,
      r = { { EXTRA, 2 }, { ID, 1 } } } } } } }
  price(EXTRA, 10); S.now = S.now + 31; ns:BuildUsageIndex(); ns:InvalidateValues(true)
end
T.test("Craft materials use the vendor policy and keep stricter typed limits", function()
  local l = fresh(); recipe()
  l.items = { { id = OUT, qty = 1, mode = "craft" } }
  ns:FillUsualPrices(l)
  for _, t in ipairs(ns:ShoppingTargets()) do T.ok(t.id ~= ID) end
  ns.db.settings.vendorItemsAH = true
  T.eq((ns:MaterialLimit(l, ID)), 100)
  local found
  for _, t in ipairs(ns:ShoppingTargets()) do if t.id == ID then found = t end end
  T.ok(found); T.eq(found.limit, 100)
  l.matMax = { [ID] = 30 }; T.eq((ns:MaterialLimit(l, ID)), 30)
  l.matMax[ID] = 0; T.eq((ns:MaterialLimit(l, ID)), nil)
end)
T.test("Buy again keeps the main-input cap after 3 bought and 20 owned", function()
  local l = fresh(); recipe()
  -- A real route's main input is EXTRA; vendor ID is its extra material.
  local option
  for _, o in ipairs(ns:Options(EXTRA)) do if o.kind == "craft" then option = o end end
  T.ok(option, "main input route found")
  local chosen = { id = EXTRA, units = 2, maxBuy = option.value * 0.9, opt = option,
    buys = { { id = EXTRA, qty = 2, price = 10 }, { id = ID, qty = 1, price = 10 } } }
  ns:ShuffleToShoppingList(chosen, l, 5)
  local e = l.items[1]; T.eq(e.id, EXTRA)
  local cap = e.max; T.ok(cap > 10, "route cap exceeds today's 10 copper quote")
  S.owned[EXTRA] = 20; e.bought = 3
  local saved = assert(ns.Deserialize(ns.Serialize(l)))
  ns:BuyListAgain(saved)
  T.eq(saved.items[1].max, cap); T.eq(saved.items[1].src, "shuffle")
  T.eq(saved.items[1].bought, nil)
  T.ok(ns:ListPriceSourceText(saved, saved.items[1]):find("route cap", 1, true))
  T.ok(ns:ListPriceSourceText(saved, saved.items[2]):find("extra material cost", 1, true))
  for _, t in ipairs(ns:ShoppingTargets()) do T.ok(t.id ~= ID, "vendor extra stays out") end
end)

T.test("Typed shuffle price reveals its cap and can return to automatic", function()
  local l = fresh(); ns.db.vendorBuy[ID] = nil; ns.db.vendorSell[ID] = 165
  local f = assert(ns:VendorFlip(ID)); ns:ShuffleToShoppingList(f, l, 5)
  local e = l.items[1]; local cap = e.max
  ns:SetListItemPrice(e, 10); e.bought = 3
  T.ok(ns:ListPriceSourceText(l, e):find("Automatic: shuffle", 1, true))
  T.eq((ns:AutomaticListItemPrice(l, e)), cap)
  ns:UseAutomaticListItemPrice(l, e)
  T.eq(e.max, cap); T.eq(e.src, "shuffle"); T.eq(e.bought, 3)
end)
T.test("Typed hand item can return to usual plus its list allowance", function()
  local l = fresh(); ns.db.vendorBuy[ID] = nil
  local e = ns:AddToShoppingList(l, ID); ns:SetListItemPrice(e, 999)
  l.allowance = 25; price(ID, 100)
  T.ok(ns:ListPriceSourceText(l, e):find("usual + 25%", 1, true))
  ns:UseAutomaticListItemPrice(l, e); T.eq(e.max, 125); T.eq(e.src, "usual")
  price(ID, 200); ns:BuyListAgain(l); T.eq(e.max, 250)
end)
T.test("Adding a shuffle under a typed override retains an automatic source", function()
  local l = fresh(); ns.db.vendorBuy[ID] = nil; ns.db.vendorSell[ID] = 165
  local e = ns:AddToShoppingList(l, ID); ns:SetListItemPrice(e, 999)
  ns:ShuffleToShoppingList(assert(ns:VendorFlip(ID)), l, 1)
  T.eq(e.max, 999); T.eq(e.src, "you")
  ns.db.vendorSell[ID] = 200; ns:BuyListAgain(l); T.eq(e.max, 999)
  T.eq((ns:AutomaticListItemPrice(l, e)), ns:VendorFlipLimit(200))
  ns:UseAutomaticListItemPrice(l, e); T.eq(e.src, "shuffle"); T.eq(e.max, ns:VendorFlipLimit(200))
end)
