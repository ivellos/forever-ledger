-- What an item is worth (Values.lua ns:GetValue): the best of the auction house after
-- the cut, a vendor, disenchanting, converting essences and crafting, following chains.
local T = ...
local ns, S = T.ns, T.S
local ME = ns.CharKey()
local DUST, LESSER_MAGIC, GREATER_MAGIC = 10940, 10938, 10939

local function price(id, p, listed)
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][id] = { m = p, a = p, q = listed or 50, t = S.now }
end

-- A character of yours with these professions; recipes { { name, out, { {id, qty}, ... } } }.
local function me(profs)
  ns.db.chars = { [ME] = { name = "Tester", realm = "Testrealm", faction = "Alliance", profs = profs or {} } }
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
end
local function recipes(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = { n = r[1], out = r[2], oq = 1, r = r[3] } end
  return { Tailoring = { rank = 300, recipes = out } }
end

local function near(got, want, what)
  if type(got) ~= "number" or math.abs(got - want) > 0.001 then
    error(("%s: expected %s, got %s"):format(what or "value", tostring(want), tostring(got)), 2)
  end
end

T.test("The auction house, after the cut", function()
  me()
  price(60001, 1000)
  ns.db.vendorSell[60001] = 100
  local v, opts = ns:GetValue(60001)
  T.eq(v, 930)
  T.eq(opts[1].kind, "ah")
  T.eq(opts[1].label, "Sell on the auction house, after 5% cut and one unsold listing")
  T.eq(opts[2].kind, "vendor", "the vendor next")
end)

T.test("The cut follows the setting", function()
  me()
  ns.db.settings.ahCut = 15
  price(60002, 1000)
  T.eq((ns:GetValue(60002)), 850)
  ns.db.settings.ahCut = 5
end)

T.test("A vendor when it pays more", function()
  me()
  price(60003, 100)
  ns.db.vendorSell[60003] = 300
  local v, opts = ns:GetValue(60003)
  T.eq(v, 300)
  T.eq(opts[1].label, "Sell to vendor")
end)

T.test("Nothing known: no value", function()
  me()
  local v, opts = ns:GetValue(60004)
  T.eq(v, nil)
  T.eq(#opts, 0)
end)

T.test("Disenchanting, with an enchanter", function()
  -- A level 12 green chest: 1.18 Strange Dust and 0.31 Lesser Magic Essence on average.
  S.items[60010] = { name = "Green Vest", quality = 2, ilvl = 12, classID = 4, equipLoc = "INVTYPE_CHEST" }
  price(DUST, 1000)
  price(LESSER_MAGIC, 2000)
  me({ Enchanting = { rank = 50 } })
  local v, opts = ns:GetValue(60010)
  near(v, 1.18 * 950 + 0.31 * 1900, "disenchant value")
  T.eq(opts[1].kind, "disenchant")
  T.eq(opts[1].label, "Disenchant")
end)

T.test("No disenchanting without an enchanter", function()
  S.items[60011] = { name = "Green Gloves", quality = 2, ilvl = 12, classID = 4, equipLoc = "INVTYPE_HAND" }
  price(DUST, 1000)
  me()
  T.eq((ns:GetValue(60011)), nil)
end)

T.test("Disenchanting ignores thin markets for the materials", function()
  S.items[60012] = { name = "Green Boots", quality = 2, ilvl = 12, classID = 4, equipLoc = "INVTYPE_FEET" }
  price(DUST, 1000, 2)   -- only 2 listed
  price(LESSER_MAGIC, 2000)
  me({ Enchanting = { rank = 50 } })
  near((ns:GetValue(60012)), 0.31 * 1900, "only the essence counts")
end)

T.test("Essences: splitting a greater one into 3 lesser", function()
  price(LESSER_MAGIC, 5000)
  price(GREATER_MAGIC, 10000)
  me()
  local v, opts = ns:GetValue(GREATER_MAGIC)
  near(v, 3 * 4750, "3 lesser at 4750")
  T.eq(opts[1].kind, "convert")
  T.eq(opts[1].label, "Split into Lesser Magic Essence, sell on the auction house")
  near((ns:GetValue(LESSER_MAGIC)), 4750, "the lesser one sells as it is")
end)

T.test("Essences: combining 3 lesser into a greater", function()
  price(LESSER_MAGIC, 1000)
  price(GREATER_MAGIC, 9000)
  me()
  local v, opts = ns:GetValue(LESSER_MAGIC)
  near(v, 8550 / 3, "a third of a greater")
  T.eq(opts[1].label, "Combine into Greater Magic Essence, sell on the auction house")
end)

T.test("A craft: what's left after buying the other materials, per unit", function()
  -- 2 of the item and 1 thread (a vendor sells it for 100) make one that sells for 10000.
  ns.db.vendorBuy[60021] = { p = 100 }
  price(60022, 10000)
  price(60020, 1000)
  me(recipes({ { "Fine Shirt", 60022, { { 60020, 2 }, { 60021, 1 } } } }))
  local v, opts = ns:GetValue(60020)
  T.eq(v, (9500 - 100) / 2)
  T.eq(opts[1].kind, "craft")
  T.eq(opts[1].label, "Craft Fine Shirt, sell on the auction house")
end)

T.test("A craft whose other material has no price isn't counted", function()
  price(60032, 10000)
  price(60030, 1000)
  me(recipes({ { "Fine Hat", 60032, { { 60030, 2 }, { 60031, 1 } } } }))
  local _, opts = ns:GetValue(60030)
  T.eq(opts[1].kind, "ah")
  T.eq(#opts, 1)
end)

T.test("A loop in the recipes (A makes B, B makes A) doesn't hang", function()
  ns.db.vendorSell[60040] = 10
  me(recipes({ { "Make B", 60041, { { 60040, 1 } } }, { "Make A", 60040, { { 60041, 1 } } } }))
  -- Stop after a few million steps instead of hanging, so a loop fails the test.
  debug.sethook(function() error("GetValue didn't finish: a loop?") end, "", 5e6)
  local ok, v, opts = pcall(ns.GetValue, ns, 60040)
  local ok2, v2 = pcall(ns.GetValue, ns, 60041)
  debug.sethook()
  T.ok(ok, tostring(v))
  T.ok(ok2, tostring(v2))
  T.eq(v, 10, "A is worth its vendor price")
  T.eq(opts[1].kind, "vendor")
  T.eq(v2, 10, "B is worth making into A")
end)

T.test("A longer chain of crafts stops after a few steps", function()
  -- 60050 -> 60051 -> ... -> 60059, only the last one sells.
  local list = {}
  for i = 0, 8 do list[#list + 1] = { "Step " .. i, 60051 + i, { { 60050 + i, 1 } } } end
  price(60059, 1000)
  me(recipes(list))
  T.eq((ns:GetValue(60055)), 950, "4 steps away: reached")
  T.eq((ns:GetValue(60050)), nil, "9 steps away: too far")
end)

T.test("Items that bind are worth only their vendor price (loot in sessions)", function()
  -- 99001 is a bound item (tests/run.lua); Sessions.lua values loot this way.
  price(99001, 5000)
  ns.db.vendorSell[99001] = 30
  ns.db.settings.source = "own"
  T.eq(ns:IsClassicBound(99001), true)
  T.eq(ns:LootValue(99001), 30)
  price(60060, 5000)
  ns.db.vendorSell[60060] = 30
  T.eq(ns:LootValue(60060), 4750, "an item that doesn't bind: the auction house")
end)
