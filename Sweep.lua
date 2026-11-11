local _, ns = ...

---------------------------------------------------------------------------
-- Browse sweep (owner, November 10): between full scans the flip watch reads the auction
-- house's whole list, the same as a search with no name on the Buy page, which gives every
-- item with its cheapest price and how many are up. Each item is compared with what the
-- last sweep saw, and only what changed is acted on:
--   dearer than the saved price: the cheaper listings were bought, so they come off it
--     (Prices.lua DropBelow);
--   at or under its flip limit (a vendor flip, or a watched item at your price: Watched.lua
--     FlipLimitNow) and new: materials get a close look, an item search like the watch's
--     quick checks (Prices.lua); gear gets the new cheapest put in front of its saved
--     listings (AddCheapest), since an item search shows one stat version at a time.
-- So the watch sees every item about every half minute, not 120 picked ones every two
-- minutes. auxForever's Sniper and Point Blank Sniper read the same list on Forever
-- (design note: forever-ledger-notes, planning/BROWSE_SWEEP_DESIGN.md).
-- The game sends the list in groups of 500. Only a complete list is used: part of one
-- can't say what's gone. Prices.lua's watch pass starts it (ns:StartSweep) and carries on
-- when it's over; buying always has the auction house first.
---------------------------------------------------------------------------
local AH = C_AuctionHouse

local GROUP_WAIT = 10    -- seconds to wait for one group before giving up on the list
local AFTER_YOU = 60     -- after your own search or item page, before the list replaces your results
local FRESH = 300        -- a saved price this recent needs no close look (older shows as "seen N min ago")
local REFRESH = 600      -- a flip still listed is looked at again once its saved price is this old,
                         -- so the Buy queue doesn't leave it out as old (it drops finds over 15 minutes)
local MAX_LOOKS = 60     -- close looks per pass; the rest next time
local FAILS_TO_STOP = 3  -- failed sweeps in one visit before the watch goes back to item checks
local CHUNK = 400        -- items worked through per frame, so a long list doesn't stall the game

local S = { state = "idle", tok = 0, fails = 0 }
ns.SweepState = S        -- (for the tests)
-- States: idle; holding (waiting for the auction house to be free); waiting (a request is on
-- its way); got (its answer came, carrying on next frame); reading (working through the list).
local last, lastMarket = {}, nil   -- [itemID] = the cheapest the last complete sweep saw, this visit
local forgot = {}                  -- [itemID] = true: forgotten since this reading asked for the list
local owns = false                 -- the game's browse list is the sweep's, until anyone else searches

function ns:SweepOwnsList() return owns end

-- The Buy queue bought one, or found none left: the next reading judges it afresh, as if
-- not seen before. Otherwise one listed again at the same price looked unchanged and was
-- left out until a full scan or a reload (owner, November 10: Birchwood Mauls at 9s).
function ns:SweepForget(id)
  if id then last[id], forgot[id] = nil, true end
end

function ns:SweepAvailable()
  return AH ~= nil and AH.SendBrowseQuery ~= nil and AH.RequestMoreBrowseResults ~= nil
    and AH.HasFullBrowseResults ~= nil and AH.GetBrowseResults ~= nil
end

-- Whether the flip watch reads the list this pass (Settings, Auction house, Buying).
function ns:SweepOn()
  return ns.db.settings.watchSweep ~= false and ns:SweepAvailable() and S.fails < FAILS_TO_STOP
end

-- A group is on its way: the Buy queue waits a moment for it (BuyQueue.lua search()).
function ns:SweepWaiting()
  return S.state == "waiting" and S.askedAt ~= nil and GetTime() - S.askedAt < 3
end

---------------------------------------------------------------------------
-- Working out what to do (no game calls: tests/test_sweep.lua)
---------------------------------------------------------------------------
-- Browse rows (BrowseResultInfo) to { [itemID] = { min = cheapest each, q = listed } }, and
-- how many items. Gear has a row per stat version: a vendor pays the same for each, so the
-- cheapest counts and the amounts add up. Pet cages, and rows with no price or none up,
-- are left out.
function ns.SweepCollect(rows)
  local items, n = {}, 0
  for _, r in ipairs(rows or {}) do
    local key = r.itemKey
    local id = key and key.itemID
    local price, qty = tonumber(r.minPrice), tonumber(r.totalQuantity) or 0
    if id and (key.battlePetSpeciesID or 0) == 0 and price and price > 0 and qty > 0 then
      local it = items[id]
      if not it then
        it = { min = price, q = 0 }
        items[id] = it
        n = n + 1
      elseif price < it.min then
        it.min = price
      end
      it.q = it.q + qty
    end
  end
  return items, n
end

-- One item: drop (true: the saved price has cheaper listings that are gone) and look:
--   "check" a close look (an item search), "add" put the new cheapest into gear's saved
--   listings, "touch" gear still listed at its saved cheapest gets a new time, or nil.
-- prev: the cheapest the last sweep saw, if it was settled then (nil: not seen this visit,
-- just became a flip, or its close look got no answer: judge); price: the cheapest now;
-- rec: the saved price; limit: the most a vendor flip or watched item may cost (nil: neither).
function ns.SweepDecide(prev, price, rec, limit, gear, now)
  local has = rec ~= nil and rec.m ~= nil and not rec.none
  local drop = has and rec.l ~= nil and rec.l ~= "" and rec.m < price or false
  if not (limit and price <= limit) then return drop, nil end
  -- Do the saved listings (after the drop) start at this price?
  local known = false
  if has then
    if rec.l then
      for p in rec.l:gmatch("(%d+):%d+") do
        p = tonumber(p)
        if p >= price then known = p == price; break end
      end
    else
      known = rec.m == price
    end
  end
  local age = has and now - (rec.t or 0) or math.huge
  if prev == price then
    -- The same as last time: only a flip that's still there, so it stays in the Buy queue.
    if known and age > REFRESH then return drop, gear and "touch" or "check" end
    return drop, nil
  end
  if known and age <= FRESH then return drop, nil end   -- (just saved: a close look or your search)
  if gear then return drop, known and "touch" or "add" end
  return drop, "check"
end

-- Close looks in order: watched items, then ones that just changed, then the cheapest for
-- their limit. At most MAX_LOOKS.
function ns.SweepLookOrder(looks)
  table.sort(looks, function(a, b)
    if (a.watched and true or false) ~= (b.watched and true or false) then return a.watched and true or false end
    if (a.new and true or false) ~= (b.new and true or false) then return a.new and true or false end
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.id < b.id
  end)
  local ids = {}
  for i = 1, math.min(#looks, MAX_LOOKS) do ids[i] = looks[i].id end
  return ids
end

---------------------------------------------------------------------------
-- Reading the list
---------------------------------------------------------------------------
local ask, finish

-- Kept with /fl debug on (last 30), like the full scan log: how the list came, to check it
-- against full scans (owner's test).
local function logLine(text)
  ns:Debug(text)
  if not ns.db.settings.debug then return end
  local log = ns.db.sweepLog or {}
  ns.db.sweepLog = log
  log[#log + 1] = date("%m-%d %H:%M:%S ") .. text
  while #log > 30 do table.remove(log, 1) end
end

-- Every quality, sorted by price then name, as the game's own empty search does: with no
-- quality filter the game finds nothing (Buy queue, owner's test October 2), and it expects
-- a price and a name sort (warcraft.wiki.gg, SendBrowseQuery).
local function query()
  local filters = {}
  local F = Enum and Enum.AuctionHouseFilter
  if F then
    for name, value in pairs(F) do
      if type(name) == "string" and name:find("Quality$") then filters[#filters + 1] = value end
    end
    table.sort(filters)
  end
  local sorts = {}
  local O = Enum and Enum.AuctionHouseSortOrder
  if O and O.Price and O.Name then
    sorts = { { sortOrder = O.Price, reverseSort = false }, { sortOrder = O.Name, reverseSort = false } }
  end
  return { searchString = "", sorts = sorts, filters = filters, itemClassFilters = {} }
end
ns.SweepQuery = query   -- (for the tests)

-- A line in the status corner (and the Buy queue panel) while the watch reads the list.
local function status(text)
  if ns.SetStatusText and ns.statusText ~= text then ns:SetStatusText(text) end
end

-- Why the sweep can't send now, or nil. first: the opening search, which replaces the list
-- on the Buy page, so it also waits for you. For "page" and "you", also what was seen (for
-- the log) and the seconds until it may go ahead (nil: while the page stays open).
local pageSeen
local function holdReason(first)
  if not (ns.IsAHOpen and ns:IsAHOpen()) then return "closed" end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then return "throttle" end
  -- Buying first: a purchase ready for your click, or the Buy queue looking something up.
  if ns.queueBusyUntil and GetTime() < ns.queueBusyUntil then return "queue" end
  if ns.BuyQueueBusy and ns:BuyQueueBusy() then return "queue" end
  if first then
    local open, page = false, nil
    if ns.ItemPageOpen then open, page = ns.ItemPageOpen() end
    if open then pageSeen = GetTime(); return "page", ("%s open"):format(page or "an item's page") end
    local searched, seen = ns.lastUserSearch or -math.huge, pageSeen or -math.huge
    local you = math.max(searched, seen)
    local ago = GetTime() - you
    if ago < AFTER_YOU then
      local what = searched >= seen and ("a search (%s)"):format(ns.lastUserSearchBy or "?") or "an item's page"
      return "you", ("%s %d s ago"):format(what, math.floor(ago)), AFTER_YOU - ago
    end
  end
end

-- Run fn; an error ends the sweep as failed instead of leaving the watch stuck.
local function safely(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and S.state ~= "idle" then finish("failed", "error: " .. tostring(err)) end
end

-- Send the opening search (first) or ask for the next group, once the auction house is free.
ask = function(first)
  local why, seen, wait = holdReason(first)
  if why == "closed" then return finish("stopped") end
  -- You're on an item's page or just searched: the list isn't replaced under you. This
  -- pass checks your watched items instead, and the list is read once the wait is over
  -- (Prices.lua). Logged once until the next reading, with what was seen (owner, November
  -- 10: the old item checks ran with nothing searched, and nothing showed why).
  if why == "page" or why == "you" then
    if not S.heldLogged then
      S.heldLogged = true
      logLine(("Auction house list: put off, %s."):format(seen or why))
    end
    return finish("held", seen, nil, nil, wait)
  end
  if why then
    if why == "queue" then S.yielded = true end
    S.state = "holding"
    local tok = S.tok
    C_Timer.After(0.5, function() if S.tok == tok and S.state == "holding" then safely(ask, first) end end)
    return
  end
  S.tok = S.tok + 1
  local tok = S.tok
  -- Not your own search (Prices.lua, History.lua), and not another search breaking ours.
  S.sending, ns.Scan.sending = true, true
  local ok, err
  if first then
    forgot = {}
    ok, err = pcall(AH.SendBrowseQuery, query())
  else
    ok, err = pcall(AH.RequestMoreBrowseResults)
  end
  S.sending, ns.Scan.sending = false, false
  if not ok then return finish("failed", "couldn't search: " .. tostring(err)) end
  -- Waiting from now: an answer the game sends while the request goes out (the old list
  -- being cleared) isn't this one's.
  S.state, S.askedAt = "waiting", GetTime()
  -- (sentClock: prices saved from now on are newer than the list's rows, judge.)
  if first then S.sent, S.sentAt, S.sentClock, owns = true, GetTime(), time(), true end
  status(("Watching flips: reading the auction house list, part %d"):format(S.groups + 1))
  C_Timer.After(GROUP_WAIT, function()
    if S.tok == tok and S.state == "waiting" then
      -- The Buy queue had the auction house in between: not a failure of the list itself.
      finish(S.yielded and "broken" or "failed", "no reply in " .. GROUP_WAIT .. " seconds")
    end
  end)
end

local read

-- An answer came: the next group, or the whole list.
local function step()
  if not AH.HasFullBrowseResults() then return ask(false) end
  local rows = AH.GetBrowseResults() or {}
  if #rows == 0 and not S.emptyOnce then
    -- The first answer can be the old list being cleared: give the real one a moment.
    S.emptyOnce, S.state = true, "waiting"
    local tok = S.tok
    C_Timer.After(2, function()
      if S.tok == tok and S.state == "waiting" then S.state = "got"; safely(step) end
    end)
    return
  end
  read(rows)
end

local function onAnswer()
  if S.state ~= "waiting" then return end
  -- Both UPDATED and ADDED can come for one group: one carries on, next frame.
  S.state = "got"
  S.groups = S.groups + 1
  local tok = S.tok
  C_Timer.After(0, function() if S.tok == tok and S.state == "got" then safely(step) end end)
end
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onAnswer)
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", onAnswer)
ns:On("AUCTION_HOUSE_BROWSE_FAILURE", function()
  if S.state == "waiting" or S.state == "got" then finish("failed", "the auction house said the search failed") end
end)

-- Anyone else's search replaces the list the game holds: the Buy queue looking up gear,
-- Search all, the price window, or you. The list is then the other search's.
if AH and hooksecurefunc then
  for _, fn in ipairs({ "SendBrowseQuery", "SearchForItemKeys", "SearchForFavorites" }) do
    if AH[fn] then
      hooksecurefunc(AH, fn, function()
        if S.sending then return end
        owns = false
        if S.sent and S.state ~= "reading" and S.state ~= "idle" then finish("broken", "another search replaced the list") end
      end)
    end
  end
end


-- One item of the list. Returns whether to remember its price for next time.
-- What it returns is remembered for the next reading: { p = cheapest, e = a flip then
-- (under its limit), at = when its close look was asked for }.
local function judge(id, it, now, looks, stats)
  local market = ns.db.prices[ns.MarketKey()] or {}
  local rec = market[id]
  -- Saved since this reading asked for the list (an item search, the Buy queue's lookup, a
  -- full scan): newer than the list's row, so it's left as it is and judged afresh next
  -- time (Codex review, November 10: an older row removed a cheaper listing just saved).
  if rec and (rec.t or 0) >= (S.sentClock or math.huge) then return nil end
  local watched = ns.IsWatched and ns:IsWatched(id) or false
  -- What a vendor pays, the quick way (as ns:VendorFlip): most items aren't worth more.
  local raw = select(11, ns.GetItemInfo(id))
  if raw == nil then raw = ns.db.vendorSell[id] end
  local remember = true
  if raw == nil and not watched then
    -- Not known yet: ask the game, and look again next time.
    ns:RememberItem(id)
    remember = false
  end
  local limit
  if (watched or (raw and raw > it.min)) and ns.FlipLimitNow then limit = ns:FlipLimitNow(id) end
  local eligible = limit ~= nil and it.min <= limit
  -- The same as last time only if it was settled then: not when it has just become a flip
  -- (a new watch, its vendor price known at last), nor when its close look got no answer,
  -- which is asked for again (Codex review, November 10). A close look that was answered
  -- but left this row out (a bid at the buyout) stays settled.
  local seen, prev = last[id], nil
  if seen and seen.e == eligible and (not seen.at or (rec and (rec.t or 0) > seen.at)) then prev = seen.p end
  local drop, look = ns.SweepDecide(prev, it.min, rec, limit, ns:IsGearItem(id), now)
  if drop then
    local gone = ns:DropBelow(id, it.min, true)
    if gone > 0 then stats.dropped, stats.gone = stats.dropped + 1, stats.gone + gone end
  end
  if look == "check" then
    looks[#looks + 1] = { id = id, price = it.min, watched = watched, new = prev ~= it.min,
      gain = (limit - it.min) / math.max(limit, 1) }
    return nil   -- (remembered once it's among the looks that run: see read's end)
  elseif look == "add" then
    if ns:AddCheapest(id, it.min, it.q) then stats.added = stats.added + 1 end
  elseif look == "touch" then
    rec.t = now
    stats.touched = stats.touched + 1
    local ok, err = pcall(ns.CheckFlip, ns, id)
    if not ok then ns:Debug("Flip check failed for", id, err) end
  end
  return remember and { p = it.min, e = eligible } or nil
end

-- The whole list is here: read it once, then work through it a few hundred items a frame.
read = function(rows)
  S.state = "reading"
  local items, n = ns.SweepCollect(rows)
  local secs = GetTime() - (S.sentAt or GetTime())
  local summary = ("%d rows, %d items, in %d parts, %.1f s"):format(#rows, n, S.groups, secs)
  if n == 0 then return finish("failed", "the list came back empty (" .. summary .. ")") end
  if lastMarket ~= ns.MarketKey() then last, lastMarket = {}, ns.MarketKey() end
  local ids = {}
  for id in pairs(items) do ids[#ids + 1] = id end
  local fresh, looks = {}, {}
  local stats = { dropped = 0, gone = 0, added = 0, touched = 0 }
  local i, tok, now = 0, S.tok, time()
  local function chunk()
    if S.tok ~= tok or S.state ~= "reading" then return end
    local stop = math.min(i + CHUNK, #ids)
    for k = i + 1, stop do
      local id = ids[k]
      local ok, keep = pcall(judge, id, items[id], now, looks, stats)
      if not ok then
        ns:Debug("Auction house list: skipped", id, keep)
      elseif keep then
        fresh[id] = keep
      end
    end
    i = stop
    if i < #ids then C_Timer.After(0, chunk); return end
    -- Done: the close looks to make, and what to remember for next time.
    local check = ns.SweepLookOrder(looks)
    for _, id in ipairs(check) do fresh[id] = { p = items[id].min, e = true, at = now } end
    -- (Bought or gone while the list came: judged afresh next time too.)
    for id in pairs(forgot) do fresh[id] = nil end
    last = fresh
    local changed = stats.dropped + stats.added + stats.touched > 0
    if changed then
      if ns.InvalidateValues then ns:InvalidateValues(true) end
      if ns.RefreshFlipsIfShown then C_Timer.After(0.5, function() ns:RefreshFlipsIfShown() end) end
    end
    logLine(("Auction house list: %s. Cheaper listings gone on %d items (%d units); %d to look at closely%s; gear added %d, still listed %d."):format(
      summary, stats.dropped, stats.gone, #check, #looks > #check and (" (%d more next time)"):format(#looks - #check) or "",
      stats.added, stats.touched))
    finish("done", nil, check, changed)
  end
  chunk()
end

-- outcome: "done", "failed" (couldn't read the list: the watch does item checks this time),
-- "held" (you're searching or on an item's page: your watched items are checked, and the list read
-- once the wait is over; not counted as a failure), "broken" (another search replaced it: tried
-- again next pass) or "stopped".
-- wait ("held"): seconds until it may go ahead, nil while an item's page is open.
finish = function(outcome, why, ids, changed, wait)
  local done = S.onDone
  S.tok = S.tok + 1
  S.state, S.onDone, S.sent, S.askedAt = "idle", nil, nil, nil
  if outcome == "done" then
    S.fails, S.heldLogged = 0, nil
  elseif outcome == "failed" then
    S.fails = S.fails + 1
    logLine(("Auction house list couldn't be read: %s (%d in a row)."):format(why or "?", S.fails))
    if S.fails == FAILS_TO_STOP then
      ns:Print("Couldn't read the whole auction house list " .. FAILS_TO_STOP .. " times in a row, so the flip watch checks likely items instead until you next open the auction house.")
    end
  elseif outcome == "broken" then
    logLine("Auction house list: " .. (why or "stopped") .. "; trying again next time.")
  end
  if done then done(outcome, ids or {}, changed and true or false, wait) end
end

---------------------------------------------------------------------------
-- Prices.lua's watch pass
---------------------------------------------------------------------------
-- done(outcome, ids, changed) is called once, when it's over.
local MAX_SECONDS = 300   -- a sweep still going after this is given up (nothing may leave the watch stuck)
function ns:StartSweep(done)
  if S.state ~= "idle" then return false end
  S.onDone, S.groups, S.yielded, S.emptyOnce, S.sent, S.sentAt = done, 0, false, nil, nil, nil
  S.run = (S.run or 0) + 1
  local run = S.run
  S.state = "holding"
  C_Timer.After(MAX_SECONDS, function()
    if S.run == run and S.state ~= "idle" then
      finish(S.yielded and "broken" or "failed", "still going after " .. MAX_SECONDS .. " seconds")
    end
  end)
  safely(ask, true)
  return true
end

function ns:StopSweep()
  if S.state == "idle" then return end
  S.onDone = nil
  finish("stopped")
end

-- Each visit starts afresh: another auction house, or prices changed while you were away.
ns:On("AUCTION_HOUSE_SHOW", function()
  last, lastMarket, S.fails, pageSeen, S.heldLogged, forgot = {}, nil, 0, nil, nil, {}
end)
ns:On("AUCTION_HOUSE_CLOSED", function()
  owns = false
  ns:StopSweep()
end)
