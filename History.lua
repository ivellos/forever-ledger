local _, ns = ...

---------------------------------------------------------------------------
-- History for the dashboard and deal alerts: gold over time, money in and out
-- by source, auction house sales and purchases, and daily prices.
---------------------------------------------------------------------------
-- How long money history is kept (owner, October 3): sales data goes stale, so the
-- details are kept a while and then summed up by month.
local HOURLY_DAYS = 14      -- keep hourly gold this long, then one value per day
local DAILY_MONEY_DAYS = 365 -- gold and money in/out per day this long, then per month (kept)
local LOG_SIZE = 10000      -- auction house sales and purchases, and vendor buys and sells, kept
local LOG_DAYS = 30         -- one by one this long, then as monthly totals per item
local LEDGER_MONTHS_KEPT = 365 * 86400   -- monthly totals kept this long
local PENDING_SECONDS = 5   -- how long a hint (repair, posting fee, mail) waits for the gold change

-- Days follow the player's own clock (a UTC day would start in the US evening).
local function localDay(t)
  t = t or time()
  local utc = date("!*t", t)
  utc.isdst = date("*t", t).isdst
  local offset = t - time(utc)   -- seconds ahead of UTC, summer time included
  return math.floor((t + offset) / 86400)
end
ns.LocalDay = localDay
local function today() return localDay() end
local function thisHour() return math.floor(time() / 3600) end

local function charTable(root)
  local key = ns.CharKey()
  root[key] = root[key] or {}
  return root[key]
end

---------------------------------------------------------------------------
-- Gold over time: gold[charKey][hour] = copper
---------------------------------------------------------------------------
-- Around login and logout the game can briefly report 0 gold; those readings are
-- skipped (they made the Dashboard graph dip to 0c).
local function snapshotGold()
  if not ns.db or not GetMoney then return end
  local g = GetMoney()
  if not g or g <= 0 then return end
  charTable(ns.db.gold)[thisHour()] = g
end

-- Older than HOURLY_DAYS: keep only the last value of each day; older than
-- DAILY_MONEY_DAYS, only the last value of each month.
local function pruneGold()
  local cutoff = thisHour() - HOURLY_DAYS * 24
  local monthCutoff = thisHour() - DAILY_MONEY_DAYS * 24
  for _, hours in pairs(ns.db.gold) do
    local last = {}
    local function period(h)
      if h < monthCutoff then return date("%Y%m", h * 3600) end
      return math.floor(h / 24)
    end
    for h in pairs(hours) do
      if h < cutoff then
        local p = period(h)
        if not last[p] or h > last[p] then last[p] = h end
      end
    end
    for h in pairs(hours) do
      if h < cutoff and last[period(h)] ~= h then hours[h] = nil end
    end
  end
end

-- The local day number of the 1st of the month a day falls in.
local function monthStartDay(day)
  local t = date("*t", day * 86400 + 43200)   -- midday, so time zones can't shift the date
  return localDay(time({ year = t.year, month = t.month, day = 1, hour = 12 }))
end

-- Money in and out older than DAILY_MONEY_DAYS: one entry per month (on its 1st day),
-- so the Dashboard and Ledger still add up over any range.
local function foldMoney()
  local cutoff = today() - DAILY_MONEY_DAYS
  for _, days in pairs(ns.db.money) do
    local moves = {}
    for day in pairs(days) do
      if day < cutoff then
        local first = monthStartDay(day)
        if first ~= day then moves[#moves + 1] = { day, first } end
      end
    end
    for _, m in ipairs(moves) do
      local into = days[m[2]] or {}
      days[m[2]] = into
      for s, amt in pairs(days[m[1]]) do into[s] = (into[s] or 0) + amt end
      days[m[1]] = nil
    end
  end
end

-- Ledger entries older than LOG_DAYS become one line per item, character and month:
-- ledgerMonths = { { t = month start, c, k = "sale" | "buy" | "vsell" | "vbuy", id or n,
-- q = quantity, a = copper, cnt = trades, mx = biggest single trade } }, kept a year.
local function foldLedger()
  local months = ns.db.ledgerMonths
  local index = {}
  local function key(e) return table.concat({ e.t, e.c or "?", e.k, e.id or e.n or "?" }, "|") end
  for _, m in ipairs(months) do index[key(m)] = m end
  local cutoff = time() - LOG_DAYS * 86400
  local function fold(list, kindOf)
    local drop = 0
    while list[drop + 1] and (list[drop + 1].t or 0) < cutoff do
      drop = drop + 1
      local e = list[drop]
      local d = date("*t", e.t or 0)
      local m = { t = time({ year = d.year, month = d.month, day = 1, hour = 12 }), c = e.c, k = kindOf(e),
        id = e.id, n = (not e.id) and e.n or nil }
      local k = key(m)
      local x = index[k]
      if not x then
        x = m
        x.q, x.a, x.cnt, x.mx = 0, 0, 0, 0
        months[#months + 1] = x
        index[k] = x
      end
      local amount = e.a or 0
      x.q, x.a, x.cnt = x.q + (e.q or 1), x.a + amount, x.cnt + 1
      if amount > x.mx then x.mx = amount end
    end
    if drop > 0 then
      for i = 1, #list - drop do list[i] = list[i + drop] end
      for i = #list, #list - drop + 1, -1 do list[i] = nil end
    end
  end
  fold(ns.db.sales, function() return "sale" end)
  fold(ns.db.purchases, function() return "buy" end)
  fold(ns.db.vendorLog, function(e) return e.s == "sell" and "vsell" or "vbuy" end)
  -- Monthly totals older than a year go.
  local keep = time() - LEDGER_MONTHS_KEPT
  local kept = {}
  for _, m in ipairs(months) do if m.t >= keep then kept[#kept + 1] = m end end
  ns.db.ledgerMonths = kept
end

---------------------------------------------------------------------------
-- Money in and out: money[charKey][day][source] = copper (always positive)
---------------------------------------------------------------------------
local open = {}          -- per window: true while open, GetTime() when it closed
local pendingAll = {}    -- hints for the next gold change: { source, t, amount, item, qty, log }
local lastMoney
local lastShownItem      -- the item the auction house last showed listings for
function ns.LastShownItem() return lastShownItem end

local function hint(h)
  h.t = GetTime()
  pendingAll[#pendingAll + 1] = h
end

-- Take the hints that explain a gold change: one with the same amount; otherwise several
-- whose amounts add up to it (quick vendor sales can arrive as one change); otherwise
-- the oldest. Returns a list, possibly empty.
local GAINS = { vendorSell = true, ahSale = true, mailIn = true }

local function takeHints(delta)
  local now, want = GetTime(), math.abs(delta)
  -- Drop old hints, and never let a sale explain money going out (or the reverse).
  local pending = {}
  for i = #pendingAll, 1, -1 do
    if now - pendingAll[i].t > PENDING_SECONDS then table.remove(pendingAll, i) end
  end
  for _, h in ipairs(pendingAll) do
    if (GAINS[h.source] or false) == (delta > 0) then pending[#pending + 1] = h end
  end
  local function take(h)
    for i, p in ipairs(pendingAll) do if p == h then table.remove(pendingAll, i); break end end
    return h
  end
  for _, h in ipairs(pending) do
    if h.amount == want then return { take(h) } end
  end
  local sum, picks = 0, {}
  for _, h in ipairs(pending) do
    if h.amount and sum + h.amount <= want then sum = sum + h.amount; picks[#picks + 1] = h end
  end
  if sum == want and #picks > 1 then
    for _, h in ipairs(picks) do take(h) end
    return picks
  end
  if #pending > 0 then return { take(pending[1]) } end
  return {}
end

-- A window counts as open until LINGER seconds after it closes, because money can
-- arrive a moment later (auto-loot closes the loot window before the coins land).
local LINGER = 1.5
-- Close events don't always arrive (loot was once counted as mail because the mailbox
-- never reported closing), so also check the window is really on screen. Loot is left
-- out: with auto-loot its window often never shows.
local FRAMES = {
  merchant = "MerchantFrame", ah = "AuctionHouseFrame", mail = "MailFrame", trade = "TradeFrame",
  quest = "QuestFrame", trainer = "ClassTrainerFrame", taxi = "TaxiFrame",
}
local function isOpen(name)
  local v = open[name]
  if v == true then
    local frame = FRAMES[name] and _G[FRAMES[name]]
    if frame and frame.IsShown and not frame:IsShown() then
      open[name] = nil
      return false
    end
    return true
  end
  return v and GetTime() - v < LINGER
end

local function sourceFor(delta)
  local gain = delta > 0
  if isOpen("merchant") then return gain and "vendorSell" or "vendorBuy" end
  if isOpen("ah") then return gain and "otherIn" or "ahBuy" end
  if isOpen("mail") then return gain and "mailIn" or "mailOut" end
  if isOpen("trade") then return gain and "tradeIn" or "tradeOut" end
  if isOpen("loot") and gain then return "loot" end
  if isOpen("quest") and gain then return "quest" end
  if isOpen("trainer") and not gain then return "training" end
  if isOpen("taxi") and not gain then return "flight" end
  return gain and "otherIn" or "otherOut"
end

local function addLog(list, entry)
  -- Vendor trades of the same item within a minute are one entry: selling 20 of
  -- something one by one made 20 (owner's log, October 3).
  local last = list[#list]
  if list == ns.db.vendorLog and last and last.id == entry.id and last.s == entry.s and last.c == entry.c
    and entry.t - (last.t or 0) <= 60 and last.q and entry.q and last.q > 0 and entry.q > 0
    and math.abs(last.a / last.q - entry.a / entry.q) < 1 then
    last.q, last.a, last.t = last.q + entry.q, last.a + entry.a, entry.t
    return
  end
  list[#list + 1] = entry
  while #list > LOG_SIZE do table.remove(list, 1) end
end

local function onMoney()
  local now = GetMoney()
  if not lastMoney then lastMoney = now; return end
  local delta = now - lastMoney
  lastMoney = now
  snapshotGold()
  if delta == 0 then return end

  local hints = takeHints(delta)
  local source = hints[1] and hints[1].source or sourceFor(delta)
  local day = charTable(ns.db.money)
  day[today()] = day[today()] or {}
  local totals = day[today()]
  totals[source] = (totals[source] or 0) + math.abs(delta)
  -- A running session counts it too (Sessions.lua).
  if ns.SessionMoney then ns:SessionMoney(source, delta) end
  if ns.DungeonMoney then ns:DungeonMoney(source, delta) end   -- and a dungeon run (Dungeons.lua)

  local now, who = time(), ns.CharKey()
  for _, h in ipairs(hints) do
    local amount = (#hints > 1 and h.amount) or math.abs(delta)
    if h.log == "sale" then
      addLog(ns.db.sales, { t = now, c = who, n = h.item, a = amount, cut = h.cut, q = h.qty, b = h.buyer })
      ns:Debug("Sale", h.qty or "?", "x", h.item or "?", "to", h.buyer or "?", "for", ns.Money(amount))
    elseif h.log == "vendor" then
      addLog(ns.db.vendorLog, { t = now, c = who, id = h.item, q = h.qty, a = amount, s = h.source == "vendorSell" and "sell" or "buy" })
      ns:Debug("Vendor", h.source == "vendorSell" and "sold" or "bought", h.qty or "?", "x", h.item or "?", "for", ns.Money(amount))
    end
  end
  if source == "ahBuy" then
    -- Commodity purchases name their item; for other purchases, use the item the
    -- auction house last showed listings for.
    local h = hints[1]
    -- Non-commodity purchases (gear) are always one item.
    local id = (h and h.item) or lastShownItem
    addLog(ns.db.purchases, { t = now, c = who, id = id, q = (h and h.qty) or 1, a = math.abs(delta) })
    -- It comes by mail: shopping lists count it as had until it's taken (ShoppingLists.lua).
    if ns.NoteBoughtToMail then ns:NoteBoughtToMail(id, (h and h.qty) or 1) end
    -- Gear: the addon doesn't save prices from gear pages (one page shows one stat
    -- version), so take the bought one off the saved listings instead. Otherwise a
    -- gear flip stays on Vendor flips until the next full scan (owner's test, October 1:
    -- Hefty Battlehammer). Commodities are saved from the page, so they're left alone.
    if (not h or h.single) and id and ns.RemoveBought then
      local ok, err = pcall(ns.RemoveBought, ns, id, 1, math.abs(delta))
      if not ok then ns:Debug("Couldn't take the purchase off the listings:", err) end
    end
  end
  if ns.OnMoneyLogged then ns:OnMoneyLogged() end
  ns:Debug("Money", source, delta > 0 and "+" or "-", ns.Money(math.abs(delta)))
end

-- Windows that decide where money came from.
local function track(showEvent, hideEvent, name)
  ns:On(showEvent, function() open[name] = true end)
  ns:On(hideEvent, function() open[name] = GetTime() end)
end
track("MERCHANT_SHOW", "MERCHANT_CLOSED", "merchant")
track("AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ah")
track("MAIL_SHOW", "MAIL_CLOSED", "mail")
track("TRADE_SHOW", "TRADE_CLOSED", "trade")
track("LOOT_OPENED", "LOOT_CLOSED", "loot")
track("QUEST_COMPLETE", "QUEST_FINISHED", "quest")
track("TRAINER_SHOW", "TRAINER_CLOSED", "trainer")
track("TAXIMAP_OPENED", "TAXIMAP_CLOSED", "taxi")

ns:On("PLAYER_MONEY", onMoney)
ns:On("PLAYER_ENTERING_WORLD", function()
  -- A 0 here may be the game not having loaded gold yet; the next change sets it.
  local g = GetMoney()
  lastMoney = g and g > 0 and g or nil
  snapshotGold()
end)
ns:On("PLAYER_LOGOUT", snapshotGold)

-- Hints from actions that cost or pay money a moment later.
local function hook(target, name, fn)
  if target and type(target[name]) == "function" then hooksecurefunc(target, name, fn) end
end

-- Taking money from mail: an "Auction successful" invoice is a sale.
local function mailHint(index)
  if not GetInboxHeaderInfo then return end
  local _, _, _, _, money = GetInboxHeaderInfo(index)
  if not money or money <= 0 then return end
  local invoiceType, itemName, buyer, consignment, count
  if GetInboxInvoiceInfo then
    local info = { GetInboxInvoiceInfo(index) }
    invoiceType, itemName, buyer, consignment, count = info[1], info[2], info[3], info[7], info[11]
  end
  if invoiceType == "seller" then
    hint({ source = "ahSale", amount = money, item = itemName, cut = consignment, log = "sale",
      buyer = buyer, qty = tonumber(count) })
  else
    hint({ source = "mailIn", amount = money })
  end
end

-- Buying from a vendor: which item and how many.
local function buyHint(index, quantity)
  local id = GetMerchantItemID and GetMerchantItemID(index)
  local stack = 1
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(index)
    stack = info and info.stackCount or 1
  end
  hint({ source = "vendorBuy", item = id, qty = quantity or stack, log = "vendor" })
end

-- Selling to a vendor (right-clicking a bag item while a vendor is open): which item,
-- how many, and what the vendor should pay, so quick sales can be told apart.
local function sellHint(bag, slot)
  if not isOpen("merchant") or not (C_Container and C_Container.GetContainerItemInfo) then return end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info or not info.itemID then return end
  local count = info.stackCount or 1
  local each = ns:GetSellPrice(info.itemID)
  hint({ source = "vendorSell", item = info.itemID, qty = count, amount = each and each > 0 and each * count or nil, log = "vendor" })
end

ns:OnReady(function()
  hook(_G, "BuyMerchantItem", buyHint)
  hook(C_Container, "UseContainerItem", sellHint)
  hook(_G, "TakeInboxMoney", mailHint)
  hook(_G, "AutoLootMailItem", mailHint)
  hook(_G, "RepairAllItems", function() hint({ source = "repair" }) end)
  hook(C_AuctionHouse, "PostItem", function() hint({ source = "ahFee" }) end)
  hook(C_AuctionHouse, "PostCommodity", function() hint({ source = "ahFee" }) end)
  hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
    hint({ source = "ahBuy", item = itemID, qty = quantity })
  end)
  -- The auction house window asks for an item's listings when you open it. Our own
  -- scans do too, so those are ignored. (Checks the scan's own sends, not "a scan is
  -- running": with the flip watch on, a scan is always running, so your pages were
  -- ignored and a Soldier's Armor purchase was put down as Curved Dagger, October 2.)
  hook(C_AuctionHouse, "SendSearchQuery", function(itemKey)
    -- Not the buy queue's own searches either: they run in the background while you
    -- look at another page (owner, October 2: a Stout Battlehammer page showed Crag
    -- Boar Rib's 4c limit).
    if itemKey and itemKey.itemID and not (ns.Scan and ns.Scan.sending) and not ns.queueSending then
      lastShownItem = itemKey.itemID
    end
  end)
  -- Buying one listing (gear and other single items): which item. The buy queue says
  -- which; otherwise it's the page you're on.
  hook(C_AuctionHouse, "PlaceBid", function()
    local id = ns.queueBidItem or lastShownItem
    if id then hint({ source = "ahBuy", item = id, qty = 1, single = true }) end
  end)
  pruneGold()
  -- Remove bad 0-gold readings saved before they were skipped, for characters that
  -- have real readings too.
  for _, hours in pairs(ns.db.gold) do
    local real = false
    for _, g in pairs(hours) do if g > 0 then real = true; break end end
    if real then
      for h, g in pairs(hours) do if g <= 0 then hours[h] = nil end end
    end
  end
  -- Older ledger entries become monthly totals, and old days of money in and out are
  -- summed by month (the logs are oldest first).
  foldLedger()
  foldMoney()
  -- Market history: once a day, a little at a time, a few seconds after login.
  if ns.db.lastTrim ~= today() then
    ns.db.lastTrim = today()
    C_Timer.After(10, function() if ns.TrimMarketHistory then ns:TrimMarketHistory() end end)
  end
end)

---------------------------------------------------------------------------
-- Price history, per market and item, as compact strings:
--   history[market][id]       = "day:cheapest:typical|..."        the last DAILY_DAYS days
--   historyWeekly[market][id] = "week:cheapest:typical:days|..."  older days, WEEKLY_WEEKS kept
--   historyAll[market][id]    = "lowest:typicalSum:days"          all time
-- A day keeps the lowest cheapest seen that day and the latest typical price.
---------------------------------------------------------------------------
-- How long market history is kept (owner, October 3): two weeks of days is plenty to
-- judge a deal by, older days fold into weekly averages, and a year of those is enough;
-- older market data is stale. Counts (listed per day, sell speed) are kept 30 days.
local DAILY_DAYS = 14
local WEEKLY_WEEKS = 52
local COUNT_DAYS = 30

local function marketTable(name)
  local key = ns.MarketKey()
  ns.db[name][key] = ns.db[name][key] or {}
  return ns.db[name][key]
end

-- Drop entries from the front of a history string while their first number is <= cutoff.
local function dropOld(s, cutoff, onDrop)
  while s:find("|", 1, true) do
    local first, a, b = s:match("^(%d+):(%d+):(%d+)")
    if not first or tonumber(first) > cutoff then break end
    if onDrop then onDrop(tonumber(first), tonumber(a), tonumber(b)) end
    s = s:gsub("^[^|]*|", "")
  end
  return s
end

-- A finished day adds to the all-time figures.
local function addAllTime(id, cheapest, typical)
  local all = marketTable("historyAll")
  local lo, sum, n = (all[id] or ""):match("^(%d+):(%d+):(%d+)$")
  lo, sum, n = tonumber(lo), tonumber(sum) or 0, tonumber(n) or 0
  all[id] = ("%.0f:%.0f:%.0f"):format(lo and math.min(lo, cheapest) or cheapest, sum + typical, n + 1)
end

-- A day older than DAILY_DAYS is folded into its week.
local function addWeek(id, day, cheapest, typical)
  local weekly = marketTable("historyWeekly")
  local w = math.floor(day / 7)
  local s = weekly[id] or ""
  local lw, lmin, ltyp, ln = s:match("(%d+):(%d+):(%d+):(%d+)$")
  if tonumber(lw) == w then
    ln = tonumber(ln)
    cheapest = math.min(cheapest, tonumber(lmin))
    typical = math.floor((tonumber(ltyp) * ln + typical) / (ln + 1) + 0.5)
    s = s:gsub("[^|]*$", "") .. ("%.0f:%.0f:%.0f:%.0f"):format(w, cheapest, typical, ln + 1)
  else
    s = (s ~= "" and (s .. "|") or "") .. ("%.0f:%.0f:%.0f:1"):format(w, cheapest, typical)
  end
  weekly[id] = dropOld(s, w - WEEKLY_WEEKS)
end

-- How many were listed each day (the most seen that day), for "usually N listed" on deals.
local function recordListed(id, d, listed)
  local qty = marketTable("historyQty")
  local s = qty[id] or ""
  local lastDay, lastQ = s:match("(%d+):(%d+)$")
  if tonumber(lastDay) == d then
    listed = math.max(listed, tonumber(lastQ))
    s = s:gsub("[^|]*$", "")
  elseif s ~= "" then
    s = s .. "|"
  end
  s = s .. ("%.0f:%.0f"):format(d, listed)
  while s:find("|", 1, true) and tonumber(s:match("^(%d+)")) <= d - COUNT_DAYS do s = s:gsub("^[^|]*|", "") end
  qty[id] = s
end

function ns:RecordPriceHistory(id, cheapest, typical, listed)
  if not ns.db or not cheapest then return end
  typical = typical or cheapest
  local hist = marketTable("history")
  local d = today()
  if listed then recordListed(id, d, listed) end
  local s = hist[id] or ""
  local lastDay, lastMin, lastTyp = s:match("(%d+):(%d+):(%d+)$")
  lastDay = tonumber(lastDay)
  if lastDay == d then
    cheapest = math.min(cheapest, tonumber(lastMin))
    s = s:gsub("[^|]*$", "")
  else
    -- The previous day is finished.
    if lastDay then addAllTime(id, tonumber(lastMin), tonumber(lastTyp)) end
    if s ~= "" then s = s .. "|" end
  end
  s = s .. ("%.0f:%.0f:%.0f"):format(d, cheapest, typical)
  hist[id] = dropOld(s, d - DAILY_DAYS, function(day, m, a) addWeek(id, day, m, a) end)
end

-- Once a day, trim this market's history for every item, including ones no longer listed
-- (those are only trimmed here, as nothing records them). A little at a time, so login
-- doesn't hitch. Days past DAILY_DAYS fold into their week, as when a price is recorded.
local function trimCounts(s, cutoff)
  local out = {}
  for e in s:gmatch("[^|]+") do
    if (tonumber(e:match("^(%d+)")) or 0) > cutoff then out[#out + 1] = e end
  end
  return #out > 0 and table.concat(out, "|") or nil
end

function ns:TrimMarketHistory()
  local d = today()
  local hist, weekly = marketTable("history"), marketTable("historyWeekly")
  local qty, sold = marketTable("historyQty"), marketTable("historySold2")
  local ids = {}
  for id in pairs(hist) do ids[#ids + 1] = id end
  for id in pairs(weekly) do if not hist[id] then ids[#ids + 1] = id end end
  for id in pairs(qty) do if not hist[id] and not weekly[id] then ids[#ids + 1] = id end end
  for id in pairs(sold) do if not hist[id] and not weekly[id] and not qty[id] then ids[#ids + 1] = id end end
  local i = 0
  local function step()
    for _ = 1, 200 do
      i = i + 1
      local id = ids[i]
      if not id then return end
      if hist[id] then
        local kept, last = {}, nil
        for e in hist[id]:gmatch("[^|]+") do
          local day, m, a = e:match("^(%d+):(%d+):(%d+)")
          day = tonumber(day)
          if day and day <= d - DAILY_DAYS then
            addWeek(id, day, tonumber(m), tonumber(a))
            last = { tonumber(m), tonumber(a) }
          else
            kept[#kept + 1] = e
            last = nil
          end
        end
        -- An item no longer listed: its last day was never finished by a newer one, so
        -- it hasn't counted toward all time yet.
        if #kept == 0 and last then addAllTime(id, last[1], last[2]) end
        hist[id] = #kept > 0 and table.concat(kept, "|") or nil
      end
      if weekly[id] then weekly[id] = trimCounts(weekly[id], math.floor(d / 7) - WEEKLY_WEEKS) end
      if qty[id] then qty[id] = trimCounts(qty[id], d - COUNT_DAYS) end
      if sold[id] then sold[id] = trimCounts(sold[id], d - COUNT_DAYS) end
    end
    C_Timer.After(0, step)
  end
  step()
end

-- Returns a list of { day, cheapest, typical } for the last DAILY_DAYS days, oldest first.
function ns:PriceHistory(id)
  local out = {}
  for d, m, a in (marketTable("history")[id] or ""):gmatch("(%d+):(%d+):(%d+)") do
    out[#out + 1] = { tonumber(d), tonumber(m), tonumber(a) }
  end
  return out
end

-- Periods for "usual price", in days.
ns.PRICE_WINDOWS = { week = 7, month = 30, ["3months"] = 91, ["6months"] = 182, year = 365, all = math.huge }

-- Price history from before an item's vendor price changed is left out: the old vendor
-- price held the auction price up or down (October 1 build: crafted wands went from
-- 15s to 1 copper at vendors, so their "usual price" of about 15s no longer applies).
-- vendorSellChanged[id] = the local day the change was seen (Prices.lua GetSellPrice).
local function historyStart(id, from)
  local changed = ns.db and ns.db.vendorSellChanged and ns.db.vendorSellChanged[id]
  if changed and changed > from then return changed end
  return from
end
-- The usual price over a period: the median of the daily (and weekly, for older
-- times) typical prices, leaving today out. Returns the price and how many points it used.
function ns:UsualPrice(id, window)
  local d = today()
  local from = d - (ns.PRICE_WINDOWS[window or "all"] or math.huge)
  from = historyStart(id, from)
  local points = {}
  for day, _, typ in (marketTable("history")[id] or ""):gmatch("(%d+):(%d+):(%d+)") do
    day = tonumber(day)
    if day < d and day >= from then points[#points + 1] = tonumber(typ) end
  end
  for w, _, typ in (marketTable("historyWeekly")[id] or ""):gmatch("(%d+):(%d+):(%d+):%d+") do
    if (tonumber(w) + 1) * 7 > from then points[#points + 1] = tonumber(typ) end
  end
  if #points == 0 then return nil, 0 end
  table.sort(points)
  return points[math.floor((#points + 1) / 2)], #points
end

-- Sell speed (Prices.lua compares full scans): units gone between scans, the minutes
-- covered, and how many of those minutes came from close ("watched") pairs, summed per
-- day: historySold[market][id] = "day:gone:minutes:closeMinutes|..." (30 days; entries
-- written before the close count was added have three numbers).
local function soldEntry(e)
  local d, g, m, c = e:match("^(%d+):(%d+):(%d+):?(%d*)$")
  -- Three-number entries came from the first version, which only compared scans within
  -- one session (the flip watch), so count them as close.
  return tonumber(d), tonumber(g), tonumber(m), tonumber(c) or tonumber(m)
end

-- historySold2 since October 2: counted from listings that can't have expired (time
-- left). The old historySold (counts of listings that went down, mostly noise) was
-- dropped in 0.9.0 (Core.lua, schema 2).
local SOLD_TABLE = "historySold2"

function ns:RecordSold(id, gone, minutes, close)
  if not ns.db or minutes <= 0 then return end
  if ns.ForgetSellSpeeds then ns:ForgetSellSpeeds() end
  local sold = marketTable(SOLD_TABLE)
  local d = today()
  local s = sold[id] or ""
  local closeMin = close and minutes or 0
  local lastDay, lastGone, lastMin, lastClose = soldEntry(s:match("[^|]*$"))
  if lastDay == d then
    gone, minutes, closeMin = gone + lastGone, minutes + lastMin, closeMin + lastClose
    s = s:gsub("[^|]*$", "")
  elseif s ~= "" then
    s = s .. "|"
  end
  s = s .. ("%.0f:%.0f:%.0f:%.0f"):format(d, gone, minutes, closeMin)
  while s:find("|", 1, true) and tonumber(s:match("^(%d+)")) <= d - COUNT_DAYS do s = s:gsub("^[^|]*|", "") end
  sold[id] = s
end

-- Units gone between scans, minutes of scans behind it, and the minutes from close
-- ("watched") pairs, over a period (today included).
function ns:SellRate(id, window)
  local from = today() - math.min(ns.PRICE_WINDOWS[window or "all"] or math.huge, COUNT_DAYS)
  local gone, minutes, close = 0, 0, 0
  for e in (marketTable(SOLD_TABLE)[id] or ""):gmatch("[^|]+") do
    local day, g, m, c = soldEntry(e)
    if day and day >= from then gone, minutes, close = gone + g, minutes + m, close + c end
  end
  return gone, minutes, close
end

---------------------------------------------------------------------------
-- Sell speed rating (owner's design, October 2): judged against items of the same kind,
-- since Copper Ore is expected to move in bulk and a sword isn't. Turnover is units
-- bought a day for each one usually listed: 4 a day with 5 listed beats 100 listed and
-- none selling. Rare items that are seldom listed but go when they are get their own
-- rating. Shown only after 3 hours of scans compared (the flip watch gets there fastest).
---------------------------------------------------------------------------
local SPEED_MIN_MINUTES = 180
local SPEED_NONE_MINUTES = 12 * 60   -- this long with none bought: "no sales seen"
local SPEED = {
  fast = { label = "Fast", color = "7fd39c" },
  steady = { label = "Steady", color = "c8e37c" },
  slow = { label = "Slow", color = "ffd100" },
  rare = { label = "Rare, sells quickly", color = "7fb8ff" },
  none = { label = "No sales seen", color = "ee8597" },
}
-- Turnover needed for Fast and Steady, per kind.
local SPEED_STEPS = {
  goods = { 0.5, 0.15 },   -- stackable materials and consumables
  gear = { 1, 0.3 },
  other = { 1, 0.3 },      -- recipes, single items
}

local instantInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
-- What kind of item: "gear" (armor and weapons), "goods" (stacks: materials,
-- consumables) or "other" (recipes, single items). Also the Deals tab's filter.
function ns:ItemKind(id)
  if not instantInfo then return "other" end
  -- (Called on its own line: "instantInfo and instantInfo(id)" keeps only the first
  -- value, the item ID, so nothing ever counted as gear. Owner's screenshot, October 2.)
  local _, _, _, _, _, classID = instantInfo(id)
  if classID == 2 or classID == 4 then return "gear" end
  local stack = select(8, ns.GetItemInfo(id))
  if stack and stack > 1 then return "goods" end
  return "other"
end
local function speedKind(id) return ns:ItemKind(id) end

-- Worked out once per item until the next full scan (or day): the Deals tab and deal
-- check ask for hundreds of items at a time (/fl perf, October 3: up to 0.28 s).
local speedCache, speedDay, speedMarket = {}, nil, nil
function ns:ForgetSellSpeeds() speedCache = {} end

-- Returns nil and the minutes of scans so far when there isn't enough yet; otherwise
-- { key, label, color, perDay, listed, hours, kind }.
local sellSpeed
function ns:SellSpeed(id)
  local d, m = today(), ns.MarketKey()
  if d ~= speedDay or m ~= speedMarket then speedCache, speedDay, speedMarket = {}, d, m end
  local c = speedCache[id]
  if not c then
    c = { sellSpeed(id) }
    speedCache[id] = c
  end
  return c[1], c[2]
end

-- Fewer sales than this aren't enough to judge by in the first day: one piece of gear
-- gone in 3 hours made it "Fast" (owner's Deals tab, October 3: nearly all gear Fast).
local SPEED_MIN_SALES = 3
sellSpeed = function(id)
  local gone, minutes = ns:SellRate(id, "month")
  if minutes < SPEED_MIN_MINUTES then return nil, minutes end
  if gone > 0 and gone < SPEED_MIN_SALES and minutes < 24 * 60 then return nil, minutes end
  local perDay = gone / minutes * 1440
  local stats = ns:PriceStats(id, "month")
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  local listed = (stats and stats.listed) or (rec and not rec.none and rec.q) or 0
  local kind = speedKind(id)
  local key
  if gone == 0 then
    if minutes < SPEED_NONE_MINUTES then return nil, minutes end
    key = "none"
  elseif kind ~= "goods" and listed <= 2 and perDay >= 1 then
    key = "rare"
  else
    local steps = SPEED_STEPS[kind]
    local turnover = perDay / math.max(listed, 1)
    key = (turnover >= steps[1] and "fast") or (turnover >= steps[2] and "steady") or "slow"
  end
  local s = SPEED[key]
  return { key = key, label = s.label, color = s.color, perDay = perDay, listed = listed,
    hours = minutes / 60, kind = kind }
end

-- "Steady, about 12 a day (40 listed)" for tooltips and the Deals tab.
function ns:SellSpeedText(sp)
  local per = sp.perDay >= 1 and ("about %d a day"):format(math.floor(sp.perDay + 0.5))
    or sp.perDay > 0 and "under 1 a day" or "none bought"
  return ("|cff%s%s|r, %s (%s listed)"):format(sp.color, sp.label, per, math.floor(sp.listed + 0.5))
end

local function median(list)
  if #list == 0 then return nil end
  table.sort(list)
  return list[math.floor((#list + 1) / 2)]
end

-- Everything known about an item's past prices over a period, for judging a deal.
-- Leaves today out, like UsualPrice. Returns nil without history, else a table:
--   usual = median typical price, low = median of each day's cheapest,
--   q1, q3 = the typical prices a quarter and three quarters of the way up (spread),
--   points = days (and older weeks) used, days = daily points only,
--   firstDay = the oldest day used, listed = median listed per day (nil before it was recorded).
function ns:PriceStats(id, window)
  local d = today()
  local from = d - (ns.PRICE_WINDOWS[window or "all"] or math.huge)
  from = historyStart(id, from)
  local typ, low, first, days = {}, {}, nil, 0
  for day, m, a in (marketTable("history")[id] or ""):gmatch("(%d+):(%d+):(%d+)") do
    day = tonumber(day)
    if day < d and day >= from then
      typ[#typ + 1], low[#low + 1] = tonumber(a), tonumber(m)
      first, days = first or day, days + 1
    end
  end
  for w, m, a in (marketTable("historyWeekly")[id] or ""):gmatch("(%d+):(%d+):(%d+):%d+") do
    w = tonumber(w)
    if (w + 1) * 7 > from then
      typ[#typ + 1], low[#low + 1] = tonumber(a), tonumber(m)
      first = math.min(first or w * 7, w * 7)
    end
  end
  if #typ == 0 then return nil end
  local listed = {}
  for day, q in (marketTable("historyQty")[id] or ""):gmatch("(%d+):(%d+)") do
    day = tonumber(day)
    if day < d and day >= from then listed[#listed + 1] = tonumber(q) end
  end
  local n = #typ
  local usual = median(typ)   -- sorts typ
  return {
    usual = usual, low = median(low), points = n, days = days, firstDay = first,
    q1 = typ[math.max(1, math.ceil(n / 4))], q3 = typ[math.max(1, math.ceil(n * 3 / 4))],
    listed = median(listed),
  }
end

-- All time: lowest price ever seen and the average typical price, or nil.
function ns:AllTimePrice(id)
  local lo, sum, n = (marketTable("historyAll")[id] or ""):match("^(%d+):(%d+):(%d+)$")
  if not lo then return end
  return tonumber(lo), tonumber(sum) / tonumber(n), tonumber(n)
end

---------------------------------------------------------------------------
-- /fl money: today's money in and out for this character, for testing
---------------------------------------------------------------------------
local LABELS = {
  ahSale = "Auction house sales", ahBuy = "Auction house purchases", ahFee = "Auction house fees",
  vendorSell = "Sold to vendors", vendorBuy = "Bought from vendors", repair = "Repairs",
  mailIn = "Mail received", mailOut = "Mail sent", tradeIn = "Trade received", tradeOut = "Trade given",
  loot = "Loot", quest = "Quests", training = "Training", flight = "Flights",
  otherIn = "Other income", otherOut = "Other spending",
}
local INCOME = { ahSale = true, vendorSell = true, mailIn = true, tradeIn = true, loot = true, quest = true, otherIn = true }

-- Today's money for this character as lines ("Sold to vendors: +5s"), plus the net.
function ns:MoneyToday()
  local totals = (ns.db.money[ns.CharKey()] or {})[today()]
  if not totals or not next(totals) then return nil end
  local keys = {}
  for k in pairs(totals) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines, net = {}, 0
  for _, k in ipairs(keys) do
    local sign = INCOME[k] and 1 or -1
    net = net + sign * totals[k]
    lines[#lines + 1] = ("%s: %s%s"):format(LABELS[k] or k, sign > 0 and "+" or "-", ns.Money(totals[k]))
  end
  return lines, net
end

-- The first day anything was recorded, as text, or nil.
function ns:RecordingSince()
  local first
  for _, hours in pairs(ns.db.gold) do
    for h in pairs(hours) do if not first or h < first then first = h end end
  end
  return first and date("%B %d", first * 3600)
end

function ns:PrintMoney()
  local lines, net = ns:MoneyToday()
  if not lines then ns:Print("No money in or out recorded today yet."); return end
  ns:Print("Money today for " .. (UnitName("player") or "?") .. ":")
  for _, line in ipairs(lines) do print("    " .. line) end
  print(("    Net: %s%s"):format(net >= 0 and "+" or "-", ns.Money(math.abs(net))))
end
