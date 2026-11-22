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

-- Owner's screenshot, October 22: Medium Leather's cheap listings were gone, the cheapest
-- was 2s 65c, but the typical price stayed about 1s 60c.
T.test("The typical price follows the ladder when the cheap end goes", function()
  price({ m = 54, a = 160, q = 30, t = 1, l = "54:10,265:30" })
  ns:DropBelow(ID, 265)
  local rec = ns.db.prices[ns.MarketKey()][ID]
  T.eq(rec.m, 265); T.eq(rec.a, 265, "the average of what's left")
  price({ m = 100, a = 110, q = 10, t = 1, l = "100:5,120:10" })
  ns:RemoveBought(ID, 5, 100)
  T.eq(ns.db.prices[ns.MarketKey()][ID].a, 120)
  price({ m = 265, a = 160, q = 20, t = os.time() })
  T.eq((ns:GetPrice(ID)), 265, "an average under the cheapest isn't used")
end)

T.test("RemoveBought: nothing at that price changes nothing", function()
  price({ m = 100, a = 100, q = 5, t = 1, l = "100:5" })
  ns:RemoveBought(ID, 2, 50)
  T.eq(ns.db.prices[ns.MarketKey()][ID].l, "100:5")
end)

---------------------------------------------------------------------------
-- The typical price (average of the cheapest 20) leaves out silly listings
---------------------------------------------------------------------------
T.test("TypicalPrice: the average of the cheapest 20 units", function()
  T.eq(ns.TypicalPrice({ { 100, 10 }, { 200, 10 } }), 150)
  T.eq(ns.TypicalPrice({ { 100, 15 }, { 300, 10 } }), 150, "only 5 of the dearer ones count")
  T.eq(ns.TypicalPrice({ { 100, 3 } }), 100, "fewer than 20 listed: all of them")
  T.eq(ns.TypicalPrice({}), nil)
end)

T.test("TypicalPrice: a listing over 10 times the cheapest is left out", function()
  -- Heavy Sharpening Stone, owner's export (October 22): 21s 90c cheapest, one at 99,999g.
  local units = {}
  for i = 1, 19 do units[i] = { 2190 + i * 10, 1 } end
  units[20] = { 999999990000, 1 }
  local typical = ns.TypicalPrice(units)
  T.ok(typical < 2400, "about 22s, not 5,000,000g: " .. tostring(typical))
  T.eq(ns.TypicalPrice({ { 100, 1 }, { 1000, 1 } }), 550, "10 times the cheapest still counts")
  T.eq(ns.TypicalPrice({ { 100, 1 }, { 1001, 1 } }), 100, "more than that doesn't")
  T.eq(ns.TypicalPrice({ { 999999990000, 1 } }), 999999990000, "a lone listing is all there is")
end)

-- AHledger (Prices.lua, November 16): read live through AHledgerAPI, after fresh own
-- scans, before the other addons; its packaged copy only after every other source;
-- never copied into saved data; its sold a day fills in sell speed.
T.test("AHledger prices: order, packaged copy, sell speed, never copied", function()
  local live = { median = 500, minBuyout = 450, quantity = 40, soldPerDay = 30, updated = time() - 600 }
  _G.AHledgerAPI = { GetPrice = function(id) if id == ID then return live end end }
  local s = ns.db.settings
  local oldSrc, oldAge = s.source, s.maxAgeHours
  s.source, s.maxAgeHours = "auto", 12
  price({ m = 100, a = 120, q = 5, t = time() })
  local v, src = ns:GetPrice(ID)
  T.eq(v, 120, "fresh own scan first")
  T.eq(src, "scan")
  price({ m = 100, a = 120, q = 5, t = time() - 13 * 3600 })
  local when
  v, src, when = ns:GetPrice(ID)
  T.eq(v, 500, "an old scan: AHledger's median")
  T.eq(src, "AHledger")
  T.eq(when, time() - 600, "with when AHledger saw it")
  _G.TSM_API = { GetCustomPriceValue = function() return 700 end }
  live.snapshot = true
  v, src = ns:GetPrice(ID)
  T.eq(src, "TSM", "AHledger's packaged copy only after the others")
  _G.TSM_API = nil
  v, src = ns:GetPrice(ID)
  T.eq(src, "AHledger", "packaged copy before an old scan of ours")
  live.snapshot = nil
  -- Sell speed: AHledger's estimate where our own scans can't say yet.
  ns:ForgetSellSpeeds()
  local sp = ns:SellSpeed(ID)
  T.ok(sp and sp.from == "AHledger", "speed from AHledger")
  T.eq(sp and sp.perDay, 30)
  T.ok(ns:SellSpeedText(sp):find("AHledger", 1, true), "named in the text")
  live.soldPerDay = 0
  ns:ForgetSellSpeeds()
  T.eq(ns:SellSpeed(ID), nil, "none sold isn't judged from it")
  live.soldPerDay, live.snapshot = 30, true
  ns:ForgetSellSpeeds()
  T.ok(ns:SellSpeed(ID), "a packaged copy under a week old: its speed")
  live.updated = time() - 8 * 86400
  ns:ForgetSellSpeeds()
  T.eq(ns:SellSpeed(ID), nil, "over a week old: not used")
  live.snapshot, live.updated = nil, time() - 600
  -- Never copied by PullExternal.
  local key = ns.MarketKey()
  ns.db.prices[key] = {}
  local oldWatch = ns.WatchList
  ns.WatchList = function() return { ID } end
  ns:PullExternal()
  T.eq(ns.db.prices[key][ID], nil, "AHledger's price isn't saved")
  ns.WatchList = oldWatch
  _G.AHledgerAPI = nil
  ns:ForgetSellSpeeds()
  s.source, s.maxAgeHours = oldSrc, oldAge
end)

T.test("AHledger prices: values worked out from them are counted for its credit, from the cache too", function()
  -- (Codex review, November 17: Worth to you from an AHledger price showed no credit.)
  local ID2 = 990201
  local oldAPI = rawget(_G, "AHledgerAPI")
  _G.AHledgerAPI = { GetPrice = function(id) if id == ID2 then return { median = 400, updated = time() - 60 } end end }
  local s = ns.db.settings
  local oldSrc = s.source
  s.source = "auto"
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][ID2] = nil
  ns:InvalidateValues(true)
  local ok, err = pcall(function()
    local before = ns.AHledgerUses()
    ns:GetValue(ID2)
    T.ok(ns.AHledgerUses() > before, "worked out with an AHledger price")
    before = ns.AHledgerUses()
    ns:GetValue(ID2)
    T.ok(ns.AHledgerUses() > before, "the cached value still counts")
    _G.AHledgerAPI = nil
    ns:InvalidateValues(true)
    before = ns.AHledgerUses()
    ns:GetValue(ID2)
    T.eq(ns.AHledgerUses(), before, "without AHledger: nothing to credit")
  end)
  _G.AHledgerAPI, s.source = oldAPI, oldSrc
  ns:InvalidateValues(true)
  if not ok then error(err, 0) end
end)

-- Frank's /fl perf, November 21: 63,334 item answers in 39 seconds.
T.test("Item details: one ask per item until the game answers; an item it doesn't have isn't asked again", function()
  local S = T.S
  local ID, GONE = 97901, 97902
  S.items[ID], S.items[GONE] = nil, nil
  T.eq(ns.GetItemInfo(ID), nil, "not loaded yet")
  S.items[ID] = { name = "Late Arrival" }
  T.eq(ns.GetItemInfo(ID), nil, "no second ask before the answer")
  T.fire("GET_ITEM_INFO_RECEIVED", ID, true)
  T.eq(ns.GetItemInfo(ID), "Late Arrival", "asked again once it arrived")
  T.eq(ns.GetItemInfo(GONE), nil)
  T.fire("GET_ITEM_INFO_RECEIVED", GONE, false)
  S.items[GONE] = { name = "Never" }
  T.eq(ns.GetItemInfo(GONE), nil, "the game said it has no such item: not asked again this session")
  -- (Codex review, November 21: a later answer that it does exist counts.)
  T.fire("GET_ITEM_INFO_RECEIVED", GONE, true)
  T.eq(ns.GetItemInfo(GONE), "Never", "a later yes clears the no")
  S.items[ID], S.items[GONE] = nil, nil
end)

-- Codex review, November 21: a recipe's output with a saved vendor price was listed as a
-- flip before its details arrived; when they came (bind on pickup), nothing told the
-- Recipes tab's kept list. An answer for an item asked about without success counts as a
-- change to its values; one nobody was waiting for doesn't.
T.test("Item details: an awaited answer changes the item's values, an unasked one doesn't", function()
  local S = T.S
  local ID, OTHER = 97903, 97904
  S.items[ID] = nil
  T.eq(ns.GetItemInfo(ID), nil, "not loaded yet")
  S.items[ID] = { name = "Bound Robe" }
  local before = ns.ValuesChanges()
  T.fire("GET_ITEM_INFO_RECEIVED", ID, true)
  T.ok(ns.ValuesChanges() > before, "the awaited item's values changed")
  before = ns.ValuesChanges()
  T.fire("GET_ITEM_INFO_RECEIVED", OTHER, true)
  T.eq(ns.ValuesChanges(), before, "nobody was waiting for this one")
  S.items[ID] = nil
end)

-- Frank's nineteenth /fl perf, November 22: each vendor visit threw every value away (all
-- worked out again 30 seconds later). Only a new or changed price changes values now.
T.test("A vendor visit changes values only for a new or changed price", function()
  local S = T.S
  local ID = 97910
  local real = { GetMerchantNumItems, GetMerchantItemInfo, C_MerchantFrame }
  local price = 50
  local ok, err = pcall(function()
    C_MerchantFrame = nil
    GetMerchantNumItems = function() return 1 end
    GetMerchantItemInfo = function() return "Test Thread", nil, price, 1, -1, nil, nil, false end
    S.merchant[1] = ID
    local before = ns.ValuesChanges()
    T.fire("MERCHANT_SHOW"); T.runTimers()
    T.eq(ns.db.vendorBuy[ID] and ns.db.vendorBuy[ID].p, 50)
    T.ok(ns.ValuesChanges() > before, "a new price")
    before = ns.ValuesChanges()
    T.fire("MERCHANT_SHOW"); T.runTimers()
    T.eq(ns.ValuesChanges(), before, "the same price again: no values change")
    price = 60
    T.fire("MERCHANT_SHOW"); T.runTimers()
    T.ok(ns.ValuesChanges() > before, "a changed price")
  end)
  GetMerchantNumItems, GetMerchantItemInfo, C_MerchantFrame = real[1], real[2], real[3]
  S.merchant[1] = nil
  ns.db.vendorBuy[ID] = nil
  T.runTimers()
  assert(ok, err)
end)

-- /fl perf detail: work timed by kind, only while switched on.
T.test("Timing by kind of work: only while switched on", function()
  local ID = 97911
  T.S.items[ID] = { name = "Detail Robe", sell = 500 }
  ns:InvalidateValues(true)
  ns.perfDetailOn, ns.perfDetail = false, {}
  ns:Options(ID)
  T.eq(next(ns.perfDetail), nil, "off: nothing timed")
  ns:InvalidateValues(true)
  ns.perfDetailOn = true
  local ok, err = pcall(ns.Options, ns, ID)
  ns.perfDetailOn = false
  assert(ok, err)
  local p = ns.perfDetail["Values: an item's ways to sell worked out"]
  T.ok(p and p.n == 1, "the outermost item once")
  T.ok(#ns.DetailLines() >= 1)
  ns.perfDetail = {}
  T.S.items[ID] = nil
end)

-- Frank's twenty-first /fl perf, November 22: a 259 ms freeze in which 902 item details
-- arrived, all asked for at once by Gold making's list. Items the game hasn't loaded are
-- asked for 20 a frame now; until then they read as not loaded, as before.
T.test("Item details: items not loaded are asked for a few each frame", function()
  local S = T.S
  local realC = C_Item
  local sent = {}
  local ok, err = pcall(function()
    C_Item = {
      IsItemDataCachedByID = function(id) return id < 97950 end,
      RequestLoadItemDataByID = function(id) sent[#sent + 1] = id end,
    }
    S.items[97940] = { name = "Loaded Thing" }
    T.eq(ns.GetItemInfo(97940), "Loaded Thing", "a loaded item reads at once")
    for id = 97951, 98000 do S.items[id] = { name = "Late " .. id } end
    for id = 97951, 98000 do T.eq(ns.GetItemInfo(id), nil) end
    T.eq(#sent, 0, "nothing asked for while reading")
    T.eq(ns._itemRequestsTest.send(), true); T.eq(#sent, 20, "20 the first frame")
    T.eq(ns._itemRequestsTest.send(), true); T.eq(#sent, 40)
    T.eq(ns._itemRequestsTest.send(), false); T.eq(#sent, 50, "the rest, then done")
    T.eq(ns.GetItemInfo(97951), nil, "still waiting for its answer: not asked again")
    T.eq(ns._itemRequestsTest.send(), false); T.eq(#sent, 50)
    T.fire("GET_ITEM_INFO_RECEIVED", 97951, true)
    T.eq(ns.GetItemInfo(97951), "Late 97951", "read once its answer came")
  end)
  C_Item = realC
  for id = 97940, 98000 do S.items[id] = nil end
  assert(ok, err)
end)

-- /fl perf detail counts every full clearing of values and who asked (Frank's twenty-first
-- /fl perf: values kept 15 minutes were still all worked out again within 3).
T.test("Timing by kind of work: full clearings of values are counted, with who asked", function()
  ns.perfDetailOn, ns.perfDetail = true, {}
  local ok, err = pcall(function() ns:InvalidateValues(true) end)
  ns.perfDetailOn = false
  assert(ok, err)
  local found
  for label, p in pairs(ns.perfDetail) do
    if label:find("Values: all thrown away at once, asked by", 1, true) then found = p.n end
  end
  T.eq(found, 1)
  local line = ns.DetailLines()[1]
  T.ok(line and not line:find("ms total", 1, true), "a count prints as a count: " .. tostring(line))
  ns.perfDetail = {}
end)

-- Codex review, November 22: with no way to ask the game for an item, one it says isn't
-- loaded is read directly, as before.
T.test("Item details: read directly when the game can't be asked for them", function()
  local S = T.S
  local realC = C_Item
  local ok, err = pcall(function()
    C_Item = { IsItemDataCachedByID = function() return false end }
    S.items[98990] = { name = "Direct Read" }   -- (outside the IDs the test above asked about)
    T.eq(ns.GetItemInfo(98990), "Direct Read")
  end)
  C_Item = realC
  S.items[98990] = nil
  assert(ok, err)
end)
