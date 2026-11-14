-- Shuffles' Sells to a vendor, All professions (Shuffles.lua ns:FindAllVendorCrafts): every
-- profession's crafts that sell to a vendor for more than their materials cost, whoever
-- knows them (owner, November 12).
local T = ...
local ns, S = T.ns, T.S
local ME = ns.CharKey()
local CLOTH, THREAD, DYE, SHIRT, GLOVES, POTION, HERB, VIAL, ODD = 97001, 97002, 97003, 97004, 97005, 97006, 97007, 97008, 97009
local UNLOADED, JUNK, BAR, ORE, IRON = 97012, 97013, 97020, 97021, 97022
local POISON = 6947   -- Instant Poison: vendors won't buy it (Prices.lua VENDOR_WONT_BUY)
S.items[SHIRT] = { name = "Test Shirt", sell = 300 }
S.items[GLOVES] = { name = "Test Gloves", sell = 40 }
S.items[POTION] = { name = "Test Potion", sell = 150 }
S.items[JUNK] = { name = "Test Junk", sell = 0 }   -- loaded: the game says no vendor price
S.items[BAR] = { name = "Test Bar", sell = 600 }

local function price(id, p)
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][id] = { m = p, a = p, q = 50, t = S.now }
end

-- The rows that make `out`, by the material bought for them (each recipe its own row).
local function rows(list, out)
  local by, n = {}, 0
  for _, s in ipairs(list) do
    if s.opt.rec.out == out then by[s.id] = s; n = n + 1 end
  end
  return by, n
end

T.test("All professions: every profession's crafts that sell to a vendor at a profit", function()
  local realChars, realBook, realClassic = ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFTS
  ns.db.chars = { [ME] = { name = "Tester", realm = ns.RealmName(), faction = "Alliance",
    profs = { Tailoring = { rank = 100, recipes = { [5] = { n = "Test Shirt", out = SHIRT, oq = 1, r = { { CLOTH, 2 }, { THREAD, 1 } } } } } } } }
  -- Tailoring has been opened in game: its recipe book counts, Classic's Tailoring doesn't.
  ns.db.recipeBook = { Tailoring = {
    [5] = { n = "Test Shirt", out = SHIRT, oq = 1, r = { { CLOTH, 2 }, { THREAD, 1 } } },
    [6] = { n = "Test Gloves", out = GLOVES, oq = 1, r = { { CLOTH, 3 } } },
    -- A second recipe for the same shirt, not learned by anyone of yours.
    [7] = { n = "Test Shirt", out = SHIRT, oq = 1, r = { { THREAD, 2 } } },
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
  local shirts, nShirts = rows(list, SHIRT)
  T.eq(nShirts, 2, "two recipes make the shirt: two rows")
  T.ok(shirts[CLOTH], "a known craft: 300 for 110 of materials")
  T.eq(shirts[CLOTH].profit, 190)
  T.eq(shirts[CLOTH].known, true)
  T.ok(shirts[CLOTH].opt.who:find("Tailoring: Tester", 1, true), shirts[CLOTH].opt.who)
  T.ok(shirts[THREAD], "the other shirt recipe: 300 for 20 of thread")
  T.eq(shirts[THREAD].profit, 280)
  T.eq(shirts[THREAD].known, false, "known by recipe, not by the item it makes")
  T.ok(shirts[THREAD].opt.who:find("Tailoring, none of yours", 1, true), shirts[THREAD].opt.who)
  T.eq(select(2, rows(list, GLOVES)), 0, "40 for 150 of cloth: no profit")
  local potion = rows(list, POTION)[HERB]
  T.ok(potion, "a profession nobody of yours has opened: Classic's recipe")
  T.eq(potion.profit, 90)
  T.eq(potion.classic, true)
  T.ok(potion.opt.who:find("Alchemy, none of yours, Classic recipe", 1, true), potion.opt.who)
  T.eq(select(2, rows(list, 97010)), 0, "Classic's Tailoring is set aside for the recipe book's")
  T.eq(select(2, rows(list, 97011)), 0)
  T.eq(noPrice, 1, "one recipe left out for a material with no price")
  T.eq(shirts[CLOTH].opt.next.kind, "vendor")
  ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFTS = realChars, realBook, realClassic
  local key = ns.MarketKey()
  for _, id in ipairs({ CLOTH, THREAD, HERB, VIAL }) do ns.db.prices[key][id] = nil end
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
end)

-- Codex review, November 12: Classic's vendor price brought back items the game says
-- vendors won't buy, and two recipes for one item (Gold Bar: smelted, or transmuted from
-- Iron Bars) showed only the first.
T.test("All professions: the game's no vendor price wins; each recipe has its own row", function()
  local realChars, realBook, realClassic = ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFTS
  ns.db.chars, ns.db.recipeBook = {}, {}
  ns.CLASSIC_CRAFTS = {
    { "Alchemy", 10, JUNK, 1, 1, 1000, HERB .. ":1" },       -- the game: no vendor price
    { "Alchemy", 10, POISON, 1, 1, 1000, HERB .. ":1" },     -- a poison vendors refuse
    { "Alchemy", 10, UNLOADED, 1, 1, 400, HERB .. ":1" },    -- not loaded yet: Classic's price
    { "Mining", 155, BAR, 1, 1, 600, ORE .. ":1" },
    { "Alchemy", 150, BAR, 1, 1, 600, IRON .. ":1" },
    { "Alchemy", 150, BAR, 1, 1, 600, IRON .. ":1" },        -- listed twice: still one row
  }
  price(HERB, 10); price(ORE, 250); price(IRON, 10)
  ns:InvalidateValues(true)
  local list = ns:FindAllVendorCrafts()
  T.eq(select(2, rows(list, JUNK)), 0, "a known zero isn't replaced by Classic's price")
  T.eq(select(2, rows(list, POISON)), 0)
  local unloaded = rows(list, UNLOADED)[HERB]
  T.ok(unloaded, "an item the game hasn't loaded yet uses Classic's price")
  T.eq(unloaded.profit, 390)
  local bars, nBars = rows(list, BAR)
  T.eq(nBars, 2, "smelted and transmuted, once each")
  T.eq(bars[ORE].profit, 350)
  T.ok(bars[ORE].opt.who:find("Mining", 1, true), bars[ORE].opt.who)
  T.eq(bars[IRON].profit, 590)
  T.ok(bars[IRON].opt.who:find("Alchemy", 1, true), bars[IRON].opt.who)
  ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFTS = realChars, realBook, realClassic
  local key = ns.MarketKey()
  for _, id in ipairs({ HERB, ORE, IRON }) do ns.db.prices[key][id] = nil end
  ns.db.vendorSell[UNLOADED] = nil
  ns:InvalidateValues(true)
end)

-- Frank's All professions list (November 13) showed Felblood Soul Bag, Sylvan Shoulders and
-- Simple Poultice twice: a new character's Skinning window had listed Tailoring, Enchanting,
-- First Aid and Fishing recipes too, and all of them were saved under Skinning.
T.test("Recipe book: another profession's leftover recipes aren't saved under this one", function()
  local realBook, realTS = ns.db.recipeBook, C_TradeSkillUI
  ns.db.recipeBook = { Tailoring = { [501] = { n = "Shirt" }, [502] = { n = "Gloves" } } }
  local names = { [501] = "Shirt", [502] = "Gloves", [601] = "Camp Chair" }
  C_TradeSkillUI = {
    GetAllRecipeIDs = function() return { 501, 502, 601 } end,
    GetRecipeInfo = function(id) return { name = names[id] } end,
    GetRecipeSchematic = function(id) return { outputItemID = 98000 + id, reagentSlotSchematics = {} } end,
  }
  ns:CaptureRecipeBook("Skinning")
  T.eq(ns.db.recipeBook.Skinning[601].n, "Camp Chair", "Skinning's own recipe")
  T.eq(ns.db.recipeBook.Skinning[501], nil, "Tailoring's stay Tailoring's")
  T.eq(ns.db.recipeBook.Tailoring[501].n, "Shirt")
  -- A book an older version mixed up: each recipe stays only in the smaller book.
  ns.db.recipeBook.Skinning[501], ns.db.recipeBook.Skinning[502] = { n = "Shirt" }, { n = "Gloves" }
  T.eq(ns:CleanRecipeBook(), 2)
  T.eq(ns.db.recipeBook.Skinning[501], nil)
  T.eq(ns.db.recipeBook.Skinning[502], nil)
  T.eq(ns.db.recipeBook.Skinning[601].n, "Camp Chair")
  T.eq(ns.db.recipeBook.Tailoring[501].n, "Shirt")
  T.eq(ns.db.recipeBook.Tailoring[502].n, "Gloves")
  T.eq(ns:CleanRecipeBook(), 0, "nothing more to do the second time")
  ns.db.recipeBook, C_TradeSkillUI = realBook, realTS
end)
