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
local OFFERING = { "lfw", "wts", "selling", "can make", "can craft", "offering", "my services", "have all" }
-- Mage services, for Mages.
local MAGE = { "water", "portal", "port", "food", "mage table" }

local lastAlert = {}

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
  if has(text, "wtb") or any(text, ASKING) then
    for id in msg:gmatch("item:(%d+)") do
      local prof = items[tonumber(id)]
      if prof then return prof .. ": " .. (ns.ItemName(tonumber(id)) or "an item you craft") end
    end
  end
  if not any(text, ASKING) then return end
  for prof in pairs(profs) do
    if WORDS[prof] and any(text, WORDS[prof]) then return prof end
  end
  local _, class = UnitClass("player")
  if class == "MAGE" and any(text, MAGE) then return "Mage services" end
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
  log[#log + 1] = { t = time(), who = sender, what = what, msg = msg, where = where, c = ns.CharKey() }
  while #log > LOG_SIZE do table.remove(log, 1) end
  if s.customerWindow then ns:ShowCustomers(true) end
end

---------------------------------------------------------------------------
-- Ads: one click posts a line to Trade (Services), or Trade. {professions} becomes your
-- profession links (saved when you open each profession window, since the game only
-- gives a link while it's open). Right-click a button to change its text.
---------------------------------------------------------------------------
local AD_COOLDOWN = 60      -- seconds between posts, so the button can't spam
local DEFAULT_ADS = {
  crafting = "{professions} looking for work, your mats or mine. Whisper me!",
  mage = "Selling Mage water and food. Whisper me!",
}
local GATHERING = { Herbalism = true, Mining = true, Skinning = true, Fishing = true, Cooking = true, ["First Aid"] = true }
local lastAd = 0

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
  return text
end

-- Trade (Services) if you've joined it, otherwise Trade: its channel number.
local function adChannel()
  local found
  for i = 1, (GetNumDisplayChannels and GetNumDisplayChannels() or 0) do
    local name, header, _, number = GetChannelDisplayInfo(i)
    if not header and name and number then
      if name:find("Services", 1, true) then return number, name end
      if not found and name:find("^Trade") and not name:find("Local", 1, true) then found = { number, name } end
    end
  end
  if found then return found[1], found[2] end
end

function ns:PostAd(kind)
  local wait = AD_COOLDOWN - (GetTime() - lastAd)
  if wait > 0 then ns:Print(("Wait %d seconds before posting again."):format(math.ceil(wait))); return end
  local number, name = adChannel()
  if not number then ns:Print("You're not in the Trade or Services channel. Join it in a city first."); return end
  local text = adText(kind)
  if #text > 255 then ns:Print("That ad is too long for chat (255 letters). Right-click the button to shorten it."); return end
  SendChatMessage(text, "CHANNEL", nil, number)
  lastAd = GetTime()
  ns:Debug("Posted to", name, ":", text)
end

StaticPopupDialogs["FOREVER_LEDGER_EDIT_AD"] = {
  text = "Ad text. {professions} becomes your profession links.",
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

local function refresh()
  if not (win and win:IsShown()) then return end
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
    win = ns.ThemedWindow("ForeverLedgerCustomers", 520, 330, T:AccentCode() .. "Customers|r")
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
        GameTooltip:AddLine("Click to post it in Trade (Services). Right-click to change the text.", T.accent[1], T.accent[2], T.accent[3], true)
        GameTooltip:Show()
      end)
      b:HookScript("OnLeave", function() GameTooltip:Hide() end)
      return b
    end
    local ad = adButton("crafting", "Advertise my crafting", 170)
    ad:SetPoint("TOPLEFT", 10, -38)
    local _, class = UnitClass("player")
    if class == "MAGE" then
      local mage = adButton("mage", "Sell food and water", 150)
      mage:SetPoint("LEFT", ad, "RIGHT", 6, 0)
    end

    win.sf, win.content = T:Scroll(win)
    win.sf:SetPoint("TOPLEFT", 8, -70)
    win.sf:SetPoint("BOTTOMRIGHT", -8, 30)
    win.empty = T:Text(win.content, 12, T.dim)
    win.empty:SetPoint("TOPLEFT", 8, -8)
    win.empty:SetText("No requests in the last hour. They appear here as soon as someone asks for what you do.")
    win.foot = T:Text(win, 11, T.dim)
    win.foot:SetPoint("BOTTOMLEFT", 10, 10)
    win.foot:SetText("Hover for the full message. x hides a request. Settings: Customer finder.")
    win:SetScript("OnShow", function(self) self:Raise(); refresh() end)
    C_Timer.NewTicker(30, refresh)   -- keep the "3m" ages current (does nothing while hidden)
  end
  if quiet and win:IsShown() then refresh(); return end
  win:Show()
  refresh()
end

-- The 9th value is the channel's plain name ("Trade", "Services").
ns:On("CHAT_MSG_CHANNEL", function(msg, sender, _, channelName, _, _, _, _, baseName)
  onChat(msg, sender, baseName or channelName)
end)
ns:On("CHAT_MSG_SAY", function(msg, sender) onChat(msg, sender, "Say") end)
ns:On("CHAT_MSG_YELL", function(msg, sender) onChat(msg, sender, "Yell") end)

-- For testing: /fl customer <message> runs a message through the finder.
function ns:TestCustomer(msg)
  local what = wanted(msg or "")
  ns:Print(what and ("That would alert: " .. what) or "That wouldn't alert (not a request for something this character does).")
end
