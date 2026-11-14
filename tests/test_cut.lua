-- The auction house cut (settings.ahCut, percent): Values.lua ns:AHCut and what a
-- looted item is worth (Values.lua ns:LootValue: the better of the auction house
-- after the cut and a vendor; dungeon runs rank drops by it).
local T = ...
local ns = T.ns
local ID = 2589

local function setup(ahPrice, vendor)
  ns.db.settings.source, ns.db.settings.ahCut = "own", 5
  ns.db.prices[ns.MarketKey()] = ahPrice and { [ID] = { m = ahPrice, t = T.S.now } } or {}
  ns.db.vendorSell[ID] = vendor
end

T.test("AHCut follows the setting", function()
  T.eq(ns:AHCut(), 0.05, "5% by default")
  ns.db.settings.ahCut = 15
  T.eq(ns:AHCut(), 0.15)
  ns.db.settings.ahCut = 0
  T.eq(ns:AHCut(), 0)
  ns.db.settings.ahCut = nil
  T.eq(ns:AHCut(), 0.05, "missing setting: 5%")
end)

T.test("A neutral auction house takes 15%, whatever the setting", function()
  ns.db.settings.ahCut = 5
  ns.neutralAH = true
  T.eq(ns:AHCut(), 0.15, "at a neutral one")
  ns.neutralAH = nil
  T.eq(ns:AHCut(), 0.05, "back at your faction's")
  T.eq(ns:AHCut(true), 0.15, "asked about a neutral one")
  T.eq(ns:AfterCut(433, true), 369, "Booty Bay mail: 4s 33c, cut 64c, received 369c")
end)

-- Gold audit G8, November 9: Sell protection rounded the cut per item.
T.test("A whole sale's cut is rounded once, on the lot", function()
  ns.db.settings.ahCut = 5
  T.eq(ns:SaleAfterCut(19, 1), 19, "5% of 19c rounds to nothing")
  T.eq(ns:SaleAfterCut(19, 20), 361, "20 at 19c: a 19c cut, less than a vendor's 380c")
  T.eq(ns:SaleAfterCut(8, 10), 76, "the Empty Vial mail: 10 at 8c lost 4c")
  T.eq(ns:SaleAfterCut(19), 19, "no count: one")
  T.eq(ns:SaleAfterCut(433, 1, true), 369, "neutral: 15%")
end)

T.test("LootValue: the auction house after the cut", function()
  setup(1000, nil)
  T.eq(ns:LootValue(ID), 950)
  ns.db.settings.ahCut = 15
  T.eq(ns:LootValue(ID), 850)
end)

T.test("LootValue rounds the cut down to whole copper, as the game does", function()
  setup(999, nil)
  T.eq(ns:LootValue(ID), 950, "cut 999 * 0.05 = 49.95, taken as 49 (Booty Bay mail, October 5)")
end)

T.test("LootValue: a vendor when it pays more", function()
  setup(1000, 960)
  T.eq(ns:LootValue(ID), 960)
  setup(nil, 25)
  T.eq(ns:LootValue(ID), 25, "no auction price")
  setup(nil, nil)
  T.eq(ns:LootValue(ID), 0, "nothing known")
end)
