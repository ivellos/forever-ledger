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

-- Text for one craft or conversion step, with the craft's extra materials unless skipBuys.
local function stepText(o, skipBuys)
  local step = o.step
  if o.kind == "craft" then
    if not skipBuys then
      local extra = {}
      for _, b in ipairs(o.buys or {}) do extra[#extra + 1] = b.qty .. " " .. itemName(b.id) end
      if #extra > 0 then step = step .. " (+" .. table.concat(extra, ", +") .. ")" end
    end
    if o.who then step = step .. " [" .. o.who .. "]" end
  end
  return step
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
  return stepText(o, skipBuys) .. " > " .. describe(o.next)
end

-- The same steps as numbered lines, for the ledger window.
local function stepLines(o, lines, num, skipBuys)
  num.n = num.n + 1
  if o.kind == "ah" then lines[#lines + 1] = num.n .. ". Sell on the auction house"; return end
  if o.kind == "vendor" then lines[#lines + 1] = num.n .. ". Sell to a vendor"; return end
  if o.kind == "disenchant" then
    lines[#lines + 1] = num.n .. ". Disenchant. On average each one gives:"
    for _, m in ipairs(o.mats) do
      lines[#lines + 1] = ("      %.2f %s: %s"):format(m.count, itemName(m.id), describe(m.opt))
    end
    return
  end
  lines[#lines + 1] = num.n .. ". " .. stepText(o, skipBuys)
  stepLines(o.next, lines, num)
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

-- Items that disenchant the same way (same row of the disenchant table) are one
-- shuffle: "buy any of these and disenchant". Folds them into a single group entry,
-- using the numbers of the cheapest member.
local function groupDisenchants(list)
  local groups, out = {}, {}
  for _, s in ipairs(list) do
    local yield = s.single and s.opt.kind == "disenchant" and ns:DisenchantYield(s.id)
    if yield then
      groups[yield] = groups[yield] or {}
      table.insert(groups[yield], s)
    else
      out[#out + 1] = s
    end
  end
  for yield, members in pairs(groups) do
    if #members == 1 then
      out[#out + 1] = members[1]
    else
      table.sort(members, function(a, b) return a.cost < b.cost end)
      local g = {}
      for k, v in pairs(members[1]) do g[k] = v end
      g.key = "group:" .. (yield.label or "?")
      g.group = yield.label or "Similar items"
      g.members = members
      out[#out + 1] = g
    end
  end
  return out
end

-- Returns four lists: shuffles that end with vendor sales, ones that end with auction
-- house sales, one-off deals (best profit per hour first), and vendor flips (buy on the
-- auction house, sell straight to a vendor).
function ns:FindShuffles()
  local margin = (ns.db.settings.margin or 10) / 100
  local secs = ns.db.settings.actionSeconds or 3
  local market = ns.db.prices[ns.MarketKey()] or {}

  local candidates = {}
  for id, rec in pairs(market) do
    if rec.m and not rec.none then candidates[id] = true end
  end
  for id in pairs(ns.db.vendorBuy) do candidates[id] = true end

  local vendor, ah, oneOff, flips, seen = {}, {}, {}, {}, {}
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
              -- Buying and selling straight to a vendor is a vendor flip, not a shuffle.
              local list = (o.kind == "vendor" and flips) or (s.oneOff and oneOff) or (section == "ah" and ah) or vendor
              list[#list + 1] = s
            end
          end
          if done.ah and done.vendor then break end
        end
      end
    end
  end

  local function byHour(a, b) return a.perHour > b.perHour end
  vendor, ah = groupDisenchants(vendor), groupDisenchants(ah)
  table.sort(vendor, byHour)
  table.sort(ah, byHour)
  table.sort(oneOff, byHour)
  -- Vendor flips have no crafting time, so rank them by total profit on offer.
  table.sort(flips, function(a, b)
    return a.profit * math.min(a.buys[1].listed or 20, 20) > b.profit * math.min(b.buys[1].listed or 20, 20)
  end)
  return vendor, ah, oneOff, flips
end

local function where(b)
  return b.listed and (b.listed .. " listed") or "vendor"
end

local function returnPct(s)
  return math.floor(s.profit / s.cost * 100 + 0.5)
end

-- Short one-line name, for example "Raider's Cloak: Disenchant".
function ns:ShuffleTitle(s)
  if s.group then return ("%s (%d items): %s"):format(s.group, #s.members, ns:OptionLabel(s.opt)) end
  if s.single then return itemName(s.id) .. ": " .. ns:OptionLabel(s.opt) end
  return ns:OptionLabel(s.opt)
end

-- Profit, return and per hour (rounded to silver) for the right side of a row.
function ns:ShuffleSummary(s)
  if s.opt.kind == "vendor" then
    -- No crafting time, so per hour means nothing. Show how many are listed instead.
    return ("|cff7fd39c%s|r   %d%%   %s listed"):format(ns.Money(s.profit), returnPct(s), s.buys[1].listed or "?")
  end
  return ("|cff7fd39c%s|r   %d%%   %s/h"):format(
    ns.Money(s.profit), returnPct(s), ns.Money(math.floor(s.perHour / 100) * 100))
end

-- Everything needed to do a shuffle, one line per step.
function ns:ShuffleDetails(s)
  local lines = {}
  if s.group then
    lines[#lines + 1] = ("Buy any of these at up to %s, cheapest first:"):format(ns.Money(s.maxBuy))
    for i, m in ipairs(s.members) do
      if i > 12 then
        lines[#lines + 1] = ("      and %d more"):format(#s.members - 12)
        break
      end
      lines[#lines + 1] = ("      %s at %s (%s)"):format(itemName(m.id), ns.Money(m.cost), where(m.buys[1]))
    end
  elseif s.single then
    local b = s.buys[1]
    lines[#lines + 1] = ("Buy %s at up to %s (now %s, %s)."):format(
      itemName(s.id), ns.Money(s.maxBuy), ns.Money(b.price), where(b))
  else
    lines[#lines + 1] = "Buy for each craft:"
    for _, b in ipairs(s.buys) do
      lines[#lines + 1] = ("      %s %s at %s (%s)"):format(b.qty, itemName(b.id), ns.Money(b.price), where(b))
    end
  end
  lines[#lines + 1] = "Then:"
  stepLines(s.opt, lines, { n = 0 }, true)
  lines[#lines + 1] = ("Profit %s %s (%d%%), about %s an hour."):format(
    ns.Money(s.profit), s.single and "each" or "per craft", returnPct(s), ns.Money(s.perHour))
  return table.concat(lines, "\n")
end

local function printShuffle(i, s)
  if s.group then
    print(("%d. |cffffffff%s|r"):format(i, ns:ShuffleTitle(s)))
    local names = {}
    for j = 1, math.min(5, #s.members) do names[j] = itemName(s.members[j].id) end
    print(("    Buy any at up to %s, for example %s."):format(ns.Money(s.maxBuy), table.concat(names, ", ")))
    print(("    Profit %s each at %s (%d%%), about %s an hour."):format(
      ns.Money(s.profit), ns.Money(s.cost), math.floor(s.profit / s.cost * 100 + 0.5), ns.Money(s.perHour)))
  elseif s.single then
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
  local vendor, ah, oneOff, flips = ns:FindShuffles()
  if #vendor + #ah + #oneOff + #flips == 0 then
    ns:Print("No shuffles found at current prices. Scan the auction house and open your profession windows first.")
    return
  end
  local n = showAll and math.huge or SHOWN
  ns:Print(("Shuffles at current prices, best profit per hour first (%g%% safety margin)."):format(ns.db.settings.margin or 10))
  printSection("Sells to a vendor (safe):", vendor, n)
  printSection("Sells on the auction house (depends on buyers):", ah, n)
  printSection("Vendor flips (buy on the auction house, sell to a vendor):", flips, n)
  if showAll then
    printSection(("One-off deals (fewer than %d listed):"):format(MIN_LISTED), oneOff, n)
  else
    local hidden = math.max(0, #vendor - n) + math.max(0, #ah - n) + math.max(0, #flips - n) + #oneOff
    if hidden > 0 then
      local deals = #oneOff > 0 and (", including %d one-off deals"):format(#oneOff) or ""
      ns:Print(("Plus %d more%s. Type /fl shuffles all to see everything."):format(hidden, deals))
    end
  end
end


---------------------------------------------------------------------------
-- Deal alerts, two kinds:
--   Below usual price: the cheapest listing is at least dealUsualPct% below the
--   item's usual price over dealWindow (a week ... all time). Needs MIN_POINTS days
--   of price history, so these start a few days after scanning begins.
--   Below vendor price: the cheapest listing is below what a vendor pays, by at least
--   dealVendorPct% and at least dealVendorMin copper (either can be 0 to turn it off).
-- Recipe profits aren't deals (every ingredient shares them); the Shuffles tab has them.
---------------------------------------------------------------------------
local DEAL_RECENT = 600       -- only prices from the last 10 minutes
local MIN_POINTS = 3          -- days of history needed for a usual price
local alerted = {}            -- [kind .. itemID] = price already alerted this session

ns.WINDOW_NAMES = {
  week = "the last week", month = "the last month", ["3months"] = "the last 3 months",
  ["6months"] = "the last 6 months", year = "the last year", all = "all time",
}

-- Where usual prices come from: "auto" (TSM if it has a price, otherwise this addon's
-- own history), "local" or "tsm". TSM has no arbitrary periods: its market value
-- (about 2 weeks) stands in for a week or a month, its historical price (about 2 months)
-- for anything longer.
local TSM_SOURCE = {
  week = "dbmarket", month = "dbmarket", ["3months"] = "dbhistorical",
  ["6months"] = "dbhistorical", year = "dbhistorical", all = "dbhistorical",
}
ns.HISTORY_SOURCES = { auto = true, ["local"] = true, tsm = true }

local function tsmUsual(id, window)
  if not (TSM_API and TSM_API.GetCustomPriceValue) then return end
  local ok, v = pcall(TSM_API.GetCustomPriceValue, TSM_SOURCE[window or "all"] or "dbhistorical", "i:" .. id)
  if ok and v and v > 0 then return v end
end

-- The usual price used for deals, and where it came from ("TSM" or "ledger").
function ns:DealUsualPrice(id)
  local s = ns.db.settings
  local src = s.dealHistory or "auto"
  if src ~= "local" then
    local v = tsmUsual(id, s.dealWindow)
    if v then return v, "TSM" end
    if src == "tsm" then return end
  end
  local usual, points = ns:UsualPrice(id, s.dealWindow)
  if usual and points >= MIN_POINTS then return usual, "ledger" end
end

-- The current rules in words, for messages.
function ns:DealRules()
  local s = ns.db.settings
  local vendor = ("%g%% or more below vendor price"):format(s.dealVendorPct or 10)
  if (s.dealVendorMin or 0) > 0 then vendor = vendor .. " and at least " .. ns.Money(s.dealVendorMin) .. " profit each" end
  local src = s.dealHistory or "auto"
  local from = (src == "tsm" and "TSM's prices")
    or (src == "local" and "this addon's scans")
    or ((TSM_API and "TSM's prices, or this addon's scans where TSM has none") or "this addon's scans")
  return ("%g%% or more below the usual price over %s (from %s), or %s"):format(
    s.dealUsualPct or 20, ns.WINDOW_NAMES[s.dealWindow or "all"] or "all time", from, vendor)
end

-- Returns deals, biggest saving first: { kind = "usual" | "vendor", id, price, worth, listed }.
function ns:FindDeals()
  local s = ns.db.settings
  local market = ns.db.prices[ns.MarketKey()] or {}
  local usualPct = (s.dealUsualPct or 20) / 100
  local vendorPct, vendorMin = (s.dealVendorPct or 10) / 100, s.dealVendorMin or 0
  local now, deals = time(), {}
  for id, rec in pairs(market) do
    local price = rec.m
    if price and not rec.none and now - (rec.t or 0) <= DEAL_RECENT then
      local sell = ns:GetSellPrice(id)
      if sell and sell > price then
        local profit = sell - price
        if profit / sell >= vendorPct and profit >= vendorMin then
          deals[#deals + 1] = { kind = "vendor", id = id, price = price, worth = sell, listed = rec.q }
        end
      end
      local usual, basis = ns:DealUsualPrice(id)
      if usual and price <= usual * (1 - usualPct) then
        deals[#deals + 1] = { kind = "usual", id = id, price = price, worth = usual, listed = rec.q, basis = basis }
      end
    end
  end
  table.sort(deals, function(a, b) return a.worth - a.price > b.worth - b.price end)
  return deals
end

local function printDeal(d)
  if d.kind == "vendor" then
    print(("    |cffffffff%s|r at %s, a vendor pays %s (%s profit each). %s listed."):format(
      itemName(d.id), ns.Money(d.price), ns.Money(d.worth), ns.Money(d.worth - d.price), d.listed or "?"))
  else
    print(("    |cffffffff%s|r at %s, usually %s (%d%% below, %s). %s listed."):format(
      itemName(d.id), ns.Money(d.price), ns.Money(d.worth),
      math.floor((1 - d.price / d.worth) * 100 + 0.5), d.basis or "ledger", d.listed or "?"))
  end
end

-- Prints deals in two groups, up to `limit` each.
local function printGrouped(list, limit)
  for _, kind in ipairs({ "vendor", "usual" }) do
    local shown = 0
    for _, d in ipairs(list) do
      if d.kind == kind then
        shown = shown + 1
        if shown == 1 then print(kind == "vendor" and "  Below vendor price:" or "  Below usual price:") end
        if shown <= limit then printDeal(d) end
      end
    end
    if shown > limit then print(("    and %d more"):format(shown - limit)) end
  end
end

-- Called when a scan finishes. Alerts only for deals not already alerted at this price or lower.
function ns:CheckDeals()
  ns:InvalidateValues(true)   -- the scan just changed prices
  local fresh = {}
  for _, d in ipairs(ns:FindDeals()) do
    local key = d.kind .. d.id
    if not alerted[key] or d.price < alerted[key] then
      alerted[key] = d.price
      fresh[#fresh + 1] = d
    end
  end
  if #fresh == 0 then return end
  local top = fresh[1]
  local text = ("Deal: %s at %s (%s %s)"):format(itemName(top.id), ns.Money(top.price),
    top.kind == "vendor" and "vendor pays" or "usually", ns.Money(top.worth))
  if #fresh > 1 then text = text .. (" and %d more"):format(#fresh - 1) end
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, text, { r = 0.05, g = 0.82, b = 0.62 })
  end
  if ns.db.settings.dealSound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
  end
  ns:Print(("%d new deals:"):format(#fresh))
  printGrouped(fresh, 10)
end

-- /fl deals: list every current deal, alerted or not.
function ns:PrintDeals()
  local deals = ns:FindDeals()
  ns:Print("Deals are listings " .. ns:DealRules() .. ".")
  if #deals == 0 then
    print("  None right now, from scans in the last 10 minutes. Usual-price deals need 3 days of scans first.")
    return
  end
  printGrouped(deals, 20)
end