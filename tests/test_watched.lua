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
  T.runTimers()
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
  T.runTimers()
end)

-- (Through the check after a scan: the quick alert waits on a one-second timer, which an
-- earlier test file may have thrown away.)
T.test("Watched: a find at your price is announced as a watched item", function()
  local m = market()
  m[SILK] = { m = 180, a = 180, q = 12, l = "180:12", t = time() }
  S.money = 100000
  local out = printed(function()
    ns:WatchItem(SILK, 200)
    ns.db.alertsSeen = nil
    ns:CheckDeals()
    T.runTimers()   -- (the check goes a few hundred items a frame)
  end)
  T.ok(out:find("Watched item: Test Silk, 12 at 2s or less", 1, true), "chat line: " .. out)
  ns:UnwatchItem(SILK)
  m[SILK], S.money = nil, 0
  T.runTimers()
end)

-- Owner's /fl perf, November 11: the check after each scan took 185 ms on average, 285 at
-- most, all in one frame.
T.test("Deal check: a few hundred items a frame, and a find announced once", function()
  local m = market()
  for id = 95000, 95999 do m[id] = { m = 100, a = 100, q = 1, t = time(), src = "scan" } end
  m[SILK] = { m = 180, a = 180, q = 12, l = "180:12", t = time() }
  S.money = 100000
  ns:WatchItem(SILK, 200)
  ns.db.alertsSeen = nil
  wipe(S.timers)
  local looked, real = 0, ns.WatchedFind
  ns.WatchedFind = function(self, id) looked = looked + 1; return real(self, id) end
  local out = printed(function()
    ns:CheckDeals()
    T.ok(looked > 0 and looked <= 400, "one part in this frame: " .. looked)
    ns:CheckDeals()   -- a second check while the first is under way takes over
    T.runTimers()
  end)
  ns.WatchedFind = real
  local _, n = out:gsub("Watched item: Test Silk, 12 at 2s or less", "")
  T.eq(n, 1, "announced once: " .. out)
  out = printed(function() ns:CheckDeals(); T.runTimers() end)
  T.eq(out:find("Test Silk", 1, true), nil, "and not again at the same price")
  for id = 95000, 95999 do m[id] = nil end
  ns:UnwatchItem(SILK)
  m[SILK], S.money = nil, 0
  T.runTimers()
end)

-- Codex review of ab3fd99: leaving Booty Bay mid-check judged and marked its deals against
-- the faction auction house; and a deal that sold out mid-check was still announced.
T.test("Deal check: it belongs to the auction house it started at, and a deal gone by the end isn't announced", function()
  local s = ns.db.settings
  local realUsual, realStats, realMin, realPct = ns.DealUsualPrice, ns.PriceStats, s.dealUsualMin, s.dealUsualPct
  local DEAL = 95100
  local judged = {}
  local ok, err = pcall(function()
    ns.DealUsualPrice = function(_, id) judged[id] = true; return 1000, "TSM" end
    ns.PriceStats = function() return nil end
    s.dealUsualMin, s.dealUsualPct = 0, 20
    S.items[DEAL] = { name = "Test Deal", sell = 1 }
    T.fire("AUCTION_HOUSE_CLOSED")   -- (deposits from the vendor price)
    ns.neutralAH = true
    local nm = {}
    ns.db.prices[ns.MarketKey()] = nm
    -- (Other items at about the usual price: no deals.)
    for id = 95101, 95900 do nm[id] = { m = 950, a = 950, q = 1, t = time(), src = "scan" } end
    local function cheap() nm[DEAL] = { m = 600, a = 600, q = 2, l = "600:2", t = time(), src = "scan" } end
    cheap()
    ns.db.alertsSeen = nil
    wipe(S.timers)
    local out = printed(function()
      ns:CheckDeals()
      ns.neutralAH = nil   -- left Booty Bay before the check finished
      T.runTimers()
    end)
    T.eq(out:find("below the usual price", 1, true), nil, "nothing announced: " .. out)
    local here = ns.db.alertsSeen and ns.db.alertsSeen[ns.MarketKey()]
    T.eq(here and next(here.deals), nil, "nothing marked at the faction auction house")
    -- At Booty Bay throughout, but the deal sold out after the check had judged it and
    -- before it finished. (Half a minute on, so it's judged afresh, not from the cache.)
    S.now = S.now + 31
    cheap()
    ns.neutralAH, ns.db.alertsSeen = true, nil
    wipe(judged)
    local stepped = false
    out = printed(function()
      ns:CheckDeals()
      while not judged[DEAL] and #S.timers > 0 do table.remove(S.timers, 1)() end
      stepped = judged[DEAL] and #S.timers > 0
      nm[DEAL] = { t = time(), src = "scan", none = true }
      T.runTimers()
    end)
    T.ok(stepped, "judged before the last part, so it sold out mid-check")
    T.eq(out:find("below the usual price", 1, true), nil, "gone by the end: " .. out)
    -- Still there at the end: announced.
    cheap()
    ns.db.alertsSeen = nil
    out = printed(function() ns:CheckDeals(); T.runTimers() end)
    T.ok(out:find("1 new deal below the usual price", 1, true), "announced: " .. out)
  end)
  ns.neutralAH = true
  ns.db.prices[ns.MarketKey()] = nil
  ns.neutralAH, ns.db.alertsSeen = nil, nil
  ns.DealUsualPrice, ns.PriceStats, s.dealUsualMin, s.dealUsualPct = realUsual, realStats, realMin, realPct
  S.items[DEAL] = nil
  wipe(S.timers)
  assert(ok, err)
end)

-- Codex review, November 10: a purchase planned at 200 each and waiting at Confirm was
-- still sent after the price was lowered to 100 (or the item unwatched).
T.test("Watched: a lower price or an unwatch applies to a purchase waiting at Confirm", function()
  local cancelled = 0
  rawset(C_AuctionHouse, "CancelCommoditiesPurchase", function() cancelled = cancelled + 1 end)
  local function waiting(id, reason, limit)
    local e = { id = id, lane = "flips", reason = reason, limit = limit }
    Q.lanes = { flips = { e }, lists = {} }
    Q.cur, Q.plan, Q.state = e, { kind = "commodity", qty = 3, cost = 380, total = 380 }, "confirm"
    return e
  end
  local ok, err = pcall(function()
    T.eq(ns:FlipLimitNow(KEEPSAKE), nil, "no vendor price, not watched")
    ns:WatchItem(KEEPSAKE, 200)
    T.eq(ns:FlipLimitNow(KEEPSAKE), 200)
    local e = waiting(KEEPSAKE, "watch", 200)
    T.eq(Q.limitDropped(e), false, "nothing changed: buy as planned")
    T.eq(Q.state, "confirm")
    ns:WatchItem(KEEPSAKE, 100)
    T.eq(Q.limitDropped(e), true, "lowered: not sent")
    T.eq(cancelled, 1, "the waiting purchase is called off")
    T.eq(e.limit, 100, "looked up again at the new price")
    T.eq(Q.plan, nil)
    T.ok(Q.state ~= "confirm", "nothing left to confirm")
    -- Removed while waiting: let go.
    ns:WatchItem(KEEPSAKE, 200)
    e = waiting(KEEPSAKE, "watch", 200)
    ns:UnwatchItem(KEEPSAKE)
    T.eq(Q.limitDropped(e), true, "unwatched: not sent")
    T.eq(cancelled, 2)
    T.eq(Q.cur, nil, "let go")
    T.eq(Q.state, "idle")
    -- An ordinary vendor flip goes ahead at its own limit, whatever happens to a watch.
    e = waiting(SILK, "flip", 147)
    T.eq(Q.limitDropped(e), false)
    ns:WatchItem(SILK, 200)
    T.eq(Q.limitDropped(e), false, "a higher price of yours: the plan still holds")
    ns:UnwatchItem(SILK)
    T.eq(Q.limitDropped(e), false, "unwatched: still a vendor flip at 147")
    T.eq(Q.state, "confirm")
    -- ...but not over a vendor flip's limit that went down (a bigger margin set meanwhile).
    ns.db.settings.dealVendorPct = 50
    T.eq(Q.limitDropped(e), true)
    T.eq(e.limit, 82)
    T.eq(cancelled, 3)
  end)
  ns.db.settings.dealVendorPct = 10
  ns:UnwatchItem(KEEPSAKE); ns:UnwatchItem(SILK)
  rawset(C_AuctionHouse, "CancelCommoditiesPurchase", nil)
  Q.cur, Q.plan, Q.state, Q.note, Q.lanes = nil, nil, "idle", nil, { flips = {}, lists = {} }
  T.runTimers()
  assert(ok, err)
end)

T.test("Watched: watching an item with an old price doesn't chime", function()
  local m = market()
  local calls, real = 0, ns.CheckFlip
  ns.CheckFlip = function() calls = calls + 1 end
  local ok, err = pcall(function()
    m[SILK] = { m = 150, a = 150, q = 2, l = "150:2", t = time() - 3600 }
    ns:WatchItem(SILK, 200)
    T.eq(calls, 0, "an hour old: the flip watch checks it on its next pass")
    ns:UnwatchItem(SILK)
    m[SILK].t = time() - 60
    ns:WatchItem(SILK, 200)
    T.eq(calls, 1, "a minute old: checked now")
  end)
  ns.CheckFlip = real
  ns:UnwatchItem(SILK)
  m[SILK] = nil
  T.runTimers()
  assert(ok, err)
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
  T.runTimers()
end)
