local _, ns = ...

---------------------------------------------------------------------------
-- History for the dashboard and deal alerts: gold over time, money in and out
-- by source, auction house sales and purchases, and daily prices.
---------------------------------------------------------------------------
local HOURLY_DAYS = 14      -- keep hourly gold this long, then one value per day
local LOG_SIZE = 500        -- auction house sales and purchases kept
local PENDING_SECONDS = 5   -- how long a hint (repair, posting fee, mail) waits for the gold change

local function today() return math.floor(time() / 86400) end
local function thisHour() return math.floor(time() / 3600) end

local function charTable(root)
  local key = ns.CharKey()
  root[key] = root[key] or {}
  return root[key]
end

---------------------------------------------------------------------------
-- Gold over time: gold[charKey][hour] = copper
---------------------------------------------------------------------------
local function snapshotGold()
  if not ns.db or not GetMoney then return end
  charTable(ns.db.gold)[thisHour()] = GetMoney()
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
local pending = {}       -- hints for the next gold change: { source, t, amount, item, log }
local lastMoney

local function hint(h)
  h.t = GetTime()
  pending[#pending + 1] = h
end

-- Take the hint that best matches a gold change: same amount first, otherwise the oldest.
local function takeHint(delta)
  local now, pick = GetTime(), nil
  for i = #pending, 1, -1 do
    if now - pending[i].t > PENDING_SECONDS then table.remove(pending, i) end
  end
  for i, h in ipairs(pending) do
    if h.amount and h.amount == math.abs(delta) then pick = i; break end
  end
  pick = pick or (#pending > 0 and 1)
  if pick then return table.remove(pending, pick) end
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

  local h = takeHint(delta)
  local source = h and h.source or sourceFor(delta)
  local day = charTable(ns.db.money)
  day[today()] = day[today()] or {}
  local totals = day[today()]
  totals[source] = (totals[source] or 0) + math.abs(delta)

  if h and h.log == "sale" then
    addLog(ns.db.sales, { t = time(), c = ns.CharKey(), n = h.item, a = math.abs(delta), cut = h.cut })
  elseif source == "ahBuy" then
    addLog(ns.db.purchases, { t = time(), c = ns.CharKey(), id = h and h.item, q = h and h.qty, a = math.abs(delta) })
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
  lastMoney = GetMoney()
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
  local invoiceType, itemName, _, _, _, _, consignment
  if GetInboxInvoiceInfo then invoiceType, itemName, _, _, _, _, consignment = GetInboxInvoiceInfo(index) end
  if invoiceType == "seller" then
    hint({ source = "ahSale", amount = money, item = itemName, cut = consignment, log = "sale" })
  else
    hint({ source = "mailIn", amount = money })
  end
end

ns:OnReady(function()
  hook(_G, "TakeInboxMoney", mailHint)
  hook(_G, "AutoLootMailItem", mailHint)
  hook(_G, "RepairAllItems", function() hint({ source = "repair" }) end)
  hook(C_AuctionHouse, "PostItem", function() hint({ source = "ahFee" }) end)
  hook(C_AuctionHouse, "PostCommodity", function() hint({ source = "ahFee" }) end)
  hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
    hint({ source = "ahBuy", item = itemID, qty = quantity })
  end)
  pruneGold()
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

function ns:PrintMoney()
  local totals = (ns.db.money[ns.CharKey()] or {})[today()]
  if not totals or not next(totals) then ns:Print("No money in or out recorded today yet."); return end
  ns:Print("Money today for " .. (UnitName("player") or "?") .. ":")
  local keys = {}
  for k in pairs(totals) do keys[#keys + 1] = k end
  table.sort(keys)
  local net = 0
  for _, k in ipairs(keys) do
    local sign = INCOME[k] and 1 or -1
    net = net + sign * totals[k]
    print(("    %s: %s%s"):format(LABELS[k] or k, sign > 0 and "+" or "-", ns.Money(totals[k])))
  end
  print(("    Net: %s%s"):format(net >= 0 and "+" or "-", ns.Money(math.abs(net))))
end
