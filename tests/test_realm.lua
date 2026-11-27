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

-- Gold audit G9, November 9: all-time figures were joined like dated history.
T.test("Plain realm data: two servers' all-time figures combine", function()
  local db = { historyAll = {
    ["CAMWOW US2 Realm 1 PvE|Alliance"] = { [1] = "100:5000:5", [2] = "7:70:1" },
    ["CAMWOW US2 Realm 3 PvE|Alliance"] = { [1] = "120:6000:6", [3] = "9:90:1" },
  } }
  ns.PlainRealmData(db)
  local all = db.historyAll["PvE|Alliance"]
  T.eq(all[1], "100:11000:11", "the lower lowest, sums and days added")
  T.eq(all[2], "7:70:1")
  T.eq(all[3], "9:90:1")
end)

T.test("All-time figures an earlier realm move joined are still read", function()
  local lo, sum, n = ns.ReadAllTime("100:5000:5|120:6000:6")
  T.eq(lo, 100)
  T.eq(sum, 11000)
  T.eq(n, 11)
  T.eq(ns.ReadAllTime(nil), nil)
  local key = ns.MarketKey()
  ns.db.historyAll[key] = ns.db.historyAll[key] or {}
  ns.db.historyAll[key][60101] = "100:5000:5|120:6000:6"
  local low, avg, days = ns:AllTimePrice(60101)
  T.eq(low, 100, "the tooltip's all-time low comes back")
  T.eq(avg, 1000)
  T.eq(days, 11)
  ns.db.historyAll[key][60101] = nil
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

-- November 21: the live game gave an empty realm name (Frank's mage in Felwood), which hid
-- every price and started a second record of the character.
T.test("Empty realm name: the last good one is used", function()
  local oldRead, oldGood = GetRealmName, ns.goodRealm
  local ok, err = pcall(function()
    ns.goodRealm = nil
    ns.db.charRealm[ns.FullName()] = nil
    GetRealmName = function() return "" end
    local saved = ns.db.chars
    ns.db.chars = { ["Someone Else-PvP"] = { realm = "PvP" }, ["Tester-PvE"] = { realm = "PvE" },
      ["Tester-"] = { realm = "" } }
    T.eq(ns.RealmName(), "PvE", "from this character's own record")
    T.eq(ns.MarketKey(), "PvE|Alliance")
    ns.db.chars = saved
    ns.db.charRealm[ns.FullName()] = "PvE"
    T.eq(ns.RealmName(), "PvE", "remembered")
    GetRealmName = function() return "CAMWOW US2 Realm 3 Hardcore" end
    T.eq(ns.RealmName(), "Hardcore", "a real name is read again")
    T.eq(ns.db.charRealm[ns.FullName()], "Hardcore", "and remembered")
    GetRealmName = function() return "" end
    T.eq(ns.RealmName(), "Hardcore", "then kept for the session")
  end)
  GetRealmName, ns.goodRealm = oldRead, oldGood
  ns.db.charRealm[ns.FullName()] = oldGood
  assert(ok, err)
end)

T.test("Empty realm name: data saved meanwhile moves back under the realm", function()
  local me, blank = "Ivellos Veren-PvE", "Ivellos Veren-"
  local db = {
    chars = { [me] = { realm = "PvE", level = 40, updated = 100 }, [blank] = { realm = "", level = 41, updated = 200 } },
    prices = { ["PvE|Alliance"] = { [1] = { m = 10, t = 100 } }, ["|Alliance"] = { [1] = { m = 12, t = 200 }, [2] = { m = 5, t = 200 } } },
    money = { [me] = { [20778] = { loot = 100, vendorSell = 50 } }, [blank] = { [20778] = { loot = 30 }, [20779] = { loot = 7 } } },
    myAuctions = { [blank .. " (neutral)"] = { list = {} } },
    sales = { { c = blank, a = 5 } },
    soldSnap = { market = "|Alliance" },
    itemNames = { [1] = "Pick-" },
  }
  T.ok(ns.HasBlankRealmData(db, "PvE"))
  ns.FixBlankRealm(db, "PvE")
  T.eq(db.chars[blank], nil)
  T.eq(db.chars[me].level, 41, "the newer record")
  T.eq(db.chars[me].realm, "PvE")
  T.eq(db.prices["|Alliance"], nil)
  T.eq(db.prices["PvE|Alliance"][1].m, 12, "the newer price")
  T.eq(db.prices["PvE|Alliance"][2].m, 5)
  T.eq(db.money[me][20778].loot, 130, "the same day's money adds up")
  T.eq(db.money[me][20778].vendorSell, 50)
  T.eq(db.money[me][20779].loot, 7)
  T.ok(db.myAuctions["Ivellos Veren-PvE (neutral)"], "the neutral auctions list")
  T.eq(db.sales[1].c, me)
  T.eq(db.soldSnap.market, "PvE|Alliance")
  T.eq(db.itemNames[1], "Pick-", "only your characters' names")
  T.eq(ns.HasBlankRealmData(db, "PvE"), false)
end)

-- Codex review, November 21: characters on two rulesets.
T.test("Empty realm name: another character goes back to its own realm, not the logged-in one's", function()
  local other, blank = "Other Person-Hardcore", "Other Person-"
  local db = {
    chars = { ["Ivellos Veren-PvE"] = { realm = "PvE", faction = "Alliance", updated = 5 },
      [other] = { realm = "Hardcore", faction = "Alliance", updated = 1, level = 20 },
      [blank] = { realm = "", updated = 2, level = 21 } },
    money = { [blank] = { [123] = { loot = 50 } } },
    sales = { { c = blank, a = 5 } },
    prices = { ["|Alliance"] = { [1] = { m = 12, t = 200 } } },
  }
  T.ok(ns.HasBlankRealmData(db, "PvE"))
  ns.FixBlankRealm(db, "PvE")
  T.eq(db.chars["Other Person-PvE"], nil, "not moved to the logged-in character's realm")
  T.eq(db.chars[blank], nil)
  T.eq(db.chars[other].level, 21, "joined its own record")
  T.eq(db.chars[other].realm, "Hardcore")
  T.eq(db.money[other][123].loot, 50)
  T.eq(db.sales[1].c, other)
  T.ok(db.prices["|Alliance"], "Alliance characters on two rulesets: the market stays as it is")
  T.eq(db.prices["PvE|Alliance"], nil, "and isn't mixed into either")
  T.eq(ns.HasBlankRealmData(db, "PvE"), false, "nothing left that can be placed")
end)

T.test("Empty realm name: the remembered realm places a character, an unknown one waits", function()
  local db = {
    chars = { ["Other Person-"] = { realm = "", updated = 2 }, ["Stranger Person-"] = { realm = "", updated = 3 } },
    charRealm = { ["Other Person"] = "Hardcore" },
    money = { ["Other Person-"] = { [123] = { loot = 50 } }, ["Stranger Person-"] = { [123] = { loot = 9 } } },
  }
  ns.FixBlankRealm(db, "PvE")
  T.eq(db.chars["Other Person-Hardcore"].realm, "Hardcore", "from charRealm")
  T.eq(db.money["Other Person-Hardcore"][123].loot, 50)
  T.ok(db.chars["Stranger Person-"], "unknown realm: left until it logs in")
  T.eq(db.money["Stranger Person-"][123].loot, 9)
end)

T.test("Empty realm name: synced data is placed by both sides' records", function()
  local mine = { chars = { ["Other Person-Hardcore"] = { realm = "Hardcore", updated = 1 } } }
  local data = { chars = { ["Other Person-"] = { realm = "", updated = 2, level = 30 } },
    sales = { { c = "Other Person-", a = 1 } } }
  T.ok(ns.HasBlankRealmData(data, "PvE", mine))
  ns.FixBlankRealm(data, "PvE", mine)
  T.eq(data.chars["Other Person-Hardcore"].level, 30)
  T.eq(data.sales[1].c, "Other Person-Hardcore")
end)

-- Codex review, November 21: markets went by already-known characters only.
T.test("Empty realm name: a side's prices stay put when its characters are on two rulesets", function()
  local me = ns.FullName()
  local db = {
    chars = { [me .. "-"] = { realm = "", faction = "Alliance" }, ["Other Person-Hardcore"] = { realm = "Hardcore", faction = "Alliance" } },
    prices = { ["|Alliance"] = { [2589] = { m = 123, t = 1 } } },
    history = { ["|Alliance"] = { [2589] = "20778:123:123" } },
  }
  ns.FixBlankRealm(db, "PvE")
  T.ok(db.chars[me .. "-PvE"], "the logged-in character is placed")
  T.eq(db.prices["Hardcore|Alliance"], nil, "prices not moved to Hardcore")
  T.eq(db.history["Hardcore|Alliance"], nil, "nor the history")
  T.ok(db.prices["|Alliance"] and db.history["|Alliance"], "they stay where they are")
end)

T.test("Empty realm name: a remembered alt on another ruleset makes its side ambiguous too", function()
  local db = {
    chars = { ["Main Person-PvE"] = { realm = "PvE", faction = "Alliance" }, ["Other Person-"] = { realm = "", faction = "Alliance" } },
    charRealm = { ["Other Person"] = "Hardcore" },
    prices = { ["|Alliance"] = { [2589] = { m = 123, t = 1 } } },
  }
  ns.FixBlankRealm(db, "PvE")
  T.ok(db.chars["Other Person-Hardcore"], "the alt goes to Hardcore")
  T.eq(db.prices["PvE|Alliance"], nil, "its prices aren't mixed into PvE")
  T.ok(db.prices["|Alliance"])
  -- The same through sync: the receiver remembers the alt.
  local mine = { chars = { ["Main Person-PvE"] = { realm = "PvE", faction = "Alliance" } }, charRealm = { ["Other Person"] = "Hardcore" } }
  local data = { chars = { ["Other Person-"] = { realm = "", faction = "Alliance" } }, prices = { ["|Alliance"] = { [2589] = { m = 9, t = 1 } } } }
  ns.FixBlankRealm(data, "PvE", mine)
  T.ok(data.chars["Other Person-Hardcore"])
  T.eq(data.prices["PvE|Alliance"], nil, "sync: not mixed into PvE either")
end)

T.test("Empty realm name: one ruleset, its side's prices go back", function()
  local me = ns.FullName()
  local db = {
    chars = { [me .. "-"] = { realm = "", faction = "Alliance" }, ["Bank Person-PvE"] = { realm = "PvE", faction = "Alliance" } },
    prices = { ["|Alliance"] = { [2589] = { m = 123, t = 1 } } },
  }
  ns.FixBlankRealm(db, "PvE")
  T.eq(db.prices["PvE|Alliance"][2589].m, 123)
  T.eq(db.prices["|Alliance"], nil)
end)

T.test("Hidden unit text: Readable gives nil for a hidden value, the string otherwise", function()
  issecretvalue = function(v) return v == "Creature-0-1-2-3-4-5" end
  T.eq(ns.Readable("Creature-0-1-2-3-4-5"), nil)
  T.eq(ns.Readable("Creature-0-1-2-3-4-6"), "Creature-0-1-2-3-4-6")
  T.eq(ns.Readable(nil), nil)
  T.eq(ns.Readable(12), nil)
  issecretvalue = nil
  T.eq(ns.Readable("Creature-0-1-2-3-4-5"), "Creature-0-1-2-3-4-5")
end)

-- Frank's BugSack, November 26: "attempt to perform string conversion on a secret string
-- value", 27 times, no stack. Hidden item links and tooltip text are read as nothing.
T.test("Hidden links: no item, no version, nothing learned", function()
  local link = "|cff1eff00|Hitem:2589::::::::20:::::::::|h[Linen Cloth]|h|r"
  issecretvalue = function(v) return v == link end
  local ok, id = pcall(ns.ItemIDFromLink, link)
  T.ok(ok, "no error")
  T.eq(id, nil)
  T.eq(#ns.LinkBonusIDs(link), 0)
  T.eq(ns:VersionOfLink(2589, link), nil)
  T.ok(pcall(ns.LearnVersionName, ns, 2589, 1234, link), "no error learning a version")
  issecretvalue = nil
  T.eq(ns.ItemIDFromLink(link), 2589)
end)
