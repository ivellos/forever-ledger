-- Characters on other rulesets and the other faction (owner, October 4): what sums or
-- compares your characters counts only those on this realm and faction (Core.lua
-- ns:SameMarketChar). Recipes, the Enchanting skill, the usage index, the watch list and
-- /fl book.
local T = ...
local ns = T.ns
local ME = ns.CharKey()

-- You and an alt here; one on the other faction, one on another ruleset, one saved
-- before realm and faction were recorded. Each knows one Enchanting recipe of its own.
local function chars()
  local function prof(rank, recipeID, out, mat)
    return { Enchanting = { rank = rank, max = 300, recipes = { [recipeID] = { n = "Recipe " .. recipeID, out = out, oq = 1, r = { { mat, 1 } } } } } }
  end
  ns.db.chars = {
    [ME] = { name = "Tester", realm = "Testrealm", faction = "Alliance", profs = prof(100, 1, 61001, 62001) },
    ["Alt-Testrealm"] = { name = "Alt", realm = "Testrealm", faction = "Alliance", profs = prof(150, 2, 61002, 62002) },
    ["Hordie-Testrealm"] = { name = "Hordie", realm = "Testrealm", faction = "Horde", profs = prof(250, 3, 61003, 62003) },
    ["Far-Otherrealm"] = { name = "Far", realm = "Otherrealm", faction = "Alliance", profs = prof(300, 4, 61004, 62004) },
    ["Old-Testrealm"] = { name = "Old", profs = prof(120, 5, 61005, 62005) },
  }
  ns.db.settings.skipChars = {}
end

T.test("SameMarketChar: this realm and faction, and old saves without them", function()
  chars()
  T.eq(ns:SameMarketChar(ME), true)
  T.eq(ns:SameMarketChar("Alt-Testrealm"), true)
  T.eq(ns:SameMarketChar("Hordie-Testrealm"), false, "the other faction")
  T.eq(ns:SameMarketChar("Far-Otherrealm"), false, "another ruleset")
  T.eq(ns:SameMarketChar("Old-Testrealm"), true, "no realm or faction saved: counts as here")
end)

T.test("Enchanting skill: the best on this realm and faction only", function()
  chars()
  T.eq(ns.EnchantingSkill(), 150, "not Hordie's 250 or Far's 300")
  ns.db.settings.skipChars["Alt-Testrealm"] = true
  T.eq(ns.EnchantingSkill(), 120, "an unticked alt doesn't count either")
end)

T.test("Usage index: only recipes of characters on this realm and faction", function()
  chars()
  ns:BuildUsageIndex()
  T.ok(ns.usage[62001] and ns.usage[62001]["Tester|Enchanting"], "yours")
  T.ok(ns.usage[62002] and ns.usage[62002]["Alt|Enchanting"], "the alt's")
  T.ok(ns.usage[62005], "an old save's")
  T.eq(ns.usage[62003], nil, "not the other faction's")
  T.eq(ns.usage[62004], nil, "not another ruleset's")
  T.eq(ns.recipesByReagent[62004], nil)
end)

T.test("Watch list: products and materials of this realm and faction's recipes", function()
  chars()
  local on = {}
  for _, id in ipairs(ns:WatchList()) do on[id] = true end
  T.ok(on[61002] and on[62002], "the alt's recipe")
  T.eq(on[61003], nil, "not the other faction's")
  T.eq(on[62004], nil, "not another ruleset's")
end)

T.test("/fl book: known by your characters on this realm and faction", function()
  chars()
  ns.db.recipeBook = { Enchanting = { [1] = { n = "Recipe 1" }, [2] = { n = "Recipe 2" }, [3] = { n = "Recipe 3" },
    [4] = { n = "Recipe 4" }, [5] = { n = "Recipe 5" }, [6] = { n = "Recipe 6" } } }
  local out, real = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    out[#out + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(ns.PrintRecipeBook, ns)
  print = real
  T.ok(ok, err)
  local line
  for _, l in ipairs(out) do if l:find("Enchanting:", 1, true) then line = l end end
  T.ok(line and line:find("6 recipes, 3 known by your characters", 1, true), line)
end)
