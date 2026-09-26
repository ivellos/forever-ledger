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
  settings = { source = "auto", maxAgeHours = 12, tooltip = true, debug = false, watch = {}, ahCut = 5 },
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

function ns.ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

function ns.CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Forever is realmless: the "realm" is the ruleset, and each ruleset + faction is one auction house.
function ns.MarketKey()
  return (GetRealmName() or "?") .. "|" .. (UnitFactionGroup("player") or "?")
end

-- Placeholders; UI.lua replaces these.
function ns:RefreshUI() end
function ns:UpdateScanStatus() end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
function ns:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then handlers[event].unknown = true end
  end
  table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then geterrorhandler()(err) end
  end
end)

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
  local db, nChars, nPrices = ns.db, 0, 0
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
    if not mine or (rec.t or 0) > (mine.t or 0) then db.vendorBuy[id] = rec end
  end
  for id, v in pairs(data.vendorSell or {}) do
    if db.vendorSell[id] == nil then db.vendorSell[id] = v end
  end
  if ns.BuildUsageIndex then ns:BuildUsageIndex() end
  return true, ("Imported %d characters and %d prices."):format(nChars, nPrices)
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
    ns.Scan:Start("watch")
  elseif msg == "scan full" then
    ns.Scan:Start("full")
  elseif msg == "stop" then
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
  elseif msg:match("^cut") then
    local n = tonumber(msg:match("^cut%s+(%S+)"))
    if n and n >= 0 and n < 100 then
      ns.db.settings.ahCut = n
      ns:Print(("Auction house cut set to %g%%."):format(n))
    else
      ns:Print(("Auction house cut is %g%%. Change it with /fl cut 5"):format(ns.db.settings.ahCut or 5))
    end
  else
    ns:Print("Commands: /fl (window), /fl scan, /fl scan full, /fl stop, /fl pull, /fl export, /fl csv, /fl import, /fl source <auto|own|auctionator>, /fl cut <percent>, /fl tooltip, /fl api, /fl debug")
  end
end
