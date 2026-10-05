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
