local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Waylaid Crates: fill one with any bundle from its list (read from the crate's
-- tooltip), turn it in for Merchant's Favor. This works out the cheapest bundle at
-- today's prices, the total with the crate's own price, and gold per Favor.
-- A turn-in's Favor depends on the crate's level and kind (crateFavor); its money isn't counted.
---------------------------------------------------------------------------
local FAVOR = 3402
local PREFIX = "Waylaid Crate"
-- What a turn-in gives: a filled crate becomes a Sealed (Apprentice to Artisan) Crate of
-- the same quality. In the beta every one gave 10 Merchant's Favor (owner's turn-ins,
-- October 3). Now (player reports gathered on outof.games, November 24; Frank: a green
-- crate gives twice a white one): 5 Favor per level for a gathered (white) crate, 10 per
-- level for a crafted (green) one: Apprentice 5 / 10 up to Artisan 20 / 40. The Favor a
-- turn-in really gives is learned per sealed crate (crateFavorSeen) and wins over these.
-- Its money (a coin pouch at best, and that varies: Frank, November 24) isn't counted, so
-- the cost is what the crate takes. The first turn-in is a one-time quest (50 Favor).
local FAVOR_PER_LEVEL = 5

local function dim(t) return "|cff888888" .. t .. "|r" end
local function money(v) return v and ns.Money(math.floor(v + 0.5)) or dim("?") end

-- The Waylaid Crates by item number (Frank's saved crates, November 18), so they're found
-- in every language: a German player's Crates tab was empty (CurseForge comment, November
-- 18) because only the English name was checked. 248700 and 248701 aren't crates.
local CRATE_IDS = {}
for id = 248682, 248713 do if id ~= 248700 and id ~= 248701 then CRATE_IDS[id] = true end end
ns.CRATE_IDS = CRATE_IDS

-- Each crate's level and kind, by item number (from the English names, November 23), for the
-- Crates tab's filters (Frank, November 23). Earthly and Flowering herbs are both Herbs.
local CRATE_LEVELS = { "Apprentice", "Journeyman", "Expert", "Artisan" }
local CRATE_KINDS = { "Herbs", "Ore", "Ingots", "Textiles", "Fabrics", "Parts", "Curiosities" }
local CRATE_KIND = {
  [248682] = { 1, "Herbs" }, [248683] = { 1, "Ore" }, [248684] = { 1, "Textiles" }, [248685] = { 1, "Curiosities" },
  [248686] = { 2, "Herbs" }, [248687] = { 2, "Ore" }, [248688] = { 2, "Textiles" }, [248689] = { 2, "Curiosities" },
  [248690] = { 3, "Herbs" }, [248691] = { 3, "Herbs" }, [248692] = { 3, "Ore" }, [248693] = { 3, "Textiles" }, [248694] = { 3, "Curiosities" },
  [248695] = { 4, "Herbs" }, [248696] = { 4, "Herbs" }, [248697] = { 4, "Ore" }, [248698] = { 4, "Textiles" }, [248699] = { 4, "Curiosities" },
  [248702] = { 1, "Fabrics" }, [248703] = { 1, "Ingots" }, [248704] = { 1, "Parts" },
  [248705] = { 2, "Fabrics" }, [248706] = { 2, "Ingots" }, [248707] = { 2, "Parts" },
  [248708] = { 3, "Fabrics" }, [248709] = { 3, "Ingots" }, [248710] = { 3, "Parts" },
  [248711] = { 4, "Fabrics" }, [248712] = { 4, "Ingots" }, [248713] = { 4, "Parts" },
}
-- A crate's level (1-4) and kind; a crate added later is read from its English name.
local function crateKind(id, name)
  local k = CRATE_KIND[id]
  if k then return k[1], k[2] end
  local level, kind
  for i, l in ipairs(CRATE_LEVELS) do if name and name:find(l, 1, true) then level = i end end
  for _, x in ipairs(CRATE_KINDS) do if name and name:find(x, 1, true) then kind = x end end
  return level, kind
end
ns.CrateKind = crateKind

-- id: the item number (any language); name: the English name, for a crate added later.
local function isCrate(id, name)
  if id and CRATE_IDS[id] then return true end
  return name and name:sub(1, #PREFIX) == PREFIX or false
end
-- A filled crate: "Sealed Apprentice Crate" to "Sealed Elite Crate", five levels in each of
-- three qualities: 248765-248769 white, 248770-248774 green, 248775-248779 blue (ItemSparse,
-- build 1.60.1.71091, November 24; only the Apprentice ones were known before, so filling a
-- higher crate went unseen outside English). The English name as fallback.
local SEALED_FIRST = 248765
local SEALED_IDS = {}
for id = SEALED_FIRST, SEALED_FIRST + 14 do SEALED_IDS[id] = true end
ns.SEALED_CRATE_IDS = SEALED_IDS

-- Each crate's quality (ItemSparse, build 1.60.1.71091, November 24): Herbs, Ore, Textiles
-- and Curiosities are white, Fabrics, Ingots and Parts green. A crate added later: the game's.
local function crateQuality(id)
  if id and id >= 248682 and id <= 248699 then return 1 end
  if id and id >= 248702 and id <= 248713 then return 2 end
  local _, _, q = ns.GetItemInfo(id)
  return q
end
ns.CrateQuality = crateQuality

-- The sealed crate a crate becomes when filled: same level, same quality.
local function sealedFor(id)
  local q, level = crateQuality(id), crateKind(id, ns.ItemName(id))
  if not (q and level and q >= 1 and q <= 3) then return end
  return SEALED_FIRST + (q - 1) * 5 + (level - 1)
end
ns.CrateSealedFor = sealedFor

-- Merchant's Favor for turning in a crate: what a turn-in of its sealed crate gave, else
-- 5 per level, twice that for a crafted (green) crate. Second value: true if seen in game.
local function crateFavor(id)
  local q, level = crateQuality(id), crateKind(id, ns.ItemName(id))
  if not (q and level) then return end
  local sealed = sealedFor(id)
  local seen = sealed and ns.db and ns.db.crateFavorSeen and ns.db.crateFavorSeen[sealed]
  return seen or FAVOR_PER_LEVEL * level * (q >= 2 and 2 or 1), seen and true or false
end
ns.CrateFavor = crateFavor

-- Every crate's bundles by item number: { qty, itemID, qty, itemID, ... }, one item per
-- bundle, in the tooltip's order. Read from the English tooltips saved on Frank's second
-- account (November 24; the last line's color code had hidden Briarthorn, Tin Ore and
-- Large Glimmering Shard), item numbers checked in Forever's ItemSparse. Used in every
-- language, so no names need matching (a Spanish client's tooltip read "de polvo de alma":
-- issue #48). The tooltip is read only for a crate missing here.
local CRATE_BUNDLES = {
  [248682] = { 20, 2447, 20, 765, 10, 2449, 10, 785, 10, 2450 },        -- Apprentice Herbs
  [248683] = { 20, 2770, 20, 2771 },                                    -- Apprentice Ore
  [248684] = { 40, 2589, 20, 2318 },                                    -- Apprentice Textiles
  [248685] = { 20, 10940, 4, 10939, 6, 10978, 2, 11084 },               -- Apprentice Curiosities
  [248686] = { 10, 3820, 10, 2453, 10, 3355, 10, 3369, 10, 3356 },      -- Journeyman Herbs
  [248687] = { 10, 2775, 20, 2772 },                                    -- Journeyman Ore
  [248688] = { 20, 2592, 40, 4306, 20, 2319 },                          -- Journeyman Textiles
  [248689] = { 20, 11083, 4, 11082, 6, 11138, 2, 11139 },               -- Journeyman Curiosities
  [248690] = { 20, 3357, 10, 3818, 10, 3821, 10, 3358 },                -- Earthly Expert Herbs
  [248691] = { 10, 3819, 10, 4625, 20, 8831, 10, 8836 },                -- Flowering Expert Herbs
  [248692] = { 10, 2776, 20, 3858 },                                    -- Expert Ore
  [248693] = { 40, 4338, 20, 4234 },                                    -- Expert Textiles
  [248694] = { 20, 11137, 4, 11135, 6, 11177, 2, 11178 },               -- Expert Curiosities
  [248695] = { 10, 13464, 20, 8838, 10, 8839, 10, 8845, 10, 8846 },     -- Earthly Artisan Herbs
  [248696] = { 20, 13463, 20, 13465, 20, 13466, 20, 13467 },            -- Flowering Artisan Herbs
  [248697] = { 10, 7911, 20, 10620, 20, 11370 },                        -- Artisan Ore
  [248698] = { 40, 14047, 20, 4304, 20, 8170 },                         -- Artisan Textiles
  [248699] = { 20, 11176, 4, 11175, 6, 14343, 2, 14344 },               -- Artisan Curiosities
  [248702] = { 2, 4231, 20, 2996 },                                     -- Apprentice Fabrics
  [248703] = { 20, 2840, 20, 3576, 10, 2841 },                          -- Apprentice Ingots
  [248704] = { 16, 4359, 16, 4361, 4, 4363 },                           -- Apprentice Parts
  [248705] = { 6, 2997, 10, 4305, 2, 4233 },                            -- Journeyman Fabrics
  [248706] = { 10, 2842, 20, 3575 },                                    -- Journeyman Ingots
  [248707] = { 8, 4371, 7, 4375, 4, 4382, 45, 10558 },                  -- Journeyman Parts
  [248708] = { 8, 4339, 2, 4236 },                                      -- Expert Fabrics
  [248709] = { 20, 3860, 15, 3859, 10, 3577 },                          -- Expert Ingots
  [248710] = { 8, 4387, 5, 10559, 12, 10560, 5, 10561 },                -- Expert Parts
  [248711] = { 8, 14048, 2, 8172 },                                     -- Artisan Fabrics
  [248712] = { 2, 11371, 10, 6037, 20, 12359 },                         -- Artisan Ingots
  [248713] = { 5, 15994, 5, 18631, 2, 16000 },                          -- Artisan Parts
}
ns.CRATE_BUNDLES = CRATE_BUNDLES
local crateItems   -- itemID = true for every item a crate takes (Groups.lua's Crates group)
function ns.CrateTakesItem(id)
  if not crateItems then
    crateItems = {}
    for _, list in pairs(CRATE_BUNDLES) do
      for i = 2, #list, 2 do crateItems[list[i]] = true end
    end
  end
  return crateItems[id] or false
end
local function isSealed(id, name)
  if id and SEALED_IDS[id] then return true end
  return name and name:find("^Sealed") and name:find("Crate", 1, true) and true or false end
-- A crate's name without "Waylaid Crate: " (or its translation): "Expert Ingots".
local function shortName(name)
  name = name or "?"
  return name:match("^[^:]+:%s*(.+)$") or name
end

---------------------------------------------------------------------------
-- Reading a crate's bundles from its tooltip
---------------------------------------------------------------------------
-- One bundle line without its dash: "10 Copper Bar and 5 Tin Bar" -> parts. Any language:
-- each number starts an item, and the word just before the next number ("and", "und",
-- "et") or a comma ends it.
local function parseParts(rest)
  local parts, starts = {}, {}
  local pos = 1
  while true do
    local s, e = rest:find("%f[%d]%d+%s*x?%s+", pos)
    if not s then break end
    -- A number counts only at the start or after a space or comma ("x10" glued on doesn't).
    if s == 1 or rest:sub(s - 1, s - 1):find("[%s,]") then starts[#starts + 1] = { s = s, e = e } end
    pos = e + 1
  end
  for i, st in ipairs(starts) do
    local qty = tonumber(rest:match("^(%d+)", st.s))
    local nextS = starts[i + 1] and starts[i + 1].s
    local name = rest:sub(st.e + 1, nextS and nextS - 1 or #rest)
    name = name:gsub("%s+$", "")
    if nextS then
      if name:find(",$") then name = name:gsub(",$", "")
      else name = name:gsub("%s+%S+$", "") end   -- the joining word
      name = name:gsub("[,%s]+$", "")
    end
    name = name:gsub("[%.;]$", "")
    if qty and name ~= "" then parts[#parts + 1] = { qty = qty, name = name } end
  end
  return parts
end

-- "- 20 Strange Dust" lines -> { { qty = 20, name = "Strange Dust" }, ... } per bundle.
-- A bundle of several items ("- 10 Copper Bar and 5 Tin Bar") becomes several parts.
-- English tooltips: only the lines after "any bundle". Other languages (that line is
-- translated): every "- <number> ..." line.
local function parseBundles(lines)
  local all, english, inList = {}, {}, false
  for _, text in ipairs(lines) do
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      -- Color codes off: the last line ends in |r ("Tin Ore|r" matched no item).
      line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      if line:find("any bundle", 1, true) then inList = true end
      local rest = line:match("^%s*%-%s*(%d.+)$")
      if rest then
        local parts = parseParts(rest)
        if #parts > 0 then
          all[#all + 1] = parts
          if inList then english[#english + 1] = parts end
        end
      end
    end
  end
  return inList and english or all
end
ns.CrateBundlesFromLines = parseBundles

-- Bundles for a crate: by item number for the crates above (saved over any read from a
-- tooltip before), else read once from its tooltip and saved.
local fixedDone = {}
local function crateInfo(id)
  local saved = ns.db.crates[id]
  local list = CRATE_BUNDLES[id]
  if list then
    if not fixedDone[id] then
      local bundles = {}
      for i = 1, #list, 2 do bundles[#bundles + 1] = { { qty = list[i], id = list[i + 1] } } end
      local _, _, _, _, minLevel = ns.GetItemInfo(id)
      saved = { name = saved and saved.name, level = minLevel or (saved and saved.level), bundles = bundles }
      ns.db.crates[id] = saved
      fixedDone[id] = true
    end
    saved.name = ns.GetItemInfo(id) or saved.name or ns.ItemName(id)
    return saved
  end
  if saved and saved.bundles and #saved.bundles > 0 then return saved end
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
  if not ok or not data or not data.lines then return end
  local texts = {}
  for _, l in ipairs(data.lines) do texts[#texts + 1] = ns.Readable(l.leftText) or "" end
  local bundles = parseBundles(texts)
  if #bundles == 0 then return end
  local name, _, _, _, minLevel = ns.GetItemInfo(id)
  saved = { name = name or ns.ItemName(id), level = minLevel, bundles = bundles }
  ns.db.crates[id] = saved
  return saved
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------
-- Item names to IDs, from names saved or already loaded by the game.
-- Built again only for a name it doesn't know, at most every 10 minutes. It never asks
-- the game for items it hasn't loaded: asking for every priced item (about 6,000) made the
-- game load them all, 6,304 item loads in 14 seconds and a 650 ms freeze on a crate hover
-- (Frank's AN30, November 19). Names found are saved with the crate as item IDs (CrateReport).
local NAME_INDEX_KEEP = 600
local nameIndex, nameIndexTime = {}, -math.huge
local function loadedName(id)
  local cached = C_Item and C_Item.IsItemDataCachedByID
  if not cached then return end
  local ok, yes = pcall(cached, id)
  if ok and yes then return (ns.GetItemInfo(id)) end
end
local function idForName(name)
  if not name then return end
  if nameIndex[name] then return nameIndex[name] end
  if GetTime() - nameIndexTime > NAME_INDEX_KEEP then
    nameIndex, nameIndexTime = {}, GetTime()
    for id, n in pairs(ns.FOREVER_ITEM_NAMES or {}) do nameIndex[n] = id end
    for id, n in pairs(ns.db.itemNames) do nameIndex[n] = id end
    for _, list in ipairs({ ns.db.prices[ns.MarketKey()] or {}, ns.db.vendorBuy }) do
      for id in pairs(list) do
        if not ns.db.itemNames[id] then
          local n = loadedName(id)
          if n then nameIndex[n] = id end
        end
      end
    end
  end
  return nameIndex[name]
end
ns.CrateIdForName = idForName
function ns.CrateNamesReset() nameIndexTime = -math.huge end   -- (tests)

-- What buying qty of an item costs: from a vendor, or across the cheapest auction
-- listings (the price ladder saved by scans). nil if unknown or not enough listed.
-- Whichever is cheaper, a vendor or the auction house (a limited vendor's price used
-- to win even when the auction house was far cheaper).
local function ahCostToBuy(id, qty)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not rec or rec.none or not rec.m then return end
  if rec.l then
    local cost, got = 0, 0
    for p, c in rec.l:gmatch("(%d+):(%d+)") do
      p, c = tonumber(p), tonumber(c)
      local take = math.min(c - got, qty - got)
      if take > 0 then cost, got = cost + take * p, got + take end
      if got >= qty then return cost end
    end
    -- More than the ladder holds: the rest at the average price.
    return cost + (qty - got) * (rec.a or rec.m)
  end
  return qty * (rec.a or rec.m)
end

-- The most you'd pay for one, buying qty from the cheapest listings up (the last price
-- level needed), so a shopping list's limit can get them all. nil if not listed.
local function priceToGet(id, qty)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not rec or rec.none or not rec.m then return end
  local top
  for p, c in (rec.l or ""):gmatch("(%d+):(%d+)") do
    top = tonumber(p)
    if tonumber(c) >= qty then return top end
  end
  return math.max(top or 0, rec.a or rec.m)
end

-- Puts a crate's cheapest fill (or the bundle given) on a shopping list named after the
-- crate (owner, October 3). "Keep this many", so what's in your bags and bank counts.
function ns:CrateToShoppingList(r, bundle)
  bundle = bundle or (r and (r.cheapest or r.bundles[1]))
  if not bundle then return end
  local name = "Crate: " .. shortName(r.name)
  local list
  for _, l in ipairs(ns:ShoppingLists()) do if l.name == name then list = l end end
  if not list then
    list = ns:NewShoppingList(name)
    -- What you have counts towards Want (the only lists that do): the queue buys what
    -- the crate is short of.
    list.countHave = true
  else
    for i, l in ipairs(ns:ShoppingLists()) do if l == list then ns:SelectShoppingList(i) end end
  end
  -- Temporary (owner, October 3): it goes when the last crate is filled, or after a week.
  list.temp, list.tempT = r.name, time()
  -- How many crates: the crate's own Want (kept if the list was made before).
  local count = 1
  for _, e in ipairs(list.items) do
    if e.id == r.id and e.qty then count = e.qty end
  end
  -- A different bundle than last time: the old bundle's items go.
  local newParts, keep = {}, { [r.id or 0] = true }
  for _, p in ipairs(bundle.parts) do
    if p.id then newParts[#newParts + 1] = { p.id, p.qty }; keep[p.id] = true end
  end
  for _, old in ipairs(list.crateParts or {}) do
    if not keep[old[1]] then
      for i = #list.items, 1, -1 do if list.items[i].id == old[1] then table.remove(list.items, i) end end
    end
  end
  list.crateID, list.crateParts = r.id, newParts

  local added, unknown = 0, {}
  -- The crate itself too (owner, October 3): done if you have enough of them.
  if r.id then
    local e = ns:AddToShoppingList(list, r.id, priceToGet(r.id, count) or ns:GetVendorBuyPrice(r.id) or 0, count)
    e.done = nil
    added = added + 1
  end
  for _, p in ipairs(bundle.parts) do
    if p.id then
      local e = ns:AddToShoppingList(list, p.id, priceToGet(p.id, p.qty * count) or ns:GetVendorBuyPrice(p.id) or 0)
      e.done = nil   -- sent again: back in the queue if you're short
      added = added + 1
    else
      unknown[#unknown + 1] = p.name
    end
  end
  ns:ScaleCrateList(list)
  ns:Print(("Added %d %s for %s to the shopping list \"%s\". Set the crate's Want there to fill more than one; tick Buy from this list in the Buy queue to buy what you're short (/fl lists). The list goes when you fill the last crate.%s"):format(
    added, added == 1 and "item" or "items", r.name or "the crate", name,
    #unknown > 0 and (" Not added (not seen in a scan yet): " .. table.concat(unknown, ", ") .. ".") or ""))
  return list
end

-- A crate list's crate Want is how many crates to fill: each bundle item wants its
-- amount times that, like a Craft item's materials (owner, October 3). Limits go up
-- if more are needed than the old limit could buy. Returns the item IDs changed.
function ns:ScaleCrateList(list)
  local count = 1
  for _, e in ipairs(list.items) do
    if e.id == list.crateID then count = e.qty or 1 end
  end
  local ids = {}
  for _, part in ipairs(list.crateParts or {}) do
    for _, e in ipairs(list.items) do
      if e.id == part[1] then
        local want = part[2] * count
        if e.qty ~= want then
          e.qty = want
          if ns:HaveCount(e.id) < want then e.done = nil end
          local need = priceToGet(e.id, want)
          if need and (e.max or 0) > 0 and need > e.max then e.max = need end
          ids[#ids + 1] = e.id
        end
      end
    end
  end
  return ids
end

-- Temporary crate lists: filling a crate (crateName) takes one off its list, and the
-- list goes with the last one; with no name, lists older than a week go.
local TEMP_LIST_SECONDS = 7 * 86400
local function dropCrateLists(crateName)
  local lists = ns:ShoppingLists()
  for i = #lists, 1, -1 do
    local l = lists[i]
    if l.temp and crateName and l.temp == crateName then
      local crate
      for _, e in ipairs(l.items) do if e.id == l.crateID then crate = e end end
      local left = crate and (crate.qty or 1) - 1 or 0
      if left > 0 then
        crate.qty = left
        ns:ScaleCrateList(l)
        ns:Print(("Shopping list \"%s\": %d %s left to fill."):format(l.name or "?", left, left == 1 and "crate" or "crates"))
      else
        ns:DeleteShoppingList(i)
        ns:Print(("Removed the shopping list \"%s\" (last crate filled)."):format(l.name or "?"))
      end
    elseif l.temp and not crateName and time() - (l.tempT or 0) > TEMP_LIST_SECONDS then
      ns:DeleteShoppingList(i)
      ns:Print(("Removed the shopping list \"%s\" (a week old)."):format(l.name or "?"))
    end
  end
end
ns:OnReady(function() dropCrateLists() end)

function ns:CostToBuy(id, qty)
  local vendor = ns:GetVendorBuyPrice(id)
  local ah = ahCostToBuy(id, qty)
  if vendor and ah then return math.min(vendor * qty, ah) end
  return vendor and vendor * qty or ah
end

local function bagCount(id)
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  return id and count and count(id, false, false, true) or 0
end

-- Everything about one crate: bundles with costs, the cheapest, totals.
function ns:CrateReport(id)
  local info = crateInfo(id)
  if not info then return end
  local r = { id = id, name = info.name, level = info.level, bundles = {} }
  for _, parts in ipairs(info.bundles) do
    local b = { parts = {}, cost = 0, have = true }
    for _, p in ipairs(parts) do
      -- (p is the saved bundle part: its item ID is kept once found, so later looks, and
      -- any language, don't need the name.)
      local pid = p.id or idForName(p.name)
      if pid and not p.id then p.id = pid end
      local cost = pid and ns:CostToBuy(pid, p.qty)
      local bags, bank, alts, byAlt = ns:ItemLocations(pid)
      local owned = bags + bank + alts
      b.parts[#b.parts + 1] = { id = pid, name = pid and ns.ItemName(pid) or p.name, qty = p.qty, cost = cost, owned = owned,
        bags = bags, bank = bank, alts = alts, byAlt = byAlt }
      if cost then b.cost = b.cost + cost else b.cost = nil end
      if owned < p.qty then b.have = false end
    end
    r.bundles[#r.bundles + 1] = b
    if b.cost and (not r.cheapest or b.cost < r.cheapest.cost) then r.cheapest = b end
  end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  r.owned = bagCount(id) > 0
  -- How many of this crate you have: bags, bank and your other characters (their last visit).
  local cb, cbank, calts, cby = ns:ItemLocations(id)
  r.have, r.haveBags, r.haveBank, r.haveAlts, r.haveBy = cb + cbank + calts, cb, cbank, calts, cby
  r.tier, r.kind = crateKind(id, info.name)
  r.cratePrice = (not r.owned) and rec and not rec.none and rec.m or nil
  r.favor, r.favorSeen = crateFavor(id)
  if r.cheapest then
    r.total = r.cheapest.cost + (r.cratePrice or 0)
    if r.favor and r.favor > 0 then r.perFavor = r.total / r.favor; r.sortKey = r.perFavor end
  end
  return r
end

-- Every crate seen: in the last scan or in the bags.
function ns:KnownCrates()
  local ids, seen = {}, {}
  local function consider(id)
    if seen[id] then return end
    seen[id] = true
    if isCrate(id, ns.ItemName(id)) then ids[#ids + 1] = id end
  end
  for id in pairs(ns.db.prices[ns.MarketKey()] or {}) do consider(id) end
  for id in pairs(ns.db.crates) do consider(id) end
  if C_Container then
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
      for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then consider(info.itemID) end
      end
    end
  end
  return ids
end

---------------------------------------------------------------------------
-- Filling a crate: the Waylaid Crate leaves the bags and a Sealed Apprentice Crate
-- turns up in the same update. That's when its materials are used, so its shopping
-- list counts down then (a crate sold or mailed away doesn't count).
---------------------------------------------------------------------------
local lastFavor, cratesInBags, sealedInBags = nil, {}, 0

local sealedById = {}   -- filled crates in the bags by item number (which quality left)

local function crateCounts()
  local counts, sealed, byId = {}, 0, {}
  if not C_Container then return counts, sealed, byId end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local name = info and info.itemID and ns.ItemName(info.itemID)
      if isCrate(info and info.itemID, name) then counts[name] = (counts[name] or 0) + (info.stackCount or 1)
      elseif isSealed(info and info.itemID, name) then
        sealed = sealed + (info.stackCount or 1)
        byId[info.itemID] = (byId[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return counts, sealed, byId
end

-- Learning a turn-in's Favor: a sealed crate leaves the bags and Favor
-- goes up within 5 seconds of it, in either order.
local sealedGone, favorGain
local function learnFavor()
  if not (sealedGone and favorGain) or math.abs(sealedGone.t - favorGain.t) > 5 then return end
  local sealed, n = sealedGone.id, favorGain.n
  sealedGone, favorGain = nil, nil
  if not (ns.db and sealed and n and n > 0) then return end
  ns.db.crateFavorSeen = ns.db.crateFavorSeen or {}
  if ns.db.crateFavorSeen[sealed] ~= n then
    ns:Debug("Crate turn-in,", ns.ItemName(sealed), sealed, "gives", n, "Favor")
    ns.db.crateFavorSeen[sealed] = n
    if ns.RefreshCrates then ns:RefreshCrates() end
  end
end
ns.CrateLearnFavor = function(sealed, n, t)   -- (tests)
  if sealed then sealedGone = { id = sealed, t = t or GetTime() } end
  if n then favorGain = { n = n, t = t or GetTime() } end
  learnFavor()
end

local function favorNow()
  local get = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo   -- (guarded: pcall can't catch the look-up)
  if not get then return nil end
  local ok, info = pcall(get, FAVOR)
  return ok and info and info.quantity or nil
end

ns:On("BAG_UPDATE_DELAYED", function()
  if not ns.db then return end
  local now, sealed, byId = crateCounts()
  for id, n in pairs(sealedById) do
    if (byId[id] or 0) < n and SEALED_IDS[id] then
      sealedGone = { id = id, t = GetTime() }
      learnFavor()
    end
  end
  sealedById = byId
  if sealed > sealedInBags then
    for name, n in pairs(cratesInBags) do
      if (now[name] or 0) < n then
        ns:Debug("Crate filled:", name)
        dropCrateLists(name)
      end
    end
  end
  cratesInBags, sealedInBags = now, sealed
end)

ns:On("CURRENCY_DISPLAY_UPDATE", function(currencyID)
  if currencyID and currencyID ~= FAVOR then return end
  local q = favorNow()
  if not q then return end
  if lastFavor and q > lastFavor then
    ns:Debug("Merchant's Favor:", "+" .. (q - lastFavor))
    favorGain = { n = q - lastFavor, t = GetTime() }
    learnFavor()
    if ns.NoteCrateTurnIn then ns:NoteCrateTurnIn() end   -- (the coin pouch it gives: Writs.lua)
  end
  lastFavor = q
  if ns.db then ns.db.favor[ns.CharKey()] = q end
end)

ns:On("PLAYER_ENTERING_WORLD", function()
  C_Timer.After(3, function()
    lastFavor = favorNow()
    if lastFavor and ns.db then ns.db.favor[ns.CharKey()] = lastFavor end
    cratesInBags, sealedInBags, sealedById = crateCounts()
  end)
end)

---------------------------------------------------------------------------
-- Tooltip line on crates
---------------------------------------------------------------------------
-- Kept TIP_KEEP seconds per crate: the tooltip asks again on every redraw.
local TIP_KEEP, tipCache = 30, {}
function ns:CrateTooltipLine(id)
  if not ns.db.settings.crates then return end
  if not isCrate(id, ns.ItemName(id)) then return end
  local c = tipCache[id]
  if c and GetTime() - c.t < TIP_KEEP then return c.line or nil end
  local line = ns:CrateTooltipText(id)
  tipCache[id] = { t = GetTime(), line = line or false }
  return line
end

function ns:CrateTooltipText(id)
  local r = ns:CrateReport(id)
  if not r or not r.cheapest then return end
  local parts = {}
  for _, p in ipairs(r.cheapest.parts) do parts[#parts + 1] = p.qty .. " " .. p.name end
  local per = ""
  if r.perFavor then
    per = (", about %s per Favor (%d Favor)"):format(money(r.perFavor), r.favor)
  end
  return ("Cheapest fill: %s, %s%s"):format(table.concat(parts, " + "), money(r.cheapest.cost), per)
end

---------------------------------------------------------------------------
-- The Crates tab
---------------------------------------------------------------------------
local ROW = 24
local f
local rows, details = {}, {}
local openID
local COLS = {
  { key = "name", label = "Crate" },
  { key = "have", label = "Have", w = 40 },
  { key = "level", label = "Level", w = 44 },
  { key = "fill", label = "Cheapest fill", w = 150 },
  { key = "fillCost", label = "Fill cost", w = 74 },
  { key = "cratePrice", label = "Price", w = 70 },
  { key = "total", label = "Total", w = 80 },
  { key = "favor", label = "Favor", w = 44 },
  { key = "perFavor", label = "Per Favor", w = 80 },
}

-- The filters (Frank, November 23): level, kind, and only the crates you have.
local function S()
  local s = ns.db.settings
  s.crateTab = type(s.crateTab) == "table" and s.crateTab or {}
  local c = s.crateTab
  c.level = c.level or "all"
  c.kind = c.kind or "all"
  return c
end

function ns:BuildCrates(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local lopts = { { value = "all", label = "All" } }
  for i, l in ipairs(CRATE_LEVELS) do lopts[#lopts + 1] = { value = i, label = l } end
  f.level = T:Choice(f, lopts, function(v) S().level = v; ns:RefreshCrates() end)
  f.level:SetPoint("TOPLEFT", 2, -2)
  f.kind = T:Dropdown(f, 130, function(v) S().kind = v; ns:RefreshCrates() end)
  f.kind:SetPoint("LEFT", f.level, "RIGHT", 12, 0)
  local kopts = { { value = "all", label = "Any kind" } }
  for _, k in ipairs(CRATE_KINDS) do kopts[#kopts + 1] = { value = k, label = k } end
  f.kind:SetOptions(kopts)
  f.mine = T:Check(f, function(self) S().mine = self:GetChecked() or nil; ns:RefreshCrates() end)
  f.mine:SetPoint("LEFT", f.kind, "RIGHT", 14, 0)
  f.mine.label:SetText("Only ones I have")
  f.mine:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ns:TooltipAddLine("Only the crates you have", 1, 1, 1)
    ns:TooltipAddLine("In your bags, your bank or on your other characters (as of their last visit).", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  f.mine:HookScript("OnLeave", function() GameTooltip:Hide() end)
  f.info = T:Text(f, 12, T.dim)
  f.info:SetPoint("TOPLEFT", f.level, "BOTTOMLEFT", 0, -6)
  f.info:SetPoint("RIGHT", f, "RIGHT", -2, 0)
  f.info:SetJustifyH("LEFT")
  -- The headings sit under the text however many lines it takes (with the themes' fonts
  -- it ran into them: owner's screenshots, October 4).
  f.header = CreateFrame("Frame", nil, f)
  f.header:SetPoint("TOP", f.info, "BOTTOM", 0, -6)
  f.header:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.header:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.header:SetHeight(22)
  T:Fill(f.header, { 1, 1, 1, 0.05 })
  f.heads = {}
  f.sf, f.content = T:Scroll(f)
  f.sf:SetPoint("TOP", f.header, "BOTTOM", 0, -2)
  f.sf:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.sf:SetPoint("BOTTOMRIGHT")
  f.empty = T:Text(f.content, 12, T.dim)
  f.empty:SetPoint("TOPLEFT", 8, -8)
  f.empty:SetText("No Waylaid Crates seen yet. Run a full scan, or put a crate in your bags.")
  return f
end

local function layout(width)
  local fixed = 0
  for _, c in ipairs(COLS) do fixed = fixed + (c.w or 0) + 8 end
  local x, out = 4, {}
  for _, c in ipairs(COLS) do
    local w = c.w or math.max(160, width - fixed - 4)
    out[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  return out
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, f.content)
  r:SetHeight(ROW)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cells = {}
  for _, c in ipairs(COLS) do
    local fs = T:Text(r, 12)
    fs:SetWordWrap(false)
    fs:SetJustifyH((c.key == "name" or c.key == "fill") and "LEFT" or "RIGHT")
    r.cells[c.key] = fs
  end
  r:SetScript("OnClick", function(self) openID = (openID ~= self.id) and self.id or nil; ns:RefreshCrates() end)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetItemByID(self.id)
    local x = self.report
    if x and x.have and x.have > 0 then
      ns:TooltipAddLine(" ")
      ns:TooltipAddDoubleLine("You have", tostring(x.have), 0.7, 0.7, 0.7, 1, 1, 1)
      if x.haveBags > 0 then ns:TooltipAddDoubleLine("  In your bags", tostring(x.haveBags), 0.7, 0.7, 0.7, 1, 1, 1) end
      if x.haveBank > 0 then ns:TooltipAddDoubleLine("  In your bank", tostring(x.haveBank), 0.7, 0.7, 0.7, 1, 1, 1) end
      for name, n in pairs(x.haveBy or {}) do ns:TooltipAddDoubleLine("  " .. name, tostring(n), 0.7, 0.7, 0.7, 1, 1, 1) end
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

-- Opened crate: every bundle, cheapest marked, click an item to search for it.
local function getDetail(i)
  if details[i] then return details[i] end
  local d = CreateFrame("Frame", nil, f.content)
  T:Fill(d, { 1, 1, 1, 0.035 })
  d.lines = {}
  -- The cheapest fill onto a shopping list, to buy with the Buy queue.
  d.toList = T:Button(d, "Add cheapest fill to a shopping list", 240, function()
    if d.report then ns:CrateToShoppingList(d.report) end
  end, 20)
  d.toList:SetPoint("BOTTOMLEFT", 14, 6)
  details[i] = d
  return d
end

local function detailLine(d, j)
  if d.lines[j] then return d.lines[j] end
  local b = CreateFrame("Button", nil, d)
  b:SetHeight(20)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(14, 14)
  b.icon:SetPoint("LEFT", 14, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.text = T:Text(b, 11)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetJustifyH("LEFT")
  b.right = T:Text(b, 11)
  b.right:SetPoint("RIGHT", -10, 0)
  b.right:SetJustifyH("RIGHT")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
  b:SetScript("OnClick", function(self)
    if self.itemID and not ns:SearchAuctionHouse(self.itemID) then
      ns:Print("Open the auction house, then click an item to search for it.")
    end
  end)
  -- Hover: which alts have it.
  b:SetScript("OnEnter", function(self)
    local p = self.part
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    ns:TooltipAddLine(p.name, 1, 1, 1)
    ns:TooltipAddDoubleLine("In your bags", tostring(p.bags or 0), 0.85, 0.85, 0.85, 1, 1, 1)
    ns:TooltipAddDoubleLine("In your bank", tostring(p.bank or 0), 0.85, 0.85, 0.85, 1, 1, 1)
    for name, n in pairs(p.byAlt or {}) do ns:TooltipAddDoubleLine(name, tostring(n), 0.85, 0.85, 0.85, 1, 1, 1) end
    ns:TooltipAddLine("Bank and alts as of their last visit. Click to search the auction house.", T.accent[1], T.accent[2], T.accent[3], true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  d.lines[j] = b
  return b
end

function ns:RefreshCrates()
  if not f or not f:IsShown() then return end
  local width = f:GetWidth() - 12
  local lay = layout(width)
  for i, c in ipairs(COLS) do
    local h = f.heads[i]
    if not h then h = T:Text(f.header, 11, T.dim); f.heads[i] = h end
    h:ClearAllPoints()
    h:SetPoint("LEFT", f.header, "LEFT", lay[c.key].x, 0)
    h:SetWidth(lay[c.key].w)
    h:SetJustifyH((c.key == "name" or c.key == "fill") and "LEFT" or "RIGHT")
    h:SetText(c.label .. (c.key == "perFavor" and " ^" or ""))
  end

  local s = S()
  f.level:SetValue(s.level)
  f.kind:SetValue(s.kind)
  f.mine:SetChecked(s.mine and true or false)
  local reports, unread, hidden = {}, 0, 0
  for _, id in ipairs(ns:KnownCrates()) do
    local r = ns:CrateReport(id)
    if not r then unread = unread + 1
    elseif (s.level == "all" or r.tier == s.level) and (s.kind == "all" or r.kind == s.kind) and (not s.mine or r.have > 0) then
      reports[#reports + 1] = r
    else hidden = hidden + 1 end
  end
  table.sort(reports, function(a, b)
    if (a.sortKey ~= nil) ~= (b.sortKey ~= nil) then return a.sortKey ~= nil end
    if a.sortKey and b.sortKey and a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
    return (a.name or "") < (b.name or "")
  end)

  local favor = ns.db.favor[ns.CharKey()]
  local pouch = ns.PouchText and ns:PouchText("crate")
  f.info:SetText(("Cheapest way to fill each Waylaid Crate at your last scan's prices, least gold per Favor first. A turn-in gives 5 Merchant's Favor a level for gathered goods (Herbs, Ore, Textiles, Curiosities), 10 a level for crafted goods (Fabrics, Ingots, Parts); Favor turns white once a turn-in has checked it. Its money varies, so it isn't counted%s. You have %s Merchant's Favor on this character.%s Click a crate for every bundle."):format(
    pouch and (" (coin pouches from crates: " .. pouch .. ")") or "", favor and tostring(favor) or "?", unread > 0 and (" %d crates still loading."):format(unread) or ""))

  f.content:SetWidth(width)
  local y, n, nd = 0, 0, 0
  for i, r in ipairs(reports) do
    n = n + 1
    local row = getRow(n)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    row.id = r.id
    row.stripe:SetShown(i % 2 == 0)
    row.icon:SetTexture(ns:ItemIcon(r.id))
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", lay.name.x, 0)
    local parts = {}
    for _, p in ipairs(r.cheapest and r.cheapest.parts or {}) do parts[#parts + 1] = p.qty .. " " .. p.name end
    row.report = r
    local values = {
      name = shortName(r.name),
      have = r.have > 0 and (T:AccentCode() .. r.have .. "|r") or dim("-"),
      level = r.level and tostring(r.level) or "",
      fill = #parts > 0 and table.concat(parts, " + ") .. (r.cheapest.have and dim(" (have)") or "") or dim("no prices yet"),
      fillCost = r.cheapest and money(r.cheapest.cost) or dim("?"),
      cratePrice = r.owned and dim("owned") or money(r.cratePrice),
      total = r.total and money(r.total) or dim("?"),
      favor = r.favor and ((r.favorSeen and "" or "|cffbbbbbb") .. r.favor .. (r.favorSeen and "" or "|r")) or dim("?"),
      perFavor = r.perFavor and ("|cff7fd39c" .. money(r.perFavor) .. "|r") or dim("?"),
    }
    for key, fs in pairs(row.cells) do
      fs:ClearAllPoints()
      local x, w = lay[key].x, lay[key].w
      if key == "name" then x, w = x + 22, w - 22 end
      fs:SetPoint("LEFT", row, "LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetText(values[key])
    end
    row:Show()
    y = y + ROW

    if openID == r.id then
      nd = nd + 1
      local d = getDetail(nd)
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
      d:SetWidth(width)
      local j = 0
      for _, b in ipairs(r.bundles) do
        for k, p in ipairs(b.parts) do
          j = j + 1
          local line = detailLine(d, j)
          line:ClearAllPoints()
          line:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -(4 + (j - 1) * 20))
          line:SetWidth(width)
          line.itemID, line.part = p.id, p
          line.icon:SetTexture(p.id and ns:ItemIcon(p.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
          local mark = (b == r.cheapest and k == 1) and (T:AccentCode() .. "cheapest|r  ") or ""
          line.text:SetText(("%s%d x %s  %s"):format(mark, p.qty, p.name,
            dim(("you have %d (bags %d, bank %d, alts %d)%s"):format(p.owned, p.bags or 0, p.bank or 0, p.alts or 0,
              p.id and "" or ", price unknown"))))
          line.right:SetText(k == 1 and (b.cost and money(b.cost) or dim("?")) or "")
          line:Show()
        end
      end
      for k = j + 1, #d.lines do d.lines[k]:Hide() end
      d.report = r
      d.toList:SetShown(r.cheapest ~= nil)
      local extra = r.cheapest and 30 or 0
      d:SetHeight(j * 20 + 8 + extra)
      d:Show()
      y = y + j * 20 + 12 + extra
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  for i = nd + 1, #details do details[i]:Hide() end
  f.empty:SetText(hidden > 0 and ("No crate matches these filters (%d hidden by them)."):format(hidden)
    or "No Waylaid Crates seen yet. Run a full scan, or put a crate in your bags.")
  f.empty:SetShown(n == 0)
  f.content:SetHeight(math.max(y, 30))
  f.sf.UpdateScrollBar()
end
