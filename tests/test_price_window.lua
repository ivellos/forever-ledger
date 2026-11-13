-- The price window's numbers (PriceWindow.lua ns:ItemPriceSummary, owner, November 8) and
-- adding a recipe's materials to a shopping list (ShoppingLists.lua ns:CraftToShoppingList).
local T = ...
local ns, S = T.ns, T.S

local DAY = 86400
local function market() local k = ns.MarketKey(); ns.db.prices[k] = ns.db.prices[k] or {}; return ns.db.prices[k] end
-- ShoppingLists.lua keeps its recipe index for 30 seconds: move the clock on so each
-- test sees its own characters.
local step = 0
local function fresh() T.resetDB(); step = step + 1; S.now = S.now + step * 1000 end

-- A typical price on each of the last n days (not today): price(daysAgo).
local function history(id, n, price)
  local now = S.now
  for i = n, 1, -1 do
    S.now = now - i * DAY
    ns:RecordPriceHistory(id, price(i), price(i), 10)
  end
  S.now = now
end

T.test("Price window: usual price, trend, listed, have, posted and your week", function()
  fresh()
  local id = 71001
  S.items[id] = { name = "Test Bolt" }
  history(id, 20, function(i) return i > 6 and 100 or 120 end)
  market()[id] = { m = 95, a = 110, q = 40, t = time() }
  S.bags[id] = 5
  ns.db.myAuctions = {
    [ns.CharKey()] = { list = { { id = id, q = 3 }, { id = id, q = 2, sold = true }, { id = 5, q = 9 } } },
    [ns.CharKey() .. " (neutral)"] = { list = { { id = id, q = 1 } } },
  }
  ns.db.sales = { { t = time() - DAY, c = "x", n = "Test Bolt", a = 500, q = 2 }, { t = time() - 10 * DAY, c = "x", n = "Test Bolt", a = 900, q = 9 } }
  ns.db.purchases = { { t = time(), c = "x", id = id, q = 4, a = 400 } }
  ns.db.vendorLog = { { t = time(), c = "x", id = id, q = 1, a = 7, s = "sell" }, { t = time(), c = "x", id = id, q = 2, a = 50, s = "buy" } }
  local s = ns:ItemPriceSummary(id)
  T.eq(s.usual, 100, "the month's usual price")
  T.eq(s.cheapest, 95)
  T.eq(s.listed, 40)
  T.ok(s.trend and math.abs(s.trend - 0.2) < 1e-9, "this week 120 against 100 before: up 20%")
  T.eq(s.have.total, 5)
  T.eq(s.posted, 4, "unsold auctions at both auction houses")
  T.same(s.week.sold, { n = 2, a = 500 }, "only the last 7 days")
  T.same(s.week.bought, { n = 6, a = 450 }, "auction house and vendor")
  T.same(s.week.vendorSold, { n = 1, a = 7 })
  T.eq(s.craft, nil, "nothing makes it")
end)

T.test("Price window: too few scans says so instead of guessing", function()
  fresh()
  local id = 71002
  history(id, 2, function() return 100 end)
  local s = ns:ItemPriceSummary(id)
  T.eq(s.usual, nil)
  T.eq(s.trend, nil)
  T.eq(s.listed, nil, "never scanned")
end)

local BAG, CLOTH, THREAD = 71011, 71012, 71013
local function recipe()
  S.items[BAG] = { name = "Test Bag" }
  ns.db.chars.x = { name = "Crafter", profs = { Tailoring = { recipes = {
    [1] = { n = "Test Bag", out = BAG, oq = 1, r = { { CLOTH, 4 }, { THREAD, 1 } } } } } } }
end

T.test("Price window: what crafting it costs, and the profit", function()
  fresh()
  recipe()
  market()[CLOTH] = { m = 10, a = 12, q = 100, l = "10:3,12:10", t = time() }
  market()[THREAD] = { m = 50, q = 5, t = time() }
  market()[BAG] = { m = 200, q = 5, t = time() }
  S.bags[CLOTH] = 7
  ns:InvalidateValues(true)
  local c = ns:ItemPriceSummary(BAG).craft
  T.ok(c, "a recipe makes it")
  T.eq(c.prof, "Tailoring")
  T.eq(c.who, "Crafter")
  T.eq(c.mats[1].cost, 42, "3 at 10c and 1 at 12c, up the price ladder")
  T.eq(c.mats[1].have, 7)
  T.eq(c.mats[2].cost, 50)
  T.eq(c.cost, 92)
  T.eq(c.sells, 190, "200c after the 5% cut (no vendor price: no deposit to allow for)")
  T.eq(c.profit, 98)
end)

-- Owner's screenshot, November 8: Bolt of Silk Cloth showed 59c profit selling at 8s 55c,
-- while Worth to you, beside it, said 7s 35c after one unsold listing.
T.test("Price window: a craft sells for what Worth to you says, after one unsold listing", function()
  fresh()
  -- Its own item: the stubs remember an item's details (BAG has no vendor price).
  local SACK = 71014
  S.items[SACK] = { name = "Test Sack", sell = 100 }
  ns.db.chars.x = { name = "Crafter", profs = { Tailoring = { recipes = {
    [2] = { n = "Test Sack", out = SACK, oq = 1, r = { { CLOTH, 4 }, { THREAD, 1 } } } } } } }
  market()[CLOTH] = { m = 10, q = 100, t = time() }
  market()[THREAD] = { m = 50, q = 5, t = time() }
  market()[SACK] = { m = 200, q = 5, t = time() }
  ns.db.vendorSell[SACK] = 100
  ns:InvalidateValues(true)
  local c = ns:ItemPriceSummary(SACK).craft
  T.eq(c.deposit, 20, "an 8-hour deposit at a 100c vendor price")
  T.eq(c.sells, 170, "200c after the 5% cut, less the deposit")
  T.eq(c.profit, 170 - 90)
  local _, opts = ns:GetValue(SACK)
  local ah
  for _, o in ipairs(opts) do if o.kind == "ah" then ah = o end end
  T.eq(c.sells, ah and ah.value, "the same as Worth to you")
end)

T.test("Price window: the graph's scale falls on round prices", function()
  T.eq(ns.PriceScaleStep(26.7), 50, "a narrow range: steps of 50c")
  T.eq(ns.PriceScaleStep(823), 1000, "10s")
  T.eq(ns.PriceScaleStep(180), 200)
  T.eq(ns.PriceScaleStep(21), 25)
  T.eq(ns.PriceScaleStep(0.3), 0.5, "ammo")
  T.eq(ns.PriceScaleLabel(1950, 50), "19s 50c")
  T.eq(ns.PriceScaleLabel(2000, 50), "20s")
  T.eq(ns.PriceScaleLabel(12000, 2000), "1g 20s")
  T.eq(ns.PriceScaleLabel(0, 1000), "0c")
  T.eq(ns.PriceScaleLabel(0.5, 0.5), "0.5c")
end)

T.test("Price window: the click that opens it", function()
  local real = { IsAltKeyDown, IsControlKeyDown, IsShiftKeyDown }
  local alt, ctrl, shift = false, false, false
  IsAltKeyDown = function() return alt end
  IsControlKeyDown = function() return ctrl end
  IsShiftKeyDown = function() return shift end
  local ok, err = pcall(function()
    fresh()
    local function down(a, c, s) alt, ctrl, shift = a, c, s; return ns:PriceClickDown() end
    T.eq(ns:PriceClickName(), "Alt-click", "Alt by default")
    T.eq(down(true, false, false), true)
    T.eq(down(true, true, false), false, "Ctrl+Alt isn't Alt")
    T.eq(down(true, false, true), false, "Shift is never taken (links)")
    ns.db.settings.priceClick = "ctrl"
    T.eq(ns:PriceClickName(), "Ctrl-click")
    T.eq(down(true, false, false), false, "Alt-click left to the other addon")
    T.eq(down(false, true, false), true)
    ns.db.settings.priceClick = "ctrlalt"
    T.eq(down(false, true, false), false)
    T.eq(down(true, true, false), true)
    ns.db.settings.priceWindow = false
    T.eq(down(true, true, false), false, "turned off")
  end)
  IsAltKeyDown, IsControlKeyDown, IsShiftKeyDown = real[1], real[2], real[3]
  assert(ok, err)
end)

-- Owner's screenshots, November 8: clicking Fortified Spaulders of the Whale on the auction
-- house opened All versions. The row gives a group link; its tooltip had the version.
T.test("Price window: an auction house click opens the version its tooltip showed", function()
  fresh()
  local id = 71051
  market()[id] = { m = 250, q = 3, sx = "12719:300:2", t = time() }
  local whale = "|cff1eff00|Hitem:71051::::::::20:1482::1:1:12719:1:28:7000|h[Test Spaulders of the Whale]|h|r"
  local group = "|cff1eff00|Hitem:71051::::::::20:1482::1:1:3524|h[Test Spaulders]|h|r"
  T.eq(ns:ClickedLink(id, whale), whale, "a link with its version is used as it is")
  ns.RememberHoveredItem(whale)
  ns.HoveredItemGone()
  T.eq(ns:ClickedLink(id, group), whale, "the click closed the tooltip just now")
  T.eq(ns:ClickedLink(id, nil), whale, "a row with no link")
  T.eq(ns:ClickedLink(71052, nil), nil, "another item")
  S.now = S.now + 5
  T.eq(ns:ClickedLink(id, group), group, "an old tooltip doesn't count")
end)

-- Codex review, November 8: opening the item shown again, from a search-results row or
-- /fl price, kept the last version (and Add to shopping list added that version).
T.test("Price window: opening the same item without a version shows All versions", function()
  fresh()
  local id = 71054
  market()[id] = { m = 250, q = 3, sx = "12719:300:2", t = time() }
  local whale = "|cff1eff00|Hitem:71054::::::::20:1482::1:1:12719:1:28:7000|h[Test Spaulders of the Whale]|h|r"
  local group = "|cff1eff00|Hitem:71054::::::::20:1482::1:1:3524|h[Test Spaulders]|h|r"
  T.eq(ns:PriceWindowChoose(id, whale), 12719)
  T.eq(ns:PriceWindowChoose(id, group), nil, "a search-results row")
  T.eq(ns:PriceWindowChoose(id, whale), 12719)
  T.eq(ns:PriceWindowChoose(id, nil), nil, "/fl price or the look-up box")
end)

-- Owner's screenshot, November 8: Fortified Spaulders bonus 12734 showed "other stats",
-- because no full scan had read a listing of it with its name.
T.test("Price window: a version full scans never named learns it from the link", function()
  fresh()
  ns:ForgetVersionNames()
  local id = 71053
  ns.db.itemNames[id] = "Test Spaulders"
  ns.db.suffixNames["of the Whale"] = 12719
  market()[id] = { m = 250, q = 3, sx = "12719:300:2;12734:1800:2;12735:1700:1", t = time() }
  local function link(bonus, shown)
    return "|cff1eff00|Hitem:" .. id .. "::::::::20:1482::1:1:" .. bonus .. ":1:28:7000|h[" .. shown .. "]|h|r"
  end
  T.eq(ns:VersionName(12734), nil, "not named yet")
  ns:LearnVersionName(id, 12734, link(12734, "Test Spaulders"))
  T.eq(ns:VersionName(12734), nil, "a link without a version in its name teaches nothing")
  ns:LearnVersionName(id, 12734, link(12734, "Test Spaulders of Marksmanship"))
  T.eq(ns:VersionName(12734), "of Marksmanship")
  T.eq(ns.db.suffixNames["of Marksmanship"], 12734, "saved")
  ns:LearnVersionName(id, 12719, link(12719, "Test Spaulders of Blocking"))
  T.eq(ns:VersionName(12719), "of the Whale", "a scan's name is kept")
  ns:LearnVersionName(id, 12735, link(12735, "Test Spaulders of the Whale"))
  T.eq(ns.db.suffixNames["of the Whale"], 12719, "a name another number has isn't taken over")
  T.eq(ns:VersionName(12735), "of the Whale", "but shows for this session")
  ns:LearnVersionName(id, 12736, link(12736, "Other Spaulders of Stamina"))
  T.eq(ns:VersionName(12736), nil, "a link for another item's name")
  ns:ForgetVersionNames()
end)

T.test("Price window: a material without a price leaves the cost open", function()
  fresh()
  recipe()
  market()[CLOTH] = { m = 10, q = 100, t = time() }
  market()[BAG] = { m = 200, q = 5, t = time() }
  local c = ns:ItemPriceSummary(BAG).craft
  T.eq(c.missing, THREAD)
  T.eq(c.cost, nil)
  T.eq(c.profit, nil)
end)

T.test("Price window: one version of random-stat gear", function()
  fresh()
  local id = 71021
  market()[id] = { m = 250, q = 3, sx = "1019:300:2;1200:800:1", t = time() }
  local now = S.now
  for i = 3, 1, -1 do
    S.now = now - i * DAY
    ns:RecordVersionHistory(id, { [1019] = { m = 300 + i, q = 2 } })
  end
  S.now = now
  local s = ns:ItemPriceSummary(id, 1019)
  T.eq(s.cheapest, 300)
  T.eq(s.listed, 2)
  T.eq(s.usual, 302, "the middle of 301, 302 and 303")
end)

T.test("Add materials: the recipe's materials for that many crafts", function()
  fresh()
  recipe()
  local list = ns:CraftToShoppingList(BAG, 3)
  T.ok(list, "a new list")
  T.eq(list.name, "Test Bag")
  T.eq(#list.items, 2)
  T.eq(list.items[1].id, CLOTH)
  T.eq(list.items[1].qty, 12)
  T.eq(list.items[2].qty, 3)
  T.eq(list.items[1].src, "usual")
  -- Again into the same list: added to what it wants; a typed price stays.
  ns:SetListItemPrice(list.items[1], 5)
  T.eq(ns:CraftToShoppingList(BAG, 2, list), list)
  T.eq(list.items[1].qty, 20)
  T.eq(list.items[1].max, 5, "your price stays")
  T.eq(list.items[2].qty, 5)
end)

T.test("Add materials: refuses what it can't do, before changing anything", function()
  fresh()
  recipe()
  local before = #ns:ShoppingLists()
  local list, err = ns:CraftToShoppingList(BAG, 0)
  T.eq(list, nil); T.ok(err)
  list, err = ns:CraftToShoppingList(BAG, 1.5)
  T.eq(list, nil); T.ok(err)
  list, err = ns:CraftToShoppingList(71099, 1)
  T.eq(list, nil); T.ok(err, "no recipe")
  T.eq(#ns:ShoppingLists(), before, "no list made")
  local crafting = ns:NewShoppingList("Crafting")
  crafting.items[1] = { id = CLOTH, mode = "craft", qty = 1 }
  list, err = ns:CraftToShoppingList(BAG, 1, crafting)
  T.eq(list, nil); T.ok(err, "that list crafts a material")
  T.eq(#crafting.items, 1)
end)

-- Owner's screenshot, November 8: the main account's graph only had the days it scanned.
T.test("Price history: a sync partner's prices from today go into today's history", function()
  fresh()
  local home, neutral = ns.MarketKey(), ns.RealmName() .. "|Neutral"
  local d = ns.LocalDay(time())
  ns:MergeData({ prices = {
    [home] = { [71041] = { m = 90, a = 100, q = 7, t = time() }, [71042] = { m = 50, a = 60, q = 3, t = time() - 2 * DAY } },
    [neutral] = { [71043] = { m = 70, a = 80, q = 2, t = time() } },
  } }, "Partner Name")
  T.runTimers()
  T.eq(ns.db.history[home][71041], d .. ":90:100")
  T.eq(ns.db.historyQty[home][71041], d .. ":7")
  T.eq(ns.db.history[home][71042], nil, "an older day isn't put on today")
  T.eq(ns.db.history[neutral][71043], d .. ":70:80", "in its own market")
  -- An import (not from a partner) doesn't touch history.
  ns:MergeData({ prices = { [home] = { [71044] = { m = 90, a = 100, q = 7, t = time() } } } })
  T.runTimers()
  T.eq((ns.db.history[home] or {})[71044], nil)
end)

-- Frank's BugSack, November 12: a partner's full scan recorded into history in one go
-- ran too long ("script ran too long", Core.lua MergeData).
T.test("Price history: a partner's many prices are recorded a few at a time", function()
  fresh()
  T.runTimers()
  local home, d = ns.MarketKey(), ns.LocalDay(time())
  local items = {}
  for i = 1, 40 do items[71100 + i] = { m = 100 + i, a = 110 + i, q = 3, t = time() } end
  local realClock, clock = debugprofilestop, 0
  debugprofilestop = function() clock = clock + 3; return clock end   -- each look: 3 ms later
  local _, nPrices = ns:MergeData({ prices = { [home] = items } }, "Partner Name")
  T.eq(nPrices, 40, "the prices themselves are saved at once")
  T.eq(ns.db.prices[home][71101].m, 101)
  T.eq((ns.db.history[home] or {})[71101], nil, "history waits for the next frame")
  local steps = T.runTimers()
  debugprofilestop = realClock
  T.ok(steps > 5, "spread over frames: " .. steps)
  for i = 1, 40 do T.eq(ns.db.history[home][71100 + i], ("%d:%d:%d"):format(d, 100 + i, 110 + i)) end
  -- And it starts again for the next one.
  ns:MergeData({ prices = { [home] = { [71101] = { m = 90, a = 95, q = 2, t = time() + 1 } } } }, "Partner Name")
  T.runTimers()
  T.eq(ns.db.history[home][71101], ("%d:90:95"):format(d), "today's lower cheapest and the newer typical")
  -- A run that never comes back (its timer lost) doesn't hold up the next.
  ns:MergeData({ prices = { [home] = { [71201] = { m = 5, a = 6, q = 1, t = time() } } } }, "Partner Name")
  for k in pairs(S.timers) do S.timers[k] = nil end
  ns:MergeData({ prices = { [home] = { [71202] = { m = 7, a = 8, q = 1, t = time() } } } }, "Partner Name")
  T.runTimers()
  T.eq(ns.db.history[home][71201], ("%d:5:6"):format(d), "picked up by the next run")
  T.eq(ns.db.history[home][71202], ("%d:7:8"):format(d))
end)

T.test("Price window: Add to shopping list puts the item on the list you're on", function()
  fresh()
  local list = ns:QuickAddToShoppingList(71031)
  T.eq(list.name, "Shopping list", "a new list when there's none")
  T.eq(list.items[1].id, 71031)
  local again = ns:QuickAddToShoppingList(71032)
  T.eq(again, list, "the same list next time")
  T.eq(#list.items, 2)
end)
