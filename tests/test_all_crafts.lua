-- Shuffles' Sells to a vendor, All professions (Shuffles.lua ns:FindAllVendorCrafts): every
-- profession's crafts that sell to a vendor for more than their materials cost, whoever
-- knows them (owner, November 12).
local T = ...
local ns, S = T.ns, T.S
local ME = ns.CharKey()
local CLOTH, THREAD, DYE, SHIRT, GLOVES, POTION, HERB, VIAL, ODD = 97001, 97002, 97003, 97004, 97005, 97006, 97007, 97008, 97009
S.items[SHIRT] = { name = "Test Shirt", sell = 300 }
S.items[GLOVES] = { name = "Test Gloves", sell = 40 }
S.items[POTION] = { name = "Test Potion", sell = 150 }

local function price(id, p)
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][id] = { m = p, a = p, q = 50, t = S.now }
end

T.test("All professions: every profession's crafts that sell to a vendor at a profit", function()
  local realChars, realBook, realClassic = ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFTS
  ns.db.chars = { [ME] = { name = "Tester", realm = ns.RealmName(), faction = "Alliance",
    profs = { Tailoring = { rank = 100, recipes = { [5] = { n = "Test Shirt", out = SHIRT, oq = 1, r = { { CLOTH, 2 }, { THREAD, 1 } } } } } } } }
  -- Tailoring has been opened in game: its recipe book counts, Classic's Tailoring doesn't.
  ns.db.recipeBook = { Tailoring = {
    [5] = { n = "Test Shirt", out = SHIRT, oq = 1, r = { { CLOTH, 2 }, { THREAD, 1 } } },
    [6] = { n = "Test Gloves", out = GLOVES, oq = 1, r = { { CLOTH, 3 } } },
  } }
  ns.CLASSIC_CRAFTS = {
    { "Alchemy", 50, POTION, 1, 1, 150, HERB .. ":1," .. VIAL .. ":1" },
    { "Tailoring", 1, 97010, 1, 1, 9999, CLOTH .. ":1" },   -- left out: Tailoring is in the recipe book
    { "Alchemy", 60, 97011, 1, 1, 500, ODD .. ":1" },        -- left out: a material with no price
  }
  price(CLOTH, 50); price(THREAD, 10); price(HERB, 40); price(VIAL, 20)
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
  local list, noPrice = ns:FindAllVendorCrafts()
  local byOut = {}
  for _, s in ipairs(list) do byOut[s.opt.rec.out] = s end
  T.ok(byOut[SHIRT], "a known craft: 300 for 110 of materials")
  T.eq(byOut[SHIRT].profit, 190)
  T.eq(byOut[SHIRT].known, true)
  T.ok(byOut[SHIRT].opt.who:find("Tailoring: Tester", 1, true), byOut[SHIRT].opt.who)
  T.eq(byOut[GLOVES], nil, "40 for 150 of cloth: no profit")
  T.ok(byOut[POTION], "a profession nobody of yours has opened: Classic's recipe")
  T.eq(byOut[POTION].profit, 90)
  T.eq(byOut[POTION].classic, true)
  T.ok(byOut[POTION].opt.who:find("Alchemy, none of yours, Classic recipe", 1, true), byOut[POTION].opt.who)
  T.eq(byOut[97010], nil, "Classic's Tailoring is set aside for the recipe book's")
  T.eq(byOut[97011], nil)
  T.eq(noPrice, 1, "one recipe left out for a material with no price")
  T.eq(byOut[SHIRT].opt.next.kind, "vendor")
  ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFTS = realChars, realBook, realClassic
  local key = ns.MarketKey()
  for _, id in ipairs({ CLOTH, THREAD, HERB, VIAL }) do ns.db.prices[key][id] = nil end
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
end)
