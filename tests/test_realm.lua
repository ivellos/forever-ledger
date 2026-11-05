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

T.test("Hidden event text: the event is skipped and counted", function()
  local heard = 0
  ns:On("FL_TEST_SECRET", function() heard = heard + 1 end)
  for _, f in ipairs(T.S.frames) do
    if f.events.FL_TEST_SECRET then
      issecretvalue = function(v) return v == "hidden" end
      f.scripts.OnEvent(f, "FL_TEST_SECRET", "plain", 1, nil)
      f.scripts.OnEvent(f, "FL_TEST_SECRET", 1, "hidden")
      issecretvalue = nil
    end
  end
  T.eq(heard, 1)
  T.eq(ns.secretSkipped.FL_TEST_SECRET, 1)
end)
