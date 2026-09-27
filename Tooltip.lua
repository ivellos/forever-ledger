local _, ns = ...

local LR, LG, LB = 0.73, 0.64, 1.0   -- label colour

local function addLines(tt, id)
  if not id or not ns.db or not ns.db.settings.tooltip then return end
  ns:RememberItem(id)

  local price, src, t, rec = ns:GetPrice(id)
  if price then
    local right = ns.Money(price)
    local age = t and ns.Age(t) or ""
    if age ~= "" then right = right .. " |cff999999" .. age .. "|r" end
    tt:AddDoubleLine("Ledger price (" .. (src or "?") .. ")", right, LR, LG, LB, 1, 1, 1)
    if rec and rec.m and rec.a and rec.m ~= rec.a and src ~= "Auctionator" and src ~= "TSM" and src ~= "Auctioneer" then
      tt:AddDoubleLine("  cheapest listing", ns.Money(rec.m) .. (rec.q and (" |cff999999" .. rec.q .. " listed|r") or ""), 0.7, 0.7, 0.7, 1, 1, 1)
    end
  elseif rec and rec.none then
    tt:AddDoubleLine("Ledger price", "none listed " .. ns.Age(rec.t), LR, LG, LB, 0.7, 0.7, 0.7)
  end

  local buy = ns.db.vendorBuy[id]
  if buy then
    tt:AddDoubleLine("Vendor sells it for", ns.Money(buy.p) .. (buy.lim and " |cff999999limited|r" or ""), LR, LG, LB, 1, 1, 1)
  end

  local best, options = ns:GetValue(id)
  if best then
    tt:AddDoubleLine("Worth to you", ns.Money(best), LR, LG, LB, 1, 1, 1)
    for i, o in ipairs(options) do
      if i == 1 then
        tt:AddDoubleLine("  " .. o.label, ns.Money(o.value), 0.5, 0.83, 0.61, 0.5, 0.83, 0.61)
      else
        tt:AddDoubleLine("  " .. o.label, ns.Money(o.value), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
      end
    end
  end

  -- Green when the ledger price is already at or below it.
  local maxBuy = ns:BuyAtOrBelow(id)
  if maxBuy then
    if price and price <= maxBuy then
      tt:AddDoubleLine("Buy at or below", ns.Money(maxBuy), LR, LG, LB, 0.5, 0.83, 0.61)
    else
      tt:AddDoubleLine("Buy at or below", ns.Money(maxBuy), LR, LG, LB, 1, 1, 1)
    end
  end

  local yield = ns:DisenchantYield(id)
  if yield then
    local parts = {}
    for _, y in ipairs(yield) do
      parts[#parts + 1] = ("%.2f %s"):format(y[2], ns:DisenchantMaterialName(y[1]))
    end
    tt:AddLine("Disenchants to about " .. table.concat(parts, ", "), LR, LG, LB, true)
  end

  local users = ns.usage and ns.usage[id]
  if users then
    local shown = 0
    for k, count in pairs(users) do
      if shown >= 4 then break end
      local name, prof = k:match("^(.-)|(.*)$")
      tt:AddLine(("Used by %s: %s, %d recipe%s"):format(name or "?", prof or "?", count, count == 1 and "" or "s"), LR, LG, LB)
      shown = shown + 1
    end
  end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
    if tt == GameTooltip or tt == ItemRefTooltip then addLines(tt, data and data.id) end
  end)
else
  local function hook(tt)
    local _, link = tt:GetItem()
    addLines(tt, ns.ItemIDFromLink(link))
  end
  GameTooltip:HookScript("OnTooltipSetItem", hook)
  ItemRefTooltip:HookScript("OnTooltipSetItem", hook)
end

addLines = ns.Timed("Tooltip lines", addLines)   -- for /fl perf
