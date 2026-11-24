-- Core.lua freeze watch (Frank, November 17: the game froze while hovering tooltips): a
-- slow frame is kept with Forever Ledger's share and what the profiler named.
local T = ...
local ns = T.ns

T.test("Freeze watch: slow frames kept, short ones not, Forever Ledger's share", function()
  ns.db.freezeLog = nil
  ns.NoteFrame(0.1, 5, "Tooltip lines", 5, nil, nil)
  T.eq(ns.db.freezeLog, nil, "a normal frame isn't noted")
  ns.NoteFrame(0.8, 12.4, "Tooltip lines", 9, 2589, { { name = "SomeAddon", v = 640 } })
  local e = ns.db.freezeLog[1]
  T.eq(e.ms, 800)
  T.eq(e.ours, 12)
  T.eq(e.what, "Tooltip lines")
  T.eq(e.item, 2589)
  T.eq(e.addons[1], "SomeAddon 640 ms")
  ns.NoteFrame(0.5, 1, "Tiny", 1, nil, nil)
  T.eq(ns.db.freezeLog[2].what, nil, "a share under 5 ms isn't named")
  local text = table.concat(ns.FreezeLines(8), "\n")
  T.ok(text:find("800 ms", 1, true), "listed")
  T.ok(text:find("SomeAddon 640 ms", 1, true), "with the other addon")
  for _ = 1, 30 do ns.NoteFrame(0.3, 0, nil, 0, nil, nil) end
  T.eq(#ns.db.freezeLog, 20, "the last 20 kept")
  ns.db.freezeLog = nil
  T.ok(table.concat(ns.FreezeLines(8), "\n"):find("none seen", 1, true))
end)

T.test("Freeze watch: the addons with a frame over 100 ms in it", function()
  local slow = ns.SlowSince({ Bags = 10, UI = 3, Other = 2 }, { Bags = 12, UI = 3, Other = 3, New = 1 })
  T.eq(#slow, 3)
  T.eq(slow[1].name, "Bags", "most first")
  T.eq(slow[1].n, 2)
  T.eq(#ns.SlowSince({ A = 1 }, { A = 1 }), 0, "none: the game itself")
  ns.db.freezeLog = { { t = 1, ms = 600, ours = 2, slow = { "Bags" } }, { t = 2, ms = 500, ours = 1, slow = {} } }
  local text = table.concat(ns.FreezeLines(8), "\n")
  T.ok(text:find("over 100 ms within a second or two of it: Bags", 1, true), "named, as nearby")
  T.ok(text:find("no addon had a frame over 100 ms within", 1, true), "or none (not blamed on the game)")
  T.ok(not text:find("game itself", 1, true), "no conclusion it can't support")
  ns.db.freezeLog = nil
end)

T.test("Freeze watch: the slowest part of our share is named", function()
  ns.db.freezeLog = nil
  ns.NoteFrame(0.5, 471, "Tooltip lines", 468, 2589, nil, "Tooltip: worth to you", 450.4)
  local e = ns.db.freezeLog[1]
  T.eq(e.part, "Tooltip: worth to you")
  T.eq(e.partMs, 450)
  T.ok(table.concat(ns.FreezeLines(8), "\n"):find("slowest part Tooltip: worth to you, 450 ms", 1, true), "listed")
  ns.NoteFrame(0.5, 3, "Tooltip lines", 3, nil, nil, "Tooltip: price", 2)
  T.eq(ns.db.freezeLog[2].part, nil, "not when our share wasn't named")
  -- A part is listed in /fl perf without being counted twice in the frame's total.
  ns.perf["Tooltip: test part"] = nil
  ns.PerfNote("Tooltip: test part", 7, true)
  T.eq(ns.perf["Tooltip: test part"].max, 7)
  ns.perf["Tooltip: test part"] = nil
  ns.db.freezeLog = nil
end)

T.test("Freeze watch: leftovers made, and memory cleared in a freeze", function()
  -- (Frank's AN30, November 19: 148 MB before clearing against 44 MB in use.)
  local saved = ns.perf
  ns.perf = {}
  T.eq(ns.LeftoverLine(4), nil, "none yet")
  ns.PerfNote("Tooltip: crates", 3, true, 3 * 1024)
  ns.PerfNote("CHAT_MSG_ADDON", 1, false, 10 * 1024)
  ns.PerfNote("Tiny", 1, false, 10)
  local line = ns.LeftoverLine(4)
  T.ok(line:find("CHAT_MSG_ADDON 10.0 MB, Tooltip: crates 3.0 MB", 1, true), line)
  T.ok(not line:find("Tiny", 1, true), "under 1 MB isn't named")
  T.ok(ns.PerfLines(3)[1]:find("MB of leftovers", 1, true) or ns.PerfLines(3)[2]:find("MB of leftovers", 1, true))
  ns.perf = saved
  ns.db.freezeLog = { { t = 1, ms = 600, ours = 2, slow = {}, clearedMB = 95 } }
  T.ok(table.concat(ns.FreezeLines(8), "\n"):find("cleared 95 MB of leftover memory", 1, true))
  -- (Frank's twentieth /fl perf: item details arriving, and memory made, in the frozen frame.)
  ns.db.freezeLog = { { t = 1, ms = 290, ours = 18, slow = {}, items = 340, grewMB = 6 } }
  local text = table.concat(ns.FreezeLines(8), "\n")
  T.ok(text:find("340 item details arrived from the game in it", 1, true), text)
  T.ok(text:find("memory grew 6 MB in it", 1, true), text)
  ns.db.freezeLog = nil
end)

T.test("Freeze watch: a timed step inside a timed task isn't counted twice", function()
  -- (Codex review, November 17: 100 ms outer with an 80 ms inner showed as 180 ms.)
  local realClock = debugprofilestop
  local now = 0
  debugprofilestop = function() return now end
  local inner = ns.Timed("Test inner", function() now = now + 80 end)
  local outer = ns.Timed("Test outer", function() now = now + 10; inner(); now = now + 10 end)
  local before = ns.perf["Test outer"]
  local share = ns.FrameShare()
  outer()
  local added = ns.FrameShare() - share
  debugprofilestop = realClock
  T.eq(ns.perf["Test outer"].max, 100)
  T.eq(ns.perf["Test inner"].max, 80, "the inner step is still listed")
  T.ok(before == nil)
  T.eq(added, 100, "the frame's share: the outer task once")
  ns.perf["Test outer"], ns.perf["Test inner"] = nil, nil
end)

T.test("Freeze watch: a timed task that stops with an error doesn't hide the rest of the frame", function()
  -- (Codex verification, November 18: an 80 ms task that threw left the count raised, so the
  -- next 20 ms handler and a later 50 ms task counted as parts, and the frame showed 0 ms ours.)
  local realClock, realHandler = debugprofilestop, geterrorhandler
  local now = 0
  debugprofilestop = function() return now end
  geterrorhandler = function() return function() end end
  local broken = ns.Timed("Test broken", function() now = now + 80; error("test") end)
  ns:On("FL_TEST_DEPTH", function() broken() end)
  ns:On("FL_TEST_DEPTH", function() now = now + 20 end)
  local later = ns.Timed("Test later", function() now = now + 50 end)
  local share = ns.FrameShare()
  T.fire("FL_TEST_DEPTH")
  later()
  local added = ns.FrameShare() - share
  debugprofilestop, geterrorhandler = realClock, realHandler
  -- (Near, not equal: the frame's running total before it can carry a fraction.)
  T.ok(math.abs(added - 150) < 0.001, "the event's 100 ms and the later task's 50, got " .. tostring(added))
  ns.perf["Test broken"], ns.perf["Test later"], ns.perf.FL_TEST_DEPTH = nil, nil, nil
end)

-- Frank's /fl perf, November 21: Gold making's list, 855 ms in one frame.
T.test("Slices: long work gives the frame back and still finishes", function()
  local realClock, now = debugprofilestop, 0
  debugprofilestop = function() return now end
  local ok, err = pcall(function()
    local done, slices = nil, 0
    ns.RunInSlices("Test slices", function()
      local sum = 0
      for i = 1, 10 do
        now = now + 3            -- each step 3 ms
        sum = sum + i
        ns.MaybeYield()
      end
      return sum, "end"
    end, function(a, b) done = { a, b } end)
    T.eq(done, nil, "not all in the first frame")
    while not done and slices < 20 do slices = slices + 1; T.runTimers() end
    T.eq(done[1], 55)
    T.eq(done[2], "end")
    local before = now
    ns.MaybeYield()   -- outside a run: nothing happens
    T.eq(now, before)
  end)
  debugprofilestop = realClock
  T.runTimers()
  assert(ok, err)
end)

T.test("Slices: a stopped run never finishes, and timed tasks inside a run just run", function()
  local realClock, now = debugprofilestop, 0
  debugprofilestop = function() return now end
  local ok, err = pcall(function()
    local done, inner = false, ns.Timed("Test inner", function() now = now + 5; ns.MaybeYield(); return "in" end)
    local run = ns.RunInSlices("Test stop", function()
      local got
      for _ = 1, 10 do got = inner() end
      return got
    end, function() done = true end)
    T.eq(run.stopped, nil, "still going after the first frame")
    ns.StopSlices(run)
    T.runTimers()
    T.eq(done, false, "stopped: done never called")
    T.eq(run.stopped, true)
    local result
    ns.RunInSlices("Test inner yield", function() return inner() end, function(r) result = r end)
    T.runTimers()
    T.eq(result, "in", "a timed task that gave the frame back still returned")
  end)
  debugprofilestop = realClock
  T.runTimers()
  assert(ok, err)
end)

T.test("Slices: the merge sort orders like table.sort and keeps equal items in order", function()
  local list, expect = {}, {}
  for i = 1, 1000 do list[i] = { v = (i * 7919) % 101, n = i } end
  for i = 1, 1000 do expect[i] = list[i] end
  table.sort(expect, function(a, b) if a.v ~= b.v then return a.v < b.v end return a.n < b.n end)
  ns.SortInSlices(list, function(a, b) return a.v < b.v end)
  for i = 1, 1000 do T.eq(list[i], expect[i], "position " .. i) end
  T.same(ns.SortInSlices({}, function() return false end), {})
  T.same(ns.SortInSlices({ 3 }, function(a, b) return a < b end), { 3 })
end)

T.test("Slices: the merge sort looks at the clock every 64 comparisons, inside a big merge too", function()
  -- (Codex review, November 21: once per merged block left 1,024 comparisons in one frame.)
  local realYield, since, most = ns.MaybeYield, 0, 0
  ns.MaybeYield = function() if since > most then most = since end; since = 0 end
  local ok, err = pcall(function()
    local list = {}
    for i = 1, 2048 do list[i] = 2049 - i end
    ns.SortInSlices(list, function(a, b) since = since + 1; return a < b end)
    for i = 1, 2048 do assert(list[i] == i, "sorted") end
  end)
  ns.MaybeYield = realYield
  assert(ok, err)
  T.ok(most > 0 and most <= 64, "at most 64 comparisons between looks: " .. most)
end)

T.test("Slices: putting a sync message's realm names right looks at the clock as it goes", function()
  -- (Frank's eleventh /fl perf, November 21: the whole message was walked in one frame.)
  local realYield, looks = ns.MaybeYield, 0
  ns.MaybeYield = function() looks = looks + 1 end
  local ok, err = pcall(function()
    local items = {}
    for i = 1, 1000 do items[i] = { m = i, l = i .. ":1" } end
    local data = { prices = { ["CAMWOW US2 Realm 3 PvE|Alliance"] = items } }
    ns.PlainRealmData(data)
    assert(data.prices["PvE|Alliance"] == items, "the market put under the plain realm")
  end)
  ns.MaybeYield = realYield
  assert(ok, err)
  T.ok(looks >= 1000, "a look per record: " .. looks)
end)

-- Frank's fifteenth /fl perf, November 21: a partner's hello, 50 ms in one frame, counting
-- every item's recent days of price history.
T.test("Slices: a hello's count of price history days gives frames back", function()
  local market = "Slice test market|Alliance"
  local d = ns.LocalDay(T.S.now)
  local hist = {}
  for i = 1, 150 do hist[95000 + i] = ("%d:100:120|%d:90:95"):format(d - 2, d - 1) end
  ns.db.history = ns.db.history or {}
  ns.db.history[market] = hist
  local whole = ns:HistoryDayCounts(d - 14, d - 1)[market]
  local realClock, ms, result = debugprofilestop, 0, nil
  local ok, err = pcall(function()
    debugprofilestop = function() ms = ms + 1; return ms end   -- (each look at the clock: 1 ms)
    ns.RunInSlices("Day count test", function() return ns:HistoryDayCounts(d - 14, d - 1) end, function(r) result = r end)
    T.eq(result, nil, "not all in the first frame")
    for _ = 1, 100 do if result then break end T.runTimers() end
  end)
  debugprofilestop = realClock
  ns.db.history[market] = nil
  T.runTimers()
  assert(ok, err)
  T.eq(whole and whole[d - 2], 150)
  T.eq(whole and whole[d - 1], 150)
  T.eq(result and result[market] and result[market][d - 2], 150, "the same counts")
  T.eq(result and result[market] and result[market][d - 1], 150)
end)

-- Frank's twentieth /fl perf, November 22: sizing every saved table hit the game's time
-- limit ("script ran too long"). A sample of each level now, the rest estimated.
T.test("Perf report: saved data sized from a sample, the big part still named", function()
  local big = {}
  for i = 1, 300 do
    local inner = {}
    for j = 1, 300 do inner[j] = { j, "some text here" } end
    big[i] = inner
  end
  ns.db.testBigData = big
  local lines, realPrint = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(ns.PrintPerf, ns)
  print = realPrint
  ns.db.testBigData = nil
  assert(ok, err)
  local sizes
  for _, l in ipairs(lines) do if l:find("Biggest saved data", 1, true) then sizes = l end end
  T.ok(sizes and sizes:find("testBigData", 1, true), sizes or "no sizes line")
  local kb = sizes and tonumber(sizes:match("testBigData (%d+) KB"))
  -- (300 x 300 entries of about 46 bytes: roughly 4 MB, estimated from the sample.)
  T.ok(kb and kb > 2000 and kb < 8000, tostring(kb))
end)

-- Frank's twentieth /fl perf, November 22: the recipe index was rebuilt at every loading
-- screen and threw every value away, so Gold making worked out all of them again.
T.test("Recipe index: rebuilt, and values thrown away, only when what it's made from changed", function()
  local key = "Index Tester-Testrealm"
  ns.db.chars[key] = { name = "Index Tester", profs = { Tailoring = { rank = 100,
    recipes = { [97501] = { n = "Test Bolt", out = 97502, r = { { 97503, 2 } } } } } } }
  ns:BuildUsageIndex()
  local realAll, all = ns.InvalidateValues, 0
  ns.InvalidateValues = function() all = all + 1 end
  local ok, err = pcall(function()
    ns:BuildUsageIndex()
    T.eq(all, 0, "nothing changed: kept")
    ns.db.chars[key].profs.Tailoring.recipes[97501].r[1][2] = 3
    ns:BuildUsageIndex()
    T.eq(all, 1, "a material count changed")
    ns.db.chars[key].profs.Tailoring.rank = 125
    ns:BuildUsageIndex()
    T.eq(all, 2, "a rank changed (Enchanting's sets disenchanting)")
    T.ok(ns.recipesByReagent[97503], "the index has the recipe's material")
  end)
  ns.InvalidateValues = realAll
  ns.db.chars[key] = nil
  ns:BuildUsageIndex()
  assert(ok, err)
end)

-- Codex review, November 22: the walk's limit has to stop every loop, and a part cut short
-- says so ("at least"), rather than reading as complete or 0 KB.
T.test("Perf report: a part too big to look through is cut short and says so", function()
  local flat = {}
  for i = 1, 120000 do flat[i] = i end
  ns.db.testFlatData = flat
  local lines, realPrint = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(ns.PrintPerf, ns)
  print = realPrint
  ns.db.testFlatData = nil
  assert(ok, err)
  local sizes
  for _, l in ipairs(lines) do if l:find("Biggest saved data", 1, true) then sizes = l end end
  T.ok(sizes and (sizes:find("testFlatData at least", 1, true) or sizes:find("not measured", 1, true)), sizes or "no sizes line")
end)

-- Codex review, November 22: two recipes swapping their material counts left the old index
-- (the fingerprint added each field on its own).
T.test("Recipe index: two recipes swapping their counts is a change", function()
  local key = "Swap Tester-Testrealm"
  ns.db.chars[key] = { name = "Swap Tester", profs = { Tailoring = { rank = 100, recipes = {
    [97601] = { n = "Swap X", out = 97611, r = { { 97620, 2 } } },
    [97602] = { n = "Swap Y", out = 97612, r = { { 97620, 3 } } },
  } } } }
  ns:BuildUsageIndex()
  local realAll, all = ns.InvalidateValues, 0
  ns.InvalidateValues = function() all = all + 1 end
  local ok, err = pcall(function()
    local recs = ns.db.chars[key].profs.Tailoring.recipes
    recs[97601] = { n = "Swap X", out = 97611, r = { { 97620, 3 } } }
    recs[97602] = { n = "Swap Y", out = 97612, r = { { 97620, 2 } } }
    ns:BuildUsageIndex()
    T.eq(all, 1, "rebuilt")
    local x
    for _, use in ipairs(ns.recipesByReagent[97620] or {}) do if use.recipeID == 97601 then x = use.rec end end
    T.eq(x and x.r[1][2], 3, "the index has the new rows")
    recs[97601].n = "Swap Z"   -- (a name of the same length)
    ns:BuildUsageIndex()
    T.eq(all, 2, "a renamed recipe too")
  end)
  ns.InvalidateValues = realAll
  ns.db.chars[key] = nil
  ns:BuildUsageIndex()
  assert(ok, err)
end)

-- Codex review, November 22: two real Blacksmithing recipes (Volcanic Hammer, Girdle of the
-- Dawn) with corrected counts gave the same added-up fingerprint. Each recipe is compared on
-- its own now, so no pair of changes can cancel out.
T.test("Recipe index: paired corrections in two recipes are a change", function()
  local key = "Pair Tester-Testrealm"
  local function rows(hammer, girdle)
    return {
      [16984] = { n = "Volcanic Hammer", out = 12792, r = { { 12359, 30 }, { 7077, 4 }, { 7910, 4 }, { 8170, hammer } } },
      [23632] = { n = "Girdle of the Dawn", out = 19051, r = { { 12359, 8 }, { 6037, 6 }, { 12811, girdle } } },
    }
  end
  ns.db.chars[key] = { name = "Pair Tester", profs = { Blacksmithing = { rank = 265, recipes = rows(4, 2) } } }
  ns:BuildUsageIndex()
  local realAll, all = ns.InvalidateValues, 0
  ns.InvalidateValues = function() all = all + 1 end
  local ok, err = pcall(function()
    ns.db.chars[key].profs.Blacksmithing.recipes = rows(5, 1)
    ns:BuildUsageIndex()
    T.eq(all, 1, "Codex's pair: rebuilt")
    -- Many pairs of opposite changes, each pair in two recipes.
    local recs = {}
    for i = 1, 200 do recs[97700 + i] = { n = "Pair " .. i, out = 96700 + i, r = { { 96000 + i % 7, 3 + i % 5 } } } end
    ns.db.chars[key].profs.Blacksmithing.recipes = recs
    ns:BuildUsageIndex()
    local missed = 0
    for i = 1, 199, 2 do
      local before = all
      local a, b = recs[97700 + i].r[1], recs[97700 + i + 1].r[1]
      a[2], b[2] = a[2] + 1, b[2] - 1
      ns:BuildUsageIndex()
      if all == before then missed = missed + 1 end
    end
    T.eq(missed, 0, "every pair of opposite changes rebuilt")
    ns:BuildUsageIndex()
    local before = all
    ns:BuildUsageIndex()
    T.eq(all, before, "and nothing changed: kept")
  end)
  ns.InvalidateValues = realAll
  ns.db.chars[key] = nil
  ns:BuildUsageIndex()
  assert(ok, err)
end)
