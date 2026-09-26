local _, ns = ...

---------------------------------------------------------------------------
-- What an item is worth to you: the best of selling it on the auction house,
-- selling it to a vendor, or crafting it into something and selling that.
---------------------------------------------------------------------------

function ns:AHCut()
  return (ns.db.settings.ahCut or 5) / 100
end

-- What one unit fetches on the auction house after the cut.
local function ahSale(id)
  local p = ns:GetPrice(id)
  if p then return p * (1 - ns:AHCut()) end
end

local function vendorSale(id)
  return ns:GetSellPrice(id)
end

-- What a material costs to buy. Vendor price when a vendor sells it, otherwise the
-- auction house price, unless vendorOnly is set.
local function buyCost(id, vendorOnly)
  local p = ns:GetVendorBuyPrice(id)
  if p then return p end
  if not vendorOnly then return (ns:GetPrice(id)) end
end

-- Value of one `id` when crafted with `rec` and the output sold with `sell`.
-- Every other material is paid for; what's left is shared across the units of `id`.
local function viaRecipe(id, rec, sell, vendorOnly)
  if not rec.out or rec.out == id then return end
  local each = sell(rec.out)
  if not each or each <= 0 then return end
  local left, units = each * (rec.oq or 1), 0
  for _, r in ipairs(rec.r or {}) do
    if r[1] == id then
      units = units + r[2]
    else
      local cost = buyCost(r[1], vendorOnly)
      if not cost then return end
      left = left - cost * r[2]
    end
  end
  if units > 0 and left > 0 then return left / units end
end

-- Returns the best value and a list of options { label, value }, best first.
function ns:GetValue(id)
  if not id or not ns.db then return end
  local options = {}
  local function add(label, v)
    if v and v > 0 then options[#options + 1] = { label = label, value = v } end
  end

  add(("Auction house, after %g%% cut"):format(ns.db.settings.ahCut or 5), ahSale(id))
  add("Sell to vendor", vendorSale(id))

  -- Best recipe for each way of selling the output. The vendor route only counts
  -- vendor-bought materials, so it's a guaranteed floor.
  local me = ns.CharKey()
  local routes = {
    { sell = vendorSale, vendorOnly = true, fmt = "Craft %s, sell to vendor" },
    { sell = ahSale, vendorOnly = false, fmt = "Craft %s, auction house" },
  }
  for _, route in ipairs(routes) do
    local best, bestUse
    for _, use in ipairs(ns.recipesByReagent and ns.recipesByReagent[id] or {}) do
      local v = viaRecipe(id, use.rec, route.sell, route.vendorOnly)
      if v and (not best or v > best) then best, bestUse = v, use end
    end
    if best then
      local label = route.fmt:format(bestUse.rec.n or "?")
      if bestUse.key ~= me then label = label .. " (" .. (bestUse.who or "?") .. ")" end
      add(label, best)
    end
  end

  table.sort(options, function(a, b) return a.value > b.value end)
  return options[1] and options[1].value, options
end
