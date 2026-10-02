local _, ns = ...

local LR, LG, LB = 0.73, 0.64, 1.0   -- label colour

-- What shows is set in Settings (tester feedback: the tooltip grew long): compact mode
-- shows one line and the rest while Shift is held; each section can be turned off; and
-- "Worth to you" lists only the best few ways.
-- The item on GameTooltip right now, and whether its full lines are already there
-- (compact mode: pressing Shift adds them to the tooltip that's showing).
local shownID, shownFull
local debugLinks = {}   -- tooltip links already shown in debug

local function addLines(tt, id, forceFull)
  local s = ns.db and ns.db.settings
  if not id or not s or not s.tooltip then return end
  ns:RememberItem(id)
  local full = forceFull or s.tipMode ~= "compact" or IsShiftKeyDown()
  local function on(key) return s[key] ~= false end
  if tt == GameTooltip then shownID, shownFull = id, full end

  local price, src, t, rec = ns:GetPrice(id)
  if not full then
    local best, options = ns:GetValue(id)
    if best then
      local how = options and options[1] and options[1].label
      tt:AddDoubleLine("Worth to you" .. (how and (" |cff999999(" .. how .. ")|r") or ""), ns.Money(best), LR, LG, LB, 1, 1, 1)
    elseif price then
      tt:AddDoubleLine("Ledger price", ns.Money(price), LR, LG, LB, 1, 1, 1)
    else
      return
    end
    tt:AddLine("Hold Shift for Forever Ledger details", 0.5, 0.5, 0.5)
    return
  end

  if price and on("tipPrice") then
    local right = ns.Money(price)
    local age = t and ns.Age(t) or ""
    if age ~= "" then right = right .. " |cff999999" .. age .. "|r" end
    tt:AddDoubleLine("Ledger price (" .. (src or "?") .. ")", right, LR, LG, LB, 1, 1, 1)
    if rec and rec.m and rec.a and rec.m ~= rec.a and src ~= "Auctionator" and src ~= "TSM" and src ~= "Auctioneer" then
      tt:AddDoubleLine("  cheapest listing", ns.Money(rec.m) .. (rec.q and (" |cff999999" .. rec.q .. " listed|r") or ""), 0.7, 0.7, 0.7, 1, 1, 1)
    end
  elseif rec and rec.none and on("tipPrice") then
    tt:AddDoubleLine("Ledger price", "none listed " .. ns.Age(rec.t), LR, LG, LB, 0.7, 0.7, 0.7)
  end

  -- How fast it sells, once there are enough scans to say (History.lua SellSpeed).
  if on("tipSpeed") and ns.SellSpeed then
    local ok, sp = pcall(ns.SellSpeed, ns, id)
    if ok and sp then tt:AddDoubleLine("Sells", ns:SellSpeedText(sp), LR, LG, LB, 1, 1, 1) end
  end

  -- Gear with random stats: the price of this exact version ("of the Eagle"). An auction
  -- house group ("Items in this group may vary") has no one version: its link carries a
  -- general bonus ID (3524, beta September 30) and the plain name, so it lists the
  -- cheapest versions on sale instead.
  if on("tipPrice") and tt.GetItem then
    local _, link = tt:GetItem()
    local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
    local suffix = ns:VersionOfLink(id, link)
    if suffix then
      local m, q = ns:SuffixPrice(id, suffix)
      local vname = ns:VersionName(suffix) or "these stats"
      if m and m > 0 then
        tt:AddDoubleLine("  this version (" .. vname .. ")", ns.Money(m) .. " |cff999999" .. q .. " listed|r",
          0.7, 0.7, 0.7, 1, 1, 1)
      elseif m == 0 then
        tt:AddDoubleLine("  this version (" .. vname .. ")", "none listed", 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
      end
    elseif rec and rec.sx then
      local list = {}
      for s, m, q in rec.sx:gmatch("(%-?%d+):(%d+):(%d+)") do
        list[#list + 1] = { s = tonumber(s), m = tonumber(m), q = tonumber(q) }
      end
      table.sort(list, function(a, b) return a.m < b.m end)
      if #list > 0 then
        tt:AddDoubleLine("  versions on sale", tostring(#list), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        for i = 1, math.min(3, #list) do
          local v = list[i]
          tt:AddDoubleLine("    " .. (ns:VersionName(v.s) or "other stats"), ns.Money(v.m) .. " |cff999999" .. v.q .. " listed|r",
            0.7, 0.7, 0.7, 1, 1, 1)
        end
      end
    end
    -- Checking tooltip links against the scan (/fl debug), once per link.
    if link and rec and rec.sx and ns.db.settings.debug and not debugLinks[link] then
      debugLinks[link] = true
      ns:Debug("Tooltip version:", link:match("%[(.-)%]") or "?", "=", link:match("item:[%-%d:]*") or "?",
        "version:", suffix or "none (group)", "scan has:", rec.sx:sub(1, 80))
    end
  end

  local buy = ns.db.vendorBuy[id]
  if buy and on("tipPrice") then
    -- The standing it was seen at, when above Neutral (reputation discounts).
    local standing = buy.rep and buy.rep > 4 and (_G["FACTION_STANDING_LABEL" .. buy.rep] or ("standing " .. buy.rep))
    tt:AddDoubleLine("Vendor sells it for", ns.Money(buy.p) .. (buy.lim and " |cff999999limited|r" or "")
      .. (standing and (" |cff999999at " .. standing .. "|r") or ""), LR, LG, LB, 1, 1, 1)
  end

  local best, options = ns:GetValue(id)
  if best and on("tipWorth") then
    tt:AddDoubleLine("Worth to you", ns.Money(best), LR, LG, LB, 1, 1, 1)
    local limit = s.tipOptions or 3
    for i, o in ipairs(options) do
      if i > limit then
        tt:AddLine(("  and %d more ways"):format(#options - limit), 0.5, 0.5, 0.5)
        break
      end
      if i == 1 then
        tt:AddDoubleLine("  " .. o.label, ns.Money(o.value), 0.5, 0.83, 0.61, 0.5, 0.83, 0.61)
      else
        tt:AddDoubleLine("  " .. o.label, ns.Money(o.value), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
      end
    end
  end

  -- Green when the ledger price is already at or below it.
  local maxBuy = on("tipBuy") and ns:BuyAtOrBelow(id)
  if maxBuy then
    if price and price <= maxBuy then
      tt:AddDoubleLine("Buy at or below", ns.Money(maxBuy), LR, LG, LB, 0.5, 0.83, 0.61)
    else
      tt:AddDoubleLine("Buy at or below", ns.Money(maxBuy), LR, LG, LB, 1, 1, 1)
    end
  end

  local crateLine = on("tipCrate") and ns.CrateTooltipLine and ns:CrateTooltipLine(id)
  if crateLine then tt:AddLine(crateLine, LR, LG, LB, true) end

  local yield = on("tipDisenchant") and ns:DisenchantYield(id)
  if yield then
    local parts = {}
    for _, y in ipairs(yield) do
      parts[#parts + 1] = ("%.2f %s"):format(y[2], ns:DisenchantMaterialName(y[1]))
    end
    tt:AddLine("Disenchants to about " .. table.concat(parts, ", "), LR, LG, LB, true)
  end

  local users = on("tipUsedBy") and ns.usage and ns.usage[id]
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

-- Compact mode: pressing Shift adds the full details to the tooltip that's showing.
-- (Tests 1 and 2: asking the game to redraw the tooltip, by RefreshData or by hovering
-- the item again, did nothing with the owner's EllesmereUI bags, so add the lines
-- directly.) They stay until the next hover; holding Shift before hovering shows them too.
GameTooltip:HookScript("OnHide", function() shownID, shownFull = nil, nil end)
if GameTooltip.HookScript then
  pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function() shownID, shownFull = nil, nil end)
end
ns:On("MODIFIER_STATE_CHANGED", function(key, down)
  if not (key and key:find("SHIFT")) then return end
  -- Pressed is 1 in most clients; some report true. Anything else is a release.
  local pressed = down == 1 or down == true
  if not pressed then return end   -- (tested September 30: works in bags with EllesmereUI)
  if not (ns.db and ns.db.settings.tipMode == "compact") then return end
  if not GameTooltip:IsShown() or not shownID or shownFull then return end
  addLines(GameTooltip, shownID, true)
  GameTooltip:Show()   -- resize to fit the new lines
end)
