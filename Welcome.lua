local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Welcome: a short card over the main window the first time it opens, with the five
-- things to do first and a button for each that can be done from here. "Got it" puts
-- it away; the Help tab (or /fl welcome) shows it again. From the first UI pass
-- (Magic, October 3: a new player didn't know what Check did or where to scroll).
---------------------------------------------------------------------------
local STEPS = {
  { "Learn your recipes", "Open each profession window once on every character. Forever Ledger reads your recipes from it." },
  { "Price everything", "At the auction house, click Full scan. It reads every listing in a few seconds; the game allows one about every 15 minutes. Prices and flips work from the first scan; deals and sell speed get sharper as a few days of scans build up." },
  { "Buy vendor flips", "At the auction house, click Buy queue: a panel beside it lists things selling for less than a vendor pays, with Watch flips to keep scanning while you're there. Click Buy to buy the next one, or tick Scroll to buy and scroll down over its top strip." },
  { "Find deals", "The Deals tab lists items selling well below their usual price, to buy and resell.", "Open Deals", "deals" },
  { "Plan your shopping", "Shopping lists hold what you want to buy and the most you'd pay. Plan anywhere; they show beside the auction house when you get there.", "Open shopping lists", "lists" },
}

---------------------------------------------------------------------------
-- The cards over the main window (the welcome and What's new), in the theme like the
-- newer pages (owner, October 4-5): its background, edge and frame, a gold title on
-- Default and Gilded, a line under the header, each item in its own card with a badge,
-- and the buttons in a footer band.
---------------------------------------------------------------------------
local FOOT = 52

-- A shade over the whole window under the title bar, tabs and bottom buttons too, so
-- nothing behind can be clicked until a button is (Magic, October 3). The title bar
-- stays usable: drag the window, or close it with x. Returns the shade, the card and
-- its width.
local function overlay(body)
  local win = body:GetParent()
  local shade = CreateFrame("Frame", nil, win)
  shade:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -30)
  shade:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
  shade:SetFrameLevel(body:GetFrameLevel() + 19)
  shade:EnableMouse(true)
  shade:EnableMouseWheel(true)
  shade:SetScript("OnMouseWheel", function() end)
  T:Fill(shade, { 0, 0, 0, 0.55 })
  local c = CreateFrame("Frame", nil, shade)
  c:SetAllPoints(body)
  c:SetFrameLevel(body:GetFrameLevel() + 20)
  c:EnableMouse(true)
  T:Fill(c, { T.bg[1], T.bg[2], T.bg[3], 0.98 })
  T:Border(c)
  T:DecorateWindow(c, FOOT)
  if not T.theme.footer then   -- (Clean: just the line above the buttons)
    local t = c:CreateTexture(nil, "BORDER")
    t:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
    t:SetHeight(1)
    t:SetPoint("BOTTOMLEFT", 1, FOOT)
    t:SetPoint("BOTTOMRIGHT", -1, FOOT)
  end
  return shade, c, math.max(body:GetWidth(), 600)
end

-- The title, a line under it, and a line across. Returns where the items start.
local function header(c, titleText, subText)
  local title = T:Text(c, 16)
  T:StyleTitle(title, 16)
  title:SetPoint("TOPLEFT", 18, -16)
  title:SetText(titleText)
  local sub = T:Text(c, 12, T.dim)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetPoint("RIGHT", c, "RIGHT", -18, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText(subText)
  local t = c:CreateTexture(nil, "BORDER")
  t:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
  t:SetHeight(1)
  t:SetPoint("TOPLEFT", 1, -66)
  t:SetPoint("TOPRIGHT", -1, -66)
  return 76
end

-- One item as a card at y: a badge (its number, or a mark), its name, its text, and a
-- button on the right if given ({ label, onClick }). compact: less padding (seven of
-- What's new have to fit). Returns the card's height.
local BTN_W = 150
local function itemCard(c, y, W, badgeText, name, text, button, compact)
  local pad = compact and 6 or 9
  local edge = T.theme.cardEdge and { T.theme.cardEdge[1], T.theme.cardEdge[2], T.theme.cardEdge[3], 0.45 } or { 1, 1, 1, 0.08 }
  local badgeC = T.theme.heading or T.accent
  local row = CreateFrame("Frame", nil, c)
  row:SetPoint("TOPLEFT", 18, -y)
  row:SetWidth(W - 36)
  T:Fill(row, { 1, 1, 1, 0.025 })
  T:Border(row, edge)
  local badge = row:CreateTexture(nil, "ARTWORK")
  badge:SetSize(24, 24)
  badge:SetPoint("TOPLEFT", 10, -pad)
  badge:SetColorTexture(badgeC[1], badgeC[2], badgeC[3], 0.16)
  local mark = T:Text(row, 13, badgeC)
  mark:SetPoint("CENTER", badge, "CENTER", 0, 0)
  mark:SetText(badgeText)
  local head = T:Text(row, 13)
  head:SetPoint("TOPLEFT", 46, -pad)
  head:SetText(name)
  local fs = T:Text(row, 12, T.dim)
  fs:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, compact and -2 or -3)
  fs:SetWidth(W - 36 - 46 - (button and BTN_W + 28 or 14))
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  local h = math.max(pad * 2 + 24, pad + head:GetStringHeight() + ((text or "") ~= "" and (compact and 2 or 3) + fs:GetStringHeight() or 0) + pad)
  row:SetHeight(h)
  if button then
    local b = T:Button(row, button[1], BTN_W, button[2], 22)
    b:SetPoint("RIGHT", -12, 0)
  end
  return h
end

-- The footer: a note on the left, the buttons on the right (the last is the main one:
-- the way out stands out, Magic, October 3). buttons = { { label, onClick }, ... }.
local function footer(c, noteText, buttons)
  local right
  for i = #buttons, 1, -1 do
    local b = T:Button(c, buttons[i][1], 110, buttons[i][2], 26)
    if right then b:SetPoint("RIGHT", right, "LEFT", -8, 0) else b:SetPoint("BOTTOMRIGHT", -18, 13) end
    if i == #buttons then b:SetPrimary(true) end
    right = b
  end
  local note = T:Text(c, 11, T.dim)
  note:SetPoint("LEFT", c, "BOTTOMLEFT", 18, 26)
  note:SetPoint("RIGHT", right, "LEFT", -12, 0)
  note:SetJustifyH("LEFT")
  note:SetText(noteText)
end

local card, shade

-- Every button closes it (Magic, October 3: "Open shopping lists" opened behind it).
local function close()
  ns.db.settings.welcomeSeen = true
  shade:Hide()   -- (the card is inside it)
end

local function build()
  local body = ns:MainBody()
  if not body then return end
  local W
  shade, card, W = overlay(body)
  local y = header(card, "Welcome to Forever Ledger",
    "It finds gold for you: things to buy and sell on, and what your crafting is worth. Five things to start with:")
  for i, s in ipairs(STEPS) do
    local key = s[4]
    local button = s[3] and { s[3], function()
      close()
      if key == "lists" then ns:ShowSidePanel("lists") else ns:ShowTab(key) end
    end }
    y = y + itemCard(card, y, W, tostring(i), s[1], s[2], button) + 6
  end
  footer(card, "The Help tab explains every feature, and can show this again.", {
    { "Open Help", function() close(); ns:ShowTab("help") end },
    { "Got it", close },
  })
end

function ns:ShowWelcome()
  if not card then build() end
  if card then shade:Show(); card:Show() end
end

---------------------------------------------------------------------------
-- What's new: after an update, chat lists the new version's highlights once (not on a
-- first install, which gets the welcome). At each release, copy the changelog's
-- Highlights here and set the version (docs/RELEASING.md). /fl new and the What's new
-- button show them as a card.
-- Each line is "Name: text", marked by its kind after the usual software convention
-- (owner, October 5): { ..., major = true } a big change (a bold delta, its own card);
-- a plain line something new (a plus); { ..., change = true } a change (a pencil);
-- { ..., fix = true } a fix (a wrench). The small ones share one card.
---------------------------------------------------------------------------
ns.WHATS_NEW = {
  version = "0.15.0",
  lines = {
    { "Training advice: beside your class trainer, what to learn now as Must have, Nice to have or Skip while leveling, following your talents and the spells you actually cast.", major = true },
    { "Booty Bay prices: the neutral auction house kept as its own market, its 15% cut in the math, and a Deals view of what sells for more there or is cheaper to buy there.", major = true },
    { "Shopping lists from shuffles and the Disenchant finder: add them in one click; each Up to says where it came from (the shuffle, your usual price plus an allowance, or you).", major = true },
    "Riding fund: on the Dashboard, how close you are to riding at 40 and epic riding at 60, mount included.",
    "Characters in Settings: remove ones you've deleted; live sync can share bags and bank between your accounts.",
    { "Buy queue: the corner shows your profit if you sold what you bought to a vendor.", change = true },
    { "Fixes: Booty Bay's 15% cut, its own Auctions list, long Up to amounts, dropdowns cut off at the edge.", fix = true },
  },
}

-- The kinds: icon (media/icons, drawn by tools/make-icons.ps1), colour, what a hover says.
local KINDS = {
  major = { "change-major", nil, "A big change" },
  new = { "change-new", { 0.5, 0.83, 0.61 }, "New" },
  change = { "change-edit", { 0.95, 0.75, 0.35 }, "Changed" },
  fix = { "change-fix", { 0.6, 0.7, 0.85 }, "Fixed" },
}
local function kindOf(l)
  if type(l) ~= "table" then return "new" end
  return (l.major and "major") or (l.change and "change") or (l.fix and "fix") or "new"
end

local function lineText(l) return type(l) == "table" and l[1] or l end
local function split(l)
  local s = lineText(l)
  local name, text = s:match("^([^:]+):%s*(.+)$")
  if not name then return s, "" end
  return name, text
end

-- A kind's icon at size, with its meaning on hover.
local function kindIcon(parent, kind, size)
  local k = KINDS[kind]
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  local tex = f:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\AddOns\\ForeverLedger\\media\\icons\\" .. k[1])
  local c = k[2] or T.theme.heading or T.accent
  tex:SetVertexColor(c[1], c[2], c[3], 1)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(k[3], 1, 1, 1)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

local function cardFrame(c, y, W, tint)
  local edge = T.theme.cardEdge and { T.theme.cardEdge[1], T.theme.cardEdge[2], T.theme.cardEdge[3], 0.45 } or { 1, 1, 1, 0.08 }
  local row = CreateFrame("Frame", nil, c)
  row:SetPoint("TOPLEFT", 18, -y)
  row:SetWidth(W - 36)
  T:Fill(row, { 1, 1, 1, tint })
  T:Border(row, edge)
  return row
end

-- A big change: its own card with the delta, the name a little bigger.
local function majorCard(c, y, W, l)
  local name, text = split(l)
  local row = cardFrame(c, y, W, 0.03)
  kindIcon(row, "major", 26):SetPoint("TOPLEFT", 12, -10)
  local head = T:Text(row, 14)
  head:SetPoint("TOPLEFT", 52, -8)
  head:SetText(name)
  local fs = T:Text(row, 12, T.dim)
  fs:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
  fs:SetWidth(W - 36 - 52 - 14)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  local h = math.max(48, 8 + head:GetStringHeight() + 3 + fs:GetStringHeight() + 9)
  row:SetHeight(h)
  return h
end

-- The smaller ones together in one card under a small heading: each with its kind's
-- icon, the name in white and its text after it.
local function groupCard(c, y, W, title, list)
  local row = cardFrame(c, y, W, 0.025)
  local head = T:Text(row, 11)
  T:StyleHeading(head, title)
  head:SetPoint("TOPLEFT", 12, -9)
  local top = 9 + head:GetStringHeight() + 7
  for _, l in ipairs(list) do
    local name, text = split(l)
    kindIcon(row, kindOf(l), 14):SetPoint("TOPLEFT", 12, -(top + 1))
    local fs = T:Text(row, 12, T.dim)
    fs:SetPoint("TOPLEFT", 34, -top)
    fs:SetWidth(W - 36 - 34 - 14)
    fs:SetJustifyH("LEFT")
    fs:SetText(text ~= "" and ("|cffffffff" .. name .. "|r  " .. text) or name)
    top = top + fs:GetStringHeight() + 6
  end
  local h = top + 3
  row:SetHeight(h)
  return h
end

-- What's new as a card over the main window, like the welcome (owner, October 5: a
-- release notes button on Help and the Dashboard, then the same look as the welcome).
local news, newsShade
local function buildNews()
  local body = ns:MainBody()
  if not body then return end
  local W
  newsShade, news, W = overlay(body)
  local w = ns.WHATS_NEW
  local y = header(news, "What's new in " .. w.version,
    "The highlights of this version. Every change is in the changelog on CurseForge and Wago.")
  -- Big changes first, then the rest: new, changed, fixed.
  local rest = { new = {}, change = {}, fix = {} }
  for _, l in ipairs(w.lines) do
    local kind = kindOf(l)
    if kind == "major" then y = y + majorCard(news, y, W, l) + 6
    else table.insert(rest[kind], l) end
  end
  local small = {}
  for _, kind in ipairs({ "new", "change", "fix" }) do
    for _, l in ipairs(rest[kind]) do small[#small + 1] = l end
  end
  if #small > 0 then y = y + groupCard(news, y, W, "Also in this version", small) + 6 end
  footer(news, "The Help tab explains every feature. /fl new shows this again.", {
    { "Open Help", function() newsShade:Hide(); ns:ShowTab("help") end },
    { "Close", function() newsShade:Hide() end },
  })
end

function ns:ShowWhatsNewCard()
  local body = ns:MainBody()
  if not (body and body:GetParent():IsShown()) then ns:ToggleUI("dashboard") end
  if not news then buildNews() end
  if not news then return ns:ShowWhatsNew() end   -- (no window: chat instead)
  newsShade:Show()
end

function ns:ShowWhatsNew()
  local w = ns.WHATS_NEW
  ns:Print(("What's new in %s:"):format(w.version))
  for _, line in ipairs(w.lines) do print("  - " .. lineText(line)) end
  print("  The Help tab explains everything; What's new there (or /fl new) shows this again.")
end

ns:OnReady(function()
  local v, s = ns.VERSION, ns.db.settings
  -- A fresh install (nothing saved yet, welcome never seen): the window opens with the
  -- welcome a few seconds after the first login, then never by itself again (owner,
  -- October 6). Closing the welcome marks it seen.
  if not s.welcomeSeen and not s.welcomeAutoShown and ns.db.lastFullScan == nil and not s.seenVersion and C_Timer then
    C_Timer.After(4, function()
      if s.welcomeSeen or (InCombatLockdown and InCombatLockdown()) then return end
      s.welcomeAutoShown = true   -- once only, even if the window is closed without the welcome
      ns:ToggleUI()
    end)
  end
  if v == "dev" then return end
  -- Versions before 0.10.0 didn't note the version seen: a saved full scan means it's
  -- an update, not a first install.
  local updated = (s.seenVersion and s.seenVersion ~= v) or (not s.seenVersion and ns.db.lastFullScan ~= nil)
  s.seenVersion = v
  if updated and ns.WHATS_NEW.version == v then
    C_Timer.After(8, function() ns:ShowWhatsNew() end)   -- after the login chat spam
  end
end)
