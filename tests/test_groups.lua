-- Groups.lua: built-in groups sorted by the game's item types, profession and special
-- groups, your own groups, and the rules (redesign build step 2, November 15).
local T = ...
local ns = T.ns
local S = T.S

-- What C_Item.GetItemInfoInstant gives: class and subclass (Forever's own item data,
-- read November 15: Linen Cloth 7/5, Coarse Thread 7/5, Peacebloom 7/9, Tigerseye 7/11,
-- Pattern: Red Woolen Bag 9/2, Fishing Pole 2/20, Ornate Bronze Lockbox 15/0).
local CLOTH, THREAD, HERB, OTHERMAT, POTION, RECIPE, PET, UNKNOWN, BAG, GRAY, CRATEMAT =
  97601, 97602, 97603, 97604, 97605, 97606, 97607, 97608, 97609, 97610, 97611
local GEM, POLE, LOCKBOX = 818, 6256, 4632
local types = {
  [CLOTH] = { 7, 5 }, [THREAD] = { 7, 5 }, [HERB] = { 7, 9 }, [OTHERMAT] = { 7, 11 }, [GEM] = { 7, 11 },
  [POTION] = { 0, 1 }, [RECIPE] = { 9, 2 }, [PET] = { 15, 2 }, [POLE] = { 2, 20 }, [LOCKBOX] = { 15, 0 },
  [BAG] = { 1, 0 }, [GRAY] = { 15, 0 }, [CRATEMAT] = { 7, 6 },
}
GetItemInfoInstant = function(id)
  local t = types[id]
  if not t then return end
  return id, "", "", "", 0, t[1], t[2]
end
S.items[GRAY] = { name = "Test Broken Thing", quality = 0 }
S.items[CRATEMAT] = { name = "Test Crate Leather", quality = 1 }

local function has(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

T.test("Groups: saved data starts empty under schema 9 (now 13)", function()
  T.eq(ns.db.schema, 13)
  for _, k in ipairs({ "user", "added", "removed", "rules", "saved" }) do T.eq(type(ns.db.groups[k]), "table", k) end
  T.eq(ns.db.groups.nextId, 1)
end)

T.test("Groups: items sort themselves by the game's item type, hand lists first", function()
  T.eq(ns.NaturalGroup(CLOTH), "mat.cloth")
  T.eq(ns.NaturalGroup(THREAD), "mat.cloth")
  T.eq(ns.NaturalGroup(HERB), "mat.herb")
  T.eq(ns.NaturalGroup(GEM), "mat.gems", "a gem isn't Other materials")
  T.eq(ns.NaturalGroup(OTHERMAT), "mat.other")
  T.eq(ns.NaturalGroup(POTION), "con.potion")
  T.eq(ns.NaturalGroup(RECIPE), "rec.tailoring")
  T.eq(ns.NaturalGroup(PET), "pets")
  T.eq(ns.NaturalGroup(POLE), "fishing", "a fishing pole isn't a weapon here")
  T.eq(ns.NaturalGroup(LOCKBOX), "lockbox")
  T.eq(ns.NaturalGroup(BAG), "bags")
  T.eq(ns.NaturalGroup(UNKNOWN), "misc")
end)

T.test("Groups: a group counts the groups under it; ticked groups add together", function()
  T.ok(ns:GroupHas("mat.cloth", CLOTH))
  T.ok(ns:GroupHas("mat", CLOTH), "Materials holds Cloth's items")
  T.ok(not ns:GroupHas("con", CLOTH))
  T.ok(ns:GroupHas("all", UNKNOWN))
  local got = ns:GroupFilter({ "mat.cloth", "con.potion" }, { CLOTH, HERB, POTION, RECIPE })
  T.same(got, { CLOTH, POTION })
  T.same(ns:GroupFilter({}, { CLOTH, HERB }), { CLOTH, HERB }, "no groups ticked: everything")
end)

T.test("Groups: the tree lists built-in, special, profession and your groups", function()
  ns.db.recipeBook = { Tailoring = { [1] = { n = "Test Bag", out = BAG, r = { { CLOTH, 2 } } } } }
  ns:ForgetProfessionGroups()
  local gid = ns:NewGroup("Cooking mats")
  local sub = ns:NewGroup("Spices", gid)
  local tree = ns:GroupTree()
  local at = {}
  for i, g in ipairs(tree) do at[g.id] = { i = i, depth = g.depth, kind = g.kind } end
  T.eq(at["mat"].depth, 0); T.eq(at["mat.cloth"].depth, 1)
  T.ok(at["mat"].i < at["mat.cloth"].i and at["mat.cloth"].i < at["con"].i, "children right under their parent")
  T.eq(at["watched"].kind, "special"); T.eq(at["gray"].kind, "special")
  T.eq(at["prof:Tailoring:mats"].kind, "profession")
  T.eq(at[gid].kind, "user"); T.eq(at[sub].depth, 1)
  T.eq(ns:GroupInfo("prof:Tailoring:mats").name, "Tailoring materials")
  T.eq(ns:GroupInfo("prof:Tailoring:crafts").name, "Tailoring crafts")
end)

T.test("Groups: an item's groups, most specific first", function()
  ns.db.recipeBook = { Tailoring = { [1] = { n = "Test Bag", out = BAG, r = { { CLOTH, 2 } } } } }
  ns:ForgetProfessionGroups()
  local mine = ns:NewGroup("My cloth")
  local deeper = ns:NewGroup("My silk", mine)
  ns:AddToGroup(mine, CLOTH); ns:AddToGroup(deeper, CLOTH)
  ns.db.watchItems[CLOTH] = { t = 1 }
  local g = ns:ItemGroups(CLOTH)
  T.same(g, { deeper, mine, "watched", "prof:Tailoring:mats", "mat.cloth" })
  T.ok(has(ns:ItemGroups(BAG), "prof:Tailoring:crafts"))
  T.ok(has(ns:ItemGroups(GRAY), "gray"), "poor quality is Gray items")
  T.ok(ns:GroupHas(mine, CLOTH))
end)

T.test("Groups: taking an item out of a built-in group, putting it back, restoring", function()
  ns:RemoveFromGroup("mat.cloth", CLOTH)
  T.ok(not ns:GroupHas("mat.cloth", CLOTH), "out of Cloth")
  T.ok(ns:GroupHas("mat", CLOTH), "still under Materials")
  ns:AddToGroup("mat.cloth", CLOTH)
  T.ok(ns:GroupHas("mat.cloth", CLOTH), "back in")
  T.eq(ns.db.groups.removed["mat.cloth"], nil, "no leftover removal")
  T.eq(ns.db.groups.added["mat.cloth"], nil, "putting it back isn't an addition")
  ns:AddToGroup("con.potion", CLOTH)
  T.ok(ns:GroupHas("con.potion", CLOTH) and ns:GroupHas("mat.cloth", CLOTH), "in both")
  ns:RemoveFromGroup("mat.herb", HERB)
  ns:SetGroupRule("mat.herb", "post", "off")
  local added, removed, rules = ns:BuiltinChanges()
  T.eq(added, 1); T.eq(removed, 1); T.eq(rules, 1)
  T.ok(ns:RestoreGroupItems("con.potion"))
  T.ok(not ns:GroupHas("con.potion", CLOTH))
  local mine = ns:NewGroup("Kept")
  ns:SaveRule("Mine", "post", { floorPct = 50 })
  ns:RestoreBuiltinGroups()
  added, removed, rules = ns:BuiltinChanges()
  T.eq(added + removed + rules, 0)
  T.ok(ns:GroupHas("mat.herb", HERB))
  T.ok(ns.db.groups.user[mine], "your groups stay")
  T.ok(next(ns.db.groups.saved), "saved rules stay")
end)

T.test("Groups: items in crate bundles are in Crates and writs", function()
  ns.db.crates[97690] = { name = "Test Crate", bundles = { { { 20, "Test Crate Leather" } } } }
  T.ok(has(ns:ItemGroups(CRATEMAT), "crates"))
  T.ok(not has(ns:ItemGroups(CLOTH), "crates"))
end)

T.test("Rules: Forever Ledger's default until something sets one", function()
  local f, from = ns:RuleFor(CLOTH, "post")
  T.same(f, ns.RULE_DEFAULTS.post); T.eq(from, "Default")
  T.eq(ns:RuleFor(CLOTH, "nonsense"), nil)
end)

T.test("Rules: a sub-group follows the group above; changed here and off", function()
  T.ok(ns:SetGroupRule("mat", "post", { floorPct = 60 }))
  local f, from, gid = ns:RuleFor(CLOTH, "post")
  T.eq(f.floorPct, 60); T.eq(f.undercut, 0, "the rest from the default"); T.eq(from, "Materials, changed here"); T.eq(gid, "mat")
  T.ok(ns:SetGroupRule("mat.cloth", "post", "off"))
  f, from = ns:RuleFor(CLOTH, "post")
  T.eq(f, nil); T.eq(from, "Off (Cloth)")
  T.ok(ns:SetGroupRule("mat.cloth", "post", "default"))
  f, from = ns:RuleFor(CLOTH, "post")
  T.same(f, ns.RULE_DEFAULTS.post); T.eq(from, "Default (Cloth)")
  T.ok(ns:SetGroupRule("mat.cloth", "post", "parent"))
  T.eq(ns:GroupRuleSetting("mat.cloth", "post"), nil)
  T.eq((ns:RuleFor(CLOTH, "post")).floorPct, 60, "back to Materials'")
  T.eq((ns:RuleFor(HERB, "buy")).underPct, 80, "other kinds untouched")
end)

T.test("Rules: your rule shared by groups; deleting it sends them back", function()
  local rid = ns:SaveRule("Cheap mats", "buy", { underPct = 70 })
  T.ok(ns:SetGroupRule("mat.cloth", "buy", "rule:" .. rid))
  T.ok(ns:SetGroupRule("mat.herb", "buy", "rule:" .. rid))
  T.ok(not ns:SetGroupRule("mat.herb", "post", "rule:" .. rid), "a buy rule can't be a post rule")
  T.ok(not ns:SetGroupRule("mat.herb", "buy", "rule:nope"))
  local f, from = ns:RuleFor(HERB, "buy")
  T.eq(f.underPct, 70); T.eq(f.maxQty, 200); T.eq(from, "Your rule Cheap mats (Herbs)")
  T.same(ns:RuleUsers(rid), { "mat.cloth", "mat.herb" })
  ns:UpdateRule(rid, { underPct = 65 })
  T.eq((ns:RuleFor(CLOTH, "buy")).underPct, 65, "one change reaches every group")
  T.ok(ns:DeleteRule(rid))
  T.eq(ns:GroupRuleSetting("mat.cloth", "buy"), nil)
  T.eq((ns:RuleFor(CLOTH, "buy")).underPct, 80)
end)

T.test("Rules: your group wins, then a profession group, then built in", function()
  ns.db.recipeBook = { Tailoring = { [1] = { n = "Test Bag", out = BAG, r = { { CLOTH, 2 } } } } }
  ns:ForgetProfessionGroups()
  ns:SetGroupRule("mat.cloth", "post", { floorPct = 40 })
  ns:SetGroupRule("prof:Tailoring:mats", "post", { floorPct = 50 })
  T.eq((ns:RuleFor(CLOTH, "post")).floorPct, 50, "profession over built in")
  local mine = ns:NewGroup("Mine")
  ns:AddToGroup(mine, CLOTH)
  T.eq((ns:RuleFor(CLOTH, "post")).floorPct, 50, "your group with no rule claims nothing")
  ns:SetGroupRule(mine, "post", { floorPct = 90 })
  local f, from = ns:RuleFor(CLOTH, "post")
  T.eq(f.floorPct, 90); T.eq(from, "Mine, changed here")
  local sub = ns:NewGroup("Sub", mine)
  ns:AddToGroup(sub, CLOTH)
  T.eq((ns:RuleFor(CLOTH, "post")).floorPct, 90, "a sub-group follows yours")
end)

T.test("Groups: deleting your group moves its sub-groups up and drops its rules", function()
  local top = ns:NewGroup("Top")
  local mid = ns:NewGroup("Mid", top)
  local low = ns:NewGroup("Low", mid)
  ns:SetGroupRule(mid, "post", "off")
  T.ok(ns:DeleteGroup(mid))
  T.eq(ns.db.groups.user[low].parent, top)
  T.eq(ns.db.groups.rules[mid], nil)
  T.ok(not ns:DeleteGroup("mat"), "built-in groups can't be deleted")
  T.eq(ns:NewGroup("   "), nil, "a group needs a name")
  T.ok(not ns:AddToGroup("prof:Tailoring:mats", HERB), "profession groups aren't changed by hand")
  T.ok(not ns:SetGroupRule("nope", "post", "off"))
end)

-- Codex review, November 15 (two P2s).
T.test("Groups: out of a parent group means out of its sub-groups too", function()
  ns:SetGroupRule("mat.cloth", "post", "parent")   -- (an earlier test changed Cloth's)
  ns:SetGroupRule("mat", "post", "off")
  local _, from = ns:RuleFor(THREAD, "post")
  T.eq(from, "Off (Materials)")
  T.ok(not ns:RemoveFromGroup("con", THREAD), "not in Consumables: nothing to take out")
  T.ok(ns:RemoveFromGroup("mat", THREAD))
  T.ok(not ns:GroupHas("mat", THREAD), "out of Materials")
  T.ok(not ns:GroupHas("mat.cloth", THREAD), "and so out of Cloth")
  T.same(ns:GroupFilter({ "mat" }, { THREAD, HERB }), { HERB })
  _, from = ns:RuleFor(THREAD, "post")
  T.eq(from, "Default", "Materials' rule no longer applies")
  T.ok(ns:AddToGroup("mat", THREAD))
  T.ok(ns:GroupHas("mat.cloth", THREAD), "back where it was")
  T.eq(ns.db.groups.removed.mat, nil)
  ns:SetGroupRule("mat", "post", "parent")
end)

T.test("Groups: a captured recipe replaces ForeverCrafts' row in profession groups", function()
  local OLDMAT, NEWMAT, OTHER, OUT1, OUT2, OUT3 = 97620, 97621, 97622, 97623, 97624, 97625
  local saved = ns.FOREVER_CRAFTS
  ns.FOREVER_CRAFTS = {
    { id = 555, prof = "Tailoring", out = OUT1, r = { { OLDMAT, 1 } } },
    { id = 556, prof = "Tailoring", out = OUT3, r = { { OTHER, 1 } } },
  }
  ns.db.recipeBook = { Tailoring = { [555] = { n = "Test Robe", out = OUT2, r = { { NEWMAT, 1 } } } } }
  ns.recipeBookStamp = (ns.recipeBookStamp or 0) + 1   -- as RecipeBook.lua does after a capture
  T.ok(not ns:GroupHas("prof:Tailoring:mats", OLDMAT), "the replaced row's material is gone")
  T.ok(ns:GroupHas("prof:Tailoring:mats", NEWMAT))
  T.ok(ns:GroupHas("prof:Tailoring:mats", OTHER), "a different recipe stays")
  T.ok(not ns:GroupHas("prof:Tailoring:crafts", OUT1))
  T.ok(ns:GroupHas("prof:Tailoring:crafts", OUT2))
  T.ok(ns:GroupHas("prof:Tailoring:crafts", OUT3))
  ns:SetGroupRule("prof:Tailoring:mats", "post", "off")
  T.eq(select(2, ns:RuleFor(OLDMAT, "post")), "Default")
  ns:SetGroupRule("prof:Tailoring:mats", "post", "parent")
  ns.FOREVER_CRAFTS = saved
  ns.recipeBookStamp = ns.recipeBookStamp + 1
end)

T.test("Groups: an item added to a sub-group leaves it when taken out of the group above", function()
  ns:AddToGroup("con.potion", HERB)
  T.ok(ns:GroupHas("con", HERB))
  ns:SetGroupRule("con", "post", "off")
  T.eq(select(2, ns:RuleFor(HERB, "post")), "Off (Consumables)")
  T.ok(ns:RemoveFromGroup("con", HERB))
  T.ok(not ns:GroupHas("con", HERB))
  T.ok(not ns:GroupHas("con.potion", HERB))
  T.same(ns:GroupFilter({ "con" }, { HERB }), {})
  T.eq(select(2, ns:RuleFor(HERB, "post")), "Default")
  T.ok(ns:GroupHas("mat.herb", HERB), "still in its own group")
  T.ok(ns:AddToGroup("con", HERB))
  T.ok(ns:GroupHas("con.potion", HERB), "back in the group it was added to")
  ns:SetGroupRule("con", "post", "parent")
  ns:RemoveFromGroup("con.potion", HERB)
  T.ok(not ns:GroupHas("con", HERB))
end)

T.test("Groups: gear sorts into level bands by required level", function()
  local ROBE, SWORD, UNSEEN = 97620, 97621, 97622
  types[ROBE], types[SWORD], types[UNSEEN] = { 4, 1 }, { 2, 7 }, { 4, 2 }
  S.items[ROBE] = { name = "Test Robe", quality = 2, minLevel = 22 }
  S.items[SWORD] = { name = "Test Sword", quality = 2, minLevel = 60 }
  -- (As the game does when details arrive: an item asked about earlier waits for this.)
  T.fire("GET_ITEM_INFO_RECEIVED", ROBE, true); T.fire("GET_ITEM_INFO_RECEIVED", SWORD, true)
  T.eq(ns.NaturalGroup(ROBE), "gear.cloth.l16")
  T.eq(ns.NaturalGroup(SWORD), "gear.weapon.l56")
  T.eq(ns.NaturalGroup(UNSEEN), "gear.leather", "not described by the game yet: its kind")
  T.ok(ns:GroupHas("gear.cloth", ROBE), "Cloth armor holds its bands' items")
  T.ok(ns:GroupHas("gear", ROBE))
  T.ok(not ns:GroupHas("gear.cloth.l26", ROBE))
  T.eq(ns:GroupInfo("gear.cloth.l16").name, "Level 16-25")
  T.eq(ns:GroupInfo("gear.cloth.l16").parent, "gear.cloth")
end)
