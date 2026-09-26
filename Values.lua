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

---------------------------------------------------------------------------
-- Conversions anyone can do by right-clicking: 3 lesser essences make 1 greater,
-- and 1 greater splits into 3 lesser.
---------------------------------------------------------------------------
local ESSENCES = {
  { 10938, 10939, "Magic" }, { 10998, 11082, "Astral" }, { 11134, 11135, "Mystic" },
  { 11174, 11175, "Nether" }, { 16202, 16203, "Eternal" },
}
local CONVERSIONS = {}   -- [itemID] = { { out = itemID, per = outputs per input, label } }
for _, e in ipairs(ESSENCES) do
  local lesser, greater, kind = e[1], e[2], e[3]
  CONVERSIONS[lesser] = { { out = greater, per = 1 / 3, label = "Combine into Greater " .. kind .. " Essence" } }
  CONVERSIONS[greater] = { { out = lesser, per = 3, label = "Split into Lesser " .. kind .. " Essence" } }
end

---------------------------------------------------------------------------
-- Disenchanting. Average materials per item from the Classic table, which the
-- owner's test (30 item level 12 capes) matched. Greens up to item level 20 only.
---------------------------------------------------------------------------
local STRANGE_DUST, LESSER_MAGIC, GREATER_MAGIC, SMALL_GLIMMERING = 10940, 10938, 10939, 10978
local MAT_NAMES = {
  [STRANGE_DUST] = "Strange Dust", [LESSER_MAGIC] = "Lesser Magic Essence",
  [GREATER_MAGIC] = "Greater Magic Essence", [SMALL_GLIMMERING] = "Small Glimmering Shard",
}
local DISENCHANT = {
  { maxLevel = 15,
    armor  = { { STRANGE_DUST, 1.18 }, { LESSER_MAGIC, 0.31 } },
    weapon = { { STRANGE_DUST, 0.30 }, { LESSER_MAGIC, 1.20 } } },
  { maxLevel = 20,
    armor  = { { STRANGE_DUST, 1.875 }, { GREATER_MAGIC, 0.30 }, { SMALL_GLIMMERING, 0.05 } },
    weapon = { { STRANGE_DUST, 0.50 }, { GREATER_MAGIC, 1.125 }, { SMALL_GLIMMERING, 0.05 } } },
}
local WEAPON, ARMOR, UNCOMMON = 2, 4, 2   -- item class IDs and quality
local NOT_DISENCHANTABLE = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

-- Returns a list of { itemID, average count }, or nil if the item can't be disenchanted
-- (or isn't covered by the table yet).
function ns:DisenchantYield(id)
  local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID = ns.GetItemInfo(id)
  if quality ~= UNCOMMON or not ilvl or NOT_DISENCHANTABLE[equipLoc] then return end
  local kind = (classID == WEAPON and "weapon") or (classID == ARMOR and "armor")
  if not kind then return end
  for _, band in ipairs(DISENCHANT) do
    if ilvl <= band.maxLevel then return band[kind] end
  end
end

function ns:DisenchantMaterialName(id)
  return ns.GetItemInfo(id) or MAT_NAMES[id] or ("item " .. id)
end

local function canDisenchant()
  for _, c in pairs(ns.db.chars) do
    if c.profs and c.profs.Enchanting then return true end
  end
end

-- Materials are valued at their own best value, but without disenchanting, so this can't loop.
local function disenchantSale(id)
  local yield = ns:DisenchantYield(id)
  if not yield or not canDisenchant() then return end
  local total = 0
  for _, y in ipairs(yield) do
    local v = ns:GetValue(y[1], true)
    if v then total = total + v * y[2] end
  end
  if total > 0 then return total end
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
-- noDisenchant leaves out disenchanting, used when valuing disenchant materials.
-- noConvert leaves out conversions, used when valuing a conversion's output so
-- splitting and combining can't loop.
function ns:GetValue(id, noDisenchant, noConvert)
  if not id or not ns.db then return end
  local options = {}
  local function add(label, v)
    if v and v > 0 then options[#options + 1] = { label = label, value = v } end
  end

  add(("Auction house, after %g%% cut"):format(ns.db.settings.ahCut or 5), ahSale(id))
  add("Sell to vendor", vendorSale(id))
  if not noDisenchant then add("Disenchant", disenchantSale(id)) end
  if not noConvert then
    for _, conv in ipairs(CONVERSIONS[id] or {}) do
      local v = ns:GetValue(conv.out, noDisenchant, true)
      if v then add(conv.label, v * conv.per) end
    end
  end

  -- Best recipe for each way of selling the output. The vendor route only counts
  -- vendor-bought materials, so it's a guaranteed floor.
  local me = ns.CharKey()
  local routes = {
    { sell = vendorSale, vendorOnly = true, fmt = "Craft %s, sell to vendor" },
    { sell = ahSale, vendorOnly = false, fmt = "Craft %s, auction house" },
  }
  if not noDisenchant then
    routes[#routes + 1] = { sell = disenchantSale, vendorOnly = false, fmt = "Craft %s, disenchant" }
  end
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
