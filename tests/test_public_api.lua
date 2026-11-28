-- ForeverLedgerAPI's later functions (vendor prices, sell speed, gear versions, the update
-- notice) and Forever Ledger as a price source in CraftProfit (CraftProfitSource.lua).
local T = ...
local ns, S = T.ns, T.S
local api = ForeverLedgerAPI
local LEATHER, BRITCHES, GONE, COPIED = 2319, 9747, 4304, 8170
local LINK = "|cff1eff00|Hitem:9747::::::::20:1482::1:1:12719:1:28:7000|h[Simple Britches of the Whale]|h|r"

local function prices()
  T.resetDB()
  ns.db.prices[ns.MarketKey()] = {
    [LEATHER] = { m = 40, a = 52, q = 30, l = "40:5,45:12,60:30", t = S.now - 600, src = "full" },
    [BRITCHES] = { m = 250, a = 250, q = 3, sx = "12719:300:2;12734:1800:1", t = S.now - 60, src = "full" },
    [GONE] = { t = S.now - 300, src = "full", none = true },
    [COPIED] = { m = 70, a = 70, t = S.now, src = "Auctionator" },
  }
end

-- Runs fn with ns[name] swapped for a stand-in, then puts the real one back.
local function with(name, stand, fn)
  local real = ns[name]
  ns[name] = stand
  local ok, err = pcall(fn)
  ns[name] = real
  assert(ok, err)
end

T.test("API: vendor prices, what a vendor pays and what one costs there", function()
  prices()
  ns.db.vendorSell[LEATHER] = 15
  ns.db.vendorBuy[LEATHER] = { p = 50, n = 1, t = 1, src = "merchant" }
  local sell, buy = api.GetVendorPrice(LEATHER)
  T.eq(sell, 15, "a vendor pays")
  T.eq(buy, 50, "a vendor charges")
  sell, buy = api.GetVendorPrice(GONE)
  T.eq(buy, nil, "not sold by a vendor")
  T.eq(api.GetVendorPrice("2319"), nil, "an ID that isn't a number")
end)

T.test("API: sold a day from our own scans, never AHledger's estimate", function()
  prices()
  with("SellSpeed", function(_, id)
    if id == LEATHER then return { perDay = 12, listed = 30, hours = 48 } end
    if id == GONE then return { perDay = 5, listed = 2, hours = 0, from = "AHledger" } end
  end, function()
    local perDay, listed, hours = api.GetSoldPerDay(LEATHER)
    T.eq(perDay, 12, "per day")
    T.eq(listed, 30, "listed")
    T.eq(hours, 48, "hours of scans")
    T.eq(api.GetSoldPerDay(GONE), nil, "AHledger's estimate isn't passed on")
    T.eq(api.GetSoldPerDay(BRITCHES), nil, "not enough scans yet")
  end)
end)

T.test("API: a gear version's price by item and version, or by its link", function()
  prices()
  local cheapest, listed, seen = api.GetVersionPrice(BRITCHES, 12719)
  T.eq(cheapest, 300, "cheapest")
  T.eq(listed, 2, "listed")
  T.eq(seen, S.now - 60, "seen")
  T.eq((api.GetVersionPrice(LINK)), 300, "from a link")
  cheapest, listed = api.GetVersionPrice(BRITCHES, 12735)
  T.eq(cheapest, nil, "a version none are listed of")
  T.eq(listed, 0, "none listed")
  T.eq(api.GetVersionPrice(BRITCHES), nil, "no version given")
  T.eq(api.GetVersionPrice(COPIED, 12719), nil, "not our own scan")
end)

T.test("API: listeners hear once after saving stops, an error in one doesn't stop the others", function()
  prices()
  wipe(S.errors)
  local heard = 0
  api.RegisterForUpdate("Test1", function() error("listener broke") end)
  api.RegisterForUpdate("Test2", function() heard = heard + 1 end)
  local ok, err = pcall(function()
    ns.PricesChanged(); ns.PricesChanged(); ns.PricesChanged()
    T.runTimers()
    T.eq(heard, 1, "once for three saves")
    T.eq(#S.errors, 1, "the broken listener's error went to the error handler")
    ns.PricesChanged()
    T.runTimers()
    T.eq(heard, 2, "again after the next save")
    api.UnregisterForUpdate("Test2")
    ns.PricesChanged()
    T.runTimers()
    T.eq(heard, 2, "not after unregistering")
    T.eq(api.RegisterForUpdate("Test3"), false, "a listener needs a function")
  end)
  api.UnregisterForUpdate("Test1")
  api.UnregisterForUpdate("Test2")
  wipe(S.errors)
  assert(ok, err)
end)

-- A stand-in for CraftProfit's list of price sources.
local function fakeCraftProfit()
  local fired = {}
  local sources = { list = {}, byKey = {} }
  function sources:Register(def)
    if self.byKey[def.key] then return end
    self.byKey[def.key] = def
    table.insert(self.list, def)
  end
  CraftProfit = { settings = { saleBasis = "min" }, Sources = sources,
    Fire = function(_, event, key) fired[#fired + 1] = event .. ":" .. key end }
  return sources, fired
end

T.test("CraftProfit: Forever Ledger is added to its price sources, with our own scans", function()
  prices()
  local sources, fired = fakeCraftProfit()
  local ok, err = pcall(function()
    T.ok(ns:AddCraftProfitSource(), "added")
    local def = sources.byKey.foreverledger
    T.ok(def, "in the list")
    T.eq(def.name, "Forever Ledger")
    T.ok(def:IsAvailable(), "available")
    T.ok(def:HasData(), "has prices")
    T.eq(def:GetCostPrice(LEATHER), 40, "cost: the cheapest")
    T.eq(def:GetSalePrice(LEATHER), 40, "sale: the cheapest, as CraftProfit's min setting")
    T.eq(def:GetAge(LEATHER), 600, "age in seconds")
    T.eq(def:GetCostPrice(COPIED), nil, "never another addon's price")
    T.eq(def:GetCostPrice(GONE), nil, "none listed: no cost")
    with("UsualPrice", function(_, id) if id == LEATHER or id == GONE then return 55, 7 end end, function()
      T.eq(def:GetSalePrice(GONE), 55, "none listed: the usual price")
      CraftProfit.settings.saleBasis = "market"
      T.eq(def:GetSalePrice(LEATHER), 55, "CraftProfit's market setting: the usual price")
    end)
    ns.PricesChanged()
    T.runTimers()
    T.same(fired, { "PRICES_UPDATED:foreverledger" }, "CraftProfit hears about new prices")
    ns.db.settings.shareCraftProfit = false
    T.ok(not def:IsAvailable(), "turned off in Settings")
    T.eq(def:GetCostPrice(LEATHER), nil, "and gives no prices")
    T.ok(ns:CraftProfitSourceState():find("turned off", 1, true), "/fl api says so")
    ns.db.settings.shareCraftProfit = true
    T.ok(ns:AddCraftProfitSource(), "adding again is harmless")
    T.eq(#sources.list, 1, "listed once")
  end)
  api.UnregisterForUpdate("CraftProfit")
  CraftProfit = nil
  assert(ok, err)
end)

T.test("CraftProfit: an error of ours doesn't reach CraftProfit", function()
  prices()
  local sources = fakeCraftProfit()
  local ok, err = pcall(function()
    ns:AddCraftProfitSource()
    local def = sources.byKey.foreverledger
    with("MarketKey", function() error("broken") end, function()
      T.eq(def:GetCostPrice(LEATHER), nil, "nothing, no error")
      T.eq(def:HasData(), nil, "nothing, no error")
    end)
  end)
  api.UnregisterForUpdate("CraftProfit")
  CraftProfit = nil
  assert(ok, err)
end)
