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
-- So the watch sees every item about every 20 seconds, not 120 picked ones every two
-- minutes. auxForever's Sniper and Point Blank Sniper read the same list on Forever
-- (design note: forever-ledger-notes, planning/BROWSE_SWEEP_DESIGN.md).
-- The game sends the list in groups of 500, cheapest first. A new flip is acted on as soon
-- as its group is here (early, below): other players were buying flips within a second or
-- two of the chime (owner, November 11). Everything else waits for the complete list: part
-- of one can't say what's gone. Prices.lua's watch pass starts it (ns:StartSweep) and
-- carries on when it's over; buying always has the auction house first.
---------------------------------------------------------------------------
local AH = C_AuctionHouse

local GROUP_SIZE = 500   -- rows the game sends at a time (for the log)
local GROUP_WAIT = 10    -- seconds to wait for one group before giving up on the list
local AFTER_QUEUE_WAIT = 6   -- the same, for the first group after the Buy queue's lookups: if
                             -- they cost us the list, the next reading starts sooner
local VERSIONS_FRESH = 60    -- seconds the list's gear versions are handed to the Buy queue
local AFTER_YOU = 30     -- after your own search or item page, before the list replaces your results
                         -- (a minute at first, owner November 10; 30 seconds, November 11)
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
-- [itemID] = { rec, l, t }: a material's new cheapest put in front of its saved listings
-- straight from the list (early, below), which no search has seen yet. While its saved
-- entry is that one, unchanged, it's judged as if nothing were saved, so its close look is
-- asked for again until one is answered.
local provisional = {}
-- [itemID] = { run, at, market, upTo, complete, list = { { key, price } }, seen }: gear rows
-- at or under the item's flip limit, for the Buy queue (ns:SweepVersions).
local versions = {}

function ns:SweepOwnsList() return owns end

-- The Buy queue bought one, or found none left: the next reading judges it afresh, as if
-- not seen before. Otherwise one listed again at the same price looked unchanged and was
-- left out until a full scan or a reload (owner, November 10: Birchwood Mauls at 9s).
-- gone: none left, so the versions the list had are out of date too.
function ns:SweepForget(id, gone)
  if id then last[id], forgot[id] = nil, true end
  if id and gone then versions[id] = nil end
end

-- Gear: the stat versions the list had at or under `limit`, cheapest first, from a reading
-- in the last minute (nil if none), and whether there may be more: the list only got so far
-- (its groups come cheapest first), or it judged the item against a lower limit. The Buy
-- queue searches these straight away instead of first searching the item's name, which
-- took a moment and replaced the list being read (owner, November 11).
function ns:SweepVersions(id, limit)
  local v = versions[id]
  if not (v and v.market == ns.MarketKey() and GetTime() - v.at <= VERSIONS_FRESH) then return nil end
  local out = {}
  for _, x in ipairs(v.list) do
    if not limit or x.price <= limit then out[#out + 1] = x end
  end
  if #out == 0 then return nil end
  table.sort(out, function(a, b) return a.price < b.price end)
  for i, x in ipairs(out) do out[i] = x.key end
  local upTo = v.complete and math.huge or (v.run == S.run and S.upTo) or v.upTo or 0
  local partial = limit ~= nil and (limit > upTo or limit > (v.limit or math.huge))
  return out, partial
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
      local from = ns.lastUserSearchFrom and (", " .. ns.lastUserSearchFrom) or ""
      local what = searched >= seen and ("a search (%s%s)"):format(ns.lastUserSearchBy or "?", from) or "an item's page"
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
    if why == "queue" then
      -- (Counted once per wait, for the log.)
      if S.state ~= "holding" or not S.afterQueue then S.yields = S.yields + 1 end
      S.yielded, S.afterQueue = true, true
    elseif why == "throttle" and S.holdWhy ~= "throttle" then
      S.throttled = S.throttled + 1
      S.throttledSince = GetTime()
    end
    if why ~= "throttle" and S.holdWhy == "throttle" and S.throttledSince then
      S.throttledFor = S.throttledFor + (GetTime() - S.throttledSince)
      S.throttledSince = nil
    end
    -- Busy for a moment after each group: asked again the moment the game says it's ready
    -- (below), not half a second later, which was most of each group's 0.63 seconds
    -- (owner, November 11). The half-second look stays as a fallback.
    S.state, S.holdWhy, S.holdFirst = "holding", why, first
    local tok = S.tok
    C_Timer.After(0.5, function() if S.tok == tok and S.state == "holding" then safely(ask, first) end end)
    return
  end
  if S.holdWhy == "throttle" and S.throttledSince then
    S.throttledFor = S.throttledFor + (GetTime() - S.throttledSince)
    S.throttledSince = nil
  end
  S.holdWhy = nil
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
  status(("Watching flips: reading the AH list, part %d"):format(S.groups + 1))
  local wait = S.afterQueue and AFTER_QUEUE_WAIT or GROUP_WAIT
  C_Timer.After(wait, function()
    if S.tok == tok and S.state == "waiting" then
      -- The Buy queue had the auction house in between: not a failure of the list itself.
      finish(S.yielded and "broken" or "failed", "no reply in " .. wait .. " seconds")
    end
  end)
end

---------------------------------------------------------------------------
-- New flips as each group comes (owner, November 11: flips chimed and were gone a second
-- or two later, and a reading takes about 16 seconds, so one could wait that long for the
-- rest of the list). The list comes cheapest first. A flip's new cheapest goes in front of
-- its saved listings as soon as its group is here: it chimes, and the Buy queue looks it
-- up at once while the list waits for it. A material's is only a stand-in until a search
-- sees its listings (`provisional`). Cheaper listings gone, flips already known and what
-- to remember for next time wait for the whole list (read, below).
---------------------------------------------------------------------------
-- The most an item may cost as a flip or watched item this reading (nil: neither), and
-- what a vendor pays; kept on `it`.
local function limitFor(id, it)
  if it.limit ~= nil then return it.limit or nil end
  local watched = ns.IsWatched and ns:IsWatched(id) or false
  local raw = select(11, ns.GetItemInfo(id))
  if raw == nil then raw = ns.db.vendorSell[id] end
  it.watched, it.raw = watched, raw
  if not (watched or (raw and raw > it.min)) then return nil end   -- (a cheaper row may still come)
  it.limit = ns.FlipLimitNow and ns:FlipLimitNow(id) or false
  return it.limit or nil
end

-- Gear row at or under its limit: one of the versions the Buy queue can search straight away.
local function noteVersion(key, price, limit, complete)
  local id = key.itemID
  local v = versions[id]
  if not v or v.run ~= S.run then
    v = { run = S.run, market = ns.MarketKey(), list = {}, seen = {} }
    versions[id] = v
  end
  v.at, v.limit, v.upTo = GetTime(), limit, S.upTo
  if complete then v.complete = true end
  local k = ("%s:%s:%s"):format(tostring(key.itemLevel), tostring(key.itemSuffix), tostring(key.battlePetSpeciesID))
  if v.seen[k] then return end   -- (the same row again, from the whole list)
  v.seen[k] = true
  v.list[#v.list + 1] = { key = key, price = price }
end

-- Whether a saved entry is still the stand-in put there from the list (see provisional).
local function stillProvisional(id, rec)
  local p = provisional[id]
  if not p then return false end
  if rec ~= nil and rec == p.rec and rec.l == p.l and rec.t == p.t then return true end
  provisional[id] = nil
  return false
end

local function earlyJudge(id, it, now)
  local limit = limitFor(id, it)
  if not (limit and it.min <= limit) then return end
  local market = ns.db.prices[ns.MarketKey()] or {}
  local rec = market[id]
  local mine = S.early[id]
  -- Saved since the list was asked for (a search, the Buy queue): newer than this row.
  if rec and (rec.t or 0) >= (S.sentClock or math.huge) and not (mine and mine.rec == rec) then return end
  local gear = ns:IsGearItem(id)
  local seen, prev = last[id], nil
  if seen and seen.e and (not seen.at or (rec and (rec.t or 0) > seen.at)) then prev = seen.p end
  local _, look = ns.SweepDecide(prev, it.min, rec, limit, gear, now)
  if look == "check" then
    -- Only a new cheapest below what's saved: a flip already known waits for the whole list.
    if prev == it.min or (rec and rec.m and not rec.none and rec.m <= it.min) then return end
  elseif look ~= "add" then
    return
  end
  if not ns:AddCheapest(id, it.min, it.q) then return end
  local saved = (ns.db.prices[ns.MarketKey()] or {})[id]
  S.early[id] = { rec = saved, price = it.min, limit = limit, gear = gear, watched = it.watched }
  if not gear and saved then provisional[id] = { rec = saved, l = saved.l, t = saved.t } end
  S.earlyCount = S.earlyCount + 1
  -- (Which part it came in, for the log: if flips keep to the cheap end of the list, that end
  -- could be read more often. Owner, November 11: the auction house answers about two
  -- requests a second, so a whole reading can't be quicker.)
  S.flipParts[#S.flipParts + 1] = S.earlyParts
end

-- Rows that just came (the first group, or one the game added).
local function early(rows)
  if not (S.sent and owns) or S.state == "idle" or S.state == "reading" or #rows == 0 then return end
  S.earlyParts = S.earlyParts + 1
  local now, touched, list = time(), {}, {}
  for _, r in ipairs(rows) do
    local key = r.itemKey
    local id = key and key.itemID
    local price, qty = tonumber(r.minPrice), tonumber(r.totalQuantity) or 0
    if id and (key.battlePetSpeciesID or 0) == 0 and price and price > 0 and qty > 0 then
      if price > S.upTo then S.upTo = price end
      local it = S.items[id]
      if not it then
        it = { min = price, q = 0 }
        S.items[id] = it
      elseif price < it.min then
        it.min = price
      else
        price = nil
      end
      it.q = it.q + qty
      if price and not touched[id] then touched[id] = true; list[#list + 1] = id end
    end
  end
  local before = S.earlyCount
  for _, id in ipairs(list) do
    local ok, err = pcall(earlyJudge, id, S.items[id], now)
    if not ok then ns:Debug("Auction house list: skipped", id, err) end
  end
  -- Gear versions cheap enough, for the Buy queue's lookups.
  for _, r in ipairs(rows) do
    local key = r.itemKey
    local it = key and key.itemID and S.items[key.itemID]
    local price = tonumber(r.minPrice)
    if it and it.limit and price and price <= it.limit and (key.battlePetSpeciesID or 0) == 0
      and ns:IsGearItem(key.itemID) then
      noteVersion(key, price, it.limit)
    end
  end
  if S.earlyCount > before then
    S.newFlips = true   -- (the Buy queue goes first: step, below)
    if ns.InvalidateValues then ns:InvalidateValues() end
  end
end

local read

-- An answer came: the next group, or the whole list.
local function step()
  -- (The first group: the game's later ones come with the event, below.)
  if S.earlyParts == 0 then
    local ok, err = pcall(early, AH.GetBrowseResults() or {})
    if not ok then ns:Debug("Auction house list: early look failed", err) end
  end
  if not AH.HasFullBrowseResults() then
    -- A new flip in this group: the Buy queue starts its lookup first (it claims the auction
    -- house as it starts, next frame), instead of waiting for the next group to come
    -- (owner, November 11). Then the list carries on.
    if S.newFlips then
      S.newFlips = nil
      S.state, S.holdWhy = "holding", nil
      local tok = S.tok
      C_Timer.After(0.1, function() if S.tok == tok and S.state == "holding" then safely(ask, false) end end)
      return
    end
    return ask(false)
  end
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
  S.afterQueue = nil
  local tok = S.tok
  C_Timer.After(0, function() if S.tok == tok and S.state == "got" then safely(step) end end)
end
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onAnswer)
-- A later group's rows come with the event: new flips in it are acted on straight away.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
  if type(added) == "table" and (S.state == "waiting" or S.state == "got") then
    local ok, err = pcall(early, added)
    if not ok then ns:Debug("Auction house list: early look failed", err) end
  end
end)
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", onAnswer)
-- The auction house is ready for the next request: a group held for it goes now.
ns:On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
  if S.state == "holding" and S.holdWhy == "throttle" then safely(ask, S.holdFirst) end
end)
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
  it.raw, it.watched, it.limit = raw, watched, limit   -- (for the gear versions and the log)
  local eligible = limit ~= nil and it.min <= limit
  -- The same as last time only if it was settled then: not when it has just become a flip
  -- (a new watch, its vendor price known at last), nor when its close look got no answer,
  -- which is asked for again (Codex review, November 10). A close look that was answered
  -- but left this row out (a bid at the buyout) stays settled.
  local seen, prev = last[id], nil
  if seen and seen.e == eligible and (not seen.at or (rec and (rec.t or 0) > seen.at)) then prev = seen.p end
  local gear = ns:IsGearItem(id)
  local drop, look = ns.SweepDecide(prev, it.min, rec, limit, gear, now)
  -- A material's cheapest put in from the list that no search has seen (provisional): its
  -- close look is still to come, so it's judged as if nothing were saved. (Cheaper saved
  -- listings gone still go, the stand-in among them.)
  if not gear and stillProvisional(id, rec) then
    local _
    _, look = ns.SweepDecide(prev, it.min, nil, limit, gear, now)
  end
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
    -- Flips put in as their group came (early): gear is remembered like any other; a
    -- material that no search has seen since gets its close look now.
    local market = ns.db.prices[ns.MarketKey()] or {}
    for id, e in pairs(S.early) do
      local it = items[id]
      if e.gear then
        if fresh[id] == nil then fresh[id] = { p = e.price, e = true } end
      elseif it and stillProvisional(id, market[id]) then
        looks[#looks + 1] = { id = id, price = it.min, watched = e.watched, new = true,
          gain = (e.limit - it.min) / math.max(e.limit, 1) }
      end
    end
    -- Done: the close looks to make, and what to remember for next time.
    local check = ns.SweepLookOrder(looks)
    for _, id in ipairs(check) do fresh[id] = { p = items[id].min, e = true, at = now } end
    -- (Bought or gone while the list came: judged afresh next time too.)
    for id in pairs(forgot) do fresh[id] = nil end
    last = fresh
    -- The whole list: every gear version cheap enough, for the Buy queue; and, for the log,
    -- how far into the list a flip could be (rows over the highest vendor price or watched
    -- limit can't be one) and whether it really came cheapest first.
    S.upTo = math.huge
    local ceiling = 0
    for id, it in pairs(items) do
      local e = S.items[id] or {}
      local watched = it.watched or e.watched
      ceiling = math.max(ceiling, it.raw or e.raw or 0, watched and (it.limit or e.limit) or 0)
    end
    local before, unsorted, within = 0, 0, nil
    for k, r in ipairs(rows) do
      local key, price = r.itemKey, tonumber(r.minPrice) or 0
      if price > 0 then
        if price < before then unsorted = unsorted + 1 end
        before = price
        if not within and price > ceiling then within = k - 1 end
      end
      local id = key and key.itemID
      local it = id and items[id]
      local lim = it and (it.limit or (S.items[id] and S.items[id].limit))
      if lim and price > 0 and price <= lim and (key.battlePetSpeciesID or 0) == 0 and ns:IsGearItem(id) then
        noteVersion(key, price, lim, true)
      end
    end
    within = within or #rows
    local changed = stats.dropped + stats.added + stats.touched + S.earlyCount > 0
    if changed then
      if ns.InvalidateValues then ns:InvalidateValues(true) end
      if ns.RefreshFlipsIfShown then C_Timer.After(0.5, function() ns:RefreshFlipsIfShown() end) end
    end
    local money = ns.MoneyPlain or tostring
    logLine(("Auction house list: %s. New flips as their part came: %d%s (parts read as they came: %d). Cheaper listings gone on %d items (%d units); %d to look at closely%s; gear added %d, still listed %d. Waited for the Buy queue %d times, for the auction house %d times (%.1f s). Flips can only be in the first %d parts (up to %s)%s."):format(
      summary, S.earlyCount, #S.flipParts > 0 and (", in parts " .. table.concat(S.flipParts, ", ")) or "",
      S.earlyParts, stats.dropped, stats.gone, #check,
      #looks > #check and (" (%d more next time)"):format(#looks - #check) or "",
      stats.added, stats.touched, S.yields, S.throttled, S.throttledFor, math.ceil(within / GROUP_SIZE), money(ceiling),
      unsorted > 0 and ("; %d rows out of price order"):format(unsorted) or ""))
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
  S.items, S.early, S.earlyParts, S.earlyCount, S.upTo, S.yields, S.afterQueue = {}, {}, 0, 0, 0, 0, nil
  S.throttled, S.throttledFor, S.throttledSince, S.holdWhy, S.holdFirst, S.newFlips = 0, 0, nil, nil, nil, nil
  S.flipParts = {}
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
  provisional, versions = {}, {}
end)
ns:On("AUCTION_HOUSE_CLOSED", function()
  owns = false
  ns:StopSweep()
end)
