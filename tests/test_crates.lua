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

T.test("Crates: a bundle's item found by its words in another language", function()
  local names = { [990311] = "Льняная ткань", [990312] = "Медный слиток", [990313] = "Медная руда",
    [990314] = "Горсть медных болтов", [990315] = "Мироцвет", [990316] = "Тонкая кожа", [990317] = "Кожа",
    [990318] = "Ёлочная игрушка", [990319] = "Пучок", [990320] = "Странная пыль" }
  for id, n in pairs(names) do ns.db.itemNames[id] = n end
  local ok, err = pcall(function()
    ns.CrateNamesReset()
    T.eq(ns.CrateIdForName("кусков льняной ткани"), 990311, "a counting word and other endings")
    T.eq(ns.CrateIdForName("медных слитков"), 990312, "not the ore with the same first word")
    T.eq(ns.CrateIdForName("кусков медной руды"), 990313)
    T.eq(ns.CrateIdForName("горстей медных болтов"), 990314, "the counting word in the item's own name")
    T.eq(ns.CrateIdForName("кусков тонкой кожи"), 990316, "the name with more words wins")
    T.eq(ns.CrateIdForName("елочных игрушек"), 990318, "е and ё alike")
    T.eq(ns.CrateIdForName("пучков мироцвета"), nil, "two one-word names: none rather than a guess")
    T.eq(ns.CrateIdForName("порций странной пыли"), 990320)
    T.eq(ns.CrateIdForName("кусков шёлка"), nil, "nothing like it")
  end)
  for id in pairs(names) do ns.db.itemNames[id] = nil end
  ns.CrateNamesReset()
  if not ok then error(err, 0) end
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
