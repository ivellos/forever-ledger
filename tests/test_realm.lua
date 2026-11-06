-- The live game names each character's server; saved data is filed by the plain realm.
-- Hidden ("secret") event text never reaches the handlers.
local T = ...
local ns = T.ns

T.test("Plain realm: the server part goes, anything else stays", function()
  T.eq(ns.PlainRealm("CAMWOW US2 Realm 3 PvE"), "PvE")
  T.eq(ns.PlainRealm("Ivellos Veren-CAMWOW US2 Realm 3 PvE"), "Ivellos Veren-PvE")
  T.eq(ns.PlainRealm("CAMWOW US2 Realm 1 PvE|Neutral"), "PvE|Neutral")
  T.eq(ns.PlainRealm("Classic Beta PvE 2"), "Classic Beta PvE 2")
end)

T.test("Plain realm data: characters, logs and fields are renamed", function()
  local a, b = "Ivellos Veren-CAMWOW US2 Realm 3 PvE", "Aukshaun Veren-CAMWOW US2 Realm 1 PvE"
  local db = { chars = { [a] = { realm = "CAMWOW US2 Realm 3 PvE" }, [b] = { realm = "CAMWOW US2 Realm 1 PvE" } },
    sales = { { c = a, a = 5 } }, marker = { market = "CAMWOW US2 Realm 1 PvE|Alliance" } }
  ns.PlainRealmData(db)
  T.eq(db.chars["Ivellos Veren-PvE"].realm, "PvE")
  T.eq(db.chars["Aukshaun Veren-PvE"].realm, "PvE")
  T.eq(db.chars[a], nil)
  T.eq(db.sales[1].c, "Ivellos Veren-PvE")
  T.eq(db.marker.market, "PvE|Alliance")
end)

T.test("Plain realm data: two servers' prices become one market, newest first", function()
  local db = { prices = {
    ["CAMWOW US2 Realm 1 PvE|Alliance"] = { [1] = { m = 10, t = 100 }, [2] = { m = 20, t = 300 } },
    ["CAMWOW US2 Realm 3 PvE|Alliance"] = { [1] = { m = 15, t = 200 }, [2] = { m = 25, t = 250 }, [3] = { m = 30, t = 1 } },
  }, history = {
    ["CAMWOW US2 Realm 1 PvE|Alliance"] = { [1] = "1:2:3" },
    ["CAMWOW US2 Realm 3 PvE|Alliance"] = { [1] = "1:2:3|2:3:4" },
  } }
  ns.PlainRealmData(db)
  local market = db.prices["PvE|Alliance"]
  T.eq(market[1].m, 15)
  T.eq(market[2].m, 20)
  T.eq(market[3].m, 30)
  T.eq(db.history["PvE|Alliance"][1], "1:2:3|2:3:4")
  T.eq(db.prices["CAMWOW US2 Realm 1 PvE|Alliance"], nil)
end)

-- Codex review, November 5.
T.test("Plain realm data: two servers' histories keep every day", function()
  local db = { history = {
    ["CAMWOW US2 Realm 1 PvE|Alliance"] = { [1] = "1:10:20|2:11:21" },
    ["CAMWOW US2 Realm 3 PvE|Alliance"] = { [1] = "2:9:19|3:12:22", [2] = "4:1:1" },
  } }
  ns.PlainRealmData(db)
  local market = db.history["PvE|Alliance"]
  T.eq(market[1], "1:10:20|2:9:19|3:12:22", "day 2 from the cheaper, day 3 kept")
  T.eq(market[2], "4:1:1")
end)

T.test("Plain realm data: the same character twice keeps its newest details and all recipes", function()
  local one, three = "Ivellos Veren-CAMWOW US2 Realm 1 PvE", "Ivellos Veren-CAMWOW US2 Realm 3 PvE"
  local db = { chars = {
    [one] = { level = 5, updated = 100, questsDone = { a = true }, profs = { Tailoring = { rank = 10, recipes = { [1] = { n = "old" } } } } },
    [three] = { level = 9, updated = 200, questsDone = { b = true }, profs = { Tailoring = { rank = 40, recipes = { [2] = { n = "new" } } } } },
  } }
  ns.PlainRealmData(db)
  local c = db.chars["Ivellos Veren-PvE"]
  T.eq(c.level, 9)
  T.eq(c.profs.Tailoring.rank, 40)
  T.ok(c.profs.Tailoring.recipes[1] and c.profs.Tailoring.recipes[2], "both recipes")
  T.ok(c.questsDone.a and c.questsDone.b, "both quests")
end)

T.test("Plain realm data: the same bags twice, each part by its own time", function()
  local db = { inventory = {
    ["A-CAMWOW US2 Realm 1 PvE"] = { bags = { [1] = 1 }, bank = { [2] = 2 }, t = 100, bankT = 300 },
    ["A-CAMWOW US2 Realm 3 PvE"] = { bags = { [3] = 3 }, bank = { [4] = 4 }, t = 200, bankT = 100 },
  } }
  ns.PlainRealmData(db)
  local inv = db.inventory["A-PvE"]
  T.eq(inv.t, 200)
  T.eq(inv.bankT, 300)
  T.same(inv.bags, { [3] = 3 })
  T.same(inv.bank, { [2] = 2 })
end)

T.test("Hidden event text: hidden message skipped and counted, other hidden arguments are nil", function()
  local heard, got = 0, nil
  ns:On("FL_TEST_SECRET", function(a, b) heard = heard + 1; got = { a, b } end)
  for _, f in ipairs(T.S.frames) do
    if f.events.FL_TEST_SECRET then
      issecretvalue = function(v) return v == "hidden" end
      f.scripts.OnEvent(f, "FL_TEST_SECRET", "plain", 1, nil)
      f.scripts.OnEvent(f, "FL_TEST_SECRET", "hidden", 1)
      T.eq(heard, 1)
      f.scripts.OnEvent(f, "FL_TEST_SECRET", "plain", "hidden")
      issecretvalue = nil
    end
  end
  T.eq(heard, 2)
  T.eq(got[1], "plain")
  T.eq(got[2], nil)
  T.eq(ns.secretSkipped.FL_TEST_SECRET, 1)
end)
