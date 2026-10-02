local _, ns = ...

---------------------------------------------------------------------------
-- What an item is worth to you: the best of selling it on the auction house,
-- selling it to a vendor, disenchanting it, converting it, or crafting it into
-- something else, following chains up to MAX_STEPS long.
---------------------------------------------------------------------------
local MAX_STEPS = 4     -- crafts, disenchants and conversions in one chain
local MIN_LISTED = 5    -- inside a chain, ignore auction house prices with fewer listings

function ns:AHCut()
  return (ns.db.settings.ahCut or 5) / 100
end

-- What one unit fetches on the auction house after the cut. With needListings,
-- thin markets (fewer than MIN_LISTED listed) don't count.
-- What selling one on the auction house brings, after the cut. Selling means listing at
-- or under the cheapest, so this is the lowest of the price used for buying (the average
-- of the cheapest 20 listed), today's cheapest, and the usual cheapest from price history
-- (owner's test, October 1: Simple Linen Pants showed 10,564% return, valued at the
-- average of a few hopeful listings).
local function ahSale(id, needListings)
  local p, _, _, rec = ns:GetPrice(id)
  if not p then return end
  if needListings and rec and rec.q and rec.q < MIN_LISTED then return end
  if rec and rec.m and not rec.none and rec.m < p then p = rec.m end
  if ns.PriceStats then
    local ok, st = pcall(ns.PriceStats, ns, id, "month")
    if ok and st and st.points >= 4 and st.low and st.low < p then p = st.low end
  end
  return p * (1 - ns:AHCut())
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
-- Every material in the table, so names show before the game has loaded the item.
for id, name in pairs({
  [10998] = "Lesser Astral Essence", [11082] = "Greater Astral Essence", [11083] = "Soul Dust",
  [11084] = "Large Glimmering Shard", [11134] = "Lesser Mystic Essence", [11135] = "Greater Mystic Essence",
  [11137] = "Vision Dust", [11138] = "Small Glowing Shard", [11139] = "Large Glowing Shard",
  [11174] = "Lesser Nether Essence", [11175] = "Greater Nether Essence", [11176] = "Dream Dust",
  [11177] = "Small Radiant Shard", [11178] = "Large Radiant Shard", [16202] = "Lesser Eternal Essence",
  [16203] = "Greater Eternal Essence", [16204] = "Illusion Dust", [14343] = "Small Brilliant Shard",
  [14344] = "Large Brilliant Shard",
}) do MAT_NAMES[id] = name end

-- Green items. Up to 20 from the owner's capes test; 21-25 matched the owner's first
-- disenchants (4-6 Strange Dust, sometimes 1-2 Lesser Astral Essence). The rest are
-- Classic's table, assumed until tested. Averages: dust or essence 75% of the time
-- (the other 20%), shard 5%. Weapons swap the dust and essence chances.
-- How many drop when that material comes up (Classic's ranges), by average.
local RANGES = { [1.5] = { 1, 2 }, [2.5] = { 2, 3 }, [3.5] = { 2, 5 }, [5] = { 4, 6 } }
-- odds = { { itemID, chance, low, high }, ... } for tooltips (the Disenchant finder).
local function row(maxLevel, dust, dustAvg, essence, essAvg, shard)
  local d, e = RANGES[dustAvg] or { dustAvg, dustAvg }, RANGES[essAvg] or { essAvg, essAvg }
  return { maxLevel = maxLevel,
    armor  = { { dust, 0.75 * dustAvg }, { essence, 0.20 * essAvg }, { shard, 0.05 },
      odds = { { dust, 75, d[1], d[2] }, { essence, 20, e[1], e[2] }, { shard, 5, 1, 1 } } },
    weapon = { { dust, 0.20 * dustAvg }, { essence, 0.75 * essAvg }, { shard, 0.05 },
      odds = { { dust, 20, d[1], d[2] }, { essence, 75, e[1], e[2] }, { shard, 5, 1, 1 } } } }
end
local DISENCHANT = {
  { maxLevel = 15,
    armor  = { { STRANGE_DUST, 1.18 }, { LESSER_MAGIC, 0.31 },
      odds = { { STRANGE_DUST, 80, 1, 2 }, { LESSER_MAGIC, 20, 1, 2 } } },
    weapon = { { STRANGE_DUST, 0.30 }, { LESSER_MAGIC, 1.20 },
      odds = { { STRANGE_DUST, 20, 1, 2 }, { LESSER_MAGIC, 80, 1, 2 } } } },
  { maxLevel = 20, tested = "armor",
    armor  = { { STRANGE_DUST, 1.875 }, { GREATER_MAGIC, 0.30 }, { SMALL_GLIMMERING, 0.05 },
      odds = { { STRANGE_DUST, 75, 2, 3 }, { GREATER_MAGIC, 20, 1, 2 }, { SMALL_GLIMMERING, 5, 1, 1 } } },
    weapon = { { STRANGE_DUST, 0.50 }, { GREATER_MAGIC, 1.125 }, { SMALL_GLIMMERING, 0.05 },
      odds = { { STRANGE_DUST, 20, 2, 3 }, { GREATER_MAGIC, 75, 1, 2 }, { SMALL_GLIMMERING, 5, 1, 1 } } } },
  row(25, STRANGE_DUST, 5, 10998, 1.5, SMALL_GLIMMERING),   -- Lesser Astral Essence
  row(30, 11083, 1.5, 11082, 1.5, 11084),                   -- Soul Dust, Greater Astral, Large Glimmering
  row(35, 11083, 3.5, 11134, 1.5, 11138),                   -- Lesser Mystic, Small Glowing Shard
  row(40, 11137, 1.5, 11135, 1.5, 11139),                   -- Vision Dust, Greater Mystic, Large Glowing
  row(45, 11137, 3.5, 11174, 1.5, 11177),                   -- Lesser Nether, Small Radiant Shard
  row(50, 11176, 1.5, 11175, 1.5, 11178),                   -- Dream Dust, Greater Nether, Large Radiant
  row(55, 11176, 3.5, 16202, 1.5, 14343),                   -- Lesser Eternal, Small Brilliant Shard
  row(60, 16204, 1.5, 16203, 1.5, 14344),                   -- Illusion Dust, Greater Eternal, Large Brilliant
  row(65, 16204, 3.5, 16203, 2.5, 14344),
}
ns.DISENCHANT_BANDS = {}
-- Names for each row of the table, used to group shuffles ("Item level 16-20 green armor").
do
  local low = 1
  for _, band in ipairs(DISENCHANT) do
    local levels = low == 1 and ("up to " .. band.maxLevel) or (low .. "-" .. band.maxLevel)
    band.armor.label = "Item level " .. levels .. " green armor"
    band.weapon.label = "Item level " .. levels .. " green weapons"
    band.armor.band, band.weapon.band = band.maxLevel, band.maxLevel
    band.armor.kind, band.weapon.kind = "armor", "weapon"
    -- Enchanting skill needed (Classic: 1 up to level 20, then 25 more per 5 levels).
    local skill = band.maxLevel <= 20 and 1 or (band.maxLevel - 20) * 5
    band.armor.skill, band.weapon.skill = skill, skill
    -- Tested in Forever: 16-20 armor (owner, 22 items). The rest is Classic's table.
    band.armor.tested = band.tested == "armor" or nil
    ns.DISENCHANT_BANDS[#ns.DISENCHANT_BANDS + 1] = { key = band.maxLevel, label = levels,
      armor = band.armor, weapon = band.weapon }
    low = band.maxLevel + 1
  end
end
local WEAPON, ARMOR, UNCOMMON = 2, 4, 2   -- item class IDs and quality
local NOT_DISENCHANTABLE = { INVTYPE_BODY = true, INVTYPE_TABARD = true }
-- Crafted wands can't be disenchanted in Forever (owner's test); wands found in the world can.
local CRAFTED_WANDS = { [247789] = true, [11287] = true, [11288] = true, [11289] = true, [11290] = true }

-- True if a captured Enchanting recipe makes this item.
local function madeByEnchanting(id)
  for _, c in pairs(ns.db.chars) do
    local p = c.profs and c.profs.Enchanting
    for _, rec in pairs(p and p.recipes or {}) do
      if rec.out == id then return true end
    end
  end
end

-- Returns a list of { itemID, average count }, or nil if the item can't be disenchanted
-- (or isn't covered by the table yet). The list also has .label, .band (highest item
-- level of its row) and .kind ("armor" or "weapon").
function ns:DisenchantYield(id)
  if CRAFTED_WANDS[id] or madeByEnchanting(id) then return end
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

-- Characters unticked in the Shuffles tab don't count for recipes or disenchanting.
local function counts(charKey)
  return not ns.db.settings.skipChars[charKey]
end

-- The highest Enchanting skill among counted characters, or nil if none enchant.
local function canDisenchant()
  local best
  for key, c in pairs(ns.db.chars) do
    local p = counts(key) and c.profs and c.profs.Enchanting
    if p then best = math.max(best or 0, p.rank or 1) end
  end
  return best
end
ns.EnchantingSkill = canDisenchant

-- What a material costs to buy: the vendor price when a vendor sells it, otherwise
-- the auction house price.
local function buyCost(id)
  -- The cheaper of a vendor and the auction house (see buyInfo in Shuffles.lua).
  local vendor, ah = ns:GetVendorBuyPrice(id), (ns:GetPrice(id))
  if vendor and ah then return math.min(vendor, ah) end
  return vendor or ah
end

---------------------------------------------------------------------------
-- Options. Each option is a table:
--   kind  = "ah" | "vendor" | "disenchant" | "convert" | "craft"
--   value = copper per unit of the item
--   step  = text for this step (convert, craft)
--   next  = the best option for the output (convert, craft)
--   per   = outputs per unit (convert)
--   mats  = { { id, count, opt } } for disenchant
--   buys  = { { id, qty, cost } } other materials a craft needs, per craft
--   rec, units, who (craft): the recipe, units of this item it uses, and the
--   character who knows it if that isn't the one logged in
---------------------------------------------------------------------------

-- Best options are cached per item and chain depth. When prices or recipes change the
-- cache is cleared at most every 2 seconds, so a scan saving prices doesn't make every
-- tooltip recalculate everything. Settings changes clear it straight away (now = true).
-- It's also cleared at least once a minute.
local cache, cacheTime, dirty = {}, 0, false
local listCache = {}    -- itemID = full options list at depth 0 (tooltips, finder)
function ns:InvalidateValues(now)
  if now then cache, listCache, cacheTime, dirty = {}, {}, GetTime(), false else dirty = true end
end

local best

-- True if the chain `o` passes through item `id`. Used to stop loops such as
-- splitting an essence and combining it straight back.
local function passesThrough(o, id)
  if o.id == id then return true end
  if o.next then return passesThrough(o.next, id) end
  for _, m in ipairs(o.mats or {}) do
    if passesThrough(m.opt, id) then return true end
  end
  return false
end

local options

-- Best option for the next item in a chain that doesn't lead back to `from`. If the
-- best one loops back, take the next best instead of treating the item as worthless:
-- otherwise which items looked profitable depended on the order they were worked out,
-- and disenchant shuffles came and went on every refresh (owner's log, September 30).
local function follow(nextID, depth, from)
  local o = best(nextID, depth + 1)
  if not o then return end
  if not passesThrough(o, from) then return o end
  -- The full list, kept in the same cache (cleared together) so this stays cheap.
  local key = "all:" .. nextID .. ":" .. (depth + 1)
  local list = cache[key]
  if not list then list = options(nextID, depth + 1); cache[key] = list end
  for _, alt in ipairs(list) do
    if not passesThrough(alt, from) then return alt end
  end
end

-- All options for `id` with `depth` steps already taken. Results don't depend on
-- the chain they're part of, so the cache always gives the same answer.
options = function(id, depth)
  local list = {}
  local function add(o)
    if o.value and o.value > 0 then o.id = id; list[#list + 1] = o end
  end

  add({ kind = "ah", value = ahSale(id, depth > 0) })
  add({ kind = "vendor", value = vendorSale(id) })

  if depth < MAX_STEPS then
    local skill = canDisenchant()
    local yield = skill and ns:DisenchantYield(id)
    if yield and skill >= (yield.skill or 1) then
      local total, mats = 0, {}
      for _, y in ipairs(yield) do
        local o = follow(y[1], depth, id)
        if o then
          total = total + o.value * y[2]
          mats[#mats + 1] = { id = y[1], count = y[2], opt = o }
        end
      end
      add({ kind = "disenchant", value = total, mats = mats })
    end

    for _, conv in ipairs(CONVERSIONS[id] or {}) do
      local o = follow(conv.out, depth, id)
      if o then add({ kind = "convert", value = o.value * conv.per, step = conv.label, next = o, per = conv.per }) end
    end

    local me = ns.CharKey()
    for _, use in ipairs(ns.recipesByReagent and ns.recipesByReagent[id] or {}) do
      local rec = use.rec
      local o = counts(use.key) and rec.out and rec.out ~= id and follow(rec.out, depth, id)
      if o then
        -- Pay for every other material; what's left is shared across the units of `id`.
        local left, units, buys = o.value * (rec.oq or 1), 0, {}
        for _, r in ipairs(rec.r or {}) do
          if r[1] == id then
            units = units + r[2]
          else
            local cost = buyCost(r[1])
            if not cost then left = nil; break end
            left = left - cost * r[2]
            buys[#buys + 1] = { id = r[1], qty = r[2], cost = cost }
          end
        end
        if left and units > 0 then
          add({
            kind = "craft", value = left / units, step = "Craft " .. (rec.n or "?"), next = o,
            rec = rec, units = units, buys = buys, prof = use.prof, recipeID = use.recipeID,
            who = use.key ~= me and use.who or nil,
          })
        end
      end
    end

  end

  -- Ties are broken by name, so the same prices always give the same order.
  table.sort(list, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return (a.step or a.kind) < (b.step or b.kind)
  end)
  return list
end

best = function(id, depth)
  local key = id .. ":" .. depth
  local hit = cache[key]
  if hit == nil then
    hit = options(id, depth)[1] or false
    cache[key] = hit
  end
  return hit or nil
end

-- After small changes (an item's details arriving, a vendor price) values are rebuilt at
-- most every 30 seconds; rebuilding every 2 seconds caused a lag spike each time.
-- Scans and settings changes rebuild straight away (InvalidateValues(true)).
local function freshCache()
  local age = GetTime() - cacheTime
  if (dirty and age > 30) or age > 300 then
    cache, listCache, cacheTime, dirty = {}, {}, GetTime(), false
    if ns.PerfNote then ns.PerfNote("Values thrown away (count only)", 0) end
  end
end

local function allOptions(id)
  local list = listCache[id]
  if not list then list = options(id, 0); listCache[id] = list end
  return list
end

-- Best option for an item, with its whole chain.
function ns:BestOption(id)
  if not id or not ns.db then return end
  freshCache()
  return best(id, 0)
end

-- The most worth paying for an item: its best value without relisting it on the
-- auction house, less the safety margin. Only for items you can craft with,
-- disenchant or convert. Returns the price and the option it comes from.
function ns:BuyAtOrBelow(id)
  local bestNonAH, useful
  for _, o in ipairs(ns:Options(id)) do
    if o.kind ~= "ah" then
      bestNonAH = bestNonAH or o
      if o.kind ~= "vendor" then useful = true end
    end
  end
  if bestNonAH and useful then
    return bestNonAH.value * (1 - (ns.db.settings.margin or 10) / 100), bestNonAH
  end
end

-- Every option for an item, best first.
function ns:Options(id)
  if not id or not ns.db then return {} end
  freshCache()
  return allOptions(id)
end

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------
local function countSteps(o)
  if o.kind == "craft" or o.kind == "convert" then return 1 + countSteps(o.next) end
  if o.kind == "disenchant" then
    local n = 0
    for _, m in ipairs(o.mats) do n = math.max(n, countSteps(m.opt)) end
    return 1 + n
  end
  return 0
end
ns.CountSteps = countSteps

-- How a chain carries on after its first step.
local function rest(o)
  if o.kind == "ah" then return "auction house" end
  if o.kind == "vendor" then return "sell to vendor" end
  local n = countSteps(o)
  if o.kind == "disenchant" and n == 1 then return "disenchant" end
  return n == 1 and "1 more step" or (n .. " more steps")
end

function ns:OptionLabel(o)
  if o.kind == "ah" then return ("Auction house, after %g%% cut"):format(ns.db.settings.ahCut or 5) end
  if o.kind == "vendor" then return "Sell to vendor" end
  if o.kind == "disenchant" then return "Disenchant" end
  local label = o.step .. ", " .. rest(o.next)
  if o.who then label = label .. " (" .. o.who .. ")" end
  return label
end

-- Returns the best value and a list of options (each with a label), best first.
-- Only the three best recipes are listed, so tooltips stay short.
function ns:GetValue(id)
  if not id or not ns.db then return end
  freshCache()
  local list, crafts, seen = {}, 0, {}
  for _, o in ipairs(allOptions(id)) do
    if o.kind ~= "craft" or (not seen[o.step] and crafts < 3) then
      if o.kind == "craft" then seen[o.step] = true; crafts = crafts + 1 end
      o.label = ns:OptionLabel(o)
      list[#list + 1] = o
    end
  end
  return list[1] and list[1].value, list
end
