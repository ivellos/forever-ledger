local _, ns = ...

---------------------------------------------------------------------------
-- What an item is worth to you: the best of selling it on the auction house,
-- selling it to a vendor, disenchanting it, converting it, or crafting it into
-- something else, following chains up to MAX_STEPS long.
---------------------------------------------------------------------------
local MAX_STEPS = 4     -- crafts, disenchants and conversions in one chain
local MIN_LISTED = 5    -- inside a chain, ignore auction house prices with fewer listings

-- The cut as a fraction: the setting at your faction's auction house, and 15% at a
-- neutral one (owner's mail from Booty Bay, October 5: 4s 33c sold, cut 64c, 15% rounded
-- down). neutral: true / false to ask about one; nil = the one open now.
ns.NEUTRAL_CUT = 15
function ns:AHCut(neutral)
  if neutral == nil then neutral = ns.neutralAH end
  if neutral then return ns.NEUTRAL_CUT / 100 end
  return (ns.db.settings.ahCut or 5) / 100
end

-- One item at the neutral auction house (Booty Bay) against your faction's, each after
-- its own cut and one lost 8-hour deposit reserve (owner, October 5: see what sells for more there, without it mixing into
-- your normal prices). Neutral prices stay in their own market ("realm|Neutral"); only
-- this reads them while you're away from it. nil when either side has no price.
-- { there, here = cheapest each; netThere, netHere = after the cut; gain = netThere -
--   netHere (selling there instead); pct = gain / netHere; buyProfit = netHere - there
--   (buying there, selling here); listedThere, listedHere; t = when Booty Bay was seen }
function ns:NeutralCompare(id)
  local realm, faction = ns.RealmName() or "?", UnitFactionGroup("player") or "?"
  local there = (ns.db.prices[realm .. "|Neutral"] or {})[id]
  local here = (ns.db.prices[realm .. "|" .. faction] or {})[id]
  if not (there and here and there.m and here.m and not there.none and not here.none) then return end
  if there.m <= 0 or here.m <= 0 then return end
  local netThere, depositThere = ns:AuctionSaleValue(id, there.m, true)
  local netHere, depositHere = ns:AuctionSaleValue(id, here.m, false)
  return { there = there.m, here = here.m, netThere = netThere, netHere = netHere,
    depositThere = depositThere, depositHere = depositHere, gain = netThere - netHere, pct = netHere > 0 and (netThere - netHere) / netHere or 0, buyProfit = netHere - there.m,
    listedThere = there.q or 0, listedHere = here.q or 0, t = there.t, tHere = here.t }
end

-- What a sale of this many copper brings: the game rounds the cut down, not what you get
-- (Booty Bay mail: 433c at 15% = 64.95, cut 64c, received 369c).
function ns:AfterCut(copper, neutral)
  return copper - math.floor(copper * ns:AHCut(neutral))
end

-- What count at price each brings when one buyer takes them all: the cut is worked out on
-- the whole sale and rounded down once, so 20 at 19c brings 361c, though 5% of 19c alone
-- rounds to nothing (gold audit G8, November 9; the Empty Vial mail, 10 at 8c, lost 4c).
function ns:SaleAfterCut(price, count, neutral)
  return ns:AfterCut(price * math.max(math.floor(count or 1), 1), neutral)
end

-- What one unit fetches after the cut and one lost 8-hour deposit reserve. With needListings,
-- thin markets (fewer than MIN_LISTED listed) don't count.
-- What selling one on the auction house brings, after the cut. Selling means listing at
-- or under the cheapest, so this is the lowest of the price used for buying (the average
-- of the cheapest 20 listed), today's cheapest, and the usual cheapest from price history
-- (owner's test, October 1: Simple Linen Pants showed 10,564% return, valued at the
-- average of a few hopeful listings).
local function ahSale(id, needListings)
  local p, _, when, rec = ns:GetPrice(id)
  if not p then return end
  if needListings and rec and rec.q and rec.q < MIN_LISTED then return end
  -- A chain is what shuffles and list limits are worked out from: an old price there can
  -- mean overpaying on every unit (gold audit, November 9). maxAgeHours, as in GetPrice.
  if needListings and when and time() - when > (ns.db.settings.maxAgeHours or 12) * 3600 then return end
  if rec and rec.m and not rec.none and rec.m < p then p = rec.m end
  -- This month's usual cheapest guards against a few hopeful listings. With 20 or more
  -- listed, today's market is the real one (owner's screenshot, October 22: Medium
  -- Leather at 2s 65c with 1,569 listed was valued at 43c from a month at about 54c).
  if ns.PriceStats and not (rec and rec.q and rec.q >= 20) then
    local ok, st = pcall(ns.PriceStats, ns, id, "month")
    if ok and st and st.points >= 4 and st.low and st.low < p then p = st.low end
  end
  -- A chain's result (a disenchant's materials, a craft's output) at no more than its usual
  -- price this week, however many are listed: a buyout that spikes today's price can't make
  -- a purchase look profitable, while a drop counts at once (a player on Discord, November
  -- 10: Astral Essence bought out, expensive items shown as profitable disenchants; Frank
  -- chose the lower of the two). A real rise counts once the week's median has caught up,
  -- after about 4 days (the week, not Deals' window: all of history would take weeks).
  if needListings and ns.UsualPrice then
    local ok, usual, points = pcall(ns.UsualPrice, ns, id, "week")
    if ok and usual and (points or 0) >= 3 and usual < p then p = usual end
  end
  return ns:AuctionSaleValue(id, p)
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
-- Disenchanting: client eligibility from Wago ItemDisenchantLoot, build 1.60.1.70938.
-- Public model: wow-professions.com/forever/disenchanting-guide and the explicitly
-- Classic-derived ranges at foreverdb.net/profession/enchanting, read November 14, 2026.
-- Data from ForeverDB.net. These are estimates, not server loot tables or measured odds.
-- Source access, differences from 120 local results: tools/FOREVER_DATA_SOURCES.md.
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
  [20725] = "Nexus Crystal",
}) do MAT_NAMES[id] = name end

-- Green items. Up to 20 from the owner's capes test; 21-25 matched the owner's first
-- disenchants (4-6 Strange Dust, sometimes 1-2 Lesser Astral Essence). The rest are
-- Classic's table, assumed until tested. Averages: dust or essence 75% of the time
-- (the other 20%), shard 5%. Weapons swap the dust and essence chances.
-- Weapons of item level 21-30 give Greater Magic Essence in Forever, not Astral: every one
-- in the owner's disenchant log (five, item levels 22-30, a Dire Wand among them; November
-- 10), as a player reported on Discord and CraftShuffle Forever 0.2.4 found.
-- How many drop when that material comes up (Classic's ranges), by average.
local RANGES = { [1.5] = { 1, 2 }, [2] = { 1, 3 }, [2.5] = { 2, 3 }, [3.5] = { 2, 5 }, [5] = { 4, 6 } }
-- odds = { { itemID, chance, low, high }, ... } for tooltips (the Disenchant finder).
-- weaponEssence: weapons' essence when it isn't armor's. tested: "armor", "weapon" or
-- "both", checked in Forever.
local function row(maxLevel, dust, dustAvg, essence, essAvg, shard, weaponEssence, tested, chances)
  local d, e = RANGES[dustAvg] or { dustAvg, dustAvg }, RANGES[essAvg] or { essAvg, essAvg }
  local wess = weaponEssence or essence
  local c = chances or { 75, 20, 5, 20, 75, 5 }
  return { maxLevel = maxLevel, tested = tested,
    armor  = { { dust, c[1] / 100 * dustAvg }, { essence, c[2] / 100 * essAvg }, { shard, c[3] / 100 },
      odds = { { dust, c[1], d[1], d[2] }, { essence, c[2], e[1], e[2] }, { shard, c[3], 1, 1 } } },
    weapon = { { dust, c[4] / 100 * dustAvg }, { wess, c[5] / 100 * essAvg }, { shard, c[6] / 100 },
      odds = { { dust, c[4], d[1], d[2] }, { wess, c[5], e[1], e[2] }, { shard, c[6], 1, 1 } } } }
end
local DISENCHANT = {
  { maxLevel = 15,
    armor  = { { STRANGE_DUST, 1.20 }, { LESSER_MAGIC, 0.30 },
      odds = { { STRANGE_DUST, 80, 1, 2 }, { LESSER_MAGIC, 20, 1, 2 } } },
    weapon = { { STRANGE_DUST, 0.30 }, { LESSER_MAGIC, 1.20 },
      odds = { { STRANGE_DUST, 20, 1, 2 }, { LESSER_MAGIC, 80, 1, 2 } } } },
  { maxLevel = 20, tested = "armor",
    armor  = { { STRANGE_DUST, 1.875 }, { GREATER_MAGIC, 0.30 }, { SMALL_GLIMMERING, 0.05 },
      odds = { { STRANGE_DUST, 75, 2, 3 }, { GREATER_MAGIC, 20, 1, 2 }, { SMALL_GLIMMERING, 5, 1, 1 } } },
    weapon = { { STRANGE_DUST, 0.50 }, { GREATER_MAGIC, 1.125 }, { SMALL_GLIMMERING, 0.05 },
      odds = { { STRANGE_DUST, 20, 2, 3 }, { GREATER_MAGIC, 75, 1, 2 }, { SMALL_GLIMMERING, 5, 1, 1 } } } },
  row(25, STRANGE_DUST, 5, 10998, 1.5, SMALL_GLIMMERING, GREATER_MAGIC, "both", { 75, 15, 10, 15, 75, 10 }),
  row(30, 11083, 1.5, 11082, 1.5, 11084, GREATER_MAGIC, "both"),
  row(35, 11083, 3.5, 11134, 1.5, 11138, nil, "armor"),
  row(40, 11137, 1.5, 11135, 1.5, 11139),                   -- Vision Dust, Greater Mystic, Large Glowing
  row(45, 11137, 3.5, 11174, 1.5, 11177),                   -- Lesser Nether, Small Radiant Shard
  row(50, 11176, 1.5, 11175, 1.5, 11178),                   -- Dream Dust, Greater Nether, Large Radiant
  row(55, 11176, 3.5, 16202, 1.5, 14343, nil, nil, { 75, 20, 5, 22, 75, 3 }),
  row(60, 16204, 1.5, 16203, 1.5, 14344, nil, nil, { 75, 20, 5, 22, 75, 3 }),
  row(65, 16204, 3.5, 16203, 2, 14344, nil, nil, { 75, 20, 5, 22, 75, 3 }),
}
ns.DISENCHANT_BANDS = {}
-- Names for each row of the table, used to group shuffles ("Item level 16-20 green armor").
do
  local low = 1
  for _, band in ipairs(DISENCHANT) do
    band.topLevel = band.maxLevel == 65 and 99 or band.maxLevel
    local levels = low == 1 and ("5-" .. band.maxLevel) or (low .. "-" .. band.topLevel)
    band.armor.label = "Item level " .. levels .. " green armor"
    band.weapon.label = "Item level " .. levels .. " green weapons"
    band.armor.band, band.weapon.band = band.maxLevel, band.maxLevel
    band.armor.kind, band.weapon.kind = "armor", "weapon"
    -- Frank confirmed November 14: Enchanting 1 suffices for every eligible item.
    -- All current ItemDisenchantLoot rows have SkillRequired=0 (no extra gate).
    local skill = 1
    band.armor.skill, band.weapon.skill = skill, skill
    -- Material observations in the owner's 120 results: armor 16-20 (30), 21-25
    -- (15), 26-30 (22), 31-35 (11); weapons 21-30 (5). Not measured probabilities.
    band.armor.tested = (band.tested == "armor" or band.tested == "both") or nil
    band.weapon.tested = (band.tested == "weapon" or band.tested == "both") or nil
    ns.DISENCHANT_BANDS[#ns.DISENCHANT_BANDS + 1] = { key = band.maxLevel, label = levels,
      armor = band.armor, weapon = band.weapon }
    low = band.maxLevel + 1
  end
end
local WEAPON, ARMOR, UNCOMMON = 2, 4, 2   -- item class IDs and quality
local NOT_DISENCHANTABLE = { INVTYPE_BODY = true, INVTYPE_TABARD = true }
-- Crafted wands can't be disenchanted in Forever (owner's test); wands found in the world can.
local CRAFTED_WANDS = { [247789] = true, [11287] = true, [11288] = true, [11289] = true, [11290] = true }

-- Rare items below 21 conflict with the public shard rule: three local results gave
-- essences. Leave those unknown, rather than valuing every early blue as a shard.
local rare, epic = {}, {}
epic[40] = { { 11177, 3 }, odds = { { 11177, 100, 2, 4 } } }
for _, b in ipairs(DISENCHANT) do
  local shard = b.armor[3] and b.armor[3][1]
  if b.maxLevel >= 25 then
    rare[b.maxLevel] = { { shard, 1 }, odds = { { shard, 100, 1, 1 } } }
  end
  if b.maxLevel >= 45 then
    local id, lo, hi = shard, 2, 4
    if b.maxLevel == 60 then id, lo, hi = 20725, 1, 1
    elseif b.maxLevel == 65 then id, lo, hi = 20725, 1, 2 end
    epic[b.maxLevel] = { { id, (lo + hi) / 2 }, odds = { { id, 100, lo, hi } } }
  end
end
-- The high-level rare crystal tail is approximate in the guide and incomplete in
-- the public table. Keep the one-shard model; do not advertise an invented tail.

-- Returns a list of { itemID, average count }, or nil if the item can't be disenchanted
-- (or isn't covered by the table yet). The list also has .label, .band (highest item
-- level of its row) and .kind ("armor" or "weapon").
function ns:DisenchantYield(id)
  if CRAFTED_WANDS[id] or (ns.FOREVER_NO_DISENCHANT and ns.FOREVER_NO_DISENCHANT[id]) then return end
  local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID = ns.GetItemInfo(id)
  if not quality or quality < UNCOMMON or quality > 4 or not ilvl or ilvl < 5 or ilvl > 99 or NOT_DISENCHANTABLE[equipLoc] then return end
  local kind = (classID == WEAPON and "weapon") or (classID == ARMOR and "armor")
  if not kind then return end
  for bandIndex, band in ipairs(DISENCHANT) do
    if ilvl <= band.topLevel then
      if quality == UNCOMMON then return band[kind] end
      if (quality == 3 and ilvl < 21) or (quality == 4 and ilvl < 40) then return end
      local model = quality == 3 and rare[band.maxLevel] or epic[band.maxLevel]
      if not model then return end
      -- Clone metadata: armor and weapon share outcomes but not their kind/label.
      local out = { odds = model.odds, skill = 1, band = band.maxLevel, kind = kind,
        label = ("Item level %s %s %s"):format(ns.DISENCHANT_BANDS[bandIndex].label, quality == 3 and "blue" or "purple", kind == "weapon" and "weapons" or "armor") }
      for i, m in ipairs(model) do out[i] = m end
      return out
    end
  end
end

function ns:DisenchantMaterialName(id)
  return ns.GetItemInfo(id) or MAT_NAMES[id] or ("item " .. id)
end

-- Characters unticked in the Shuffles tab don't count for recipes or disenchanting.
local function counts(charKey)
  return not ns.db.settings.skipChars[charKey] and ns:SameMarketChar(charKey)
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

-- The counted character with the most Enchanting skill: name, skill (nil if none). For the
-- sell suggestion's "or disenchant (name)" (SellAdvice.lua), with the same characters the
-- disenchant value counts (Codex review of 3bb2be7).
function ns:BestEnchanter()
  local best, name
  for key, c in pairs(ns.db.chars) do
    local p = counts(key) and c.profs and c.profs.Enchanting
    if p and (p.rank or 1) > (best or -1) then best, name = p.rank or 1, c.name end
  end
  return name, best
end

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

-- A disenchant's material as something you sell: the best way with no crafting in it
-- (selling it, or splitting or combining and selling that). Crafts made a 3s disenchant
-- look like 6s, with nothing saying why, and after the nerfs they rarely matter (Magic and
-- the owner, November 6).
-- A split whose best next step is a craft still counts as split and sold (owner's
-- screenshot, November 6: Greater Magic Essence). from: the item this came from, so
-- splitting doesn't combine straight back.
local function sellable(id, depth, from)
  local key = "all:" .. id .. ":" .. (depth + 1)
  local list = cache[key]
  if not list then list = options(id, depth + 1); cache[key] = list end
  local found
  for _, o in ipairs(list) do
    local way
    if o.kind == "ah" or o.kind == "vendor" then
      way = o
    elseif o.kind == "convert" and o.next.id ~= from then
      local after = sellable(o.next.id, depth + 1, id)
      if after then way = { kind = "convert", id = id, value = after.value * o.per, step = o.step, next = after, per = o.per } end
    end
    if way and (not found or way.value > found.value) then found = way end
  end
  return found
end

-- All options for `id` with `depth` steps already taken. Results don't depend on
-- the chain they're part of, so the cache always gives the same answer.
options = function(id, depth)
  local list = {}
  local function add(o)
    if o.value and o.value > 0 then o.id = id; list[#list + 1] = o end
  end

  local sale, deposit, source = ahSale(id, depth > 0)
  -- The deposit allowance only when this item itself is what you'd list (owner, October
  -- 7: not for the dust from a disenchant or a craft's output down a chain, so the
  -- Disenchant finder, shuffles and shopping-list limits are unchanged). Deals and the
  -- Booty Bay view, which resell the item itself, use ns:AuctionSaleValue directly.
  if depth > 0 and sale and deposit then sale, deposit = sale + deposit, 0 end
  add({ kind = "ah", value = sale, deposit = deposit, depositSource = source })
  local vendor = vendorSale(id)
  add({ kind = "vendor", value = vendor, vendorInstead = vendor and sale and deposit and deposit > 0 and sale <= vendor and sale + deposit > vendor })

  if depth < MAX_STEPS then
    local skill = canDisenchant()
    local yield = skill and ns:DisenchantYield(id)
    if yield and skill >= (yield.skill or 1) then
      local total, mats = 0, {}
      for _, y in ipairs(yield) do
        local o = sellable(y[1], depth)
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

  -- Ties favour the vendor (no listing risk), then name for a stable order.
  table.sort(list, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    if a.kind == "vendor" or b.kind == "vendor" then return a.kind == "vendor" end
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

-- A material as something you get from a disenchant: no deposit allowance, thin markets
-- left out, no crafting, exactly as the disenchant option counts it.
function ns:MaterialSale(id)
  if not id or not ns.db then return end
  freshCache()
  return sellable(id, 0)
end

-- What one disenchant brings on average, for showing how it adds up. Works without an
-- enchanter too. Returns the total and { { id, count, each, chance, low, high, when } }:
-- count is the average per disenchant with its chance already in it, and when is what
-- that result brings on the times it comes up. Each disenchant gives only one result, so
-- the total is an average (owner's screenshot, November 6: read as getting all three).
function ns:DisenchantSaleValue(id)
  local yield = ns:DisenchantYield(id)
  if not yield then return end
  local odds = {}
  for _, row in ipairs(yield.odds or {}) do odds[row[1]] = row end
  local total, parts = 0, {}
  for _, y in ipairs(yield) do
    local o = ns:MaterialSale(y[1])
    if o then
      total = total + o.value * y[2]
      local row = odds[y[1]]
      parts[#parts + 1] = { id = y[1], count = y[2], each = o.value,
        chance = row and row[2], low = row and row[3], high = row and row[4],
        when = row and y[2] / (row[2] / 100) * o.value }
    end
  end
  return total, parts
end

-- The most worth paying for an item: its best value without relisting it on the
-- auction house, less the safety margin. Only for items you can craft with,
-- disenchant or convert. Returns the price and the option it comes from.
function ns:BuyAtOrBelow(id, shown)
  local bestNonAH, useful
  for _, o in ipairs(ns:Options(id)) do
    if o.kind ~= "ah" and not (shown and not ns:WorthCounts(o)) then
      bestNonAH = bestNonAH or o
      if o.kind ~= "vendor" then useful = true end
    end
  end
  if bestNonAH and useful then
    return bestNonAH.value * (1 - (ns.db.settings.margin or 10) / 100), bestNonAH
  end
end

-- The finder and its saved shopping source use the disenchant route specifically,
-- even when selling/crafting the gear would be worth more. Copper limits round down.
function ns:DisenchantBuyLimit(id, source)
  local yield = ns:DisenchantYield(id)
  if not yield or (source and (source.id ~= id or source.band ~= yield.band or source.kind ~= yield.kind)) then return end
  for _, o in ipairs(ns:Options(id)) do
    if o.kind == "disenchant" then
      local cap = math.floor(o.value * (1 - (ns.db.settings.margin or 10) / 100))
      return cap > 0 and cap or nil, o.value, yield
    end
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
  if o.kind == "ah" then return "sell on the auction house" end
  if o.kind == "vendor" then return "sell to vendor" end
  local n = countSteps(o)
  if o.kind == "disenchant" and n == 1 then return "disenchant" end
  return n == 1 and "1 more step" or (n .. " more steps")
end

-- Every way starts with what you'd do ("Sell on the auction house"), so none of them
-- reads like a price to buy at (Magic, October 3: "Auction house, after 5% cut" in green
-- looked like the buying price, next to "Auction, cheapest").
function ns:OptionLabel(o)
  if o.kind == "ah" then
    local label = ("Sell on the auction house, after %g%% cut"):format(ns:AHCut() * 100)
    return (o.deposit or 0) > 0 and (label .. " and one unsold listing") or label
  end
  if o.kind == "vendor" then return o.vendorInstead and "Vendor it instead (deposit risk)" or "Sell to vendor" end
  if o.kind == "disenchant" then return "Disenchant" end
  local label = o.step .. ", " .. rest(o.next)
  if o.who then label = label .. " (" .. o.who .. ")" end
  return label
end

-- Which ways Worth to you counts (issue #15, October 22: "turn off the craft value"):
-- Settings, Tooltips. Only what tooltips and the Characters tab show; shuffles, the Buy
-- queue and shopping lists value every way.
local WORTH_SETTING = { ah = "worthAH", vendor = "worthVendor", disenchant = "worthDisenchant",
  craft = "worthCraft", convert = "worthCraft" }
function ns:WorthCounts(o)
  local key = WORTH_SETTING[o.kind]
  return not key or ns.db.settings[key] ~= false
end

-- Returns the best value and a list of options (each with a label), best first.
-- Only the three best recipes are listed, so tooltips stay short. shown: only the ways
-- ticked in Settings, Tooltips, Worth to you counts.
function ns:GetValue(id, shown)
  if not id or not ns.db then return end
  freshCache()
  local list, crafts, seen = {}, 0, {}
  for _, o in ipairs(allOptions(id)) do
    if shown and not ns:WorthCounts(o) then
      -- left out
    elseif o.kind ~= "craft" or (not seen[o.step] and crafts < 3) then
      if o.kind == "craft" then seen[o.step] = true; crafts = crafts + 1 end
      o.label = ns:OptionLabel(o)
      list[#list + 1] = o
    end
  end
  return list[1] and list[1].value, list
end

-- What a vendor pays for this copy, from the game's own tooltip: less for damaged gear
-- (owner's screenshot, November 9: Mantle of Honor at 42/45 durability, Sell Price 20s 69c
-- against Worth to you 21s 2c). A stack's is for the whole stack. nil if it doesn't say.
function ns.TooltipSellPrice(data)
  local want = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
  if not (want and data and data.lines) then return end
  for _, line in ipairs(data.lines) do
    if line.type == want and type(line.price) == "number" then return line.price end
  end
end

-- GetValue's answer for that copy: only ever lowers the vendor way, and leaves the shared
-- list alone. Returns best, options.
function ns:WorthOfCopy(best, options, copyPrice)
  if not (copyPrice and copyPrice > 0 and options) then return best, options end
  local changed, out = false, {}
  for i, o in ipairs(options) do
    if o.kind == "vendor" and copyPrice < o.value then
      local c = {}
      for k, v in pairs(o) do c[k] = v end
      c.value, changed = copyPrice, true
      out[i] = c
    else
      out[i] = o
    end
  end
  if not changed then return best, options end
  table.sort(out, function(a, b) return a.value > b.value end)
  return out[1].value, out
end

-- What one looted item is worth: the better of the auction house after the cut and a
-- vendor; items that bind when picked up only a vendor's (they can't be listed). Dungeon
-- runs (/fl runs) rank their drops by it. (From Sessions.lua, archived November 13.)
function ns:LootValue(id)
  local vendor = ns:GetSellPrice(id) or 0
  if ns.IsClassicBound and ns:IsClassicBound(id) then return vendor end
  local price = ns:GetPrice(id)
  local ah = price and ns:AfterCut(math.floor(price)) or 0
  return math.max(ah, vendor)
end
