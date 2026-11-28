local _, ns = ...

-- Forever Ledger as a price source in CraftProfit (Frank, November 28: CraftProfit only
-- reads Auctionator, TSM or its own scan). CraftProfit keeps a list of price sources,
-- CraftProfit.Sources, that its settings and /cf source pick from; we add one entry built
-- on ForeverLedgerAPI (API.lua), so it hands out only our own scans. CraftProfit's list
-- isn't an official way in, so everything is checked first and runs inside pcall: a
-- CraftProfit update that changes it just leaves us out. settings.shareCraftProfit (Global
-- settings, Prices) turns it off: CraftProfit then lists us as not installed.

local KEY = "foreverledger"
local api = ns.API

local function on()
  return api ~= nil and ns.db ~= nil and ns.db.settings.shareCraftProfit ~= false
end

-- The setting CraftProfit's own scan uses for sale prices: "min" (cheapest now) or
-- "market" (its usual price). We follow it: cheapest, or our usual price.
local function saleBasis()
  local cp = CraftProfit
  return type(cp) == "table" and type(cp.settings) == "table" and cp.settings.saleBasis or "min"
end

local source = {
  key = KEY,
  name = "Forever Ledger",
  description = "Forever Ledger's auction house scans (full scans and the flip watch).",
  IsAvailable = function() return on() end,
  HasData = function()
    if not on() then return false end
    local market = ns.db.prices[ns.MarketKey()]
    return type(market) == "table" and next(market) ~= nil
  end,
  -- What one costs to buy now: the cheapest listed.
  GetCostPrice = function(_, itemID)
    if not on() then return end
    local _, cheapest = api.GetPrice(itemID)
    return cheapest
  end,
  -- What one sells for: the cheapest now, or the usual price when CraftProfit is set to
  -- its market price. Either falls back to the other, so an item none are listed of
  -- still has its usual price.
  GetSalePrice = function(_, itemID)
    if not on() then return end
    local _, cheapest = api.GetPrice(itemID)
    local usual = api.GetUsualPrice(itemID)
    if saleBasis() == "market" then return usual or cheapest end
    return cheapest or usual
  end,
  GetAge = function(_, itemID)
    if not on() then return end
    local _, _, _, seen = api.GetPrice(itemID)
    if type(seen) == "number" then return math.max(0, time() - seen) end
  end,
  GetSoldPerDay = function(_, itemID)
    if not on() then return end
    return (api.GetSoldPerDay(itemID))
  end,
}

-- Each call wrapped, so an error of ours can't break CraftProfit's price lookups.
local wrapped = {}
for k, v in pairs(source) do
  if type(v) == "function" then
    wrapped[k] = function(...)
      local ok, a = pcall(v, ...)
      if ok then return a end
      ns:Debug("CraftProfit price source:", k, a)
    end
  else
    wrapped[k] = v
  end
end

local added   -- CraftProfit's list of sources we're in
function ns:AddCraftProfitSource()
  if not api then return end
  local sources = type(CraftProfit) == "table" and CraftProfit.Sources
  if not (type(sources) == "table" and type(sources.Register) == "function" and type(sources.byKey) == "table") then return end
  if added == sources and sources.byKey[KEY] == wrapped then return true end
  if not sources.byKey[KEY] then pcall(sources.Register, sources, wrapped) end
  -- (Not ours under our key: leave it alone.)
  if sources.byKey[KEY] ~= wrapped then return end
  added = sources
  -- CraftProfit recalculates when we save new prices (its own event, as its other sources do).
  api.RegisterForUpdate("CraftProfit", function()
    local cp = CraftProfit
    if on() and type(cp) == "table" and type(cp.Fire) == "function" then cp:Fire("PRICES_UPDATED", KEY) end
  end)
  return true
end

-- For /fl api: whether CraftProfit is installed and has us in its list.
function ns:CraftProfitSourceState()
  if type(CraftProfit) ~= "table" then return "CraftProfit not installed" end
  if not (added and added == CraftProfit.Sources) then return "not added (CraftProfit's list of price sources wasn't found)" end
  return on() and "added (pick Forever Ledger in CraftProfit's price source setting)" or "added, turned off in Settings"
end

-- CraftProfit's name sorts before ours, so it's usually loaded already; if not, add it
-- when it loads.
ns:AddCraftProfitSource()
ns:On("ADDON_LOADED", function(name)
  if name == "CraftProfit" then ns:AddCraftProfitSource() end
end)
