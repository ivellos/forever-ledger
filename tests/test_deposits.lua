local T = ...
local ns, S = T.ns, T.S
local ID = 99020
T.test("Deposit estimate duration, stacks, neutral and copper rounding", function()
  T.eq(ns:DepositEstimate(101, 1, 1, false), 15)
  T.eq(ns:DepositEstimate(101, 2, 1, false), 30)
  T.eq(ns:DepositEstimate(101, 3, 1, false), 60)
  T.eq(ns:DepositEstimate(101, 2, 20, false), 606)
  T.eq(ns:DepositEstimate(101, 2, 1, true), 151)
  T.eq(ns:DepositEstimate(0, 2, 1), 0)
  T.eq(ns:DepositEstimate(nil, 2, 1), nil)
  T.eq(ns:DepositEstimate(100, 4, 1), nil)
  T.eq(ns:DepositEstimate(100, 2, 0), nil)
  T.eq(ns:DepositEstimate(100, 2, 1.5), nil)
end)
T.test("Commodity and item quotes use their distinct arguments, fallback survives errors", function()
  local realAH, realOpen, realC, realLocation = C_AuctionHouse, ns.IsAHOpen, C_Container, ItemLocation
  local ok, err = pcall(function()
    ns.neutralAH = false; ns.db.vendorSell[ID] = 1000
    ns.IsAHOpen = function() return true end
    local commodity = true
    C_AuctionHouse = {
      GetItemKeyInfo = function(key) T.eq(key.itemID, ID); return { isCommodity = commodity } end,
      CalculateCommodityDeposit = function(id, duration, qty) T.eq(id, ID); T.eq(duration, 2); T.eq(qty, 20); return 4321 end,
      CalculateItemDeposit = function(location, duration, qty) T.eq(location.bag, 0); T.eq(location.slot, 1); T.eq(duration, 2); T.eq(qty, 1); return 777 end,
    }
    C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
      GetContainerItemInfo = function() return { itemID = ID } end }
    ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    T.fire("BAG_UPDATE_DELAYED")
    local amount, source = ns:AuctionDeposit(ID, 20); T.eq(amount, 4321); T.eq(source, "commodity API")
    commodity = false; amount, source = ns:AuctionDeposit(ID); T.eq(amount, 777); T.eq(source, "item API")
    -- A faction quote is never used for a hypothetical Booty Bay sale.
    amount, source = ns:AuctionDeposit(ID, 1, 2, true); T.eq(amount, 1500); T.eq(source, "Classic estimate")
    C_AuctionHouse.CalculateItemDeposit = function() error("unsupported") end
    amount, source = ns:AuctionDeposit(ID); T.eq(amount, 300); T.eq(source, "Classic estimate")
    C_AuctionHouse.CalculateItemDeposit = function() return 0 end
    amount, source = ns:AuctionDeposit(ID); T.eq(amount, 0); T.eq(source, "item API")
    C_AuctionHouse.CalculateItemDeposit = function() return -1 end
    T.eq((ns:AuctionDeposit(ID)), 300)
    C_AuctionHouse.CalculateItemDeposit = function() return 0/0 end
    T.eq((ns:AuctionDeposit(ID)), 300)
    C_Container.GetContainerNumSlots = function() return 0 end; T.fire("BAG_UPDATE_DELAYED")
    amount, source = ns:AuctionDeposit(ID); T.eq(amount, 300); T.eq(source, "Classic estimate")
    ns.IsAHOpen = function() return false end
    T.eq((ns:AuctionDeposit(ID)), 300)
  end)
  C_AuctionHouse, ns.IsAHOpen, C_Container, ItemLocation = realAH, realOpen, realC, realLocation
  ns.neutralAH = nil; T.fire("BAG_UPDATE_DELAYED"); T.runTimers(); assert(ok, err)
end)
T.test("One failed deposit can select vendor instead, without changing vendor proceeds", function()
  ns.db.settings.ahCut = 5; ns.db.vendorSell[ID] = 100
  ns.db.prices[ns.MarketKey()] = { [ID] = { m = 120, a = 120, q = 20, t = S.now } }
  ns:InvalidateValues(true)
  local value, opts = ns:GetValue(ID)
  T.eq(value, 100); T.eq(opts[1].kind, "vendor"); T.ok(opts[1].label:find("Vendor it instead", 1, true))
  T.eq(opts[2].value, 84); T.eq(opts[2].deposit, 30)
  T.eq(ns:AfterCut(120), 114, "successful-sale proceeds still refund the deposit")
end)
T.test("Deposit reserve propagates through crafts and lowers buying caps and profit", function()
  local OUT = 99021; local me = ns.CharKey()
  ns.db.vendorSell[OUT] = 100
  ns.db.prices[ns.MarketKey()] = { [ID] = { m = 10, a = 10, q = 50, t = S.now }, [OUT] = { m = 1000, a = 1000, q = 50, t = S.now } }
  ns.db.chars = { [me] = { name = "Tester", realm = "Testrealm", faction = "Alliance", profs = {
    Tailoring = { rank = 300, recipes = { [1] = { n = "Deposit craft", out = OUT, oq = 2, r = { { ID, 2 } } } } }
  } } }
  ns:BuildUsageIndex(); ns:InvalidateValues(true)
  local o = ns:BestOption(ID); T.eq(o.kind, "craft"); T.eq(o.value, 920)
  local cap = ns:BuyAtOrBelow(ID); T.eq(cap, 828)
  local vendor, ah = ns:FindShuffles()
  local found
  for _, list in ipairs({ vendor, ah }) do for _, s in ipairs(list) do if s.id == ID and s.opt.kind == "craft" then found = s end end end
  T.ok(found); T.eq(found.profit, 1820); T.eq(found.maxBuy, 828); T.ok(found.perHour > 0); T.eq(found.deposit, 60)
end)
T.test("Neutral sale losses guard percentages and reserve the destination deposit", function()
  ns.db.vendorSell[ID] = 100
  ns.db.prices["Testrealm|Alliance"] = { [ID] = { m = 120, q = 10 } }
  ns.db.prices["Testrealm|Neutral"] = { [ID] = { m = 300, q = 10 } }
  local c = ns:NeutralCompare(ID); T.eq(c.netHere, 84); T.eq(c.netThere, 105)
  T.eq(c.depositHere, 30); T.eq(c.depositThere, 150); T.eq(c.gain, 21)
  ns.db.prices["Testrealm|Alliance"][ID].m = 1
  c = ns:NeutralCompare(ID); T.eq(c.pct, 0); T.eq(c.netHere, -29)
end)

T.test("Route reserves scale through conversion and mixed disenchant outputs", function()
  local sale = { kind = "ah", deposit = 30 }
  T.eq(ns:OptionDeposit({ kind = "convert", per = 3, next = sale }), 90)
  T.eq(ns:OptionDeposit({ kind = "disenchant", mats = {
    { count = 1.875, opt = sale }, { count = 0.3, opt = { kind = "vendor" } }
  } }), 56.25)
end)
T.test("Resale deals cannot spend a profit eaten by the deposit", function()
  local realUsual, realStats = ns.DealUsualPrice, ns.PriceStats
  local ok, err = pcall(function()
    ns.DealUsualPrice = function() return 1000, "TSM" end
    ns.PriceStats = function() return nil end
    ns.db.settings.dealUsualMin = 0; ns.db.settings.dealUsualPct = 20
    ns.db.vendorSell[ID] = 1000
    ns.db.prices[ns.MarketKey()] = { [ID] = { m = 700, a = 700, q = 2, l = "700:2", t = S.now } }
    T.fire("AUCTION_HOUSE_CLOSED")
    local usual
    for _, d in ipairs(ns:FindDeals()) do if d.id == ID and d.kind == "usual" then usual = d end end
    T.eq(usual, nil, "950c less 300c reserve cannot justify buying at 700c")
    ns.db.prices[ns.MarketKey()][ID].m = 600; ns.db.prices[ns.MarketKey()][ID].l = "600:2"
    for _, d in ipairs(ns:FindDeals()) do if d.id == ID and d.kind == "usual" then usual = d end end
    T.ok(usual); T.eq(usual.each, 50); T.eq(usual.deposit, 300); T.eq(usual.limit, 650)
  end)
  ns.DealUsualPrice, ns.PriceStats = realUsual, realStats; assert(ok, err)
end)
