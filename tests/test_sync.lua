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
