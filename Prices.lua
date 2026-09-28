local _, ns = ...

-- Materials always included in scans, even before any recipes are captured.
local DEFAULT_WATCH = {
  2589, 2996, 2592, 2997, 4306, 4305, 4338, 4339, 14047, 14048,  -- cloth and bolts
  2318,                                                          -- Light Leather
  10940, 11083, 11137, 11176, 16204,                             -- dusts
  10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203, -- essences
  10978, 11084, 11177, 11178, 14343, 14344, 20725,               -- shards and Nexus Crystal
  20744, 247786, 11287, 11288,                                   -- Minor Wizard Oil, Mote of Magic, wands
}
ns.DEFAULT_WATCH = DEFAULT_WATCH

-- What vendors charge you. Replaced automatically whenever you open a vendor that sells the item.
local VENDOR_DEFAULTS = {
  [4470] = 38,     -- Simple Wood
  [2320] = 10,     -- Coarse Thread
  [2321] = 100,    -- Fine Thread
  [4291] = 500,    -- Silken Thread
  [14341] = 5000,  -- Rune Thread
  [2324] = 25,     -- Bleach
  [2604] = 50,     -- Red Dye
  [6260] = 50,     -- Blue Dye
  [6217] = 124,    -- Copper Rod
}

ns:OnReady(function()
  for id, p in pairs(VENDOR_DEFAULTS) do
    if not ns.db.vendorBuy[id] then ns.db.vendorBuy[id] = { p = p, t = 0, src = "default" } end
  end
  -- Ask the game for vendor items' names now, so lists show names instead of "item 2321".
  if C_Item and C_Item.RequestLoadItemDataByID then
    for id in pairs(ns.db.vendorBuy) do pcall(C_Item.RequestLoadItemDataByID, id) end
  end
end)

---------------------------------------------------------------------------
-- Vendor sell prices (what a vendor pays you), read from the game
---------------------------------------------------------------------------
local function getItemInfo(id)
  if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(id) end
  if GetItemInfo then return GetItemInfo(id) end
end
ns.GetItemInfo = getItemInfo

-- Item names, remembered in saved data once the game has given them. The game keeps
-- only so many item details in memory, and asking for hundreds (the Disenchant finder)
-- pushed out names already shown, so lists flickered between "item 727" and the name.
ns.nameWanted = {}      -- itemID = true while a name we showed as "item N" is on its way
function ns.ItemName(id)
  if not id then return "?" end
  local names = ns.db and ns.db.itemNames
  local name = names and names[id]
  if name then return name end
  name = getItemInfo(id)
  if name then
    if names then names[id] = name end
    return name
  end
  if not ns.nameWanted[id] then
    ns.nameWanted[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  end
  return "item " .. id
end

ns:On("GET_ITEM_INFO_RECEIVED", function(id, success)
  if id and ns.nameWanted[id] and success then
    local name = getItemInfo(id)
    if name and ns.db then ns.db.itemNames[id] = name end
  end
end)

local waiting = {}
function ns:RememberItem(id)
  if not id or not ns.db or ns.db.vendorSell[id] ~= nil then return end
  local name, _, _, _, _, _, _, _, _, _, sell = getItemInfo(id)
  if name then
    ns.db.vendorSell[id] = sell or 0
    if ns.InvalidateValues then ns:InvalidateValues() end
  elseif not waiting[id] then
    waiting[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  end
end

ns:On("GET_ITEM_INFO_RECEIVED", function(id, success)
  if id and waiting[id] then
    waiting[id] = nil
    if success then ns:RememberItem(id) end
  end
end)

function ns:GetSellPrice(id)
  if ns.db.vendorSell[id] == nil then ns:RememberItem(id) end
  return ns.db.vendorSell[id]
end

function ns:GetVendorBuyPrice(id)
  local rec = ns.db.vendorBuy[id]
  return rec and rec.p, rec
end

---------------------------------------------------------------------------
-- Vendor buy prices (what a vendor charges you), captured from merchant windows
---------------------------------------------------------------------------
local function captureMerchant()
  if not GetMerchantNumItems then return end
  local n, got = GetMerchantNumItems() or 0, 0
  for i = 1, n do
    local id = GetMerchantItemID and GetMerchantItemID(i)
    local price, qty, avail, ext
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local info = C_MerchantFrame.GetItemInfo(i)
      if info then price, qty, avail, ext = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
    elseif GetMerchantItemInfo then
      local _, _, p, q, a, _, _, e = GetMerchantItemInfo(i)
      price, qty, avail, ext = p, q, a, e
    end
    if id and price and price > 0 and not ext then
      ns.db.vendorBuy[id] = {
        p = math.floor(price / math.max(qty or 1, 1) + 0.5),
        t = time(),
        src = "merchant",
        lim = (avail and avail >= 0) or nil,
      }
      ns:RememberItem(id)
      got = got + 1
    end
  end
  if got > 0 and ns.InvalidateValues then ns:InvalidateValues() end
  if got > 0 and ns.SyncSoon then ns:SyncSoon() end
  ns:Debug("Vendor prices captured:", got)
end
ns:On("MERCHANT_SHOW", function() C_Timer.After(0.3, captureMerchant) end)
ns:On("MERCHANT_UPDATE", captureMerchant)

---------------------------------------------------------------------------
-- Auction house prices
---------------------------------------------------------------------------
local ahOpen = false
function ns:IsAHOpen() return ahOpen end

function ns:WatchList()
  local set, list = {}, {}
  local function add(id)
    if id and not set[id] then set[id] = true; list[#list + 1] = id end
  end
  for _, id in ipairs(DEFAULT_WATCH) do add(id) end
  for id in pairs(ns.db.settings.watch) do add(id) end
  for _, c in pairs(ns.db.chars) do
    for _, p in pairs(c.profs or {}) do
      for _, rec in pairs(p.recipes or {}) do
        add(rec.out)
        for _, r in ipairs(rec.r or {}) do add(r[1]) end
      end
    end
  end
  return list
end

local LADDER_LEVELS = 20

-- How many are listed at or below a price, from the last scan's price ladder.
-- Older scans without a ladder give the total listed. nil if never scanned.
function ns:ListedAtOrBelow(id, price)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not rec or rec.none then return rec and 0 or nil end
  if not rec.l then return rec.q end
  local n = 0
  for p, c in rec.l:gmatch("(%d+):(%d+)") do
    if tonumber(p) > price then break end
    n = tonumber(c)
  end
  return n
end

-- The listings at or below a price: how many, and their average price. Uses the price
-- ladder (the ladder's counts are running totals). Without a ladder, the cheapest price
-- if it qualifies. Returns 0 when none qualify, nil if never scanned.
function ns:CheapListings(id, price)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not rec then return nil end
  if rec.none or not rec.m then return 0 end
  if not rec.l then
    if rec.m <= price then return rec.q or 1, rec.m end
    return 0
  end
  local n, cost, prev = 0, 0, 0
  for p, c in rec.l:gmatch("(%d+):(%d+)") do
    p, c = tonumber(p), tonumber(c)
    if p > price then break end
    cost = cost + p * (c - prev)
    n, prev = c, c
  end
  return n, n > 0 and cost / n or nil
end

-- units: list of { unitPrice, quantity }
local function record(id, units, src)
  if ns.InvalidateValues then ns:InvalidateValues() end
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  if #units == 0 then
    ns.db.prices[key][id] = { t = time(), src = src or "scan", none = true }
    return
  end
  table.sort(units, function(a, b) return a[1] < b[1] end)
  local total, qty, want, listed = 0, 0, 20, 0
  for _, u in ipairs(units) do
    listed = listed + u[2]
    if qty < want then
      local take = math.min(u[2], want - qty)
      total = total + u[1] * take
      qty = qty + take
    end
  end
  -- Price ladder: how many are listed at or below each of the cheapest price levels,
  -- as "price:count,price:count" (count is running total). Lets "runs" count only
  -- listings cheap enough to be worth buying.
  local ladder, cum, lastPrice = {}, 0, nil
  for _, u in ipairs(units) do
    cum = cum + u[2]
    if u[1] == lastPrice then
      ladder[#ladder] = math.floor(u[1]) .. ":" .. cum
    elseif #ladder < LADDER_LEVELS then
      ladder[#ladder + 1] = math.floor(u[1]) .. ":" .. cum
      lastPrice = u[1]
    else
      break
    end
  end
  local rec = {
    m = units[1][1],
    a = math.floor(total / math.max(qty, 1) + 0.5),
    q = listed,
    l = table.concat(ladder, ","),
    t = time(),
    src = src or "scan",
  }
  ns.db.prices[key][id] = rec
  -- History is a bonus: a problem there must never stop a scan from saving prices.
  if ns.RecordPriceHistory then
    local ok, err = pcall(ns.RecordPriceHistory, ns, id, rec.m, rec.a)
    if not ok then ns:Debug("Price history skipped for", id, err) end
  end
end
ns.RecordPrice = record

local Scan = { queue = {}, active = false, done = 0, total = 0 }
ns.Scan = Scan

-- "45s" or "2m 5s" since the scan started.
local function took()
  local s = math.floor(GetTime() - (Scan.started or GetTime()) + 0.5)
  if s < 60 then return s .. "s" end
  return ("%dm %ds"):format(math.floor(s / 60), s % 60)
end

local SORTS
local function sorts()
  if not SORTS and Enum and Enum.AuctionHouseSortOrder then
    SORTS = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  end
  return SORTS or {}
end

local FULL_COOLDOWN = 15 * 60   -- Blizzard allows a full scan about every 15 minutes

-- Seconds until a full scan is allowed again (0 if it is now).
function Scan:FullWait()
  if not C_AuctionHouse.ReplicateItems then return math.huge end
  return math.max(0, (ns.db.lastFullScan or 0) + FULL_COOLDOWN - time())
end

-- mode: "auto" (full scan if allowed, otherwise materials), "full" or "watch" (materials only).
function Scan:Start(mode)
  if not C_AuctionHouse then ns:Print("This client has no auction house scanning."); return end
  if not ahOpen then ns:Print("Open the auction house first."); return end
  if self.active then ns:Print("A scan is already running. Type /fl stop to cancel it."); return end
  self.started = GetTime()
  if mode == "full" then return self:StartFull(false) end
  if mode == "auto" then
    local wait = self:FullWait()
    if wait == 0 then return self:StartFull(true) end
    if wait < math.huge then
      ns:Print(("A full scan is possible again in %d min. Scanning your materials instead."):format(math.ceil(wait / 60)))
    end
  end
  self:StartWatch()
end

function Scan:StartWatch()
  self.queue = ns:WatchList()
  self.items, self.retry, self.retrying = #self.queue, {}, false
  self.total, self.done, self.active, self.pending = #self.queue, 0, true, nil
  ns:Print(("Scanning %d items. Keep the auction house open."):format(self.total))
  self:Next()
end

function Scan:Next()
  if not self.active then return end
  if #self.queue == 0 then
    -- Give items that got no reply one more try at the end.
    if #self.retry > 0 and not self.retrying then
      ns:Debug("Trying again:", #self.retry, "items")
      self.queue, self.retry, self.retrying = self.retry, {}, true
      self.total = self.total + #self.queue
    else
      self:Stop()
      return
    end
  end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    self.waiting = true
    C_Timer.After(0.5, function()
      if self.waiting then self.waiting = false; self:Next() end
    end)
    return
  end
  local id = table.remove(self.queue, 1)
  self.pending = id
  self.token = (self.token or 0) + 1
  local tok = self.token
  local ok, err = pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(id), sorts(), false)
  if not ok then
    ns:Debug("Search failed for", id, err)
    self:Finish(id, nil)
    return
  end
  -- Items with nothing listed may never get a reply, so don't wait long.
  C_Timer.After(3, function()
    if self.active and self.token == tok and self.pending == id then
      local units = self:ReadWaiting(id)
      ns:Debug(units and "Read waiting results for item" or "No reply for item", id)
      if not units and not self.retrying then table.insert(self.retry, id) end
      self:Finish(id, units)
    end
  end)
end

function Scan:Finish(id, units)
  if units then record(id, units, "scan") end
  self.pending = nil
  self.done = self.done + 1
  ns:UpdateScanStatus(self.done, self.total)
  C_Timer.After(0.1, function() self:Next() end)
end

function Scan:Stop(reason)
  local was = self.active
  self.active, self.pending, self.full, self.waiting = false, nil, false, false
  self.queue = {}
  if was then ns:Print(reason or ("Scan finished: %d items checked in %s."):format(self.items or self.done or 0, took())) end
  if was and not reason and ns.CheckDeals then C_Timer.After(0.5, function() ns:CheckDeals() end) end
  if was and ns.SyncSoon then ns:SyncSoon() end
  ns:RefreshUI()
end

ns:On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
  if Scan.waiting then Scan.waiting = false; Scan:Next() end
end)

-- Read search results as { unit price, quantity } lists.
local function commodityUnits(itemID)
  local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
  local units = {}
  for i = 1, n do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice then units[#units + 1] = { r.unitPrice, r.quantity or 1 } end
  end
  return units, n
end

local function itemUnits(itemKey)
  local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
  local units = {}
  for i = 1, n do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    -- buyoutAmount is already per item in Forever (beta test: dividing by quantity
    -- made Linen Reagent Bags 19c instead of 13s). The full scan's buyout is per listing.
    if r and r.buyoutAmount and r.buyoutAmount > 0 then
      units[#units + 1] = { r.buyoutAmount, math.max(r.quantity or 1, 1) }
    end
  end
  return units, n
end

-- Sometimes the auction house already has results (for example right after a full
-- scan) and never sends the "updated" event. Read whatever is there.
function Scan:ReadWaiting(id)
  local ok, units, n = pcall(commodityUnits, id)
  if ok and n > 0 then return units end
  ok, units, n = pcall(itemUnits, C_AuctionHouse.MakeItemKey(id))
  if ok and n > 0 then return units end
end

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
  if not Scan.active or Scan.pending ~= itemID then return end
  Scan:Finish(itemID, (commodityUnits(itemID)))
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  local id = itemKey and itemKey.itemID
  if not Scan.active or Scan.pending ~= id then return end
  local units, n = itemUnits(itemKey)
  if n > 0 then ns:Debug("Item search sample", id, n, units[1] and units[1][1]) end
  Scan:Finish(id, units)
end)

-- Full scan of every listing. Blizzard only allows this about every 15 minutes.
-- fallback: scan materials instead if the auction house doesn't send the full scan.
local FULL_TIMEOUT = 30
function Scan:StartFull(fallback)
  if not C_AuctionHouse.ReplicateItems then
    ns:Print("Full scans aren't available in this client. Use /fl scan materials instead.")
    return
  end
  self.active, self.full, self.done, self.total = true, true, 0, 0
  self.fullToken = (self.fullToken or 0) + 1
  local tok = self.fullToken
  ns:Print("Requesting a full scan of the auction house. This usually takes a few seconds.")
  C_AuctionHouse.ReplicateItems()
  -- Nothing comes back if Blizzard's 15-minute limit hasn't passed (for example after
  -- a full scan on another character).
  C_Timer.After(FULL_TIMEOUT, function()
    if not (self.active and self.full and self.fullToken == tok) then return end
    self.active, self.full = false, false
    if fallback then
      ns:Print("The auction house didn't send a full scan yet. Scanning your materials instead.")
      self:StartWatch()
    else
      ns:Print("The auction house didn't send a full scan. It allows one about every 15 minutes, so try again later, or use /fl scan materials.")
    end
  end)
end

-- The results arrive for every addon, so a full scan started by another addon
-- (Auctionator, TSM...) is read too. They share Blizzard's 15-minute limit.
local readingFull, lastFullRead = false, 0
ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
  local mine = Scan.active and Scan.full
  if readingFull and GetTime() - lastFullRead < 120 then return end   -- (unstick after an error)
  -- Another addon's scan: once per scan (ignore repeat events for a minute).
  if not mine and GetTime() - lastFullRead < 60 then return end
  readingFull, lastFullRead = true, GetTime()
  if mine then Scan.full = false end
  local started = mine and Scan.started or GetTime()
  local n = C_AuctionHouse.GetNumReplicateItems() or 0
  if not mine then ns:Debug("Reading another addon's full scan:", n, "listings") end
  local byItem, i = {}, 0
  local function chunk()
    local stop = math.min(i + 2000, n)
    for idx = i, stop - 1 do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
      if itemID and buyout and buyout > 0 then
        count = math.max(count or 1, 1)
        local t = byItem[itemID]
        if not t then t = {}; byItem[itemID] = t end
        t[#t + 1] = { math.floor(buyout / count + 0.5), count }
      end
    end
    i = stop
    if i < n then
      ns:UpdateScanStatus(i, n)
      C_Timer.After(0, chunk)
    else
      local items = 0
      for id, units in pairs(byItem) do record(id, units, "full"); items = items + 1 end
      ns.db.lastFullScan = time()
      readingFull = false
      if not ahOpen then ns.neutralAH = nil end
      if mine then Scan.active = false end
      ns:UpdateScanStatus(n, n)
      local secs = math.floor(GetTime() - started + 0.5)
      if mine then
        ns:Print(("Full scan done: %d listings across %d items in %s."):format(n, items, took()))
      else
        ns:Print(("Another addon ran a full scan; Forever Ledger read it too: %d listings across %d items in %ds."):format(n, items, secs))
      end
      if ns.CheckDeals then C_Timer.After(0.5, function() ns:CheckDeals() end) end
      if ns.SyncSoon then ns:SyncSoon() end
      ns:RefreshUI()
    end
  end
  chunk()
end)

ns:On("AUCTION_HOUSE_SHOW", function()
  ahOpen = true
  local ok, neutral = pcall(ns.IsNeutralAuctioneer)
  ns.neutralAH = ok and neutral or nil
  -- For checking which auction houses are neutral (/fl debug).
  ns:Debug("Auction house:", GetSubZoneText() or "?", "/", GetZoneText() or "?", "auctioneer faction:",
    tostring(UnitFactionGroup("npc")), ns.neutralAH and "neutral" or "faction")
  if ns.neutralAH then
    ns:Print("Neutral auction house: prices seen here are kept separate from your faction's.")
  end
  if ns.OnAHShow then ns:OnAHShow() end
end)
ns:On("AUCTION_HOUSE_CLOSED", function()
  ahOpen = false
  -- A full scan still being read keeps its market until it's saved.
  if not readingFull then ns.neutralAH = nil end
  if Scan.active then Scan:Stop("Auction house closed, so the scan stopped.") end
  ns:RefreshUI()   -- grey out the scan buttons
end)

---------------------------------------------------------------------------
-- Prices from other auction addons
---------------------------------------------------------------------------
local function auctionatorPrice(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if api and api.GetAuctionPriceByItemID then
    local ok, v = pcall(api.GetAuctionPriceByItemID, "ForeverLedger", id)
    if ok then return v end
  end
end
local function tsmPrice(id)
  if TSM_API and TSM_API.GetCustomPriceValue then
    local ok, v = pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", "i:" .. id)
    if ok then return v end
  end
end
local function auctioneerPrice(id)
  local api = AucAdvanced and AucAdvanced.API
  if api and api.GetMarketValue then
    local _, link = getItemInfo(id)
    if link then
      local ok, v = pcall(api.GetMarketValue, link)
      if ok then return v end
    end
  end
end
ns.EXTERNAL = {
  { name = "Auctionator", fn = auctionatorPrice },
  { name = "TSM", fn = tsmPrice },
  { name = "Auctioneer", fn = auctioneerPrice },
}

function ns:ExternalSources()
  local found = {}
  if Auctionator and Auctionator.API then found[#found + 1] = "Auctionator" end
  if TSM_API then found[#found + 1] = "TSM" end
  if AucAdvanced then found[#found + 1] = "Auctioneer" end
  return found
end

-- Returns price, source name, time scanned, raw record
function ns:GetPrice(id)
  if not id or not ns.db then return end
  local market = ns.db.prices[ns.MarketKey()]
  local rec = market and market[id]
  local src = ns.db.settings.source
  local maxAge = (ns.db.settings.maxAgeHours or 12) * 3600
  local fresh = rec and rec.m and (time() - (rec.t or 0)) <= maxAge
  if rec and rec.m and (src == "own" or (src == "auto" and fresh)) then
    local label = rec.src == "full" and "full scan" or rec.src or "scan"
    return rec.a or rec.m, label, rec.t, rec
  end
  if src ~= "own" then
    for _, e in ipairs(ns.EXTERNAL) do
      if src == "auto" or src == e.name then
        local v = e.fn(id)
        if v and v > 0 then return v, e.name, nil, rec end
      end
    end
  end
  if rec and rec.m then return rec.a or rec.m, "scan", rec.t, rec end
  return nil, nil, rec and rec.t, rec
end

-- Copy prices from Auctionator/TSM/Auctioneer into the ledger so they're included in exports.
function ns:PullExternal()
  local sources = ns:ExternalSources()
  if #sources == 0 then ns:Print("No supported auction addon found (Auctionator, TSM or Auctioneer)."); return end
  local key, n = ns.MarketKey(), 0
  ns.db.prices[key] = ns.db.prices[key] or {}
  for _, id in ipairs(ns:WatchList()) do
    for _, e in ipairs(ns.EXTERNAL) do
      local v = e.fn(id)
      if v and v > 0 then
        local mine = ns.db.prices[key][id]
        if not mine or mine.src ~= "scan" or (time() - (mine.t or 0)) > 3600 then
          ns.db.prices[key][id] = { m = v, a = v, t = time(), src = e.name }
          n = n + 1
        end
        break
      end
    end
  end
  ns:Print(("Copied %d prices from %s."):format(n, table.concat(sources, ", ")))
  ns:RefreshUI()
end
