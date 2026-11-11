-- Sweep.lua: between full scans the flip watch reads the auction house's whole list (an
-- empty browse search, in groups of 500) and acts only on what changed (owner, November 10).
local T = ...
local ns = T.ns
local S = T.S
local SW = ns.SweepState
local Q = ns.buyQueueState
local AH = C_AuctionHouse

local MAT, GEAR, PLAIN, SILK, CHEAP = 94001, 94002, 94003, 94004, 94005
local PETCAGE = 94006
S.items[MAT] = { name = "Test Thread", sell = 100 }
S.items[GEAR] = { name = "Test Boots", sell = 200, classID = 4 }
S.items[PLAIN] = { name = "Test Rock", sell = 10 }
S.items[SILK] = { name = "Test Silk", sell = 50 }
S.items[CHEAP] = { name = "Test Pebble", sell = 0 }

ns.db.settings.dealVendorPct, ns.db.settings.dealVendorMin = 10, 0

local function market()
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  return ns.db.prices[key]
end

local function row(id, price, qty, pet)
  return { itemKey = { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = pet or 0 },
    minPrice = price, totalQuantity = qty }
end

---------------------------------------------------------------------------
-- Working out what to do
---------------------------------------------------------------------------
T.test("Sweep: a list's rows become each item's cheapest and how many are up", function()
  local items, n = ns.SweepCollect({
    row(GEAR, 170, 2), row(GEAR, 150, 1),   -- two stat versions: the cheapest counts, amounts add up
    row(MAT, 80, 12),
    row(PETCAGE, 5, 1, 40),                 -- a pet cage: left out
    row(PLAIN, 0, 3),                       -- no price: left out
    row(SILK, 30, 0),                       -- none up: left out
    { minPrice = 5, totalQuantity = 1 },    -- no item: left out
  })
  T.eq(n, 2)
  T.eq(items[GEAR].min, 150); T.eq(items[GEAR].q, 3)
  T.eq(items[MAT].min, 80); T.eq(items[MAT].q, 12)
  T.eq(items[PETCAGE], nil); T.eq(items[PLAIN], nil); T.eq(items[SILK], nil)
end)

T.test("Sweep: what each item needs", function()
  local now = 1000000
  local D = ns.SweepDecide
  local rec = { m = 95, a = 100, q = 8, l = "95:3,120:8", t = now - 100 }
  -- Dearer than saved: the cheaper ones are gone.
  local drop, look = D(nil, 120, rec, nil, false, now)
  T.eq(drop, true); T.eq(look, nil, "not a flip: nothing more")
  drop = D(nil, 120, { m = 95, q = 3 }, nil, false, now)
  T.eq(drop, false, "no saved listings to take them from")
  drop = D(nil, 120, { m = 95, l = "", q = 3 }, nil, false, now)
  T.eq(drop, false, "an empty ladder neither")
  -- Cheaper and under the flip limit: a close look (materials), or added (gear).
  drop, look = D(nil, 80, rec, 90, false, now)
  T.eq(drop, false); T.eq(look, "check")
  drop, look = D(nil, 80, rec, 90, true, now)
  T.eq(look, "add", "gear")
  drop, look = D(nil, 80, rec, 70, false, now)
  T.eq(look, nil, "over the limit: not a flip")
  drop, look = D(nil, 80, nil, 90, false, now)
  T.eq(drop, false); T.eq(look, "check", "nothing saved yet")
  drop, look = D(nil, 80, { t = now, none = true }, 90, true, now)
  T.eq(look, "add", "saved as none listed")
  -- Dearer, and the saved listings have the new cheapest: they say how many, nothing more.
  drop, look = D(nil, 120, rec, 130, false, now)
  T.eq(drop, true); T.eq(look, nil)
  -- Dearer, but the new cheapest isn't among them: a look as well.
  drop, look = D(nil, 110, rec, 130, false, now)
  T.eq(drop, true); T.eq(look, "check")
  -- Already saved at this price just now (a close look or your search): nothing.
  drop, look = D(nil, 95, rec, 130, false, now)
  T.eq(look, nil)
  -- Saved at this price, but a while ago: looked at again (gear: a new time).
  local old = { m = 95, q = 8, l = "95:3,120:8", t = now - 400 }
  drop, look = D(nil, 95, old, 130, false, now)
  T.eq(look, "check")
  drop, look = D(nil, 95, old, 130, true, now)
  T.eq(look, "touch")
end)

T.test("Sweep: the same as last time is left alone, except a flip whose saved price is getting old", function()
  local now = 1000000
  local D = ns.SweepDecide
  local rec = { m = 95, q = 8, l = "95:3,120:8", t = now - 400 }
  local drop, look = D(80, 80, rec, 90, false, now)
  T.eq(drop, false); T.eq(look, nil, "unchanged and not what's saved (a listing the search left out): no look every time")
  drop, look = D(95, 95, rec, 130, false, now)
  T.eq(look, nil, "a flip still there, saved 7 minutes ago")
  rec.t = now - 700
  drop, look = D(95, 95, rec, 130, false, now)
  T.eq(look, "check", "saved over 10 minutes ago: the Buy queue would soon leave it out")
  drop, look = D(95, 95, rec, 130, true, now)
  T.eq(look, "touch", "gear")
  drop, look = D(95, 95, rec, nil, false, now)
  T.eq(look, nil, "not a flip")
  drop, look = D(120, 120, rec, nil, false, now)
  T.eq(drop, true, "cheaper saved listings still go, whatever the last sweep saw")
end)

T.test("Sweep: close looks go watched first, then new ones, then the cheapest for their limit, 60 at most", function()
  local looks = {
    { id = 1, gain = 0.5 }, { id = 2, gain = 0.9, new = true }, { id = 3, gain = 0.1, watched = true },
    { id = 4, gain = 0.2, new = true },
  }
  T.same(ns.SweepLookOrder(looks), { 3, 2, 4, 1 })
  local many = {}
  for i = 1, 75 do many[i] = { id = i, gain = 0, new = true } end
  T.eq(#ns.SweepLookOrder(many), 60)
end)

T.test("Sweep: gear's new cheapest goes in front of its saved listings", function()
  local m = market()
  m[GEAR] = { m = 180, a = 190, q = 6, l = "180:2,200:6", t = 1, src = "full" }
  T.eq(ns:AddCheapest(GEAR, 150, 9), true)
  local rec = m[GEAR]
  T.eq(rec.m, 150); T.eq(rec.l, "150:1,180:3,200:7")
  T.eq(rec.q, 9, "the list's count of everything up")
  T.eq(rec.t, time()); T.eq(rec.src, "full", "kept, so the next full scan can mark it gone")
  T.eq(ns:AddCheapest(GEAR, 150, 9), false, "already in front")
  T.eq(ns:AddCheapest(GEAR, 160, 9), false, "something cheaper is saved")
  -- 20 price levels at most.
  local levels = {}
  for i = 1, 20 do levels[i] = (200 + i) .. ":" .. i end
  m[GEAR] = { m = 201, q = 20, l = table.concat(levels, ","), t = 1, src = "full" }
  ns:AddCheapest(GEAR, 150, 1)
  local n = 0
  for _ in m[GEAR].l:gmatch("%d+:%d+") do n = n + 1 end
  T.eq(n, 20); T.eq(m[GEAR].q, 20, "never fewer than the saved listings count")
  -- Nothing saved yet.
  m[GEAR] = nil
  ns:AddCheapest(GEAR, 150, 3)
  T.eq(m[GEAR].m, 150); T.eq(m[GEAR].l, "150:1"); T.eq(m[GEAR].q, 3); T.eq(m[GEAR].src, "scan")
  m[GEAR] = nil
  T.runTimers()
end)

T.test("Sweep: DropBelow says how many went, and quietly when asked", function()
  local m = market()
  m[CHEAP] = { m = 5, a = 6, q = 10, l = "5:4,8:10", t = 1 }
  T.eq(ns:DropBelow(CHEAP, 8, true), 4)
  T.eq(m[CHEAP].m, 8); T.eq(m[CHEAP].l, "8:6"); T.eq(m[CHEAP].q, 6)
  T.eq(ns:DropBelow(CHEAP, 8, true), 0, "nothing cheaper left")
  T.eq(ns:DropBelow(CHEAP, 20), 6, "the ordinary way too")
  m[CHEAP] = nil
  T.runTimers()
end)

T.test("Sweep: the search is the game's own empty one: every quality, by price then name", function()
  local realF, realO = Enum.AuctionHouseFilter, Enum.AuctionHouseSortOrder
  Enum.AuctionHouseFilter = { ExactMatch = 5, PoorQuality = 6, CommonQuality = 7, UncommonQuality = 8,
    RareQuality = 9, EpicQuality = 10, LegendaryQuality = 11, ArtifactQuality = 12, UsableOnly = 2 }
  Enum.AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2 }
  local q = ns.SweepQuery()
  Enum.AuctionHouseFilter, Enum.AuctionHouseSortOrder = realF, realO
  T.eq(q.searchString, "")
  T.same(q.filters, { 6, 7, 8, 9, 10, 11, 12 })
  T.same(q.sorts, { { sortOrder = 0, reverseSort = false }, { sortOrder = 1, reverseSort = false } })
  T.same(q.itemClassFilters, {})
end)

---------------------------------------------------------------------------
-- Reading the list, with a pretend auction house
---------------------------------------------------------------------------
local sent, more = {}, 0
hooksecurefunc(AH, "SendBrowseQuery", function(query) sent[#sent + 1] = query end)
hooksecurefunc(AH, "RequestMoreBrowseResults", function() more = more + 1 end)
local rows, full = {}, false
AH.HasFullBrowseResults = function() return full end
AH.GetBrowseResults = function() return rows end
AH.IsThrottledMessageSystemReady = function() return true end

local realGear = ns.IsGearItem
ns.IsGearItem = function(_, id) return id == GEAR end

local result
local function start()
  result = nil
  wipe(S.timers)
  return ns:StartSweep(function(outcome, ids, changed, wait) result = { outcome = outcome, ids = ids, changed = changed, wait = wait } end)
end
-- The game answers the request on its way; the sweep carries on next frame.
local function answer()
  T.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  local fn = table.remove(S.timers)
  fn()
end

T.fire("AUCTION_HOUSE_SHOW")
T.runTimers()
Q.state = "idle"
ns.queueBusyUntil, ns.lastUserSearch = 0, nil

T.test("Sweep: reads every group, then acts only on what changed", function()
  local m = market()
  local now = time()
  m[MAT] = { m = 95, a = 100, q = 8, l = "95:3,120:8", t = now - 100, src = "full" }
  m[PLAIN] = { m = 5, a = 7, q = 10, l = "5:2,8:10", t = now - 100, src = "full" }
  rows = { row(MAT, 80, 4), row(GEAR, 150, 1), row(GEAR, 170, 2), row(PLAIN, 8, 8), row(PETCAGE, 1, 1, 40) }
  full, sent, more = false, {}, 0
  T.eq(start(), true)
  T.eq(#sent, 1, "the opening search")
  T.eq(sent[1].searchString, "")
  T.eq(ns:SweepOwnsList(), true)
  T.eq(ns:SweepWaiting(), true, "the Buy queue waits a moment for it")
  answer()
  T.eq(more, 1, "not complete: the next group")
  T.eq(result, nil)
  full = true
  answer()
  T.ok(result, "over")
  T.eq(result.outcome, "done")
  T.same(result.ids, { MAT }, "a new cheaper material under its limit: a close look")
  T.eq(result.changed, true)
  T.eq(m[PLAIN].m, 8, "its cheaper listings are gone"); T.eq(m[PLAIN].l, "8:8")
  T.eq(m[GEAR].m, 150, "gear's new cheapest added"); T.eq(m[GEAR].q, 3)
  T.eq(m[MAT].m, 80, "a material's new cheapest goes in at once, as a stand-in until its close look")
  T.eq(SW.state, "idle")
  T.runTimers()

  -- The thread's close look is answered a second later, without the 80 row (a bid at the
  -- buyout, say). Then the same list again: nothing changed, nothing to do.
  S.now = S.now + 1
  m[MAT] = { m = 95, a = 100, q = 8, l = "95:3,120:8", t = time(), src = "scan" }
  S.now = S.now + 1
  full = false
  start()
  answer()
  full = true
  answer()
  T.eq(result.outcome, "done")
  T.same(result.ids, {}, "nothing new")
  T.eq(result.changed, false)

  -- The close look saved the thread at 80 a moment ago: the next sweeps leave it alone...
  S.now = S.now + 1
  m[MAT] = { m = 80, a = 90, q = 9, l = "80:4,95:7,120:9", t = time(), src = "scan" }
  rows, full = { row(MAT, 80, 4) }, true
  start()
  answer()
  T.same(result.ids, {})
  -- ...until its saved price is over 10 minutes old while it's still listed.
  S.now = S.now + 700
  start()
  answer()
  T.same(result.ids, { MAT }, "looked at again, so the Buy queue keeps it")
  m[MAT], m[PLAIN], m[GEAR] = nil, nil, nil
  T.runTimers()
end)

T.test("Sweep: another search replacing the list ends it, to be tried again next time", function()
  rows, full = { row(MAT, 80, 4) }, false
  start()
  answer()
  T.eq(SW.state, "waiting")
  AH.SendBrowseQuery({ searchString = "linen" })   -- the Buy queue looking up gear, or you
  T.eq(result.outcome, "broken")
  T.eq(ns:SweepOwnsList(), false)
  T.eq(SW.fails, 0, "not a failure")
  ns.lastUserSearch = nil
  market()[MAT] = nil   -- (put in from the first group)
  T.runTimers()
end)

T.test("Sweep: right after your own search it doesn't replace your results", function()
  ns.lastUserSearch = GetTime() - 30
  sent = {}
  start()
  T.eq(result.outcome, "held", "the item checks run this time instead")
  T.eq(#sent, 0, "nothing sent")
  ns.lastUserSearch = GetTime() - 61
  rows, full = { row(MAT, 80, 4) }, true
  start()
  T.eq(#sent, 1, "a minute later it goes ahead")
  answer()
  T.eq(result.outcome, "done")
  ns.lastUserSearch = nil
  T.runTimers()
end)

T.test("Sweep: buying comes first; the next group waits for the Buy queue", function()
  rows, full, more = { row(MAT, 80, 4) }, false, 0
  start()
  Q.state = "search"   -- the queue looks something up
  answer()
  T.eq(more, 0, "held back")
  T.eq(SW.state, "holding")
  Q.state = "idle"
  table.remove(S.timers)()   -- (checks again half a second later)
  T.eq(more, 1, "then asked for")
  -- No answer: since the queue had the auction house in between, not counted as a failure.
  for i = #S.timers, 1, -1 do S.timers[i]() end
  T.eq(result.outcome, "broken")
  T.eq(SW.fails, 0)
  market()[MAT] = nil   -- (put in from the first group)
  T.runTimers()
end)

T.test("Sweep: an empty or missing list fails; three in a row and the watch goes back to item checks", function()
  T.eq(ns:SweepOn(), true)
  rows, full = {}, true
  for n = 1, 3 do
    start()
    answer()
    T.eq(SW.state, "waiting", "the first empty answer can be the old list clearing")
    table.remove(S.timers)()   -- (2 seconds later)
    T.eq(result.outcome, "failed")
    T.eq(SW.fails, n)
  end
  T.eq(ns:SweepOn(), false)
  T.fire("AUCTION_HOUSE_SHOW")   -- the next visit tries again
  T.runTimers()
  T.eq(ns:SweepOn(), true)
  -- No answer at all within 10 seconds.
  start()
  for i = #S.timers, 1, -1 do S.timers[i]() end
  T.eq(result.outcome, "failed")
  T.eq(SW.fails, 1)
  T.fire("AUCTION_HOUSE_SHOW")
  T.runTimers()
  ns.db.settings.watchSweep = false
  T.eq(ns:SweepOn(), false, "Settings: off")
  ns.db.settings.watchSweep = true
end)

T.test("Sweep: the flip watch looks closely at what it found, or does its item checks", function()
  local Scan = ns.Scan
  ns.lastUserSearch = nil
  Scan.active, Scan.sweep, Scan.quiet = true, true, true
  ns.FlipWatchSweepDone("done", { MAT }, true)
  T.eq(Scan.sweep, nil)
  T.eq(Scan.active, true, "a close look at the thread")
  T.eq(Scan.pending, MAT)
  Scan:Stop("test")
  T.eq(Scan.active, false)
  -- Another search replaced the list: this pass ends.
  Scan.active, Scan.sweep, Scan.quiet = true, true, true
  ns.FlipWatchSweepDone("broken", {}, false)
  T.eq(Scan.active, false)
  -- Stopped meanwhile: nothing more.
  ns.FlipWatchSweepDone("done", { MAT }, true)
  T.eq(Scan.active, false)
  -- Stopping the scan stops the sweep with it.
  rows, full = { row(MAT, 80, 4) }, false
  Scan.active, Scan.sweep, Scan.quiet = true, true, true
  start()
  T.eq(SW.state, "waiting")
  Scan:Stop("test")
  T.eq(SW.state, "idle")
  T.eq(result, nil, "no callback once stopped")
  T.runTimers()
end)

-- Owner's test, November 10: Birchwood Mauls at 9s, bought out, then listed again at 9s,
-- only showed after a reload.
T.test("Sweep: one bought or gone, then listed again at the same price, comes back", function()
  local m = market()
  ns.lastUserSearch = nil
  m[GEAR] = nil
  rows, full = { row(GEAR, 150, 1) }, true
  start()
  answer()
  T.eq(m[GEAR].m, 150, "found and added")
  -- Bought: the saved listings now start higher (History.lua RemoveBought).
  m[GEAR] = { m = 170, a = 170, q = 2, l = "170:2", t = time(), src = "full" }
  S.now = S.now + 1   -- (saved before the next list is asked for)
  start()
  answer()
  T.eq(m[GEAR].m, 170, "without being told, the same as last time is left alone")
  ns:SweepForget(GEAR)   -- (the Buy queue, on a purchase or "none left")
  start()
  answer()
  T.eq(m[GEAR].m, 150, "judged afresh: back in front, so the Buy queue has it")
  m[GEAR] = nil
  T.runTimers()
end)

-- Codex review, November 10: a price saved while the list was coming in is newer than the
-- list's row for it, and the row removed the cheaper listing just saved.
T.test("Sweep: a price saved while the list comes in is newer, so the list leaves it alone", function()
  local m = market()
  ns.lastUserSearch = nil
  m[MAT] = { m = 200, a = 200, q = 3, l = "200:3", t = time() - 100, src = "full" }
  rows, full = { row(MAT, 200, 3) }, false
  start()
  answer()   -- the first group
  S.now = S.now + 1
  m[MAT] = { m = 50, a = 163, q = 4, l = "50:1,200:4", t = time(), src = "scan" }   -- an item search
  full = true
  answer()
  T.eq(result.outcome, "done")
  T.eq(m[MAT].m, 50, "the cheaper listing just saved stays")
  T.eq(m[MAT].l, "50:1,200:4")
  -- The next list is newer than that price: if it still says 2c, the 50c one is gone.
  S.now = S.now + 1
  start()
  answer()
  T.eq(m[MAT].m, 200, "the next reading takes it off")
  m[MAT] = nil
  T.runTimers()
end)

-- Codex review, November 10: the same price as last time was left alone even when the item
-- had just become a flip (a new watch), or when its close look got no answer.
T.test("Sweep: the same price is looked at again when it just became a flip, or its look got no answer", function()
  local m = market()
  ns.lastUserSearch = nil
  m[MAT] = { m = 250, a = 250, q = 2, l = "250:2", t = time() - 100, src = "full" }
  rows, full = { row(MAT, 150, 2) }, true
  S.now = S.now + 1
  start(); answer()
  T.same(result.ids, {}, "a vendor pays 1s: not a flip at 1s 50c")
  ns.db.watchItems[MAT] = { max = 200, t = time() }
  S.now = S.now + 1
  start(); answer()
  T.same(result.ids, { MAT }, "watched up to 2s: a close look at once")
  S.now = S.now + 1
  start(); answer()
  T.same(result.ids, { MAT }, "that look got no answer: asked again")
  S.now = S.now + 1
  -- Answered, without this row (a bid at the buyout): the saved listings are the search's.
  m[MAT] = { m = 250, a = 250, q = 2, l = "250:2", t = time(), src = "scan" }
  S.now = S.now + 1
  start(); answer()
  T.same(result.ids, {}, "answered: left alone")
  ns.db.watchItems[MAT], m[MAT] = nil, nil
  T.runTimers()
end)

-- Owner's test, November 10: the old item checks ran with nothing searched by hand, and
-- nothing showed why; and those 120 checks took two minutes.
T.test("Sweep: put off for you, it says why once, and only watched items are checked meanwhile", function()
  ns.db.settings.debug, ns.db.sweepLog = true, nil
  ns.lastUserSearch, ns.lastUserSearchBy = GetTime() - 30, "SendBrowseQuery"
  start()
  T.eq(result.outcome, "held")
  T.eq(ns.db.sweepLog and #ns.db.sweepLog, 1)
  T.ok(ns.db.sweepLog[1]:find("put off, a search (SendBrowseQuery) 30 s ago.", 1, true), ns.db.sweepLog[1])
  T.eq(math.floor(result.wait + 0.5), 30, "the list can be read in 30 seconds")
  start()
  T.eq(#ns.db.sweepLog, 1, "said once until the list is next read")
  local realPage = ns.ItemPageOpen
  ns.ItemPageOpen = function() return true, "ItemSellFrame" end
  start()
  T.eq(result.outcome, "held")
  T.eq(result.wait, nil, "on an item's page: for as long as it stays open")
  ns.ItemPageOpen = realPage
  -- Meanwhile only the watched items are checked, not the usual 120.
  local Scan = ns.Scan
  ns.lastUserSearch = nil
  ns.db.watchItems[MAT] = { t = time() }
  Scan.active, Scan.sweep, Scan.quiet = true, true, true
  ns.FlipWatchSweepDone("held", {}, false, 30)
  T.eq(Scan.total, 1, "the watched thread only")
  T.eq(Scan.pending, MAT)
  Scan:Stop("test")
  ns.db.watchItems[MAT] = nil
  ns.db.settings.debug, ns.db.sweepLog, ns.lastUserSearchBy = false, nil, nil
  T.fire("AUCTION_HOUSE_SHOW")   -- (forgets the page)
  T.runTimers()
end)

-- Owner, November 11: flips chimed and were bought by others a second or two later, while
-- the rest of the list (about 16 seconds of it) was still coming.
T.test("Sweep: a new flip is acted on as soon as its part of the list comes", function()
  local m = market()
  ns.lastUserSearch = nil
  ns.db.settings.debug, ns.db.sweepLog = true, nil
  m[MAT], m[GEAR], m[SILK] = nil, nil, nil
  local k1 = { itemID = GEAR, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
  local k2 = { itemID = GEAR, itemLevel = 0, itemSuffix = 7, battlePetSpeciesID = 0 }
  local function gearRow(key, price, qty) return { itemKey = key, minPrice = price, totalQuantity = qty } end
  rows, full = { row(MAT, 80, 4), gearRow(k1, 150, 1) }, false
  S.now = S.now + 1
  start()
  answer()
  T.eq(result, nil, "the list isn't over")
  T.eq(m[GEAR] and m[GEAR].m, 150, "gear goes in front at once")
  T.eq(m[MAT] and m[MAT].m, 80, "a material too, as a stand-in")
  local keys, partial = ns:SweepVersions(GEAR, 180)
  T.same(keys, { k1 }, "the version the Buy queue can search straight away")
  T.eq(partial, true, "dearer versions under the limit may still come")
  -- The next group comes with its rows: silk at 30c is a flip (a vendor pays 50c).
  T.fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { gearRow(k2, 175, 2), row(SILK, 30, 5) })
  T.eq(m[SILK] and m[SILK].m, 30, "acted on before the list is over")
  T.same(ns:SweepVersions(GEAR, 180), { k1, k2 }, "both versions under 1s 80c, cheapest first")
  T.eq(ns:SweepVersions(GEAR, 160)[2], nil, "only those under the limit asked for")
  -- Meanwhile the Buy queue looked the thread up: what's saved is its search now.
  m[MAT] = { m = 80, a = 80, q = 4, l = "80:4", t = time(), src = "scan" }
  rows, full = { row(SILK, 30, 5), row(MAT, 80, 4), gearRow(k1, 150, 1), gearRow(k2, 175, 2) }, true
  table.remove(S.timers)()   -- (the group's answer carries on next frame)
  T.eq(result.outcome, "done")
  T.same(result.ids, { SILK }, "only the material no search has seen gets its close look")
  keys, partial = ns:SweepVersions(GEAR, 180)
  T.eq(#keys, 2); T.eq(partial, false, "the whole list: no more to come")
  local line = ns.db.sweepLog[#ns.db.sweepLog]
  T.ok(line:find("New flips as their part came: 3 (parts read as they came: 2)", 1, true), line)
  T.ok(line:find("Flips can only be in the first 1 parts", 1, true), line)
  T.runTimers()

  -- Its close look got no answer, and the next list says 60c: the stand-in comes off.
  S.now = S.now + 1
  rows, full = { row(SILK, 60, 5) }, true
  start()
  answer()
  T.eq(m[SILK].m, 60, "the 30c one is gone")
  -- A purchase keeps the versions; none left, or a minute on, they're out of date.
  ns:SweepForget(GEAR)
  T.ok(ns:SweepVersions(GEAR, 180), "kept after a purchase")
  S.now = S.now + 61
  T.eq(ns:SweepVersions(GEAR, 180), nil, "a minute old")
  ns:SweepForget(GEAR, true)
  m[MAT], m[GEAR], m[SILK] = nil, nil, nil
  ns.db.settings.debug, ns.db.sweepLog = false, nil
  T.runTimers()
end)

T.test("Buy queue: a gear flip searches the versions the list saw, not its name first", function()
  local realSearch, realVersions = rawget(AH, "SendSearchQuery"), ns.SweepVersions
  local searched = {}
  rawset(AH, "SendSearchQuery", function(key) searched[#searched + 1] = key end)
  rawset(AH, "GetNumItemSearchResults", function() return 0 end)
  rawset(AH, "HasFullItemSearchResults", function() return true end)
  local k1 = { itemID = GEAR, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
  local k2 = { itemID = GEAR, itemLevel = 0, itemSuffix = 7, battlePetSpeciesID = 0 }
  local partial = false
  ns.SweepVersions = function(_, id) if id == GEAR then return { k1, k2 }, partial end end
  ns.lastUserSearch, ns.queueBusyUntil = nil, 0
  local sentBefore = #sent
  Q.forceActive, Q.state, Q.key, Q.keys, Q.tries = true, "idle", nil, nil, 0
  Q.cur = { id = GEAR, gear = true, lane = "flips", reason = "flip", limit = 180 }
  Q.search()
  T.eq(Q.state, "search")
  T.eq(searched[1], k1, "the cheaper version, straight away")
  T.same(Q.keys, { k2 })
  T.eq(#sent, sentBefore, "no search by name")
  -- From part of the list: both versions gone, so the name is searched after all.
  partial = true
  Q.cur, Q.key, Q.keys, Q.tries = { id = GEAR, gear = true, lane = "flips", reason = "flip", limit = 180 }, nil, nil, 0
  Q.search()
  Q.planItem(k1)
  T.eq(searched[#searched], k2, "the next version")
  Q.planItem(k2)
  T.eq(Q.state, "browse", "then the name")
  T.eq(#sent, sentBefore + 1)
  -- A shopping list's gear always searches the name: its limit isn't the one the list used.
  Q.cur, Q.key, Q.keys, Q.tries = { id = GEAR, gear = true, lane = "lists", reason = "list", limit = 180 }, nil, nil, 0
  Q.search()
  T.eq(Q.state, "browse")
  rawset(AH, "SendSearchQuery", realSearch)
  rawset(AH, "GetNumItemSearchResults", nil)
  rawset(AH, "HasFullItemSearchResults", nil)
  ns.SweepVersions = realVersions
  Q.forceActive, Q.cur, Q.key, Q.keys, Q.state = nil, nil, nil, nil, "idle"
  T.runTimers()
end)

-- Codex review, November 11: from part of the list, version A had gone up to more than you
-- could spend, and version B, at a price you could pay, wasn't in the part read yet.
T.test("Buy queue: versions from part of the list search the name before 'more than you can spend'", function()
  local realSearch, realVersions = rawget(AH, "SendSearchQuery"), ns.SweepVersions
  local k1 = { itemID = GEAR, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
  rawset(AH, "SendSearchQuery", function() end)
  rawset(AH, "GetNumItemSearchResults", function() return 1 end)
  rawset(AH, "GetItemSearchResultInfo", function() return { auctionID = 31, buyoutAmount = 200, quantity = 1 } end)
  rawset(AH, "HasFullItemSearchResults", function() return true end)
  ns.SweepVersions = function(_, id) if id == GEAR then return { k1 }, true end end
  ns.db.settings.buyQueue.limit, Q.spent, S.money = 100, 0, 100000
  ns.lastUserSearch, ns.queueBusyUntil = nil, 0
  local sentBefore = #sent
  Q.forceActive, Q.state, Q.key, Q.keys, Q.tries = true, "idle", nil, nil, 0
  local e = { id = GEAR, gear = true, lane = "flips", reason = "flip", limit = 270 }
  Q.cur = e
  Q.search()
  Q.planItem(k1)   -- A: 2s now, with 1s left to spend
  T.eq(Q.state, "browse", "the name is searched, not set aside as more than you can spend")
  T.eq(#sent, sentBefore + 1)
  T.eq(Q.cur, e)
  -- From the whole list (not partial): then it is set aside.
  ns.SweepVersions = function(_, id) if id == GEAR then return { k1 }, false end end
  e = { id = GEAR, gear = true, lane = "flips", reason = "flip", limit = 270 }
  Q.cur, Q.key, Q.keys, Q.tries = e, nil, nil, 0
  Q.search()
  Q.planItem(k1)
  T.eq(e.poorAt, 200, "the whole list had no cheaper version: more than you can spend")
  rawset(AH, "SendSearchQuery", realSearch)
  rawset(AH, "GetNumItemSearchResults", nil)
  rawset(AH, "GetItemSearchResultInfo", nil)
  rawset(AH, "HasFullItemSearchResults", nil)
  ns.SweepVersions = realVersions
  ns.db.settings.buyQueue.limit = nil
  Q.forceActive, Q.cur, Q.key, Q.keys, Q.state = nil, nil, nil, nil, "idle"
  T.runTimers()
end)

T.test("Buy queue: a busy auction house is looked at again within a quarter second, and at once when it's ready", function()
  local ready = false
  AH.IsThrottledMessageSystemReady = function() return ready end
  ns.lastUserSearch, ns.queueBusyUntil = nil, 0
  Q.forceActive, Q.state, Q.key, Q.keys, Q.tries = true, "idle", nil, nil, 0
  Q.cur = { id = MAT, lane = "flips", reason = "flip", limit = 90 }
  wipe(S.timers)
  Q.search()
  T.eq(Q.state, "wait"); T.eq(Q.waitKind, "ah")
  local tok = Q.tok
  table.remove(S.timers)()   -- a quarter second later: still busy
  T.eq(Q.state, "wait")
  T.eq(Q.tok, tok, "said once, not again every quarter second")
  T.eq(#S.timers, 1, "one look waiting, never two")
  ready = true
  T.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  table.remove(S.timers)()   -- (next frame)
  T.eq(Q.state, "search", "looked up as soon as the game said so")
  local tok2 = Q.tok
  table.remove(S.timers, 1)()   -- the older look: nothing more
  T.eq(Q.tok, tok2)
  AH.IsThrottledMessageSystemReady = function() return true end
  Q.forceActive, Q.cur, Q.state = nil, nil, "idle"
  T.runTimers()
end)

-- Owner, November 10: Pause in place of Scan materials.
T.test("Pause: holds the flip watch and the Buy queue's own lookups until Resume or the auction house closes", function()
  local Scan = ns.Scan
  T.eq(ns:IsScanPaused(), false)
  Scan.active, Scan.quiet, Scan.queue = true, true, {}   -- a watch pass under way
  ns:ToggleScanPause()
  T.eq(ns:IsScanPaused(), true)
  T.eq(Scan.active, false, "the pass under way stops")
  Q.userPicked, Q.clickAt = nil, nil
  T.eq(Q.pausedNow(), true, "the Buy queue looks nothing up by itself")
  Q.clickAt = GetTime() - 5
  T.eq(Q.pausedNow(), false, "right after your click or scroll it goes ahead (the next of a row)")
  Q.clickAt = GetTime() - 11
  T.eq(Q.pausedNow(), true)
  Q.userPicked = true
  T.eq(Q.pausedNow(), false, "Go now or a row you clicked")
  Q.userPicked = nil
  ns:ToggleScanPause()
  T.eq(ns:IsScanPaused(), false, "Resume")
  T.eq(Q.pausedNow(), false)
  ns:ToggleScanPause()
  T.fire("AUCTION_HOUSE_CLOSED")
  T.eq(ns:IsScanPaused(), false, "closing the auction house ends it")
  T.fire("AUCTION_HOUSE_SHOW")
  T.runTimers()
  Q.clickAt = nil
end)

-- Codex review, November 10: /fl scan asked for a full scan, Pause came while it waited,
-- and when none came the materials scan started anyway.
T.test("Pause: a full scan that doesn't come starts no materials scan in its place", function()
  local Scan = ns.Scan
  local realWatch, started = Scan.StartWatch, 0
  Scan.StartWatch = function() started = started + 1 end
  wipe(S.timers)
  ns.db.lastFullScan, Scan.heldUntil = nil, nil
  Scan:StartFull(true)   -- (/fl scan: the materials instead if the full scan doesn't come)
  ns:ToggleScanPause()
  T.eq(ns:IsScanPaused(), true)
  T.eq(Scan.active, true, "the full scan already asked for is still awaited")
  T.runTimers()          -- 30 seconds, no answer
  T.eq(started, 0, "paused: nothing in its place")
  T.eq(Scan.active, false)
  ns:ToggleScanPause()
  Scan:StartFull(true)
  T.runTimers()
  T.eq(started, 1, "not paused: the materials, as before")
  Scan.StartWatch = realWatch
  Scan.active, Scan.full, Scan.heldUntil, ns.db.lastFullScan = false, false, nil, nil
end)

ns.IsGearItem = realGear
AH.IsThrottledMessageSystemReady, AH.HasFullBrowseResults, AH.GetBrowseResults = nil, nil, nil
T.fire("AUCTION_HOUSE_CLOSED")
T.runTimers()
