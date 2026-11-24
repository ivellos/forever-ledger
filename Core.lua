local ADDON, ns = ...
-- When the addon's files started loading (Core.lua is first), for /fl perf.
ns.loadStart = debugprofilestop and debugprofilestop() or nil
do
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(getMeta, ADDON, "Version")
  -- Release builds replace @project-version@ with the real number; local copies show "dev".
  ns.VERSION = (ok and v and not v:find("@", 1, true)) and v or "dev"
end
ns.PREFIX = "|cffb9a2ffForever Ledger:|r"

local DEFAULTS = {
  schema = 11,
  charRealm = {},   -- [full name] = the realm last read for that character, for when the game gives none (schema 11)
  profAliases = {}, -- [the game's name for a profession] = English key (Professions.lua, schema 10)
  chars = {},       -- [charKey] = { name, realm, class, level, faction, updated, profs = { [profName] = { rank, max, updated, recipes = {...} } } }
  prices = {},      -- [marketKey][itemID] = { m = cheapest, a = avg of cheapest 20, q = listed, t = time, src = "scan" }
  vendorSell = {},  -- [itemID] = copper the vendor pays you
  vendorBuy = {},   -- [itemID] = { p = copper you pay, t = time, src, lim = limited supply }
  gold = {},        -- [charKey][hour] = copper (History.lua)
  money = {},       -- [charKey][day][source] = copper in or out
  sales = {},       -- auction house sales: { t, c = charKey, n = item name, a = copper received, cut }
  purchases = {},   -- auction house purchases: { t, c, id, q, a }
  vendorLog = {},   -- vendor buys and sells: { t, c, id, q, a, s = "buy" | "sell" }
  otherLog = {},    -- other money one by one, 30 days: { t, c, s = source, a = copper } (History.lua; day totals stay in money)
  otherLogSince = {}, -- [charKey] = when its other money began to be logged one by one (Ledger.lua uses otherLog from then)
  otherLogCut = {},   -- [charKey] = newest entry of it the size limit removed (Ledger.lua: that day and before as day totals)
  recipeBook = {},  -- [profession][recipeID] = { n, out, oq, r } every recipe, learned or not (RecipeBook.lua)
  recipeSources = {}, -- [recipe name lowercased][kind..npc] = { kind, conf = "seen", npc, npcID, mapID, x, y, zone, cost, currency, skill, limited, t }
  vendors = {},     -- [npcID] = { name, mapID, x, y, zone, t, trainer }
  recipeTypes = {}, -- [recipeID] = "shuffle" | "sells" | "notsale" | "loss", the player's own choice (RecipesTab.lua)
  crates = {},      -- [crate itemID] = { name, level, bundles = { { { qty, name }, ... } } } read from tooltips
  vendorSellChanged = {}, -- [itemID] = local day its vendor sell price was seen to change (older price history is ignored)
  favor = {},       -- [charKey] = Merchant's Favor held
  inventory = {},   -- [charKey] = { bags = { [itemID] = count }, bank = { ... }, t, bankT, via = sync partner's name if theirs } (Inventory.lua)
  itemNames = {},   -- [itemID] = name, remembered so lists don't flicker (Prices.lua ns.ItemName)
  disenchants = {}, -- { t, id, ilvl, q, cls, mats = { [itemID] = count } } (Disenchant.lua, last 1000)
  sync = {},        -- [partner name lowercased] = { sentUpTo = time } (Sync.lua; partner in settings.syncPartner)
  sessions = {},    -- finished sessions (Sessions.lua, archived November 13: kept and synced, no longer shown)
  history = {},       -- [marketKey][itemID] = "day:cheapest:typical|..." (90 days, History.lua)
  historyWeekly = {}, -- [marketKey][itemID] = "week:cheapest:typical:days|..." (52 weeks)
  historyVersions = {},       -- [marketKey][itemID][suffix] = "day:cheapest:listed|..." gear versions from full scans (90 days)
  historyVersionsWeekly = {}, -- [marketKey][itemID][suffix] = "week:cheapest:listedSum:days|..." (52 weeks)
  historyAll = {},    -- [marketKey][itemID] = "lowest:typicalSum:days"
  suffixNames = {},   -- [version name, "of the Whale"] = the bonus ID full scans saw for it (Prices.lua)
  -- soldSnap = { t, market, items = { [itemID] = "price:count" } }: the last full scan's counts (Prices.lua), no default
  historyQty = {},    -- [marketKey][itemID] = "day:listed|..." most listed seen each day (last 30 days)
  dungeons = {},      -- [dungeon name] = { runs, secs, coin, drops = { [itemID] = runs it dropped in } } (Dungeons.lua, archived November 14: kept, nothing adds to it)
  ledgerMonths = {},  -- ledger entries older than 30 days, as monthly totals per item: { { t = month start, c, k = "sale" | "buy" | "vsell" | "vbuy", id or n, q, a, cnt, mx } } (History.lua, kept a year)
  historySold2 = {},  -- [marketKey][itemID] = "day:bought:minutes:closeMinutes:expired|..." units that vanished though they couldn't have expired, and those gone from the last time band (expired) (sell speed, since October 2)
  profiles = {},     -- settings profiles: [name] = { [setting] = value } (Settings.lua; "Default" is settings itself)
  charProfile = {},  -- [charKey] = profile name; none = Default
  quietChars = {},   -- [charKey] = true: quiet mode turned on with /fl quiet there, kept until turned off (Quiet.lua)
  shopping = { lists = {} }, -- shopping lists: { lists = { { name, on, items = { { id, max, qty } } } }, current } (ShoppingLists.lua)
  watchItems = {},   -- [itemID] = { max = copper or nil for the vendor price, t = added }: watched items (Watched.lua)
  groups = { user = {}, added = {}, removed = {}, rules = {}, saved = {}, nextId = 1 }, -- groups and rules, account-wide (Groups.lua: shapes there)
  settings = { source = "auto", maxAgeHours = 12, tooltip = true, debug = false, watch = {}, ahCut = 5, margin = 10, actionSeconds = 3, skipChars = {}, minimap = true, minimapAngle = 200, dealSound = true, dealScreen = true, dealChat = true, sellGuard = true, watchResume = true, stackTwoClicks = false, sessionValue = "best", saleSound = true, deRolls = true, keepGold = 0, postUndercut = 0, vendorItemsAH = false, undercutAlerts = true, undercutSound = true, updateNotice = true, priceHelper = true, soldSummary = true,
    dealUsualPct = 20, dealWindow = "all", dealVendorPct = 10, dealVendorMin = 0, dealHistory = "auto", dealUsualMin = 1000, dealShowThin = false, dealsSort = {}, window = {}, ahHighlight = true, ahTabs = true, dashboard = {}, ledger = {}, goldMaking = {}, writs = {}, crateTab = {}, quickDE = true, quickDEKey = "ctrlalt", deFinder = {}, crates = true, recipes = {}, openFlips = true, customers = true, customerSound = true, customerWindow = true, customerChat = false,
    svcCrafting = true, svcFood = true, svcPortal = true, svcSummon = true, svcLockpick = true,
    -- Buy queue (BuyQueue.lua): what goes in it, scroll anywhere to buy, the side panel's tab.
    -- wheel: on from the start (owner, October 22: the fresh-install test found it hard to
    -- find off; it was off from October 2 so nobody bought by accident). Buying still
    -- needs the mouse over the top strip, and Up to and Spend at most still apply.
    buyQueue = { flips = true, disenchant = true, deals = false, lists = true, wheel = true, tab = "queue" },
    tipMode = "full", tipOptions = 3, tipPrice = true, tipSpeed = true, tipSell = true, tipQuest = true, tipQuestMine = true, tipDarkmoon = true, tipHistory = true, priceWindow = true, priceClick = "alt", tipWorth = true, tipBuy = true, tipDisenchant = true, tipUsedBy = true, tipCrate = true, tipBagSlot = true, tipNeutral = false, worthAH = true, worthVendor = true, worthDisenchant = true, worthCraft = true, ridingFund = true,
    -- theme: FL Gilded for new installs (owner, October 22); "default" is FL Bronze now.
    theme = "gilded", accent = "", uiScale = 100, moneyStyle = "coins", syncMoney = false, quietWatch = false },
}
-- For Settings: "Default: Auto." under each choice (UI.lua).
ns.DEFAULT_SETTINGS = DEFAULTS.settings

local function copyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      copyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

---------------------------------------------------------------------------
-- Output helpers
---------------------------------------------------------------------------
function ns:Print(...) print(ns.PREFIX, ...) end
function ns:Debug(...)
  if ns.db and ns.db.settings.debug then print("|cff888888Ledger debug:|r", ...) end
end

-- How many of an item this character has in its bags (with includeBank, the bank too).
-- C_Item.GetItemCount first: the old global GetItemCount is one of the item functions
-- Blizzard moved into C_Item, like GetMerchantItemInfo, which Forever doesn't have. The
-- sell suggestion called the old one and never showed (Frank, AN4, November 13).
function ns.ItemCount(id, includeBank)
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  return id and count and count(id, includeBank and true or false) or 0
end

-- Money as the game's coin icons, or as colored letters (Settings, Appearance, Show money
-- as; Frank, November 21: the icons are fine but busy, letters to compare in game).
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local UNITS = {
  coins = { COIN:format("Gold"), COIN:format("Silver"), COIN:format("Copper") },
  letters = { "|cffffd100g|r", "|cffc7c7cfs|r", "|cffeda55fc|r" },
}

function ns.Money(copper)
  if not copper then return "?" end
  copper = math.floor(copper + 0.5)
  local style = ns.db and ns.db.settings and ns.db.settings.moneyStyle
  local u = UNITS[style] or UNITS.coins
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. u[1] end
  if s > 0 then out[#out + 1] = s .. u[2] end
  if c > 0 or #out == 0 then out[#out + 1] = c .. u[3] end
  return table.concat(out, " ")
end

-- The two biggest coins, for summaries where the change doesn't matter (Frank, November
-- 21: the Dashboard was busy with three coins on every amount): copper goes from 1 gold,
-- rounded to the nearest silver. Exact amounts stay in hovers and wherever a price is used.
function ns.MoneyBrief(copper)
  if not copper then return "?" end
  copper = math.floor(copper + 0.5)
  if copper >= 10000 then copper = math.floor(copper / 100 + 0.5) * 100 end
  return ns.Money(copper)
end

-- Money rounded for a narrow column: no copper from 1 gold, no silver from 100 gold
-- (Frank's AH9, November 19: the Writs tab ran out of room). The exact amount goes in
-- the hover.
function ns.MoneyRound(copper)
  if not copper then return nil end
  copper = math.floor(copper + 0.5)
  if copper >= 1000000 then copper = math.floor(copper / 10000 + 0.5) * 10000
  elseif copper >= 10000 then copper = math.floor(copper / 100 + 0.5) * 100 end
  return copper
end
function ns.MoneyShort(copper)
  if not copper then return "?" end
  return ns.Money(ns.MoneyRound(copper))
end

function ns.Age(t)
  if not t or t == 0 then return "" end
  local d = time() - t
  if d < 3600 then return math.max(1, math.floor(d / 60)) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

-- Money as plain text without coin icons, for text boxes: "1g 50s", "75c".
function ns.MoneyPlain(copper)
  copper = math.floor((copper or 0) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
  return table.concat(out, " ")
end

-- "1g50s", "25s", "75c" or plain copper ("75") to copper. nil if it isn't money.
function ns.ParseMoney(s)
  s = (s or ""):lower():gsub("%s+", "")
  if s:match("^%d+$") then return tonumber(s) end
  if s == "" or s:gsub("%d+[gsc]", "") ~= "" then return nil end
  local total = 0
  for n, unit in s:gmatch("(%d+)([gsc])") do
    total = total + tonumber(n) * ((unit == "g" and 10000) or (unit == "s" and 100) or 1)
  end
  return total
end

-- Forgiving price input for boxes you type in (owner, October 2: forcing "2s 40c" felt
-- buggy). Takes "2g 50s", "2g50s", "1.5g", "2.5s", "75c", "2,5g", "2 50 25" and
-- "2.50.25" (gold silver copper), "2 50" (gold silver), a plain number in plainUnit
-- ("g", "s" or "c", default copper), "off" or empty (0), and "any" (-1).
-- nil if it can't be read.
function ns.ParseMoneyLoose(s, plainUnit)
  s = (s or ""):lower():gsub(",", "."):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" or s == "off" or s == "none" or s == "0" then return 0 end
  if s == "any" or s == "*" then return -1 end
  -- Numbers in a row, by spaces or dots: gold silver ("12 50", "12.50") or gold silver
  -- copper ("12 50 25", "12.50.25") (owner, October 3). A lone number is plainUnit.
  if s:find("^%d+[%s%.]+%d+$") or s:find("^%d+[%s%.]+%d+[%s%.]+%d+$") then
    local p = {}
    for d in s:gmatch("%d+") do p[#p + 1] = tonumber(d) end
    -- One digit after a dot is a decimal: "1.5" is one and a half gold, 1g 50s (owner,
    -- October 4), as "1.5g" is; "1.05" and "1 5" stay 1g 5s.
    if not p[3] and s:find("^%d+%.%d$") then p[2] = p[2] * 10 end
    return p[1] * 10000 + p[2] * 100 + (p[3] or 0)
  end
  local n = tonumber(s)
  if n then
    if n < 0 then return nil end
    return math.floor(n * ((plainUnit == "g" and 10000) or (plainUnit == "s" and 100) or 1) + 0.5)
  end
  local total, found = 0, false
  local rest = s:gsub("(%d*%.?%d+)%s*([gsc])", function(num, unit)
    found = true
    total = total + tonumber(num) * ((unit == "g" and 10000) or (unit == "s" and 100) or 1)
    return ""
  end)
  if found and rest:gsub("[%s%a]", "") == "" and not rest:find("%d") then return math.floor(total + 0.5) end
end

function ns.SpellName(spellID)
  if not spellID then return end
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
  if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

-- Search the open auction house for an item by its exact name (clicking an item in the
-- Buy queue, Deals, crates...). (Filling in the Quantity box was tried and removed: the
-- auction house kept its old amount and price, so purchases failed with "no longer
-- available".)
function ns:SearchAuctionHouse(id)
  local ah, name = AuctionHouseFrame, ns.GetItemInfo(id)
  if not (ah and ah:IsShown() and name) then return false end
  if ah.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
    pcall(ah.SetDisplayMode, ah, AuctionHouseFrameDisplayMode.Buy)
  end
  local bar = ah.SearchBar
  if not (bar and bar.SearchBox) then return false end
  bar.SearchBox:SetText('"' .. name .. '"')
  if bar.StartSearch then pcall(bar.StartSearch, bar) end
  return true
end

function ns.ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

-- The character's full name. Forever names have a first and last name, and UnitName
-- returns them as two values ("Iveilos", "Veren"); elsewhere the second value is a realm
-- or nothing, so a plain name is used then.
function ns.FullName()
  local first, last = UnitName("player")
  first = first or "?"
  if last and last ~= "" and not last:find("-", 1, true) then return first .. " " .. last end
  return first
end

-- Saved data used to be filed under the first name only, so two characters named
-- "Iveilos ..." would have shared one record: gold, recipes, everything. Now it's the
-- full name. The first time each character logs in, everything filed under its old key
-- moves to the new one (whoever logs in first takes a record two characters shared).
-- Tables keyed by character (chars, gold, money, inventory, favor...) have the key
-- renamed; log entries that note the character (c = key, char = key) are rewritten.
local function moveCharacterKey(old, new)
  local db = ns.db
  local moved = 0
  for _, t in pairs(db) do
    if type(t) == "table" then
      if t[old] ~= nil and t[new] == nil then
        t[new], t[old] = t[old], nil
        moved = moved + 1
      end
      for _, v in pairs(t) do
        if type(v) == "table" then
          if v.c == old then v.c = new; moved = moved + 1 end
          if v.char == old then v.char = new; moved = moved + 1 end
        end
      end
    end
  end
  return moved
end

-- Forever's realm is its ruleset, but the live game names the server each character
-- lives on: "CAMWOW US2 Realm 3 PvE". Characters on Realm 1 and Realm 3 are on the one
-- PvE realm and share an auction house (owner's test, November 6: a listing seen from
-- both), so saved data is filed under what's left: "PvE". Also turns
-- "Name-CAMWOW US2 Realm 3 PvE" into "Name-PvE".
function ns.PlainRealm(s) return (s:gsub("CAMWOW%s+%S+%s+Realm%s+%d+%s+", "")) end

-- Since November 21 the live game can give an empty realm name (Frank's mage in Felwood:
-- GetRealmName() printed nothing, while his bank character in Stormwind still had one; likely
-- Blizzard's layer changes against layer-hopping addons). Everything is filed under the
-- realm, so an empty one hid every price and sell speed and started a second record of the
-- character (a CurseForge comment and a Discord report the same day). The last good name is
-- kept per character (charRealm) and used whenever the game's is empty or hidden.
-- A string the addon may read: nil for a hidden (secret) value or anything not a string.
-- Since November 23 an NPC's GUID can be hidden (Frank's BugSack: RecipeBook.lua matching
-- a trainer's GUID, 29 times), so read unit GUIDs and names through this.
function ns.Readable(s)
  if (issecretvalue and issecretvalue(s)) or type(s) ~= "string" then return nil end
  return s
end

local function readRealm()
  if not GetRealmName then return end
  local ok, realm = pcall(GetRealmName)
  if not ok or (issecretvalue and issecretvalue(realm)) or type(realm) ~= "string" then return end
  realm = ns.PlainRealm(realm)
  if not realm:find("%S") then return end
  return realm
end

-- This character's realm from saved data: remembered, else its own record ("Name-Realm"),
-- else the realm most characters are on.
local function knownRealm()
  local db = ns.db
  if not db then return end
  local me = ns.FullName()
  local r = db.charRealm and db.charRealm[me]
  if r then return r end
  local counts, best = {}, nil
  for key, c in pairs(db.chars or {}) do
    local realm = type(c) == "table" and c.realm
    if type(realm) == "string" and realm:find("%S") and realm ~= "?" then
      if key == me .. "-" .. realm then return realm end
      counts[realm] = (counts[realm] or 0) + 1
      if not best or counts[realm] > counts[best] then best = realm end
    end
  end
  return best
end

function ns.RealmName()
  if ns.goodRealm then return ns.goodRealm end
  local realm = readRealm()
  if not realm then return knownRealm() end
  -- (A realm can't change without a reload, so once read it's kept for the session.)
  ns.goodRealm = realm
  if ns.db then
    ns.db.charRealm = ns.db.charRealm or {}
    ns.db.charRealm[ns.FullName()] = realm
  end
  return realm
end

-- Two records for the same place under different server names. A price history is dated
-- ("day:cheapest:typical|..."): every day from both is kept, in order, and of the same
-- day the cheaper (Codex review, November 5: keeping the longer string lost days).
local function isDated(s) return s:find("^%d+:%d+") and not s:find(",", 1, true) end

local function combineDated(a, b)
  local byDay, days = {}, {}
  for _, s in ipairs({ a, b }) do
    for part in s:gmatch("[^|]+") do
      local day = tonumber(part:match("^(%d+):"))
      if day then
        local have = byDay[day]
        if not have then
          byDay[day] = part
          days[#days + 1] = day
        elseif tonumber(part:match("^%d+:(%d+)") or 0) < tonumber(have:match("^%d+:(%d+)") or 0) then
          byDay[day] = part
        end
      end
    end
  end
  table.sort(days)
  for i, day in ipairs(days) do days[i] = byDay[day] end
  return table.concat(days, "|")
end

-- A character: the newer record, keeping recipes and finished quests only the older knew.
local function combineChar(a, b)
  local new, old = a, b
  if (b.updated or 0) > (a.updated or 0) then new, old = b, a end
  for k, v in pairs(old) do
    if new[k] == nil then new[k] = v end
  end
  for quest, v in pairs(old.questsDone or {}) do new.questsDone[quest] = v end
  for name, prof in pairs(old.profs or {}) do
    local q = new.profs[name]
    if not q then new.profs[name] = prof
    else
      q.recipes = q.recipes or {}
      for id, recipe in pairs(prof.recipes or {}) do
        if q.recipes[id] == nil then q.recipes[id] = recipe end
      end
    end
  end
  return new
end

-- Bags and bank: each the newer of the two by its own time.
local function combineBags(a, b)
  if (b.t or 0) > (a.t or 0) then a.bags, a.t = b.bags, b.t end
  if (b.bankT or 0) > (a.bankT or 0) then a.bank, a.bankT = b.bank, b.bankT end
  return a
end

local combine
local function combineRecord(a, b)
  if a.profs or b.profs or a.updated or b.updated then return combineChar(a, b) end
  if a.bags or b.bags or a.bank or b.bank then return combineBags(a, b) end
  if type(a.t) == "number" and type(b.t) == "number" then return b.t > a.t and b or a end
  combine(a, b)
  return a
end

-- The newer record wins where they have times, else both are kept.
function combine(into, from)
  for k, v in pairs(from) do
    local mine = into[k]
    if mine == nil then into[k] = v
    elseif type(mine) == "table" and type(v) == "table" then into[k] = combineRecord(mine, v)
    elseif type(mine) == "string" and type(v) == "string" and isDated(mine) and isDated(v) then
      into[k] = combineDated(mine, v)
    end
  end
end

-- All-time price figures (History.lua historyAll): "lowest:typicalSum:days", not dated. Two
-- combine as the lower lowest, with the sums and days added (gold audit G9, November 9: the
-- realm move joined them like dated history, "100:5000:5|120:6000:6", which nothing could
-- read). A value joined that way before is read the same way. Returns lowest, sum, days or nil.
function ns.ReadAllTime(s)
  local lo, sum, n
  for part in tostring(s or ""):gmatch("[^|]+") do
    local l, a, d = part:match("^(%d+):(%d+):(%d+)$")
    if l then
      lo = math.min(lo or tonumber(l), tonumber(l))
      sum, n = (sum or 0) + tonumber(a), (n or 0) + tonumber(d)
    end
  end
  return lo, sum, n
end

local function combineAllTime(a, b)
  local lo, sum, n = ns.ReadAllTime(a .. "|" .. b)
  if not lo then return a end
  return ("%.0f:%.0f:%.0f"):format(lo, sum, n)
end

-- Gear version history (History.lua) has its own fields per day or week, so two records
-- of the same day can't just keep the cheaper row (Codex review, November 7):
--   day  "day:cheapest:listed"            the cheaper price and the most listed
--   week "week:cheapest:listedSum:days"   the row covering more days, with the cheaper price
-- (Two weekly summaries of one week can't be added up without knowing which days each
-- covers, so the fuller one stands.) All-time figures: combineAllTime above.
local OWN_MERGE = { historyVersions = "day", historyVersionsWeekly = "week", historyAll = "all" }

local function combinePeriods(a, b, kind)
  local byKey, keys = {}, {}
  for _, s in ipairs({ a, b }) do
    for part in s:gmatch("[^|]+") do
      local f = {}
      for n in part:gmatch("%d+") do f[#f + 1] = tonumber(n) end
      local key = f[1]
      if key then
        local have = byKey[key]
        if not have then
          byKey[key] = f
          keys[#keys + 1] = key
        elseif kind == "day" then
          have[2], have[3] = math.min(have[2] or f[2], f[2] or have[2]), math.max(have[3] or 0, f[3] or 0)
        else
          local cheapest = math.min(have[2] or f[2], f[2] or have[2])
          if (f[4] or 0) > (have[4] or 0) then byKey[key] = f; have = f end
          have[2] = cheapest
        end
      end
    end
  end
  table.sort(keys)
  for i, key in ipairs(keys) do
    local f = byKey[key]
    for j, n in ipairs(f) do f[j] = ("%.0f"):format(n) end
    keys[i] = table.concat(f, ":")
  end
  return table.concat(keys, "|")
end

local function combineVersions(into, from, kind)
  for k, v in pairs(from) do
    local mine = into[k]
    if mine == nil then into[k] = v
    elseif type(mine) == "table" and type(v) == "table" then combineVersions(mine, v, kind)
    elseif type(mine) == "string" and type(v) == "string" then
      into[k] = kind == "all" and combineAllTime(mine, v) or combinePeriods(mine, v, kind)
    end
  end
  return into
end
ns.CombineVersions = combineVersions   -- (tests)

-- Money in and out (money[charKey][day][source] = copper): the same day under two keys is
-- the same character's gold in two parts of the day, so the amounts add up.
local function addUp(into, from)
  for k, v in pairs(from) do
    local mine = into[k]
    if mine == nil then into[k] = v
    elseif type(mine) == "number" and type(v) == "number" then into[k] = mine + v
    elseif type(mine) == "table" and type(v) == "table" then addUp(mine, v) end
  end
  return into
end
OWN_MERGE.money = "sum"

-- Renames keys (newKey) and string values (newValue) everywhere in t; two records that end
-- up under one key are combined. kind: inside a table with its own way of combining (OWN_MERGE).
local function renameData(t, kind, newKey, newValue)
  local renames
  for k, v in pairs(t) do
    -- (Gives the frame back inside a sliced run: sync's message, its own tables, is walked
    -- whole, and that was most of a 55 ms frame. Frank's eleventh /fl perf, November 21.
    -- At load it runs in one go: MaybeYield does nothing outside a run.)
    if ns.MaybeYield then ns.MaybeYield() end
    if type(v) == "table" then renameData(v, kind or OWN_MERGE[k], newKey, newValue)
    elseif type(v) == "string" then
      local nv = newValue(v, k)
      if nv then t[k] = nv end
    end
    if type(k) == "string" and newKey(k) then
      renames = renames or {}
      renames[#renames + 1] = k
    end
  end
  for _, k in ipairs(renames or {}) do
    local v, new = t[k], newKey(k)
    t[k] = nil
    if t[new] == nil then t[new] = v
    elseif type(t[new]) == "table" and type(v) == "table" then
      if kind == "sum" then addUp(t[new], v)
      else t[new] = kind and combineVersions(t[new], v, kind) or combineRecord(t[new], v) end
    end
  end
end

-- Puts every key and value in saved or received data under the plain realm.
function ns.PlainRealmData(t, kind)
  renameData(t, kind, function(k)
    return k:find("CAMWOW", 1, true) and ns.PlainRealm(k)
  end, function(v)
    return v:find("CAMWOW", 1, true) and ns.PlainRealm(v)
  end)
end

-- Data saved while the game gave an empty realm name (November 21, see RealmName above):
-- markets "|Alliance" and characters "Name-" (or "?|Alliance", "Name-?" with none at all),
-- and a character's "Name- (neutral)" auctions list, back under the realm.
-- Each character goes back to its own realm (Codex review, November 21: an account with
-- characters on two rulesets had the other one's data moved to the logged-in one's
-- realm): the realm read now for the character logged in, else the one remembered for it
-- (charRealm), else the one its other records are under. A character whose realm isn't
-- known stays as it is until it logs in. Market data ("|Alliance") goes to the only realm
-- that side's characters are on; with that side on several rulesets it stays where it is
-- (prices go stale anyway; mixing rulesets would be worse).
-- realm: the logged-in character's realm. Also learns from the tables in extra (sync).
local function blankRealmRenamer(db, realm, extra)
  local home, seen = {}, {}
  local function good(r) return type(r) == "string" and r:find("%S") and r ~= "?" end
  local function note(t, key, r)
    if t[key] == nil then t[key] = r elseif t[key] ~= r then t[key] = false end
  end
  local function eachChar(fn)
    for i = 1, 2 do
      local source = i == 1 and db or extra
      for key, c in pairs(source and source.chars or {}) do
        if type(key) == "string" then
          local name, r = key:match("^(.+)%-([^%-]*)$")
          if name then fn(name, r, c) end
        end
      end
    end
  end
  -- Characters: the realm of their other records, then the remembered one, then (for the
  -- one logged in) the one read now.
  eachChar(function(name, r) if good(r) then note(seen, name, r) end end)
  for name, r in pairs(seen) do if r then home[name] = r end end
  -- (Not ipairs over { extra, db }: with no extra the list would look empty.)
  for i = 1, 2 do
    local source = i == 1 and extra or db
    for name, r in pairs(source and source.charRealm or {}) do if good(r) then home[name] = r end end
  end
  local me = ns.FullName()
  if good(realm) then home[me] = realm end
  -- Markets: the realms each side's characters are on, counting every character placed
  -- above, blank records included (Codex review, November 21: a just-repaired character
  -- didn't count, so Alliance prices made on PvE went to Hardcore). A character whose side
  -- isn't known makes every side with another realm ambiguous; ambiguous stays put.
  local sideRealm, anyRealm, unknownSide, counted = {}, nil, {}, {}
  local function count(side, r)
    if anyRealm == nil then anyRealm = r elseif anyRealm ~= r then anyRealm = false end
    if type(side) == "string" then note(sideRealm, side, r) else unknownSide[r] = true end
  end
  eachChar(function(name, r, c)
    local placed = good(r) and r or home[name]
    if placed then
      counted[name] = true
      count(type(c) == "table" and c.faction or nil, placed)
    end
  end)
  for name, r in pairs(home) do
    if not counted[name] then
      count(name == me and UnitFactionGroup and UnitFactionGroup("player") or nil, r)
    end
  end
  if good(realm) then count(UnitFactionGroup and UnitFactionGroup("player") or nil, realm) end
  for side, r in pairs(sideRealm) do
    if r then for u in pairs(unknownSide) do if u ~= r then sideRealm[side] = false end end end
  end
  local function fix(s)
    local side = s:match("^%??|(%a+)$")
    if side then
      local r = sideRealm[side]
      if r == nil then r = anyRealm end
      return r and r .. "|" .. side or nil
    end
    local name = s:match("^(.+)%-%??$")
    if name and home[name] then return name .. "-" .. home[name] end
    name = s:match("^(.+)%-%?? %(neutral%)$")
    if name and home[name] then return name .. "-" .. home[name] .. " (neutral)" end
  end
  return fix, function(v, k)
    if k == "realm" then return end   -- (a character record's realm: set from its key after)
    return fix(v)
  end
end

-- Whether any table has such a key (a quick look, so the full repair runs only when needed).
function ns.HasBlankRealmData(db, realm, extra)
  local fix = blankRealmRenamer(db, realm, extra)
  for _, t in pairs(db) do
    if type(t) == "table" then
      for k in pairs(t) do
        if type(k) == "string" and fix(k) then return true end
      end
    end
  end
  return false
end

function ns.FixBlankRealm(db, realm, extra)
  if not realm then return end
  local fixKey, fixValue = blankRealmRenamer(db, realm, extra)
  renameData(db, nil, fixKey, fixValue)
  -- A character record moved back gets its realm from its key.
  for key, c in pairs(db.chars or {}) do
    local r = type(key) == "string" and type(c) == "table" and (c.realm == "" or c.realm == "?") and key:match("%-([^%-]+)$")
    if r and r ~= "?" then c.realm = r end
  end
end

function ns.CharKey()
  local realm = ns.RealmName() or "?"
  local first = UnitName("player") or "?"
  local key = ns.FullName() .. "-" .. realm
  local old = first .. "-" .. realm
  if key ~= old and ns.db then
    ns.db.charKeysMoved = ns.db.charKeysMoved or {}
    if not ns.db.charKeysMoved[key] then
      ns.db.charKeysMoved[key] = true
      local n = moveCharacterKey(old, key)
      if n > 0 and ns.Debug then ns:Debug(("Saved data moved from %s to %s (%d places)."):format(old, key, n)) end
    end
  end
  return key
end

-- A single character picked while playing another one: the character you're on now, once
-- you switch (a player on Discord, November 22: "When Im changing to alts, and open Forever
-- Ledger ... could you make it by default to chose profile from that char? ... it is
-- remembering last selected"). All, the realm and a faction stay as picked; a character
-- picked on purpose stays until the next switch. The Dashboard and the Ledger.
function ns.OwnCharChoice(s)
  local me = ns.CharKey()
  if s.charOn == me then return end
  local c = s.char
  local group = c == nil or c == "all" or c == "realm" or (type(c) == "string" and c:match("^faction:") ~= nil)
  if not group and c ~= me then s.char = me end
  s.charOn = me
end

-- Is a saved character on the same ruleset (realm name) and faction as the one you're
-- playing: one who could mail you items or craft for you (owner, October 3: other
-- rulesets' characters counted in Have, recipes and values). True when either side
-- isn't known yet (old saved data, or the very start of a login).
function ns:SameMarketChar(key)
  local c = ns.db and ns.db.chars[key]
  if not c then return true end
  local realm, faction = ns.RealmName(), UnitFactionGroup and UnitFactionGroup("player")
  if c.realm and realm and c.realm ~= realm then return false end
  if c.faction and faction and c.faction ~= faction then return false end
  return true
end

-- Forever is realmless: the "realm" is the ruleset, and each ruleset + faction is one auction house.
-- While a neutral (goblin) auction house is open, its prices are kept apart, since in
-- Classic it's a separate market shared with the other faction, with a 15% cut.
function ns.MarketKey()
  return (ns.RealmName() or "?") .. "|" .. (ns.neutralAH and "Neutral" or UnitFactionGroup("player") or "?")
end

-- The auctioneer has no faction and stands in a town with a neutral auction house:
-- Classic's goblin towns (Booty Bay confirmed, October 5). The Waylaid Crate trade posts'
-- auctioneers were removed in the beta (owner, October 5).
-- Found by the zone's map number first, so it works in every language (GitHub #23,
-- November 19: an EU player's Booty Bay scans were saved as their faction's); the town
-- names are English only. Classic's map numbers (Frank's saved vendors: Stormwind 1453,
-- Elwynn 1429): Stranglethorn Vale 1434 (Booty Bay), Tanaris 1446 (Gadgetzan), Winterspring
-- 1452 (Everlook), the only auction houses in those zones.
local NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true }
local NEUTRAL_TOWNS = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }
ns.NEUTRAL_MAPS = NEUTRAL_MAPS
function ns.IsNeutralAuctioneer()
  if not UnitExists("npc") or UnitFactionGroup("npc") then return false end
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  if map and NEUTRAL_MAPS[map] then return true end
  return NEUTRAL_TOWNS[GetSubZoneText() or ""] or NEUTRAL_TOWNS[GetMinimapZoneText and GetMinimapZoneText() or ""] or false
end

-- Placeholders; UI.lua replaces these.
function ns:RefreshUI() end
function ns:UpdateScanStatus() end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
-- Events only ever wanted for the player's own unit: the game sends just those,
-- instead of every cast by everyone nearby.
local PLAYER_ONLY = {
  UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_INTERRUPTED = true,
}

function ns:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    local ok
    if PLAYER_ONLY[event] and frame.RegisterUnitEvent then
      ok = pcall(frame.RegisterUnitEvent, frame, event, "player")
    else
      ok = pcall(frame.RegisterEvent, frame, event)
    end
    if not ok then handlers[event].unknown = true end
  end
  table.insert(handlers[event], fn)
end
-- Whether the game knows an event we listen for (for /fl api).
function ns:EventKnown(event) return handlers[event] ~= nil and not handlers[event].unknown end
-- Timing, for /fl perf: total and slowest single run per event or task.
ns.perf, ns.perfSince = {}, GetTime()
local function clock() return debugprofilestop and debugprofilestop() or GetTime() * 1000 end

-- Long work spread over frames (Frank's /fl perf, November 21: Gold making's list took
-- 855 ms in one frame). ns.RunInSlices(fn, done) runs fn in a coroutine, BUDGET_MS a
-- frame; long loops inside it call ns.MaybeYield() to give the frame back. done gets fn's
-- results. Outside such a run MaybeYield does nothing, so the same code still works in
-- one go. Each slice is timed as label (nothing timed may be running when it yields).
local SLICE_MS = 8
local slicing, sliceStart = nil, 0
-- A table's keys as a list, to walk it in slices safely while it may grow.
function ns.KeysOf(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  return out
end
-- Whether the code running now is part of a sliced run.
function ns.InSlices() return slicing ~= nil and coroutine.running() == slicing end
function ns.MaybeYield()
  if slicing and coroutine.running() == slicing and clock() - sliceStart > SLICE_MS then coroutine.yield() end
end
-- Returns the run: run.stopped is true once it finished, failed or was stopped
-- (ns.StopSlices: the rest is dropped and done is never called).
-- A run's parts (ns.SlicePart) are also listed in /fl perf on their own, "label: part", so
-- a long run shows which part makes its time and leftovers (Frank's /fl perf, November 21).
local sliceRun, partLabel, partStart, partKB = nil, nil, 0, 0
local function closePart()
  if partLabel and ns.PerfNote then
    ns.PerfNote(partLabel, clock() - partStart, true, collectgarbage("count") - partKB)
  end
end
function ns.SlicePart(name)
  if not (sliceRun and ns.InSlices()) then return end
  closePart()
  partLabel = name and (sliceRun.label .. ": " .. name) or nil
  partStart, partKB = clock(), collectgarbage("count")
end
-- failed (optional): called, outside the run, when fn stops with an error after it started.
function ns.RunInSlices(label, fn, done, failed)
  local run = { co = coroutine.create(fn), label = label }
  local step
  step = ns.Timed(label, function()
    if run.stopped then return end
    slicing, sliceStart, sliceRun = run.co, clock(), run
    partLabel, partStart, partKB = run.part, clock(), collectgarbage("count")
    local result = { coroutine.resume(run.co) }
    closePart()
    run.part, partLabel, sliceRun = partLabel, nil, nil
    slicing = nil
    if not result[1] then
      run.stopped = true; geterrorhandler()(result[2])
      if failed then failed() end
      return
    end
    if coroutine.status(run.co) == "dead" then run.stopped = true; done(unpack(result, 2))
    else C_Timer.After(0, step) end
  end)
  step()
  return run
end
function ns.StopSlices(run) if run then run.stopped = true end end

-- A stable merge sort that gives the frame back now and then inside a sliced run (Lua's
-- table.sort can't: it calls the comparator from C). Sorts t in place by less.
-- (The clock is looked at every 64 comparisons, inside a merge too: once per merged block
-- left a block of thousands in one frame, Codex review, November 21.)
function ns.SortInSlices(t, less)
  local n = #t
  if n < 2 then return t end
  local a, b, width, done = t, {}, 1, 0
  while width < n do
    for i = 1, n, 2 * width do
      local mid, hi = math.min(i + width, n + 1), math.min(i + 2 * width, n + 1)
      local l, r, k = i, mid, i
      while l < mid and r < hi do
        if less(a[r], a[l]) then b[k] = a[r]; r = r + 1 else b[k] = a[l]; l = l + 1 end
        k = k + 1
        done = done + 1
        if done >= 64 then done = 0; ns.MaybeYield() end
      end
      while l < mid do b[k] = a[l]; l = l + 1; k = k + 1 end
      while r < hi do b[k] = a[r]; r = r + 1; k = k + 1 end
    end
    a, b = b, a
    width = width * 2
  end
  if a ~= t then for i = 1, n do t[i] = a[i] end end
  return t
end

local frameOurs, frameTop, frameTopMs = 0, nil, 0   -- this frame's time in our code (freeze watch, below)
local framePart, framePartMs, frameTipItem = nil, 0, nil   -- its slowest part (sub), the tooltip item we worked on
-- sub: a part of a task timed under its own label too (the tooltip's sections): listed in
-- /fl perf, but not added to the frame's total again. Likewise anything timed inside another
-- timed task or event (depth > 0): only the outermost counts toward the frame (Codex review,
-- November 17: a 100 ms task with an 80 ms timed step inside showed as 180 ms).
local depth = 0
-- kb: memory it took meanwhile (leftovers the game clears up later; Frank's AN30, November
-- 19: 148 MB before clearing against 44 MB in use, and freezes with almost none of our time).
local function memKB() return collectgarbage("count") end
ns.MemKB = memKB
-- /fl perf detail: where a long run's time and leftovers go, by kind of work, across every
-- run and tooltip (Frank's nineteenth /fl perf, November 22: Gold making's list still left
-- 86 MB, and which work makes it can't be told from its parts). Off unless switched on,
-- for this session; measured where the work starts (DetailStart, DetailStop).
ns.perfDetailOn, ns.perfDetail = false, {}
function ns.DetailStart()
  if ns.perfDetailOn then return clock(), collectgarbage("count") end
end
function ns.DetailStop(label, t, kb)
  if not t then return end
  local p = ns.perfDetail[label]
  if not p then p = { n = 0, ms = 0, kb = 0 }; ns.perfDetail[label] = p end
  p.n, p.ms = p.n + 1, p.ms + (clock() - t)
  local grew = collectgarbage("count") - kb
  if grew > 0 then p.kb = p.kb + grew end
end
-- A count only (no time): how often something happened, for /fl perf detail.
function ns.DetailCount(label, n)
  if not ns.perfDetailOn then return end
  local p = ns.perfDetail[label]
  if not p then p = { n = 0, ms = 0, kb = 0 }; ns.perfDetail[label] = p end
  p.n = p.n + (n or 1)
end
-- Where the code that called the caller of this is ("Values.lua:342"), for those counts.
function ns.DetailCaller()
  local s = debugstack and debugstack(3, 1, 0) or ""
  return s:match("([%w_]+%.lua:%d+)") or "?"
end
function ns.DetailLines()
  local list = {}
  for label, p in pairs(ns.perfDetail) do list[#list + 1] = { label = label, p = p } end
  table.sort(list, function(a, b) return a.p.kb > b.p.kb end)
  local out = {}
  for i, e in ipairs(list) do
    if e.p.ms == 0 and e.p.kb == 0 then out[i] = ("%s: %d"):format(e.label, e.p.n)   -- (a count: DetailCount)
    else out[i] = ("%s: %d times, %d ms total, %.1f MB of leftovers"):format(e.label, e.p.n, e.p.ms, e.p.kb / 1024) end
  end
  return out
end

local function note(label, ms, sub, kb)
  sub = sub or depth > 0
  local p = ns.perf[label]
  if not p then p = { n = 0, ms = 0, max = 0, kb = 0 }; ns.perf[label] = p end
  p.n, p.ms = p.n + 1, p.ms + ms
  if kb and kb > 0 then p.kb = (p.kb or 0) + kb end
  if ms > p.max then p.max = ms end
  if sub then
    if ms > framePartMs then framePart, framePartMs = label, ms end
    return
  end
  frameOurs = frameOurs + ms
  if ms > frameTopMs then frameTop, frameTopMs = label, ms end
end

-- Freeze watch (Frank, November 17: "often when im hovering over tooltips my game freezes"):
-- a frame that took FREEZE_SECONDS or more is noted with how much of it was Forever Ledger's
-- own code (and what), the item a tooltip was showing, and, where the game's addon profiler
-- exists (C_AddOnProfiler), which addons took longest. Loading screens don't count. The last
-- 20 are kept in the saved data (freezeLog) for /fl perf, after a reload too.
local FREEZE_SECONDS, FREEZE_KEEP = 0.25, 20
ns.FREEZE_SECONDS = FREEZE_SECONDS
local loading, loadingSeq = true, 0   -- (until the first loading screen ends)

-- The addons the game's profiler says took longest in the last frame, "Name 180 ms" each.
-- Every loaded addon's value of one profiler metric: { [name] = number }, or nil without one.
local function profilerAll(metricName)
  local P = C_AddOnProfiler
  local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[metricName]
  if not (P and P.GetAddOnMetric and metric ~= nil) then return nil end
  local count = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
  local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not (count and info and isLoaded) then return nil end
  local all = {}
  for i = 1, count() do
    local name = info(i)
    if name and isLoaded(name) then
      local ok, v = pcall(P.GetAddOnMetric, name, metric)
      if ok and type(v) == "number" then all[name] = v end
    end
  end
  return all
end

local function profilerTop(metricName, n)
  local all = profilerAll(metricName)
  if not all then return nil end
  local rows = {}
  for name, v in pairs(all) do
    if v > 0 then rows[#rows + 1] = { name = name, v = v } end
  end
  table.sort(rows, function(a, b) return a.v > b.v end)
  local out = {}
  for i = 1, math.min(n or 3, #rows) do out[i] = rows[i] end
  return out
end
ns.ProfilerTop = profilerTop

-- The addons with a frame over 100 ms between two counts (each { [name] = count }), most first.
function ns.SlowSince(before, after)
  local out = {}
  for name, v in pairs(after or {}) do
    local d = v - ((before or {})[name] or 0)
    if d > 0 then out[#out + 1] = { name = name, n = d } end
  end
  table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  return out
end

function ns.NoteFrame(elapsed, ours, top, topMs, tipItem, others, part, partMs)
  if elapsed < FREEZE_SECONDS or not ns.db then return end
  local log = ns.db.freezeLog or {}
  ns.db.freezeLog = log
  local e = { t = time(), ms = math.floor(elapsed * 1000 + 0.5), ours = math.floor(ours + 0.5), item = tipItem }
  if top and topMs >= 5 then e.what, e.whatMs = top, math.floor(topMs + 0.5) end
  if e.what and part and (partMs or 0) >= 5 then e.part, e.partMs = part, math.floor(partMs + 0.5) end
  if others and #others > 0 then
    e.addons = {}
    for i, r in ipairs(others) do e.addons[i] = ("%s %.0f ms"):format(r.name, r.v) end
  end
  log[#log + 1] = e
  while #log > FREEZE_KEEP do table.remove(log, 1) end
  return e
end

local frameItems = 0   -- (item details that arrived since the last frame: GET_ITEM_INFO_RECEIVED)
local overBase, overOld   -- (each addon's count of frames over 100 ms: a second ago at most, and the one before)
local watch = CreateFrame("Frame")
local lastTick   -- (our own clock at the last OnUpdate)
local lastMem    -- (all addons' memory then, KB)
watch:SetScript("OnUpdate", function(_, elapsed)
  -- The time since our last OnUpdate, on the same clock as our share: the game's elapsed is
  -- the frame before, so a freeze and the work that caused it landed on different lines
  -- (Frank's AN30, November 17: "463 ms; Forever Ledger 559 ms", then a 1124 ms freeze at 3 ms).
  local now = clock()
  if lastTick then elapsed = (now - lastTick) / 1000 end
  lastTick = now
  -- Memory cleared in this frame (all addons share one pile): a big drop in a frozen frame
  -- means the game was clearing up leftovers then (Frank's AN30, November 19).
  local mem = memKB()
  local cleared = lastMem and lastMem - mem or 0
  lastMem = mem
  if elapsed >= FREEZE_SECONDS and not loading then
    local tip
    if GameTooltip and GameTooltip:IsShown() and GameTooltip.GetItem then
      local ok, _, link = pcall(GameTooltip.GetItem, GameTooltip)
      tip = ok and link and ns.ItemIDFromLink and ns.ItemIDFromLink(link) or nil
    end
    local e = ns.NoteFrame(elapsed, frameOurs, frameTop, frameTopMs, tip or frameTipItem, profilerTop("LastTime", 3), framePart, framePartMs)
    if e and cleared >= 1024 then e.clearedMB = math.floor(cleared / 1024 + 0.5) end
    -- Item details the game sent in it, and memory made in it (Frank's twentieth /fl perf,
    -- November 22: freezes of 250-290 ms while Gold making's list was worked out, Forever
    -- Ledger 18 ms of them, no addon over 100 ms: the game loading items asked about?).
    if e and frameItems > 0 then e.items = frameItems end
    if e and cleared <= -1024 then e.grewMB = math.floor(-cleared / 1024 + 0.5) end
    -- Which addons had a frame over 100 ms in it: their counts a second later against the
    -- counts kept every second before it (the per-frame times read now aren't the frozen
    -- frame's: Frank's AN30, November 17, every addon showed 15 ms or less).
    -- (The older count: the newer one may have been taken after the frozen frame.)
    local base = overOld or overBase
    if e and base then
      C_Timer.After(1, function()
        local slow = ns.SlowSince(base, profilerAll("CountTimeOver100Ms"))
        e.slow = {}
        for i = 1, math.min(4, #slow) do e.slow[i] = slow[i].name end
      end)
    end
  end
  frameOurs, frameTop, frameTopMs = 0, nil, 0
  framePart, framePartMs, frameTipItem = nil, 0, nil
  frameItems = 0
  depth = 0   -- (a timed task that stopped with an error left it raised)
end)
-- Every second: each addon's count of frames over 100 ms, for the freeze above.
if C_AddOnProfiler and C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(1, function()
    if not loading then overOld, overBase = overBase, profilerAll("CountTimeOver100Ms") end
  end)
end
watch:RegisterEvent("LOADING_SCREEN_ENABLED")
watch:RegisterEvent("LOADING_SCREEN_DISABLED")
watch:RegisterEvent("PLAYER_LEAVING_WORLD")
watch:RegisterEvent("GET_ITEM_INFO_RECEIVED")
watch:SetScript("OnEvent", function(_, event)
  if event == "GET_ITEM_INFO_RECEIVED" then frameItems = frameItems + 1; return end
  loadingSeq = loadingSeq + 1
  if event == "LOADING_SCREEN_DISABLED" then
    -- (A few seconds more: the first frames after a loading screen are slow for everyone.
    -- Not if another loading screen began meanwhile.)
    local seq = loadingSeq
    C_Timer.After(5, function() if seq == loadingSeq then loading = false end end)
  else
    loading = true
  end
end)

ns.PerfNote = note
-- The item our tooltip lines were for this frame (a freeze names it after the tooltip is gone).
function ns.NoteTipItem(id) frameTipItem = id end
-- This frame's share so far (tests).
function ns.FrameShare() return frameOurs end

-- Wrap a function so its time is counted under a label.
function ns.Timed(label, fn)
  return function(...)
    -- Inside a sliced run the slice is timed as a whole, and a task timed here could be
    -- left open by a yield, so it just runs.
    if slicing and coroutine.running() == slicing then return fn(...) end
    local t, m, before = clock(), memKB(), depth
    depth = before + 1
    local a, b, c, d = fn(...)
    depth = before
    note(label, clock() - t, nil, memKB() - m)
    return a, b, c, d
  end
end

-- The live game hides some event text from addons (a "secret" value; seen on system chat
-- messages, November 5): even looking at one is an error. If the first argument is hidden
-- (the message itself), the event is skipped and /fl api lists it; a later one hidden
-- (Codex review: a cast's GUID, say) reaches the handlers as nil, so readable text isn't lost.
ns.secretSkipped = {}
local function firstSecret(...)
  for i = 1, select("#", ...) do
    if issecretvalue((select(i, ...))) then return i end
  end
end

local function withoutSecrets(...)
  local n, args = select("#", ...), { ... }
  for i = 1, n do
    if issecretvalue(args[i]) then args[i] = nil end
  end
  return unpack(args, 1, n)
end

local function dispatch(list, event, ...)
  local t, m, before = clock(), memKB(), depth
  for i = 1, #list do
    depth = before + 1   -- (again for each: a timed task that stopped with an error left it raised,
                         -- which made the rest of this frame's work look like parts: Codex, November 18)
    local ok, err = pcall(list[i], ...)
    if not ok then geterrorhandler()(err) end
  end
  depth = before
  note(event, clock() - t, nil, memKB() - m)
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  local secret = issecretvalue and firstSecret(...)
  if secret == 1 then
    ns.secretSkipped[event] = (ns.secretSkipped[event] or 0) + 1
  elseif secret then
    dispatch(list, event, withoutSecrets(...))
  else
    dispatch(list, event, ...)
  end
end)

-- The slowest tasks as lines of text, slowest single moment first (/fl perf, and the copy
-- kept at logout with /fl debug on).
function ns.PerfLines(n)
  local rows = {}
  for label, p in pairs(ns.perf) do rows[#rows + 1] = { label = label, p = p } end
  table.sort(rows, function(a, b) return a.p.max > b.p.max end)
  local lines = {}
  for i = 1, math.min(n, #rows) do
    local r = rows[i]
    lines[i] = ("%s: slowest %.0f ms, %d times, %.0f ms total"):format(r.label, r.p.max, r.p.n, r.p.ms)
      .. ((r.p.kb or 0) >= 1024 and (", %.1f MB of leftovers"):format(r.p.kb / 1024) or "")
  end
  return lines
end

-- The tasks that left the most memory behind, most first: "Label 12.3 MB, ...", or nil.
function ns.LeftoverLine(n)
  local rows = {}
  for label, p in pairs(ns.perf) do
    if (p.kb or 0) >= 1024 then rows[#rows + 1] = { label = label, kb = p.kb } end
  end
  if #rows == 0 then return end
  table.sort(rows, function(a, b) return a.kb > b.kb end)
  local out = {}
  for i = 1, math.min(n or 4, #rows) do out[i] = ("%s %.1f MB"):format(rows[i].label, rows[i].kb / 1024) end
  return "Most leftovers made: " .. table.concat(out, ", ")
end

-- The freeze watch's report (tested): the newest freezes first, each with Forever Ledger's
-- share and the other addons the game's profiler named, then which addons had the most
-- long frames this session.
function ns.FreezeLines(n)
  local lines, log = {}, (ns.db and ns.db.freezeLog) or {}
  if #log == 0 then
    lines[1] = ("  Freezes: none seen (a frame of %.2f seconds or more) since they were first watched."):format(FREEZE_SECONDS)
  else
    lines[1] = ("  Freezes (the newest %d of %d kept):"):format(math.min(n, #log), #log)
    for i = #log, math.max(1, #log - n + 1), -1 do
      local e = log[i]
      local ours = e.ours >= e.ms * 0.5 and ("|cffee8597Forever Ledger %d ms|r"):format(e.ours) or ("Forever Ledger %d ms"):format(e.ours)
      local parts = { ("%s: %d ms; %s"):format(date("%b %d %H:%M", e.t), e.ms, ours) }
      if e.what then
        parts[#parts + 1] = e.part and ("(most in %s, %d ms; slowest part %s, %d ms)"):format(e.what, e.whatMs or 0, e.part, e.partMs or 0)
          or ("(most in %s, %d ms)"):format(e.what, e.whatMs or 0)
      end
      if e.slow then
        parts[#parts + 1] = #e.slow > 0 and ("; |cffffd100addons with a frame over 100 ms within a second or two of it: " .. table.concat(e.slow, ", ") .. "|r")
          or "; no addon had a frame over 100 ms within a second or two of it"
      elseif e.addons then
        parts[#parts + 1] = "; slowest addons: " .. table.concat(e.addons, ", ")
      end
      if e.clearedMB then parts[#parts + 1] = ("; |cffffd100the game cleared %d MB of leftover memory in it|r"):format(e.clearedMB) end
      if e.grewMB then parts[#parts + 1] = ("; addons' memory grew %d MB in it"):format(e.grewMB) end
      if e.items then parts[#parts + 1] = ("; %d item details arrived from the game in it"):format(e.items) end
      if e.item then parts[#parts + 1] = "; tooltip on " .. (ns.ItemName(e.item) or ("item " .. e.item)) end
      lines[#lines + 1] = "    " .. table.concat(parts, " ")
    end
  end
  local over = profilerTop("CountTimeOver100Ms", 5)
  if over and #over > 0 then
    local out = {}
    for i, r in ipairs(over) do out[i] = ("%s %d"):format(r.name, r.v) end
    lines[#lines + 1] = "  Addons with the most frames over 100 ms this session: " .. table.concat(out, ", ")
  elseif not over then
    lines[#lines + 1] = "  (This game client has no addon profiler, so other addons can't be named; Forever Ledger's share still shows.)"
  end
  return lines
end

function ns:PrintPerf(reset)
  if reset then
    ns.perf, ns.perfSince, ns.perfDetail = {}, GetTime(), {}
    if ns.db then ns.db.freezeLog = nil end
    print(ns.PREFIX, "Timing and freezes reset. Play until it happens again, then /fl perf.")
    return
  end
  print(ns.PREFIX, ("Time used by Forever Ledger over the last %d seconds, slowest single moment first:"):format(GetTime() - ns.perfSince))
  for _, line in ipairs(ns.PerfLines(12)) do print("  " .. line) end
  local left = ns.LeftoverLine(4)
  if left then print("  " .. left) end
  if ns.perfDetailOn then
    print("  By kind of work (/fl perf detail; one can be inside another):")
    local lines = ns.DetailLines()
    if #lines == 0 then print("    none yet") end
    for _, line in ipairs(lines) do print("    " .. line) end
  end
  for _, line in ipairs(ns.FreezeLines(8)) do print(line) end
  -- Memory and loading, to see whether the data files (ClassicItems.lua) cost much.
  local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
  local usage = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
  if update and usage then
    -- Before and after clearing leftovers: the first counts memory the game hasn't
    -- tidied up yet (84.6 MB on October 2), the second what the addon really holds.
    pcall(update)
    local ok, before = pcall(usage, ADDON)
    collectgarbage("collect")
    pcall(update)
    local ok2, after = pcall(usage, ADDON)
    if ok and ok2 and before and after then
      print(("  Memory: %.1f MB in use, %.1f MB before clearing leftovers."):format(after / 1024, before / 1024))
    end
  end
  -- The biggest parts of the saved data, roughly (entries, and KB of text where it's text).
  -- A sample of each level's tables, the rest estimated from it, and a limit on the whole
  -- walk: walking all of it hit the game's time limit for one script (Frank's twentieth
  -- /fl perf, November 22: "script ran too long").
  -- (Every loop stops at the limit, and a part cut short or never reached says so: Codex
  -- review, November 22: the limit only stopped going deeper, and later parts read 0 KB.)
  local SAMPLE, LIMIT, visits = 24, 100000, 0
  local function measure(t, depth)
    local n, bytes, tables, sampled, sampledBytes, cut = 0, 0, 0, 0, 0, false
    for k, v in pairs(t) do
      if visits >= LIMIT then cut = true; break end
      n = n + 1
      visits = visits + 1
      if type(k) == "string" then bytes = bytes + #k end
      if type(v) == "string" then bytes = bytes + #v
      elseif type(v) == "table" and depth > 0 then
        tables = tables + 1
        if sampled < SAMPLE then
          sampled = sampled + 1
          local n2, b2, cut2 = measure(v, depth - 1)
          sampledBytes = sampledBytes + b2 + n2 * 16
          if cut2 then cut = true end
        end
      else bytes = bytes + 8 end
    end
    if sampled > 0 then bytes = bytes + sampledBytes * tables / sampled end
    return n, bytes, cut
  end
  local parts, unmeasured = {}, 0
  for key, v in pairs(ns.db or {}) do
    if type(v) == "table" then
      if visits >= LIMIT then unmeasured = unmeasured + 1
      else
        local n, bytes, cut = measure(v, 4)
        parts[#parts + 1] = { key = key, n = n, kb = bytes / 1024, cut = cut }
      end
    end
  end
  table.sort(parts, function(a, b) return a.kb > b.kb end)
  local out = {}
  for i = 1, math.min(6, #parts) do
    out[i] = ("%s %s%.0f KB"):format(parts[i].key, parts[i].cut and "at least " or "", parts[i].kb)
  end
  local tail = unmeasured > 0 and (" (%d more not measured: too much to look through at once)"):format(unmeasured) or ""
  print("  Biggest saved data (rough): " .. table.concat(out, ", ") .. tail)
  if ns.loadMs then
    print(("  Loading the addon's files took %.0f ms, setting up saved data %.0f ms."):format(ns.loadMs, ns.readyMs or 0))
  end
end

---------------------------------------------------------------------------
-- Settings profiles (owner, October 4; like EllesmereUI's): each character uses a
-- profile, "Default" to start. A profile holds only the settings that can differ per
-- character (ns.PER_CHAR_SETTINGS, from Settings.lua); Global settings (price and deal
-- rules) are the same for everyone and never in a profile.
--   Default: those settings live in ns.db.settings itself, as they always have.
--   Any other: ns.db.profiles[name] = { [setting] = value }, and charProfile[charKey] =
--   name. For a character on one, ns.db.settings is a stand-in that reads the profile's
--   value (or the setting's default) for per-character settings and the shared table for
--   the rest, and writes the same way. The shared table is put back before the game
--   saves (PLAYER_LOGOUT) and kept under settingsAccount too, in case that ever fails.
-- Characters on Default (everyone who never makes a profile): nothing changes.
---------------------------------------------------------------------------
ns.DEFAULT_PROFILE = "Default"

function ns:PerCharSetting(key) return ns.PER_CHAR_SETTINGS and ns.PER_CHAR_SETTINGS[key] or false end

-- The profile a character uses (this one if no key).
function ns:ProfileOf(charKey)
  local name = ns.db and ns.db.charProfile and ns.db.charProfile[charKey or ns.CharKey()]
  if name and ns.db.profiles[name] then return name end
  return ns.DEFAULT_PROFILE
end

function ns:ApplyCharSettings()
  local db = ns.db
  ns.accountSettings = ns.accountSettings or db.settings
  local account = ns.accountSettings
  local name = ns:ProfileOf()
  if name == ns.DEFAULT_PROFILE then
    db.settings, db.settingsAccount = account, nil
    return
  end
  local values = db.profiles[name]
  local defaults = ns.DEFAULT_SETTINGS or {}
  db.settingsAccount = account
  db.settings = setmetatable({}, {
    __index = function(_, k)
      if ns:PerCharSetting(k) then
        local v = values[k]
        if v ~= nil then return v end
        -- (A setting added after the profile was made starts at its default.)
        if defaults[k] ~= nil then return defaults[k] end
      end
      return account[k]
    end,
    __newindex = function(_, k, v)
      if ns:PerCharSetting(k) then values[k] = v else account[k] = v end
    end,
  })
end

ns:On("PLAYER_LOGOUT", function()
  -- With /fl debug on, this session's /fl perf, to read after a reload (owner, November 11:
  -- how long the Buy queue takes to rebuild when a flip comes in).
  if ns.db and ns.db.settings and ns.db.settings.debug and ns.PerfLines then
    ns.db.perfLog = { t = time(), secs = math.floor(GetTime() - ns.perfSince), lines = ns.PerfLines(25) }
  end
  if ns.db and ns.accountSettings then
    ns.db.settings, ns.db.settingsAccount = ns.accountSettings, nil
  end
end)

ns.readyCallbacks = {}
function ns:OnReady(fn) table.insert(ns.readyCallbacks, fn) end

ns:On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  local t = clock()
  if ns.loadStart then ns.loadMs = t - ns.loadStart end
  ForeverLedgerDB = ForeverLedgerDB or {}
  -- Schema 2 (0.9.0): the first sell speed data (historySold, counts of listings that
  -- went down: mostly noise, replaced by historySold2) is dropped, with the owner's
  -- go-ahead (October 3). Nothing read it any more; it was about 170 KB.
  if (ForeverLedgerDB.schema or 1) < 2 then
    ForeverLedgerDB.historySold = nil
    ForeverLedgerDB.schema = 2
  end
  -- Schema 3: crate turn-ins pay the same for every crate (owner, October 3), so the
  -- Favor and money learned per crate (crateFavor, crateMoney) aren't used any more.
  if ForeverLedgerDB.schema < 3 then
    ForeverLedgerDB.crateFavor, ForeverLedgerDB.crateMoney = nil, nil
    ForeverLedgerDB.schema = 3
  end
  -- Schema 4: one kind of shopping list (list.kind and list.wantMode go, list.countHave
  -- for crate lists). The lists themselves are changed at login by ShoppingLists.lua
  -- (it needs bag counts), once (shopping.oneKind). The setting for new lists' kind goes.
  if ForeverLedgerDB.schema < 4 then
    if ForeverLedgerDB.settings then ForeverLedgerDB.settings.listKind = nil end
    ForeverLedgerDB.schema = 4
  end
  -- Schema 5: "Just for this character" (charSettings, one day in testing) becomes
  -- settings profiles: a character that had its own settings gets a profile named after it.
  if ForeverLedgerDB.schema < 5 then
    local db = ForeverLedgerDB
    db.profiles, db.charProfile = db.profiles or {}, db.charProfile or {}
    for key, c in pairs(db.charSettings or {}) do
      if type(c) == "table" and c.own and type(c.values) == "table" then
        local who = db.chars and db.chars[key]
        local name, n = (who and who.name) or key, 2
        local base = name
        while db.profiles[name] or name == "Default" do name = base .. " " .. n; n = n + 1 end
        db.profiles[name] = c.values
        db.charProfile[key] = name
      end
    end
    db.charSettings = nil
    db.schema = 5
  end
  -- Schema 6: price provenance. Existing limits were chosen before sources were
  -- recorded, so protect every nonzero limit as the player's own (including any).
  if ForeverLedgerDB.schema < 6 then
    for _, list in ipairs((ForeverLedgerDB.shopping or {}).lists or {}) do
      list.allowance = list.allowance or 10
      for _, e in ipairs(list.items or {}) do
        if not e.src then e.src = ((e.max or 0) ~= 0 or e.offSet) and "you" or "usual" end
      end
    end
    ForeverLedgerDB.schema = 6
  end
  -- Schema 7 adds an optional disenchant source to shopping entries. Existing limits
  -- and their provenance remain unchanged; no old entry becomes a DE purchase.
  if ForeverLedgerDB.schema < 7 then ForeverLedgerDB.schema = 7 end
  -- Schema 8: characters, prices and history filed under one server of a realm ("CAMWOW
  -- US2 Realm 3 PvE") move to the plain realm ("PvE"), so they all count as one realm.
  if ForeverLedgerDB.schema < 8 then
    ns.PlainRealmData(ForeverLedgerDB)
    ForeverLedgerDB.schema = 8
  end
  -- Schema 9 (November 15): groups and rules (Groups.lua) start empty; nothing moves.
  if ForeverLedgerDB.schema < 9 then
    ForeverLedgerDB.schema = 9
  end
  -- Schema 10 (November 19): professions are keyed by their English name on every client.
  -- profAliases (the game's names, learned as they're seen) starts empty; entries saved
  -- under a translated name are merged into the English key at every login and after sync
  -- or import, once that name is known (ns.NormalizeProfessions). Nothing is dropped.
  if ForeverLedgerDB.schema < 10 then
    ForeverLedgerDB.profAliases = ForeverLedgerDB.profAliases or {}
    ForeverLedgerDB.schema = 10
  end
  -- Schema 11 (November 21): charRealm remembers each character's realm (ns.RealmName);
  -- it fills in as characters log in, and data saved under an empty realm moves back below.
  if ForeverLedgerDB.schema < 11 then
    ForeverLedgerDB.charRealm = ForeverLedgerDB.charRealm or {}
    ForeverLedgerDB.schema = 11
  end
  -- Settings per character (below): while a character used its own, the shared settings
  -- were also kept under settingsAccount. If the game ever saved the stand-in instead of
  -- the real table, this brings them back.
  if type(ForeverLedgerDB.settingsAccount) == "table" then
    ForeverLedgerDB.settings = ForeverLedgerDB.settingsAccount
    ForeverLedgerDB.settingsAccount = nil
  end
  copyDefaults(DEFAULTS, ForeverLedgerDB)
  ns.db = ForeverLedgerDB
  -- Anything saved while the game gave no realm name (see ns.RealmName) goes back under it.
  local okFix, errFix = pcall(function()
    local realm = ns.RealmName()
    if realm and ns.HasBlankRealmData(ForeverLedgerDB, realm) then ns.FixBlankRealm(ForeverLedgerDB, realm) end
  end)
  if not okFix then geterrorhandler()(errFix) end
  ns:ApplyCharSettings()
  if ns.Theme and ns.Theme.Apply then ns.Theme:Apply() end   -- the look, before any of our frames exist
  for _, fn in ipairs(ns.readyCallbacks) do
    local ok, err = pcall(fn)
    if not ok then geterrorhandler()(err) end
  end
  ns.readyMs = clock() - t
end)

---------------------------------------------------------------------------
-- Export / import (plain-text format, no code execution)
---------------------------------------------------------------------------
local function ser(v, out)
  local t = type(v)
  if t == "number" then
    out[#out + 1] = "n" .. tostring(v) .. ";"
  elseif t == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, val in pairs(v) do
      local kt = type(k)
      if (kt == "string" or kt == "number") and type(val) ~= "function" then
        ser(k, out)
        ser(val, out)
      end
    end
    out[#out + 1] = "}"
  end
end

local function des(s, i)
  if i > #s then error("Import text ends early. Make sure you copied all of it.") end
  local c = s:sub(i, i)
  if c == "n" then
    local j = s:find(";", i, true)
    return tonumber(s:sub(i + 1, j - 1)), j + 1
  elseif c == "s" then
    local j = s:find(":", i, true)
    local len = tonumber(s:sub(i + 1, j - 1))
    return s:sub(j + 1, j + len), j + len + 1
  elseif c == "T" then
    return true, i + 1
  elseif c == "F" then
    return false, i + 1
  elseif c == "{" then
    local t = {}
    i = i + 1
    while s:sub(i, i) ~= "}" do
      local k, v
      k, i = des(s, i)
      v, i = des(s, i)
      if k == nil then error("Import text is damaged.") end
      t[k] = v
    end
    return t, i + 1
  end
  error("Import text is damaged near character " .. i .. ".")
end

function ns.Serialize(v)
  local out = { "FL1:" }
  ser(v, out)
  return table.concat(out)
end

function ns.Deserialize(s)
  s = (s or ""):match("^%s*(.-)%s*$")
  if s:sub(1, 4) ~= "FL1:" then return nil, "That isn't a Forever Ledger export." end
  local ok, v = pcall(function() return (des(s, 5)) end)
  if not ok then return nil, tostring(v) end
  return v
end

function ns:Export()
  return ns.Serialize({
    v = 1,
    from = ns.CharKey(),
    t = time(),
    chars = ns.db.chars,
    prices = ns.db.prices,
    vendorBuy = ns.db.vendorBuy,
    vendorSell = ns.db.vendorSell,
  })
end

function ns:Import(text)
  local data, err = ns.Deserialize(text)
  if not data then return false, err end
  if type(data) ~= "table" then return false, "That isn't a Forever Ledger export." end
  if data.kind == "profile" then return false, "That's a settings profile: import it in Settings, Profiles." end
  local nChars, nPrices = ns:MergeData(data)
  return true, ("Imported %d characters and %d prices."):format(nChars, nPrices)
end

-- A character played on this account: the one you're on, or one whose bags were saved
-- here (Inventory.lua saves them at every login). Characters from a sync partner or an
-- import have no bags saved here, or bags marked as the partner's (inv.via).
function ns:IsOwnChar(key)
  if key == ns.CharKey() then return true end
  local inv = ns.db.inventory and ns.db.inventory[key]
  return inv ~= nil and not inv.via
end

-- Whether two records of a character have the same recipes, as the recipe index reads them
-- (realm, faction, name, and each recipe's fields and materials): sync sends a partner's
-- characters with a new time on nearly every message, and rebuilding the recipe index for
-- each threw every value away (Frank's /fl perf, November 21). Counting recipes wasn't
-- enough: a corrected recipe, or another one in its place, left the index on the old one
-- (Codex review, November 21). Builds nothing, so the usual case costs no leftovers.
local NONE = {}
local function sameFields(a, b)
  for k, v in pairs(a) do if k ~= "r" and b[k] ~= v then return false end end
  for k, v in pairs(b) do if k ~= "r" and a[k] ~= v then return false end end
  return true
end
local function sameRecipe(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or not sameFields(a, b) then return false end
  local ra, rb = a.r or NONE, b.r or NONE
  if #ra ~= #rb then return false end
  for i = 1, #ra do
    local x, y = ra[i], rb[i]
    if type(x) ~= "table" or type(y) ~= "table" or x[1] ~= y[1] or x[2] ~= y[2] then return false end
  end
  return true
end
local function sameRecipes(old, new)
  if type(old) ~= "table" or type(new) ~= "table" then return false end
  if old.realm ~= new.realm or old.faction ~= new.faction or old.name ~= new.name then return false end
  local po, pn = old.profs or NONE, new.profs or NONE
  for prof in pairs(pn) do if po[prof] == nil then return false end end
  for prof, p in pairs(po) do
    local q = pn[prof]
    if type(p) ~= "table" or type(q) ~= "table" or p.rank ~= q.rank then return false end
    local ro, rn = p.recipes or NONE, q.recipes or NONE
    for id in pairs(rn) do if ro[id] == nil then return false end end
    for id, rec in pairs(ro) do
      if not sameRecipe(rec, rn[id]) then return false end
    end
  end
  return true
end
ns.SameRecipes = sameRecipes   -- (tests)

-- Merge characters, prices and vendor prices from another account (Import and live
-- sync). Newer data wins. via = the sync partner's name: what comes from them is marked
-- with it (c.via, inv.via) so unpairing can remove it, and it never replaces a character
-- of this account. Returns how many characters, prices, vendor prices and characters'
-- bags changed.
function ns:MergeData(data, via)
  local db, nChars, nPrices, nVendor, nBags = ns.db, 0, 0, 0, 0
  local newRecipes = false
  if ns.SlicePart then ns.SlicePart("realm names") end   -- (in /fl perf, when in slices)
  ns.PlainRealmData(data)   -- (from someone still on a version that files by server)
  -- (and from one that saved under an empty realm name: November 21)
  -- (Each character to its own realm, learned from both sides' records.)
  if ns.RealmName() and ns.HasBlankRealmData(data, ns.RealmName(), db) then ns.FixBlankRealm(data, ns.RealmName(), db) end
  if ns.SlicePart then ns.SlicePart("recipes") end
  for key, c in pairs(data.chars or {}) do
    if ns.MaybeYield then ns.MaybeYield() end   -- (each character's recipes are compared: sameRecipes)
    local mine = db.chars[key]
    if via and ns:IsOwnChar(key) then
      -- (yours: keep your own copy)
    elseif not mine or (c.updated or 0) > (mine.updated or 0) then
      if not mine or not sameRecipes(mine, c) then newRecipes = true end
      c.via = via or c.via
      db.chars[key] = c
      nChars = nChars + 1
    elseif via and not mine.via then
      mine.via = via   -- came before sync marked characters (October 5)
    end
  end
  -- Bags and bank each by their own time (Codex review, October 5: newer bags with an
  -- unchanged bank were ignored, and newer bags could carry an older bank over a newer).
  for key, inv in pairs(via and data.inventory or {}) do
    if type(inv) == "table" and not ns:IsOwnChar(key) then
      local mine = db.inventory[key]
      if not mine then
        mine = { bags = {}, bank = {} }
        db.inventory[key] = mine
      end
      local changed = false
      if inv.bags and (inv.t or 0) > (mine.t or 0) then mine.bags, mine.t, changed = inv.bags, inv.t, true end
      if inv.bank and (inv.bankT or 0) > (mine.bankT or 0) then mine.bank, mine.bankT, changed = inv.bank, inv.bankT, true end
      mine.via = via
      if changed then nBags = nBags + 1 end
    end
  end
  -- A partner's prices from today also go into today's price history (owner's
  -- screenshot, November 8: the main account's graph only had the days it scanned
  -- itself, while the auction house character scanned every day). Earlier days aren't
  -- sent, so they can't be filled in. Recorded over the next frames (History.lua): a
  -- full scan's thousands in one go ran too long (Frank's BugSack, November 12).
  local nowDay = ns.LocalDay and ns.LocalDay(time())
  local later, here, changedIds = {}, ns.MarketKey(), {}
  if ns.SlicePart then ns.SlicePart("prices") end   -- (in /fl perf, when in slices)
  -- (MaybeYield: live sync takes a message in over several frames; the payload's own tables
  -- are walked, so prices saved meanwhile don't break the walk.)
  for market, items in pairs(data.prices or {}) do
    db.prices[market] = db.prices[market] or {}
    for id, rec in pairs(items) do
      if ns.MaybeYield then ns.MaybeYield() end
      local mine = db.prices[market][id]
      if not mine or (rec.t or 0) > (mine.t or 0) then
        db.prices[market][id] = rec
        nPrices = nPrices + 1
        if market == here then changedIds[id] = true end
        if via and nowDay and rec.t and rec.m and not rec.none and ns.LocalDay(rec.t) == nowDay then
          later[#later + 1] = { id, rec.m, rec.a, rec.q, market, rec = rec, day = nowDay }
        end
      end
    end
  end
  if ns.RecordPriceHistoryLater then ns:RecordPriceHistoryLater(later) end
  for id, rec in pairs(data.vendorBuy or {}) do
    local mine = db.vendorBuy[id]
    if not mine or (rec.t or 0) > (mine.t or 0) then db.vendorBuy[id] = rec; nVendor = nVendor + 1; changedIds[id] = true end
  end
  for id, v in pairs(data.vendorSell or {}) do
    if db.vendorSell[id] == nil then db.vendorSell[id] = v; nVendor = nVendor + 1; changedIds[id] = true end
  end
  if ns.SlicePart then ns.SlicePart("sales and purchases") end
  local nBooks = via and data.books and ns:MergeBooks(data.books, via) or 0
  if ns.SlicePart then ns.SlicePart("characters") end
  if newRecipes and ns.BuildUsageIndex then ns:BuildUsageIndex() end
  -- Only the items that changed have their values worked out again (values don't read bags):
  -- a partner's prices threw every value away within 30 seconds (Frank's /fl perf, November 21).
  if ns.InvalidateItem then
    for id in pairs(changedIds) do ns:InvalidateItem(id) end
  elseif (nPrices > 0 or nVendor > 0) and ns.InvalidateValues then ns:InvalidateValues() end
  -- A partner's or an import's professions under a translated name (Codex review, November 19).
  if nChars > 0 and ns.NormalizeProfessions then ns.NormalizeProfessions(db) end
  return nChars, nPrices, nVendor, nBags, nBooks
end

-- Forget a character: its level, professions, recipes, bags and bank, and the profile it
-- used. Its gold and money history stay (owner, October 3: history isn't dropped without
-- asking). Not the character you're on. Prices are never touched.
function ns:RemoveCharacter(key)
  if not key or key == ns.CharKey() or not ns.db.chars[key] then return false end
  ns.db.chars[key] = nil
  ns.db.inventory[key] = nil
  if ns.db.charProfile then ns.db.charProfile[key] = nil end
  return true
end

-- Everything that came from a sync partner (/fl unpair): their characters and their bags.
function ns:RemoveSyncedFrom(name)
  local who, n = (name or ""):lower(), 0
  -- Never one played on this account, whatever its mark says.
  for key, c in pairs(ns.db.chars) do
    if c.via and c.via:lower() == who and not ns:IsOwnChar(key) and ns:RemoveCharacter(key) then
      n = n + 1
      ns:DropBooks(key)
    end
  end
  -- Their books go even for a character already removed from Settings, which keeps its
  -- history while it's yours to keep (Codex review, November 5).
  for key, from in pairs(ns.db.booksFrom or {}) do
    if from:lower() == who then
      if not ns:IsOwnChar(key) then ns:DropBooks(key) end
      ns.db.booksFrom[key] = nil
    end
  end
  for key, inv in pairs(ns.db.inventory) do
    if inv.via and inv.via:lower() == who and key ~= ns.CharKey() then ns.db.inventory[key] = nil end
  end
  if ns.BuildUsageIndex then ns:BuildUsageIndex() end
  if ns.InvalidateValues then ns:InvalidateValues() end
  if ns.RefreshUI then ns:RefreshUI() end
  return n
end

---------------------------------------------------------------------------
-- API report, used while testing on the beta
---------------------------------------------------------------------------
function ns:ApiReport()
  local function has(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
      if type(cur) ~= "table" then return false end
      cur = cur[part]
    end
    return cur ~= nil
  end
  local checks = {
    "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetRecipeSchematic",
    "C_TradeSkillUI.GetRecipeNumReagents", "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetProfessionInfoBySkillLineID", "C_TradeSkillUI.GetTradeSkillLine",
    "GetProfessions", "GetNumSkillLines",
    "C_AuctionHouse.SendSearchQuery", "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetReplicateItemTimeLeft","C_AuctionHouse.GetCommoditySearchResultInfo",
    "C_AuctionHouse.GetItemSearchResultInfo", "C_MerchantFrame.GetItemInfo", "GetMerchantItemInfo",
    "TooltipDataProcessor.AddTooltipPostCall", "IsPlayerSpell", "C_Spell.GetSpellName", "C_Item.GetItemInfo", "C_Item.IsItemDataCachedByID", "C_Item.RequestLoadItemDataByID", "C_Item.GetItemCount", "GetItemCount",
    "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItem", "GetInboxNumItems",
    -- Your auctions (Auctions.lua).
    "C_AuctionHouse.CalculateCommodityDeposit", "C_AuctionHouse.CalculateItemDeposit", "C_AuctionHouse.GetItemKeyInfo",
    "ItemLocation.CreateFromBagAndSlot",
    "C_AuctionHouse.QueryOwnedAuctions", "C_AuctionHouse.GetNumOwnedAuctions", "C_AuctionHouse.GetOwnedAuctionInfo",
    "C_AuctionHouse.CancelAuction", "TakeInboxMoney", "AutoLootMailItem", "RepairAllItems",
    "BuyMerchantItem", "GetMerchantItemID", "GetNumBuybackItems", "GetBuybackItemInfo", "GetBuybackItemLink", "BuybackItem", "C_Container.UseContainerItem", "C_Container.GetContainerItemInfo",
    "C_TradeSkillUI.CraftRecipe", "C_TradeSkillUI.OpenTradeSkill", "LOOT_ITEM_CREATED_SELF",
    "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink", "GetLootSourceInfo", "C_Container.GetContainerNumSlots",
    "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceSkillReq", "GetTrainerServiceCost",
    "C_Map.GetBestMapForUnit", "C_Map.SetUserWaypoint",
    "C_QuestLog.GetAllCompletedQuestIDs", "GetQuestsCompleted", "C_QuestLog.GetTitleForQuestID",
    "C_QuestLog.RequestLoadQuestByID", "GetQuestGreenRange", "IsInInstance", "GetInstanceInfo",
    "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "ChatFrame_AddMessageEventFilter",
    "C_AuctionHouse.PostItem", "C_AuctionHouse.PostCommodity", "C_AuctionHouse.ConfirmCommoditiesPurchase",
    -- Buy queue (BuyQueue.lua): buying needs these, each from a click or a mouse wheel tick.
    "C_AuctionHouse.StartCommoditiesPurchase", "C_AuctionHouse.CancelCommoditiesPurchase", "C_AuctionHouse.PlaceBid",
    "C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.GetBrowseResults", "C_AuctionHouse.HasFullBrowseResults",
    -- Live watch's browse sweep (Sweep.lua): the whole list, and the searches that replace it.
    "C_AuctionHouse.RequestMoreBrowseResults", "C_AuctionHouse.SearchForItemKeys", "C_AuctionHouse.SearchForFavorites",
    "Enum.AuctionHouseFilter.PoorQuality", "Enum.AuctionHouseSortOrder.Name",
    -- Our tabs in the auction house window (AHTabs.lua), the groups (Groups.lua).
    "PanelTemplates_TabResize", "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab", "C_Item.GetItemInfoInstant", "C_Item.GetItemQualityByID",
    "C_AuctionHouse.GetItemCommodityStatus", "C_AuctionHouse.GetQuoteDurationRemaining", "C_AuctionHouse.IsThrottledMessageSystemReady", "C_CVar.SetCVar", "SetOverrideBindingClick",
    "Enum.TooltipDataLineType.SellPrice",
    "AHledgerAPI.GetPrice", "C_AddOnProfiler.GetAddOnMetric", "Enum.AddOnProfilerMetric.LastTime", "Auctionator.API.v1.GetAuctionPriceByItemID", "TSM_API.GetCustomPriceValue", "AucAdvanced.API.GetMarketValue",
    -- Pets (owner, September 30: planning a pet collection module; Forever's collection
    -- window has no pet tab yet). Modern journal, and Classic's older companion list.
    "C_PetJournal.GetNumPets", "C_PetJournal.GetPetInfoByIndex", "C_PetJournal.GetPetInfoBySpeciesID",
    "C_PetJournal.GetPetInfoByItemID", "C_PetJournal.SetSearchFilter", "GetNumCompanions", "GetCompanionInfo",
    -- Mounts, toys and appearances (owner, October 1: mounts got cheap and riding
    -- training dear, so a mount collection tab is likely; plan a Collections module).
    "C_MountJournal.GetNumMounts", "C_MountJournal.GetMountIDs", "C_MountJournal.GetMountInfoByID",
    "C_MountJournal.GetMountFromItem", "C_MountJournal.GetMountInfoExtraByID",
    "C_ToyBox.GetNumToys", "C_ToyBox.GetToyInfo", "PlayerHasToy",
    "C_TransmogCollection.GetItemInfo", "C_TransmogCollection.PlayerHasTransmog",
    -- Training (Training.lua, October 5): trainer levels, talents, riding, casts.
    "GetTrainerServiceLevelReq", "GetTrainerServiceTypeFilter", "GetNumTalentTabs", "GetTalentTabInfo",
    "GetTalentInfo", "IsPlayerSpell", "IsSpellKnown", "GetSkillLineInfo", "C_SpellBook.IsSpellKnown",
  }
  print(ns.PREFIX, "API check (include this in a bug report if something isn't working):")
  for _, path in ipairs(checks) do
    print(("  %s %s"):format(has(path) and "|cff7fd39cyes|r" or "|cffee8597no|r ", path))
  end
  print("  Market: " .. ns.MarketKey())
  print(("  %s GLOBAL_MOUSE_DOWN event (Buy queue panel comes to the front)"):format(
    ns:EventKnown("GLOBAL_MOUSE_DOWN") and "|cff7fd39cyes|r" or "|cffee8597no|r "))
  for _, event in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE" }) do
    print(("  %s %s event (reading the whole auction house list)"):format(
      ns:EventKnown(event) and "|cff7fd39cyes|r" or "|cffee8597no|r ", event))
  end
  -- Which ruleset the character is on (owner, October 3: group characters by ruleset,
  -- not by server name, if the game says it). Each is tried safely and printed.
  local function try(label, fn)
    local ok, a, b = pcall(fn)
    print(("  %s: %s"):format(label, ok and (tostring(a) .. (b ~= nil and (", " .. tostring(b)) or "")) or "not available"))
  end
  try("Realm", function() return GetRealmName(), GetNormalizedRealmName and GetNormalizedRealmName() end)
  try("Realm ID", function() return GetRealmID and GetRealmID() end)
  try("Hidden from addons", function()
    local skipped = {}
    for event, n in pairs(ns.secretSkipped) do skipped[#skipped + 1] = ("%s %d"):format(event, n) end
    table.sort(skipped)
    return #skipped > 0 and table.concat(skipped, ", ") or "nothing so far"
  end)
  try("Season", function() return C_Seasons and C_Seasons.GetActiveSeason and C_Seasons.GetActiveSeason() end)
  try("Hardcore", function() return C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() end)
  try("PvP server", function() return C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired(), IsPVPTimerRunning and IsPVPTimerRunning() end)
  try("Server type", function() return GetCVar and GetCVar("realmName"), GetCVar and GetCVar("portal") end)
  try("Riding", function() return ns.RidingReport and ns:RidingReport() end)
  -- Blizzard's tab art, for icon tabs on the window's right edge like the spellbook's
  -- (owner, October 7): which templates, files and atlases this client has.
  try("Tab art", function()
    local found = {}
    for _, t in ipairs({ "SpellBookSkillLineTabTemplate", "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate",
                         "PanelTopTabButtonTemplate", "SideTabTemplate" }) do
      -- C_XMLUtil knows templates without making a frame; else try making one.
      local ok
      if C_XMLUtil and C_XMLUtil.GetTemplateInfo then ok = C_XMLUtil.GetTemplateInfo(t) ~= nil
      else ok = pcall(CreateFrame, "CheckButton", nil, nil, t) end
      found[#found + 1] = (ok and "+" or "-") .. t
    end
    if GetFileIDFromPath then
      for _, p in ipairs({ "Interface\\SpellBook\\SpellBook-SkillLineTab", "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab",
                           "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab", "Interface\\HelpFrame\\HelpFrameTab-Active" }) do
        found[#found + 1] = (GetFileIDFromPath(p) and "+" or "-") .. p:match("[^\\]+$")
      end
    end
    if C_Texture and C_Texture.GetAtlasInfo then
      for _, a in ipairs({ "uiframe-tab-left", "uiframe-activetab-left", "spellbook-skilllinetab", "QuestLog-tab", "Options_Tab_Left" }) do
        found[#found + 1] = (C_Texture.GetAtlasInfo(a) and "+" or "-") .. "atlas " .. a
      end
    end
    return table.concat(found, " ")
  end)
  -- The WoW Forever look (owner, November 11: make the addon fit the game's own windows;
  -- planning/UI_OVERHAUL_PREP.md): which of the game's frame art this client has, and at
  -- what size, and which of Blizzard's window and control templates. The names are the
  -- ones EllesmereUI's WoW Forever look draws with.
  -- Kept (this /fl api's only) so it can be read from the saved data after a reload: a
  -- fresh report each time, each part "not available" until it's read (Codex review of
  -- b0296a7: a failed part kept the last report's result).
  local look = { t = time(), art = "not available", templates = "not available" }
  ns.db.apiLook = look
  try("Forever art", function()
    local found = {}
    if not (C_Texture and C_Texture.GetAtlasInfo) then look.art = "no atlas lookup"; return look.art end
    for _, a in ipairs({ "UI-Frame-Metal-CornerTopLeft", "_UI-Frame-Metal-EdgeTop", "!UI-Frame-Metal-EdgeLeft",
                         "UI-Frame-Metal-CornerBottomRight", "UI-HUD-ActionBar-Frame", "ui-frame-portraitmetal",
                         "uiframe-tab-left", "common-dropdown-bg", "common-search-border-left",
                         "common-button-tertiary-square-normal", "common-coinbox-left", "uitools-icon-close",
                         "Ui-Dialog-New-Background" }) do
      local info = C_Texture.GetAtlasInfo(a)
      found[#found + 1] = info and ("+%s %dx%d"):format(a, info.width or 0, info.height or 0) or ("-" .. a)
    end
    look.art = table.concat(found, " ")
    return look.art
  end)
  try("Window templates", function()
    local found = {}
    for _, t in ipairs({ "ButtonFrameTemplate", "PortraitFrameTemplate", "BasicFrameTemplateWithInset", "DefaultPanelTemplate",
                         "UIPanelButtonTemplate", "UICheckButtonTemplate", "InputBoxTemplate", "SearchBoxTemplate",
                         "ScrollFrameTemplate", "UIPanelScrollFrameTemplate", "WowStyle1DropdownTemplate", "UIDropDownMenuTemplate" }) do
      local ok
      if C_XMLUtil and C_XMLUtil.GetTemplateInfo then ok = C_XMLUtil.GetTemplateInfo(t) ~= nil
      else ok = pcall(CreateFrame, "Frame", nil, nil, t) end
      found[#found + 1] = (ok and "+" or "-") .. t
    end
    local layouts = type(NineSliceLayouts) == "table" and NineSliceLayouts or nil
    for _, l in ipairs({ "ButtonFrameTemplateNoPortrait", "PortraitFrameTemplate" }) do
      found[#found + 1] = ((layouts and layouts[l]) and "+" or "-") .. "layout " .. l
    end
    look.templates = table.concat(found, " ")
    return look.templates
  end)
  try("Spells cast saved", function()
    local n = 0
    for _ in pairs((ns.db.casts or {})[ns.CharKey()] or {}) do n = n + 1 end
    return n
  end)
  -- If the pet journal exists: how many pets it knows, and one sample with its
  -- "how to get it" text (the 12th value), to see what a pet module could show.
  if C_PetJournal and C_PetJournal.GetNumPets then
    local ok, total, owned = pcall(C_PetJournal.GetNumPets)
    print(("  Pet journal: %s pets listed, %s owned"):format(ok and tostring(total) or "error", ok and tostring(owned) or "?"))
    if ok and (total or 0) > 0 and C_PetJournal.GetPetInfoByIndex then
      local ok2, _, species, isOwned, _, _, _, _, name, _, _, _, source, _, _, _, tradeable = pcall(C_PetJournal.GetPetInfoByIndex, 1)
      if ok2 then
        print(("  Sample: %s (species %s), owned %s, tradeable %s, source: %s"):format(tostring(name), tostring(species),
          tostring(isOwned), tostring(tradeable), tostring(source):gsub("|", "||"):sub(1, 120)))
      end
    end
  end
  if GetNumCompanions then
    local ok, n = pcall(GetNumCompanions, "CRITTER")
    print("  Companion pets known (old list): " .. (ok and tostring(n) or "error"))
  end
  -- Mount journal: how many mounts it knows, and one sample with its source text.
  if C_MountJournal and C_MountJournal.GetMountIDs then
    local ok, ids = pcall(C_MountJournal.GetMountIDs)
    print(("  Mount journal: %s mounts listed"):format(ok and type(ids) == "table" and #ids or "error"))
    if ok and type(ids) == "table" and ids[1] and C_MountJournal.GetMountInfoByID then
      local ok2, name, _, _, _, _, _, _, _, faction, _, collected = pcall(C_MountJournal.GetMountInfoByID, ids[1])
      local source
      if C_MountJournal.GetMountInfoExtraByID then
        local ok3, _, _, src = pcall(C_MountJournal.GetMountInfoExtraByID, ids[1])
        source = ok3 and src or nil
      end
      if ok2 then
        print(("  Mount sample: %s, collected %s, faction %s, source: %s"):format(tostring(name), tostring(collected),
          tostring(faction), tostring(source):gsub("|", "||"):sub(1, 120)))
      end
    end
  end
  if C_ToyBox and C_ToyBox.GetNumToys then
    local ok, n = pcall(C_ToyBox.GetNumToys)
    print("  Toy box: " .. (ok and tostring(n) or "error") .. " toys listed")
  end
  -- The journal listed 0 pets for an owner with none (September 30). Asking for pets by
  -- their item shows whether the data is there anyway: Cat Carrier (Bombay) 8485,
  -- Cat Carrier (Siamese) 8490, Parrot Cage (Green Wing Macaw) 8492, Excitable Slime 275682.
  if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
    for _, item in ipairs({ 8485, 8490, 8492, 275682 }) do
      local ok, name, _, _, _, source, _, _, _, tradeable, _, _, _, species = pcall(C_PetJournal.GetPetInfoByItemID, item)
      print(("  Pet item %d: %s"):format(item, not ok and "error" or not name and "no data" or
        ("%s (species %s), tradeable %s, source: %s"):format(name, tostring(species), tostring(tradeable),
          tostring(source):gsub("|", "||"):sub(1, 120))))
    end
  end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_FOREVERLEDGER1 = "/fl"
SLASH_FOREVERLEDGER2 = "/ledger"
SlashCmdList.FOREVERLEDGER = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" then
    ns:ToggleUI()
  elseif msg == "scan" then
    ns.Scan:Start("auto")
  elseif msg == "scan materials" then
    ns.Scan:Start("watch")
  elseif msg == "scan full" then
    ns.Scan:Start("full")
  elseif msg == "watch" then
    ns:ToggleFlipWatch()
  elseif msg == "quiet" then
    ns:ToggleQuiet()
  elseif msg == "queue" or msg == "buy" then
    ns:ShowSidePanel("queue")
  elseif msg == "lists" or msg == "list" then
    ns:ShowSidePanel("lists")
  elseif msg == "new" or msg == "whatsnew" then
    if ns.ShowWhatsNewCard then ns:ShowWhatsNewCard() elseif ns.ShowWhatsNew then ns:ShowWhatsNew() end
  elseif msg == "welcome" then
    ns:ToggleUI("dashboard")
    if ns.ShowWelcome then ns:ShowWelcome() end
  elseif msg == "customers on" then
    ns:SilenceCustomers("on")
  elseif msg == "customers off" then
    ns:SilenceCustomers("always")
  elseif msg == "customers" then
    ns:ShowCustomers()
  elseif msg == "work" or msg == "worklog" then
    ns:ShowWorkLog()
  elseif msg:match("^customer ") then
    ns:TestCustomer(msg:match("^customer (.+)$"))
  elseif msg == "stop" then
    if ns.StopFlipWatch then ns:StopFlipWatch(true) end
    ns.Scan:Stop("Scan stopped.")
  elseif msg == "pull" then
    ns:PullExternal()
  elseif msg == "export" then
    ns:ShowExport()
  elseif msg == "export prices" or msg == "csv" then
    ns:ShowPricesCSV()
  elseif msg == "import" then
    ns:ShowImport()
  elseif msg == "price" or msg:match("^price ") then
    -- /fl price [Linen Cloth] (a shift-clicked link), an item number or an exact name.
    -- Without one, or a name that isn't exact: the window, with the look-up box.
    local arg = msg:match("^price%s+(.+)$")
    local id = arg and ns.ResolveItem and ns:ResolveItem(arg)
    if not id then ns:ShowPriceWindow(nil, nil, arg)
    -- (The text is lower case by now, which breaks a full link's codes: pass just the
    -- "item:..." part, which still has the version.)
    else ns:ShowPriceWindow(id, arg:match("item:[%-%d:]+")) end
  elseif msg:match("^deposit") then
    local id, qty, hours = msg:match("^deposit%s+(%d+)%s*(%d*)%s*(%d*)$")
    -- Or a shift-clicked item link: /fl deposit [Linen Cloth] 1 24.
    if not id and msg:find("item:%d+") then
      id = msg:match("item:(%d+)")
      qty, hours = msg:match("|h|r%s*(%d*)%s*(%d*)%s*$")
    end
    local duration = ({ [2] = 1, [8] = 2, [24] = 3 })[tonumber(hours) or 8]
    if not id or not duration then ns:Print("Use /fl deposit <item ID or shift-clicked item> [quantity] [2/8/24 hours].")
    else ns:DepositReport(tonumber(id), tonumber(qty) or 1, duration) end
  elseif msg == "api" then
    ns:ApiReport()
  elseif msg == "debug" then
    ns.db.settings.debug = not ns.db.settings.debug
    ns:Print("Debug messages " .. (ns.db.settings.debug and "on." or "off."))
  elseif msg == "sellcheck" then
    -- The saved sell speed check lines (Prices.lua), for testing.
    local log = ns.db.sellCheckLog or {}
    if #log == 0 then ns:Print("No sell speed checks yet: they appear after two full scans.") end
    for _, line in ipairs(log) do print("  " .. line) end
  elseif msg:match("^deals") then
    local set = ns.db.settings
    local cmd, arg = msg:match("^deals%s+(%S+)%s*(%S*)")
    local pct = tonumber((arg or ""):match("^(%d+)%%?$"))
    if not cmd then
      ns:ToggleUI("deals")
    elseif cmd == "list" then
      ns:PrintDeals()
    elseif cmd == "sound" then
      set.dealSound = not set.dealSound
      ns:Print("Deal alert sound " .. (set.dealSound and "on." or "off."))
    elseif cmd == "usual" and pct and pct < 100 then
      set.dealUsualPct = pct
      ns:Print("Deals are now listings " .. ns:DealRules() .. ".")
    elseif cmd == "period" and ns.PRICE_WINDOWS[arg] then
      set.dealWindow = arg
      ns:Print("Deals are now listings " .. ns:DealRules() .. ".")
    elseif cmd == "history" and ns.HISTORY_SOURCES[arg] then
      set.dealHistory = arg
      ns:Print("Deals are now listings " .. ns:DealRules() .. ".")
    elseif cmd == "vendor" and arg:match("%%$") and pct and pct < 100 then
      set.dealVendorPct = pct
      ns:Print("Deals are now listings " .. ns:DealRules() .. ".")
    elseif cmd == "vendor" and ns.ParseMoney(arg) then
      set.dealVendorMin = ns.ParseMoney(arg)
      ns:Print("Deals are now listings " .. ns:DealRules() .. ".")
    else
      ns:Print("/fl deals opens the Deals tab, /fl deals list lists them in chat. Deal settings: /fl deals usual 20 (percent below usual price), /fl deals period week/month/3months/6months/year/all, /fl deals history auto/local/tsm (where usual prices come from), /fl deals vendor 10% (percent below vendor price), /fl deals vendor 1s (least profit each), /fl deals sound.")
    end
  elseif msg:match("^pair") or msg == "unpair" then
    ns:SyncCommand(msg:gsub("^pair%s*", "pair "))
  elseif msg:match("^sync") then
    ns:SyncCommand(msg:match("^sync%s*(.*)$"))
  elseif msg == "book" then
    ns:PrintRecipeBook()
  elseif msg == "probe" then
    ns:Probe()
  elseif msg == "frame" then
    -- Which frame is under the mouse, and its parents (for finding the game's windows:
    -- the Sell page in Forever, October 4). Type it with the mouse over the thing.
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local fr = foci and foci[1]
    if not fr then ns:Print("Nothing under the mouse.") end
    local depth = 0
    while fr and depth < 8 do
      local name = fr.GetName and fr:GetName() or nil
      local key = fr.GetParentKey and fr:GetParentKey() or nil
      ns:Print(("%s%s%s (%s, shown %s)"):format(("  "):rep(depth), name or "unnamed", key and (" ." .. key) or "",
        fr.GetObjectType and fr:GetObjectType() or "?", tostring(fr.IsVisible and fr:IsVisible())))
      fr = fr.GetParent and fr:GetParent() or nil
      depth = depth + 1
    end
    local ah = AuctionHouseFrame
    ns:Print(("AuctionHouseFrame %s; ItemSellFrame %s; CommoditiesSellFrame %s"):format(
      ah and (ah:IsVisible() and "shown" or "hidden") or "missing",
      ah and ah.ItemSellFrame and (ah.ItemSellFrame:IsVisible() and "shown" or "hidden") or "missing",
      ah and ah.CommoditiesSellFrame and (ah.CommoditiesSellFrame:IsVisible() and "shown" or "hidden") or "missing"))
  elseif msg == "perf" or msg == "perf reset" then
    ns:PrintPerf(msg == "perf reset")
  elseif msg == "perf detail" then
    ns.perfDetailOn, ns.perfDetail = not ns.perfDetailOn, {}
    print(ns.PREFIX, ns.perfDetailOn
      and "Timing by kind of work is on for this session: /fl perf shows it at the end. /fl perf detail again turns it off."
      or "Timing by kind of work is off.")
  elseif msg == "de" or msg == "de reset" then
    ns:PrintDisenchants(msg == "de reset")
  elseif msg == "disenchant" then
    ns:ToggleDisenchantList()   -- QuickDisenchant.lua
  elseif msg == "trainer" then
    ns:PrintTrainer()
  elseif msg == "fund" then
    ns:FundCommand()
  elseif msg == "session start" then
    ns:StartGeneralSession()
  elseif msg == "session stop" or msg == "session end" then
    ns:StopGeneralSession()
  elseif msg == "session pause" or msg == "session resume" then
    ns:PauseGeneralSession(msg == "session pause")
  elseif msg == "session reset" then
    ns:ResetGeneralSession()
  elseif msg == "session" then
    -- (Sessions were archived November 13 and are back November 15, without the Dashboard's
    -- button: a player asked for them.)
    if ns:GeneralSessionRunning() then ns:Print("A session is running: /fl session pause (or resume), /fl session reset starts it over, /fl session stop ends it.")
    else ns:Print("/fl session start begins a session (or Ctrl-click the minimap button).") end
  elseif msg == "money" then
    ns:PrintMoney()
  elseif msg == "minimap" then
    ns.db.settings.minimap = not ns.db.settings.minimap
    ns:UpdateMinimapButton()
    ns:Print("Minimap button " .. (ns.db.settings.minimap and "shown." or "hidden. Type /fl minimap to bring it back."))
  elseif msg == "tooltip" then
    ns.db.settings.tooltip = not ns.db.settings.tooltip
    ns:Print("Tooltip lines " .. (ns.db.settings.tooltip and "on." or "off."))
  elseif msg:match("^source") then
    local s = msg:match("^source%s+(%S+)")
    local map = { auto = "auto", own = "own", ahledger = "AHledger", auctionator = "Auctionator", tsm = "TSM", auctioneer = "Auctioneer" }
    if s and map[s] then
      ns.db.settings.source = map[s]
      ns:Print("Price source set to " .. map[s] .. ".")
    else
      ns:Print("Use /fl source auto, own, ahledger, auctionator, tsm or auctioneer.")
    end
  elseif msg == "shuffles" or msg == "shuffles all" then
    ns:PrintShuffles(msg == "shuffles all")
  elseif msg:match("^margin") then
    local n = tonumber(msg:match("^margin%s+(%S+)"))
    if n and n >= 0 and n < 100 then
      ns.db.settings.margin = n
      ns:Print(("Safety margin set to %g%%."):format(n))
    else
      ns:Print(("Safety margin is %g%%. Shuffles only count if you can buy at least this much below the item's worth. Change it with /fl margin 10"):format(ns.db.settings.margin or 10))
    end
  elseif msg:match("^seconds") then
    local n = tonumber(msg:match("^seconds%s+(%S+)"))
    if n and n > 0 then
      ns.db.settings.actionSeconds = n
      ns:Print(("Profit per hour now assumes %g seconds per craft, disenchant or split."):format(n))
    else
      ns:Print(("Profit per hour assumes %g seconds per craft, disenchant or split. Change it with /fl seconds 3"):format(ns.db.settings.actionSeconds or 3))
    end
  elseif msg:match("^cut") then
    local n = tonumber(msg:match("^cut%s+(%S+)"))
    if n and n >= 0 and n < 100 then
      ns.db.settings.ahCut = n
      ns:InvalidateValues(true)
      ns:Print(("Auction house cut set to %g%%."):format(n))
    else
      ns:Print(("Auction house cut is %g%%. Change it with /fl cut 5"):format(ns.db.settings.ahCut or 5))
    end
  else
    ns:Print("Commands: /fl (window), /fl scan, /fl scan full, /fl scan materials, /fl stop, /fl watch, /fl quiet, /fl price, /fl queue, /fl lists, /fl pull, /fl export, /fl csv, /fl import, /fl source <auto/own/auctionator>, /fl shuffles, /fl shuffles all, /fl cut <percent>, /fl margin <percent>, /fl seconds <n>, /fl deals, /fl deals settings, /fl minimap, /fl money, /fl session start, /fl session pause, /fl session reset, /fl session stop, /fl de, /fl pair <name>, /fl sync, /fl tooltip, /fl welcome, /fl new, /fl api, /fl debug")
  end
end
