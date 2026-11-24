-- RecipesTab.lua: the Professions tab's Where from filter (November 16).
local T = ...
local ns = T.ns

T.test("Professions: Where from groups a recipe's source", function()
  local kind = ns.RecipeSourceKind
  T.eq(kind(nil, false), "trainer", "nothing seen and no recipe item: a trainer (or new in Forever)")
  T.eq(kind(nil, true), "unseen", "a recipe item nobody has spotted")
  T.eq(kind({ kind = "mob" }), "drop"); T.eq(kind({ kind = "drop" }), "drop")
  T.eq(kind({ kind = "vendor" }), "vendor"); T.eq(kind({ kind = "trainer" }), "trainer")
  T.eq(kind({ kind = "quest" }), "quest"); T.eq(kind({ kind = "ah" }), "ah")
end)

T.test("Professions: recipes from the game data show the client's own name", function()
  local oldF, oldSpell = ns.FOREVER_CRAFTS, GetSpellInfo
  ns.FOREVER_CRAFTS = {
    { id = 97201, prof = "Alchemy", n = "Minor Healing Potion", out = 97202, low = 1, high = 1, r = { { 97203, 1 } } },
    { id = 97204, prof = "Alchemy", n = "Unknown Brew", out = 97205, low = 1, high = 1, r = { { 97203, 1 } } },
  }
  GetSpellInfo = function(id) if id == 97201 then return "Малое лечебное зелье" end end
  local book = ns.ForeverRecipeBook("Alchemy")
  T.eq(book[97201].n, "Малое лечебное зелье")
  T.eq(book[97201].en, "Minor Healing Potion", "the English name stays for the Classic data")
  T.eq(book[97204].n, "Unknown Brew", "a spell the client doesn't have keeps the data's name")
  ns.FOREVER_CRAFTS, GetSpellInfo = oldF, oldSpell
end)

T.test("Professions: the list is built over several frames, the same as in one go", function()
  -- (Frank's /fl perf, November 21: up to 101 ms in one go on opening the tab.)
  local R = ns._recipesTest
  local book = {}
  for i = 1, 300 do book[98000 + i] = { n = ("Test Recipe %03d"):format(i) } end
  ns.db.recipeBook.Testcraft = book
  local s = R.settings()
  s.view, s.skill, s.source, s.type, s.group, s.least, s.sort = "all", "all", "all", "all", "all", 0, nil
  local whole = R.buildList("Testcraft", s, "")
  T.eq(whole.total, 300)
  local realClock, ms = debugprofilestop, 0
  local result
  local ok, err = pcall(function()
    debugprofilestop = function() ms = ms + 1; return ms end   -- (each look at the clock: 1 ms)
    ns.RunInSlices("Recipes list test", function() return R.buildList("Testcraft", s, "") end, function(r) result = r end)
    T.eq(result, nil, "not all in the first frame")
    T.runTimers()
  end)
  debugprofilestop = realClock
  ns.db.recipeBook.Testcraft = nil
  T.runTimers()
  assert(ok, err)
  T.ok(result, "finished")
  T.eq(result and result.total, 300)
  T.eq(result and #result.list, #whole.list)
  for i = 1, #whole.list do T.eq(result.list[i].id, whole.list[i].id, "row " .. i) end
end)

T.test("Professions: the group choices are worked out over several frames", function()
  -- (Frank's fifteenth /fl perf, November 21: every recipe's groups, 43 ms in one frame.)
  local R = ns._recipesTest
  local book = {}
  for i = 1, 200 do book[97000 + i] = { n = ("Group Recipe %03d"):format(i), out = 96000 + i } end
  ns.db.recipeBook.Groupcraft = book
  local real = { ns.ItemGroupSet, ns.GroupTree, debugprofilestop }
  local calls, ms, result = 0, 0, nil
  local ok, err = pcall(function()
    ns.ItemGroupSet = function(_, id) calls = calls + 1; return id % 2 == 0 and { test_even = true } or {} end
    ns.GroupTree = function() return { { id = "test_even", kind = "builtin", depth = 0, name = "Even" },
      { id = "test_none", kind = "builtin", depth = 0, name = "None" } } end
    debugprofilestop = function() ms = ms + 1; return ms end   -- (each look at the clock: 1 ms)
    ns.RunInSlices("Group choices test", function() return R.groupChoices("Groupcraft") end, function(r) result = r end)
    T.eq(result, nil, "not all in the first frame")
    for _ = 1, 100 do if result then break end T.runTimers() end
  end)
  ns.ItemGroupSet, ns.GroupTree, debugprofilestop = real[1], real[2], real[3]
  ns.db.recipeBook.Groupcraft = nil
  T.runTimers()
  assert(ok, err)
  T.ok(result, "finished")
  T.eq(calls, 200, "each recipe's product once")
  T.eq(result and #result.opts, 2, "Any group and the one group something here is in")
  T.eq(result and result.opts[2].value, "test_even")
  T.ok(result and result.sets[96002] and result.sets[96002].test_even, "kept for the list's filter")
end)

-- Codex review, November 21: before a profession's first group choices were worked out,
-- the dropdown was empty, or still held the last profession's choices.
T.test("Professions: the group dropdown while its choices are worked out", function()
  local opts = ns._recipesTest.groupOptions
  local loading = opts(nil, "all")
  T.eq(#loading, 1); T.eq(loading[1].value, "all", "Any group only")
  loading = opts(nil, "test_even")
  T.eq(#loading, 2); T.eq(loading[2].value, "test_even", "the chosen group kept until its choices come")
  local known = { opts = { { value = "all" }, { value = "test_even" } } }
  T.eq(opts(known, "test_even"), known.opts, "once known: the profession's own")
end)

-- Codex review, November 21: the kept list missed a recipe just learned (here or by the
-- other account's character), a source just seen and a material's new price until the
-- minute turned.
T.test("Professions: the kept list's stamp changes with what the list is made from", function()
  local R = ns._recipesTest
  local s = R.settings()
  local key = "Stamp Tester-Testrealm"
  local realChar, realNow, realSource = ns.db.chars[key], T.S.now, ns.recipeSourceStamp
  local ok, err = pcall(function()
    ns.db.chars[key] = { name = "Stamp Tester", profs = { Stampcraft = { rank = 100, updated = 1, recipeCount = 3, recipes = {} } } }
    local c1, s1 = R.listStamp("Stampcraft", s, "")
    ns.db.chars[key].profs.Stampcraft.recipeCount, ns.db.chars[key].profs.Stampcraft.updated = 4, 2   -- (a recipe learned)
    local c2, s2 = R.listStamp("Stampcraft", s, "")
    T.eq(c2, c1, "the same choices")
    T.ok(s2 ~= s1, "a recipe learned: a new stamp")
    ns.recipeSourceStamp = (ns.recipeSourceStamp or 0) + 1   -- (RecipeBook.lua's addSource)
    local _, s3 = R.listStamp("Stampcraft", s, "")
    T.ok(s3 ~= s2, "a source seen: a new stamp")
    -- Values: taken in at most every 10 seconds, with a redraw queued for then.
    T.S.now = T.S.now + 20
    ns:InvalidateItem(2589)
    local v1 = R.valuesKey()
    T.eq(v1, ns.ValuesChanges(), "the first change after a quiet spell: taken in at once")
    local timers = #T.S.timers
    ns:InvalidateItem(2589)
    T.eq(R.valuesKey(), v1, "not within 10 seconds")
    T.eq(#T.S.timers, timers + 1, "a redraw for when they're taken in")
    T.S.now = T.S.now + 10
    T.ok(R.valuesKey() ~= v1, "then taken in")
  end)
  ns.db.chars[key], T.S.now, ns.recipeSourceStamp = realChar, realNow, realSource
  T.runTimers()
  assert(ok, err)
end)
