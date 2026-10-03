local ADDON, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Buy queue (owner, October 1, after ForeverForge's sniper in "Make lazy gold with
-- this AddOn"): everything worth buying right now in one queue (vendor flips, greens
-- worth disenchanting, shopping list items at or under their price, optionally good
-- deals). The addon searches for the next one by itself; each mouse wheel tick (or a
-- click on Buy) buys it. Blizzard needs a click or key for every purchase, so the
-- addon never buys on its own.
--   Gear and other single items: one tick buys one listing (C_AuctionHouse.PlaceBid).
--   Stackable materials: one tick starts the purchase, the game sends the final price,
--   a second tick confirms (StartCommoditiesPurchase, ConfirmCommoditiesPurchase).
-- Never pays more than the limit (checked again on the final price), never more than
-- you have. Listings sold as stacks of gear-like items are left for the page: whether
-- Forever's buyout for those is per item or per stack isn't confirmed.
--
-- The side panel beside the auction house holds three tabs: Buy queue, Shopping lists
-- (ShoppingLists.lua has the data) and the Disenchant finder (AuctionHouse.lua).
---------------------------------------------------------------------------
local AH = C_AuctionHouse
local WIDTH = 420
local DONE_FOR = 120        -- seconds an item with nothing left stays out of the queue
local REBUILD_EVERY = 20    -- seconds before the queue is worked out again
local USER_QUIET = 3        -- seconds after your own search before the queue looks things up again

local function S() return ns.db.settings.buyQueue end
local function money(c) return ns.Money(math.floor((c or 0) + 0.5)) end
-- An entry's limit as words: "any price" ones say so (and how high they'd go).
local function limitText(e)
  if not e.any then return money(e.limit) end
  if e.limit == math.huge then return "any price" end
  return "any price (at most " .. money(e.limit) .. ", 3 times usual)"
end


local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local function isGear(id)
  if not instant then return false end
  local _, _, _, _, _, classID = instant(id)
  return classID == 2 or classID == 4
end

local SORTS
local function sorts()
  if not SORTS and Enum and Enum.AuctionHouseSortOrder then
    SORTS = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  end
  return SORTS or {}
end


---------------------------------------------------------------------------
-- What's in the queue
---------------------------------------------------------------------------
local done, skipped = {}, {}   -- [itemID] = GetTime() nothing left; [itemID] = true skipped this session

-- Each kind of thing to buy is its own section ("lane") in the queue: vendor flips and
-- shopping lists (owner, October 2: so someone working on a shopping list can't buy a
-- flip by accident, and someone farming flips can just keep scrolling).
-- Returns { flips = {...}, lists = {...} }.
local function buildQueue()
  local s = S()
  local market = ns.db.prices[ns.MarketKey()] or {}
  local now = GetTime()
  local lanes = { flips = {}, lists = {} }
  local seen = { flips = {}, lists = {} }
  local function add(lane, e)
    if seen[lane][e.id] or skipped[e.id] or (done[e.id] and now - done[e.id] < DONE_FOR) then return end
    seen[lane][e.id] = true
    e.gear = isGear(e.id)
    e.lane = lane
    local l = lanes[lane]
    l[#l + 1] = e
  end
  local function byProfit(list)
    for _, e in ipairs(list) do e.profit = ((e.worth or 0) - (e.cost or e.limit)) * (e.n or 1) end
    table.sort(list, function(a, b) return a.profit > b.profit end)
    return list
  end
  -- Each part timed on its own for /fl perf (the whole took about 180 ms, October 2).
  local clock = debugprofilestop or function() return GetTime() * 1000 end
  local t0 = clock()
  local function lap(label)
    local t1 = clock()
    if ns.PerfNote then ns.PerfNote("Buy queue: " .. label, t1 - t0) end
    t0 = t1
  end

  -- Shopping lists, in list order. Ones not cheap enough right now still show, greyed at
  -- the end, so you can see they're watched.
  if s.lists then
    local waiting = {}
    for _, t in ipairs(ns:ShoppingTargets()) do
      local n, avg = ns:CheapListings(t.id, t.limit)
      local e = { id = t.id, limit = t.limit, any = t.any, reason = "list", list = t.list, want = t.want, n = n, cost = avg }
      if n == 0 then e.waiting = true; waiting[#waiting + 1] = e else add("lists", e) end
    end
    for _, e in ipairs(waiting) do add("lists", e) end
  end
  lap("lists")

  if s.flips then
    local list = {}
    for id in pairs(market) do
      local f = ns:VendorFlip(id)
      if f then
        list[#list + 1] = { id = id, limit = math.floor(f.maxBuy), reason = "flip", worth = f.opt.value,
          n = f.buys[1].listed, cost = f.cost }
      end
    end
    for _, e in ipairs(byProfit(list)) do add("flips", e) end
  end
  lap("flips")
  return lanes
end
buildQueue = ns.Timed("Buy queue", buildQueue)

---------------------------------------------------------------------------
-- The engine: search for the current item, plan the purchase, buy on a tick.
-- States: idle, wait, browse (gear: finding its stat versions), search, ready,
-- price (commodity: waiting for the final price), confirm, buying.
---------------------------------------------------------------------------
-- Q.lanes: the sections' lists. Q.armed: the one section that looks things up and buys,
-- chosen by you (a click, or the wheel over its strip); nil = none. Q.cur is from it.
local Q = { lanes = { flips = {}, lists = {} }, state = "idle", tok = 0, bought = 0, spent = 0, worth = 0 }

-- The armed section's list.
local function laneList() return (Q.armed and Q.lanes[Q.armed]) or {} end

-- Let items back into the queue at once (Buy again, a changed Want or price, a new
-- item): a finished item is otherwise kept out for 2 minutes, so Buy again did nothing
-- (owner, October 2: Crafted Light Shot).
local function unpark(ids)
  for _, id in ipairs(ids) do done[id], skipped[id] = nil, nil end
  Q.built = 0
end
local side, queueView, listsView   -- frames, built when the auction house first opens
local refreshQueue                  -- redraws the queue view

-- The queue tab is on screen at the auction house.
local function shown()
  return side and side:IsShown() and S().tab == "queue" and ns:IsAHOpen()
end

-- ...and a section is armed: only then does anything get looked up or bought.
local function active()
  return shown() and Q.armed ~= nil
end

local function setState(state)
  Q.state, Q.tok = state, Q.tok + 1
  if refreshQueue then refreshQueue() end
end

-- Run fn after secs unless the state has changed since.
local function timeout(secs, fn)
  local tok = Q.tok
  C_Timer.After(secs, function() if Q.tok == tok then fn() end end)
end

local function throttled()
  return AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady()
end

local search, prepare, updateBinding, rebuildNow

-- The auction house keeps one item search at a time: when the queue looks up the next
-- item, a page still showing the last one spins on "Searching..." for good (owner,
-- October 2). Go back to the search list instead, which shows the queue's lookups.
local function leaveStalePage()
  local ah = AuctionHouseFrame
  if not (ah and ah.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy) then return end
  local item, commodity = ah.ItemBuyFrame, ah.CommoditiesBuyFrame
  if (item and item:IsShown()) or (commodity and commodity:IsShown()) then
    pcall(ah.SetDisplayMode, ah, AuctionHouseFrameDisplayMode.Buy)
  end
end

local function finishTarget(note)
  local e = Q.cur
  if e then
    done[e.id] = GetTime()
    local list = Q.lanes[e.lane] or {}
    for i, x in ipairs(list) do if x == e then table.remove(list, i); break end end
    Q.note = ns.ItemName(e.id) .. ": " .. note
    ns:Debug("Buy queue:", ns.ItemName(e.id), "-", note)
  end
  Q.cur, Q.plan, Q.key, Q.keys = nil, nil, nil, nil
  setState("idle")
  C_Timer.After(0.3, prepare)
end

local function bought(n, cost)
  local e = Q.cur
  Q.bought, Q.spent = Q.bought + n, Q.spent + cost
  if e and e.worth then Q.worth = Q.worth + n * e.worth end
  if e and e.want then e.want = e.want - n end
  if e then Q.note = ("Bought %d %s for %s."):format(n, ns.ItemName(e.id), money(cost)) end
end

function search()
  local e = Q.cur
  if not e or not active() then setState("idle"); return end
  -- Only a full scan (a few seconds) is waited for. Other scans pause for a moment after
  -- each lookup and purchase of ours instead (Prices.lua Scan:Next).
  if throttled() or (ns.Scan.active and ns.Scan.full) then
    Q.waitFor = ns.Scan.full and "the full scan to finish" or "the auction house"
    setState("wait")
    timeout(1, search)
    return
  end
  -- You're searching the auction house yourself (a flip clicked in the main window, the
  -- search box): the queue's lookups would replace your page, so it waits until you've
  -- stopped for a few seconds (owner's test, October 2: pages spinning, buys refused).
  -- Clicking Buy or a queue row isn't "searching yourself" (Q.userPicked).
  if not Q.userPicked and ns.lastUserSearch and GetTime() - ns.lastUserSearch < USER_QUIET then
    Q.waitText = "Paused while you search the auction house yourself."
    setState("wait")
    timeout(1, search)
    return
  end
  Q.userPicked, Q.waitText = nil, nil
  ns.queueBusyUntil = math.max(ns.queueBusyUntil or 0, GetTime() + 2)
  leaveStalePage()
  Q.tries = (Q.tries or 0) + 1
  if Q.tries > 3 then finishTarget("no reply from the auction house."); return end
  -- Gear: find its stat versions first (one row each in the search list).
  if e.gear and not Q.key then
    local name = ns.GetItemInfo(e.id) or ns.ItemName(e.id)
    -- Every quality, like the game's own search box: with only "exact match" the lookup
    -- found nothing at all (owner's test, October 2: 0 rows for every item).
    local filters = {}
    local F = Enum and Enum.AuctionHouseFilter
    if F then
      for name, value in pairs(F) do
        if type(name) == "string" and name:find("Quality$") then filters[#filters + 1] = value end
      end
      if F.ExactMatch then filters[#filters + 1] = F.ExactMatch end
    end
    setState("browse")
    -- The queue's own searches aren't the page you're looking at (History.lua, the tint).
    ns.queueSending = true
    local ok, err = pcall(AH.SendBrowseQuery, { searchString = name, sorts = sorts(), filters = filters, itemClassFilters = {} })
    ns.queueSending = false
    if not ok then ns:Debug("Buy queue: browse failed", err); finishTarget("couldn't search for it."); return end
    timeout(5, search)
    return
  end
  setState("search")
  ns.queueSending = true
  local ok, err = pcall(AH.SendSearchQuery, Q.key or AH.MakeItemKey(e.id), sorts(), true)
  ns.queueSending = false
  if not ok then ns:Debug("Buy queue: search failed", err); finishTarget("couldn't search for it."); return end
  timeout(5, search)
end

-- Start on the first item in the queue, if nothing's under way.
function prepare()
  if not active() or Q.cur then return end
  if GetTime() - (Q.built or 0) > REBUILD_EVERY then
    Q.lanes, Q.built = buildQueue(), GetTime()
  end
  -- The first one that's cheap enough; waiting list items are only looked up when clicked.
  -- An empty section just waits: scrolling over it does nothing until something turns
  -- up (owner, October 2: "scroll there endlessly" while flips come and go).
  local e
  for _, x in ipairs(laneList()) do
    if not x.waiting then e = x; break end
  end
  if not e then
    setState("idle")
    return
  end
  Q.cur, Q.plan, Q.key, Q.keys, Q.tries = e, nil, nil, nil, 0
  search()
end

-- Let go of the current item (a purchase waiting for its confirm tick is cancelled).
local function dropCurrent()
  if Q.state == "price" or Q.state == "confirm" then pcall(AH.CancelCommoditiesPurchase) end
  Q.cur, Q.plan, Q.key, Q.keys = nil, nil, nil, nil
  Q.state = "idle"
end

-- Make a section the one that looks things up and buys. Only you do this (a click, or
-- the wheel over its strip); scans and the flip watch never switch it.
local function arm(key, quiet)
  if Q.armed == key then return end
  dropCurrent()
  Q.armed = key
  Q.note = nil
  if not quiet then
    Q.userPicked = true
    prepare()
  end
  if refreshQueue then refreshQueue() end
end

-- Work on this entry now (clicking a row): its section becomes the armed one.
local function choose(e)
  arm(e.lane, true)
  dropCurrent()
  Q.cur, Q.tries = e, 0
  Q.userPicked = true
  search()
end

local function planCommodity()
  local e = Q.cur
  local n = AH.GetNumCommoditySearchResults(e.id) or 0
  local full = not AH.HasFullCommoditySearchResults or AH.HasFullCommoditySearchResults(e.id)
  local cash, qty, cost = GetMoney(), 0, 0
  -- all: every listing at or under the limit is in this purchase (none stopped by
  -- "want" or your gold), so there's no need to look again after buying it.
  local all = full
  for i = 1, n do
    local r = AH.GetCommoditySearchResultInfo(e.id, i)
    if not (r and r.unitPrice) or r.unitPrice > e.limit then all = true; break end
    local k = (r.quantity or 0) - (r.numOwnerItems or 0)
    local avail = k
    if e.want then k = math.min(k, e.want - qty) end
    k = math.min(k, math.floor((cash - cost) / r.unitPrice))
    if k > 0 then qty, cost = qty + k, cost + k * r.unitPrice end
    if k < avail then all = false; break end
  end
  if qty == 0 then
    if n == 0 and not full then return end   -- more results on the way
    finishTarget(("none left at %s or less."):format(limitText(e)))
    return
  end
  Q.plan = { kind = "commodity", qty = qty, cost = cost, all = all }
  setState("ready")
end

local function planItem(key)
  local e = Q.cur
  local n = AH.GetNumItemSearchResults(key) or 0
  local cash, best, count, stacks = GetMoney(), nil, 0, 0
  for i = 1, n do
    local r = AH.GetItemSearchResultInfo(key, i)
    if r and r.auctionID and r.buyoutAmount and r.buyoutAmount > 0 and r.buyoutAmount <= e.limit and not r.containsOwnerItem
      and not (e.boughtIDs and e.boughtIDs[r.auctionID]) then
      if (r.quantity or 1) > 1 then
        stacks = stacks + 1
      elseif r.buyoutAmount <= cash then
        count = count + 1
        if not best or r.buyoutAmount < best.buyoutAmount then best = r end
      end
    end
  end
  if not best then
    if n == 0 and AH.HasFullItemSearchResults and not AH.HasFullItemSearchResults(key) then return end
    -- For testing why an item drops out: what the page had.
    local r1 = n > 0 and AH.GetItemSearchResultInfo(key, 1)
    ns:Debug(("Buy queue: %s page has %d listings; cheapest %s each, %s; limit %s."):format(ns.ItemName(e.id), n,
      r1 and r1.buyoutAmount and ns.MoneyPlain(r1.buyoutAmount) or "?", r1 and (("quantity %d%s"):format(r1.quantity or 1,
      r1.containsOwnerItem and ", yours" or "")) or "", e.limit == math.huge and "any" or ns.MoneyPlain(e.limit)))
    -- Gear: the next stat version that had one cheap enough.
    if Q.keys and #Q.keys > 0 then
      Q.key, Q.tries = table.remove(Q.keys, 1), 0
      search()
      return
    end
    finishTarget(stacks > 0 and ("%d listed as stacks: buy those on the page."):format(stacks)
      or ("none left at %s or less."):format(limitText(e)))
    return
  end
  Q.plan = { kind = "item", auctionID = best.auctionID, price = best.buyoutAmount, key = key, count = count }
  setState("ready")
end

-- After a purchase: look again, there may be more. reuse: a single item was bought, so
-- take the next cheap listing from the page already loaded instead of searching again,
-- which cost about a second per purchase (owner, October 2: "slow to buy with the scroll").
-- A failed purchase or no reply always searches again.
local function again(reuse)
  local p = Q.plan
  Q.plan, Q.tries = nil, 0
  local e = Q.cur
  if e and e.want and e.want <= 0 then finishTarget("you have all you wanted."); return end
  if e and p and reuse and p.kind == "item" and p.key then
    e.boughtIDs = e.boughtIDs or {}
    e.boughtIDs[p.auctionID] = true
    setState("search")
    planItem(p.key)
    -- The page had gone after all: search for real.
    if Q.state == "search" and Q.cur == e then search() end
    return
  end
  if e and p and reuse and p.kind == "commodity" and p.all then
    finishTarget(("bought every one at %s or less."):format(limitText(e)))
    return
  end
  search()
end

-- One tick of the mouse wheel or a click on Buy: the next step of the purchase.
-- A click can arrive as both "down" and "up", so two within 0.15 s count once.
local lastAct = 0
function ns:BuyQueueAct()
  if not active() or GetTime() - lastAct < 0.15 then return end
  lastAct = GetTime()
  -- Scans step aside for a few seconds after each buy, and longer while you keep going.
  ns.queueBusyUntil = math.max(ns.queueBusyUntil or 0, GetTime() + 4)
  local e, p = Q.cur, Q.plan
  if Q.state == "ready" and p and p.kind == "commodity" then
    local ok, err = pcall(AH.StartCommoditiesPurchase, e.id, p.qty)
    if not ok then ns:Print("Couldn't start that purchase: " .. tostring(err)); again(); return end
    setState("price")
    timeout(6, function() pcall(AH.CancelCommoditiesPurchase); Q.note = "No final price came back: checking again."; again() end)
  elseif Q.state == "confirm" and p and p.kind == "commodity" then
    local ok, err = pcall(AH.ConfirmCommoditiesPurchase, e.id, p.qty)
    if not ok then ns:Print("Couldn't confirm that purchase: " .. tostring(err)); again(); return end
    setState("buying")
    timeout(10, again)
  elseif Q.state == "ready" and p and p.kind == "item" then
    -- So the purchase is logged under the right item (History.lua's PlaceBid hook).
    ns.queueBidItem = e.id
    local ok, err = pcall(AH.PlaceBid, p.auctionID, p.price)
    ns.queueBidItem = nil
    if not ok then ns:Print("Couldn't buy that: " .. tostring(err)); again(); return end
    setState("buying")
    timeout(6, again)
  elseif Q.state == "wait" and Q.waitText then
    -- Paused for your own searching: Buy means go now.
    Q.userPicked = true
    search()
  elseif Q.state == "idle" and not Q.cur then
    -- Nothing under way: look again (at most every 3 seconds, as a spun wheel sends many ticks).
    if GetTime() - (Q.built or 0) > 3 then Q.built = 0 end
    Q.userPicked = true
    prepare()
  end
end

-- Search results and purchase replies.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  local e = Q.cur
  if Q.state ~= "browse" or not e then return end
  local keys, rows, ours, cheapest = {}, 0, 0, nil
  for _, r in ipairs(AH.GetBrowseResults() or {}) do
    rows = rows + 1
    if r.itemKey and r.itemKey.itemID == e.id then
      ours = ours + 1
      if r.minPrice and r.minPrice > 0 then cheapest = math.min(cheapest or math.huge, r.minPrice) end
      if r.minPrice and r.minPrice > 0 and r.minPrice <= e.limit then keys[#keys + 1] = r.itemKey end
    end
  end
  ns:Debug(("Buy queue: looking up %s: %d rows, %d of them this item, cheapest %s, limit %s."):format(ns.ItemName(e.id),
    rows, ours, cheapest and ns.MoneyPlain(cheapest) or "-", e.limit == math.huge and "any" or ns.MoneyPlain(e.limit)))
  if #keys == 0 then
    -- A list without this item at all isn't the answer yet: the first one can be empty
    -- or the previous search's (owner's test, October 2: every gear flip dropped at once
    -- as "none left", then Battering Hammer was bought by hand under the limit). Wait a
    -- moment for the real one; if nothing comes, it really isn't listed.
    if ours == 0 then
      if not Q.browseWait then
        Q.browseWait = true
        local tok = Q.tok
        C_Timer.After(2.5, function()
          Q.browseWait = nil
          if Q.tok == tok and Q.state == "browse" and Q.cur == e then
            -- The lookup found nothing: search the item itself instead. That shows one
            -- stat version's listings, and any version under the limit will do.
            ns:Debug("Buy queue: no versions found for", ns.ItemName(e.id), "- searching the item itself.")
            Q.key, Q.keys, Q.tries = AH.MakeItemKey(e.id), {}, 0
            search()
          end
        end)
      end
      return
    end
    if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() then return end
    finishTarget(("none left at %s or less."):format(limitText(e)))
    return
  end
  Q.browseWait = nil
  Q.keys = keys
  Q.key, Q.tries = table.remove(Q.keys, 1), 0
  search()
end)

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
  if not (Q.cur and itemID == Q.cur.id) then return end
  if Q.state == "search" or (Q.state == "ready" and Q.plan and Q.plan.kind == "commodity") then planCommodity() end
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  if not (Q.cur and itemKey and itemKey.itemID == Q.cur.id) then return end
  -- Any stat version of the item will do (they all sell to a vendor and disenchant the
  -- same), and the reply's key can differ in detail from the one asked for: matching it
  -- exactly ignored every gear reply (owner's test, October 2).
  if Q.state == "search" or (Q.state == "ready" and Q.plan and Q.plan.kind == "item") then planItem(itemKey) end
end)

-- The final price of a commodity purchase: the total for all of them. Only goes on to
-- "confirm" if the average is still within the limit.
ns:On("COMMODITY_PRICE_UPDATED", function(unitPrice, totalPrice)
  if Q.state ~= "price" or not (Q.cur and Q.plan) then return end
  local total = totalPrice or (unitPrice and unitPrice * Q.plan.qty)
  if total and total <= Q.cur.limit * Q.plan.qty and total <= GetMoney() then
    Q.plan.total = total
    setState("confirm")
  else
    pcall(AH.CancelCommoditiesPurchase)
    Q.note = "The price went up before buying: checking again."
    again()
  end
end)

ns:On("COMMODITY_PRICE_UNAVAILABLE", function()
  if Q.state ~= "price" then return end
  Q.note = "Those listings were just bought: checking again."
  again()
end)

ns:On("COMMODITY_PURCHASE_SUCCEEDED", function()
  if Q.state ~= "buying" or not (Q.plan and Q.plan.kind == "commodity") then return end
  bought(Q.plan.qty, Q.plan.total or Q.plan.cost)
  again(true)
end)

ns:On("COMMODITY_PURCHASE_FAILED", function()
  if Q.state ~= "buying" then return end
  Q.note = "That purchase failed: the listings changed. Checking again."
  again()
end)

local function itemBought()
  if Q.state ~= "buying" or not (Q.plan and Q.plan.kind == "item") then return end
  bought(1, Q.plan.price)
  again(true)
end
ns:On("AUCTION_HOUSE_PURCHASE_COMPLETED", itemBought)
-- Also the chat line, in case the client has no event for it: "You won an auction for X".
local wonPattern
ns:On("CHAT_MSG_SYSTEM", function(msg)
  if Q.state ~= "buying" or type(msg) ~= "string" then return end
  if not wonPattern and ERR_AUCTION_WON_S then
    wonPattern = "^" .. ERR_AUCTION_WON_S:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
  end
  if wonPattern and msg:find(wonPattern) and Q.plan and Q.plan.kind == "item" then itemBought() end
end)

local function failed(_, msg)
  if Q.state ~= "buying" then return end
  if type(msg) == "string" and msg ~= "" then Q.note = msg end
  again()
end
ns:On("UI_ERROR_MESSAGE", failed)
ns:On("AUCTION_HOUSE_SHOW_ERROR", function() failed(nil, "The auction house refused that purchase.") end)

-- If the game won't let an addon buy (it could restrict these calls), say so plainly.
local function blocked(addon, fn)
  if addon ~= ADDON then return end
  ns:Print(("The game blocked %s for addons. Buy from the auction house page instead, and tell us on Discord."):format(tostring(fn)))
  Q.note = "The game blocked buying from the addon."
  setState("idle")
end
ns:On("ADDON_ACTION_BLOCKED", blocked)
ns:On("ADDON_ACTION_FORBIDDEN", blocked)

---------------------------------------------------------------------------
-- Scroll to buy: the mouse wheel down over the top box (with Buy in it) buys. A
-- "scroll anywhere" key binding was tried first, but in the beta it only ever worked
-- over that box (the auction house and other windows take the wheel themselves), so
-- it's just the box now (owner, October 2). This only clears a binding left from before.
---------------------------------------------------------------------------
function updateBinding()
  if side and not InCombatLockdown() and ClearOverrideBindings then ClearOverrideBindings(side) end
end
ns:On("PLAYER_REGEN_ENABLED", updateBinding)

---------------------------------------------------------------------------
-- Queue view
---------------------------------------------------------------------------
local ROW_H = 18
local STRIP_H = 46
local STRIP_BIG = 84    -- a section on its own

-- The sections, in the order they're stacked. setting: the box that turns it on.
-- Disenchanting and good deals were sections too; they moved back out (owner, October 2:
-- the Disenchant finder shows item levels and the Deals tab has the detail, so the queue
-- is for flips and shopping lists).
local LANES = {
  { key = "flips", setting = "flips", title = "Vendor flips" },
  { key = "lists", setting = "lists", title = "Shopping lists" },
}
local LANE_BY_KEY = {}
for _, d in ipairs(LANES) do LANE_BY_KEY[d.key] = d end

local function ticked()
  local out = {}
  for _, d in ipairs(LANES) do if S()[d.setting] then out[#out + 1] = d end end
  return out
end

-- One section on its own does its thing without a click, unless it's shopping lists,
-- which only buy once you've said so (owner, October 2).
local function autoArm()
  local t = ticked()
  if not Q.armed and #t == 1 and t[1].key ~= "lists" then Q.armed = t[1].key end
  -- A section you've unticked can't stay armed.
  if Q.armed and not S()[LANE_BY_KEY[Q.armed].setting] then
    dropCurrent()
    Q.armed = nil
  end
end

local function reasonLine(e)
  if not e then return "" end
  if e.reason == "flip" then return ("Vendor flip: a vendor pays %s."):format(money(e.worth)) end
  if e.reason == "list" then
    return ("Shopping list %s: up to %s%s."):format(e.list or "", limitText(e),
      e.want and (", %d more wanted"):format(e.want) or "")
  end
  return ""
end

-- The armed section's strip: what's happening now. Returns line 1, line 2, button text.
local function statusText()
  local e, p = Q.cur, Q.plan
  local name = e and ("|cffffffff" .. ns.ItemName(e.id) .. "|r") or ""
  local st = Q.state
  if st == "wait" then
    if Q.waitText then return Q.waitText, "Carries on a few seconds after you stop, or click Buy.", "Buy" end
    return ("Waiting for %s..."):format(Q.waitFor or "the auction house"), "", "..."
  end
  if st == "browse" or st == "search" then return "Looking for " .. name .. "...", reasonLine(e), "..." end
  if st == "ready" and p and p.kind == "commodity" then
    return ("Buy %d %s for %s"):format(p.qty, name, money(p.cost)),
      ("%s each, up to %s."):format(money(p.cost / p.qty), limitText(e)), "Buy"
  end
  if st == "price" then return "Getting the final price for " .. name .. "...", "", "..." end
  if st == "confirm" and p then
    return ("|cffffd100Confirm:|r %d %s for %s"):format(p.qty, name, money(p.total)),
      ("%s each. Scroll or click again to buy them."):format(money(p.total / p.qty)), "Confirm"
  end
  if st == "ready" and p and p.kind == "item" then
    return ("Buy %s for %s"):format(name, money(p.price)),
      ("%d at or under %s."):format(p.count, limitText(e)), "Buy"
  end
  if st == "buying" then return "Buying " .. name .. "...", "", "..." end
  local waiting = 0
  for _, x in ipairs(laneList()) do if x.waiting then waiting = waiting + 1 end end
  return "Nothing to buy right now.", Q.note or (waiting > 0
    and ("%d waiting for a lower price (greyed below)."):format(waiting)
    or (S().wheel and "New finds show up here; scroll down over this strip to buy them."
      or "Keep this open: new finds show up here.")), "Check"
end

-- A section that isn't armed: what it has, and how to start it.
local function idleText(d)
  local list = Q.lanes[d.key] or {}
  local ready, best = 0, nil
  for _, x in ipairs(list) do
    if not x.waiting then
      ready = ready + 1
      best = best or x
    end
  end
  if ready == 0 then return "|cff888888Nothing to buy right now.|r", "|cff888888Click here to make this the section you buy from.|r" end
  return ("|cff888888%d to buy, best: %s|r"):format(ready, ns.ItemName(best.id)),
    "|cff888888Click here (or scroll over this strip) to buy from this section.|r"
end

local function laneRow(L, i)
  local r = L.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, L.content)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.current = T:Fill(r, { T.accent[1], T.accent[2], T.accent[3], 0.18 }, "BORDER")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.12)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = T:Text(r, 11)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.name:SetWidth(176)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.limit, r.n, r.profit = T:Text(r, 11), T:Text(r, 11), T:Text(r, 11)
  -- Profit gets the widest column: "10g 45s 64c" ran into Cheap (owner, October 2).
  r.limit:SetPoint("RIGHT", r, "LEFT", 254, 0)
  r.n:SetPoint("RIGHT", r, "LEFT", 292, 0)
  r.profit:SetPoint("RIGHT", r, "LEFT", 392, 0)
  r:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      skipped[self.entry.id] = true
      if Q.cur == self.entry then finishTarget("skipped.") end
      local list = Q.lanes[self.entry.lane] or {}
      for k, x in ipairs(list) do if x == self.entry then table.remove(list, k); break end end
      refreshQueue()
    else
      choose(self.entry)
    end
  end)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(self.entry.id)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(reasonLine(self.entry), T.accent[1], T.accent[2], T.accent[3], true)
    if self.entry.waiting then
      GameTooltip:AddLine("Waiting: none listed at or under your price at the last search. Raise Most each on the list, or Search list again later.", 1, 0.82, 0, true)
    end
    GameTooltip:AddLine("Click to buy this one next (its section becomes the one you buy from). Right-click to skip it until you reload.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  L.rows[i] = r
  return r
end

-- One section: a strip on top (what's next, and Buy) and its list below.
local function buildLane(v, d)
  local L = CreateFrame("Frame", nil, v)
  L.def = d
  T:Fill(L, { 1, 1, 1, 0.015 })
  T:Border(L)
  L:EnableMouse(true)
  L:SetScript("OnMouseDown", function() arm(d.key) end)

  local strip = CreateFrame("Button", nil, L)
  strip:SetPoint("TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", -1, -1)
  strip:SetHeight(STRIP_H)
  L.strip = strip
  L.stripBg = T:Fill(strip, { 1, 1, 1, 0.04 })
  strip:SetScript("OnClick", function() arm(d.key) end)
  -- The wheel over the strip: makes this the section you buy from, then (with Scroll to
  -- buy ticked) each tick down buys. Over the list below, the wheel scrolls the list.
  strip:EnableMouseWheel(true)
  strip:SetScript("OnMouseWheel", function(_, delta)
    if delta >= 0 then return end
    if Q.armed ~= d.key then arm(d.key)
    elseif S().wheel then ns:BuyQueueAct() end
  end)
  L.title = T:Text(strip, 11, T.accent)
  L.title:SetPoint("TOPLEFT", 6, -4)
  L.title:SetPoint("RIGHT", strip, "RIGHT", -100, 0)
  L.title:SetJustifyH("LEFT")
  L.title:SetWordWrap(false)
  L.icon = strip:CreateTexture(nil, "ARTWORK")
  L.icon:SetSize(24, 24)
  L.icon:SetPoint("TOPLEFT", 6, -18)
  L.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  L.line1 = T:Text(strip, 12)
  L.line1:SetPoint("TOPLEFT", L.icon, "TOPRIGHT", 6, 1)
  L.line1:SetPoint("RIGHT", strip, "RIGHT", -100, 0)
  L.line1:SetJustifyH("LEFT")
  L.line1:SetWordWrap(false)
  L.line2 = T:Text(strip, 10, T.dim)
  L.line2:SetPoint("TOPLEFT", L.line1, "BOTTOMLEFT", 0, -2)
  L.line2:SetPoint("RIGHT", strip, "RIGHT", -100, 0)
  L.line2:SetJustifyH("LEFT")
  L.line2:SetWordWrap(false)
  L.buy = T:Button(strip, "Buy", 72, function()
    if Q.armed ~= d.key then arm(d.key) else ns:BuyQueueAct() end
  end, 34)
  L.buy:SetPoint("RIGHT", -6, 0)
  L.buy:GetFontString():SetFont(T.font, 14, "")

  local header = CreateFrame("Frame", nil, L)
  header:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 4, -2)
  header:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", -4, -2)
  header:SetHeight(14)
  for _, c in ipairs({ { "Item", 4, "LEFT" }, { "Up to", 250, "RIGHT" }, { "Cheap", 288, "RIGHT" },
                       { d.key == "lists" and "Now" or "Profit", 388, "RIGHT" } }) do
    local fs = T:Text(header, 10, T.dim)
    if c[3] == "LEFT" then fs:SetPoint("LEFT", c[2], 0) else fs:SetPoint("RIGHT", header, "LEFT", c[2], 0) end
    fs:SetText(c[1])
  end
  L.sf, L.content = T:Scroll(L)
  L.sf:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -1)
  L.sf:SetPoint("BOTTOMRIGHT", -3, 3)
  L.rows = {}
  return L
end

local function buildQueueView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetPoint("TOPLEFT", 0, -30)
  v:SetPoint("BOTTOMRIGHT")

  -- A toolbar band under the tabs, set apart by its shade and a line below (owner,
  -- October 2: a cleaner split between the tabs and the buttons).
  local bar = CreateFrame("Frame", nil, v)
  bar:SetPoint("TOPLEFT", 1, 0)
  bar:SetPoint("TOPRIGHT", -1, 0)
  bar:SetHeight(30)
  T:Fill(bar, { 1, 1, 1, 0.035 })
  local line = bar:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)
  line:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.25)

  -- Which sections to show, and Scroll to buy, on one row.
  local x = 12
  for _, d in ipairs(LANES) do
    local cb = T:Check(bar, function(self) S()[d.setting] = self:GetChecked(); rebuildNow() end)
    cb:SetPoint("LEFT", x, 0)
    cb.label:SetText(d.title)
    cb:SetChecked(S()[d.setting])
    x = x + 20 + cb.label:GetStringWidth() + 18
  end
  local wheel = T:Check(bar, function(self) S().wheel = self:GetChecked(); refreshQueue() end)
  wheel.label:SetText("Scroll to buy")
  -- The label sits to the right of the box: move the pair left by the label's width.
  wheel:ClearAllPoints()
  wheel:SetPoint("RIGHT", bar, "RIGHT", -(wheel.label:GetStringWidth() + 18), 0)
  wheel:SetChecked(S().wheel)
  wheel:SetHitRectInsets(0, -(wheel.label:GetStringWidth() + 8), 0, 0)
  wheel:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Scroll to buy", 1, 1, 1)
    GameTooltip:AddLine("With the mouse over the top strip of the section you're buying from (the one with the bright border), each tick of the wheel down buys the next item; stacks of materials take a second tick to confirm. It keeps working while the section is empty, so new flips can be bought the moment they show up. Off: only clicking Buy buys.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  wheel:SetScript("OnLeave", function() GameTooltip:Hide() end)
  v.wheel = wheel

  v.lanes = {}
  for _, d in ipairs(LANES) do v.lanes[d.key] = buildLane(v, d) end
  v.empty = T:Text(v, 12, T.dim)
  v.empty:SetPoint("TOP", 0, -80)
  v.empty:SetText("Tick what to buy above.")

  local refresh = T:Button(v, "Refresh", 80, function() Q.built = 0; rebuildNow() end, 22)
  refresh:SetPoint("BOTTOMLEFT", 10, 8)
  v.totals = T:Text(v, 11, T.dim)
  v.totals:SetPoint("LEFT", refresh, "RIGHT", 10, 0)
  v.totals:SetPoint("RIGHT", v, "RIGHT", -10, 0)
  v.totals:SetJustifyH("LEFT")
  v:SetScript("OnSizeChanged", function() if refreshQueue then refreshQueue() end end)
  return v
end

-- Stack the ticked sections, splitting the height between them.
local function layoutLanes(v)
  local t = ticked()
  local top, bottom, gap = 38, 36, 6
  local h = v:GetHeight() - top - bottom
  local n = #t
  v.empty:SetShown(n == 0)
  local each = n > 0 and math.floor((h - gap * (n - 1)) / n) or 0
  local on = {}
  for i, d in ipairs(t) do
    local L = v.lanes[d.key]
    -- One section on its own gets a big strip and Buy button: a large target to rest
    -- the mouse on and scroll while farming (owner, October 2).
    local big = n == 1
    L.strip:SetHeight(big and STRIP_BIG or STRIP_H)
    L.buy:SetSize(big and 88 or 72, big and 60 or 34)
    L.buy:GetFontString():SetFont(T.font, big and 16 or 14, "")
    L.icon:SetSize(big and 36 or 24, big and 36 or 24)
    L.line1:SetFont(T.font, big and 13 or 12, "")
    L.line2:SetWordWrap(big)   -- room for two lines in the big strip
    L:ClearAllPoints()
    L:SetPoint("TOPLEFT", 6, -(top + (i - 1) * (each + gap)))
    L:SetPoint("RIGHT", v, "RIGHT", -6, 0)
    L:SetHeight(each)
    L:Show()
    on[d.key] = true
  end
  for key, L in pairs(v.lanes) do if not on[key] then L:Hide() end end
end

local function fillLane(L)
  local d, armed = L.def, Q.armed == L.def.key
  local list = Q.lanes[d.key] or {}
  -- The section you buy from has a bright border; the others are dimmed.
  for _, e in ipairs(L.borders or {}) do
    if armed then e:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.9)
    else e:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4]) end
  end
  L.stripBg:SetColorTexture(1, 1, 1, armed and 0.07 or 0.03)
  local ready = 0
  for _, x in ipairs(list) do if not x.waiting then ready = ready + 1 end end
  -- Where to scroll, said in the section itself rather than on the checkbox.
  L.title:SetText(("%s  |cff888888%d|r%s"):format(d.title, ready,
    armed and (S().wheel and "   |cff7fd39cbuying here, scroll this strip|r"
      or "   |cff7fd39cbuying from this one|r") or ""))
  local a, b, label
  if armed then
    a, b, label = statusText()
    if Q.note and Q.state == "idle" then b = Q.note end
    L.icon:SetTexture(Q.cur and ns:ItemIcon(Q.cur.id) or "Interface\\Icons\\INV_Misc_Coin_01")
  else
    a, b = idleText(d)
    label = "Start"
    L.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  end
  L.icon:SetDesaturated(not armed)
  L.line1:SetText(a)
  L.line2:SetText(b or "")
  L.buy:SetText(label)
  L.buy:SetSelected(armed and Q.state == "confirm")

  local width = L.sf:GetWidth() - 12
  L.content:SetWidth(width)
  for i, e in ipairs(list) do
    local r = laneRow(L, i)
    r.entry = e
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", L.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    r.current:SetShown(armed and e == Q.cur)
    r.icon:SetTexture(ns:ItemIcon(e.id))
    r.icon:SetDesaturated(e.waiting and true or false)
    r.name:SetText(e.waiting and ("|cff888888" .. ns.ItemName(e.id) .. "|r") or ns.ItemName(e.id))
    r.limit:SetText(e.any and "any" or money(e.limit))
    r.n:SetText(e.waiting and "0" or (e.n and tostring(e.n) or "?"))
    if d.key == "lists" then
      local rec = (ns.db.prices[ns.MarketKey()] or {})[e.id]
      local now = rec and rec.m and not rec.none and ns.MoneyPlain(rec.m) or "none"
      r.profit:SetText(e.waiting and ("|cff888888" .. now .. "|r") or now)
    else
      r.profit:SetText(e.profit and e.profit > 0 and ("|cff7fd39c" .. money(e.profit) .. "|r") or "")
    end
    r:Show()
  end
  for i = #list + 1, #L.rows do L.rows[i]:Hide() end
  L.content:SetHeight(math.max(#list * ROW_H, ROW_H))
  L.sf.UpdateScrollBar()
end

refreshQueue = function()
  local v = queueView
  if not v or not v:IsVisible() then return end
  autoArm()
  layoutLanes(v)
  for _, d in ipairs(ticked()) do fillLane(v.lanes[d.key]) end
  local total = 0
  for _, d in ipairs(ticked()) do
    for _, x in ipairs(Q.lanes[d.key] or {}) do if not x.waiting then total = total + 1 end end
  end
  v.totals:SetText(Q.bought > 0 and ("Bought %d for %s%s."):format(Q.bought, money(Q.spent),
    Q.worth > 0 and (", worth about %s"):format(money(Q.worth)) or "")
    or (Q.armed and ("%d to buy. Click a section to buy from it."):format(total)
      or "Click a section (or scroll over its strip) to buy from it."))
end
refreshQueue = ns.Timed("Buy queue view", refreshQueue)

---------------------------------------------------------------------------
-- Shopping lists view
---------------------------------------------------------------------------
StaticPopupDialogs["FOREVER_LEDGER_LIST_NAME"] = {
  text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 40,
  OnShow = function(self, data)
    local eb = self.editBox or self.EditBox
    eb:SetText(data and data.default or "")
    eb:HighlightText()
  end,
  OnAccept = function(self, data)
    local eb = self.editBox or self.EditBox
    local name = eb:GetText():gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" then data.fn(name) end
  end,
  EditBoxOnEnterPressed = function(self, data)
    local name = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" then data.fn(name) end
    self:GetParent():Hide()
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["FOREVER_LEDGER_LIST_DELETE"] = {
  text = "%s", button1 = YES or "Yes", button2 = NO or "No",
  OnAccept = function(_, data) data.fn() end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

local refreshLists

local function currentList() return (ns:CurrentShoppingList()) end

local function addFromBox(v)
  local list = currentList() or ns:NewShoppingList("Shopping list")
  local id = v.pendingID or ns:ResolveItem(v.add:GetText())
  if not id then
    ns:Print("Couldn't find that item. Shift-click it from your bags or a chat link, drag it here, or type its exact name.")
    return
  end
  local max = ns.ParseMoneyLoose(v.max:GetText(), "g")
  if not max then
    ns:Print("Couldn't read that price. Try 2g 50s, 1.5g, 25s, 75c, a plain number for gold, or any.")
    v.max:SetFocus()
    return
  end
  local qty = tonumber(v.qty:GetText())
  ns:AddToShoppingList(list, id, max, qty and qty > 0 and math.floor(qty) or nil)
  unpark({ id })
  v.add:SetText("")
  v.max:SetText("")
  v.qty:SetText("")
  v.pendingID = nil
  v.sug:Hide()
  v.add:ClearFocus(); v.max:ClearFocus(); v.qty:ClearFocus()
  Q.built = 0
  refreshLists()
end

-- A text box with a grey hint inside while it's empty.
local function hinted(parent, width, hint, justify)
  local eb = T:EditBox(parent, width, justify)
  local fs = T:Text(eb, 11, T.section)
  if justify == "LEFT" then fs:SetPoint("LEFT", 6, 0) else fs:SetPoint("CENTER") end
  fs:SetText(hint)
  local function update(self) fs:SetShown(self:GetText() == "" and not self:HasFocus()) end
  eb:SetScript("OnTextChanged", update)
  eb:SetScript("OnEditFocusGained", function() fs:Hide() end)
  eb:SetScript("OnEditFocusLost", update)
  return eb
end

-- Columns (x from the left of a row).
local C = { name = 22, get = 160, max = 206, want = 274, have = 336, now = 376, x = 380 }

local function buildListsView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetPoint("TOPLEFT", 0, -30)
  v:SetPoint("BOTTOMRIGHT")
  v:EnableMouse(true)

  -- Which list: a dropdown of every list (owner, October 2: instead of arrows), and
  -- New / Rename / Delete.
  local pick = T:Button(v, "", 210, nil, 22)
  pick:SetPoint("TOPLEFT", 10, -8)
  v.title = pick:GetFontString()
  v.title:ClearAllPoints()
  v.title:SetPoint("LEFT", 8, 0)
  v.title:SetPoint("RIGHT", -20, 0)
  v.title:SetJustifyH("LEFT")
  v.title:SetWordWrap(false)
  local arrow = T:Text(pick, 11, T.dim)
  arrow:SetPoint("RIGHT", -7, 0)
  arrow:SetText("v")

  -- The menu: up to 10 names at a time, scrolling if there are more.
  local menu = CreateFrame("Frame", nil, v)
  menu:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -2)
  menu:SetWidth(260)
  -- Above the panel, which is itself drawn in the dialog layer when it floats away from
  -- the auction house: in the same layer, the panel's buttons and ticks showed through
  -- the menu (owner's screenshot, October 3).
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetToplevel(true)
  menu:EnableMouse(true)
  T:Fill(menu, { 0.05, 0.05, 0.05, 0.98 })
  T:Border(menu)
  menu.sf, menu.content = T:Scroll(menu)
  menu.sf:SetPoint("TOPLEFT", 2, -2)
  menu.sf:SetPoint("BOTTOMRIGHT", -2, 2)
  menu.buttons = {}
  menu:Hide()
  local function fillMenu()
    local lists = ns:ShoppingLists()
    local _, cur = ns:CurrentShoppingList()
    menu.content:SetWidth(menu:GetWidth() - 16)
    for i, l in ipairs(lists) do
      local b = menu.buttons[i]
      if not b then
        b = CreateFrame("Button", nil, menu.content)
        b:SetHeight(20)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
        b.text = T:Text(b, 12)
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self)
          ns:SelectShoppingList(self.index)
          menu:Hide()
          refreshLists()
        end)
        menu.buttons[i] = b
      end
      b.index = i
      b:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
      b:SetPoint("RIGHT", 0, 0)
      local doneN = 0
      for _, e in ipairs(l.items) do if ns:ItemDone(e, l) then doneN = doneN + 1 end end
      b.text:SetText(("%s%s|r  |cff888888%d/%d%s|r"):format(i == cur and T:AccentCode() or "|cffffffff", l.name,
        doneN, #l.items, l.on and "" or ", not in queue"))
      b:Show()
    end
    for i = #lists + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu.content:SetHeight(math.max(#lists * 20, 20))
    menu:SetHeight(math.min(#lists, 10) * 20 + 4)
    menu.sf.UpdateScrollBar()
  end
  pick:SetScript("OnClick", function()
    if menu:IsShown() or #ns:ShoppingLists() == 0 then menu:Hide(); return end
    fillMenu()
    menu:Show()
    menu:Raise()
  end)
  v:HookScript("OnHide", function() menu:Hide() end)

  local new = T:Button(v, "New", 50, function()
    StaticPopup_Show("FOREVER_LEDGER_LIST_NAME", "Name for the new shopping list:", nil,
      { fn = function(name) ns:NewShoppingList(name); refreshLists() end })
  end, 22)
  new:SetPoint("LEFT", pick, "RIGHT", 6, 0)
  local rename = T:Button(v, "Rename", 58, function()
    local list = currentList()
    if not list then return end
    StaticPopup_Show("FOREVER_LEDGER_LIST_NAME", "New name for this list:", nil,
      { default = list.name, fn = function(name) list.name = name; refreshLists() end })
  end, 22)
  rename:SetPoint("LEFT", new, "RIGHT", 4, 0)
  local delete = T:Button(v, "Delete", 54, function()
    local list, i = ns:CurrentShoppingList()
    if not list then return end
    StaticPopup_Show("FOREVER_LEDGER_LIST_DELETE", ("Delete the shopping list \"%s\"?"):format(list.name), nil,
      { fn = function() ns:DeleteShoppingList(i); Q.built = 0; refreshLists() end })
  end, 22)
  delete:SetPoint("LEFT", rename, "RIGHT", 4, 0)
  v.listButtons = { rename, delete }

  v.on = T:Check(v, function(self)
    local list = currentList()
    if list then list.on = self:GetChecked(); Q.built = 0 end
  end)
  v.on:SetPoint("TOPLEFT", 12, -40)
  v.on:SetHitRectInsets(0, -170, 0, 0)
  v.on.label:SetText("Use in the buy queue")

  -- Any price: the list is what you need, whatever it costs (raid prep).
  v.any = T:Check(v, function(self)
    local list = currentList()
    if list then list.anyPrice = self:GetChecked() or nil; Q.built = 0; refreshLists() end
  end)
  v.any:SetPoint("TOPLEFT", 200, -40)
  v.any:SetHitRectInsets(0, -170, 0, 0)
  v.any.label:SetText("Any price (just what I need)")
  v.any:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Any price", 1, 1, 1)
    GameTooltip:AddLine("For lists where you just need the items, like raid prep: prices are ignored and the buy queue buys the cheapest ones until you have the number you want (1 if no number is set). It never pays more than 3 times an item's usual price, so a joke listing can't slip in. Type any in one item's price for just that item.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  v.any:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- What Want means for this list (owner, October 2: both, made clear).
  local wantLabel = T:Text(v, 12, T.dim)
  wantLabel:SetPoint("TOPLEFT", 12, -64)
  wantLabel:SetText("Want means:")
  v.wantMode = T:Choice(v, { { value = "keep", label = "Keep this many" }, { value = "buy", label = "Buy this many" } }, function(value)
    local list = currentList()
    if not list then return end
    list.wantMode = value == "buy" and "buy" or nil
    -- A different meaning: start counting afresh.
    ns:BuyListAgain(list)
    local ids = {}
    for _, e in ipairs(list.items) do ids[#ids + 1] = e.id end
    unpark(ids)
    refreshLists()
  end)
  v.wantMode:SetPoint("LEFT", wantLabel, "RIGHT", 8, 0)
  for _, b in ipairs(v.wantMode.buttons) do
    b:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      if self.value == "keep" then
        GameTooltip:AddLine("Keep this many", 1, 1, 1)
        GameTooltip:AddLine("Want is how many you want to have: bags, bank and what's in the mail count. The queue only buys what you're short of. After you use some, Buy again tops you back up. Good for raid consumables you keep in stock.", nil, nil, nil, true)
      else
        GameTooltip:AddLine("Buy this many", 1, 1, 1)
        GameTooltip:AddLine("Want is how many to buy, whatever you already have. The list counts what's been bought since Buy again (the Bought column). Buy again buys the whole amount again. Good for \"I need 20 of these for a craft\".", nil, nil, nil, true)
      end
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end

  -- Add an item: shift-click, drag, or type its name; the most you'd pay; how many.
  v.add = hinted(v, 196, "Shift-click, drag or type an item", "LEFT")
  v.add:SetPoint("TOPLEFT", 10, -88)
  v.add:HookScript("OnTextChanged", function(self) v.pendingID = ns.ItemIDFromLink(self:GetText()) end)

  -- Suggestions while you type a name (owner, October 2): up to 8 items whose name
  -- matches, including ones the game hasn't loaded. Click one, or Enter for the top one.
  local sug = CreateFrame("Frame", nil, v)
  sug:SetPoint("TOPLEFT", v.add, "BOTTOMLEFT", 0, -2)
  sug:SetWidth(300)
  sug:SetFrameStrata("DIALOG")
  T:Fill(sug, { 0.05, 0.05, 0.05, 0.98 })
  T:Border(sug)
  sug.buttons = {}
  sug:Hide()
  v.sug = sug
  local function pick(e)
    v.add:SetText(e.name)
    v.pendingID = e.id
    sug:Hide()
    v.max:SetFocus()
  end
  local function suggest(text)
    local found = (not ns.ItemIDFromLink(text)) and ns:FindItemsByName(text, 8) or {}
    v.suggestions = found
    if #found == 0 then sug:Hide(); return end
    for i, e in ipairs(found) do
      local b = sug.buttons[i]
      if not b then
        b = CreateFrame("Button", nil, sug)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
        b:SetPoint("RIGHT", -2, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 2, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.text = T:Text(b, 11)
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
        b.text:SetPoint("RIGHT", -4, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self) pick(self.e) end)
        sug.buttons[i] = b
      end
      b.e = e
      b.icon:SetTexture(ns:ItemIcon(e.id))
      b.text:SetText(e.bound and (e.name .. " |cff888888(can't be bought)|r") or e.name)
      b:Show()
    end
    for i = #found + 1, #sug.buttons do sug.buttons[i]:Hide() end
    sug:SetHeight(#found * 20 + 4)
    sug:Show()
  end
  v.add:HookScript("OnTextChanged", function(self, userInput) if userInput then suggest(self:GetText()) end end)
  -- A click on a suggestion takes the focus first, so hide a moment later.
  v.add:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() if not v.add:HasFocus() then sug:Hide() end end) end)
  v.add:SetScript("OnEnterPressed", function()
    if sug:IsShown() and not v.pendingID and v.suggestions and v.suggestions[1] then pick(v.suggestions[1]); return end
    addFromBox(v)
  end)
  v.add:SetScript("OnEscapePressed", function(self) sug:Hide(); self:ClearFocus() end)
  local function drop()
    local kind, id, link = GetCursorInfo()
    if kind == "item" and id then
      ClearCursor()
      v.add:SetText(link or ns.ItemName(id))
      v.pendingID = id
      v.max:SetFocus()
    end
  end
  v.add:SetScript("OnReceiveDrag", drop)
  v.add:SetScript("OnMouseDown", function() if GetCursorInfo() then drop() end end)
  v:SetScript("OnReceiveDrag", drop)
  v.max = hinted(v, 70, "max each")
  v.max.allowAny = true
  T:MoneyPreview(v.max, "g")
  v.max:SetPoint("LEFT", v.add, "RIGHT", 4, 0)
  v.max:SetScript("OnEnterPressed", function() addFromBox(v) end)
  v.qty = hinted(v, 44, "want")
  v.qty:SetPoint("LEFT", v.max, "RIGHT", 4, 0)
  v.qty:SetScript("OnEnterPressed", function() addFromBox(v) end)
  local addB = T:Button(v, "Add", 60, function() addFromBox(v) end, 22)
  addB:SetPoint("LEFT", v.qty, "RIGHT", 4, 0)

  local header = CreateFrame("Frame", nil, v)
  header:SetPoint("TOPLEFT", 6, -116)
  header:SetPoint("TOPRIGHT", -6, -116)
  header:SetHeight(20)
  T:Fill(header, { 1, 1, 1, 0.05 })
  v.headers = {}
  for _, c in ipairs({ { "Item", 8, "LEFT" }, { "Get", C.get, "LEFT" }, { "Most each", C.max, "LEFT" }, { "Want", C.want, "LEFT" },
                       { "Have", C.have, "RIGHT" }, { "Now", C.now, "RIGHT" } }) do
    local fs = T:Text(header, 11, T.dim)
    if c[3] == "LEFT" then fs:SetPoint("LEFT", c[2], 0) else fs:SetPoint("RIGHT", header, "LEFT", c[2], 0) end
    fs:SetText(c[1])
    v.headers[c[1]] = fs
  end
  -- "Bought" is wider than "Have": nudge it right so it doesn't run into Want.
  v.headers.Have:ClearAllPoints()
  v.headers.Have:SetPoint("RIGHT", header, "LEFT", C.have + 8, 0)
  v.sf, v.content = T:Scroll(v)
  v.sf:SetPoint("TOPLEFT", 6, -138)
  v.sf:SetPoint("BOTTOMRIGHT", -6, 58)
  v.rows = {}

  local searchB = T:Button(v, "Search list", 96, function()
    local list = currentList()
    if not list then return end
    local ids, seen = {}, {}
    local function add(id) if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
    for _, e in ipairs(list.items) do if e.mode ~= "craft" then add(e.id) end end
    for _, m in ipairs((ns:ListMaterials(list))) do if not m.vendor then add(m.id) end end
    ns.Scan:StartList(ids, list.name)
  end, 22)
  searchB:SetPoint("BOTTOMLEFT", 10, 8)
  v.searchB = searchB

  -- Share a list as text (Discord, a friend), or import one (Magic, October 2).
  local share = T:Button(v, "Share", 70, function()
    local list = currentList()
    if not list then return end
    ns:ShowTextWindow("Share \"" .. list.name .. "\"",
      "Press Ctrl+C to copy, then paste it in Discord (between ``` marks keeps it tidy) or send it to a friend. They paste it into Import on their Shopping lists tab.",
      ns:ExportShoppingList(list))
  end, 22)
  share:SetPoint("BOTTOMRIGHT", -84, 8)
  -- Buy again: everything on the list counts as not done, so the queue buys what's
  -- missing (next raid).
  local again = T:Button(v, "Buy again", 80, function()
    local list = currentList()
    if not list then return end
    ns:BuyListAgain(list)
    local ids = {}
    for _, e in ipairs(list.items) do ids[#ids + 1] = e.id end
    for _, m in ipairs((ns:ListMaterials(list))) do ids[#ids + 1] = m.id end
    unpark(ids)
    ns:Print(("%s: everything you're short of goes back in the buy queue."):format(list.name))
    refreshLists()
  end, 22)
  again:SetPoint("RIGHT", share, "LEFT", -4, 0)
  again:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Buy again", 1, 1, 1)
    GameTooltip:AddLine("Items stay done once you've had enough of them, even after you use some, so the queue doesn't keep refilling them. Click this to start the list over: whatever you're short of now goes back in the queue.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  again:HookScript("OnLeave", function() GameTooltip:Hide() end)
  v.share = share
  local import = T:Button(v, "Import", 70, function()
    ns:ShowTextWindow("Import shopping lists",
      "Paste a shared list with Ctrl+V and click Import. A plain list of item names (or Wowhead links), one per line, works too. Your own lists are never changed: an import with the same name is added as a new list.",
      "", "Import", function(text)
        local ok, msg = ns:ImportShoppingLists(text)
        if ok then Q.built = 0; refreshLists() end
        return ok, msg
      end)
  end, 22)
  import:SetPoint("BOTTOMRIGHT", -10, 8)

  v.info = T:Text(v, 11, T.dim)
  v.info:SetPoint("BOTTOMLEFT", 12, 36)
  v.info:SetPoint("RIGHT", v, "RIGHT", -10, 0)
  v.info:SetJustifyH("LEFT")
  v.info:SetWordWrap(false)

  -- Keep Now and Have current (a list search, things bought or crafted).
  local elapsed = 0
  v:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 1 then elapsed = 0; refreshLists() end
  end)
  return v
end

-- Shift-click an item while the Shopping lists tab is open: it goes on the list (or in
-- the add box, if you're typing there). The auction house's own search box gets it too;
-- that's Blizzard's and can't be stopped (owner, October 2).
local function onModifiedClick(link)
  local v = listsView
  if not (v and v:IsVisible() and type(link) == "string") then return end
  if IsModifiedClick and not IsModifiedClick("CHATLINK") then return end
  local id = ns.ItemIDFromLink(link)
  if not id then return end
  if v.add:HasFocus() or v.max:HasFocus() or v.qty:HasFocus() then
    v.add:SetText(link)
    v.pendingID = id
    return
  end
  local list = currentList() or ns:NewShoppingList("Shopping list")
  ns:AddToShoppingList(list, id)
  unpark({ id })
  Q.built = 0
  ns:Print(("Added %s to %s. Set the most you'd pay and how many you want on the list."):format(link, list.name))
  refreshLists()
end
if HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", onModifiedClick) end

local function listRow(i)
  local v = listsView
  local r = v.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, v.content)
  r:SetHeight(24)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.hit = CreateFrame("Button", nil, r)
  r.hit:SetPoint("LEFT", 0, 0)
  r.hit:SetSize(C.get - 4, 24)
  r.icon = r.hit:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = T:Text(r.hit, 11)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.name:SetWidth(C.get - C.name - 6)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.hit:SetScript("OnEnter", function(self)
    local id = (r.kind == "item" and r.entry.id) or (r.kind == "mat" and r.mat.id)
    if not id then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(id)
    if r.kind == "item" and r.entry.mode == "craft" then
      local recipe = ns:RecipeFor(id)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(recipe and ("Crafted with %s%s."):format(recipe.prof or "a profession", recipe.who and (" (" .. recipe.who .. ")") or "")
        or "No recipe known for it yet.", T.accent[1], T.accent[2], T.accent[3], true)
      if recipe and recipe.classic then
        GameTooltip:AddLine(("Original Classic recipe (skill %d, makes %g): Forever may differ. Open the profession window on a character who knows it to use theirs."):format(
          recipe.skill or 0, recipe.oq or 1), 0.7, 0.7, 0.7, true)
      end
    end
    GameTooltip:Show()
  end)
  r.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

  r.mode = T:Button(r, "Buy", 42, function()
    r.entry.mode = r.entry.mode ~= "craft" and "craft" or nil
    Q.built = 0
    refreshLists()
  end, 20)
  r.mode:SetPoint("LEFT", C.get, 0)
  r.mode:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Buy or craft", 1, 1, 1)
    GameTooltip:AddLine("Buy: get it on the auction house, up to the price you set. Craft: make it instead; the materials you're short of are listed below and go in the buy queue.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  r.mode:HookScript("OnLeave", function() GameTooltip:Hide() end)
  r.kindText = T:Text(r, 11, T.section)
  r.kindText:SetPoint("LEFT", C.get + 4, 0)

  r.max = T:MoneyBox(r, function(value)
    if r.kind == "item" then
      r.entry.max = value
    elseif r.kind == "mat" then
      local list = currentList()
      if list then
        list.matMax = list.matMax or {}
        list.matMax[r.mat.id] = value ~= 0 and value or nil
      end
    end
    unpark({ (r.kind == "item" and r.entry.id) or (r.mat and r.mat.id) })
  end, "g", true)
  r.max:SetWidth(64)
  r.max:SetPoint("LEFT", C.max, 0)
  r.maxText = T:Text(r, 11, T.section)
  r.maxText:SetPoint("LEFT", C.max + 6, 0)

  r.qty = T:EditBox(r, 30)
  r.qty:SetPoint("LEFT", C.want, 0)
  r.qty:SetScript("OnEditFocusLost", function(self)
    local n = tonumber(self:GetText())
    local old = r.entry.qty
    r.entry.qty = n and n > 0 and math.floor(n) or nil
    -- Wanting more than you have opens a done item again.
    if r.entry.qty ~= old and ns:HaveCount(r.entry.id) < (r.entry.qty or 1) then r.entry.done = nil end
    self:SetText(r.entry.qty and tostring(r.entry.qty) or "")
    if r.entry.qty ~= old then unpark({ r.entry.id }) end
    -- A crate list: the crate's Want is how many crates, so its items follow (Crates.lua).
    local list = ns:CurrentShoppingList()
    if r.entry.qty ~= old and list and list.crateID == r.entry.id and ns.ScaleCrateList then
      unpark(ns:ScaleCrateList(list))
    end
  end)
  r.need = T:Text(r, 11)
  r.need:SetPoint("RIGHT", r, "LEFT", C.want + 28, 0)
  r.have = T:Text(r, 11, T.dim)
  r.have:SetPoint("RIGHT", r, "LEFT", C.have, 0)
  -- Hover Have: where they are (bags, bank, other characters on this account).
  r.haveHit = CreateFrame("Frame", nil, r)
  r.haveHit:SetPoint("LEFT", C.want + 32, 0)
  r.haveHit:SetSize(C.have - C.want - 30, 22)
  r.haveHit:EnableMouse(true)
  r.haveHit:SetScript("OnEnter", function(self)
    local id = (r.kind == "item" and r.entry.id) or (r.kind == "mat" and r.mat.id)
    if not id then return end
    local bags, bank, alts, byAlt = ns:ItemLocations(id)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.ItemName(id), 1, 1, 1)
    GameTooltip:AddDoubleLine("Bags", tostring(bags), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Bank", tostring(bank), 0.8, 0.8, 0.8, 1, 1, 1)
    local mail = ns:InTheMail(id)
    if mail > 0 then GameTooltip:AddDoubleLine("In the mail (bought)", tostring(mail), 0.8, 0.8, 0.8, 1, 1, 1) end
    for name, n in pairs(byAlt) do GameTooltip:AddDoubleLine(name, tostring(n), 0.8, 0.8, 0.8, 1, 1, 1) end
    if ns:BuyMode(currentList()) then
      GameTooltip:AddLine("This list is set to Buy this many: the column counts what's been bought since Buy again (auction house purchases, from the queue or by hand). Where you have them is shown above.", 0.6, 0.6, 0.6, true)
    else
      GameTooltip:AddLine("Have counts this character's bags, bank and auction house purchases still in the mail. Bank as of your last visit; other characters as of their last login on this account.", 0.6, 0.6, 0.6, true)
    end
    if alts == 0 then GameTooltip:AddLine("None on your other characters.", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  r.haveHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.now = T:Text(r, 11)
  r.now:SetPoint("RIGHT", r, "LEFT", C.now, 0)
  r.remove = T:Button(r, "x", 16, function()
    local list = currentList()
    if not list then return end
    for k, e in ipairs(list.items) do if e == r.entry then table.remove(list.items, k); break end end
    Q.built = 0
    refreshLists()
  end, 16)
  r.remove:SetPoint("LEFT", C.x, 0)

  -- Section heading and notes.
  r.head = T:Text(r, 12, T.accent)
  r.head:SetPoint("LEFT", 4, 0)
  r.head:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.head:SetJustifyH("LEFT")
  r.headCols = {}
  for _, c in ipairs({ { "Up to", C.max }, { "Need", C.want } }) do
    local fs = T:Text(r, 11, T.dim)
    fs:SetPoint("LEFT", c[2], 0)
    fs:SetText(c[1])
    r.headCols[#r.headCols + 1] = fs
  end
  v.rows[i] = r
  return r
end

-- Price now, green at or under the limit; for vendor items, the vendor's price.
local function nowText(id, limit, vendor)
  -- "vendor" is already in the Up to column; here just the price, grey.
  if vendor then return "|cff888888" .. ns.MoneyPlain(vendor) .. "|r" end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if rec and rec.none then return "|cff888888none|r", false end
  if rec and rec.m then
    local ok = limit and limit > 0 and rec.m <= limit
    return (ok and "|cff7fd39c" or "|cffffffff") .. money(rec.m) .. "|r", ok
  end
  return "|cff888888?|r", false
end

local function showRow(r, kind)
  r.kind = kind
  local item, mat, text = kind == "item", kind == "mat", kind == "head" or kind == "note"
  r.hit:SetShown(item or mat)
  r.mode:SetShown(item)
  r.kindText:SetShown(mat)
  r.max:SetShown(false)
  r.maxText:SetShown(false)
  r.qty:SetShown(item)
  r.need:SetShown(mat)
  r.have:SetShown(item or mat)
  r.haveHit:SetShown(item or mat)
  r.now:SetShown(item or mat)
  r.remove:SetShown(item)
  r.head:SetShown(text)
  for _, fs in ipairs(r.headCols) do fs:SetShown(kind == "head") end
end

refreshLists = function()
  local v = listsView
  if not v or not v:IsVisible() then return end
  -- While you're typing in a row's price or Want box, leave the rows alone: redrawing
  -- hides and shows boxes, which took the cursor away after a second (owner, October 2:
  -- "basically unusable").
  local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
  local row = focus and focus.GetParent and focus:GetParent()
  if row and row.GetParent and row:GetParent() == v.content then return end
  local list, idx = ns:CurrentShoppingList()
  local lists = ns:ShoppingLists()
  v.title:SetText(list and list.name or "No lists yet: click New")
  for _, b in ipairs(v.listButtons) do b:SetEnabled(list ~= nil) end
  v.on:SetChecked(list and list.on)
  v.on:SetShown(list ~= nil)
  v.any:SetChecked(list and list.anyPrice)
  v.any:SetShown(list ~= nil)
  local buyMode = ns:BuyMode(list)
  v.wantMode:SetValue(buyMode and "buy" or "keep")
  v.wantMode:SetShown(list ~= nil)
  -- Buy this many counts what's been bought, so the column says so.
  v.headers.Have:SetText(buyMode and "Bought" or "Have")

  -- What to show: the list's items, then the materials for its Craft items.
  local show = {}
  local mats, missing = {}, {}
  if list then
    for _, e in ipairs(list.items) do show[#show + 1] = { kind = "item", e = e } end
    mats, missing = ns:ListMaterials(list)
    if #mats > 0 or #missing > 0 then
      show[#show + 1] = { kind = "head", text = "Materials to craft them" }
      for _, m in ipairs(mats) do show[#show + 1] = { kind = "mat", m = m } end
      for _, id in ipairs(missing) do
        show[#show + 1] = { kind = "note", text = ("|cffee8597No recipe known for %s:|r open its profession window on the character who makes it."):format(ns.ItemName(id)) }
      end
    end
  end

  local width = v.sf:GetWidth() - 12
  v.content:SetWidth(width)
  local cheap, toBuy, y = 0, 0, 0
  local done, matsShort = 0, 0   -- items you have enough of; materials you're short of
  for i, s in ipairs(show) do
    local r = listRow(i)
    showRow(r, s.kind)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r:SetHeight(s.kind == "note" and 30 or 24)
    y = y + r:GetHeight()
    r.stripe:SetShown(i % 2 == 0 and (s.kind == "item" or s.kind == "mat"))
    if s.kind == "item" then
      local e = s.e
      r.entry = e
      r.icon:SetTexture(ns:ItemIcon(e.id))
      r.name:SetText(ns.ItemName(e.id))
      local craft = e.mode == "craft"
      r.max:SetTextColor(1, 1, 1, 1)
      r.mode:SetText(craft and "Craft" or "Buy")
      r.mode:SetSelected(craft)
      local any = list.anyPrice or e.max == -1
      r.max:SetShown(not craft and not list.anyPrice)
      r.maxText:SetShown(craft or list.anyPrice)
      r.maxText:SetText(craft and "crafted" or "any")
      if not craft and not r.max:HasFocus() then r.max:SetValue(e.max or 0) end
      if not r.qty:HasFocus() then r.qty:SetText(e.qty and tostring(e.qty) or "") end
      -- Have against Want (1 if no number): green when you have enough. Done stays
      -- done (grey Have) after you use some, until Buy again.
      -- Buy this many shows what's been bought instead.
      local have, want = ns:HaveCount(e.id), e.qty or 1
      if buyMode then have = craft and have or (e.bought or 0) end
      local isDone = ns:ItemDone(e, list)
      if isDone then done = done + 1 end
      r.have:SetText((have >= want and "|cff7fd39c" or isDone and "|cff888888" or "|cffffd100") .. have .. "|r")
      if isDone then
        r.now:SetText("|cff7fd39cdone|r")
      else
        local text, ok = nowText(e.id, not craft and (any and ns:AnyPriceLimit(e.id) or e.max) or nil)
        r.now:SetText(text)
        if ok then cheap = cheap + 1 end
      end
    elseif s.kind == "mat" then
      local m = s.m
      r.mat = m
      r.icon:SetTexture(ns:ItemIcon(m.id))
      r.name:SetText(ns.ItemName(m.id))
      r.kindText:SetText("for craft")
      r.max:SetShown(not m.vendor and not list.anyPrice)
      r.maxText:SetShown(m.vendor ~= nil or list.anyPrice)
      r.maxText:SetText(m.vendor and "vendor" or "any")
      if not m.vendor and not list.anyPrice and not r.max:HasFocus() then
        r.max:SetValue(m.own == "any" and -1 or m.limit or 0)
        r.max:SetTextColor(1, 1, 1, m.own and 1 or 0.55)   -- grey: the usual price, not one you typed
      end
      r.need:SetText(m.buy > 0 and ("|cffffd100%d|r"):format(m.need) or ("|cff7fd39c%d|r"):format(m.need))
      local got = buyMode and m.bought or m.have
      r.have:SetText(m.buy > 0 and ("|cffffd100" .. got .. "|r") or ("|cff7fd39c" .. got .. "|r"))
      if m.buy > 0 then matsShort = matsShort + 1 end
      r.now:SetText(m.done and "|cff7fd39cdone|r" or (nowText(m.id, m.limit, m.vendor)))
      if m.buy > 0 and not m.vendor then toBuy = toBuy + 1 end
    else
      r.head:SetText(s.text)
      r.head:SetFont(T.font, s.kind == "head" and 12 or 11, "")
      r.head:SetWordWrap(s.kind == "note")
    end
    r:Show()
  end
  for i = #show + 1, #v.rows do v.rows[i]:Hide() end
  v.content:SetHeight(math.max(y, 24))
  v.sf.UpdateScrollBar()
  -- The list's progress beside its name.
  if list and #list.items > 0 then
    v.title:SetText(("%s  %s%d/%d|r"):format(list.name,
      done == #list.items and "|cff7fd39c" or "|cffffd100", done, #list.items))
  end
  v.searchB:SetEnabled(list ~= nil and #show > 0 and ns:IsAHOpen() and not ns.Scan.active)
  -- How far along the list is (lists are kept, so the same one works again next raid:
  -- what you have is counted afresh every time).
  local craftsReady = 0
  if list then
    for _, e in ipairs(list.items) do
      if e.mode == "craft" and not ns:ItemDone(e, list) then craftsReady = craftsReady + 1 end
    end
  end
  if ns.Scan.active then
    v.info:SetText("Searching...")
  elseif not list then
    v.info:SetText("Click New to start a list.")
  elseif #list.items == 0 then
    v.info:SetText("Add items above, or Import a shared list.")
  elseif done == #list.items then
    v.info:SetText("|cff7fd39cComplete: you have everything on this list.|r")
  elseif craftsReady > 0 and matsShort == 0 and done + craftsReady == #list.items then
    v.info:SetText(("|cff7fd39cYou have all the materials:|r %d to craft, then it's complete."):format(craftsReady))
  elseif not ns:IsAHOpen() then
    v.info:SetText(("%d of %d items done%s. Open the auction house to search and buy."):format(done, #list.items,
      matsShort > 0 and (", %d %s short"):format(matsShort, matsShort == 1 and "material" or "materials") or ""))
    v.info:SetText("Open the auction house to search and buy.")
  else
    local noPrice = 0
    for _, e in ipairs(list.items) do
      if e.mode ~= "craft" and (e.max or 0) == 0 and not list.anyPrice then noPrice = noPrice + 1 end
    end
    if noPrice > 0 then
      v.info:SetText(("%d %s no price: set Most each (or any) to buy %s."):format(noPrice,
        noPrice == 1 and "item has" or "items have", noPrice == 1 and "it" or "them"))
    else
      v.info:SetText(("%d of %d done. %d at your price%s: in the buy queue."):format(done, #list.items, cheap,
        toBuy > 0 and (", %d %s short"):format(toBuy, toBuy == 1 and "material" or "materials") or ""))
    end
  end
end
refreshLists = ns.Timed("Shopping lists view", refreshLists)

---------------------------------------------------------------------------
-- The side panel and its tabs. Beside the auction house when it's open; anywhere else
-- (/fl lists) it's a window of its own you can move, so lists can be made before a raid.
---------------------------------------------------------------------------
local TABS = { { "queue", "Buy queue" }, { "lists", "Shopping lists" }, { "finder", "Disenchant finder" } }

local function showTab(tab)
  S().tab = tab
  for _, b in ipairs(side.tabs) do b:SetSelected(b.key == tab) end
  queueView:SetShown(tab == "queue")
  listsView:SetShown(tab == "lists")
  local finder = ns:DisenchantFinderFrame(side)
  if finder then finder:SetShown(tab == "finder") end
  updateBinding()
  if tab == "queue" then
    -- Fill every section (armed or not) from the last scan.
    Q.built = 0
    rebuildNow()
  else
    -- Leaving the queue: let go of a purchase that was waiting for its confirm tick.
    if Q.state == "price" or Q.state == "confirm" then pcall(AH.CancelCommoditiesPurchase) end
    Q.cur, Q.plan, Q.key, Q.keys = nil, nil, nil, nil
    Q.state = "idle"
  end
  if tab == "lists" then refreshLists() end
end

-- Beside the auction house, or on its own in the middle of the screen.
local function place()
  local ah = AuctionHouseFrame
  side:ClearAllPoints()
  if ah and ah:IsShown() then
    side:SetParent(ah)
    side:SetFrameStrata(ah:GetFrameStrata())
    side:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
    side:SetPoint("BOTTOMLEFT", ah, "BOTTOMRIGHT", 4, 0)
    side:SetWidth(WIDTH)
    side.floating = false
  else
    side:SetParent(UIParent)
    side:SetFrameStrata("HIGH")
    side:SetSize(WIDTH, 560)
    side:SetPoint("CENTER")
    side.floating = true
  end
  side.close:SetShown(side.floating)
end

local function ensureSide()
  if side then return side end
  side = CreateFrame("Frame", "ForeverLedgerSidePanel", UIParent)
  side:SetSize(WIDTH, 560)
  side:EnableMouse(true)
  side:SetMovable(true)
  side:SetClampedToScreen(true)
  T:Fill(side, T.bg)
  T:Border(side)
  local strip = CreateFrame("Frame", nil, side)
  strip:SetPoint("TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", -1, -1)
  strip:SetHeight(28)
  T:Fill(strip, T.header)
  -- Drag the tab row to move it when it's on its own.
  strip:EnableMouse(true)
  strip:RegisterForDrag("LeftButton")
  strip:SetScript("OnDragStart", function() if side.floating then side:StartMoving() end end)
  strip:SetScript("OnDragStop", function() side:StopMovingOrSizing() end)
  side.tabs = {}
  local x = 4
  for _, t in ipairs(TABS) do
    local b = T:Tab(strip, t[2], function() showTab(t[1]) end)
    b.key = t[1]
    b:SetPoint("LEFT", x, 0)
    x = x + b:GetWidth()
    side.tabs[#side.tabs + 1] = b
  end
  side.close = T:Button(strip, "x", 22, function() side:Hide() end, 22)
  side.close:SetPoint("RIGHT", -3, 0)
  queueView = buildQueueView(side)
  listsView = buildListsView(side)
  ns:DisenchantFinderFrame(side)
  side:SetScript("OnShow", function() showTab(S().tab or "queue") end)
  side:SetScript("OnHide", function()
    if Q.state == "price" or Q.state == "confirm" then pcall(AH.CancelCommoditiesPurchase) end
    Q.cur, Q.plan, Q.key, Q.keys, Q.state = nil, nil, nil, nil, "idle"
    updateBinding()
  end)
  -- Escape closes it when it's on its own.
  tinsert(UISpecialFrames, "ForeverLedgerSidePanel")
  side:Hide()
  return side
end

-- The auction house opened: put the panel beside it if it was open last time.
function ns:SetUpSidePanel()
  if not AuctionHouseFrame then return end
  ensureSide()
  -- Already open on its own (a list being made): keep it open, now beside the auction house.
  local keep = side.floating and side:IsShown()
  place()
  if S().shown or keep then side:Show(); showTab(S().tab or "queue") else side:Hide() end
end

function ns:ToggleSidePanel()
  ensureSide()
  place()
  S().shown = not side:IsShown()
  side:SetShown(S().shown)
end

-- New flips from a full scan: open the panel on the Buy queue if it's closed. If it's
-- open, leave it alone, whatever tab you're on.
function ns:OpenBuyQueueGently()
  if not (ns:IsAHOpen() and AuctionHouseFrame) then return end
  ensureSide()
  if side:IsShown() then return end
  place()
  S().shown = true
  side:Show()
  showTab("queue")
end

function ns:ShowSidePanel(tab)
  ensureSide()
  place()
  if not side.floating then S().shown = true end
  side:Show()
  showTab(tab or S().tab or "queue")
end

-- A new auction house visit: fresh counts, and the queue worked out again.
ns:On("AUCTION_HOUSE_SHOW", function()
  Q.bought, Q.spent, Q.worth, Q.note, Q.built = 0, 0, 0, nil, 0
  wipe(done)
end)
ns:On("AUCTION_HOUSE_CLOSED", function()
  Q.cur, Q.plan, Q.key, Q.keys, Q.state = nil, nil, nil, nil, "idle"
  -- Next visit, nothing is armed until you click (a lone flips section arms by itself).
  Q.armed = nil
  if side and not InCombatLockdown() then ClearOverrideBindings(side) end
end)

-- New finds join their sections (the current item stays where it is). Never changes
-- which section is armed: scans and the flip watch only add to the lists.
function rebuildNow()
  if not shown() then return end
  Q.lanes, Q.built = buildQueue(), GetTime()
  autoArm()
  if Q.cur then
    local list, found = laneList(), false
    for i, e in ipairs(list) do
      if e.id == Q.cur.id then list[i] = Q.cur; found = true end
    end
    if not found then
      -- It no longer belongs (you unticked its kind, or it stopped being worth it): let
      -- it go, unless a purchase of it is under way (owner, October 2: a Rough Bronze
      -- Cuirass kept being bought as DE after Disenchant was unticked).
      if Q.state == "price" or Q.state == "confirm" or Q.state == "buying" then
        table.insert(list, 1, Q.cur)
      else
        dropCurrent()
      end
    end
  end
  refreshQueue()
  if not Q.cur then prepare() end
end

-- A price just saved made a vendor flip (watch pass or your own search): into the
-- queue within a second, not at the end of the pass, which could be 2 minutes (owner,
-- October 2: flips showed on the Vendor flips tab before the queue).
local flipRebuild = false
local function soonForFlip(_, id)
  if flipRebuild or not shown() or not S().flips or not ns:VendorFlip(id) then return end
  flipRebuild = true
  C_Timer.After(1, function() flipRebuild = false; rebuildNow() end)
end

ns:OnReady(function()
  hooksecurefunc(ns, "CheckFlip", soonForFlip)
end)

-- After any scan, new finds join the queue.
ns:OnReady(function()
  -- Scroll to buy used to start on: switch it off once for everyone (owner, October 2).
  if not S().wheelOffOnce then S().wheel, S().wheelOffOnce = false, true end
  hooksecurefunc(ns, "CheckDeals", rebuildNow)
end)
