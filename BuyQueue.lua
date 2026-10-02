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
local BUY_BUTTON = "ForeverLedgerBuyNext"

local function S() return ns.db.settings.buyQueue end
local function money(c) return ns.Money(math.floor((c or 0) + 0.5)) end
-- An entry's limit as words: "any price" ones say so (and how high they'd go).
local function limitText(e)
  if not e.any then return money(e.limit) end
  if e.limit == math.huge then return "any price" end
  return "any price (at most " .. money(e.limit) .. ", 3 times usual)"
end

local REASONS = {
  list = { badge = "LIST", color = "b9a2ff" },
  flip = { badge = "FLIP", color = "7fd39c" },
  de = { badge = "DE", color = "7fb8ff" },
  deal = { badge = "DEAL", color = "ffd100" },
}

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

local function sameKey(a, b)
  return a and b and a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0)
    and (a.itemSuffix or 0) == (b.itemSuffix or 0) and (a.battlePetSpeciesID or 0) == (b.battlePetSpeciesID or 0)
end

---------------------------------------------------------------------------
-- What's in the queue
---------------------------------------------------------------------------
local done, skipped = {}, {}   -- [itemID] = GetTime() nothing left; [itemID] = true skipped this session

-- Entries: { id, limit, reason, worth = per item if known, n = cheap listings or nil
-- (never scanned), cost = average price of those, profit, want, list }.
local function buildQueue()
  local s = S()
  local market = ns.db.prices[ns.MarketKey()] or {}
  local now = GetTime()
  local out, seen = {}, {}
  local function add(e)
    if seen[e.id] or skipped[e.id] or (done[e.id] and now - done[e.id] < DONE_FOR) then return end
    seen[e.id] = true
    e.gear = isGear(e.id)
    out[#out + 1] = e
  end
  -- Shopping lists first, in list order: they're what you asked for. Ones not cheap
  -- enough right now still show, greyed at the end, so you can see they're watched
  -- (owner, October 2: "not clear how to add it to the buy queue, it's blank").
  local waiting = {}
  if s.lists then
    for _, t in ipairs(ns:ShoppingTargets()) do
      local n, avg = ns:CheapListings(t.id, t.limit)
      local e = { id = t.id, limit = t.limit, any = t.any, reason = "list", list = t.list, want = t.want, n = n, cost = avg }
      if n == 0 then e.waiting = true; waiting[#waiting + 1] = e else add(e) end
    end
  end
  local others = {}
  if s.flips then
    for id in pairs(market) do
      local f = ns:VendorFlip(id)
      if f then
        others[#others + 1] = { id = id, limit = math.floor(f.maxBuy), reason = "flip", worth = f.opt.value,
          n = f.buys[1].listed, cost = f.cost }
      end
    end
  end
  if s.disenchant then
    for id, rec in pairs(market) do
      if rec.m and not rec.none and isGear(id) then
        local limit, opt = ns:BuyAtOrBelow(id)
        if limit and opt and opt.kind == "disenchant" and rec.m <= limit then
          local n, avg = ns:CheapListings(id, limit)
          if n and n > 0 then
            others[#others + 1] = { id = id, limit = math.floor(limit), reason = "de", worth = opt.value, n = n, cost = avg }
          end
        end
      end
    end
  end
  if s.deals then
    for _, d in ipairs(ns:FindDeals(6 * 3600)) do
      if d.kind == "usual" and d.level == "good" and d.limit and ns:DealShown(d) then
        others[#others + 1] = { id = d.id, limit = math.floor(d.limit), reason = "deal", worth = d.resell,
          n = d.listed, cost = d.cost or d.price }
      end
    end
  end
  for _, e in ipairs(others) do e.profit = ((e.worth or 0) - (e.cost or e.limit)) * (e.n or 1) end
  table.sort(others, function(a, b) return a.profit > b.profit end)
  for _, e in ipairs(others) do add(e) end
  for _, e in ipairs(waiting) do add(e) end
  return out
end
buildQueue = ns.Timed("Buy queue", buildQueue)

---------------------------------------------------------------------------
-- The engine: search for the current item, plan the purchase, buy on a tick.
-- States: idle, wait, browse (gear: finding its stat versions), search, ready,
-- price (commodity: waiting for the final price), confirm, buying.
---------------------------------------------------------------------------
local Q = { list = {}, state = "idle", tok = 0, bought = 0, spent = 0, worth = 0 }
local side, queueView, listsView   -- frames, built when the auction house first opens
local refreshQueue                  -- redraws the queue view

local function active()
  return side and side:IsShown() and S().tab == "queue" and ns:IsAHOpen()
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

local search, prepare

local function finishTarget(note)
  local e = Q.cur
  if e then
    done[e.id] = GetTime()
    for i, x in ipairs(Q.list) do if x == e then table.remove(Q.list, i); break end end
    Q.note = ns.ItemName(e.id) .. ": " .. note
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
  -- Our own scans (materials, full) come first; the flip watch's quiet checks pause
  -- for 20 seconds after each of our searches by themselves.
  if throttled() or (ns.Scan.active and not ns.Scan.quiet) then
    Q.waitFor = ns.Scan.active and "the scan to finish" or "the auction house"
    setState("wait")
    timeout(1, search)
    return
  end
  Q.tries = (Q.tries or 0) + 1
  if Q.tries > 3 then finishTarget("no reply from the auction house."); return end
  -- Gear: find its stat versions first (one row each in the search list).
  if e.gear and not Q.key then
    local name = ns.GetItemInfo(e.id) or ns.ItemName(e.id)
    local filters = {}
    if Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.ExactMatch then
      filters[1] = Enum.AuctionHouseFilter.ExactMatch
    end
    setState("browse")
    local ok, err = pcall(AH.SendBrowseQuery, { searchString = name, sorts = sorts(), filters = filters, itemClassFilters = {} })
    if not ok then ns:Debug("Buy queue: browse failed", err); finishTarget("couldn't search for it."); return end
    timeout(5, search)
    return
  end
  setState("search")
  local ok, err = pcall(AH.SendSearchQuery, Q.key or AH.MakeItemKey(e.id), sorts(), true)
  if not ok then ns:Debug("Buy queue: search failed", err); finishTarget("couldn't search for it."); return end
  timeout(5, search)
end

-- Start on the first item in the queue, if nothing's under way.
function prepare()
  if not active() or Q.cur then return end
  if #Q.list == 0 or GetTime() - (Q.built or 0) > REBUILD_EVERY then
    Q.list, Q.built = buildQueue(), GetTime()
  end
  -- The first one that's cheap enough; waiting list items are only looked up when clicked.
  local e
  for _, x in ipairs(Q.list) do
    if not x.waiting then e = x; break end
  end
  if not e then setState("idle"); return end
  Q.cur, Q.plan, Q.key, Q.keys, Q.tries = e, nil, nil, nil, 0
  search()
end

-- Work on this entry now (clicking a row).
local function choose(e)
  if Q.state == "price" or Q.state == "confirm" then pcall(AH.CancelCommoditiesPurchase) end
  Q.cur, Q.plan, Q.key, Q.keys, Q.tries = e, nil, nil, nil, 0
  search()
end

local function planCommodity()
  local e = Q.cur
  local n = AH.GetNumCommoditySearchResults(e.id) or 0
  local full = not AH.HasFullCommoditySearchResults or AH.HasFullCommoditySearchResults(e.id)
  local cash, qty, cost = GetMoney(), 0, 0
  for i = 1, n do
    local r = AH.GetCommoditySearchResultInfo(e.id, i)
    if not (r and r.unitPrice) or r.unitPrice > e.limit then break end
    local k = (r.quantity or 0) - (r.numOwnerItems or 0)
    if e.want then k = math.min(k, e.want - qty) end
    k = math.min(k, math.floor((cash - cost) / r.unitPrice))
    if k > 0 then qty, cost = qty + k, cost + k * r.unitPrice end
    if (e.want and qty >= e.want) or cash - cost < r.unitPrice then break end
  end
  if qty == 0 then
    if n == 0 and not full then return end   -- more results on the way
    finishTarget(("none left at %s or less."):format(limitText(e)))
    return
  end
  Q.plan = { kind = "commodity", qty = qty, cost = cost }
  setState("ready")
end

local function planItem(key)
  local e = Q.cur
  local n = AH.GetNumItemSearchResults(key) or 0
  local cash, best, count, stacks = GetMoney(), nil, 0, 0
  for i = 1, n do
    local r = AH.GetItemSearchResultInfo(key, i)
    if r and r.auctionID and r.buyoutAmount and r.buyoutAmount > 0 and r.buyoutAmount <= e.limit and not r.containsOwnerItem then
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

-- After a purchase: look again, there may be more.
local function again()
  Q.plan, Q.tries = nil, 0
  if Q.cur and Q.cur.want and Q.cur.want <= 0 then finishTarget("you have all you wanted."); return end
  search()
end

-- One tick of the mouse wheel or a click on Buy: the next step of the purchase.
-- A click can arrive as both "down" and "up", so two within 0.15 s count once.
local lastAct = 0
function ns:BuyQueueAct()
  if not active() or GetTime() - lastAct < 0.15 then return end
  lastAct = GetTime()
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
    local ok, err = pcall(AH.PlaceBid, p.auctionID, p.price)
    if not ok then ns:Print("Couldn't buy that: " .. tostring(err)); again(); return end
    setState("buying")
    timeout(6, again)
  elseif Q.state == "idle" and not Q.cur then
    -- Nothing under way: look again (at most every 3 seconds, as a spun wheel sends many ticks).
    if GetTime() - (Q.built or 0) > 3 then Q.built = 0 end
    prepare()
  end
end

-- Search results and purchase replies.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  local e = Q.cur
  if Q.state ~= "browse" or not e then return end
  local keys = {}
  for _, r in ipairs(AH.GetBrowseResults() or {}) do
    if r.itemKey and r.itemKey.itemID == e.id and r.minPrice and r.minPrice > 0 and r.minPrice <= e.limit then
      keys[#keys + 1] = r.itemKey
    end
  end
  if #keys == 0 then
    if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() then return end
    finishTarget(("none left at %s or less."):format(limitText(e)))
    return
  end
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
  if Q.key and not sameKey(itemKey, Q.key) then return end
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
  again()
end)

ns:On("COMMODITY_PURCHASE_FAILED", function()
  if Q.state ~= "buying" then return end
  Q.note = "That purchase failed: the listings changed. Checking again."
  again()
end)

local function itemBought()
  if Q.state ~= "buying" or not (Q.plan and Q.plan.kind == "item") then return end
  bought(1, Q.plan.price)
  again()
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
-- Scroll anywhere to buy: while the queue is open, the mouse wheel down clicks Buy.
---------------------------------------------------------------------------
local function updateBinding()
  if not side or InCombatLockdown() or not SetOverrideBindingClick then return end
  ClearOverrideBindings(side)
  if active() and S().wheel then
    SetOverrideBindingClick(side, true, "MOUSEWHEELDOWN", BUY_BUTTON, "LeftButton")
  end
end
ns:On("PLAYER_REGEN_ENABLED", updateBinding)

---------------------------------------------------------------------------
-- Queue view
---------------------------------------------------------------------------
local ROW_H = 20

local function reasonLine(e)
  if not e then return "" end
  if e.reason == "flip" then return ("Vendor flip: a vendor pays %s."):format(money(e.worth)) end
  if e.reason == "de" then return ("Disenchant: worth about %s."):format(money(e.worth)) end
  if e.reason == "deal" then return ("Below its usual price: resells for about %s."):format(money(e.worth)) end
  if e.reason == "list" then
    return ("Shopping list %s: up to %s%s."):format(e.list or "", limitText(e),
      e.want and (", %d more wanted"):format(e.want) or "")
  end
  return ""
end

local function statusText()
  local e, p = Q.cur, Q.plan
  local name = e and ("|cffffffff" .. ns.ItemName(e.id) .. "|r") or ""
  local st = Q.state
  if not ns:IsAHOpen() then
    return "Open the auction house to use the buy queue.", "Shopping lists can be made anywhere: /fl lists.", "Buy"
  end
  if st == "wait" then return ("Waiting for %s..."):format(Q.waitFor or "the auction house"), "", "..." end
  if st == "browse" or st == "search" then return "Looking for " .. name .. "...", reasonLine(e), "..." end
  if st == "ready" and p and p.kind == "commodity" then
    return ("Buy %d %s for %s"):format(p.qty, name, money(p.cost)),
      ("%s each, up to %s. "):format(money(p.cost / p.qty), limitText(e)) .. reasonLine(e), "Buy"
  end
  if st == "price" then return "Getting the final price for " .. name .. "...", "", "..." end
  if st == "confirm" and p then
    return ("|cffffd100Confirm:|r %d %s for %s"):format(p.qty, name, money(p.total)),
      ("%s each. Scroll or click again to buy them."):format(money(p.total / p.qty)), "Confirm"
  end
  if st == "ready" and p and p.kind == "item" then
    return ("Buy %s for %s"):format(name, money(p.price)),
      ("%d at or under %s. "):format(p.count, limitText(e)) .. reasonLine(e), "Buy"
  end
  if st == "buying" then return "Buying " .. name .. "...", "", "..." end
  local ready, waiting = 0, 0
  for _, x in ipairs(Q.list) do if x.waiting then waiting = waiting + 1 else ready = ready + 1 end end
  if ready == 0 then
    return "Nothing worth buying right now.", waiting > 0
      and ("%d shopping list %s waiting for a lower price (greyed below). Search the list to check again."):format(waiting, waiting == 1 and "item is" or "items are")
      or "Run a scan or Watch flips: new finds join the queue.", "Check"
  end
  return "Ready.", "", "Start"
end

local function buildQueueView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetPoint("TOPLEFT", 0, -30)
  v:SetPoint("BOTTOMRIGHT")

  -- What's next, and the Buy button.
  local box = CreateFrame("Frame", nil, v)
  box:SetPoint("TOPLEFT", 8, -6)
  box:SetPoint("TOPRIGHT", -8, -6)
  box:SetHeight(74)
  T:Fill(box, { 1, 1, 1, 0.04 })
  T:Border(box)
  v.icon = box:CreateTexture(nil, "ARTWORK")
  v.icon:SetSize(32, 32)
  v.icon:SetPoint("TOPLEFT", 8, -8)
  v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  v.line1 = T:Text(box, 13)
  v.line1:SetPoint("TOPLEFT", 48, -8)
  v.line1:SetPoint("RIGHT", box, "RIGHT", -100, 0)
  v.line1:SetJustifyH("LEFT")
  v.line1:SetWordWrap(false)
  v.line2 = T:Text(box, 11, T.dim)
  v.line2:SetPoint("TOPLEFT", v.line1, "BOTTOMLEFT", 0, -4)
  v.line2:SetPoint("RIGHT", box, "RIGHT", -100, 0)
  v.line2:SetJustifyH("LEFT")
  v.line3 = T:Text(box, 11, T.section)
  v.line3:SetPoint("BOTTOMLEFT", 8, 6)
  v.line3:SetPoint("RIGHT", box, "RIGHT", -100, 0)
  v.line3:SetJustifyH("LEFT")
  v.line3:SetWordWrap(false)

  local buy = T:Button(box, "Buy", 84, function() ns:BuyQueueAct() end, 56, BUY_BUTTON)
  buy:SetPoint("RIGHT", -8, 0)
  buy:GetFontString():SetFont(T.font, 15, "")
  -- Key bindings (the mouse wheel) may click on the way down; mouse clicks on the way up.
  buy:RegisterForClicks("AnyUp", "AnyDown")
  buy:EnableMouseWheel(true)
  buy:SetScript("OnMouseWheel", function(_, delta) if delta < 0 then ns:BuyQueueAct() end end)
  v.buy = buy

  -- What goes in the queue.
  local y = -88
  local opts = { { "flips", "Vendor flips" }, { "disenchant", "Disenchant" }, { "deals", "Good deals" }, { "lists", "Shopping lists" } }
  local x = 10
  for _, o in ipairs(opts) do
    local cb = T:Check(v, function(self) S()[o[1]] = self:GetChecked(); Q.built = 0; Q.list = buildQueue(); Q.built = GetTime(); refreshQueue() end)
    cb:SetPoint("TOPLEFT", x, y)
    cb.label:SetText(o[2])
    cb:SetChecked(S()[o[1]])
    x = x + 20 + cb.label:GetStringWidth() + 16
  end
  local wheel = T:Check(v, function(self) S().wheel = self:GetChecked(); updateBinding(); refreshQueue() end)
  wheel:SetPoint("TOPLEFT", 10, y - 20)
  wheel.label:SetText("Scroll anywhere to buy (mouse wheel down)")
  wheel:SetChecked(S().wheel)
  wheel:SetHitRectInsets(0, -(wheel.label:GetStringWidth() + 8), 0, 0)
  wheel:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Scroll anywhere to buy", 1, 1, 1)
    GameTooltip:AddLine("While this tab is open at the auction house, each tick of the mouse wheel down buys the next item (stacks of materials take a second tick to confirm). Off: only a click on Buy, or scrolling over it, buys.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  wheel:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- The queue.
  y = y - 46
  local header = CreateFrame("Frame", nil, v)
  header:SetPoint("TOPLEFT", 6, y)
  header:SetPoint("TOPRIGHT", -6, y)
  header:SetHeight(20)
  T:Fill(header, { 1, 1, 1, 0.05 })
  for _, c in ipairs({ { "Item", 8, "LEFT" }, { "Why", 214, "LEFT" }, { "Up to", 300, "RIGHT" }, { "Cheap", 340, "RIGHT" }, { "Profit", 400, "RIGHT" } }) do
    local fs = T:Text(header, 11, T.dim)
    if c[3] == "LEFT" then fs:SetPoint("LEFT", c[2], 0) else fs:SetPoint("RIGHT", header, "LEFT", c[2], 0) end
    fs:SetText(c[1])
  end
  v.sf, v.content = T:Scroll(v)
  v.sf:SetPoint("TOPLEFT", 6, y - 22)
  v.sf:SetPoint("BOTTOMRIGHT", -6, 36)
  v.rows = {}

  local refresh = T:Button(v, "Refresh", 80, function() Q.list, Q.built = buildQueue(), GetTime(); refreshQueue(); prepare() end, 22)
  refresh:SetPoint("BOTTOMLEFT", 10, 8)
  v.totals = T:Text(v, 11, T.dim)
  v.totals:SetPoint("LEFT", refresh, "RIGHT", 10, 0)
  v.totals:SetPoint("RIGHT", v, "RIGHT", -10, 0)
  v.totals:SetJustifyH("LEFT")
  return v
end

local function queueRow(i)
  local v = queueView
  local r = v.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, v.content)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.current = T:Fill(r, { T.accent[1], T.accent[2], T.accent[3], 0.18 }, "BORDER")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.12)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = T:Text(r, 11)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.name:SetWidth(184)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.why, r.limit, r.n, r.profit = T:Text(r, 11), T:Text(r, 11), T:Text(r, 11), T:Text(r, 11)
  r.why:SetPoint("LEFT", 208, 0)
  r.limit:SetPoint("RIGHT", r, "LEFT", 294, 0)
  r.n:SetPoint("RIGHT", r, "LEFT", 334, 0)
  r.profit:SetPoint("RIGHT", r, "LEFT", 394, 0)
  r:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      skipped[self.entry.id] = true
      if Q.cur == self.entry then finishTarget("skipped.") end
      for k, x in ipairs(Q.list) do if x == self.entry then table.remove(Q.list, k); break end end
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
      GameTooltip:AddLine("Waiting: none listed at or under your price at the last search. Raise Most each on the list, or Search this list again later.", 1, 0.82, 0, true)
    end
    GameTooltip:AddLine("Click to buy this one next. Right-click to skip it until you reload.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  v.rows[i] = r
  return r
end

refreshQueue = function()
  local v = queueView
  if not v or not v:IsVisible() then return end
  local a, b, label = statusText()
  v.line1:SetText(a)
  v.line2:SetText(b)
  v.line3:SetText(Q.note or (S().wheel and "Scroll down anywhere, or click Buy." or "Click Buy, or scroll down over it."))
  v.icon:SetTexture(Q.cur and ns:ItemIcon(Q.cur.id) or "Interface\\Icons\\INV_Misc_Coin_01")
  v.buy:SetText(label)
  v.buy:SetSelected(Q.state == "confirm")

  local width = v.sf:GetWidth() - 12
  v.content:SetWidth(width)
  for i, e in ipairs(Q.list) do
    local r = queueRow(i)
    r.entry = e
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    r.current:SetShown(e == Q.cur)
    r.icon:SetTexture(ns:ItemIcon(e.id))
    r.icon:SetDesaturated(e.waiting and true or false)
    r.name:SetText(e.waiting and ("|cff888888" .. ns.ItemName(e.id) .. "|r") or ns.ItemName(e.id))
    local rs = REASONS[e.reason]
    r.why:SetText(e.waiting and "|cff888888WAIT|r" or ("|cff%s%s|r"):format(rs.color, rs.badge))
    r.limit:SetText(e.any and "any" or money(e.limit))
    r.n:SetText(e.waiting and "0" or (e.n and tostring(e.n) or "?"))
    if e.waiting then
      local rec = (ns.db.prices[ns.MarketKey()] or {})[e.id]
      r.profit:SetText(rec and rec.m and not rec.none and ("|cff888888now " .. ns.MoneyPlain(rec.m) .. "|r") or "|cff888888none|r")
    else
      r.profit:SetText(e.profit and e.profit > 0 and ("|cff7fd39c" .. money(e.profit) .. "|r") or "")
    end
    r:Show()
  end
  for i = #Q.list + 1, #v.rows do v.rows[i]:Hide() end
  v.content:SetHeight(math.max(#Q.list * ROW_H, ROW_H))
  v.sf.UpdateScrollBar()
  v.totals:SetText(Q.bought > 0 and ("Bought %d for %s%s."):format(Q.bought, money(Q.spent),
    Q.worth > 0 and (", worth about %s"):format(money(Q.worth)) or "")
    or ("%d in the queue."):format(#Q.list))
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

  -- Which list: < name >, and New / Rename / Delete.
  local prev = T:Button(v, "<", 22, function() local _, i = ns:CurrentShoppingList(); ns:SelectShoppingList(i - 1); refreshLists() end, 22)
  prev:SetPoint("TOPLEFT", 10, -8)
  v.title = T:Text(v, 13, T.accent)
  v.title:SetPoint("LEFT", prev, "RIGHT", 8, 0)
  v.title:SetWidth(150)
  v.title:SetJustifyH("LEFT")
  v.title:SetWordWrap(false)
  local nextB = T:Button(v, ">", 22, function() local _, i = ns:CurrentShoppingList(); ns:SelectShoppingList(i + 1); refreshLists() end, 22)
  nextB:SetPoint("LEFT", prev, "RIGHT", 166, 0)
  local new = T:Button(v, "New", 50, function()
    StaticPopup_Show("FOREVER_LEDGER_LIST_NAME", "Name for the new shopping list:", nil,
      { fn = function(name) ns:NewShoppingList(name); refreshLists() end })
  end, 22)
  new:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
  local rename = T:Button(v, "Rename", 62, function()
    local list = currentList()
    if not list then return end
    StaticPopup_Show("FOREVER_LEDGER_LIST_NAME", "New name for this list:", nil,
      { default = list.name, fn = function(name) list.name = name; refreshLists() end })
  end, 22)
  rename:SetPoint("LEFT", new, "RIGHT", 4, 0)
  local delete = T:Button(v, "Delete", 56, function()
    local list, i = ns:CurrentShoppingList()
    if not list then return end
    StaticPopup_Show("FOREVER_LEDGER_LIST_DELETE", ("Delete the shopping list \"%s\"?"):format(list.name), nil,
      { fn = function() ns:DeleteShoppingList(i); Q.built = 0; refreshLists() end })
  end, 22)
  delete:SetPoint("LEFT", rename, "RIGHT", 4, 0)
  v.listButtons = { prev, nextB, rename, delete }

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

  -- Add an item: shift-click, drag, or type its name; the most you'd pay; how many.
  v.add = hinted(v, 196, "Shift-click, drag or type an item", "LEFT")
  v.add:SetPoint("TOPLEFT", 10, -62)
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
  header:SetPoint("TOPLEFT", 6, -92)
  header:SetPoint("TOPRIGHT", -6, -92)
  header:SetHeight(20)
  T:Fill(header, { 1, 1, 1, 0.05 })
  for _, c in ipairs({ { "Item", 8, "LEFT" }, { "Get", C.get, "LEFT" }, { "Most each", C.max, "LEFT" }, { "Want", C.want, "LEFT" },
                       { "Have", C.have, "RIGHT" }, { "Now", C.now, "RIGHT" } }) do
    local fs = T:Text(header, 11, T.dim)
    if c[3] == "LEFT" then fs:SetPoint("LEFT", c[2], 0) else fs:SetPoint("RIGHT", header, "LEFT", c[2], 0) end
    fs:SetText(c[1])
  end
  v.sf, v.content = T:Scroll(v)
  v.sf:SetPoint("TOPLEFT", 6, -114)
  v.sf:SetPoint("BOTTOMRIGHT", -6, 36)
  v.rows = {}

  local searchB = T:Button(v, "Search this list", 120, function()
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
  v.info = T:Text(v, 11, T.dim)
  v.info:SetPoint("LEFT", searchB, "RIGHT", 10, 0)
  v.info:SetPoint("RIGHT", v, "RIGHT", -10, 0)
  v.info:SetJustifyH("LEFT")

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
    Q.built = 0
  end, "g", true)
  r.max:SetWidth(64)
  r.max:SetPoint("LEFT", C.max, 0)
  r.maxText = T:Text(r, 11, T.section)
  r.maxText:SetPoint("LEFT", C.max + 6, 0)

  r.qty = T:EditBox(r, 30)
  r.qty:SetPoint("LEFT", C.want, 0)
  r.qty:SetScript("OnEditFocusLost", function(self)
    local n = tonumber(self:GetText())
    r.entry.qty = n and n > 0 and math.floor(n) or nil
    self:SetText(r.entry.qty and tostring(r.entry.qty) or "")
    Q.built = 0
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
    for name, n in pairs(byAlt) do GameTooltip:AddDoubleLine(name, tostring(n), 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:AddLine("Have counts this character's bags and bank. Bank as of your last visit; other characters as of their last login on this account.", 0.6, 0.6, 0.6, true)
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
  v.title:SetText(list and ("%s |cff888888(%d of %d)|r"):format(list.name, idx, #lists) or "No lists yet: click New")
  for _, b in ipairs(v.listButtons) do b:SetEnabled(list ~= nil) end
  v.on:SetChecked(list and list.on)
  v.on:SetShown(list ~= nil)
  v.any:SetChecked(list and list.anyPrice)
  v.any:SetShown(list ~= nil)

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
      r.have:SetText(tostring(ns:HaveCount(e.id)))
      local text, ok = nowText(e.id, not craft and (any and ns:AnyPriceLimit(e.id) or e.max) or nil)
      r.now:SetText(text)
      if ok then cheap = cheap + 1 end
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
      r.have:SetText(tostring(m.have))
      r.now:SetText((nowText(m.id, m.limit, m.vendor)))
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
  v.searchB:SetEnabled(list ~= nil and #show > 0 and ns:IsAHOpen() and not ns.Scan.active)
  if ns.Scan.active then
    v.info:SetText("Searching...")
  elseif not list then
    v.info:SetText("Click New to start a list.")
  elseif #list.items == 0 then
    v.info:SetText("Add items above: \"max each\" is the most you'd pay, \"want\" how many you want to have.")
  elseif not ns:IsAHOpen() then
    v.info:SetText("Open the auction house to search and buy.")
  else
    local noPrice = 0
    for _, e in ipairs(list.items) do
      if e.mode ~= "craft" and (e.max or 0) == 0 and not list.anyPrice then noPrice = noPrice + 1 end
    end
    if noPrice > 0 then
      v.info:SetText(("%d %s no price: set Most each so the buy queue buys %s."):format(noPrice,
        noPrice == 1 and "item has" or "items have", noPrice == 1 and "it" or "them"))
    else
      v.info:SetText(("%d at or under your price%s. They join the buy queue; the rest wait there, greyed."):format(cheap,
        toBuy > 0 and (", %d materials to buy"):format(toBuy) or ""))
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
    if refreshQueue then refreshQueue() end
    prepare()
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
  if side and not InCombatLockdown() then ClearOverrideBindings(side) end
end)

-- After any scan, new finds join the queue (the current item stays where it is).
ns:OnReady(function()
  hooksecurefunc(ns, "CheckDeals", function()
    if not active() then return end
    Q.list, Q.built = buildQueue(), GetTime()
    if Q.cur then
      local found = false
      for i, e in ipairs(Q.list) do
        if e.id == Q.cur.id then Q.list[i] = Q.cur; found = true end
      end
      if not found then table.insert(Q.list, 1, Q.cur) end
    end
    refreshQueue()
    if not Q.cur then prepare() end
  end)
end)
