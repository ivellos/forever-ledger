local _, ns = ...

---------------------------------------------------------------------------
-- Shuffle finder: things you can buy for less than they're worth to you,
-- through crafting, disenchanting, converting or selling to a vendor.
---------------------------------------------------------------------------
local OVERHEAD = 0.1    -- actions per unit for buying and selling
local MIN_LISTED = 5    -- fewer listed than this counts as a one-off deal
local SHOWN = 5         -- shuffles shown per section

local function itemName(id) return ns.ItemName(id) end

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
  if o.kind == "vendor" then return o.vendorInstead and "vendor it instead (deposit risk)" or "sell to vendor" end
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
  if o.kind == "vendor" then lines[#lines + 1] = num.n .. (o.vendorInstead and ". Vendor it instead (deposit risk)" or ". Sell to a vendor"); return end
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
-- The cheaper of the two: a vendor that sells it (often in limited stock) or the
-- auction house. (It used to take the vendor whenever there was one: Strange Dust
-- counted at a limited vendor's 8s instead of 2s 35c on the auction house, which hid
-- the Minor Wizard Oil shuffle, owner's test September 30.)
local function buyInfo(id, market)
  local vendor = ns:GetVendorBuyPrice(id)
  local ah = ns:GetPrice(id)
  if vendor and (not ah or vendor <= ah) then return vendor, nil end
  return ah, market[id] and market[id].q
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
  s.deposit = ns:OptionDeposit(o) * s.units
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

-- One item as a vendor flip, or nil: only the listings cheap enough to profit after the
-- safety margin count, at their own prices. The Vendor flips tab and the flip alerts
-- both use this, so whatever the tab shows also chimes.
-- The most worth paying to sell straight to a vendor that pays `sell`. Selling to a
-- vendor has no risk, only effort, so the profit you want is your choice (Settings,
-- Vendor flips): at least dealVendorPct% of the vendor price and at least dealVendorMin
-- copper, and always at least 1c (owner, October 2: "even if it's 1c less I make money").
function ns:VendorFlipLimit(sell)
  local s = ns.db.settings
  local need = math.max(math.ceil(sell * (s.dealVendorPct or 10) / 100), s.dealVendorMin or 0, 1)
  return sell - need
end

function ns:VendorFlip(id)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not (rec and rec.m and not rec.none) then return end
  -- A quick look at the vendor price first: the full check reads the item's tooltip (can
  -- vendors buy it?), which over every listed item took up to 210 ms (/fl perf, October 3).
  local raw = select(11, ns.GetItemInfo(id)) or ns.db.vendorSell[id]
  if raw and raw <= rec.m then return end
  local sell = ns:GetSellPrice(id)
  if not (sell and sell > rec.m) or ns:GetVendorBuyPrice(id) then return end
  local maxBuy = ns:VendorFlipLimit(sell)
  local n, avg = ns:CheapListings(id, maxBuy)
  if not (n and n > 0 and avg) then return end
  return {
    id = id, key = "item:" .. id .. ":vendor", single = true, units = 1,
    opt = { kind = "vendor", value = sell, id = id }, share = 0,
    buys = { { id = id, qty = 1, price = avg, listed = n } },
    cost = avg, profit = sell - avg, maxBuy = maxBuy, perHour = 0, t = rec.t,
  }
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
        -- Selling the item itself to a vendor is a vendor flip, worked out below.
        if o.kind ~= "ah" and o.kind ~= "vendor" then
          local section = ahShare(o) >= 0.5 and "ah" or "vendor"
          if not done[section] then
            done[section] = true
            local s = build(id, o, cost, listed, market, margin, secs)
            if s and not seen[s.key] then
              seen[s.key] = true
              -- Buying and selling straight to a vendor is a vendor flip, not a shuffle.
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
  vendor, ah = groupDisenchants(vendor), groupDisenchants(ah)
  table.sort(vendor, byHour)
  table.sort(ah, byHour)
  table.sort(oneOff, byHour)
  return vendor, ah, oneOff, ns:FindVendorFlips()
end

-- Just the vendor flips: far quicker than every shuffle, so the Vendor flips tab can
-- follow the flip watch without a hitch (owner's /fl perf, October 2: the whole
-- shuffle search ran 29 times in 106 seconds at about 195 ms each).
-- Vendor flips have no crafting time, so they're ranked by total profit on offer.
function ns:FindVendorFlips()
  local flips = {}
  for id in pairs(ns.db.prices[ns.MarketKey()] or {}) do
    local f = ns:VendorFlip(id)
    if f then flips[#flips + 1] = f end
  end
  table.sort(flips, function(a, b)
    return a.profit * math.min(a.buys[1].listed or 20, 20) > b.profit * math.min(b.buys[1].listed or 20, 20)
  end)
  return flips
end
ns.FindVendorFlips = ns.Timed("Finding vendor flips", ns.FindVendorFlips)

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
  if s.share > 0 then lines[#lines + 1] = ("Auction sales reserve %s for one lost 24-hour deposit before selling; estimates when the live quote is unavailable."):format(ns.Money(s.deposit or 0)) end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Pieces for the Shuffles table
---------------------------------------------------------------------------
local PROF_ICONS = {
  Alchemy = "Interface\\Icons\\Trade_Alchemy", Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
  Enchanting = "Interface\\Icons\\Trade_Engraving", Engineering = "Interface\\Icons\\Trade_Engineering",
  Leatherworking = "Interface\\Icons\\Trade_LeatherWorking", Tailoring = "Interface\\Icons\\Trade_Tailoring",
  Cooking = "Interface\\Icons\\INV_Misc_Food_15", ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
  Fishing = "Interface\\Icons\\Trade_Fishing", Mining = "Interface\\Icons\\Trade_Mining",
}
local DISENCHANT_ICON = "Interface\\Icons\\Spell_Holy_RemoveCurse"
local VENDOR_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local AH_ICON = "Interface\\Icons\\INV_Misc_Coin_04"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function ns:ItemIcon(id)
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if not icon and GetItemIcon then icon = GetItemIcon(id) end
  return icon or UNKNOWN_ICON
end

-- One { icon, text } per step, following the main path. After disenchanting it follows
-- the material worth the most.
function ns:StepIcons(o)
  local out = {}
  local function walk(o)
    if o.kind == "ah" then out[#out + 1] = { AH_ICON, "Sell on the auction house" }; return end
    if o.kind == "vendor" then out[#out + 1] = { VENDOR_ICON, "Sell to a vendor" }; return end
    if o.kind == "disenchant" then
      out[#out + 1] = { DISENCHANT_ICON, "Disenchant" }
      local top
      for _, m in ipairs(o.mats) do
        if not top or m.opt.value * m.count > top.opt.value * top.count then top = m end
      end
      if top then walk(top.opt) end
      return
    end
    if o.kind == "craft" then
      out[#out + 1] = { PROF_ICONS[o.prof or ""] or ns:ItemIcon(o.rec.out), stepText(o) }
    else
      out[#out + 1] = { ns:ItemIcon(o.next.id), o.step }
    end
    walk(o.next)
  end
  walk(o)
  return out
end

-- What to buy: { id, qty, price, listed }. For a group, one line per item, cheapest first.
function ns:ShuffleBuys(s)
  local out = {}
  if s.group then
    for _, m in ipairs(s.members) do
      out[#out + 1] = { id = m.id, qty = 1, price = m.cost, listed = m.buys[1].listed }
    end
  else
    for _, b in ipairs(s.buys) do
      out[#out + 1] = { id = b.id, qty = b.qty, price = b.price, listed = b.listed }
    end
  end
  return out
end

-- Purchases for the selected route, including extra materials at later crafts.
-- A disenchant group consists of alternatives: use its cheapest member, never buy
-- every alternative. Quantities after disenchanting are averages, rounded up once.
function ns:ShuffleShoppingItems(s, runs)
  local route = s.group and s.members[1] or s
  local byID, order = {}, {}
  local function add(id, qty, cap)
    if not id or not qty or qty <= 0 then return end
    local b = byID[id]
    if not b then b = { id = id, qty = 0, cap = cap }; byID[id] = b; order[#order + 1] = b end
    b.qty = b.qty + qty
    if cap then b.cap = b.cap and math.min(b.cap, cap) or cap end
  end
  for i, b in ipairs(route.buys or {}) do
    local cap = b.price
    if i == 1 then cap = route.maxBuy end
    add(b.id, (b.qty or 1) * runs, cap)
  end
  local function extras(o, amount, first)
    if not o then return end
    if o.kind == "craft" then
      local crafts = amount / math.max(o.units or 1, 1)
      if not first then
        for _, b in ipairs(o.buys or {}) do add(b.id, b.qty * crafts, b.cost) end
      end
      extras(o.next, crafts * (o.rec.oq or 1))
    elseif o.kind == "convert" then
      extras(o.next, amount * o.per)
    elseif o.kind == "disenchant" then
      for _, m in ipairs(o.mats or {}) do extras(m.opt, amount * m.count) end
    end
  end
  extras(route.opt, (route.units or 1) * runs, true)
  for _, b in ipairs(order) do
    b.qty = math.ceil(b.qty)
    -- The route's cap, independent of today's depth on the price ladder. Other
    -- materials keep the cost assumptions already deducted from the root cap.
    b.max = math.max(0, math.floor(b.cap or 0))
  end
  return order
end

-- Identify the chosen steps without saving cached valuations or character tables.
function ns:ShuffleRouteKey(o)
  if not o then return "" end
  local key = o.kind .. ":" .. (o.id or "")
  if o.rec then key = key .. ":" .. (o.recipeID or o.rec.n or "") .. ":" .. (o.rec.out or "") end
  if o.per then key = key .. ":" .. o.per end
  if o.next then key = key .. ">" .. ns:ShuffleRouteKey(o.next) end
  for _, m in ipairs(o.mats or {}) do key = key .. "|" .. m.id .. ":" .. ns:ShuffleRouteKey(m.opt) end
  return key
end

function ns:ShuffleShoppingSource(s)
  local route = s.group and s.members[1] or s
  local path = ns:ShuffleRouteKey(route.opt)
  return { id = route.id, route = path, name = ns:ShuffleName(s), key = route.id .. ":" .. path }
end

-- Revalue the same route; never silently switch to a different recipe or alternative.
-- A route no longer available leaves its items off until it can be valued again.
function ns:RefreshShuffleShoppingSource(source)
  for _, o in ipairs(ns:Options(source.id)) do
    if ns:ShuffleRouteKey(o) == source.route then
      local s
      if o.kind == "vendor" then
        s = { id = source.id, units = 1, opt = o, maxBuy = ns:VendorFlipLimit(o.value),
          buys = { { id = source.id, qty = 1 } } }
      else
        local cost, listed = buyInfo(source.id, ns.db.prices[ns.MarketKey()] or {})
        if cost then
          -- build checks the same costs and safety margin as the displayed shuffle.
          s = build(source.id, o, cost, listed, ns.db.prices[ns.MarketKey()] or {},
            (ns.db.settings.margin or 10) / 100, ns.db.settings.actionSeconds or 3)
        end
      end
      local caps = {}
      for _, b in ipairs(s and ns:ShuffleShoppingItems(s, 1) or {}) do caps[b.id] = b.max end
      return caps
    end
  end
  return {}
end

-- The detail panel is drawn in UI.lua. Keep its shopping controls here so the
-- shuffle and vendor-flip panels share the same choices and behavior.
function ns:ShuffleShoppingControls(d, s, width, top)
  local T = ns.Theme
  if not d.shopping then
    local c = CreateFrame("Frame", nil, d)
    d.shopping = c
    c.pick = T:Dropdown(c, 260, function(value) c.target = value end)
    c.pick:SetPoint("TOPLEFT", 0, 0)
    c.amount = T:Number(c, { min = 1, max = 10000, step = 1 }, function(value)
      c.runs = math.floor(value)
      c.amount:SetValue(c.runs)
    end)
    c.amount:SetPoint("TOPRIGHT", 0, 0)
    c.label = T:Text(c, 11, T.dim)
    c.label:SetPoint("RIGHT", c.amount, "LEFT", -8, 0)
    c.add = T:Button(c, "Add to shopping list", 180, function()
      local target = c.target ~= "new" and c.target or nil
      local list, err = ns:ShuffleToShoppingList(d.shuffle, target, c.runs)
      if not list then ns:Print(err); return end
      c.target = list
      ns:ShuffleShoppingControls(d, d.shuffle, d:GetWidth(), c.top)
    end)
    c.add:SetPoint("TOPLEFT", 0, -30)
    c.note = T:Text(c, 11, T.dim)
    c.note:SetPoint("TOPLEFT", c.add, "TOPRIGHT", 10, -2)
    c.note:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    c.note:SetJustifyH("LEFT")
    c.note:SetText("Adds items and Up to prices; typed prices stay.")
    c.group = T:Text(c, 11, T.dim)
    c.group:SetPoint("TOPLEFT", 0, -60)
    c.group:SetPoint("RIGHT", 0, 0)
    c.group:SetJustifyH("LEFT")
    c.group:SetWordWrap(false)
  end
  local c = d.shopping
  if c.key ~= s.key then c.key, c.runs, c.target = s.key, 1, "new" end
  local opts = { { value = "new", label = "New list: " .. ns:ShuffleName(s) } }
  local selected = c.target == "new"
  for _, l in ipairs(ns:ShoppingLists()) do
    if not l.countHave and not l.temp and not l.crateID and not l.anyPrice then
      opts[#opts + 1] = { value = l, label = l.name }
      if l == c.target then selected = true end
    end
  end
  if not selected then c.target = "new" end
  c.pick:SetOptions(opts)
  c.pick:SetValue(c.target)
  c.pick:SetWidth(math.max(190, width - 250))
  c.amount:SetValue(c.runs)
  c.label:SetText(s.single and "Items" or "Crafts")
  c.top = top
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", 14, -top)
  c:SetWidth(width - 28)
  c:SetHeight(80)
  c.group:SetText(s.group and ("Uses the cheapest option: " .. ns.ItemName(s.members[1].id)) or "")
  c:Show()
  return s.group and 84 or 66
end

-- The numbered steps as text.
function ns:ShuffleSteps(s)
  local lines = {}
  stepLines(s.opt, lines, { n = 0 }, true)
  if s.share > 0 then lines[#lines + 1] = ("Auction sales reserve %s for one lost 24-hour deposit before selling; estimates when the live quote is unavailable."):format(ns.Money(s.deposit or 0)) end
  return table.concat(lines, "\n")
end

-- The buying limit and profit, as one line.
function ns:ShuffleProfitLine(s)
  local limit = (s.single or s.group) and ("Buy at up to %s. "):format(ns.Money(s.maxBuy)) or ""
  local hour = s.opt.kind == "vendor" and "" or (", about %s an hour"):format(ns.Money(s.perHour))
  return ("%sProfit %s %s (%d%%)%s."):format(
    limit, ns.Money(s.profit), s.single and "each" or "per craft", returnPct(s), hour)
end

-- How many times the shuffle could be done profitably with what's listed now, limited
-- by the scarcest thing bought on the auction house. Only listings cheap enough count:
-- up to "buy at up to" for the main item, up to the price the sums assumed for other
-- materials. For a group, every member listed cheaply enough counts. nil when
-- everything comes from vendors (no limit).
function ns:ShuffleRuns(s)
  if s.group then
    local n = 0
    for _, m in ipairs(s.members) do n = n + (ns:ListedAtOrBelow(m.id, s.maxBuy) or 0) end
    return n
  end
  local runs
  for i, b in ipairs(s.buys) do
    if b.listed then
      local limit = (i == 1) and s.maxBuy or b.price
      local avail = ns:ListedAtOrBelow(b.id, limit) or b.listed
      local r = math.floor(avail / math.max(b.qty or 1, 1))
      runs = runs and math.min(runs, r) or r
    end
  end
  return runs
end

-- (Work it's helpers, ShuffleItems, ShuffleActions and ShuffleDisenchantTargets, went
-- with the Work it window: owner, October 4; its jobs moved to shopping lists and the
-- Buy queue.)

-- A short name for the table: the item or recipe, without the steps.
function ns:ShuffleName(s)
  if s.group then return ("%s (%d)"):format(s.group, #s.members) end
  if s.single then return itemName(s.id) end
  return (s.opt.rec and s.opt.rec.n) or ns:ShuffleTitle(s)
end

function ns:ShuffleReturn(s) return s.cost > 0 and s.profit / s.cost or 0 end

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
-- What was already announced, kept until you log out (a /reload used to forget it,
-- so every deal and flip chimed again: owner's test, October 4). Per auction house:
-- ns.db.alertsSeen[marketKey] = { deals = { [kind .. itemID] = price }, flips = { [itemID] = cost } }.
local function seen(kind)
  ns.db.alertsSeen = ns.db.alertsSeen or {}
  local m = ns.MarketKey()
  ns.db.alertsSeen[m] = ns.db.alertsSeen[m] or { deals = {}, flips = {} }
  return ns.db.alertsSeen[m][kind]
end
ns:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if isLogin == true and not isReload and ns.db then ns.db.alertsSeen = nil end
end)

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
    -- "tsm" means TSM only, unless TSM isn't installed at all.
    if src == "tsm" and TSM_API then return end
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
  local from
  if not TSM_API then
    from = src == "local" and "this addon's scans" or "this addon's scans, as TSM isn't installed"
  elseif src == "tsm" then
    from = "TSM's prices"
  elseif src == "local" then
    from = "this addon's scans"
  else
    from = "TSM's prices, or this addon's scans where TSM has none"
  end
  local usualMin = (s.dealUsualMin or 0) > 0 and (" and at least " .. ns.Money(s.dealUsualMin) .. " profit each on resale") or ""
  return ("%g%% or more below the usual cheapest price over %s (from %s)%s, or %s"):format(
    s.dealUsualPct or 20, ns.WINDOW_NAMES[s.dealWindow or "all"] or "all time", from, usualMin, vendor)
end

---------------------------------------------------------------------------
-- Below-usual-price deals are a bet that the item resells, so each one is judged
-- (owner, September 30: 546 "deals" in one scan, some absurd, like a shirt at 1s
-- "usually 23g" from one lone listing):
--   * enough days of scans, and day-to-day prices that don't jump around;
--   * the price is well below the usual cheapest price (see judgeUsual);
--   * resale at the usual cheapest price or the next listing above the cheap ones,
--     whichever is lower, less the auction house cut, must beat dealUsualMin each;
--   * warnings (lower sureness) when usually only one is listed, when nothing else is
--     listed to compare, and for gear whose versions sell at different prices.
-- Sureness is "good", "fair" or "thin"; thin deals are hidden unless dealShowThin.
---------------------------------------------------------------------------
local DEAL_MIN_DAYS = 4        -- fewer days of scans than this is thin data
local DEAL_GOOD_DAYS = 7       -- this many or more (with steady prices) can be good
local STEADY, JUMPY = 1.6, 2.5 -- spread (upper quarter / lower quarter of daily prices)
local LEVELS = { "thin", "fair", "good" }
local LEVEL = { thin = 1, fair = 2, good = 3 }

local function lower(level) return LEVELS[math.max(1, LEVEL[level] - 1)] end

-- Judges one usual-price deal. Returns the deal table, or nil if it isn't one.
-- Measured against the usual CHEAPEST price, not the typical one (owner's test,
-- October 1: Gray Woolen Robe at 40s showed as 27% below a usual 54s 80c, while its
-- cheapest listing was 38s on a normal day, so 40s was no bargain). The typical price
-- (average of the cheapest 20 listed) includes dearer listings, so cheapest-vs-typical
-- made nearly everything look like a deal.
--   ref    = usual cheapest (median of each day's cheapest), or the typical price if
--            lower or if there's no own history (TSM only)
--   resell = the lowest of ref, the typical price and the next listing up: a price
--            you can list at and expect to sell
--   only listings cheap enough to clear dealUsualMin profit each at that resale count
local function judgeUsual(id, rec)
  local s = ns.db.settings
  local usual, basis = ns:DealUsualPrice(id)
  if not usual then return end
  local pct = (s.dealUsualPct or 20) / 100
  -- Quick out: ref is never above the typical price, so if this fails, all would.
  if rec.m > usual * (1 - pct) then return end
  local stats = ns:PriceStats(id, s.dealWindow)
  local ref = usual
  if stats and stats.low and stats.low < ref then ref = stats.low end
  local limit = ref * (1 - pct)
  if rec.m > limit then return end

  local resell = ref
  -- The next listing above the cheap ones: reselling today means pricing under it.
  local nextUp
  if rec.l then
    for p in rec.l:gmatch("(%d+):%d+") do
      p = tonumber(p)
      if p > limit then nextUp = p; break end
    end
  end
  if nextUp and nextUp < resell then resell = nextUp end
  -- Only buy listings that still make the minimum profit after the cut.
  local net, deposit = ns:AuctionSaleValue(id, resell)
  local buyLimit = math.min(limit, net - (s.dealUsualMin or 0))
  if buyLimit <= 0 or rec.m > buyLimit then return end
  local n, cost = ns:CheapListings(id, buyLimit)
  if not n or n == 0 then return end
  cost = cost or rec.m
  local each = net - cost

  local d = { kind = "usual", id = id, price = rec.m, worth = ref, typical = usual, listed = n, basis = basis, cost = cost,
    limit = buyLimit, resell = resell, deposit = deposit, nextUp = nextUp, each = each, total = each * n, stats = stats,
    pct = 1 - rec.m / ref, t = rec.t, warnings = {} }

  -- How sure: from this addon's own history where there is some (TSM alone is "fair").
  local level, spread = "fair", nil
  if stats and stats.q1 and stats.q1 > 0 then spread = stats.q3 / stats.q1 end
  d.spread = spread
  if basis == "ledger" or stats then
    local points = stats and stats.points or 0
    if points >= DEAL_GOOD_DAYS and spread and spread <= STEADY then level = "good"
    elseif points >= DEAL_MIN_DAYS and spread and spread <= JUMPY then level = "fair"
    elseif basis == "ledger" then level = "thin"
    end
    if basis == "TSM" and level == "thin" then level = "fair" end
    if points < DEAL_MIN_DAYS then
      d.warnings[#d.warnings + 1] = ("Only %d %s of your own scans."):format(points, points == 1 and "day" or "days")
    elseif spread and spread > JUMPY then
      d.warnings[#d.warnings + 1] = "Prices jump around a lot from day to day."
    end
  end
  if stats and stats.listed and stats.listed <= 1 then
    level = lower(level)
    d.warnings[#d.warnings + 1] = "Usually only one is listed: it may sell slowly, or the usual price may be one hopeful seller."
  end
  -- A deal is a few listings priced below the rest. When half or more of what's listed
  -- (or of what's usually listed) is this cheap, the price has dropped, not a bargain
  -- (owner's screenshot, October 2: 2,381 Greater Magic Essence at 1s 30c "usually"
  -- 20s 90c, from when essences were scarce early in the beta).
  local usualListed = stats and stats.listed
  if n >= 5 and ((rec.q and n >= rec.q * 0.5) or (usualListed and n >= usualListed * 0.5)) then
    level = "thin"
    d.moved = true
    d.warnings[#d.warnings + 1] = "Most of what's listed is this cheap: the price has dropped, it's not a one-off bargain."
  end
  -- Sell speed (History.lua SellSpeed): listings bought between full scans, from time
  -- left, rated against items of the same kind. A deal that doesn't sell isn't one.
  local sp = ns.SellSpeed and ns:SellSpeed(id)
  if sp then
    d.speed, d.soldPerDay, d.soldHours = sp, sp.perDay, sp.hours
    if sp.key == "none" or sp.key == "slow" then
      level = lower(level)
      d.warnings[#d.warnings + 1] = sp.key == "none"
        and ("None bought in %d hours of scans: it may not sell."):format(math.floor(sp.hours))
        or "It sells slowly for how many are listed."
    end
  end
  if not nextUp then
    if level == "good" then level = "fair" end
    d.warnings[#d.warnings + 1] = "Nothing else is listed right now to compare with."
  end
  if rec.sx then
    if level == "good" then level = "fair" end
    d.warnings[#d.warnings + 1] = "Gear: versions with different stats sell at different prices."
  end
  d.level = level
  return d
end

-- A usual-price deal the Deals tab and alerts show: sure enough and worth the trouble.
function ns:DealShown(d)
  local s = ns.db.settings
  if d.kind ~= "usual" then return true end
  if d.each < (s.dealUsualMin or 0) then return false end
  return d.level ~= "thin" or s.dealShowThin
end

-- Returns deals, biggest saving first: { kind = "usual" | "vendor", id, price, worth, listed }.
-- Usual-price deals carry the judgement above. maxAge: how old a price may be
-- (default 10 minutes, for alerts right after a scan).
-- Each item's verdict is kept until its price, the day, a setting or the 30-second
-- deposit refresh changes (a live quote can become available without a new scan): judging
-- all 2,500 items took up to 0.2 s per Deals tab redraw (/fl perf, October 3).
local judged, judgedSig = {}, nil
function ns:FindDeals(maxAge)
  local s = ns.db.settings
  local market = ns.db.prices[ns.MarketKey()] or {}
  local vendorPct, vendorMin = (s.dealVendorPct or 10) / 100, s.dealVendorMin or 0
  local sig = table.concat({ ns.MarketKey(), ns.LocalDay and ns.LocalDay() or 0, tostring(s.dealUsualPct),
    tostring(s.dealWindow), tostring(s.dealUsualMin), tostring(s.ahCut), tostring(s.dealHistory),
    tostring(s.source), tostring(ns.depositRevision or 0),
    tostring(math.floor(GetTime() / 30)) }, "|")
  if sig ~= judgedSig then judged, judgedSig = {}, sig end
  local now, deals = time(), {}
  for id, rec in pairs(market) do
    local price = rec.m
    if price and not rec.none and now - (rec.t or 0) <= (maxAge or DEAL_RECENT) then
      -- Quick look at the vendor price before the full check, which reads the tooltip.
      local raw = select(11, ns.GetItemInfo(id)) or ns.db.vendorSell[id]
      local sell = (raw == nil or raw > price) and ns:GetSellPrice(id)
      if sell and sell > price then
        local profit = sell - price
        if profit / sell >= vendorPct and profit >= vendorMin then
          -- How many are cheap enough for this deal, not everything listed.
          local n = ns:CheapListings(id, math.min(sell * (1 - vendorPct), sell - vendorMin))
          deals[#deals + 1] = { kind = "vendor", id = id, price = price, worth = sell, listed = n or rec.q }
        end
      end
      local j = judged[id]
      if not (j and j.t == rec.t and j.m == price) then
        j = { t = rec.t, m = price, d = judgeUsual(id, rec) or false }
        judged[id] = j
      end
      if j.d then deals[#deals + 1] = j.d end
    end
  end
  table.sort(deals, function(a, b) return a.worth - a.price > b.worth - b.price end)
  return deals
end

ns.DEAL_LEVEL_TEXT = {
  good = "|cff7fd39cGood|r", fair = "|cffffd100Fair|r", thin = "|cffee8597Thin|r",
}

ns.DEAL_LEVEL_WHY = {
  good = "Steady prices over a week or more.",
  fair = "Some data, but not a lot, or a warning below.",
  thin = "Too little data, or prices that jump around.",
}

-- Why a usual-price deal is a deal, for the Deals tab tooltip, in short sections.
-- Entries: { head = text } a section heading, { left, right } a label and value,
-- { note = text, color = {r, g, b} } a wrapped line.
function ns:DealExplain(d)
  local s, L = ns.db.settings, {}
  local st = d.stats
  local function pair(l, r) L[#L + 1] = { l, r } end
  local function green(v) return (v > 0 and "|cff7fd39c" or "|cffee8597") .. ns.Money(math.max(0, v)) .. "|r" end

  L[#L + 1] = { head = "Right now" }
  pair("Cheapest", ns.Money(d.price))
  pair(("Worth buying, up to %s"):format(ns.Money(d.limit)), d.listed > 1 and ("%d, average %s"):format(d.listed, ns.Money(d.cost)) or "1")
  pair("Next listing up", d.nextUp and ns.Money(d.nextUp) or "none")

  L[#L + 1] = { head = "Usually (" .. (ns.WINDOW_NAMES[s.dealWindow or "all"] or "all time") .. ")" }
  -- The deal is measured against the usual cheapest price (see judgeUsual).
  pair("Usual cheapest", ns.Money(d.worth))
  if d.basis == "TSM" then
    pair("TSM price", ns.Money(d.typical))
  end
  if st then
    pair("Typical price", ns.Money(st.usual))
    pair("Based on", ("%d %s of your scans"):format(st.points, st.points == 1 and "day" or "days"))
    if st.points >= 4 and st.q1 ~= st.q3 then pair("Typical, most days", ns.Money(st.q1) .. " to " .. ns.Money(st.q3)) end
    if st.listed then pair("Listed each day", tostring(st.listed)) end
  end
  if d.speed then
    pair("Sells", ns:SellSpeedText(d.speed))
    pair("Judged on", ("%d h of scans compared"):format(math.floor(d.speed.hours + 0.5)))
  end
  -- Quest items sell to leveling players, once per character (QuestItems.lua).
  if ns.db.settings.tipQuest ~= false and ns.IsQuestItem and ns:IsQuestItem(d.id) then
    local needs = ns:QuestNeeds(d.id)
    local q = needs and needs[1]
    pair("Quest item", q and ("%s, level %d"):format(q.quest, q.level) or "for the other faction's quests")
  end

  L[#L + 1] = { head = "If you resell" }
  pair(d.nextUp and d.nextUp < d.worth and "Resell at (under the next listing)" or "Resell at (usual cheapest)", ns.Money(d.resell))
  pair("One lost 24h deposit, each", ns.Money(d.deposit or 0))
  pair(("Profit each, after %g%% cut and reserve"):format(ns:AHCut() * 100), green(d.each))
  if d.listed > 1 then pair(("Profit for all %d"):format(d.listed), green(d.total)) end

  L[#L + 1] = { head = "How sure: " .. (ns.DEAL_LEVEL_TEXT[d.level] or d.level) }
  L[#L + 1] = { note = ns.DEAL_LEVEL_WHY[d.level] or "", color = { 0.75, 0.75, 0.75 } }
  for _, w in ipairs(d.warnings) do L[#L + 1] = { note = w, color = { 1, 0.6, 0.3 } } end
  L[#L + 1] = { note = "The auction house shows what's listed, not what sold. \"Sells\" counts listings that vanished before they could have expired (bought, or cancelled): a low estimate that gets better the more full scans you run, fastest with Watch flips.",
    color = { 0.5, 0.5, 0.5 } }
  return L
end

local function printDeal(d)
  if d.kind == "vendor" then
    print(("    |cffffffff%s|r at %s, a vendor pays %s (%s profit each). %s listed."):format(
      itemName(d.id), ns.Money(d.price), ns.Money(d.worth), ns.Money(d.worth - d.price), d.listed or "?"))
  else
    print(("    |cffffffff%s|r at %s, usually %s (%d%% below, %s). %s listed, about %s profit each. %s."):format(
      itemName(d.id), ns.Money(d.price), ns.Money(d.worth),
      math.floor(d.pct * 100 + 0.5), d.basis or "ledger", d.listed or "?", ns.Money(math.max(0, d.each)),
      ns.DEAL_LEVEL_TEXT[d.level] or d.level))
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

-- Vendor flip alerts (owner, September 30: Roasted Boar Meat showed up on the tab but
-- never chimed). They follow the Vendor flips tab exactly (ns:VendorFlip), fire as soon
-- as an item's price is saved (ns:CheckFlip, not only at the end of a 2-minute watch
-- pass), and an item that stops being a flip is forgotten, so it alerts again if it
-- comes back.
local pendingFlips, flipTimer = {}, false

-- Chime, screen message and chat for new vendor flips and below-usual-price deals.
local function announce(all, usual)
  if #all == 0 and usual == 0 then return end
  -- The Buy queue takes them in at once, even ones it set aside a minute ago (BuyQueue.lua).
  if #all > 0 and ns.FlipsAnnounced then ns:FlipsAnnounced(all) end
  -- Flips you can't afford even one of don't chime or show on screen; chat still says
  -- so (Magic, October 3: "found X, but can't currently afford it").
  local cash, flips, poor = GetMoney(), {}, {}
  local market = ns.db.prices[ns.MarketKey()] or {}
  for _, f in ipairs(all) do
    local one = (market[f.id] and market[f.id].m) or f.cost
    if one and one > cash then poor[#poor + 1] = { f = f, one = one } else flips[#flips + 1] = f end
  end
  for _, p in ipairs(poor) do
    ns:Print(("Found a vendor flip: %s (vendor pays %s), but you can't afford it yet: %s each, you have %s."):format(
      itemName(p.f.id), ns.Money(p.f.opt.value), ns.Money(p.one), ns.Money(cash)))
  end
  if #flips == 0 and usual == 0 then return end
  local text
  if #flips > 0 then
    local f = flips[1]
    text = ("Vendor flip: %s at %s (vendor pays %s)"):format(itemName(f.id), ns.Money(f.cost), ns.Money(f.opt.value))
    if #flips > 1 then text = text .. (" and %d more"):format(#flips - 1) end
  else
    text = ("%d new %s below the usual price"):format(usual, usual == 1 and "deal" or "deals")
  end
  -- Off in Settings if it covers your windows (Magic, October 3: it landed on the Buy queue).
  if ns.db.settings.dealScreen ~= false and RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, text, { r = 0.05, g = 0.82, b = 0.62 })
  end
  if ns.db.settings.dealSound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
  end
  if #flips > 0 then
    -- Only after a full scan, not the flip watch's quick checks (ns.fullScanDone).
    if ns.db.settings.openFlips and ns.OpenFlips and ns.fullScanDone then ns:OpenFlips() end
    for _, f in ipairs(flips) do
      ns:Print(("New vendor flip: %s, %d at %s or less (vendor pays %s). It's in the Buy queue."):format(
        itemName(f.id), f.buys[1].listed or 1, ns.Money(f.maxBuy), ns.Money(f.opt.value)))
    end
  end
  if usual > 0 then
    ns:Print(("%d new %s below the usual price: see the Deals tab (/fl deals)."):format(
      usual, usual == 1 and "deal" or "deals"))
  end
end

-- One item's price was just saved (watch pass or your own search): alert at once if
-- it's a new vendor flip. Flips found within a second are announced together.
function ns:CheckFlip(id)
  local flipAlerted = seen("flips")
  local f = ns:VendorFlip(id)
  if not f then flipAlerted[id] = nil; return end
  if flipAlerted[id] and f.cost >= flipAlerted[id] then return end
  flipAlerted[id] = f.cost
  pendingFlips[#pendingFlips + 1] = f
  if not flipTimer then
    flipTimer = true
    C_Timer.After(1, function()
      flipTimer = false
      local list = pendingFlips
      pendingFlips = {}
      announce(list, 0)
    end)
  end
end

-- Called when a scan finishes: every vendor flip on the tab not yet alerted, and
-- below-usual-price deals not already alerted at this price or lower.
function ns:CheckDeals()
  ns:InvalidateValues(true)   -- the scan just changed prices
  if ns.RefreshDealsIfShown then ns:RefreshDealsIfShown() end
  local flipAlerted, alerted = seen("flips"), seen("deals")
  local now, flips = time(), {}
  for id in pairs(ns.db.prices[ns.MarketKey()] or {}) do
    local f = ns:VendorFlip(id)
    if not f then
      flipAlerted[id] = nil
    elseif now - (f.t or 0) <= DEAL_RECENT and (not flipAlerted[id] or f.cost < flipAlerted[id]) then
      flipAlerted[id] = f.cost
      flips[#flips + 1] = f
    end
  end
  table.sort(flips, function(a, b) return a.profit > b.profit end)
  local usual = 0
  for _, d in ipairs(ns:FindDeals()) do
    local key = d.kind .. d.id
    if d.kind == "usual" and ns:DealShown(d) and (not alerted[key] or d.price < alerted[key]) then
      alerted[key] = d.price
      usual = usual + 1
    end
  end
  announce(flips, usual)
end

-- /fl deals list: every current deal shown on the tabs, alerted or not.
function ns:PrintDeals()
  local deals = {}
  for _, d in ipairs(ns:FindDeals()) do
    if ns:DealShown(d) then deals[#deals + 1] = d end
  end
  ns:Print("Deals are listings " .. ns:DealRules() .. ".")
  if #deals == 0 then
    print("  None right now, from scans in the last 10 minutes. Usual-price deals need 4 days of scans first.")
    return
  end
  printGrouped(deals, 20)
end
ns.FindShuffles = ns.Timed("Finding shuffles", ns.FindShuffles)
ns.CheckDeals = ns.Timed("Deal check", ns.CheckDeals)
