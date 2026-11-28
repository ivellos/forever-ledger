local _, ns = ...

local api = { version = 1 }

local function record(itemID)
  if type(itemID) ~= "number" or not ns.db or not ns.db.prices or not ns.MarketKey then return end
  local ok, key = pcall(ns.MarketKey)
  local market = ok and ns.db.prices[key]
  return market and market[itemID]
end

local function own(rec)
  return rec and (rec.src == nil or rec.src == "scan" or rec.src == "full")
end

local function levels(rec)
  local out, prev = {}, 0
  for p, c in (rec.l or ""):gmatch("(%d+):(%d+)") do
    p, c = tonumber(p), tonumber(c)
    if c > prev then out[#out + 1] = { price = p, count = c - prev } end
    prev = c
  end
  if #out == 0 and rec.m then out[1] = { price = rec.m, count = rec.q or 1 } end
  return out
end

function api.GetPrice(itemID)
  local rec = record(itemID)
  if not own(rec) then return end
  if rec.none or not rec.m then return nil, nil, 0, rec.t end
  return math.max(rec.a or rec.m, rec.m), rec.m, rec.q or 0, rec.t
end

function api.GetListings(itemID)
  local rec = record(itemID)
  if not own(rec) then return end
  if rec.none or not rec.m then return {}, 0, rec.t end
  return levels(rec), rec.q or 0, rec.t
end

function api.GetCost(itemID, quantity)
  local rec = record(itemID)
  if not own(rec) or type(quantity) ~= "number" or quantity < 1 then return end
  if rec.none or not rec.m then return nil, 0, rec.t end
  local total, got = 0, 0
  for _, level in ipairs(levels(rec)) do
    local take = math.min(level.count, quantity - got)
    total, got = total + take * level.price, got + take
    if got >= quantity then break end
  end
  return total, got, rec.t
end

function api.GetUsualPrice(itemID, window)
  if type(itemID) ~= "number" or not ns.UsualPrice or not ns.db then return end
  if window ~= nil and not (ns.PRICE_WINDOWS and ns.PRICE_WINDOWS[window]) then return end
  local ok, price, points = pcall(ns.UsualPrice, ns, itemID, window or "week")
  if ok and price then return price, points end
end

function api.GetLastFullScan()
  return ns.db and ns.db.lastFullScan
end

-- What a vendor pays for one, and what one costs from a vendor (nil where it isn't sold
-- or hasn't been seen at a vendor yet). Neither comes from another addon.
function api.GetVendorPrice(itemID)
  if type(itemID) ~= "number" or not ns.db then return end
  local okS, sell = pcall(ns.GetSellPrice, ns, itemID)
  local okB, buy = pcall(ns.GetVendorBuyPrice, ns, itemID)
  return okS and sell or nil, okB and buy or nil
end

-- About how many sell a day, from our own full scans only (not AHledger's estimate,
-- whose terms don't let us pass it on), with how many are listed and the hours of scans
-- it's based on. Nothing until there are enough scans to say.
function api.GetSoldPerDay(itemID)
  if type(itemID) ~= "number" or not ns.SellSpeed or not ns.db then return end
  local ok, sp = pcall(ns.SellSpeed, ns, itemID)
  if not ok or type(sp) ~= "table" or sp.from then return end
  return sp.perDay, sp.listed, sp.hours
end

-- One version of gear with random stats ("of the Eagle"), from the last full scan: by
-- item ID and version number (the bonus ID in its link), or by an item link. Gives the
-- cheapest, how many of that version are listed and when; nil, 0, when if none listed.
function api.GetVersionPrice(item, version)
  local id = item
  if type(item) == "string" then
    if not ns.Readable(item) then return end
    id = ns.ItemIDFromLink(item)
    version = id and ns:VersionOfLink(id, item)
  end
  if type(id) ~= "number" or type(version) ~= "number" or not own(record(id)) then return end
  local cheapest, listed, seen = ns:SuffixPrice(id, version)
  if not cheapest then return end
  if cheapest == 0 then return nil, 0, seen end
  return cheapest, listed, seen
end

-- Telling other addons about new prices. Scans save prices item by item (a full scan
-- thousands over a few seconds; the flip watch a few every 20 seconds), so this waits
-- until saving has stopped for QUIET seconds, and calls each listener at most once every
-- MIN_GAP seconds (or after MAX_WAIT while saving never stops). Listeners get no
-- arguments; an error in one goes to the error handler and doesn't stop the others.
local QUIET, MIN_GAP, MAX_WAIT = 3, 30, 60
local listeners, order = {}, {}
local changes, pending, pendingSince, lastFired = 0, false, 0, nil

local function notify()
  pending, lastFired = false, GetTime()
  for _, name in ipairs(order) do
    local fn = listeners[name]
    if fn then
      local ok, err = pcall(fn)
      if not ok and geterrorhandler then geterrorhandler()(err) end
    end
  end
end

local function settle(seen)
  -- Still saving: wait for a quiet moment, unless it's been going on too long.
  if changes ~= seen and GetTime() - pendingSince < MAX_WAIT then
    local now = changes
    C_Timer.After(QUIET, function() settle(now) end)
    return
  end
  notify()
end

function ns.PricesChanged()
  changes = changes + 1
  if pending or not order[1] then return end
  pending, pendingSince = true, GetTime()
  local wait = QUIET
  if lastFired then wait = math.max(wait, MIN_GAP - (GetTime() - lastFired)) end
  local now = changes
  C_Timer.After(wait, function() settle(now) end)
end

-- RegisterForUpdate(name, fn): call fn after Forever Ledger saves new prices. name is your
-- addon's name; registering the same name again replaces its function.
function api.RegisterForUpdate(name, fn)
  if type(name) ~= "string" or type(fn) ~= "function" then return false end
  if not listeners[name] then order[#order + 1] = name end
  listeners[name] = fn
  return true
end

function api.UnregisterForUpdate(name)
  if not listeners[name] then return end
  listeners[name] = nil
  for i, n in ipairs(order) do
    if n == name then table.remove(order, i); break end
  end
end

ForeverLedgerAPI = api
ns.API = api   -- (for our own files: CraftProfitSource.lua)
