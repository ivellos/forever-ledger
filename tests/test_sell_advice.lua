-- Vendor or auction house? Step 1 (SellAdvice.lua): the sell suggestion in the tooltip of
-- an item you have (owner, November 11: "flag the items in the tooltip with a suggestion").
local T = ...
local ns, S = T.ns, T.S
local ME = ns.CharKey()
local ITEM, GRAY, GEAR = 96001, 96002, 96003
S.items[ITEM] = { name = "Test Wool", sell = 100 }
S.items[GRAY] = { name = "Test Bone", sell = 10, quality = 0 }
S.items[GEAR] = { name = "Test Gloves", sell = 50, quality = 2, ilvl = 20, equipLoc = "INVTYPE_HAND", classID = 4 }
local DUST = 10940

local V = ns.SellVerdict

T.test("Sell suggestion: keep wins over everything", function()
  local v = V({ keep = "you watch it", vendor = 100, ah = 500 })
  T.eq(v.kind, "keep"); T.eq(v.reason, "you watch it")
end)

T.test("Sell suggestion: vendor, auction house or the middle, by how much more and how fast it sells", function()
  T.eq(V({ vendor = 100, ah = 100 }).kind, "vendor", "the same: vendor")
  T.eq(V({ vendor = 100, ah = 90 }).reason, "a vendor pays as much or more")
  local ah = V({ vendor = 100, ah = 150, speed = "steady" })
  T.eq(ah.kind, "ah"); T.eq(ah.value, 150)
  local mid = V({ vendor = 100, ah = 110, speed = "fast" })
  T.eq(mid.kind, "middle"); T.eq(mid.reason, "auction house 10% more")
  T.eq(V({ vendor = 100, ah = 125 }).kind, "ah", "a quarter more, speed not known yet")
  -- Slow sellers need twice as much to say auction house.
  T.eq(V({ vendor = 100, ah = 150, speed = "slow" }).kind, "middle")
  T.eq(V({ vendor = 100, ah = 150, speed = "slow" }).reason, "auction house 50% more, but it sells slowly")
  T.eq(V({ vendor = 100, ah = 250, speed = "none" }).kind, "ah")
  local slowVendor = V({ vendor = 100, ah = 110, speed = "rare" })
  T.eq(slowVendor.kind, "vendor"); T.eq(slowVendor.value, 100)
  T.eq(slowVendor.reason, "auction house 10% more, and it sells slowly")
end)

T.test("Sell suggestion: no vendor price, no auction price", function()
  local v = V({ ah = 300 })
  T.eq(v.kind, "ah"); T.eq(v.reason, "vendors don't buy it")
  T.eq(V({ vendor = 10, quality = 0 }).kind, "vendor", "gray with no auction price: vendor")
  T.eq(V({ vendor = 10, quality = 1 }), nil, "anything else with no recent auction price: nothing said")
  T.eq(V({}), nil)
end)

T.test("Sell suggestion: soulbound items, and disenchanting as a suggestion", function()
  T.eq(V({ bound = true, gear = true, usable = true, quality = 2, vendor = 50 }), nil, "gear you can wear: your call")
  local v = V({ bound = true, gear = true, usable = false, quality = 2, vendor = 50 })
  T.eq(v.kind, "vendor"); T.eq(v.reason, "can't be sold on the auction house")
  T.eq(V({ bound = true, gear = true, usable = true, quality = 1, vendor = 50 }).kind, "vendor", "white gear you can wear: vendor")
  local de = V({ bound = true, gear = true, usable = false, quality = 2, vendor = 50, de = 120, deWho = "Iveilos" })
  T.eq(de.kind, "vendor", "vendor stays the verdict"); T.eq(de.de, 120); T.eq(de.deWho, "Iveilos")
  T.eq(V({ bound = true, vendor = 50, de = 40 }).de, nil, "not when disenchanting brings less")
  local only = V({ bound = true, de = 80 })
  T.eq(only.kind, "de", "no vendor price: just the disenchant suggestion"); T.eq(only.de, 80)
  T.eq(V({ vendor = 100, ah = 150, de = 200 }).de, 200, "beside an auction house verdict too")
  -- Frank, November 13: disenchanting is the main line when it's clearly better (25% more).
  T.eq(de.deFirst, true, "120 against a vendor's 50")
  T.eq(V({ vendor = 100, ah = 150, de = 187 }).deFirst, nil, "under 25% more than the auction house: selling first")
  T.eq(V({ vendor = 100, ah = 150, de = 188 }).deFirst, true)
  T.eq(only.deFirst, nil, "nothing else to suggest")
end)

T.test("Sell suggestion: the Disenchant line first when it's clearly better", function()
  local realChars = ns.db.chars
  ns.db.chars = {}
  ns:BuildUsageIndex()
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][ITEM] = { m = 1000, a = 1000, q = 50, t = S.now }
  ns.db.vendorSell[ITEM] = 100
  ns:InvalidateValues(true)
  S.bags[ITEM] = 1
  local realFacts = ns.SellFacts
  ns.SellFacts = function() return { vendor = 100, ah = 930, de = 2000, deWho = "Tester", usable = true } end
  local tip, added = {}, {}
  function tip:AddDoubleLine(l, r) added[#added + 1] = l .. " = " .. r end
  function tip:AddLine(l) added[#added + 1] = l end
  ns:AddSellLines(tip, ITEM, false, true)
  ns.SellFacts = realFacts
  T.eq(added[1], "Disenchant |cff999999(Tester)|r = about " .. ns.Money(2000))
  T.eq(added[2], "  or sell on the auction house |cff999999(after the cut and the deposit)|r = " .. ns.Money(930))
  T.eq(#added, 2)
  ns.db.prices[key][ITEM], ns.db.vendorSell[ITEM], S.bags[ITEM] = nil, nil, nil
  ns.db.chars = realChars
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
end)

T.test("Sell suggestion: why to keep it", function()
  local realChars = ns.db.chars
  ns.db.chars = { [ME] = { name = "Tester", realm = "Testrealm", faction = "Alliance",
    profs = { Tailoring = { rank = 100, recipes = { [1] = { n = "Bolt", out = 96010, oq = 1, r = { { ITEM, 2 } } } } } } } }
  ns:BuildUsageIndex()
  T.eq(ns:SellKeepReason(ITEM), "Tester's Tailoring uses it")
  ns:WatchItem(ITEM, 200)
  T.eq(ns:SellKeepReason(ITEM), "you watch it", "watched first")
  ns:UnwatchItem(ITEM)
  local realShopping = ns.db.shopping
  ns.db.shopping = { lists = { { name = "Raid", items = { { id = ITEM, qty = 5 } } } } }
  T.eq(ns:SellKeepReason(ITEM), "it's on your list Raid")
  ns.db.shopping.lists[1].items[1].done = true
  T.eq(ns:SellKeepReason(ITEM), "Tester's Tailoring uses it", "a list item already bought doesn't count")
  ns.db.shopping = realShopping
  ns.db.chars = {}
  ns:BuildUsageIndex()
  T.eq(ns:SellKeepReason(ITEM), nil)
  ns.db.chars = realChars
  ns:BuildUsageIndex()
  T.runTimers()
end)

-- A tooltip with the game's lines: { { text, r, g, b }, ... } from line 2 on.
local function fakeTip(lines)
  local name = "FLSellTestTip"
  for i = 1, 10 do _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i] = nil, nil end
  for i, l in ipairs(lines) do
    _G[name .. "TextLeft" .. (i + 1)] = { GetText = function() return l[1] end,
      GetTextColor = function() return l[2] or 1, l[3] or 1, l[4] or 1 end }
  end
  local added = {}
  return {
    GetName = function() return name end,
    NumLines = function() return #lines + 1 end,
    AddLine = function(_, text) added[#added + 1] = text end,
    AddDoubleLine = function(_, left, right) added[#added + 1] = left .. " = " .. right end,
  }, added
end

T.test("Sell suggestion: bound and usable from the game's tooltip lines", function()
  ITEM_SOULBOUND = ITEM_SOULBOUND or "Soulbound"
  local tip = fakeTip({ { ITEM_SOULBOUND }, { "Requires Level 60", 1, 0.13, 0.13 } })
  local bound, usable = ns.SellTooltipFlags(tip)
  T.eq(bound, true); T.eq(usable, false)
  tip = fakeTip({ { "Binds when equipped" }, { "Durability 20 / 20" } })
  bound, usable = ns.SellTooltipFlags(tip)
  T.eq(bound, false); T.eq(usable, true)
end)

T.test("Sell suggestion: the tooltip line, only for an item you have", function()
  local realChars = ns.db.chars
  ns.db.chars = {}
  ns:BuildUsageIndex()
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][ITEM] = { m = 1000, a = 1000, q = 50, t = S.now }
  ns.db.vendorSell[ITEM] = 100
  ns:InvalidateValues(true)
  local f = ns:SellFacts(ITEM, false, true)
  T.eq(f.vendor, 100); T.eq(f.ah, 930, "after the cut and one unsold deposit")
  local tip, added = fakeTip({})
  S.bags[ITEM] = nil
  ns:AddSellLines(tip, ITEM, false, true)
  T.eq(#added, 0, "not in your bags: nothing")
  S.bags[ITEM] = 3
  ns:AddSellLines(tip, ITEM, false, true)
  T.eq(added[1], "Sell: Auction house |cff999999(after the cut and the deposit)|r = " .. ns.Money(930))
  -- A gray item a vendor buys, with no auction price.
  ns.db.vendorSell[GRAY] = 10
  S.bags[GRAY] = 1
  tip, added = fakeTip({})
  ns:AddSellLines(tip, GRAY, false, true)
  T.eq(added[1], "Sell: Vendor = " .. ns.Money(10))
  -- Forever has C_Item.GetItemCount and not the old global (Frank, AN4, November 13: the
  -- line never showed).
  local oldCount, oldItem = GetItemCount, C_Item
  GetItemCount, C_Item = nil, { GetItemCount = function(id, bank) return (S.bags[id] or 0) + (bank and (S.bank[id] or 0) or 0) end }
  tip, added = fakeTip({})
  local ok, err = pcall(ns.AddSellLines, ns, tip, ITEM, false, true)
  S.bank[ITEM] = 2
  local withBank = ns.ItemCount(ITEM, true)
  GetItemCount, C_Item, S.bank[ITEM] = oldCount, oldItem, nil
  T.ok(ok, err)
  T.eq(added[1], "Sell: Auction house |cff999999(after the cut and the deposit)|r = " .. ns.Money(930), "with only C_Item.GetItemCount")
  T.eq(withBank, 5, "bags and bank")
  ns.db.prices[key][ITEM], ns.db.vendorSell[ITEM], ns.db.vendorSell[GRAY] = nil, nil, nil
  S.bags[ITEM], S.bags[GRAY] = nil, nil
  ns.db.chars = realChars
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
end)

-- Codex review of 3bb2be7: a 48-hour-old auction price was advised as current.
T.test("Sell suggestion: only a recent auction price counts", function()
  local realChars = ns.db.chars
  ns.db.chars = {}
  ns:BuildUsageIndex()
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][ITEM] = { m = 1000, a = 1000, q = 30, t = S.now - 48 * 3600 }
  ns.db.vendorSell[ITEM] = 100
  ns.db.settings.maxAgeHours = 12
  ns:InvalidateValues(true)
  T.eq(ns:SellFacts(ITEM, false, true).ah, nil, "48 hours old: no auction price to advise on")
  local tip, added = fakeTip({})
  S.bags[ITEM] = 1
  ns:AddSellLines(tip, ITEM, false, true)
  T.eq(#added, 0, "a white item with no recent price: nothing said")
  ns.db.prices[key][ITEM].t = S.now - 3600
  ns:InvalidateValues(true)
  T.eq(ns:SellFacts(ITEM, false, true).ah, 930, "an hour old: counted")
  ns.db.prices[key][ITEM], ns.db.vendorSell[ITEM], S.bags[ITEM] = nil, nil, nil
  ns.db.chars = realChars
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
end)

-- Codex review of 3bb2be7: a soulbound green was offered for disenchanting by an alt, who
-- can't receive it.
T.test("Sell suggestion: a bound item is only disenchanted by the character who has it", function()
  local realChars = ns.db.chars
  local ALT = "Alt Tester-" .. (ns.RealmName() or "?")
  local function chars(meEnch, altEnch)
    ns.db.chars = {
      [ME] = { name = "Tester", realm = ns.RealmName(), faction = "Alliance", profs = meEnch and { Enchanting = { rank = 100 } } or {} },
      [ALT] = { name = "Alt", realm = ns.RealmName(), faction = "Alliance", profs = altEnch and { Enchanting = { rank = 100 } } or {} },
    }
    ns:BuildUsageIndex()
    ns:InvalidateValues(true)
  end
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][DUST] = { m = 1000, a = 1000, q = 50, t = S.now }
  ns.db.vendorSell[GEAR] = 50
  chars(false, true)
  local f = ns:SellFacts(GEAR, true, false)
  T.eq(f.de, nil, "soulbound, and only the alt enchants: no disenchant suggestion")
  T.eq(V(f).kind, "vendor")
  f = ns:SellFacts(GEAR, false, true)
  T.ok(f.de and f.de > 0, "not bound: the alt can have it")
  T.eq(f.deWho, "Alt")
  chars(true, false)
  f = ns:SellFacts(GEAR, true, false)
  T.ok(f.de and f.de > 0, "soulbound, and this character enchants")
  T.eq(f.deWho, "Tester")
  ns.db.prices[key][DUST], ns.db.vendorSell[GEAR] = nil, nil
  ns.db.chars = realChars
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
end)
