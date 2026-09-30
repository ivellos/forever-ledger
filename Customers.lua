local _, ns = ...

---------------------------------------------------------------------------
-- Customer finder: watches chat for players asking for something your current
-- character can do ("LF enchanter to enchant wrists", "anyone tailoring bags?",
-- "WTB [item you can craft]", and for Mages "LF water / portal") and tells you, with a
-- clickable name to whisper them. It only reads chat; you do the talking.
---------------------------------------------------------------------------
local THROTTLE = 180        -- seconds before the same player can alert again
local LOG_SIZE = 50

-- Words that name each profession in a request (lowercase, matched on word edges).
local WORDS = {
  Enchanting = { "enchanter", "enchanters", "enchanting", "enchant", "enchants", "ench" },
  Tailoring = { "tailor", "tailors", "tailoring" },
  Alchemy = { "alchemist", "alchemists", "alchemy", "alch" },
  Blacksmithing = { "blacksmith", "blacksmiths", "blacksmithing", "bs" },
  Leatherworking = { "leatherworker", "leatherworkers", "leatherworking", "lw" },
  Engineering = { "engineer", "engineers", "engineering", "engi" },
  Cooking = { "cook", "cooking" },
}
-- Someone looking for help, not offering it.
local ASKING = { "lf", "lfm", "looking for", "need", "needs", "anyone", "any", "wtb", "can someone", "who can",
  "somebody", "someone" }
-- Crafters advertising: skip these.
-- ("anyone need water?" is a Mage selling, not asking: seen in beta trade chat.)
local OFFERING = { "lfw", "wts", "selling", "can make", "can craft", "offering", "my services", "have all",
  "anyone need", "anybody need", "who needs", "does anyone need", "need any",
  -- Crafters spelling it out ("[Enchanting] LF Work - come buy your BIS weapon enchant").
  "lf work", "looking for work", "lf job", "lf jobs", "come buy", "for hire", "your mats", "tips appreciated" }
local lastAlert = {}

-- Class services (owner, September 30): Mage food and water, Mage portals, Warlock
-- summons, Rogue lockpicking. Each needs its spell (Classic IDs), or the level it's
-- learned at in case Forever's spell IDs differ.
local function knows(spellID)
  if IsPlayerSpell then local ok, r = pcall(IsPlayerSpell, spellID); if ok and r then return true end end
  if IsSpellKnown then local ok, r = pcall(IsSpellKnown, spellID); if ok and r then return true end end
end
-- Portal spells: city names for the ad, per spell.
local PORTALS = {
  { 10059, "Stormwind" }, { 11416, "Ironforge" }, { 11419, "Darnassus" },
  { 11417, "Orgrimmar" }, { 11418, "Undercity" }, { 11420, "Thunder Bluff" },
}
local SERVICES = {
  -- setting: the Settings switch (Customers section) that turns the service off.
  { key = "mage", class = "MAGE", label = "Mage food and water", level = 1, setting = "svcFood",
    words = { "water", "food", "mage table", "mage water", "mage food" } },
  { key = "portal", class = "MAGE", label = "Mage portal", level = 40, setting = "svcPortal", spells = { 10059, 11416, 11419, 11417, 11418, 11420 },
    words = { "portal", "portals", "port", "port to", "mage port" } },
  { key = "summon", class = "WARLOCK", label = "Warlock summon", level = 20, setting = "svcSummon", spells = { 698 },
    -- Not "warlock" on its own: "LF warlock" is usually a group looking for dps.
    words = { "summon", "summons", "summoning", "summ", "sumon", "lock summon", "warlock summon" } },
  { key = "lockpick", class = "ROGUE", label = "Lockpicking", level = 16, setting = "svcLockpick", spells = { 1804 },
    words = { "lockpick", "lockpicker", "lockpicking", "lock pick", "pick lock", "lockbox", "lockboxes", "lock box",
      "open box", "open a box", "open my box", "junkbox" } },
}
ns.CLASS_SERVICES = SERVICES

-- The class services this character can offer now.
local function myServices()
  local _, class = UnitClass("player")
  local level = UnitLevel and UnitLevel("player") or 0
  local out = {}
  for _, sv in ipairs(SERVICES) do
    if sv.class == class and ns.db.settings[sv.setting] ~= false then
      local ok = level >= sv.level
      for _, id in ipairs(sv.spells or {}) do if knows(id) then ok = true end end
      if ok then out[#out + 1] = sv end
    end
  end
  return out
end

-- Portal cities this Mage knows, for the ad ("Stormwind, Ironforge"). If none of the
-- Classic spell IDs are known (Forever may differ), the faction's cities.
local function portalCities()
  local list = {}
  for _, p in ipairs(PORTALS) do if knows(p[1]) then list[#list + 1] = p[2] end end
  if #list == 0 then
    list = UnitFactionGroup("player") == "Horde" and { "Orgrimmar", "Undercity", "Thunder Bluff" }
      or { "Stormwind", "Ironforge", "Darnassus" }
  end
  return table.concat(list, ", ")
end

-- True if `text` contains `word` as a whole word (or phrase).
local function has(text, word)
  return (" " .. text .. " "):find("[^%w]" .. word:gsub("(%W)", "%%%1") .. "[^%w]") ~= nil
end
local function any(text, list)
  for _, w in ipairs(list) do if has(text, w) then return w end end
end

-- What the current character can offer: professions, and items its recipes make.
local function offers()
  local c = ns.db.chars[ns.CharKey()]
  local profs, items = {}, {}
  for prof, p in pairs(c and c.profs or {}) do
    profs[prof] = true
    for _, rec in pairs(p.recipes or {}) do
      if rec.out then items[rec.out] = prof end
    end
  end
  return profs, items
end

-- Returns what the message asks for (e.g. "Enchanting", "Mage services") or nil.
local function wanted(msg)
  local text = msg:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  if any(text, OFFERING) then return end
  local profs, items = offers()
  -- "WTB [Item]" for something you can craft.
  if ns.db.settings.svcCrafting ~= false and (has(text, "wtb") or any(text, ASKING)) then
    for id in msg:gmatch("item:(%d+)") do
      local prof = items[tonumber(id)]
      if prof then return prof .. ": " .. (ns.ItemName(tonumber(id)) or "an item you craft") end
    end
  end
  if not any(text, ASKING) then return end
  for prof in pairs(ns.db.settings.svcCrafting ~= false and profs or {}) do
    if WORDS[prof] and any(text, WORDS[prof]) then return prof end
  end
  for _, sv in ipairs(myServices()) do
    if any(text, sv.words) then return sv.label end
  end
end

local function onChat(msg, sender, channel)
  local s = ns.db and ns.db.settings
  if not (s and s.customers) or not msg or not sender then return end
  local me = GetUnitName and GetUnitName("player", true)
  if sender == me or sender == UnitName("player") then return end
  local what = wanted(msg)
  if not what then return end
  if lastAlert[sender] and GetTime() - lastAlert[sender] < THROTTLE then return end
  lastAlert[sender] = GetTime()
  local where = channel and channel ~= "" and channel:match("^(%S+)") or "chat"
  if s.customerChat then
    ns:Print(("Customer? |Hplayer:%s|h[%s]|h (%s, %s): %s"):format(sender, sender, where, what, msg))
  end
  if s.customerSound and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
  local log = ns.db.customers or {}
  ns.db.customers = log
  -- Asking again (Roh Riding posted every few minutes): move the open request to the top
  -- with the newest message instead of listing it twice.
  for i = #log, 1, -1 do
    local e = log[i]
    if e.who == sender and e.what == what and not e.done and time() - e.t < 3600 then
      table.remove(log, i)
      break
    end
  end
  log[#log + 1] = { t = time(), who = sender, what = what, msg = msg, where = where, c = ns.CharKey() }
  while #log > LOG_SIZE do table.remove(log, 1) end
  if s.customerWindow then ns:ShowCustomers(true) end
end

---------------------------------------------------------------------------
-- Ads: one click posts a line to Trade (or Trade (Services) if you're not in Trade). {professions} becomes your
-- profession links (saved when you open each profession window, since the game only
-- gives a link while it's open). Right-click a button to change its text.
---------------------------------------------------------------------------
local AD_COOLDOWN = 60      -- seconds between posts, so the button can't spam
local DEFAULT_ADS = {
  crafting = "{professions} looking for work, your mats or mine. Whisper me!",
  mage = "WTS Mage water and food {water} {food}. Whisper me!",
  portal = "WTS portals to {portals}. Whisper me!",
  summon = "Warlock summons available, whisper me where you are and who's coming!",
  lockpick = "Rogue lockpicking: bring your lockboxes, tips welcome. Whisper me!",
}
-- The ad button for each service.
local AD_BUTTONS = {
  mage = { "Sell food and water", 140 }, portal = { "Sell portals", 100 },
  summon = { "Offer summons", 120 }, lockpick = { "Offer lockpicking", 140 },
}
-- Conjure Water / Conjure Food ranks (Classic spell IDs) and the item each makes, lowest
-- first. The ad links the best one this Mage knows.
local CONJURED = {
  water = { { 5504, 5350 }, { 5505, 2288 }, { 5506, 2136 }, { 6127, 3772 }, { 10138, 8077 }, { 10139, 8078 }, { 10140, 8079 } },
  food = { { 587, 5349 }, { 597, 1113 }, { 990, 1114 }, { 6129, 1487 }, { 10144, 8075 }, { 10145, 8076 }, { 28612, 22895 } },
}
-- Link to the best conjured item of a kind this character knows, or nil.
local function bestConjured(kind)
  for i = #CONJURED[kind], 1, -1 do
    local spell, item = CONJURED[kind][i][1], CONJURED[kind][i][2]
    if knows(spell) then
      local _, link = ns.GetItemInfo(item)
      if not link and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
      return link or ("[" .. (ns.ItemName(item) or "Conjured " .. kind) .. "]")
    end
  end
end
-- Load the item links early, so they're ready when the button is clicked.
ns:On("PLAYER_ENTERING_WORLD", function()
  local _, class = UnitClass("player")
  if class ~= "MAGE" then return end
  C_Timer.After(5, function() bestConjured("water"); bestConjured("food") end)
end)
local GATHERING = { Herbalism = true, Mining = true, Skinning = true, Fishing = true, Cooking = true, ["First Aid"] = true }
local lastAd = {}           -- per ad kind, so crafting and food ads have their own wait

ns:On("TRADE_SKILL_SHOW", function()
  C_Timer.After(1, function()
    local TS = C_TradeSkillUI
    if not (TS and TS.GetTradeSkillListLink and TS.GetBaseProfessionInfo) then return end
    local okLink, link = pcall(TS.GetTradeSkillListLink)
    local okInfo, info = pcall(TS.GetBaseProfessionInfo)
    local name = okInfo and info and info.professionName
    if okLink and link and name then
      local links = ns.db.profLinks or {}
      ns.db.profLinks = links
      links[ns.CharKey()] = links[ns.CharKey()] or {}
      links[ns.CharKey()][name] = link
    end
  end)
end)

local function adText(kind)
  local text = (ns.db.settings.ads or {})[kind] or DEFAULT_ADS[kind]
  if text:find("{professions}", 1, true) then
    local c = ns.db.chars[ns.CharKey()]
    local saved = (ns.db.profLinks or {})[ns.CharKey()] or {}
    local parts = {}
    for prof in pairs(c and c.profs or {}) do
      if not GATHERING[prof] then parts[#parts + 1] = saved[prof] or ("[" .. prof .. "]") end
    end
    table.sort(parts)
    text = text:gsub("{professions}", (table.concat(parts, " "):gsub("%%", "%%%%")))
  end
  if text:find("{portals}", 1, true) then
    text = text:gsub("{portals}", (portalCities():gsub("%%", "%%%%")))
  end
  for _, kind in ipairs({ "water", "food" }) do
    if text:find("{" .. kind .. "}", 1, true) then
      text = text:gsub("{" .. kind .. "}", ((bestConjured(kind) or ""):gsub("%%", "%%%%")))
    end
  end
  return (text:gsub("%s%s+", " "))
end

-- The main Trade channel (where most players look; owner's choice after testing), or
-- Trade (Services) if you're not in Trade: its channel number.
local function adChannel()
  local services
  for i = 1, (GetNumDisplayChannels and GetNumDisplayChannels() or 0) do
    local name, header, _, number = GetChannelDisplayInfo(i)
    if not header and name and number then
      if name:find("Services", 1, true) then services = services or { number, name }
      elseif name:find("^Trade") and not name:find("Local", 1, true) then return number, name end
    end
  end
  if services then return services[1], services[2] end
end

function ns:PostAd(kind)
  local wait = AD_COOLDOWN - (GetTime() - (lastAd[kind] or 0))
  if wait > 0 then ns:Print(("Wait %d seconds before posting again."):format(math.ceil(wait))); return end
  local number, name = adChannel()
  if not number then ns:Print("You're not in the Trade or Services channel. Join it in a city first."); return end
  local text = adText(kind)
  if #text > 255 then ns:Print("That ad is too long for chat (255 letters). Right-click the button to shorten it."); return end
  SendChatMessage(text, "CHANNEL", nil, number)
  lastAd[kind] = GetTime()
  ns:Debug("Posted to", name, ":", text)
end

StaticPopupDialogs["FOREVER_LEDGER_EDIT_AD"] = {
  text = "Ad text. {professions} becomes your profession links; {water} and {food} your best conjured water and food; {portals} the cities you can portal to.",
  button1 = SAVE or "Save", button2 = CANCEL or "Cancel", button3 = "Default",
  hasEditBox = true, editBoxWidth = 350, maxLetters = 255,
  OnShow = function(self, kind)
    local box = self.editBox or self.EditBox
    box:SetText((ns.db.settings.ads or {})[kind] or DEFAULT_ADS[kind])
  end,
  OnAccept = function(self, kind)
    local box = self.editBox or self.EditBox
    ns.db.settings.ads = ns.db.settings.ads or {}
    ns.db.settings.ads[kind] = box:GetText()
  end,
  OnAlt = function(_, kind)
    if ns.db.settings.ads then ns.db.settings.ads[kind] = nil end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

---------------------------------------------------------------------------
-- The Customers window: requests newest first, with Whisper, Invite and dismiss.
-- Opens by itself on a new request (Settings), without taking the keyboard.
---------------------------------------------------------------------------
local win
local ROW = 40
local rows = {}

local function ago(t)
  local d = time() - t
  if d < 60 then return "now" end
  if d < 3600 then return math.floor(d / 60) .. "m" end
  return math.floor(d / 3600) .. "h"
end

---------------------------------------------------------------------------
-- Work log: every completed trade that looks like a job (you enchanted something in
-- the "will not be traded" slot, were paid, or traded with someone who asked in chat):
-- who, what, and the money. A matching request in the list is marked done.
---------------------------------------------------------------------------
local WORK_LOG = 500
local trade

local function tradeName()
  local first, last = UnitName("NPC")
  return (first and last and last ~= "" and (first .. " " .. last)) or first
    or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())
end

-- Everything on both sides of the trade window right now.
local function readTrade()
  local t = { give = {}, get = {} }
  for i = 1, 6 do
    if GetTradePlayerItemInfo then
      local name, _, qty = GetTradePlayerItemInfo(i)
      if name then t.give[#t.give + 1] = { name = name, qty = qty or 1, link = GetTradePlayerItemLink and GetTradePlayerItemLink(i) } end
    end
    if GetTradeTargetItemInfo then
      local name, _, qty = GetTradeTargetItemInfo(i)
      if name then t.get[#t.get + 1] = { name = name, qty = qty or 1, link = GetTradeTargetItemLink and GetTradeTargetItemLink(i) } end
    end
  end
  -- Slot 7 on their side holds the item you enchant; the last value is the enchant.
  if GetTradeTargetItemInfo then
    local name, _, _, _, _, enchant = GetTradeTargetItemInfo(7)
    t.enchantItem, t.enchant = name, enchant
  end
  t.gave = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
  t.got = GetTargetTradeMoney and GetTargetTradeMoney() or 0
  t.who = tradeName()
  return t
end

local function snapshot() trade = readTrade() end
ns:On("TRADE_SHOW", snapshot)
ns:On("TRADE_PLAYER_ITEM_CHANGED", snapshot)
ns:On("TRADE_TARGET_ITEM_CHANGED", snapshot)
ns:On("TRADE_MONEY_CHANGED", snapshot)
ns:On("TRADE_ACCEPT_UPDATE", snapshot)

local refresh
ns:On("UI_INFO_MESSAGE", function(_, msg)
  if msg ~= ERR_TRADE_COMPLETE or not trade then return end
  local t = trade
  trade = nil
  -- A request from this player in the last two hours makes it a job too.
  local request
  for i = #(ns.db.customers or {}), 1, -1 do
    local e = ns.db.customers[i]
    if e.who == t.who and time() - e.t < 7200 then request = e; break end
  end
  if not (t.enchant or t.got > 0 or request) then return end
  local entry = { t = time(), c = ns.CharKey(), who = t.who, got = t.got, gave = t.gave,
    enchant = t.enchant, enchantItem = t.enchantItem, give = t.give, get = t.get, what = request and request.what }
  local log = ns.db.workLog or {}
  ns.db.workLog = log
  log[#log + 1] = entry
  while #log > WORK_LOG do table.remove(log, 1) end
  if request then request.done, request.paid = true, t.got end
  local what = t.enchant or (#t.give > 0 and t.give[1].name) or entry.what or "trade"
  ns:Print(("Work log: %s for %s%s."):format(what, t.who or "?", t.got > 0 and (", paid " .. ns.Money(t.got)) or ""))
  if refresh then refresh() end
end)

-- Totals for the footer: money received minus money given, and jobs.
local function workTotals(since)
  local net, jobs = 0, 0
  for _, e in ipairs(ns.db.workLog or {}) do
    if e.t >= since then net, jobs = net + (e.got or 0) - (e.gave or 0), jobs + 1 end
  end
  return net, jobs
end

local workRows = {}
local function refreshWork()
  local T = ns.Theme
  local list, log = {}, ns.db.workLog or {}
  for i = #log, math.max(1, #log - 99), -1 do list[#list + 1] = log[i] end
  local width = win.content:GetWidth()
  for i, e in ipairs(list) do
    local r = workRows[i]
    if not r then
      r = CreateFrame("Frame", nil, win.content)
      r:SetHeight(ROW)
      r.stripe = T:Fill(r, { 1, 1, 1, 0.03 })
      r.head = T:Text(r, 12)
      r.head:SetPoint("TOPLEFT", 8, -5)
      r.head:SetJustifyH("LEFT")
      r.money = T:Text(r, 12)
      r.money:SetPoint("TOPRIGHT", -8, -5)
      r.money:SetJustifyH("RIGHT")
      r.detail = T:Text(r, 11, T.dim)
      r.detail:SetPoint("TOPLEFT", 8, -21)
      r.detail:SetJustifyH("LEFT")
      r.detail:SetWordWrap(false)
      workRows[i] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * ROW)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    local what = e.enchant and ("Enchanted " .. (e.enchantItem or "an item") .. ": " .. e.enchant)
      or (#(e.give or {}) > 0 and ("Gave " .. e.give[1].qty .. " " .. e.give[1].name .. (#e.give > 1 and (" and " .. (#e.give - 1) .. " more") or "")))
      or e.what or "Trade"
    r.head:SetText(("%s  |cff888888%s|r"):format(e.who or "?", date("%b %d %H:%M", e.t)))
    local net = (e.got or 0) - (e.gave or 0)
    r.money:SetText(net > 0 and ("|cff7fd39c+" .. ns.Money(net) .. "|r") or net < 0 and ("|cffee8597-" .. ns.Money(-net) .. "|r") or "|cff888888no gold|r")
    r.detail:SetWidth(width - 16)
    r.detail:SetText(what)
    r:Show()
  end
  for i = #list + 1, #workRows do workRows[i]:Hide() end
  for _, r in ipairs(rows) do r:Hide() end
  win.empty:SetShown(#list == 0)
  win.empty:SetText("No jobs yet. Trades where you enchant something, get paid, or trade with someone from Requests are logged here.")
  win.content:SetHeight(math.max(#list * ROW, 20))
  local now, d = time(), date("*t")
  local today, tj = workTotals(time({ year = d.year, month = d.month, day = d.day, hour = 0 }))
  local week, wj = workTotals(now - 7 * 86400)
  win.foot:SetText(("Today: %s from %d jobs.   Last 7 days: %s from %d jobs."):format(ns.Money(today), tj, ns.Money(week), wj))
  if win.sf.UpdateScrollBar then win.sf.UpdateScrollBar() end
end

refresh = function()
  if not (win and win:IsShown()) then return end
  if win.mode == "work" then return refreshWork() end
  for _, r in ipairs(workRows) do r:Hide() end
  win.empty:SetText("No requests in the last hour. They appear here as soon as someone asks for what you do.")
  win.foot:SetText("Hover for the full message. x hides a request. Settings: Customer finder.")
  local T = ns.Theme
  local list = {}
  local log = ns.db.customers or {}
  for i = #log, 1, -1 do
    local e = log[i]
    if not e.done and time() - e.t < 3600 then list[#list + 1] = e end
  end
  local width = win.content:GetWidth()
  for i, e in ipairs(list) do
    local r = rows[i]
    if not r then
      r = CreateFrame("Frame", nil, win.content)
      r:SetHeight(ROW)
      r:EnableMouse(true)
      r.stripe = T:Fill(r, { 1, 1, 1, 0.03 })
      r.head = T:Text(r, 12)
      r.head:SetPoint("TOPLEFT", 8, -5)
      r.head:SetJustifyH("LEFT")
      r.msg = T:Text(r, 11, T.dim)
      r.msg:SetPoint("TOPLEFT", 8, -21)
      r.msg:SetJustifyH("LEFT")
      r.msg:SetWordWrap(false)
      r.done = T:Button(r, "x", 22, function(self) self:GetParent().entry.done = true; refresh() end, 20)
      r.done:SetPoint("RIGHT", -6, 0)
      r.invite = T:Button(r, "Invite", 54, function(self)
        local who = self:GetParent().entry.who
        if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(who) elseif InviteUnit then InviteUnit(who) end
      end, 20)
      r.invite:SetPoint("RIGHT", r.done, "LEFT", -4, 0)
      r.whisper = T:Button(r, "Whisper", 64, function(self)
        local who = self:GetParent().entry.who
        if ChatFrame_SendTell then ChatFrame_SendTell(who) end
      end, 20)
      r.whisper:SetPoint("RIGHT", r.invite, "LEFT", -4, 0)
      -- Hover for the whole message.
      r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(self.entry.who, 1, 1, 1)
        GameTooltip:AddLine(self.entry.msg, 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      rows[i] = r
    end
    r.entry = e
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * ROW)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    r.head:SetText(("%s  %s%s|r  |cff888888%s, %s|r"):format(e.who, T:AccentCode(), e.what, e.where or "chat", ago(e.t)))
    r.msg:SetWidth(width - 170)
    r.msg:SetText(e.msg)
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  win.empty:SetShown(#list == 0)
  win.content:SetHeight(math.max(#list * ROW, 20))
  if win.sf.UpdateScrollBar then win.sf.UpdateScrollBar() end
end

-- quiet: opened by a new request (don't raise it over what you're doing if already open).
function ns:ShowCustomers(quiet)
  local T = ns.Theme
  if not win then
    win = ns.ThemedWindow("ForeverLedgerCustomers", 620, 330, T:AccentCode() .. "Customers|r")
    win:ClearAllPoints()
    win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -160)
    -- Ad buttons: left-click posts, right-click edits the text.
    local function adButton(kind, label, width)
      local b = T:Button(win, label, width, nil, 24)
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then StaticPopup_Show("FOREVER_LEDGER_EDIT_AD", nil, nil, kind)
        else ns:PostAd(kind) end
      end)
      b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(label, 1, 1, 1)
        GameTooltip:AddLine(adText(kind), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Click to post it in Trade. Right-click to change the text.", T.accent[1], T.accent[2], T.accent[3], true)
        GameTooltip:Show()
      end)
      b:HookScript("OnLeave", function() GameTooltip:Hide() end)
      return b
    end
    -- Ad buttons: crafting, then one per class service this character has and hasn't
    -- turned off in Settings. Laid out again each time the window opens.
    win.ads = { crafting = adButton("crafting", "Advertise crafting", 140) }
    for key, b in pairs(AD_BUTTONS) do win.ads[key] = adButton(key, b[1], b[2]) end
    function win:LayoutAds()
      for _, b in pairs(self.ads) do b:Hide(); b:ClearAllPoints() end
      local shown = {}
      if ns.db.settings.svcCrafting ~= false then shown[1] = self.ads.crafting end
      for _, sv in ipairs(myServices()) do shown[#shown + 1] = self.ads[sv.key] end
      for i, b in ipairs(shown) do
        if i == 1 then b:SetPoint("TOPLEFT", 10, -38) else b:SetPoint("LEFT", shown[i - 1], "RIGHT", 6, 0) end
        b:Show()
      end
    end

    -- Requests (people asking now) or Work done (the work log).
    win.mode = "requests"
    win.modeChoice = T:Choice(win, { { value = "requests", label = "Requests" }, { value = "work", label = "Work done" } },
      function(v) win.mode = v; refresh() end)
    win.modeChoice:SetPoint("TOPRIGHT", -10, -39)
    win.modeChoice:SetValue("requests")

    win.sf, win.content = T:Scroll(win)
    win.sf:SetPoint("TOPLEFT", 8, -70)
    win.sf:SetPoint("BOTTOMRIGHT", -8, 30)
    win.empty = T:Text(win.content, 12, T.dim)
    win.empty:SetPoint("TOPLEFT", 8, -8)
    win.empty:SetPoint("RIGHT", win.content, "RIGHT", -8, 0)   -- wrap instead of running off the edge
    win.empty:SetJustifyH("LEFT")
    win.empty:SetText("No requests in the last hour. They appear here as soon as someone asks for what you do.")
    win.foot = T:Text(win, 11, T.dim)
    win.foot:SetPoint("BOTTOMLEFT", 10, 10)
    win.foot:SetText("Hover for the full message. x hides a request. Settings: Customer finder.")
    win:SetScript("OnShow", function(self) self:Raise(); self:LayoutAds(); refresh() end)
    win:LayoutAds()
    C_Timer.NewTicker(30, refresh)   -- keep the "3m" ages current (does nothing while hidden)
  end
  if quiet and win:IsShown() then refresh(); return end
  -- A new request opens it on Requests.
  if quiet then win.mode = "requests"; win.modeChoice:SetValue("requests") end
  win:Show()
  refresh()
end

-- /fl work: open straight on Work done.
function ns:ShowWorkLog()
  ns:ShowCustomers()
  win.mode = "work"
  win.modeChoice:SetValue("work")
  refresh()
end

-- The 9th value is the channel's plain name ("Trade", "Services").
ns:On("CHAT_MSG_CHANNEL", function(msg, sender, _, channelName, _, _, _, _, baseName)
  onChat(msg, sender, baseName or channelName)
end)
ns:On("CHAT_MSG_SAY", function(msg, sender) onChat(msg, sender, "Say") end)
ns:On("CHAT_MSG_YELL", function(msg, sender) onChat(msg, sender, "Yell") end)

-- Settings changed: lay the ad buttons out again if the window is open.
function ns:UpdateCustomerAds()
  if win and win:IsShown() then win:LayoutAds() end
end

-- For testing: /fl customer <message> runs a message through the finder.
function ns:TestCustomer(msg)
  local what = wanted(msg or "")
  ns:Print(what and ("That would alert: " .. what) or "That wouldn't alert (not a request for something this character does).")
end
