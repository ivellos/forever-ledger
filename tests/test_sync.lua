-- What live sync merges and takes out again (Core.lua ns:MergeData with a partner's
-- name, ns:IsOwnChar, ns:RemoveCharacter, ns:RemoveSyncedFrom). Owner's test, October 5:
-- a partner's characters stayed after pairing, with no way to remove them.
local T = ...
local ns = T.ns

local function char(name, updated) return { name = name, realm = "Testrealm", faction = "Alliance", updated = updated, profs = {} } end

T.test("A partner's characters arrive marked with the partner's name", function()
  ns:MergeData({ chars = { ["Regoril Bastiane-Testrealm"] = char("Regoril Bastiane", 100) } }, "Regoril Bastiane")
  T.eq(ns.db.chars["Regoril Bastiane-Testrealm"].via, "Regoril Bastiane")
end)

T.test("A partner never replaces a character played on this account", function()
  local me = ns.CharKey()
  ns.db.chars[me] = char("Tester", 100)
  ns.db.inventory["Alt-Testrealm"] = { bags = {}, bank = {}, t = 50 }
  ns.db.chars["Alt-Testrealm"] = char("Alt", 50)
  ns:MergeData({ chars = { [me] = char("Tester", 999), ["Alt-Testrealm"] = char("Alt", 999) } }, "Regoril Bastiane")
  T.eq(ns.db.chars[me].updated, 100, "the one you're on")
  T.eq(ns.db.chars["Alt-Testrealm"].updated, 50, "an alt with bags saved here")
  T.eq(ns.db.chars["Alt-Testrealm"].via, nil)
end)

T.test("Characters that came before marking get marked on the next sync", function()
  ns.db.chars["Old Friend-Testrealm"] = char("Old Friend", 200)
  ns:MergeData({ chars = { ["Old Friend-Testrealm"] = char("Old Friend", 200) } }, "Old Friend")
  T.eq(ns.db.chars["Old Friend-Testrealm"].via, "Old Friend")
end)

T.test("Bags come only from sync, marked, and never over your own", function()
  ns.db.inventory["Mine-Testrealm"] = { bags = { [2589] = 5 }, bank = {}, t = 10 }
  ns:MergeData({ inventory = {
    ["Regoril Bastiane-Testrealm"] = { bags = { [2589] = 20 }, bank = {}, t = 300 },
    ["Mine-Testrealm"] = { bags = { [2589] = 99 }, bank = {}, t = 999 },
  } }, "Regoril Bastiane")
  T.eq(ns.db.inventory["Regoril Bastiane-Testrealm"].via, "Regoril Bastiane")
  T.eq(ns.db.inventory["Mine-Testrealm"].bags[2589], 5, "yours kept")
  -- An import (no partner) brings no bags.
  ns:MergeData({ inventory = { ["Stranger-Testrealm"] = { bags = {}, bank = {}, t = 1 } } })
  T.eq(ns.db.inventory["Stranger-Testrealm"], nil)
end)

T.test("Unpairing removes the partner's characters and bags, and keeps prices", function()
  ns.db.prices["Testrealm|Alliance"] = ns.db.prices["Testrealm|Alliance"] or {}
  ns:MergeData({
    chars = { ["Regoril Bastiane-Testrealm"] = char("Regoril Bastiane", 400), ["Second Alt-Testrealm"] = char("Second Alt", 400) },
    inventory = { ["Regoril Bastiane-Testrealm"] = { bags = {}, bank = {}, t = 400 } },
    prices = { ["Testrealm|Alliance"] = { [2589] = { m = 12, t = 400 } } },
  }, "Regoril Bastiane")
  local n = ns:RemoveSyncedFrom("regoril bastiane")
  T.eq(n, 2, "both characters")
  T.eq(ns.db.chars["Regoril Bastiane-Testrealm"], nil)
  T.eq(ns.db.chars["Second Alt-Testrealm"], nil)
  T.eq(ns.db.inventory["Regoril Bastiane-Testrealm"], nil)
  T.eq(ns.db.prices["Testrealm|Alliance"][2589].m, 12, "price kept")
  T.ok(ns.db.chars["Old Friend-Testrealm"], "another partner's character stays")
end)

local PARTNER = "Regoril Bastiane-Testrealm"
local function partnerChar()
  ns.db.chars[PARTNER] = char("Regoril Bastiane", 500)
  ns.db.chars[PARTNER].via = "Regoril Bastiane"
end

T.test("Books: your characters' gold, money and logs from a time on, not a partner's", function()
  local me = ns.CharKey()
  ns.db.chars[me] = char("Tester", 100)
  partnerChar()
  local hour, day = 500000, ns.LocalDay(500000 * 3600)
  ns.db.gold[me] = { [hour - 100] = 1, [hour] = 2 }
  ns.db.gold[PARTNER] = { [hour] = 9 }
  ns.db.money[me] = { [day - 2] = { quest = 1 }, [day] = { quest = 2 } }
  ns.db.sales = { { t = hour * 3600 - 9999, c = me, a = 1 }, { t = hour * 3600, c = me, a = 2 }, { t = hour * 3600, c = PARTNER, a = 3 } }
  ns.db.sessions = { { t = 1, kind = "shuffle" } }
  ns.db.ledgerMonths = { { t = 1, c = me, k = "sale", a = 5 } }
  local b = ns:BooksSince(hour * 3600)
  T.eq(b.chars[me].gold[hour], 2)
  T.eq(b.chars[me].gold[hour - 100], nil)
  T.eq(b.chars[me].money[day].quest, 2)
  T.eq(b.chars[me].money[day - 2], nil)
  T.eq(b.chars[PARTNER], nil)
  T.eq(#b.sales, 1)
  T.eq(b.months, nil, "monthly totals only with everything")
  T.eq(#ns:BooksSince(0).months, 1)
end)

T.test("Books: a partner's stretch is replaced, so sending twice counts once", function()
  local me = ns.CharKey()
  ns.db.chars[me] = char("Tester", 100)
  partnerChar()
  ns.db.gold, ns.db.money = {}, {}
  ns.db.sales = { { t = 50, c = PARTNER, a = 1 }, { t = 150, c = PARTNER, a = 2 }, { t = 160, c = me, a = 3 } }
  local mine = ns.db.sales
  local books = { from = 100, chars = { [PARTNER] = { gold = { [7] = 70 }, money = { [3] = { quest = 4 } } } },
    sales = { { t = 150, c = PARTNER, a = 20 }, { t = 170, c = PARTNER, a = 30 } } }
  T.eq(ns:MergeBooks(books), 1)
  ns:MergeBooks(books)
  T.eq(ns.db.sales, mine, "the same table")
  T.eq(#ns.db.sales, 4)
  T.eq(ns.db.sales[1].a, 1, "before the stretch: kept")
  T.eq(ns.db.sales[2].a, 20, "changed")
  T.eq(ns.db.sales[3].a, 3, "yours kept, in time order")
  T.eq(ns.db.sales[4].a, 30, "new")
  T.eq(ns.db.gold[PARTNER][7], 70)
  T.eq(ns.db.money[PARTNER][3].quest, 4)
end)

T.test("Books: a partner never touches a character played on this account", function()
  local me = ns.CharKey()
  ns.db.gold[me], ns.db.sales = { [7] = 1 }, { { t = 5, c = me, a = 1 } }
  T.eq(ns:MergeBooks({ from = 0, chars = { [me] = { gold = { [7] = 99 } } }, sales = {} }), 0)
  T.eq(ns.db.gold[me][7], 1)
  T.eq(#ns.db.sales, 1)
end)

T.test("Books: come through a partner's sync only, and go with unpairing", function()
  partnerChar()
  ns.db.gold, ns.db.money = {}, {}
  ns.db.sales, ns.db.ledgerMonths = {}, {}
  local books = { from = 0, chars = { [PARTNER] = { gold = { [7] = 70 } } }, sales = { { t = 1, c = PARTNER, a = 1 } },
    months = { { t = 1, c = PARTNER, k = "sale", a = 1 } } }
  ns:MergeData({ books = books })
  T.eq(ns.db.gold[PARTNER], nil, "an import brings none")
  local _, _, _, _, n = ns:MergeData({ books = books }, "Regoril Bastiane")
  T.eq(n, 1)
  T.eq(#ns.db.ledgerMonths, 1)
  ns:RemoveSyncedFrom("Regoril Bastiane")
  T.eq(ns.db.gold[PARTNER], nil)
  T.eq(#ns.db.sales, 0)
  T.eq(#ns.db.ledgerMonths, 0)
end)

-- Codex review, November 5.
T.test("Books: a full send replaces gold and money the sender has folded", function()
  partnerChar()
  ns.db.gold[PARTNER] = { [10] = 1, [11] = 2 }
  ns.db.money[PARTNER] = { [100] = { quest = 100 }, [101] = { quest = 50 } }
  ns:MergeBooks({ from = 0, chars = { [PARTNER] = { gold = { [11] = 2 }, money = { [100] = { quest = 150 } } } } })
  T.eq(ns.db.gold[PARTNER][10], nil)
  T.eq(ns.db.money[PARTNER][100].quest, 150)
  T.eq(ns.db.money[PARTNER][101], nil, "not counted twice")
end)

T.test("Books: a later stretch leaves older gold and money", function()
  partnerChar()
  local hour = 500000
  local day = ns.LocalDay(hour * 3600)
  ns.db.gold[PARTNER] = { [hour - 100] = 1, [hour] = 2 }
  ns.db.money[PARTNER] = { [day - 5] = { quest = 1 }, [day] = { quest = 2 } }
  ns:MergeBooks({ from = hour * 3600, chars = { [PARTNER] = { gold = { [hour] = 3 }, money = { [day] = { quest = 3 } } } } })
  T.eq(ns.db.gold[PARTNER][hour - 100], 1)
  T.eq(ns.db.gold[PARTNER][hour], 3)
  T.eq(ns.db.money[PARTNER][day - 5].quest, 1)
  T.eq(ns.db.money[PARTNER][day].quest, 3)
end)

T.test("Books: a long session goes when it ends, once", function()
  local me = ns.CharKey()
  ns.db.chars[me] = char("Tester", 100)
  partnerChar()
  ns.db.sessions = { { c = me, t = 1000, stop = 5000 } }
  T.eq(#ns:BooksSince(4700).sessions, 1)
  ns.db.sessions = { { c = PARTNER, t = 1000, stop = 5000, secs = 1 } }
  ns:MergeBooks({ from = 4700, chars = { [PARTNER] = {} }, sessions = { { c = PARTNER, t = 1000, stop = 5000, secs = 2 } } })
  T.eq(#ns.db.sessions, 1)
  T.eq(ns.db.sessions[1].secs, 2)
end)

T.test("Books: a partner's go with unpairing even after their character was removed", function()
  partnerChar()
  ns.db.gold, ns.db.money, ns.db.sales = {}, {}, {}
  ns:MergeData({ books = { from = 0, chars = { [PARTNER] = { gold = { [7] = 70 } } }, sales = { { t = 1, c = PARTNER, a = 1 } } } }, "Regoril Bastiane")
  T.eq(ns.db.gold[PARTNER][7], 70)
  ns:RemoveCharacter(PARTNER)
  T.eq(ns.db.gold[PARTNER][7], 70, "removing a character keeps its history")
  ns:RemoveSyncedFrom("Regoril Bastiane")
  T.eq(ns.db.gold[PARTNER], nil)
  T.eq(#ns.db.sales, 0)
  T.eq(ns.db.booksFrom[PARTNER], nil)
end)

T.test("Remove never takes the character you're on", function()
  local me = ns.CharKey()
  ns.db.chars[me] = char("Tester", 100)
  T.eq(ns:RemoveCharacter(me), false)
  T.ok(ns.db.chars[me])
  T.eq(ns:RemoveCharacter("Old Friend-Testrealm"), true)
  T.eq(ns.db.chars["Old Friend-Testrealm"], nil)
end)

-- Codex review, October 5.
T.test("A partner's character you then play is yours: unpairing keeps it", function()
  local me = ns.CharKey()
  ns.db.chars[me] = nil
  ns.db.inventory[me] = nil
  ns:MergeData({ chars = { [me] = char("Tester", 500) }, inventory = { [me] = { bags = { [2589] = 3 }, bank = {}, t = 500 } } }, "Partner Name")
  -- (it was the one you're on, so it was kept as yours already; now one that isn't)
  ns:MergeData({ chars = { ["Played Later-Testrealm"] = char("Played Later", 500) },
    inventory = { ["Played Later-Testrealm"] = { bags = {}, bank = {}, t = 500 } } }, "Partner Name")
  T.eq(ns.db.chars["Played Later-Testrealm"].via, "Partner Name")
  -- Logging in on it: Inventory.lua saves its bags as this account's.
  local realKey = ns.CharKey
  ns.CharKey = function() return "Played Later-Testrealm" end
  T.fire("BAG_UPDATE_DELAYED")
  T.runTimers()
  ns.CharKey = realKey
  T.eq(ns.db.inventory["Played Later-Testrealm"].via, nil, "bags now this account's")
  T.eq(ns.db.chars["Played Later-Testrealm"].via, nil, "character now this account's")
  ns:RemoveSyncedFrom("Partner Name")
  T.ok(ns.db.chars["Played Later-Testrealm"], "kept after unpairing")
end)

T.test("Bags and bank merge by their own times", function()
  ns.db.inventory["Split-Testrealm"] = { bags = { [2589] = 1 }, bank = { [2589] = 50 }, t = 100, bankT = 200, via = "Partner Name" }
  ns:MergeData({ inventory = { ["Split-Testrealm"] = { bags = { [2589] = 8 }, bank = { [2589] = 40 }, t = 150, bankT = 120 } } }, "Partner Name")
  local inv = ns.db.inventory["Split-Testrealm"]
  T.eq(inv.bags[2589], 8, "newer bags taken")
  T.eq(inv.bank[2589], 50, "older bank not taken over the newer one")
  T.eq(inv.bankT, 200)
end)
