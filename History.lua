local _, ns = ...

---------------------------------------------------------------------------
-- History for the dashboard and deal alerts: gold over time, money in and out
-- by source, auction house sales and purchases, and daily prices.
---------------------------------------------------------------------------
local HOURLY_DAYS = 14      -- keep hourly gold this long, then one value per day
local PRICE_DAYS = 60       -- days of price history per item
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
local open = {}          -- which windows are open: merchant, ah, mail, trade, loot, quest, trainer, taxi
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

local function sourceFor(delta)
  local gain = delta > 0
  if open.merchant then return gain and "vendorSell" or "vendorBuy" end
  if open.ah then return gain and "otherIn" or "ahBuy" end
  if open.mail then return gain and "mailIn" or "mailOut" end
  if open.trade then return gain and "tradeIn" or "tradeOut" end
  if open.loot and gain then return "loot" end
  if open.quest and gain then return "quest" end
  if open.trainer and not gain then return "training" end
  if open.taxi and not gain then return "flight" end
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
  ns:On(hideEvent, function() open[name] = nil end)
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
-- Price history: history[marketKey][itemID] = "day:cheapest:typical|day:..."
-- One entry per day (lowest cheapest seen that day, latest typical), PRICE_DAYS kept.
---------------------------------------------------------------------------
function ns:RecordPriceHistory(id, cheapest, typical)
  if not ns.db or not cheapest then return end
  local key = ns.MarketKey()
  ns.db.history[key] = ns.db.history[key] or {}
  local hist = ns.db.history[key]
  local d = today()
  local s = hist[id] or ""
  local lastDay, lastMin = s:match("(%d+):(%d+):%d+$")
  if tonumber(lastDay) == d then
    cheapest = math.min(cheapest, tonumber(lastMin))
    s = s:gsub("[^|]*$", "")
  elseif s ~= "" then
    s = s .. "|"
  end
  s = s .. ("%d:%d:%d"):format(d, cheapest, typical or cheapest)
  -- Drop entries older than PRICE_DAYS.
  local cutoff = d - PRICE_DAYS
  while true do
    local first = tonumber(s:match("^(%d+):"))
    if not first or first > cutoff or not s:find("|", 1, true) then break end
    s = s:gsub("^[^|]*|", "")
  end
  hist[id] = s
end

-- Returns a list of { day, cheapest, typical }, oldest first.
function ns:PriceHistory(id)
  local hist = ns.db.history[ns.MarketKey()]
  local out = {}
  for d, m, a in ((hist and hist[id]) or ""):gmatch("(%d+):(%d+):(%d+)") do
    out[#out + 1] = { tonumber(d), tonumber(m), tonumber(a) }
  end
  return out
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
