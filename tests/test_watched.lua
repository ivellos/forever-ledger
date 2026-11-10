-- Watched.lua: items you always want checked, each with the most you'd pay (owner,
-- November 10: Silk Cloth up to 2s, to make bandages, "but I want it actively watched").
local T = ...
local ns = T.ns
local S = T.S
local Q = ns.buyQueueState

local SILK, PLAIN, KEEPSAKE, FLIP = 93001, 93002, 93003, 93004
S.items[SILK] = { name = "Test Silk", sell = 164 }
S.items[PLAIN] = { name = "Test Plain", sell = 100 }
S.items[KEEPSAKE] = { name = "Test Keepsake", sell = 0 }
S.items[FLIP] = { name = "Test Flip", sell = 100 }

local function market()
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  return ns.db.prices[key]
end

-- Chat lines printed while fn runs.
local function printed(fn)
  local lines, real = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(fn)
  print = real
  if not ok then error(err, 2) end
  return table.concat(lines, "\n")
end

ns.db.settings.dealVendorPct, ns.db.settings.dealVendorMin = 10, 0

T.test("Watched: it pays your price or a vendor flip's limit, whichever is higher", function()
  ns:WatchItem(SILK, 200)
  local limit, how = ns:WatchLimit(SILK)
  T.eq(limit, 200); T.eq(how, "you")
  ns:WatchItem(SILK, 100)   -- under the vendor flip's 147 (164 less 10%)
  limit, how = ns:WatchLimit(SILK)
  T.eq(limit, 147, "a lower price of yours still buys vendor flips"); T.eq(how, "vendor")
  ns:WatchItem(SILK, nil)
  limit, how = ns:WatchLimit(SILK)
  T.eq(limit, 147, "vendor price"); T.eq(how, "vendor")
  T.eq(ns:WatchPrice(SILK), nil)
  ns:WatchItem(KEEPSAKE, 0)
  T.eq(ns:WatchLimit(KEEPSAKE), nil, "no price of yours and no vendor buys it: not bought")
  ns:WatchItem(KEEPSAKE, 500)
  T.eq(ns:WatchLimit(KEEPSAKE), 500)
  T.eq(ns:WatchLimit(PLAIN), nil, "not watched")
  ns:UnwatchItem(SILK); ns:UnwatchItem(KEEPSAKE)
  T.eq(ns:IsWatched(SILK), false)
  T.eq(ns:WatchedCount(), 0)
end)

T.test("Watched: a find at your price counts only the listings under it", function()
  local m = market()
  m[SILK] = { m = 180, a = 186, q = 12, l = "180:5,190:12,260:20", t = time() }
  ns:WatchItem(SILK, 200)
  local f = ns:WatchedFind(SILK)
  T.ok(f, "found")
  T.eq(f.watched, "you")
  T.eq(f.maxBuy, 200)
  T.eq(f.buys[1].listed, 12)
  T.eq(math.floor(f.cost), math.floor((180 * 5 + 190 * 7) / 12))
  T.eq(f.opt.value, 164, "what a vendor pays, for the queue's hover")
  m[SILK] = { m = 250, a = 250, q = 3, l = "250:3", t = time() }
  T.eq(ns:WatchedFind(SILK), nil, "nothing at or under 2s")
  -- At the vendor price it's a plain vendor flip, marked as watched.
  ns:WatchItem(SILK, nil)
  m[SILK] = { m = 140, a = 170, q = 8, l = "140:3,190:8", t = time() }
  f = ns:WatchedFind(SILK)
  T.ok(f, "a vendor flip")
  T.eq(f.watched, "vendor")
  T.eq(f.buys[1].listed, 3)
  ns:UnwatchItem(SILK)
  T.eq(ns:WatchedFind(SILK), nil, "not watched")
  m[SILK] = nil
  wipe(S.timers)
end)

T.test("Watched: the flip watch checks watched items first, on top of the ones it picks", function()
  local m = market()
  m[PLAIN] = { m = 60, a = 60, q = 5, t = time() }   -- near its 1s vendor price: picked
  ns:WatchItem(KEEPSAKE, 500)                        -- no price yet: still checked
  local ids = ns.FlipWatchCandidates()
  T.eq(ids[1], KEEPSAKE)
  local seen = 0
  for _, id in ipairs(ids) do if id == PLAIN then seen = seen + 1 end end
  T.eq(seen, 1, "picked as usual")
  ns:WatchItem(PLAIN, nil)
  ids = ns.FlipWatchCandidates()
  seen = 0
  for _, id in ipairs(ids) do if id == PLAIN then seen = seen + 1 end end
  T.eq(seen, 1, "watched and picked: checked once")
  ns:UnwatchItem(KEEPSAKE); ns:UnwatchItem(PLAIN)
  m[PLAIN] = nil
  wipe(S.timers)
end)

T.test("Watched: finds join Vendor flips, first, marked as watched", function()
  local m = market()
  m[SILK] = { m = 180, a = 180, q = 4, l = "180:4", t = time() }
  m[FLIP] = { m = 50, a = 50, q = 2, l = "50:2", t = time() }
  ns:WatchItem(SILK, 200)
  local buyQueue = ns.db.settings.buyQueue
  local realView = buyQueue.view
  buyQueue.view = "flips"
  S.money = 100000
  Q.lanes = Q.buildQueue()
  Q.sortFlips()
  local first, second = Q.lanes.flips[1], Q.lanes.flips[2]
  T.ok(first and second, "both listed")
  T.eq(first.id, SILK, "watched first, though the flip makes more")
  T.eq(first.reason, "watch")
  T.eq(first.limit, 200)
  T.eq(second.id, FLIP)
  T.eq(second.reason, "flip")
  ns:UnwatchItem(SILK)
  Q.lanes = Q.buildQueue()
  for _, e in ipairs(Q.lanes.flips) do T.ok(e.id ~= SILK, "gone once unwatched") end
  buyQueue.view, Q.lanes = realView, { flips = {}, lists = {} }
  m[SILK], m[FLIP], S.money = nil, nil, 0
  wipe(S.timers)
end)

T.test("Watched: one already under your price chimes when you watch it", function()
  local m = market()
  m[SILK] = { m = 180, a = 180, q = 12, l = "180:12", t = time() }
  S.money = 100000
  local out = printed(function()
    ns:WatchItem(SILK, 200)
    T.runTimers()
  end)
  T.ok(out:find("Watched item: Test Silk, 12 at 2s or less", 1, true), "chat line: " .. out)
  ns:UnwatchItem(SILK)
  m[SILK], S.money = nil, 0
  wipe(S.timers)
end)

T.test("Buy queue logs: routine replies and errors with nothing being bought aren't saved", function()
  ns.db.settings.debug = true
  ns.db.buyTrace, ns.db.buyErrors = nil, nil
  Q.cur, Q.plan, Q.state = nil, nil, "idle"
  T.fire("AUCTION_HOUSE_SHOW_ERROR", 31)
  T.eq(ns.db.buyErrors, nil, "a search's error, not the queue's")
  Q.buyAt = GetTime()
  T.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
  T.eq(ns.db.buyTrace, nil, "a routine reply after a purchase")
  T.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
  T.ok(ns.db.buyTrace and #ns.db.buyTrace == 1, "other notices just after a purchase still are")
  ns.db.settings.debug, ns.db.buyTrace, ns.db.buyErrors, Q.buyAt = false, nil, nil, nil
  wipe(S.timers)
end)
