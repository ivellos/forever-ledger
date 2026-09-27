local _, ns = ...

---------------------------------------------------------------------------
-- History for the dashboard and deal alerts: gold over time, money in and out
-- by source, auction house sales and purchases, and daily prices.
---------------------------------------------------------------------------
local HOURLY_DAYS = 14      -- keep hourly gold this long, then one value per day
local LOG_SIZE = 10000      -- auction house sales and purchases, and vendor buys and sells, kept
local LOG_DAYS = 365        -- and for at most this long
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

-- Older than HOURLY_DAYS: keep only the last value of each day.
local function pruneGold()
  local cutoff = thisHour() - HOURLY_DAYS * 24
  for _, hours in pairs(ns.db.gold) do
    local lastOfDay = {}
    for h in pairs(hours) do
      if h < cutoff then
        local d = math.floor(h / 24)
        if not lastOfDay[d] or h > lastOfDay[d] then lastOfDay[d] = h end
      end
    end
    for h in pairs(hours) do
      if h < cutoff and lastOfDay[math.floor(h / 24)] ~= h then hours[h] = nil end
    end
  end
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
    addLog(ns.db.purchases, { t = now, c = who, id = (h and h.item) or lastShownItem, q = (h and h.qty) or 1, a = math.abs(delta) })
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
  -- scans do too, so those are ignored.
  hook(C_AuctionHouse, "SendSearchQuery", function(itemKey)
    if itemKey and itemKey.itemID and not (ns.Scan and ns.Scan.active) then lastShownItem = itemKey.itemID end
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
  -- Drop log entries older than LOG_DAYS (the logs are oldest first).
  local cutoff = time() - LOG_DAYS * 86400
  for _, list in ipairs({ ns.db.sales, ns.db.purchases, ns.db.vendorLog }) do
    local drop = 0
    while list[drop + 1] and (list[drop + 1].t or 0) < cutoff do drop = drop + 1 end
    if drop > 0 then
      for i = 1, #list - drop do list[i] = list[i + drop] end
      for i = #list, #list - drop + 1, -1 do list[i] = nil end
    end
  end
end)

---------------------------------------------------------------------------
-- Price history, per market and item, as compact strings:
--   history[market][id]       = "day:cheapest:typical|..."        the last DAILY_DAYS days
--   historyWeekly[market][id] = "week:cheapest:typical:days|..."  older days, WEEKLY_WEEKS kept
--   historyAll[market][id]    = "lowest:typicalSum:days"          all time
-- A day keeps the lowest cheapest seen that day and the latest typical price.
---------------------------------------------------------------------------
local DAILY_DAYS = 30
local WEEKLY_WEEKS = 104

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
  all[id] = ("%d:%d:%d"):format(lo and math.min(lo, cheapest) or cheapest, sum + typical, n + 1)
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
    s = s:gsub("[^|]*$", "") .. ("%d:%d:%d:%d"):format(w, cheapest, typical, ln + 1)
  else
    s = (s ~= "" and (s .. "|") or "") .. ("%d:%d:%d:1"):format(w, cheapest, typical)
  end
  weekly[id] = dropOld(s, w - WEEKLY_WEEKS)
end

function ns:RecordPriceHistory(id, cheapest, typical)
  if not ns.db or not cheapest then return end
  typical = typical or cheapest
  local hist = marketTable("history")
  local d = today()
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
  s = s .. ("%d:%d:%d"):format(d, cheapest, typical)
  hist[id] = dropOld(s, d - DAILY_DAYS, function(day, m, a) addWeek(id, day, m, a) end)
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

-- The usual price over a period: the median of the daily (and weekly, for older
-- times) typical prices, leaving today out. Returns the price and how many points it used.
function ns:UsualPrice(id, window)
  local d = today()
  local from = d - (ns.PRICE_WINDOWS[window or "all"] or math.huge)
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
