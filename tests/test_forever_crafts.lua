local T = ...
local ns, S = T.ns, T.S

T.test("Forever catalog: generated rows have provenance, valid quantities and the five requested professions", function()
  local data, profs, keys = {}, {}, {}
  assert(loadfile("ForeverCrafts.lua"))("ForeverLedger", data)
  for _, c in ipairs(data.FOREVER_CRAFTS) do
    T.ok(c.id > 0 and c.skill >= 0 and c.out > 0)
    T.ok(c.low >= 1 and c.high >= c.low and #c.r > 0)
    T.eq(c.source, "https://wago.tools"); T.eq(c.build, "1.60.1.70938")
    local key = c.prof .. ":" .. c.id
    T.eq(keys[key], nil); keys[key] = true
    profs[c.prof] = (profs[c.prof] or 0) + 1
    for _, m in ipairs(c.r) do T.ok(m[1] > 0 and m[2] > 0) end
    T.ok(data.FOREVER_ITEM_NAMES[c.out])
  end
  for _, p in ipairs({ "Alchemy", "Blacksmithing", "Engineering", "Leatherworking", "Mining" }) do T.ok(profs[p] > 10, p) end
  T.eq(data.FOREVER_NO_DISENCHANT[11287], true)
  T.eq(data.FOREVER_NO_DISENCHANT[249454], nil, "Dreamstaff is not excluded just because Enchanting crafts it")
end)

T.test("All professions: captured, Forever, Classic precedence is per recipe, even when the winner is unprofitable", function()
  T.resetDB()
  local oldF, oldC = ns.FOREVER_CRAFTS, ns.CLASSIC_CRAFT_LIST
  local input, output, classicOnly = 97101, 97102, 97103
  S.items[input] = { name = "Reference material", sell = 0 }
  S.items[output] = { name = "Reference output", sell = 100 }
  S.items[classicOnly] = { name = "Classic-only output", sell = 100 }
  ns.db.chars = {}
  ns.db.prices[ns.MarketKey()] = { [input] = { m = 10, a = 10, q = 100, t = S.now } }
  ns.db.recipeBook = { Alchemy = { [1] = { n = "Captured", out = output, oq = 1, r = { { input, 2 } } } } }
  ns.FOREVER_CRAFTS = {
    { id = 1, prof = "Alchemy", out = output, low = 1, high = 1, r = { { input, 1 } }, build = "test" },
    { id = 2, prof = "Alchemy", out = output, low = 2, high = 2, r = { { input, 3 } }, build = "test" },
  }
  ns.CLASSIC_CRAFT_LIST = {
    { "Alchemy", 1, output, 10, 10, 100, input .. ":1" }, -- superseded public route
    { "Alchemy", 1, output, 10, 10, 100, input .. ":3" }, -- same public route
    -- Other materials for an item Forever makes: out of date (Claude's review of 03378d1:
    -- 229 such rows in the real data), so left out.
    { "Alchemy", 1, output, 1, 1, 100, input .. ":4" },
    -- An item no Forever recipe of that profession makes: Classic's fills it.
    { "Alchemy", 1, classicOnly, 1, 1, 100, input .. ":5" },
  }
  ns:BuildUsageIndex(); ns:InvalidateValues(true)
  local list = ns:FindAllVendorCrafts()
  T.eq(#list, 3)
  local sources = {}
  for _, s in ipairs(list) do
    local q = s.opt.rec.r[1][2]; sources[q] = s
  end
  T.eq(sources[1], nil, "captured spell ID beats old public version, whose Classic copy stays suppressed")
  T.eq(sources[2].forever, nil); T.eq(sources[2].classic, nil)
  T.eq(sources[3].forever, true); T.eq(sources[3].opt.rec.oq, 2)
  T.eq(sources[4], nil, "Classic's other materials for an item Forever makes: out of date")
  T.eq(sources[5].classic, true, "a partial book does not hide Classic's recipe for another item")
  ns.db.recipeBook.Alchemy[1].r[1][2] = 20
  ns:InvalidateValues(true); list = ns:FindAllVendorCrafts()
  T.eq(#list, 2, "an unprofitable captured recipe cannot revive lower-priority versions")
  ns.FOREVER_CRAFTS[#ns.FOREVER_CRAFTS + 1] = { id = 3, prof = "Alchemy", out = output, low = 3, high = 3,
    r = { { input, 3 } }, build = "test" }
  ns:InvalidateValues(true); list = ns:FindAllVendorCrafts()
  T.eq(#list, 3, "distinct current recipe IDs survive even with identical materials and output item")
  ns.FOREVER_CRAFTS, ns.CLASSIC_CRAFT_LIST = oldF, oldC
end)

T.test("Item names: live and cached localized names beat Forever, then Classic", function()
  local oldF, oldC = ns.FOREVER_ITEM_NAMES, ns.CLASSIC_ITEMS
  ns.FOREVER_ITEM_NAMES = { [97111] = "Public name" }
  ns.CLASSIC_ITEMS = { [97111] = "Old name", [97112] = "Classic only" }
  T.eq(ns.ItemName(97111), "Public name"); T.eq(ns.ItemName(97112), "Classic only")
  ns.db.itemNames[97111] = "Localized name"; T.eq(ns.ItemName(97111), "Localized name")
  ns.FOREVER_ITEM_NAMES[97113] = "Public other"
  S.items[97113] = { name = "Live name" }; T.eq(ns.ItemName(97113), "Live name")
  ns.FOREVER_ITEM_NAMES, ns.CLASSIC_ITEMS = oldF, oldC
end)
