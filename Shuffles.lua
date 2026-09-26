local _, ns = ...

---------------------------------------------------------------------------
-- Shuffle finder: things you can buy for less than they're worth to you,
-- through crafting, disenchanting, converting or selling to a vendor.
---------------------------------------------------------------------------
local OVERHEAD = 0.1    -- actions per unit for buying and selling
local MIN_LISTED = 5    -- fewer listed than this counts as a one-off deal

local function itemName(id)
  return (ns.GetItemInfo(id)) or ("item " .. id)
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

local function endsOnAH(o)
  if o.kind == "ah" then return true end
  if o.kind == "craft" or o.kind == "convert" then return endsOnAH(o.next) end
  if o.kind == "disenchant" then
    for _, m in ipairs(o.mats) do
      if endsOnAH(m.opt) then return true end
    end
  end
  return false
end

-- Plain-text steps, for example
-- "Craft Heavy Linen Gloves (+1 Coarse Thread) > disenchant (Strange Dust: ...; Lesser Magic Essence: ...)"
local function describe(o)
  if o.kind == "ah" then return "sell on auction house" end
  if o.kind == "vendor" then return "sell to vendor" end
  if o.kind == "disenchant" then
    local parts = {}
    for _, m in ipairs(o.mats) do
      parts[#parts + 1] = itemName(m.id) .. ": " .. describe(m.opt)
    end
    return "disenchant (" .. table.concat(parts, "; ") .. ")"
  end
  local step = o.step
  if o.kind == "craft" then
    local extra = {}
    for _, b in ipairs(o.buys or {}) do extra[#extra + 1] = b.qty .. " " .. itemName(b.id) end
    if #extra > 0 then step = step .. " (+" .. table.concat(extra, ", +") .. ")" end
    if o.who then step = step .. " [" .. o.who .. "]" end
  end
  return step .. " > " .. describe(o.next)
end

-- Returns two lists (regular and one-off deals), best profit per hour first.
function ns:FindShuffles()
  local margin = (ns.db.settings.margin or 10) / 100
  local secs = ns.db.settings.actionSeconds or 3
  local market = ns.db.prices[ns.MarketKey()] or {}

  local candidates = {}
  for id, rec in pairs(market) do
    if rec.m and not rec.none then candidates[id] = true end
  end
  for id in pairs(ns.db.vendorBuy) do candidates[id] = true end

  local regular, oneOff = {}, {}
  for id in pairs(candidates) do
    local cost, listed = ns:GetVendorBuyPrice(id), nil
    if not cost then
      cost = ns:GetPrice(id)
      listed = market[id] and market[id].q
    end
    if cost and cost > 0 then
      -- The best option that isn't just relisting it on the auction house.
      for _, o in ipairs(ns:Options(id)) do
        if o.kind ~= "ah" then
          local maxBuy = o.value * (1 - margin)
          if maxBuy > cost then
            local profit = o.value - cost
            local s = {
              id = id, opt = o, cost = cost, listed = listed, maxBuy = maxBuy, profit = profit,
              perHour = profit / ((actions(o) + OVERHEAD) * secs) * 3600, ahEnd = endsOnAH(o),
            }
            if listed and listed < MIN_LISTED then oneOff[#oneOff + 1] = s else regular[#regular + 1] = s end
          end
          break
        end
      end
    end
  end

  local function byHour(a, b) return a.perHour > b.perHour end
  table.sort(regular, byHour)
  table.sort(oneOff, byHour)
  return regular, oneOff
end

local function printShuffle(i, s)
  local where = s.listed and (s.listed .. " listed") or "from a vendor"
  print(("%d. |cffffffff%s|r: buy up to %s (now %s, %s)"):format(
    i, itemName(s.id), ns.Money(s.maxBuy), ns.Money(s.cost), where))
  print("    " .. (describe(s.opt):gsub("^%l", string.upper)))
  print(("    Profit %s each (%d%%), about %s an hour%s"):format(
    ns.Money(s.profit), math.floor(s.profit / s.cost * 100 + 0.5), ns.Money(s.perHour),
    s.ahEnd and ". Ends with an auction house sale." or "."))
end

function ns:PrintShuffles(showAll)
  local regular, oneOff = ns:FindShuffles()
  if #regular == 0 and #oneOff == 0 then
    ns:Print("No shuffles found at current prices. Scan the auction house and open your profession windows first.")
    return
  end
  local n = showAll and #regular or math.min(10, #regular)
  ns:Print(("Top %d of %d shuffles, best profit per hour first (%g%% safety margin):"):format(
    n, #regular, ns.db.settings.margin or 10))
  for i = 1, n do printShuffle(i, regular[i]) end
  if showAll then
    if #oneOff > 0 then ns:Print(("One-off deals (fewer than %d listed):"):format(MIN_LISTED)) end
    for i, s in ipairs(oneOff) do printShuffle(i, s) end
  elseif #oneOff > 0 or #regular > n then
    local more = {}
    if #regular > n then more[#more + 1] = (#regular - n) .. " more shuffles" end
    if #oneOff > 0 then more[#more + 1] = ("%d one-off deals with fewer than %d listed"):format(#oneOff, MIN_LISTED) end
    ns:Print("Plus " .. table.concat(more, " and ") .. ". Type /fl shuffles all to see everything.")
  end
end
