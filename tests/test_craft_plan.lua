-- CraftPlan.lua: the cheapest way to get a number of items, buying or making each one
-- (Frank's comment on the Gold making mockup, November 15: Felblood Soul Bags need Bolts
-- of Runecloth; buy the few cheap bolts listed, make the rest, never count both).
local T = ...
local ns = T.ns

local BOLT, RUNE, THREAD, BAG = 1, 2, 3, 4

local function sources(t) return function(id) return t[id] end end

T.test("Craft plan: the cheap bolts are bought, the rest made from cloth", function()
  local total, plan = ns.CraftPlan({ [BOLT] = 20 }, sources({
    [BOLT] = { ladder = { { 66, 2 }, { 70, 4 }, { 90, 10 } }, recipe = { makes = 1, mats = { { RUNE, 4 } } } },
    [RUNE] = { ladder = { { 18, 100 } } },
  }))
  -- 2 at 66 and 4 at 70 (cheaper than making one at 72), then 14 made from 56 cloth.
  T.eq(total, 2 * 66 + 4 * 70 + 14 * 72)
  T.eq(plan[BOLT].bought, 6); T.eq(plan[BOLT].top, 70); T.eq(plan[BOLT].made, 14)
  T.eq(plan[RUNE].bought, 56)
end)

T.test("Craft plan: a thin cheap end is used, then the cloth itself gets dearer", function()
  local total, plan = ns.CraftPlan({ [BOLT] = 3 }, sources({
    [BOLT] = { ladder = { { 100, 5 } }, recipe = { makes = 1, mats = { { RUNE, 4 } } } },
    [RUNE] = { ladder = { { 10, 4 }, { 30, 100 } } },
  }))
  -- The first bolt made from the 4 cloth at 10 (40); then cloth is 30 (120 a bolt), so
  -- the two other bolts are bought at 100.
  T.eq(total, 40 + 200)
  T.eq(plan[BOLT].made, 1); T.eq(plan[BOLT].bought, 2)
  T.eq(plan[RUNE].bought, 4)
end)

T.test("Craft plan: your bags first, at what they'd sell for or free", function()
  local src = sources({
    [BOLT] = { owned = 3, ownedValue = 80, ladder = { { 60, 10 } } },
  })
  local total, plan = ns.CraftPlan({ [BOLT] = 5 }, src)
  T.eq(total, 3 * 80 + 2 * 60); T.eq(plan[BOLT].owned, 3); T.eq(plan[BOLT].bought, 2)
  total = ns.CraftPlan({ [BOLT] = 5 }, src, { ownedFree = true })
  T.eq(total, 2 * 60)
end)

T.test("Craft plan: a vendor sells as many as wanted, after the cheaper listings", function()
  local total, plan = ns.CraftPlan({ [THREAD] = 6 }, sources({
    [THREAD] = { vendor = 10, ladder = { { 5, 2 }, { 20, 50 } } },
  }))
  T.eq(total, 2 * 5 + 4 * 10)
  T.eq(plan[THREAD].bought, 2); T.eq(plan[THREAD].vendor, 4)
end)

T.test("Craft plan: through two steps, each unit counted once", function()
  local total, plan = ns.CraftPlan({ [BAG] = 2 }, sources({
    [BAG] = { recipe = { makes = 1, mats = { { BOLT, 4 }, { THREAD, 1 } } } },
    [BOLT] = { ladder = { { 200, 2 } }, recipe = { makes = 1, mats = { { RUNE, 4 } } } },
    [RUNE] = { ladder = { { 18, 100 } } },
    [THREAD] = { vendor = 10 },
  }))
  -- 8 bolts: none bought at 200 (making one is 72), all made from 32 cloth; 2 thread.
  T.eq(total, 8 * 72 + 2 * 10)
  T.eq(plan[BOLT].made, 8); T.eq(plan[BOLT].bought, 0); T.eq(plan[RUNE].bought, 32)
  T.eq(plan[BAG].made, 2)
end)

T.test("Craft plan: a batch that makes several pays for the whole batch once", function()
  local total, plan = ns.CraftPlan({ [BOLT] = 3 }, sources({
    [BOLT] = { recipe = { makes = 2, mats = { { RUNE, 4 } } } },
    [RUNE] = { ladder = { { 10, 100 } } },
  }))
  -- 3 bolts need two batches (4 bolts) of 4 cloth each: 80, one bolt left over.
  T.eq(total, 80)
  T.eq(plan[BOLT].made, 4); T.eq(plan[RUNE].bought, 8)
end)

T.test("Craft plan: what can't be had gives no total", function()
  local total = ns.CraftPlan({ [BOLT] = 1 }, sources({ [BOLT] = { ladder = {} } }))
  T.eq(total, nil)
  T.eq(ns.CraftPlan({ [BOLT] = 2 }, sources({ [BOLT] = { ladder = { { 5, 1 } } } })), nil, "only one listed")
end)

T.test("Craft plan: a recipe that leads back to itself stops", function()
  local total = ns.CraftPlan({ [BOLT] = 1 }, sources({
    [BOLT] = { recipe = { makes = 1, mats = { { RUNE, 1 } } } },
    [RUNE] = { recipe = { makes = 1, mats = { { BOLT, 1 } } } },
  }))
  T.eq(total, nil)
end)

T.test("Craft plan: one needed is bought, not a whole batch made (Codex review)", function()
  local total, plan = ns.CraftPlan({ [BOLT] = 1 }, sources({
    [BOLT] = { ladder = { { 20, 1 } }, recipe = { makes = 10, mats = { { RUNE, 1 } } } },
    [RUNE] = { ladder = { { 100, 5 } } },
  }))
  T.eq(total, 20)
  T.eq(plan[BOLT].bought, 1); T.eq(plan[BOLT].made, 0)
end)

T.test("Craft plan: a cheap material isn't counted twice when trying a craft (Codex review)", function()
  -- BAG: 20 on the AH, or made from BOLT + RUNE; BOLT is made from RUNE. RUNE: one at 1c,
  -- then 100c. Making the bag takes both, 101c, so it's bought.
  local total, plan = ns.CraftPlan({ [BAG] = 1 }, sources({
    [BAG] = { ladder = { { 20, 1 } }, recipe = { makes = 1, mats = { { BOLT, 1 }, { RUNE, 1 } } } },
    [BOLT] = { recipe = { makes = 1, mats = { { RUNE, 1 } } } },
    [RUNE] = { ladder = { { 1, 1 }, { 100, 5 } } },
  }))
  T.eq(total, 20)
  T.eq(plan[BAG].bought, 1)
  T.eq(plan[RUNE], nil, "trying the craft out left the real plan alone")
end)

T.test("Craft plan: a leftover from a batch serves a later need", function()
  local total, plan = ns.CraftPlan({ [BAG] = 1 }, sources({
    [BAG] = { recipe = { makes = 1, mats = { { BOLT, 1 }, { THREAD, 1 } } } },
    [THREAD] = { recipe = { makes = 1, mats = { { BOLT, 1 } } } },
    [BOLT] = { recipe = { makes = 2, mats = { { RUNE, 4 } } } },
    [RUNE] = { ladder = { { 10, 100 } } },
  }))
  -- One batch of 2 bolts (40c): one for the bag, one for the thread.
  T.eq(total, 40)
  T.eq(plan[BOLT].made, 2); T.eq(plan[RUNE].bought, 4)
end)

-- Codex review, November 15: need 2 bolts; one listed at 49c, the next at 10s; a batch of 2
-- costs 1s. Buying the 49c one and then making a whole batch for the other came to 1s 49c.
T.test("Craft plan: a whole batch beats a cheap first listing when the next is dear", function()
  local total, plan = ns.CraftPlan({ [BOLT] = 2 }, sources({
    [BOLT] = { ladder = { { 49, 1 }, { 1000, 1 } }, recipe = { makes = 2, mats = { { RUNE, 4 } } } },
    [RUNE] = { ladder = { { 25, 100 } } },
  }))
  T.eq(total, 100)
  T.eq(plan[BOLT].made, 2); T.eq(plan[BOLT].bought, 0)
  T.eq(plan[RUNE].bought, 4)
  -- Three needed: the 49c one bought, then one batch for the other two.
  total, plan = ns.CraftPlan({ [BOLT] = 3 }, sources({
    [BOLT] = { ladder = { { 49, 1 }, { 1000, 1 } }, recipe = { makes = 2, mats = { { RUNE, 4 } } } },
    [RUNE] = { ladder = { { 25, 100 } } },
  }))
  T.eq(total, 149)
  T.eq(plan[BOLT].bought, 1); T.eq(plan[BOLT].made, 2)
end)

T.test("Craft plan: a big plan doesn't look over the whole rest for every unit", function()
  local reads = 0
  local function counted(levels)
    return setmetatable({}, { __index = function(_, k) reads = reads + 1; return levels[k] end })
  end
  local bolts, cloth = {}, {}
  for i = 1, 40 do bolts[i] = { 40 + i, 50 }; cloth[i] = { 12 + i, 200 } end
  local total, plan = ns.CraftPlan({ [BOLT] = 400 }, sources({
    [BOLT] = { ladder = counted(bolts), recipe = { makes = 1, mats = { { RUNE, 3 } } } },
    [RUNE] = { ladder = counted(cloth) },
  }))
  T.eq(total, 16900)
  T.eq(plan[BOLT].bought + plan[BOLT].made, 400)
  T.ok(reads < 400 * 1000, ("%d looks at the listings for 400 bolts"):format(reads))
end)

-- Frank's sixteenth /fl perf, November 21: one writ order took 128 ms in one frame. Asked
-- to (opts.yield), the plan gives frames back between units inside a sliced run, with the
-- same answer; not asked (a tier's average, inside pcall), it never does.
T.test("Craft plan: gives frames back only when asked, with the same answer", function()
  local function sourceOf(id)
    if id == 1 then return { ladder = { { 100, 5 }, { 300, 100 } }, recipe = { makes = 1, mats = { { 2, 2 } } } } end
    if id == 2 then return { ladder = { { 60, 100 } } } end
  end
  local wantTotal = ns.CraftPlan({ [1] = 30 }, sourceOf)
  local realClock, ms = debugprofilestop, 0
  local asked, notAsked
  local ok, err = pcall(function()
    debugprofilestop = function() ms = ms + 1; return ms end   -- (each look at the clock: 1 ms)
    ns.RunInSlices("Plan yield test", function() return ns.CraftPlan({ [1] = 30 }, sourceOf, { yield = true }) end,
      function(total) asked = total end)
    T.eq(asked, nil, "asked: not all in the first frame")
    for _ = 1, 200 do if asked then break end T.runTimers() end
    ns.RunInSlices("Plan no yield test", function() return ns.CraftPlan({ [1] = 30 }, sourceOf) end,
      function(total) notAsked = total end)
    T.eq(notAsked, wantTotal, "not asked: done in the first frame")
  end)
  debugprofilestop = realClock
  T.runTimers()
  assert(ok, err)
  T.eq(asked, wantTotal, "the same total")
end)

-- Frank's seventeenth /fl perf, November 22: the Writs view's costs left 187 MB for the game
-- to clear, about 1.3 MB per order, from copying the plan for every craft tried out. Tries
-- now run on the plan itself and are put back, so a big plan leaves little behind, with
-- the same answer as the big plan above.
T.test("Craft plan: trying crafts out leaves little memory behind", function()
  local bolts, cloth = {}, {}
  for i = 1, 40 do bolts[i] = { 40 + i, 50 }; cloth[i] = { 12 + i, 200 } end
  local src = sources({
    [BOLT] = { ladder = bolts, recipe = { makes = 1, mats = { { RUNE, 3 } } } },
    [RUNE] = { ladder = cloth },
  })
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  local total = ns.CraftPlan({ [BOLT] = 400 }, src)
  local kb = collectgarbage("count") - before
  collectgarbage("restart")
  T.eq(total, 16900, "the same answer")
  T.ok(kb < 200, ("%.0f KB left behind for 400 bolts"):format(kb))
end)
