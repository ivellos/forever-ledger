local T = ...
local ns, S = T.ns, T.S
local nextID = 97300
local function item(q, level, cls)
  nextID = nextID + 1
  S.items[nextID] = { name = "DE model " .. nextID, quality = q, ilvl = level, classID = cls or 4, equipLoc = "INVTYPE_CHEST" }
  return nextID
end
local function check(yield)
  T.ok(yield)
  local sum = 0
  for i, o in ipairs(yield.odds) do
    sum = sum + o[2]
    T.eq(yield[i][1], o[1])
    T.ok(math.abs(yield[i][2] - o[2] / 100 * (o[3] + o[4]) / 2) < 0.000001, "shown odds equal the valued mean")
  end
  T.eq(sum, 100); T.eq(yield.skill, 1)
end

T.test("Forever disenchant models: all green means match displayed chances and rank 1", function()
  for _, band in ipairs(ns.DISENCHANT_BANDS) do check(band.armor); check(band.weapon) end
  T.eq(ns:DisenchantYield(item(2, 4)), nil)
  T.ok(ns:DisenchantYield(item(2, 99)))
  T.eq(ns:DisenchantYield(item(2, 100)), nil)
  local y = ns:DisenchantYield(item(2, 23))
  T.eq(y.odds[2][2], 15); T.eq(y.odds[3][2], 10)
  T.eq(ns:DisenchantYield(item(2, 54, 2)).odds[3][2], 3)
end)

T.test("Forever rare and epic coverage honors eligibility and leaves contradictory early blues unknown", function()
  for _, level in ipairs({ 5, 15, 16, 20 }) do T.eq(ns:DisenchantYield(item(3, level)), nil) end
  for _, level in ipairs({ 21, 25, 26, 35, 40, 55, 60, 65, 99 }) do check(ns:DisenchantYield(item(3, level))) end
  T.eq(ns:DisenchantYield(item(4, 39)), nil)
  for _, level in ipairs({ 40, 45, 46, 50, 51, 55, 56, 60, 61, 99 }) do check(ns:DisenchantYield(item(4, level, 2))) end
  T.eq(ns:DisenchantYield(item(4, 40))[1][1], 11177)
  T.eq(ns:DisenchantYield(item(4, 56))[1][1], 20725)
  T.eq(ns:DisenchantYield(item(4, 61))[1][2], 1.5)
  T.eq(ns:DisenchantYield(item(3, 24)).tested, nil, "one blue observation does not test the entire rare model")
end)

T.test("Enchanting rank 1 counts in valuation, the finder, shopping-list caps and bound sell advice", function()
  T.resetDB()
  local id = item(2, 43)
  ns.db.chars = { [ns.CharKey()] = { name = "Tester", realm = ns.RealmName(), faction = "Alliance", profs = { Enchanting = { rank = 1 } } } }
  local market = {}
  for _, m in ipairs({ id, 11137, 11174, 11177 }) do market[m] = { m = 10, a = 10, q = 50, t = S.now } end
  ns.db.prices[ns.MarketKey()] = market
  ns.db.settings.deFinder = { bands = { [45] = true }, armor = true, weapon = true, profitable = false }
  ns:BuildUsageIndex(); ns:InvalidateValues(true)
  T.ok(ns:DisenchantBuyLimit(id))
  local rows, found = ns:DisenchantFinderItems(), false
  for _, r in ipairs(rows) do if r.id == id then found = true; T.eq(r.locked, nil) end end
  T.ok(found)
  T.ok(ns:SellFacts(id, true, false).de)
  local list = ns:NewShoppingList("Rank one")
  ns:DisenchantToShoppingList({ { id = id } }, list)
  T.ok(list.items[1] and list.items[1].max > 0)
end)

T.test("Eligibility: client NoDisenchant flags and crafted wands, not every Enchanting output", function()
  local old = ns.FOREVER_NO_DISENCHANT
  local refused, staff = item(2, 45), item(3, 50, 2)
  ns.FOREVER_NO_DISENCHANT = { [refused] = true }
  T.eq(ns:DisenchantYield(refused), nil)
  T.eq(ns:DisenchantYield(11287), nil)
  ns.db.chars[ns.CharKey()] = { profs = { Enchanting = { recipes = { [1] = { out = staff } } } } }
  T.ok(ns:DisenchantYield(staff), "a made-by-Enchanting association is not an eligibility flag")
  ns.FOREVER_NO_DISENCHANT = old
end)
