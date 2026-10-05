-- The auction house cut (settings.ahCut, percent): Values.lua ns:AHCut and what a
-- looted item is worth (Sessions.lua ns:LootValue: the better of the auction house
-- after the cut and a vendor).
local T = ...
local ns = T.ns
local ID = 2589

local function setup(ahPrice, vendor)
  ns.db.settings.source, ns.db.settings.ahCut, ns.db.settings.sessionValue = "own", 5, "best"
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

T.test("LootValue: vendor only when set to", function()
  setup(1000, 300)
  ns.db.settings.sessionValue = "vendor"
  T.eq(ns:LootValue(ID), 300)
end)
