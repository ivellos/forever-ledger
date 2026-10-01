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
-- Item details, remembered for the session once the game has given them. The game keeps
-- only so many in memory; working out every shuffle asks about thousands of items, so
-- half of them were forgotten each time, and on the next refresh the other half. Items
-- the game had forgotten gave no disenchant value, so two groups of disenchant shuffles
-- took turns disappearing on every refresh (owner's log, September 30).
local infoCache = {}
local rawGetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local function getItemInfo(id)
  if not id or not rawGetItemInfo then return end
  local hit = infoCache[id]
  if hit then return unpack(hit, 1, hit.n) end
  local function keep(...)
    if (...) ~= nil then infoCache[id] = { n = select("#", ...), ... } end
    return ...
  end
  return keep(rawGetItemInfo(id))
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

-- What vendors pay is remembered per item, but patches change it (October 1 build:
-- "All crafted common and uncommon quality wands now sell at vendors for 1 copper",
-- was 15s for a Greater Magic Wand). When the game build changes, forget the
-- remembered prices so they're read again from the game's item data. This is a cache
-- of game data, not the player's own records, so clearing it loses nothing.
ns:OnReady(function()
  local _, build = GetBuildInfo()
  if not build then return end
  if ns.db.vendorSellBuild and ns.db.vendorSellBuild ~= build then
    wipe(ns.db.vendorSell)
    if ns.InvalidateValues then ns:InvalidateValues(true) end
    ns:Debug("New game build", build, "(was", ns.db.vendorSellBuild .. "): vendor prices will be read again.")
  end
  ns.db.vendorSellBuild = build
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

-- The random-stats version in an item link ("of the Eagle"), or nil. Classic kept it in
-- the 7th field; Forever uses modern links, where it's a bonus ID (beta, September 30:
-- "Simple Britches of the Whale" = item:9747::::::::20:1482::1:1:12719:1:28:7000, field 13
-- is how many bonus IDs follow, here one, 12719). With several, the highest is used.
function ns.SuffixFromLink(link)
  local s = type(link) == "string" and link:match("item:([%-%d:]+)")
  if not s then return end
  local f = {}
  for v in (s .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
  local suffix = tonumber(f[7])
  if suffix and suffix ~= 0 then return suffix end
  local n = tonumber(f[13])
  if n and n > 0 then
    local best
    for i = 14, 13 + n do
      local b = tonumber(f[i])
      if b and (not best or b > best) then best = b end
    end
    return best
  end
end

-- Every bonus ID in a modern item link (field 13 says how many follow), as a list.
function ns.LinkBonusIDs(link)
  local s = type(link) == "string" and link:match("item:([%-%d:]+)")
  local out = {}
  if not s then return out end
  local f = {}
  for v in (s .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
  for i = 14, 13 + (tonumber(f[13]) or 0) do
    local b = tonumber(f[i])
    if b then out[#out + 1] = b end
  end
  return out
end

-- The version name for a version number ("of the Whale"), from what full scans saw.
local versionNames
function ns:VersionName(suffix)
  if not versionNames then
    versionNames = {}
    for name, s in pairs(ns.db.suffixNames or {}) do versionNames[s] = name end
  end
  return versionNames[suffix]
end
function ns:ForgetVersionNames() versionNames = nil end

-- The version of a hovered item: a bonus ID in its link that is a known version (one
-- full scans have seen, on this item or any other), or Classic's suffix field. nil for
-- an auction house group, whose link has a general bonus ID (3524) instead.
function ns:VersionOfLink(id, link)
  if type(link) ~= "string" then return end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  for _, b in ipairs(ns.LinkBonusIDs(link)) do
    if ns:VersionName(b) or (rec and rec.sx and (";" .. rec.sx):find(";" .. b .. ":", 1, true)) then return b end
  end
  local s = link:match("item:([%-%d:]+)")
  local f = {}
  for v in ((s or "") .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
  local classic = tonumber(f[7])
  if classic and classic ~= 0 then return classic end
end

-- Cheapest price and count for one version of gear with random stats, from the last
-- full scan. Returns nil if no suffix data (no full scan yet), 0 if none were listed.
function ns:SuffixPrice(id, suffix)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not (rec and rec.sx and suffix) then return end
  for s, m, q in rec.sx:gmatch("(%-?%d+):(%d+):(%d+)") do
    if tonumber(s) == suffix then return tonumber(m), tonumber(q), rec.sxt or rec.t end
  end
  return 0, 0, rec.sxt or rec.t
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

-- You bought `qty` of an item at `each` (or less) per unit: take them off its saved price
-- ladder, so flips and deals drop without waiting for the next full scan. Takes from
-- the dearest level at or below what you paid (what you most likely bought).
function ns:RemoveBought(id, qty, each)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not (rec and rec.l and not rec.none) then return end
  local levels, prev = {}, 0
  for p, c in rec.l:gmatch("(%d+):(%d+)") do
    p, c = tonumber(p), tonumber(c)
    levels[#levels + 1] = { p = p, n = c - prev }
    prev = c
  end
  local left = qty
  for i = #levels, 1, -1 do
    local lv = levels[i]
    if left > 0 and lv.p <= each + 1 then
      local take = math.min(left, lv.n)
      lv.n, left = lv.n - take, left - take
    end
  end
  if left == qty then return end   -- nothing at that price was listed
  local out, cum = {}, 0
  for _, lv in ipairs(levels) do
    if lv.n > 0 then
      cum = cum + lv.n
      out[#out + 1] = lv.p .. ":" .. cum
    end
  end
  rec.q = math.max(0, (rec.q or cum) - (qty - left))
  if #out == 0 then
    -- Nothing left in the ladder (dearer listings may remain past its 20 levels):
    -- an empty ladder counts no cheap listings, and the cheapest price stays as a guide.
    rec.l = ""
    if rec.q == 0 then rec.none = true end
  else
    rec.l = table.concat(out, ",")
    rec.m = tonumber(out[1]:match("^(%d+)"))
  end
  ns:Debug("Took", qty - left, "bought", ns.ItemName(id) or id, "off the saved listings.")
  if ns.CheckFlip then ns:CheckFlip(id) end
  if ns.InvalidateValues then ns:InvalidateValues(true) end
  if ns.RefreshFlipsIfShown then C_Timer.After(0.5, function() ns:RefreshFlipsIfShown() end) end
end

-- units: list of { unitPrice, quantity }
local function record(id, units, src)
  if ns.InvalidateValues then ns:InvalidateValues() end
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  if #units == 0 then
    ns.db.prices[key][id] = { t = time(), src = src or "scan", none = true }
    if ns.CheckFlip then pcall(ns.CheckFlip, ns, id) end   -- forgets a flip that sold out
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
  -- Versions of gear with random stats: "suffix:cheapest:listed;..." (full scans only).
  local bySuffix, sx = {}, {}
  for _, u in ipairs(units) do
    if u[3] then
      local s = bySuffix[u[3]]
      if not s then s = { m = u[1], q = 0 }; bySuffix[u[3]] = s end
      s.q = s.q + u[2]
    end
  end
  for suffix, s in pairs(bySuffix) do sx[#sx + 1] = ("%d:%d:%d"):format(suffix, s.m, s.q) end
  -- Only full scans see versions. A search or quick check keeps the last full scan's
  -- version prices (sxt says when they're from) instead of wiping them.
  local old, sxt = ns.db.prices[key][id], nil
  if #sx > 0 then
    sxt = time()
  elseif old and old.sx then
    sx, sxt = { old.sx }, old.sxt or old.t
  end
  local rec = {
    m = units[1][1],
    a = math.floor(total / math.max(qty, 1) + 0.5),
    q = listed,
    l = table.concat(ladder, ","),
    t = time(),
    src = src or "scan",
    sx = #sx > 0 and table.concat(sx, ";") or nil,
    sxt = sxt,
  }
  ns.db.prices[key][id] = rec
  -- A watch pass or your own search: alert straight away if this made a new vendor
  -- flip (full scans check everything at once when they finish).
  if src ~= "full" and ns.CheckFlip then
    local ok, err = pcall(ns.CheckFlip, ns, id)
    if not ok then ns:Debug("Flip check failed for", id, err) end
  end
  -- History is a bonus: a problem there must never stop a scan from saving prices.
  if ns.RecordPriceHistory then
    local ok, err = pcall(ns.RecordPriceHistory, ns, id, rec.m, rec.a, rec.q)
    if not ok then ns:Debug("Price history skipped for", id, err) end
  end
end
ns.RecordPrice = record

---------------------------------------------------------------------------
-- Sell speed: the auction house never says what sold, but between two full scans a
-- few hours apart, reasonably priced listings that vanished were mostly bought (some
-- expired or were cancelled). Each full scan notes, per item, how many units were
-- listed at up to 1.25 x its typical price; the next full scan counts how many of
-- those are gone. New listings in between hide some sales, so it's a low estimate.
-- History.lua keeps the totals per day (RecordSold, SellRate).
-- Best effort (owner, September 30: most players won't watch the AH all day): the last
-- full scan is saved (soldSnap), so the first scan of a session compares with the last
-- one before it, up to 12 hours apart. Pairs more than 30 minutes apart are "rough":
-- expired listings count as gone too. Only the flip watch's scans every 15 minutes give
-- a fair picture; the Deals tab says which.
---------------------------------------------------------------------------
local SOLD_MAX_GAP = 12 * 3600  -- scans further apart than this aren't compared
local SOLD_CLOSE = 30 * 60      -- pairs this close are "watched", further apart "rough"
local SOLD_PRICE = 1.25         -- "reasonably priced": up to this times the typical price
local lastSnap                  -- { t, market, items = { [id] = { price, count } } }
local olderSnap                 -- the one before lastSnap, for the "came back" check (memory only)

-- The saved copy of the last full scan's counts: items[id] = "price:count".
local function loadSnap()
  local s = ns.db.soldSnap
  if not (s and s.t and s.items) then return end
  local items = {}
  for id, v in pairs(s.items) do
    local p, n = v:match("^(%d+):(%d+)$")
    if p then items[id] = { tonumber(p), tonumber(n) } end
  end
  return { t = s.t, market = s.market, items = items }
end

local function saveSnap(snap)
  local items = {}
  for id, v in pairs(snap.items) do
    if v[2] > 0 then items[id] = ("%d:%d"):format(v[1], v[2]) end
  end
  ns.db.soldSnap = { t = snap.t, market = snap.market, items = items }
end

local function countUpTo(units, price)
  local n = 0
  for _, u in ipairs(units) do if u[1] <= price then n = n + u[2] end end
  return n
end

-- Collects one full scan's items and compares them with the previous full scan.
local function soldTracker()
  local now, market = time(), ns.MarketKey()
  local prev = lastSnap or loadSnap()
  local compare = prev and prev.market == market and now - prev.t >= 60 and now - prev.t <= SOLD_MAX_GAP
  local close = compare and now - prev.t <= SOLD_CLOSE
  local snap = { t = now, market = market, items = {} }
  local seen = {}
  local t = {}
  -- For checking (/fl debug): units that went down vs up, and the biggest drops.
  -- "Came back": units that dropped between the two previous scans and reappeared now.
  -- If most come back, full scans return a different slice of the auction house each
  -- time (beta, September 30: 10,890 down and 26,559 up in 16 minutes).
  local down, up, missing, drops = 0, 0, 0, {}
  local older = compare and olderSnap and olderSnap.market == market and olderSnap
  local lastDrop, cameBack = 0, 0
  function t.add(id, units)
    seen[id] = true
    local rec = (ns.db.prices[market] or {})[id]
    local limit = rec and rec.a and math.floor(rec.a * SOLD_PRICE)
    if limit then snap.items[id] = { limit, countUpTo(units, limit) } end
    local p = compare and prev.items[id]
    local o = older and older.items[id]
    if p and o then
      local before = countUpTo(units, p[1])
      local dropped = o[2] - p[2]
      if dropped > 0 then
        lastDrop = lastDrop + dropped
        cameBack = cameBack + math.min(dropped, math.max(0, before - p[2]))
      end
    end
    if p and p[2] > 0 and ns.RecordSold then
      local nowN = countUpTo(units, p[1])
      if nowN < p[2] then
        down = down + (p[2] - nowN)
        drops[#drops + 1] = { id, p[2], nowN }
      else
        up = up + (nowN - p[2])
      end
      pcall(ns.RecordSold, ns, id, math.max(0, p[2] - nowN), (now - prev.t) / 60, close)
    end
  end
  function t.finish()
    if compare and ns.RecordSold then
      -- Items with nothing listed now: everything that was listed is gone.
      for id, p in pairs(prev.items) do
        if not seen[id] and p[2] > 0 then
          missing = missing + 1
          pcall(ns.RecordSold, ns, id, p[2], (now - prev.t) / 60, close)
        end
      end
      -- Also kept in saved data (last 30 lines), since busy chat scrolls them away:
      -- /fl sellcheck prints them.
      local log = ns.db.sellCheckLog or {}
      ns.db.sellCheckLog = log
      local function note(text)
        ns:Debug(text)
        log[#log + 1] = date("%m-%d %H:%M ") .. text
        while #log > 30 do table.remove(log, 1) end
      end
      note(("Sell speed: compared with the full scan %d minutes ago (%s)."):format(
        math.floor((now - prev.t) / 60), close and "watched" or "rough: expired listings count too"))
      -- If scans don't return the same listings each time, "down" and "up" are both big
      -- and similar (noise), not mostly "down" (sales).
      note(("Sell speed check: %d units went down, %d went up, %d items vanished completely."):format(down, up, missing))
      table.sort(drops, function(a, b) return a[2] - a[3] > b[2] - b[3] end)
      for i = 1, math.min(5, #drops) do
        note(("  %s: %d then %d"):format(ns.ItemName(drops[i][1]) or drops[i][1], drops[i][2], drops[i][3]))
      end
      if older then
        note(("Sell speed came-back check: of %d units that went down last time, %d came back this time (%d%%)."):format(
          lastDrop, cameBack, lastDrop > 0 and math.floor(cameBack / lastDrop * 100 + 0.5) or 0))
      end
    end
    olderSnap = compare and prev or nil
    lastSnap = snap
    saveSnap(snap)
  end
  return t
end

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
  -- The flip watch's quiet checks wait while you're searching yourself, so they don't
  -- talk over the page you're buying from.
  if self.quiet and ns.lastUserSearch and GetTime() - ns.lastUserSearch < 20 then
    C_Timer.After(2, function() self:Next() end)
    return
  end
  local id = table.remove(self.queue, 1)
  self.pending = id
  self.token = (self.token or 0) + 1
  local tok = self.token
  self.sending = true
  local ok, err = pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(id), sorts(), false)
  self.sending = false
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
  -- The flip watch's quiet checks don't announce each pass.
  if was and not (self.quiet and not reason) then
    ns:Print(reason or ("Scan finished: %d items checked in %s."):format(self.items or self.done or 0, took()))
  end
  self.quiet = nil
  if was and not reason and ns.FlipWatchNext then ns.FlipWatchNext() end
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

-- Searches you make yourself (clicking a flip, browsing): save what the page shows as
-- the item's latest price, so Refresh and the flip watch use it. Before, a flip whose
-- cheap listings had just been bought stayed on the Vendor flips tab until the next scan
-- (owner test, September 30: Rough Bronze Leggings). An empty list only counts once the
-- auction house says the results are complete; gear with random stats ("of the Bear")
-- is skipped, since its versions have different prices under one item ID.
local liveRefresh
local function saveLive(id, units, complete)
  if not id or not units then return end
  if #units == 0 and not complete then return end
  record(id, units, "scan")
  ns:Debug("Saved the prices on screen for", ns.ItemName(id) or id, #units == 0 and "(none listed)" or "")
  if not liveRefresh and ns.RefreshFlipsIfShown then
    liveRefresh = true
    C_Timer.After(1, function() liveRefresh = nil; ns:InvalidateValues(true); ns:RefreshFlipsIfShown() end)
  end
end

-- Your own searches (not the addon's): noted so the flip watch can wait for you.
if C_AuctionHouse and hooksecurefunc then
  for _, fn in ipairs({ "SendSearchQuery", "SendBrowseQuery", "SearchForItemKeys" }) do
    if C_AuctionHouse[fn] then
      hooksecurefunc(C_AuctionHouse, fn, function() if not Scan.sending then ns.lastUserSearch = GetTime() end end)
    end
  end
end

-- Results that aren't the scan's own pending item are yours: save them either way
-- (they used to be ignored while the flip watch was checking, so Shadowgem and Linen
-- Bandage stayed on Vendor flips after you bought them, owner test September 30).
ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
  if not Scan.active or Scan.pending ~= itemID then
    local complete = C_AuctionHouse.HasFullCommoditySearchResults and C_AuctionHouse.HasFullCommoditySearchResults(itemID)
    saveLive(itemID, (commodityUnits(itemID)), complete)
    return
  end
  if Scan.pending ~= itemID then return end
  Scan:Finish(itemID, (commodityUnits(itemID)))
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  local id = itemKey and itemKey.itemID
  if not Scan.active or Scan.pending ~= id then
    if id and (itemKey.itemSuffix or 0) == 0 then
      local complete = C_AuctionHouse.HasFullItemSearchResults and C_AuctionHouse.HasFullItemSearchResults(itemKey)
      saveLive(id, (itemUnits(itemKey)), complete)
    end
    return
  end
  if Scan.pending ~= id then return end
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
    if not fallback and ns.FlipWatchNext then ns.FlipWatchNext() end
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
  -- Gear with random stats ("of the Eagle"): note each listing's version (the suffix
  -- number in its link) so tooltips can price the exact version (Gillee's AH video).
  local isGear, getLink = {}, C_AuctionHouse.GetReplicateItemLink
  local samples = 0
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local function suffixOf(idx, itemID)
    if not (getLink and instant) then return end
    if isGear[itemID] == nil then
      local _, _, _, _, _, classID = instant(itemID)
      isGear[itemID] = classID == 2 or classID == 4
    end
    if not isGear[itemID] then return end
    local ok, link = pcall(getLink, idx)
    -- Checking the link format (/fl debug): a few gear links, with and without a version
    -- in the name, and the version worked out from each.
    if ok and link and ns.db.settings.debug then
      local named = link:find("%[.+ of .+%]") and "named" or "plain"
      samples = type(samples) == "table" and samples or { named = 0, plain = 0 }
      if samples[named] < (named == "named" and 3 or 2) then
        samples[named] = samples[named] + 1
        ns:Debug("Gear link sample:", link:match("%[(.-)%]") or "?", "=", link:match("item:[%-%d:]*") or "no item: part",
          "version:", ns.SuffixFromLink(link) or "none")
      end
    end
    local suffix = ok and ns.SuffixFromLink(link) or nil
    -- Learn which version name goes with which number ("of the Whale" = 12719, the same
    -- on every item), so tooltips can find the version from the name they show: the
    -- tooltip's own link doesn't match the scan's (beta, September 30).
    if suffix then
      local vname = (link:match("%[(.-)%]") or ""):match(".* (of .+)$")
      if vname and ns.db.suffixNames[vname] ~= suffix then
        ns.db.suffixNames[vname] = suffix
        ns:ForgetVersionNames()
      end
    end
    return suffix
  end
  local function chunk()
    local stop = math.min(i + 2000, n)
    for idx = i, stop - 1 do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
      if itemID and buyout and buyout > 0 then
        count = math.max(count or 1, 1)
        local t = byItem[itemID]
        if not t then t = {}; byItem[itemID] = t end
        t[#t + 1] = { math.floor(buyout / count + 0.5), count, suffixOf(idx, itemID) }
      end
    end
    i = stop
    if i < n then
      ns:UpdateScanStatus(i, n)
      C_Timer.After(0, chunk)
    else
      local items, versions, gearWith = 0, 0, 0
      local sold = soldTracker()
      for id, units in pairs(byItem) do
        record(id, units, "full"); items = items + 1
        sold.add(id, units)
        local has = false
        for _, u in ipairs(units) do if u[3] then versions = versions + 1; has = true end end
        if has then gearWith = gearWith + 1 end
      end
      sold.finish()
      -- For checking gear versions (/fl debug): did the scan see any "of the Eagle" listings?
      ns:Debug(("Gear versions: %d listings with random stats across %d items (link function: %s)."):format(
        versions, gearWith, getLink and "yes" or "missing"))
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
      if mine and ns.FlipWatchNext then ns.FlipWatchNext() end
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
-- Flip watch (/fl watch): while the auction house stays open, keep looking for vendor
-- flips. A full scan whenever Blizzard allows one (about every 15 minutes); in between,
-- slow re-checks of the items closest to their vendor price. New flips chime and open
-- the Vendor flips tab (through CheckDeals). It only looks; buying is always your click.
---------------------------------------------------------------------------
local WATCH_PAUSE = 30      -- seconds between passes
local WATCH_ITEMS = 120     -- items re-checked per pass
local watching, watchTimer = false, nil

-- Items whose cheapest listing was within 50% of what a vendor pays, closest first.
-- Gear is left out: its stat versions ("of the Eagle") share one item ID, and each
-- quick search came back with a different version's listings, so prices (and
-- disenchant shuffles) jumped back and forth every pass. Full scans see all versions.
local instantInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local function isGear(id)
  if not instantInfo then return false end
  local _, _, _, _, _, classID = instantInfo(id)
  return classID == 2 or classID == 4
end

local function flipCandidates()
  local market = ns.db.prices[ns.MarketKey()] or {}
  local list = {}
  for id, rec in pairs(market) do
    local sell = rec.m and not rec.none and ns:GetSellPrice(id)
    if sell and sell >= 5 and rec.m <= sell * 1.5 and not ns:GetVendorBuyPrice(id) and not isGear(id) then
      list[#list + 1] = { id = id, r = rec.m / sell }
    end
  end
  table.sort(list, function(a, b) return a.r < b.r end)
  local ids = {}
  for i = 1, math.min(#list, WATCH_ITEMS) do ids[i] = list[i].id end
  return ids
end

local function watchPass()
  watchTimer = nil
  if not watching then return end
  if not ahOpen then ns:StopFlipWatch(); return end
  if Scan.active then watchTimer = C_Timer.NewTimer(10, watchPass); return end
  Scan.started = GetTime()
  if Scan:FullWait() == 0 then
    Scan:StartFull(false)
    return
  end
  local ids = flipCandidates()
  if #ids == 0 then
    ns:Debug("Flip watch: nothing close to vendor price; waiting for the next full scan.")
    watchTimer = C_Timer.NewTimer(WATCH_PAUSE, watchPass)
    return
  end
  Scan.quiet = true
  Scan.queue = ids
  Scan.items, Scan.retry, Scan.retrying = #ids, {}, true   -- no retries: the next pass is soon
  Scan.total, Scan.done, Scan.active, Scan.pending = #ids, 0, true, nil
  ns:Debug("Flip watch: re-checking", #ids, "items near vendor price")
  Scan:Next()
end

-- Called when any scan ends: queue the next pass.
-- While waiting, the status corner counts down to the next check, so a quiet spell
-- doesn't look like the watch has stopped (owner test, September 30).
local countdown
local function showCountdown(untilTime)
  if countdown then countdown:Cancel() end
  countdown = C_Timer.NewTicker(1, function(self)
    local left = math.ceil(untilTime - GetTime())
    if not watching or left <= 0 or Scan.active then
      self:Cancel(); countdown = nil
      return
    end
    local full = Scan:FullWait()
    ns:SetStatusText(("Watching flips: next check in %ds%s"):format(left,
      full > 0 and full < math.huge and (", full scan in %d min"):format(math.ceil(full / 60)) or ""))
  end)
end

function ns.FlipWatchNext()
  if watching and ns.RefreshFlipsIfShown then C_Timer.After(1, function() ns:RefreshFlipsIfShown() end) end
  if watching and not watchTimer then
    watchTimer = C_Timer.NewTimer(WATCH_PAUSE, watchPass)
    showCountdown(GetTime() + WATCH_PAUSE)
  end
end

function ns:StopFlipWatch(silent)
  if not watching then return end
  watching = false
  if watchTimer then watchTimer:Cancel(); watchTimer = nil end
  if countdown then countdown:Cancel(); countdown = nil end
  ns:SetStatusText("")
  -- Also end the watch's own re-check pass (it kept going and looked like the watch
  -- hadn't stopped). A full scan in progress is left to finish, as it's nearly instant.
  if Scan.active and Scan.quiet and not Scan.full then
    Scan:Stop(silent and "Scan stopped." or "Flip watch stopped.")
  elseif not silent then
    ns:Print("Flip watch stopped.")
  end
  if ns.UpdateWatchButton then ns:UpdateWatchButton() end
end

function ns:ToggleFlipWatch()
  if watching then ns:StopFlipWatch(); return end
  if not ahOpen then ns:Print("Open the auction house first, then start the flip watch."); return end
  watching = true
  ns:Print("Flip watch on: a full scan every 15 minutes, and items near vendor price re-checked in between. " ..
    "A chime means a new flip. It stops when the auction house closes. /fl watch again to stop.")
  if ns.UpdateWatchButton then ns:UpdateWatchButton() end
  if not Scan.active then watchPass() end
end
function ns:IsFlipWatching() return watching end

ns:On("AUCTION_HOUSE_CLOSED", function() ns:StopFlipWatch() end)

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
