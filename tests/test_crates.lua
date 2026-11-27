-- Crates.lua: crates found by item number and their bundles read from the tooltip in any
-- language (a German player's Crates tab was empty, CurseForge, November 18).
local T = ...
local ns = T.ns

T.test("Crates: every Waylaid Crate is known by item number", function()
  local n = 0
  for _ in pairs(ns.CRATE_IDS) do n = n + 1 end
  T.eq(n, 30)
  T.ok(ns.CRATE_IDS[248682] and ns.CRATE_IDS[248713])
  T.ok(not ns.CRATE_IDS[248700] and not ns.CRATE_IDS[248701])
end)

T.test("Crates: English tooltip, only the lines after any bundle", function()
  local b = ns.CrateBundlesFromLines({ "Waylaid Crate: Expert Ingots", "- 1 thing in the flavor text",
    "Fill it with any bundle below:\n- 10 Copper Bar and 5 Tin Bar\n- 20 Strange Dust" })
  T.eq(#b, 2)
  T.eq(#b[1], 2); T.eq(b[1][1].qty, 10); T.eq(b[1][1].name, "Copper Bar")
  T.eq(b[1][2].qty, 5); T.eq(b[1][2].name, "Tin Bar")
  T.eq(b[2][1].name, "Strange Dust"); T.eq(b[2][1].qty, 20)
end)

T.test("Crates: another language, every dash line with a number", function()
  local b = ns.CrateBundlesFromLines({ "Verirrte Kiste: Experteneisen",
    "Füllt sie mit einem dieser Bündel:", "- 10 Kupferbarren und 5 Zinnbarren", "- 8x Runenstoffballen", "- 4 Eisenbarren, 2 Goldbarren" })
  T.eq(#b, 3)
  T.eq(b[1][1].name, "Kupferbarren"); T.eq(b[1][2].name, "Zinnbarren"); T.eq(b[1][2].qty, 5)
  T.eq(b[2][1].name, "Runenstoffballen"); T.eq(b[2][1].qty, 8)
  T.eq(b[3][1].name, "Eisenbarren"); T.eq(b[3][2].name, "Goldbarren"); T.eq(b[3][2].qty, 2)
end)

T.test("Crates: the filled crate is known by item number, each quality", function()
  T.ok(ns.SEALED_CRATE_IDS[248765] and ns.SEALED_CRATE_IDS[248770] and ns.SEALED_CRATE_IDS[248775])
  T.ok(not ns.SEALED_CRATE_IDS[248682], "an empty crate isn't a filled one")
end)

T.test("Crates: a bundle's item found by name without loading every priced item", function()
  -- (Frank's AN30, November 19: 6,304 item loads in 14 seconds and a 650 ms freeze on a
  -- crate hover, from looking up every priced item's name.)
  local market = ns.MarketKey()
  ns.db.prices[market] = ns.db.prices[market] or {}
  local prices = ns.db.prices[market]
  prices[990301], prices[990302] = { m = 10 }, { m = 20 }
  ns.db.itemNames[990303] = "Saved Name Bar"
  local realInfo, realItem = ns.GetItemInfo, C_Item
  local asked = {}
  ns.GetItemInfo = function(id) asked[id] = true; if id == 990301 then return "Loaded Bar" end end
  C_Item = { IsItemDataCachedByID = function(id) return id == 990301 end }
  local ok, err = pcall(function()
    ns.CrateNamesReset()
    T.eq(ns.CrateIdForName("Loaded Bar"), 990301, "an item the game has loaded")
    T.eq(ns.CrateIdForName("Saved Name Bar"), 990303, "a saved name")
    T.ok(not asked[990302], "an item the game hasn't loaded isn't asked for")
    T.eq(ns.CrateIdForName("Nobody Bar"), nil)
  end)
  ns.GetItemInfo, C_Item = realInfo, realItem
  prices[990301], prices[990302], ns.db.itemNames[990303] = nil, nil, nil
  ns.CrateNamesReset()
  if not ok then error(err, 0) end
end)

T.test("Crates: every crate's items are known by item number, one item per bundle", function()
  for id in pairs(ns.CRATE_IDS) do
    local list = ns.CRATE_BUNDLES[id]
    T.ok(list and #list >= 4 and #list % 2 == 0, "crate " .. id)
  end
  -- The three the tooltip's last-line color code had hidden.
  T.ok(ns.CrateTakesItem(2450) and ns.CrateTakesItem(2771) and ns.CrateTakesItem(11084))
  T.eq(ns.CrateTakesItem(990399), false)
end)

T.test("Crates: a crate read in another language uses the item numbers (issue #48)", function()
  local saved = ns.db.crates[248683]
  ns.db.crates[248683] = { name = "Caja extraviada: mineral de aprendiz",
    bundles = { { { qty = 20, name = "de mineral de cobre" } }, { { qty = 20, name = "de mineral de esta\195\177o" } } } }
  local ok, err = pcall(function()
    local r = ns:CrateReport(248683)
    T.eq(#r.bundles, 2)
    T.eq(r.bundles[1].parts[1].id, 2770); T.eq(r.bundles[1].parts[1].qty, 20)
    T.eq(r.bundles[2].parts[1].id, 2771)
  end)
  ns.db.crates[248683] = saved
  if not ok then error(err, 0) end
end)

T.test("Crates: a tooltip line's color code isn't part of the item name", function()
  local b = ns.CrateBundlesFromLines({ "Fill it with any bundle below:\n- 20 Copper Ore\n|cffffffff- 20 Tin Ore|r" })
  T.eq(#b, 2); T.eq(b[2][1].name, "Tin Ore")
end)

T.test("Crates: Favor by level and kind, learned from a turn-in", function()
  T.eq(ns.CrateQuality(248682), 1); T.eq(ns.CrateQuality(248713), 2)
  T.eq(ns.CrateSealedFor(248682), 248765, "Apprentice Herbs: white Sealed Apprentice Crate")
  T.eq(ns.CrateSealedFor(248702), 248770, "Apprentice Fabrics: green Sealed Apprentice Crate")
  T.eq(ns.CrateSealedFor(248713), 248773, "Artisan Parts: green Sealed Artisan Crate")
  T.ok(ns.SEALED_CRATE_IDS[248768] and ns.SEALED_CRATE_IDS[248779])
  local seen = ns.db.crateFavorSeen
  ns.db.crateFavorSeen = {}
  local ok, err = pcall(function()
    T.eq((ns.CrateFavor(248682)), 5); T.eq((ns.CrateFavor(248702)), 10)
    T.eq((ns.CrateFavor(248689)), 10, "Journeyman gathered"); T.eq((ns.CrateFavor(248709)), 30, "Expert crafted")
    T.eq((ns.CrateFavor(248699)), 20); T.eq((ns.CrateFavor(248713)), 40)
    ns.CrateLearnFavor(248770, nil, 100); ns.CrateLearnFavor(nil, 12, 102)
    T.eq((ns.CrateFavor(248702)), 12, "what the turn-in gave")
    T.eq(select(2, ns.CrateFavor(248702)), true)
    T.eq((ns.CrateFavor(248703)), 12, "same sealed crate, same Favor")
    T.eq((ns.CrateFavor(248705)), 20, "another sealed crate keeps its own")
    ns.CrateLearnFavor(248765, nil, 200); ns.CrateLearnFavor(nil, 7, 210)
    T.eq((ns.CrateFavor(248682)), 5, "too far apart to be the same turn-in")
  end)
  ns.db.crateFavorSeen = seen
  if not ok then error(err, 0) end
end)
