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
local function monthKey(e) return table.concat({ e.t, e.c or "?", e.k, e.id or e.n or "?" }, "|") end

-- Add one ledger entry to its month's total (index: monthKey -> total, optional).
local function foldEntry(e, kind, index)
  local months = ns.db.ledgerMonths
  local d = date("*t", e.t or 0)
  local m = { t = time({ year = d.year, month = d.month, day = 1, hour = 12 }), c = e.c, k = kind,
    id = e.id, n = (not e.id) and e.n or nil }
  local k = monthKey(m)
  local x = index and index[k]
  if not index then
    for _, y in ipairs(months) do if monthKey(y) == k then x = y; break end end
  end
  if not x then
    x = m
    x.q, x.a, x.cnt, x.mx = 0, 0, 0, 0
    months[#months + 1] = x
    if index then index[k] = x end
  end
  local amount = e.a or 0
  x.q, x.a, x.cnt = x.q + (e.q or 1), x.a + amount, x.cnt + 1
  if amount > x.mx then x.mx = amount end
end

local function foldLedger()
  local months = ns.db.ledgerMonths
  local index = {}
  for _, m in ipairs(months) do index[monthKey(m)] = m end
  local cutoff = time() - LOG_DAYS * 86400
  local function fold(list, kindOf)
    local drop = 0
    while list[drop + 1] and (list[drop + 1].t or 0) < cutoff do
      drop = drop + 1
      local e = list[drop]
      foldEntry(e, kindOf(e), index)
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
  -- Over the cap, the oldest goes into its month's total rather than away (the tests
  -- found it was dropped, losing its copper from the Ledger, PR #8, October 4). Only your
  -- own: a partner's are theirs to fold, or the next sync brings one back and it counts
  -- twice (Codex review, November 5).
  if #list <= LOG_SIZE then return end
  local from = ns.db.booksFrom or {}
  local own = 0
  for i = 1, #list do
    if not from[list[i].c] then own = own + 1 end
  end
  local i = 1
  while own > LOG_SIZE do
    if from[list[i].c] then i = i + 1
    else
      local old = table.remove(list, i)
      own = own - 1
      local kind = (list == ns.db.sales and "sale") or (list == ns.db.purchases and "buy")
        or (old.s == "sell" and "vsell" or "vbuy")
      foldEntry(old, kind)
    end
  end
end

---------------------------------------------------------------------------
-- The books: what the Dashboard and Ledger show, by character. Live sync sends your
-- characters' books to your partner (Sync.lua), who replaces their copy of that stretch.
-- An entry can change after it's made (vendor trades merge, today's totals grow), so
-- it's replaced by time rather than added to.
---------------------------------------------------------------------------
local BOOK_LOGS = { "sales", "purchases", "vendorLog", "sessions" }

-- When an entry last changed: a session's end, not its start (Codex review, November 5:
-- a long session started before the stretch being sent, so it never went).
local function bookTime(e) return e.stop or e.t or 0 end

-- Keep only the entries keep(e) wants, in the same table (addLog compares tables).
local function filterLog(list, keep)
  local n = 0
  for i = 1, #list do
    local e = list[i]
    list[i] = nil
    if keep(e) then n = n + 1; list[n] = e end
  end
end

-- Your characters' books from the time `from` on; from 0, everything, with the monthly
-- totals too (entries over 30 days old are only there).
function ns:BooksSince(from)
  local b = { from = from, chars = {} }
  local firstDay = ns.LocalDay(from)
  for key, c in pairs(ns.db.chars) do
    if not c.via then
      local gold, money = {}, {}
      for h, v in pairs(ns.db.gold[key] or {}) do
        if h * 3600 >= from - 3600 then gold[h] = v end
      end
      for day, src in pairs(ns.db.money[key] or {}) do
        if day >= firstDay then money[day] = src end
      end
      b.chars[key] = { gold = gold, money = money }
    end
  end
  local function mine(e) return e.c and b.chars[e.c] ~= nil end
  for _, name in ipairs(BOOK_LOGS) do
    b[name] = {}
    for _, e in ipairs(ns.db[name] or {}) do
      if bookTime(e) >= from and mine(e) then table.insert(b[name], e) end
    end
  end
  if from == 0 then
    b.months = {}
    for _, m in ipairs(ns.db.ledgerMonths or {}) do
      if mine(m) then table.insert(b.months, m) end
    end
  end
  return b
end

-- A partner's books. Never touches a character played on this account. Returns how many
-- characters' books came in. The whole stretch sent is replaced, gold and money too: the
-- sender may have folded old days together (Codex review, November 5). via = the partner,
-- remembered in booksFrom so /fl unpair can take these out again.
function ns:MergeBooks(b, via)
  local theirs, n = {}, 0
  local from = b.from or 0
  local firstDay = ns.LocalDay(from)
  ns.db.booksFrom = ns.db.booksFrom or {}
  for key, c in pairs(b.chars or {}) do
    if not ns:IsOwnChar(key) then
      theirs[key] = true
      n = n + 1
      ns.db.booksFrom[key] = via or ns.db.booksFrom[key]
      local gold, money = ns.db.gold[key] or {}, ns.db.money[key] or {}
      ns.db.gold[key], ns.db.money[key] = gold, money
      for h in pairs(gold) do
        if h * 3600 >= from - 3600 then gold[h] = nil end
      end
      for day in pairs(money) do
        if day >= firstDay then money[day] = nil end
      end
      for h, v in pairs(c.gold or {}) do gold[h] = v end
      for day, src in pairs(c.money or {}) do money[day] = src end
    end
  end
  local function replace(list, new)
    filterLog(list, function(e) return not (theirs[e.c] and bookTime(e) >= from) end)
    for _, e in ipairs(new) do
      if theirs[e.c] then list[#list + 1] = e end
    end
    table.sort(list, function(x, y) return (x.t or 0) < (y.t or 0) end)
  end
  for _, name in ipairs(BOOK_LOGS) do
    ns.db[name] = ns.db[name] or {}
    if b[name] then replace(ns.db[name], b[name]) end
  end
  if b.months then replace(ns.db.ledgerMonths, b.months) end
  return n
end

-- /fl unpair: what came from a partner goes.
function ns:DropBooks(key)
  ns.db.gold[key], ns.db.money[key] = nil, nil
  local function notTheirs(e) return e.c ~= key end
  for _, name in ipairs(BOOK_LOGS) do filterLog(ns.db[name] or {}, notTheirs) end
  filterLog(ns.db.ledgerMonths, notTheirs)
end

local function onMoney()
  local now = GetMoney()
  if not lastMoney then lastMoney = now; return end
  local delta = now - lastMoney
  lastMoney = now
  snapshotGold()
  if ns.BooksChanged then ns:BooksChanged() end
  if delta == 0 then return end

  local hints = takeHints(delta)
  local source = hints[1] and hints[1].source or sourceFor(delta)
  local day = charTable(ns.db.money)
  day[today()] = day[today()] or {}
  local totals = day[today()]
  -- An auction sale's mail pays the deposit back too: that part is kept apart, so Sales
  -- is the sale after the cut and the deposit offsets the fee you paid (owner's
  -- question, October 4: 10 Empty Vials showed 13c each, 1s 26c with 50c deposit).
  local dep = source == "ahSale" and hints[1] and hints[1].deposit or 0
  if dep <= 0 or dep >= math.abs(delta) then dep = 0 end
  totals[source] = (totals[source] or 0) + math.abs(delta) - dep
  if dep > 0 then totals.ahDepositBack = (totals.ahDepositBack or 0) + dep end
  -- A running session counts it too (Sessions.lua).
  if ns.SessionMoney then ns:SessionMoney(source, delta) end
  if ns.DungeonMoney then ns:DungeonMoney(source, delta) end   -- and a dungeon run (Dungeons.lua)

  local now, who = time(), ns.CharKey()
  for _, h in ipairs(hints) do
    local amount = (#hints > 1 and h.amount) or math.abs(delta)
    if h.log == "sale" then
      local d = (h.deposit and h.deposit > 0 and h.deposit < amount) and h.deposit or nil
      addLog(ns.db.sales, { t = now, c = who, n = h.item, a = amount - (d or 0), dep = d, cut = h.cut, q = h.qty, b = h.buyer })
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

-- An auction sold ("A buyer has been found for your auction of X."): a coin sound
-- (owner, October 3; Settings, Auction house: saleSound). Off by itself when ForeverForge,
-- which has its own, is found (Help.lua ns.OVERLAPS).
local soldPattern
ns:On("CHAT_MSG_SYSTEM", function(msg)
  if not (msg and ns.db and ns.db.settings.saleSound ~= false and ERR_AUCTION_SOLD_S) then return end
  if not soldPattern then
    soldPattern = "^" .. ERR_AUCTION_SOLD_S:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
  end
  if msg:find(soldPattern) and PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND) or 120, "Master")
  end
end)

-- Taking money from mail: an "Auction successful" invoice is a sale.
local function mailHint(index)
  if not GetInboxHeaderInfo then return end
  local _, _, _, _, money = GetInboxHeaderInfo(index)
  if not money or money <= 0 then return end
  local invoiceType, itemName, buyer, deposit, consignment, count
  if GetInboxInvoiceInfo then
    local info = { GetInboxInvoiceInfo(index) }
    invoiceType, itemName, buyer, deposit, consignment, count = info[1], info[2], info[3], info[6], info[7], info[11]
  end
  if invoiceType == "seller" then
    hint({ source = "ahSale", amount = money, item = itemName, cut = consignment, log = "sale",
      buyer = buyer, qty = tonumber(count), deposit = tonumber(deposit) })
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
--   history[market][id]       = "day:cheapest:typical|..."        the last KEEP_DAYS days
--   historyWeekly[market][id] = "week:cheapest:typical:days|..."  older days, WEEKLY_WEEKS kept
--   historyAll[market][id]    = "lowest:typicalSum:days"          all time
-- A day keeps the lowest cheapest seen that day and the latest typical price.
---------------------------------------------------------------------------
-- How long market history is kept (owner, October 3): two weeks of days is plenty to
-- judge a deal by (DAILY_DAYS, pricingPoints), older days count as weekly averages, and a
-- year of those is enough; older market data is stale. Counts (listed per day, sell
-- speed) are kept 30 days.
local DAILY_DAYS = 14
local WEEKLY_WEEKS = 52
local COUNT_DAYS = 30
-- Price graphs (owner, November 7): every item keeps KEEP_DAYS of days before they fold
-- into weeks, and so does every version of gear with random stats. Pricing (usual
-- prices, deals, buy limits) still reads the last DAILY_DAYS one by one and older days as
-- weeks (pricingPoints), so keeping more days doesn't move it.
local KEEP_DAYS = 90

-- key: the market to use; the current one if not given. A trim spread over several frames
-- passes the market it started in, as the auction house can change in between (Codex
-- review, November 7).
local function marketTable(name, key)
  key = key or ns.MarketKey()
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
local function addAllTime(id, cheapest, typical, key)
  local all = marketTable("historyAll", key)
  local lo, sum, n = (all[id] or ""):match("^(%d+):(%d+):(%d+)$")
  lo, sum, n = tonumber(lo), tonumber(sum) or 0, tonumber(n) or 0
  all[id] = ("%.0f:%.0f:%.0f"):format(lo and math.min(lo, cheapest) or cheapest, sum + typical, n + 1)
end

-- A day older than KEEP_DAYS is folded into its week.
local function addWeek(id, day, cheapest, typical, key)
  local weekly = marketTable("historyWeekly", key)
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
local function recordListed(id, d, listed, key)
  local qty = marketTable("historyQty", key)
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

-- key: the market (nil = the one you're at): prices from a sync partner name theirs.
function ns:RecordPriceHistory(id, cheapest, typical, listed, key)
  if not ns.db or not cheapest then return end
  typical = typical or cheapest
  local hist = marketTable("history", key)
  local d = today()
  if listed then recordListed(id, d, listed, key) end
  local s = hist[id] or ""
  local lastDay, lastMin, lastTyp = s:match("(%d+):(%d+):(%d+)$")
  lastDay = tonumber(lastDay)
  if lastDay == d then
    cheapest = math.min(cheapest, tonumber(lastMin))
    s = s:gsub("[^|]*$", "")
  else
    -- The previous day is finished.
    if lastDay then addAllTime(id, tonumber(lastMin), tonumber(lastTyp), key) end
    if s ~= "" then s = s .. "|" end
  end
  s = s .. ("%.0f:%.0f:%.0f"):format(d, cheapest, typical)
  hist[id] = dropOld(s, d - KEEP_DAYS, function(day, m, a) addWeek(id, day, m, a, key) end)
end

---------------------------------------------------------------------------
-- History catch-up between sync partners (Sync.lua; owner, November 8: on the main
-- account an alt's graphs had only the days that account was online, while the other
-- account scanned every day). Finished days go whole, one at a time, packed small:
-- a day of a full scan is about 4,400 items.
---------------------------------------------------------------------------
local CATCHUP_TAIL = 600   -- characters from the end of a history string: 20 or more days

-- The end of a history string, from an entry's start: every day in the last two weeks
-- is in it (one entry a day, at most about 30 characters each). Returns head, tail;
-- head is everything before the tail, with its "|", or "".
local function splitTail(s)
  if #s <= CATCHUP_TAIL then return "", s end
  local cut = #s - CATCHUP_TAIL
  local bar = s:find("|", cut + 1, true)
  if not bar then return "", s end
  return s:sub(1, bar), s:sub(bar + 1)
end

-- One day's numbers in a history string ("day:a:b|..." or "day:a|..."), as captured by pat.
local function findDay(s, day, pat)
  if not s then return end
  local d = tostring(day) .. ":"
  if s:sub(1, #d) == d then return s:match("^" .. d .. pat) end
  return s:match("|" .. d .. pat)
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(n)
  if n <= 0 then return "0" end
  local out = ""
  while n > 0 do
    local r = n % 36
    out = B36:sub(r + 1, r + 1) .. out
    n = math.floor(n / 36)
  end
  return out
end
ns.Base36 = b36   -- (tests)

-- How many items have a price on each of these days, per market: { [market] = { [day] = n } }.
function ns:HistoryDayCounts(from, to)
  local out = {}
  for market, items in pairs(ns.db.history or {}) do
    local c
    for _, s in pairs(items) do
      if type(s) == "string" then
        local _, tail = splitTail(s)
        for day in tail:gmatch("(%d+):%d+:%d+") do
          day = tonumber(day)
          if day >= from and day <= to then
            c = c or {}
            c[day] = (c[day] or 0) + 1
          end
        end
      end
    end
    if c then out[market] = c end
  end
  return out
end

-- One market's prices for one day, packed for sending: "id.cheapest.typical.listed" per
-- item, comma-separated, in base 36, each id as the step from the one before (sorted),
-- typical left out when it equals cheapest, listed when not known. Returns it and how
-- many items it holds.
function ns:PackHistoryDay(market, day)
  local hist = (ns.db.history or {})[market] or {}
  local qty = (ns.db.historyQty or {})[market] or {}
  local found, ids = {}, {}
  for id, s in pairs(hist) do
    if type(id) == "number" and type(s) == "string" then
      local _, tail = splitTail(s)
      local m, a = findDay(tail, day, "(%d+):(%d+)")
      if m then found[id] = { tonumber(m), tonumber(a) }; ids[#ids + 1] = id end
    end
  end
  table.sort(ids)
  local out, prev = {}, 0
  for _, id in ipairs(ids) do
    local m, a = found[id][1], found[id][2]
    local q = type(qty[id]) == "string" and tonumber(findDay(qty[id], day, "(%d+)"))
    out[#out + 1] = b36(id - prev) .. "." .. b36(m) .. "." .. (a ~= m and b36(a) or "") .. "." .. (q and b36(q) or "")
    prev = id
  end
  return table.concat(out, ","), #out
end

-- The lowest price ever, when a finished day turns out lower.
local function allTimeLowest(id, cheapest, key)
  local all = marketTable("historyAll", key)
  local lo, sum, n = (all[id] or ""):match("^(%d+):(%d+):(%d+)$")
  if lo and cheapest < tonumber(lo) then all[id] = ("%.0f:%s:%s"):format(cheapest, sum, n) end
end

-- One item's day into its history string. A day you have keeps its typical price and
-- the lower cheapest. All time counts finished days only: a day put in before a later
-- one counts now, the last one when a newer day finishes it (RecordPriceHistory). True
-- if anything changed.
local function mergeDay(hist, id, day, m, a, key)
  local head, tail = splitTail(hist[id] or "")
  -- A day older than the tail may be in the head: the whole string then (Codex review,
  -- November 8: it was put in again after the head, out of order and counted twice).
  local first = tonumber(tail:match("^(%d+):"))
  if head ~= "" and not (first and day >= first) then head, tail = "", hist[id] end
  local out, placed, changed = {}, false, false
  local lastBefore   -- the entry that was last, if the day goes after it
  for e in tail:gmatch("[^|]+") do
    local ed, em, ea = e:match("^(%d+):(%d+):(%d+)")
    ed = tonumber(ed)
    if ed == day then
      placed = true
      if m < tonumber(em) then
        e = ("%.0f:%.0f:%s"):format(day, m, ea)
        changed = true
      end
    elseif ed and ed > day and not placed then
      out[#out + 1] = ("%.0f:%.0f:%.0f"):format(day, m, a)
      placed, changed = true, true
      addAllTime(id, m, a, key)
    end
    out[#out + 1] = e
    lastBefore = ed and { tonumber(em), tonumber(ea) } or nil
  end
  if not placed then
    out[#out + 1] = ("%.0f:%.0f:%.0f"):format(day, m, a)
    changed = true
    -- The day that was last is finished now.
    if lastBefore then addAllTime(id, lastBefore[1], lastBefore[2], key) end
  elseif changed and tail:match("(%d+):%d+:%d+$") ~= tostring(day) then
    allTimeLowest(id, m, key)
  end
  if changed then hist[id] = head .. table.concat(out, "|") end
  return changed
end

-- One day's listed count into an item's counts ("day:listed|..."): the higher of the two.
local function mergeListed(qty, id, day, q)
  local out, placed = {}, false
  for e in (qty[id] or ""):gmatch("[^|]+") do
    local ed, eq = e:match("^(%d+):(%d+)")
    ed = tonumber(ed)
    if ed == day then
      placed = true
      e = ("%.0f:%.0f"):format(day, math.max(q, tonumber(eq)))
    elseif ed and ed > day and not placed then
      out[#out + 1] = ("%.0f:%.0f"):format(day, q)
      placed = true
    end
    out[#out + 1] = e
  end
  if not placed then out[#out + 1] = ("%.0f:%.0f"):format(day, q) end
  qty[id] = table.concat(out, "|")
end

-- A day from the sync partner (PackHistoryDay's text) into this account's history. Only
-- finished days still kept day by day. Returns how many items changed.
function ns:MergeHistoryDay(market, day, packed)
  day = tonumber(day)
  if type(market) ~= "string" or type(packed) ~= "string" or not day then return 0 end
  local d = today()
  if day >= d or day <= d - KEEP_DAYS then return 0 end
  local hist, qty = marketTable("history", market), marketTable("historyQty", market)
  local id, n = 0, 0
  -- Empty entries count too (Codex review, November 8: skipping a damaged empty one gave
  -- the rest of the day to the wrong items).
  for e in (packed .. ","):gmatch("([^,]*),") do
    local step, m, a, q = e:match("^(%w+)%.(%w+)%.(%w*)%.(%w*)$")
    step, m = tonumber(step or "", 36), tonumber(m or "", 36)
    -- (each id is a step from the last, so nothing after a damaged entry can be trusted)
    if not (step and m) then break end
    id = id + step
    a, q = tonumber(a, 36) or m, tonumber(q, 36)
    if mergeDay(hist, id, day, m, a, market) then n = n + 1 end
    if q and day > d - COUNT_DAYS then mergeListed(qty, id, day, q) end
  end
  return n
end

---------------------------------------------------------------------------
-- Versions of gear with random stats ("of the Eagle"), from full scans only:
--   historyVersions[market][id][suffix]       = "day:cheapest:listed|..."            KEEP_DAYS days
--   historyVersionsWeekly[market][id][suffix] = "week:cheapest:listedSum:days|..."   WEEKLY_WEEKS kept
-- A day keeps the lowest cheapest and the most listed seen that day; a week the lowest
-- cheapest and the sum of each day's listed, so the average (sum / days) is only rounded
-- when shown (Codex review, November 7: rounding each day's running average drifted).
---------------------------------------------------------------------------
local function versionTable(name, id, key)
  local t = marketTable(name, key)
  t[id] = t[id] or {}
  return t[id]
end

local function addVersionWeek(id, suffix, day, cheapest, listed, key)
  local weekly = versionTable("historyVersionsWeekly", id, key)
  local w = math.floor(day / 7)
  local s = weekly[suffix] or ""
  local lw, lmin, lq, ln = s:match("(%d+):(%d+):(%d+):(%d+)$")
  if tonumber(lw) == w then
    cheapest = math.min(cheapest, tonumber(lmin))
    s = s:gsub("[^|]*$", "") .. ("%.0f:%.0f:%.0f:%.0f"):format(w, cheapest, tonumber(lq) + listed, tonumber(ln) + 1)
  else
    s = (s ~= "" and (s .. "|") or "") .. ("%.0f:%.0f:%.0f:1"):format(w, cheapest, listed)
  end
  weekly[suffix] = dropOld(s, w - WEEKLY_WEEKS)
end

-- bySuffix: { [suffix] = { m = cheapest, q = listed } } from one full scan of the item.
function ns:RecordVersionHistory(id, bySuffix)
  if not ns.db then return end
  local d = today()
  local hist = versionTable("historyVersions", id)
  for suffix, v in pairs(bySuffix) do
    local cheapest, listed = v.m, v.q or 0
    local s = hist[suffix] or ""
    local lastDay, lastMin, lastQ = s:match("(%d+):(%d+):(%d+)$")
    if tonumber(lastDay) == d then
      cheapest, listed = math.min(cheapest, tonumber(lastMin)), math.max(listed, tonumber(lastQ))
      s = s:gsub("[^|]*$", "")
    elseif s ~= "" then
      s = s .. "|"
    end
    s = s .. ("%.0f:%.0f:%.0f"):format(d, cheapest, listed)
    hist[suffix] = dropOld(s, d - KEEP_DAYS, function(day, m, q) addVersionWeek(id, suffix, day, m, q) end)
  end
end

-- Once a day, trim this market's history for every item, including ones no longer listed
-- (those are only trimmed here, as nothing records them). A little at a time, so login
-- doesn't hitch. Days past their daily limit fold into their week, as when a price is recorded.
local function trimCounts(s, cutoff)
  local out = {}
  for e in s:gmatch("[^|]+") do
    if (tonumber(e:match("^(%d+)")) or 0) > cutoff then out[#out + 1] = e end
  end
  return #out > 0 and table.concat(out, "|") or nil
end

-- Versions no longer listed: fold their old days and drop old weeks (TrimMarketHistory),
-- 200 items a frame like the rest, as there can be thousands (Codex review, November 7).
local function trimVersions(d, key)
  local hist, weekly = marketTable("historyVersions", key), marketTable("historyVersionsWeekly", key)
  local ids = {}
  for id in pairs(hist) do ids[#ids + 1] = id end
  for id in pairs(weekly) do if not hist[id] then ids[#ids + 1] = id end end
  local function trimOne(id)
    local byS = hist[id]
    if byS then
      for suffix, s in pairs(byS) do
        local kept = {}
        for e in s:gmatch("[^|]+") do
          local day, m, q = e:match("^(%d+):(%d+):(%d+)")
          if tonumber(day) and tonumber(day) <= d - KEEP_DAYS then
            addVersionWeek(id, suffix, tonumber(day), tonumber(m), tonumber(q), key)
          else
            kept[#kept + 1] = e
          end
        end
        byS[suffix] = #kept > 0 and table.concat(kept, "|") or nil
      end
      if not next(byS) then hist[id] = nil end
    end
    byS = weekly[id]
    if byS then
      for suffix, s in pairs(byS) do byS[suffix] = trimCounts(s, math.floor(d / 7) - WEEKLY_WEEKS) end
      if not next(byS) then weekly[id] = nil end
    end
  end
  local i = 0
  local function step()
    for _ = 1, 200 do
      i = i + 1
      local id = ids[i]
      if not id then return end
      local ok, err = pcall(trimOne, id)
      if not ok then ns:Debug("Version history trim skipped for", id, err) end
    end
    C_Timer.After(0, step)
  end
  step()
end

function ns:TrimMarketHistory()
  local d, key = today(), ns.MarketKey()
  trimVersions(d, key)
  local hist, weekly = marketTable("history", key), marketTable("historyWeekly", key)
  local qty, sold = marketTable("historyQty", key), marketTable("historySold2", key)
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
          if day and day <= d - KEEP_DAYS then
            addWeek(id, day, tonumber(m), tonumber(a), key)
            last = { tonumber(m), tonumber(a) }
          else
            kept[#kept + 1] = e
            last = nil
          end
        end
        -- An item no longer listed: its last day was never finished by a newer one, so
        -- it hasn't counted toward all time yet.
        if #kept == 0 and last then addAllTime(id, last[1], last[2], key) end
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

-- For price graphs (owner, November 7): every point saved for an item, or for one version
-- of it (suffix), oldest first. Each point is { day, cheapest, typical, listed, week }:
--   day      the local day (for a week, the week's first day)
--   typical  the typical price (nil for versions: full scans only keep their cheapest)
--   listed   how many were listed (the most that day; for a week, the average), or nil
--   week     true for a weekly point (older than the day-by-day history), with days = how many
-- days: only points from the last this many days (nil = all). Days without a scan are
-- simply missing, so a graph can show gaps.
function ns:PriceSeries(id, suffix, days)
  local d = today()
  local from = days and (d - days) or -math.huge
  local out, firstDaily = {}, math.huge
  local daily, weekly
  if suffix then
    daily = (marketTable("historyVersions")[id] or {})[suffix] or ""
    weekly = (marketTable("historyVersionsWeekly")[id] or {})[suffix] or ""
  else
    daily, weekly = marketTable("history")[id] or "", marketTable("historyWeekly")[id] or ""
  end
  local listedOn = {}
  if not suffix then
    for day, q in (marketTable("historyQty")[id] or ""):gmatch("(%d+):(%d+)") do listedOn[tonumber(day)] = tonumber(q) end
  end
  local days_ = {}
  for day, a, b in daily:gmatch("(%d+):(%d+):(%d+)") do
    day = tonumber(day)
    firstDaily = math.min(firstDaily, day)
    if day >= from then
      if suffix then days_[#days_ + 1] = { day = day, cheapest = tonumber(a), listed = tonumber(b) }
      else days_[#days_ + 1] = { day = day, cheapest = tonumber(a), typical = tonumber(b), listed = listedOn[day] } end
    end
  end
  for w, a, b, n in weekly:gmatch("(%d+):(%d+):(%d+):(%d+)") do
    local start = tonumber(w) * 7
    -- A week that's also partly day by day (folded up to the daily limit) would count twice.
    if start + 6 >= from and start < firstDaily then
      local p = { day = start, cheapest = tonumber(a), week = true, days = tonumber(n) }
      if suffix then p.listed = math.floor(tonumber(b) / math.max(tonumber(n), 1) + 0.5) else p.typical = tonumber(b) end
      out[#out + 1] = p
    end
  end
  for _, p in ipairs(days_) do out[#out + 1] = p end
  table.sort(out, function(x, y) return x.day < y.day end)
  return out
end

-- The versions of an item with any history, as { suffix, ... }, for picking one to graph.
function ns:PriceVersions(id)
  local seen, out = {}, {}
  for _, name in ipairs({ "historyVersions", "historyVersionsWeekly" }) do
    for suffix in pairs(marketTable(name)[id] or {}) do
      if not seen[suffix] then seen[suffix] = true; out[#out + 1] = suffix end
    end
  end
  table.sort(out)
  return out
end

-- Deal judging, usual prices and the tooltip see an item's history as they did before
-- graphs kept 90 days (Codex review, November 7: counting every day of 90 shifted a
-- falling item's usual price a hundredfold): the last DAILY_DAYS days one by one, older
-- days as one point per week, merged with the saved weeks.
-- Returns daily { { day, cheapest, typical } } and weekly { { week, cheapest, typical } }.
local function pricingPoints(id)
  local d = today()
  local daily, weeks, order = {}, {}, {}
  local function addToWeek(w, m, a, n)
    local p = weeks[w]
    if not p then p = { m = m, sum = 0, n = 0 }; weeks[w] = p; order[#order + 1] = w end
    p.m, p.sum, p.n = math.min(p.m, m), p.sum + a * n, p.n + n
  end
  for w, m, a, n in (marketTable("historyWeekly")[id] or ""):gmatch("(%d+):(%d+):(%d+):(%d+)") do
    addToWeek(tonumber(w), tonumber(m), tonumber(a), math.max(tonumber(n), 1))
  end
  for day, m, a in (marketTable("history")[id] or ""):gmatch("(%d+):(%d+):(%d+)") do
    day, m, a = tonumber(day), tonumber(m), tonumber(a)
    if day > d - DAILY_DAYS then daily[#daily + 1] = { day, m, a }
    else addToWeek(math.floor(day / 7), m, a, 1) end
  end
  table.sort(order)
  local weekly = {}
  for i, w in ipairs(order) do
    local p = weeks[w]
    weekly[i] = { w, p.m, math.floor(p.sum / p.n + 0.5) }
  end
  return daily, weekly
end
ns.PricingPoints = pricingPoints   -- (tests)

-- Returns a list of { day, cheapest, typical } for the last DAILY_DAYS days, oldest first.
function ns:PriceHistory(id)
  return (pricingPoints(id))
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
  local daily, weekly = pricingPoints(id)
  for _, p in ipairs(daily) do
    if p[1] < d and p[1] >= from then points[#points + 1] = p[3] end
  end
  for _, p in ipairs(weekly) do
    if (p[1] + 1) * 7 > from then points[#points + 1] = p[3] end
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
  local daily, weekly = pricingPoints(id)
  for _, p in ipairs(daily) do
    local day, m, a = p[1], p[2], p[3]
    if day < d and day >= from then
      typ[#typ + 1], low[#low + 1] = a, m
      first, days = first or day, days + 1
    end
  end
  for _, p in ipairs(weekly) do
    local w, m, a = p[1], p[2], p[3]
    if (w + 1) * 7 > from then
      typ[#typ + 1], low[#low + 1] = a, m
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
  ahDepositBack = "Auction deposits back",
  vendorSell = "Sold to vendors", vendorBuy = "Bought from vendors", repair = "Repairs",
  mailIn = "Mail received", mailOut = "Mail sent", tradeIn = "Trade received", tradeOut = "Trade given",
  loot = "Loot", quest = "Quests", training = "Training", flight = "Flights",
  otherIn = "Other income", otherOut = "Other spending",
}
ns.MONEY_LABELS = LABELS   -- (Sessions.lua: the tracker's hover lists money by source)
local INCOME = { ahSale = true, ahDepositBack = true, vendorSell = true, mailIn = true, tradeIn = true, loot = true, quest = true, otherIn = true }

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


function ns:PrintMoney()
  local lines, net = ns:MoneyToday()
  if not lines then ns:Print("No money in or out recorded today yet."); return end
  ns:Print("Money today for " .. (UnitName("player") or "?") .. ":")
  for _, line in ipairs(lines) do print("    " .. line) end
  print(("    Net: %s%s"):format(net >= 0 and "+" or "-", ns.Money(math.abs(net))))
end
