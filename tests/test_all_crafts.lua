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
  local realChars, realBook, realClassic = ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFT_LIST
  ns.db.chars = { [ME] = { name = "Tester", realm = ns.RealmName(), faction = "Alliance",
    profs = { Tailoring = { rank = 100, recipes = { [5] = { n = "Test Shirt", out = SHIRT, oq = 1, r = { { CLOTH, 2 }, { THREAD, 1 } } } } } } } }
  -- Tailoring has been opened in game: its recipe book counts, Classic's Tailoring doesn't.
  ns.db.recipeBook = { Tailoring = {
    [5] = { n = "Test Shirt", out = SHIRT, oq = 1, r = { { CLOTH, 2 }, { THREAD, 1 } } },
    [6] = { n = "Test Gloves", out = GLOVES, oq = 1, r = { { CLOTH, 3 } } },
    -- A second recipe for the same shirt, not learned by anyone of yours.
    [7] = { n = "Test Shirt", out = SHIRT, oq = 1, r = { { THREAD, 2 } } },
  } }
  ns.CLASSIC_CRAFT_LIST = {
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
  ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFT_LIST = realChars, realBook, realClassic
  local key = ns.MarketKey()
  for _, id in ipairs({ CLOTH, THREAD, HERB, VIAL }) do ns.db.prices[key][id] = nil end
  ns:BuildUsageIndex()
  ns:InvalidateValues(true)
end)

-- Codex review, November 12: Classic's vendor price brought back items the game says
-- vendors won't buy, and two recipes for one item (Gold Bar: smelted, or transmuted from
-- Iron Bars) showed only the first.
T.test("All professions: the game's no vendor price wins; each recipe has its own row", function()
  local realChars, realBook, realClassic = ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFT_LIST
  ns.db.chars, ns.db.recipeBook = {}, {}
  ns.CLASSIC_CRAFT_LIST = {
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
  ns.db.chars, ns.db.recipeBook, ns.CLASSIC_CRAFT_LIST = realChars, realBook, realClassic
  local key = ns.MarketKey()
  for _, id in ipairs({ HERB, ORE, IRON }) do ns.db.prices[key][id] = nil end
  ns.db.vendorSell[UNLOADED] = nil
  ns:InvalidateValues(true)
end)

-- Frank's All professions list (November 13) showed Felblood Soul Bag, Sylvan Shoulders and
-- Simple Poultice twice: a new character's Skinning window had listed Tailoring, Enchanting,
-- First Aid and Fishing recipes too, and all of them were saved under Skinning.
local NAMES = { [501] = "Shirt", [502] = "Gloves", [503] = "Belt", [504] = "Cloak", [601] = "Camp Chair", [701] = "Stew" }
local function recipeAPI(ids)
  return {
    GetAllRecipeIDs = function() return ids end,
    GetRecipeInfo = function(id) return NAMES[id] and { name = NAMES[id] } end,
    GetRecipeSchematic = function(id) return { outputItemID = 98000 + id, reagentSlotSchematics = {} } end,
  }
end
local real = {}
local function save() real.book, real.ts, real.chars, real.classic = ns.db.recipeBook, C_TradeSkillUI, ns.db.chars, ns.CLASSIC_CRAFT_LIST end
local function restore() ns.db.recipeBook, C_TradeSkillUI, ns.db.chars, ns.CLASSIC_CRAFT_LIST = real.book, real.ts, real.chars, real.classic end

T.test("Recipe book: another profession's leftover recipes aren't saved under this one", function()
  save()
  ns.db.chars, ns.CLASSIC_CRAFT_LIST = {}, nil
  ns.db.recipeBook = { Tailoring = { [501] = { n = "Shirt" }, [502] = { n = "Gloves" }, [503] = { n = "Belt" } } }
  C_TradeSkillUI = recipeAPI({ 501, 502, 503, 601 })
  ns:CaptureRecipeBook("Skinning")
  T.eq(ns.db.recipeBook.Skinning[601].n, "Camp Chair", "Skinning's own recipe")
  T.eq(ns.db.recipeBook.Skinning[501], nil, "Tailoring's whole list was in the window: its recipes stay Tailoring's")
  T.eq(ns.db.recipeBook.Tailoring[501].n, "Shirt")
  -- A book an older version mixed up: Skinning holds Tailoring's whole list besides its own.
  for id = 501, 503 do ns.db.recipeBook.Skinning[id] = { n = NAMES[id] } end
  local removed, unsure = ns:CleanRecipeBook()
  T.eq(removed, 3); T.eq(unsure, 0)
  T.eq(ns.db.recipeBook.Skinning[501], nil)
  T.eq(ns.db.recipeBook.Skinning[601].n, "Camp Chair")
  T.eq(ns.db.recipeBook.Tailoring[503].n, "Belt")
  T.eq((ns:CleanRecipeBook()), 0, "nothing more to do the second time")
  restore()
end)

-- Codex review of c4dd71a: the smaller book won, so a stray copy in a small book took the
-- recipe from the right one, deleting the right one's copy (with its item and materials);
-- and reopening the right profession couldn't put it back.
T.test("Recipe book: a recipe in two books moves only on evidence, keeping the fuller copy", function()
  save()
  ns.db.chars, ns.CLASSIC_CRAFT_LIST = {}, nil
  local full = { n = "Shirt", out = 98501, oq = 1, r = { { CLOTH, 2 } } }
  ns.db.recipeBook = {
    Tailoring = { [501] = full, [502] = { n = "Gloves" }, [503] = { n = "Belt" }, [504] = { n = "Cloak" } },
    Skinning = { [601] = { n = "Camp Chair" }, [501] = { n = "Shirt" } },
  }
  local removed, unsure = ns:CleanRecipeBook()
  T.eq(removed, 0, "neither book holds the other's list: nothing says whose it is")
  T.eq(unsure, 1)
  T.eq(ns.db.recipeBook.Tailoring[501], full)
  T.eq(ns.db.recipeBook.Skinning[501].n, "Shirt", "kept in both")
  C_TradeSkillUI = recipeAPI({ 501, 502, 503, 504 })
  ns:CaptureRecipeBook("Tailoring")
  T.eq(ns.db.recipeBook.Tailoring[501], full, "reopening Tailoring keeps it")
  -- Two stray recipes in a book of their own prove nothing either (under 3).
  ns.db.recipeBook.Mining = { [502] = { n = "Gloves" }, [503] = { n = "Belt" } }
  removed, unsure = ns:CleanRecipeBook()
  T.eq(removed, 0); T.eq(unsure, 3)
  ns.db.recipeBook.Mining = nil
  -- A character who knows it under Tailoring settles it. Here Tailoring's copy is the
  -- thin one: it gets what only Skinning's copy had.
  ns.db.recipeBook.Tailoring[501] = { n = "Shirt" }
  ns.db.recipeBook.Skinning[501] = full
  ns.db.chars = { [ME] = { name = "Tester", profs = { Tailoring = { recipes = { [501] = { n = "Shirt" } } } } } }
  removed, unsure = ns:CleanRecipeBook()
  T.eq(removed, 1); T.eq(unsure, 0)
  T.eq(ns.db.recipeBook.Skinning[501], nil)
  T.eq(ns.db.recipeBook.Tailoring[501].out, 98501, "the fuller copy's item")
  T.eq(ns.db.recipeBook.Tailoring[501].r[1][1], CLOTH, "and materials")
  restore()
end)

T.test("Recipe book: a recipe lost from its own book comes back when that window opens", function()
  save()
  ns.db.chars, ns.CLASSIC_CRAFT_LIST = {}, nil
  -- Shirt 501 was taken from Tailoring by the old smaller-book cleanup.
  ns.db.recipeBook = {
    Tailoring = { [502] = { n = "Gloves" }, [503] = { n = "Belt" }, [504] = { n = "Cloak" } },
    Skinning = { [601] = { n = "Camp Chair" }, [501] = { n = "Shirt" } },
  }
  C_TradeSkillUI = recipeAPI({ 501, 502, 503, 504 })
  ns:CaptureRecipeBook("Tailoring")
  T.eq(ns.db.recipeBook.Tailoring[501].out, 98501, "saved under Tailoring again")
  T.eq(ns.db.recipeBook.Skinning[501].n, "Shirt", "nothing says it isn't Skinning's too: kept")
  -- With Classic's data for the shirt, it's Tailoring's alone.
  ns.db.recipeBook.Tailoring[501] = nil
  ns.CLASSIC_CRAFT_LIST = { { "Tailoring", 1, 98501, 1, 1, 10, "97001:2" }, { "Cooking", 1, 98701, 1, 1, 5, "97007:1" } }
  ns:CaptureRecipeBook("Tailoring")
  T.eq(ns.db.recipeBook.Tailoring[501].out, 98501)
  T.eq(ns.db.recipeBook.Skinning[501], nil, "Classic's data says Tailoring makes it")
  -- A leftover of a profession with no book yet: Classic's data keeps it out of this one.
  C_TradeSkillUI = recipeAPI({ 601, 701 })
  ns:CaptureRecipeBook("Skinning")
  T.eq(ns.db.recipeBook.Skinning[701], nil, "Cooking makes the stew")
  restore()
end)

-- Codex review of b7c7eb2: a stray book wholly inside the window counted as leftovers, so
-- the recipe was skipped before Classic's data could say it was this profession's.
T.test("Recipe book: a stray book's one recipe is no leftover; the facts outrank which book holds which", function()
  save()
  ns.db.chars, ns.CLASSIC_CRAFT_LIST = {}, { { "Tailoring", 1, 98501, 1, 1, 10, "97001:2" } }
  ns.db.recipeBook = {
    Tailoring = { [502] = { n = "Gloves" }, [503] = { n = "Belt" }, [504] = { n = "Cloak" } },
    Skinning = { [501] = { n = "Shirt" } },
  }
  C_TradeSkillUI = recipeAPI({ 501, 502, 503, 504 })
  ns:CaptureRecipeBook("Tailoring")
  T.eq(ns.db.recipeBook.Tailoring[501] and ns.db.recipeBook.Tailoring[501].out, 98501, "back in Tailoring")
  T.eq(ns.db.recipeBook.Skinning[501], nil, "Classic's data says Tailoring makes it")
  -- With nothing to say whose it is, it's still saved here, and kept in both.
  ns.CLASSIC_CRAFT_LIST = nil
  ns.db.recipeBook.Tailoring[501], ns.db.recipeBook.Skinning[501] = nil, { n = "Shirt" }
  ns:CaptureRecipeBook("Tailoring")
  T.ok(ns.db.recipeBook.Tailoring[501], "saved under Tailoring")
  T.ok(ns.db.recipeBook.Skinning[501], "and not taken from Skinning")
  -- A book holding only some of Tailoring's recipes holds nothing of its own; going by
  -- which book holds which, they'd be its. Classic's data says Tailoring: it wins.
  ns.CLASSIC_CRAFT_LIST = { { "Tailoring", 1, 98502, 1, 1, 10, "97001:2" }, { "Tailoring", 1, 98503, 1, 1, 10, "97001:2" }, { "Tailoring", 1, 98504, 1, 1, 10, "97001:2" } }
  ns.db.recipeBook = {
    Tailoring = { [501] = { n = "Shirt" }, [502] = { n = "Gloves", out = 98502 }, [503] = { n = "Belt", out = 98503 }, [504] = { n = "Cloak", out = 98504 } },
    Skinning = { [502] = { n = "Gloves" }, [503] = { n = "Belt" }, [504] = { n = "Cloak" } },
  }
  local removed, unsure = ns:CleanRecipeBook()
  T.eq(removed, 3); T.eq(unsure, 0)
  T.eq(next(ns.db.recipeBook.Skinning), nil, "nothing left under Skinning")
  restore()
end)

-- Two data files once both set ns.CLASSIC_CRAFTS (ClassicCrafts.lua's list and ClassicItems.lua's
-- table by item). The game loads ClassicItems.lua last, so All professions had no Classic
-- recipes in game; the tests skip ClassicItems.lua, so they read the files' text instead.
T.test("No two of the addon's files set the same ns name", function()
  local owner, clash = {}, {}
  for line in io.lines("ForeverLedger.toc") do
    local file = line:gsub("\r", "")
    if file:match("%.lua$") then
      local seen = {}
      for l in io.lines(file) do
        local name, after = l:match("^ns%.([%w_]+)%s*=(.?)")
        if name and after ~= "=" and not seen[name] then
          seen[name] = true
          if owner[name] then clash[#clash + 1] = name .. ": " .. owner[name] .. ", " .. file end
          owner[name] = file
        end
      end
    end
  end
  T.eq(table.concat(clash, "; "), "")
  T.eq(owner.CLASSIC_CRAFT_LIST, "ClassicCrafts.lua")
  T.eq(owner.CLASSIC_CRAFTS, "ClassicItems.lua")
end)
