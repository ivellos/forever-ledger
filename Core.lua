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
  schema = 4,
  chars = {},       -- [charKey] = { name, realm, class, level, faction, updated, profs = { [profName] = { rank, max, updated, recipes = {...} } } }
  prices = {},      -- [marketKey][itemID] = { m = cheapest, a = avg of cheapest 20, q = listed, t = time, src = "scan" }
  vendorSell = {},  -- [itemID] = copper the vendor pays you
  vendorBuy = {},   -- [itemID] = { p = copper you pay, t = time, src, lim = limited supply }
  gold = {},        -- [charKey][hour] = copper (History.lua)
  money = {},       -- [charKey][day][source] = copper in or out
  sales = {},       -- auction house sales: { t, c = charKey, n = item name, a = copper received, cut }
  purchases = {},   -- auction house purchases: { t, c, id, q, a }
  vendorLog = {},   -- vendor buys and sells: { t, c, id, q, a, s = "buy" | "sell" }
  recipeBook = {},  -- [profession][recipeID] = { n, out, oq, r } every recipe, learned or not (RecipeBook.lua)
  recipeSources = {}, -- [recipe name lowercased][kind..npc] = { kind, conf = "seen", npc, npcID, mapID, x, y, zone, cost, currency, skill, limited, t }
  vendors = {},     -- [npcID] = { name, mapID, x, y, zone, t, trainer }
  recipeTypes = {}, -- [recipeID] = "shuffle" | "sells" | "notsale" | "loss", the player's own choice (RecipesTab.lua)
  crates = {},      -- [crate itemID] = { name, level, bundles = { { { qty, name }, ... } } } read from tooltips
  vendorSellChanged = {}, -- [itemID] = local day its vendor sell price was seen to change (older price history is ignored)
  favor = {},       -- [charKey] = Merchant's Favor held
  inventory = {},   -- [charKey] = { bags = { [itemID] = count }, bank = { ... }, t, bankT } (Inventory.lua, not synced)
  itemNames = {},   -- [itemID] = name, remembered so lists don't flicker (Prices.lua ns.ItemName)
  disenchants = {}, -- { t, id, ilvl, q, cls, mats = { [itemID] = count } } (Disenchant.lua, last 1000)
  sync = {},        -- [partner name lowercased] = { sentUpTo = time } (Sync.lua; partner in settings.syncPartner)
  sessions = {},    -- finished sessions: { name, t, stop, spent, earned, runs, goal } (the running one is `session`)
  history = {},       -- [marketKey][itemID] = "day:cheapest:typical|..." (last 30 days)
  historyWeekly = {}, -- [marketKey][itemID] = "week:cheapest:typical:days|..." (2 years)
  historyAll = {},    -- [marketKey][itemID] = "lowest:typicalSum:days"
  suffixNames = {},   -- [version name, "of the Whale"] = the bonus ID full scans saw for it (Prices.lua)
  -- soldSnap = { t, market, items = { [itemID] = "price:count" } }: the last full scan's counts (Prices.lua), no default
  historyQty = {},    -- [marketKey][itemID] = "day:listed|..." most listed seen each day (last 30 days)
  dungeons = {},      -- [dungeon name] = { runs, secs, coin, drops = { [itemID] = runs it dropped in } } (Dungeons.lua)
  ledgerMonths = {},  -- ledger entries older than 30 days, as monthly totals per item: { { t = month start, c, k = "sale" | "buy" | "vsell" | "vbuy", id or n, q, a, cnt, mx } } (History.lua, kept a year)
  historySold2 = {},  -- [marketKey][itemID] = "day:bought:minutes:minutes|..." units that vanished though they couldn't have expired (sell speed, since October 2)
  profiles = {},     -- settings profiles: [name] = { [setting] = value } (Settings.lua; "Default" is settings itself)
  charProfile = {},  -- [charKey] = profile name; none = Default
  shopping = { lists = {} }, -- shopping lists: { lists = { { name, on, items = { { id, max, qty } } } }, current } (ShoppingLists.lua)
  settings = { source = "auto", maxAgeHours = 12, tooltip = true, debug = false, watch = {}, ahCut = 5, margin = 10, actionSeconds = 3, skipChars = {}, minimap = true, minimapAngle = 200, dealSound = true, dealScreen = true, sellGuard = true, watchResume = true, sessionValue = "best", saleSound = true, deRolls = true, keepGold = 0, undercutAlerts = true, undercutSound = true, updateNotice = true, priceHelper = true, soldSummary = true,
    dealUsualPct = 20, dealWindow = "all", dealVendorPct = 10, dealVendorMin = 0, dealHistory = "auto", dealUsualMin = 1000, dealShowThin = false, dealsSort = {}, window = {}, ahHighlight = true, dashboard = {}, ledger = {}, deFinder = {}, crates = true, recipes = {}, openFlips = true, customers = true, customerSound = true, customerWindow = true, customerChat = false,
    svcCrafting = true, svcFood = true, svcPortal = true, svcSummon = true, svcLockpick = true,
    -- Buy queue (BuyQueue.lua): what goes in it, scroll anywhere to buy, the side panel's tab.
    -- wheel starts off so nobody buys by accident (owner, October 2).
    buyQueue = { flips = true, disenchant = true, deals = false, lists = true, wheel = false, tab = "queue" },
    tipMode = "full", tipOptions = 3, tipPrice = true, tipSpeed = true, tipQuest = true, tipQuestMine = true, tipDrops = true, tipHistory = true, tipWorth = true, tipBuy = true, tipDisenchant = true, tipUsedBy = true, tipCrate = true, tipBagSlot = true },
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

function ns.Money(copper)
  if not copper then return "?" end
  copper = math.floor(copper + 0.5)
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
  return table.concat(out, " ")
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

function ns.CharKey()
  local realm = GetRealmName() or "?"
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

-- Is a saved character on the same ruleset (realm name) and faction as the one you're
-- playing: one who could mail you items or craft for you (owner, October 3: other
-- rulesets' characters counted in Have, recipes and values). True when either side
-- isn't known yet (old saved data, or the very start of a login).
function ns:SameMarketChar(key)
  local c = ns.db and ns.db.chars[key]
  if not c then return true end
  local realm, faction = GetRealmName and GetRealmName(), UnitFactionGroup and UnitFactionGroup("player")
  if c.realm and realm and c.realm ~= realm then return false end
  if c.faction and faction and c.faction ~= faction then return false end
  return true
end

-- Forever is realmless: the "realm" is the ruleset, and each ruleset + faction is one auction house.
-- While a neutral (goblin) auction house is open, its prices are kept apart, since in
-- Classic it's a separate market shared with the other faction, with a 15% cut.
function ns.MarketKey()
  return (GetRealmName() or "?") .. "|" .. (ns.neutralAH and "Neutral" or UnitFactionGroup("player") or "?")
end

-- The auctioneer has no faction and stands in a town with a neutral auction house:
-- Classic's goblin towns, and Forever's trade posts by the Waylaid Crate turn-ins
-- (Three Corners in Redridge; Durotar Supply and Logistics just west of the Crossroads
-- in the Barrens, subzone name unknown, so the whole zone counts).
local NEUTRAL_TOWNS = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true, ["Three Corners"] = true }
local NEUTRAL_ZONES = { ["Redridge Mountains"] = true, ["The Barrens"] = true }
function ns.IsNeutralAuctioneer()
  if not UnitExists("npc") or UnitFactionGroup("npc") then return false end
  return NEUTRAL_TOWNS[GetSubZoneText() or ""] or NEUTRAL_TOWNS[GetMinimapZoneText and GetMinimapZoneText() or ""]
    or NEUTRAL_ZONES[GetZoneText() or ""] or false
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
local clock = debugprofilestop or function() return GetTime() * 1000 end
local function note(label, ms)
  local p = ns.perf[label]
  if not p then p = { n = 0, ms = 0, max = 0 }; ns.perf[label] = p end
  p.n, p.ms = p.n + 1, p.ms + ms
  if ms > p.max then p.max = ms end
end

ns.PerfNote = note

-- Wrap a function so its time is counted under a label.
function ns.Timed(label, fn)
  return function(...)
    local t = clock()
    local a, b, c, d = fn(...)
    note(label, clock() - t)
    return a, b, c, d
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  local t = clock()
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then geterrorhandler()(err) end
  end
  note(event, clock() - t)
end)

function ns:PrintPerf(reset)
  if reset then ns.perf, ns.perfSince = {}, GetTime(); ns:Print("Timing reset. Play for a minute, then /fl perf."); return end
  local rows = {}
  for label, p in pairs(ns.perf) do rows[#rows + 1] = { label = label, p = p } end
  table.sort(rows, function(a, b) return a.p.max > b.p.max end)
  ns:Print(("Time used by Forever Ledger over the last %d seconds, slowest single moment first:"):format(GetTime() - ns.perfSince))
  for i = 1, math.min(12, #rows) do
    local r = rows[i]
    print(("  %s: slowest %.0f ms, %d times, %.0f ms total"):format(r.label, r.p.max, r.p.n, r.p.ms))
  end
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
  local function measure(t, depth)
    local n, bytes = 0, 0
    for k, v in pairs(t) do
      n = n + 1
      if type(k) == "string" then bytes = bytes + #k end
      if type(v) == "string" then bytes = bytes + #v
      elseif type(v) == "table" and depth > 0 then
        local n2, b2 = measure(v, depth - 1)
        bytes = bytes + b2 + n2 * 16
      else bytes = bytes + 8 end
    end
    return n, bytes
  end
  local parts = {}
  for key, v in pairs(ns.db or {}) do
    if type(v) == "table" then
      local n, bytes = measure(v, 4)
      parts[#parts + 1] = { key = key, n = n, kb = bytes / 1024 }
    end
  end
  table.sort(parts, function(a, b) return a.kb > b.kb end)
  local out = {}
  for i = 1, math.min(6, #parts) do out[i] = ("%s %.0f KB"):format(parts[i].key, parts[i].kb) end
  print("  Biggest saved data (rough): " .. table.concat(out, ", "))
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
  -- Settings per character (below): while a character used its own, the shared settings
  -- were also kept under settingsAccount. If the game ever saved the stand-in instead of
  -- the real table, this brings them back.
  if type(ForeverLedgerDB.settingsAccount) == "table" then
    ForeverLedgerDB.settings = ForeverLedgerDB.settingsAccount
    ForeverLedgerDB.settingsAccount = nil
  end
  copyDefaults(DEFAULTS, ForeverLedgerDB)
  ns.db = ForeverLedgerDB
  ns:ApplyCharSettings()
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

-- Merge characters, prices and vendor prices from another account (Import and live
-- sync). Newer data wins. Returns how many characters, prices and vendor prices changed.
function ns:MergeData(data)
  local db, nChars, nPrices, nVendor = ns.db, 0, 0, 0
  for key, c in pairs(data.chars or {}) do
    local mine = db.chars[key]
    if not mine or (c.updated or 0) > (mine.updated or 0) then db.chars[key] = c; nChars = nChars + 1 end
  end
  for market, items in pairs(data.prices or {}) do
    db.prices[market] = db.prices[market] or {}
    for id, rec in pairs(items) do
      local mine = db.prices[market][id]
      if not mine or (rec.t or 0) > (mine.t or 0) then db.prices[market][id] = rec; nPrices = nPrices + 1 end
    end
  end
  for id, rec in pairs(data.vendorBuy or {}) do
    local mine = db.vendorBuy[id]
    if not mine or (rec.t or 0) > (mine.t or 0) then db.vendorBuy[id] = rec; nVendor = nVendor + 1 end
  end
  for id, v in pairs(data.vendorSell or {}) do
    if db.vendorSell[id] == nil then db.vendorSell[id] = v; nVendor = nVendor + 1 end
  end
  if nChars > 0 and ns.BuildUsageIndex then ns:BuildUsageIndex() end
  if (nPrices > 0 or nVendor > 0) and ns.InvalidateValues then ns:InvalidateValues() end
  return nChars, nPrices, nVendor
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
    "C_TradeSkillUI.GetRecipeNumReagents", "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetTradeSkillLine",
    "GetProfessions", "GetNumSkillLines",
    "C_AuctionHouse.SendSearchQuery", "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetReplicateItemTimeLeft","C_AuctionHouse.GetCommoditySearchResultInfo",
    "C_AuctionHouse.GetItemSearchResultInfo", "C_MerchantFrame.GetItemInfo", "GetMerchantItemInfo",
    "TooltipDataProcessor.AddTooltipPostCall", "C_Item.GetItemInfo",
    "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItem", "GetInboxNumItems",
    -- Your auctions (Auctions.lua).
    "C_AuctionHouse.QueryOwnedAuctions", "C_AuctionHouse.GetNumOwnedAuctions", "C_AuctionHouse.GetOwnedAuctionInfo",
    "C_AuctionHouse.CancelAuction", "TakeInboxMoney", "AutoLootMailItem", "RepairAllItems",
    "BuyMerchantItem", "GetMerchantItemID", "C_Container.UseContainerItem", "C_Container.GetContainerItemInfo",
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
    "C_AuctionHouse.GetItemCommodityStatus", "SetOverrideBindingClick",
    "Auctionator.API.v1.GetAuctionPriceByItemID", "TSM_API.GetCustomPriceValue", "AucAdvanced.API.GetMarketValue",
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
  }
  ns:Print("API check (send this to Claude if something isn't working):")
  for _, path in ipairs(checks) do
    print(("  %s %s"):format(has(path) and "|cff7fd39cyes|r" or "|cffee8597no|r ", path))
  end
  print("  Market: " .. ns.MarketKey())
  print(("  %s GLOBAL_MOUSE_DOWN event (Buy queue panel comes to the front)"):format(
    ns:EventKnown("GLOBAL_MOUSE_DOWN") and "|cff7fd39cyes|r" or "|cffee8597no|r "))
  -- Which ruleset the character is on (owner, October 3: group characters by ruleset,
  -- not by server name, if the game says it). Each is tried safely and printed.
  local function try(label, fn)
    local ok, a, b = pcall(fn)
    print(("  %s: %s"):format(label, ok and (tostring(a) .. (b ~= nil and (", " .. tostring(b)) or "")) or "not available"))
  end
  try("Realm", function() return GetRealmName(), GetNormalizedRealmName and GetNormalizedRealmName() end)
  try("Realm ID", function() return GetRealmID and GetRealmID() end)
  try("Season", function() return C_Seasons and C_Seasons.GetActiveSeason and C_Seasons.GetActiveSeason() end)
  try("Hardcore", function() return C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() end)
  try("PvP server", function() return C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired(), IsPVPTimerRunning and IsPVPTimerRunning() end)
  try("Server type", function() return GetCVar and GetCVar("realmName"), GetCVar and GetCVar("portal") end)
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
  elseif msg == "queue" or msg == "buy" then
    ns:ShowSidePanel("queue")
  elseif msg == "lists" or msg == "list" then
    ns:ShowSidePanel("lists")
  elseif msg == "new" or msg == "whatsnew" then
    if ns.ShowWhatsNew then ns:ShowWhatsNew() end
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
  elseif msg == "de" or msg == "de reset" then
    ns:PrintDisenchants(msg == "de reset")
  elseif msg == "runs" or msg == "dungeons" then
    ns:PrintRuns()
  elseif msg == "session start" then
    ns:StartGeneralSession()
  elseif msg == "session stop" or msg == "session end" then
    ns:StopGeneralSession()
  elseif msg == "session" then
    -- (It opened the Work it window, removed October 4.)
    if ns:GeneralSessionRunning() then ns:Print("A session is running: /fl session stop ends it.")
    else ns:Print("/fl session start begins a session (or Start a session on the Dashboard).") end
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
    local map = { auto = "auto", own = "own", auctionator = "Auctionator", tsm = "TSM", auctioneer = "Auctioneer" }
    if s and map[s] then
      ns.db.settings.source = map[s]
      ns:Print("Price source set to " .. map[s] .. ".")
    else
      ns:Print("Use /fl source auto, own, auctionator, tsm or auctioneer.")
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
    ns:Print("Commands: /fl (window), /fl scan, /fl scan full, /fl scan materials, /fl stop, /fl queue, /fl lists, /fl pull, /fl export, /fl csv, /fl import, /fl source <auto/own/auctionator>, /fl shuffles, /fl shuffles all, /fl cut <percent>, /fl margin <percent>, /fl seconds <n>, /fl deals, /fl deals settings, /fl minimap, /fl money, /fl session start, /fl session stop, /fl runs, /fl de, /fl pair <name>, /fl sync, /fl tooltip, /fl welcome, /fl new, /fl api, /fl debug")
  end
end
