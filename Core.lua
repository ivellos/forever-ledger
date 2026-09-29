local ADDON, ns = ...
do
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(getMeta, ADDON, "Version")
  -- Release builds replace @project-version@ with the real number; local copies show "dev".
  ns.VERSION = (ok and v and not v:find("@", 1, true)) and v or "dev"
end
ns.PREFIX = "|cffb9a2ffForever Ledger:|r"

local DEFAULTS = {
  schema = 1,
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
  crateFavor = {},  -- [crate name] = { sum, n } Favor paid, learned from turn-ins
  favor = {},       -- [charKey] = Merchant's Favor held
  inventory = {},   -- [charKey] = { bags = { [itemID] = count }, bank = { ... }, t, bankT } (Inventory.lua, not synced)
  itemNames = {},   -- [itemID] = name, remembered so lists don't flicker (Prices.lua ns.ItemName)
  disenchants = {}, -- { t, id, ilvl, q, cls, mats = { [itemID] = count } } (Disenchant.lua, last 1000)
  sync = {},        -- [partner name lowercased] = { sentUpTo = time } (Sync.lua; partner in settings.syncPartner)
  sessions = {},    -- finished sessions: { name, t, stop, spent, earned, runs, goal } (the running one is `session`)
  history = {},       -- [marketKey][itemID] = "day:cheapest:typical|..." (last 30 days)
  historyWeekly = {}, -- [marketKey][itemID] = "week:cheapest:typical:days|..." (2 years)
  historyAll = {},    -- [marketKey][itemID] = "lowest:typicalSum:days"
  settings = { source = "auto", maxAgeHours = 12, tooltip = true, debug = false, watch = {}, ahCut = 5, margin = 10, actionSeconds = 3, skipChars = {}, minimap = true, minimapAngle = 200, dealSound = true,
    dealUsualPct = 20, dealWindow = "all", dealVendorPct = 10, dealVendorMin = 0, dealHistory = "auto", window = {}, ahHighlight = true, dashboard = {}, ledger = {}, deFinder = {}, crates = true, recipes = {}, openFlips = true, customers = true, customerSound = true, customerWindow = true, customerChat = false },
}

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

function ns.ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

function ns.CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
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
end

ns.readyCallbacks = {}
function ns:OnReady(fn) table.insert(ns.readyCallbacks, fn) end

ns:On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  ForeverLedgerDB = ForeverLedgerDB or {}
  copyDefaults(DEFAULTS, ForeverLedgerDB)
  ns.db = ForeverLedgerDB
  for _, fn in ipairs(ns.readyCallbacks) do
    local ok, err = pcall(fn)
    if not ok then geterrorhandler()(err) end
  end
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
    "C_AuctionHouse.SendSearchQuery", "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetCommoditySearchResultInfo",
    "C_AuctionHouse.GetItemSearchResultInfo", "C_MerchantFrame.GetItemInfo", "GetMerchantItemInfo",
    "TooltipDataProcessor.AddTooltipPostCall", "C_Item.GetItemInfo",
    "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "TakeInboxMoney", "AutoLootMailItem", "RepairAllItems",
    "BuyMerchantItem", "GetMerchantItemID", "C_Container.UseContainerItem", "C_Container.GetContainerItemInfo",
    "C_TradeSkillUI.CraftRecipe", "C_TradeSkillUI.OpenTradeSkill", "LOOT_ITEM_CREATED_SELF",
    "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink", "GetLootSourceInfo", "C_Container.GetContainerNumSlots",
    "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceSkillReq", "GetTrainerServiceCost",
    "C_Map.GetBestMapForUnit", "C_Map.SetUserWaypoint",
    "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "ChatFrame_AddMessageEventFilter",
    "C_AuctionHouse.PostItem", "C_AuctionHouse.PostCommodity", "C_AuctionHouse.ConfirmCommoditiesPurchase",
    "Auctionator.API.v1.GetAuctionPriceByItemID", "TSM_API.GetCustomPriceValue", "AucAdvanced.API.GetMarketValue",
  }
  ns:Print("API check (send this to Claude if something isn't working):")
  for _, path in ipairs(checks) do
    print(("  %s %s"):format(has(path) and "|cff7fd39cyes|r" or "|cffee8597no|r ", path))
  end
  print("  Market: " .. ns.MarketKey())
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
  elseif msg == "customers" then
    ns:ShowCustomers()
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
  elseif msg:match("^deals") then
    local set = ns.db.settings
    local cmd, arg = msg:match("^deals%s+(%S+)%s*(%S*)")
    local pct = tonumber((arg or ""):match("^(%d+)%%?$"))
    if not cmd then
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
      ns:Print("Deal settings: /fl deals usual 20 (percent below usual price), /fl deals period week/month/3months/6months/year/all, /fl deals history auto/local/tsm (where usual prices come from), /fl deals vendor 10% (percent below vendor price), /fl deals vendor 1s (least profit each), /fl deals sound.")
    end
  elseif msg:match("^pair") or msg == "unpair" then
    ns:SyncCommand(msg:gsub("^pair%s*", "pair "))
  elseif msg:match("^sync") then
    ns:SyncCommand(msg:match("^sync%s*(.*)$"))
  elseif msg == "book" then
    ns:PrintRecipeBook()
  elseif msg == "probe" then
    ns:Probe()
  elseif msg == "perf" or msg == "perf reset" then
    ns:PrintPerf(msg == "perf reset")
  elseif msg == "de" or msg == "de reset" then
    ns:PrintDisenchants(msg == "de reset")
  elseif msg == "session" then
    ns:OpenWork()
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
    ns:Print("Commands: /fl (window), /fl scan, /fl scan full, /fl scan materials, /fl stop, /fl pull, /fl export, /fl csv, /fl import, /fl source <auto/own/auctionator>, /fl shuffles, /fl shuffles all, /fl cut <percent>, /fl margin <percent>, /fl seconds <n>, /fl deals, /fl deals settings, /fl minimap, /fl money, /fl session, /fl de, /fl pair <name>, /fl sync, /fl tooltip, /fl api, /fl debug")
  end
end
