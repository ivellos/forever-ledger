local _, ns = ...

---------------------------------------------------------------------------
-- Shuffle finder: things you can buy for less than they're worth to you,
-- through crafting, disenchanting, converting or selling to a vendor.
---------------------------------------------------------------------------
local OVERHEAD = 0.1    -- actions per unit for buying and selling
local MIN_LISTED = 5    -- fewer listed than this counts as a one-off deal
local SHOWN = 5         -- shuffles shown per section

local function itemName(id)
  local name = ns.GetItemInfo(id)
  if name then return name end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return "item " .. id
end

-- Crafts, disenchants and conversions per unit of the item, for per-hour estimates.
local function actions(o)
  if o.kind == "craft" then return (1 + (o.rec.oq or 1) * actions(o.next)) / o.units end
  if o.kind == "convert" then return math.min(1, o.per) + o.per * actions(o.next) end
  if o.kind == "disenchant" then
    local n = 1
    for _, m in ipairs(o.mats) do n = n + m.count * actions(m.opt) end
    return n
  end
  return 0
end

-- Share of the final value that comes from auction house sales (0 to 1).
local function ahShare(o)
  if o.kind == "ah" then return 1 end
  if o.kind == "craft" or o.kind == "convert" then return ahShare(o.next) end
  if o.kind == "disenchant" then
    local total, ah = 0, 0
    for _, m in ipairs(o.mats) do
      local v = m.opt.value * m.count
      total, ah = total + v, ah + v * ahShare(m.opt)
    end
    return total > 0 and ah / total or 0
  end
  return 0
end

-- Plain-text steps, for example
-- "Craft Heavy Linen Gloves (+1 Coarse Thread) > disenchant (Strange Dust: ...; Lesser Magic Essence: ...)".
-- skipBuys leaves out the first craft's extra materials, which the buy line lists instead.
local function describe(o, skipBuys)
  if o.kind == "ah" then return "sell on auction house" end
  if o.kind == "vendor" then return "sell to vendor" end
  if o.kind == "disenchant" then
    local parts = {}
    for _, m in ipairs(o.mats) do parts[#parts + 1] = itemName(m.id) .. ": " .. describe(m.opt) end
    return "disenchant (" .. table.concat(parts, "; ") .. ")"
  end
  local step = o.step
  if o.kind == "craft" then
    if not skipBuys then
      local extra = {}
      for _, b in ipairs(o.buys or {}) do extra[#extra + 1] = b.qty .. " " .. itemName(b.id) end
      if #extra > 0 then step = step .. " (+" .. table.concat(extra, ", +") .. ")" end
    end
    if o.who then step = step .. " [" .. o.who .. "]" end
  end
  return step .. " > " .. describe(o.next)
end

-- What an item costs to buy, and how many are listed (nil when a vendor sells it).
local function buyInfo(id, market)
  local p = ns:GetVendorBuyPrice(id)
  if p then return p, nil end
  return ns:GetPrice(id), market[id] and market[id].q
end

-- One shuffle: buy `id` (and the first craft's other materials), then follow `o`.
-- Returns nil if it doesn't clear the safety margin.
local function build(id, o, cost, listed, market, margin, secs)
  local s = { id = id, opt = o, share = ahShare(o) }
  if o.kind == "craft" then
    -- Keyed by recipe, so buying any of its materials counts as the same shuffle.
    s.key = "craft:" .. (o.rec.n or "?") .. ":" .. (o.rec.out or 0)
    s.units = o.units
    s.buys = { { id = id, qty = o.units, price = cost, listed = listed } }
    for _, b in ipairs(o.buys or {}) do
      local _, l = buyInfo(b.id, market)
      s.buys[#s.buys + 1] = { id = b.id, qty = b.qty, price = b.cost, listed = l }
    end
  else
    s.key = "item:" .. id .. ":" .. o.kind
    s.units = 1
    s.single = true
    s.buys = { { id = id, qty = 1, price = cost, listed = listed } }
  end

  s.cost = 0
  for _, b in ipairs(s.buys) do s.cost = s.cost + b.price * b.qty end
  s.profit = (o.value - cost) * s.units
  if s.profit <= 0 or (s.cost + s.profit) * (1 - margin) <= s.cost then return end

  s.maxBuy = o.value * (1 - margin)
  s.perHour = s.profit / ((actions(o) + OVERHEAD) * s.units * secs) * 3600
  for _, b in ipairs(s.buys) do
    if b.listed and b.listed < MIN_LISTED then s.oneOff = true end
  end
  return s
end

-- Returns three lists, best profit per hour first: shuffles that end with vendor sales,
-- ones that end with auction house sales, and one-off deals.
function ns:FindShuffles()
  local margin = (ns.db.settings.margin or 10) / 100
  local secs = ns.db.settings.actionSeconds or 3
  local market = ns.db.prices[ns.MarketKey()] or {}

  local candidates = {}
  for id, rec in pairs(market) do
    if rec.m and not rec.none then candidates[id] = true end
  end
  for id in pairs(ns.db.vendorBuy) do candidates[id] = true end

  local vendor, ah, oneOff, seen = {}, {}, {}, {}
  for id in pairs(candidates) do
    local cost, listed = buyInfo(id, market)
    if cost and cost > 0 then
      -- The best option that ends mostly with vendor sales, and the best that ends
      -- mostly on the auction house. Relisting the item itself doesn't count.
      local done = {}
      for _, o in ipairs(ns:Options(id)) do
        if o.kind ~= "ah" then
          local section = ahShare(o) >= 0.5 and "ah" or "vendor"
          if not done[section] then
            done[section] = true
            local s = build(id, o, cost, listed, market, margin, secs)
            if s and not seen[s.key] then
              seen[s.key] = true
              local list = (s.oneOff and oneOff) or (section == "ah" and ah) or vendor
              list[#list + 1] = s
            end
          end
          if done.ah and done.vendor then break end
        end
      end
    end
  end

  local function byHour(a, b) return a.perHour > b.perHour end
  table.sort(vendor, byHour)
  table.sort(ah, byHour)
  table.sort(oneOff, byHour)
  return vendor, ah, oneOff
end

local function where(b)
  return b.listed and (b.listed .. " listed") or "vendor"
end

local function printShuffle(i, s)
  if s.single then
    local b = s.buys[1]
    print(("%d. |cffffffff%s|r: %s"):format(i, itemName(s.id), describe(s.opt)))
    print(("    Buy at up to %s (now %s, %s)"):format(ns.Money(s.maxBuy), ns.Money(b.price), where(b)))
    print(("    Profit %s each (%d%%), about %s an hour."):format(
      ns.Money(s.profit), math.floor(s.profit / s.cost * 100 + 0.5), ns.Money(s.perHour)))
  else
    print(("%d. |cffffffff%s|r"):format(i, describe(s.opt, true)))
    local parts = {}
    for _, b in ipairs(s.buys) do
      parts[#parts + 1] = ("%s %s at %s (%s)"):format(b.qty, itemName(b.id), ns.Money(b.price), where(b))
    end
    print("    Buy: " .. table.concat(parts, ", "))
    print(("    Profit %s per craft (%d%%), about %s an hour."):format(
      ns.Money(s.profit), math.floor(s.profit / s.cost * 100 + 0.5), ns.Money(s.perHour)))
  end
end

local function printSection(title, list, n)
  if #list == 0 then return end
  ns:Print(title)
  for i = 1, math.min(n, #list) do printShuffle(i, list[i]) end
end

function ns:PrintShuffles(showAll)
  local vendor, ah, oneOff = ns:FindShuffles()
  if #vendor + #ah + #oneOff == 0 then
    ns:Print("No shuffles found at current prices. Scan the auction house and open your profession windows first.")
    return
  end
  local n = showAll and math.huge or SHOWN
  ns:Print(("Shuffles at current prices, best profit per hour first (%g%% safety margin)."):format(ns.db.settings.margin or 10))
  printSection("Sells to a vendor (safe):", vendor, n)
  printSection("Sells on the auction house (depends on buyers):", ah, n)
  if showAll then
    printSection(("One-off deals (fewer than %d listed):"):format(MIN_LISTED), oneOff, n)
  else
    local hidden = math.max(0, #vendor - n) + math.max(0, #ah - n) + #oneOff
    if hidden > 0 then
      local deals = #oneOff > 0 and (", including %d one-off deals"):format(#oneOff) or ""
      ns:Print(("Plus %d more%s. Type /fl shuffles all to see everything."):format(hidden, deals))
    end
  end
end
