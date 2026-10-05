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

local card, shade

-- Every button closes it (Magic, October 3: "Open shopping lists" opened behind it).
local function close()
  ns.db.settings.welcomeSeen = true
  shade:Hide()   -- (the card is inside it)
end

local function build()
  local body = ns:MainBody()
  if not body then return end
  -- A shade over the whole window under the title bar, tabs and bottom buttons too, so
  -- nothing behind can be clicked until a button is (Magic, October 3). The title bar
  -- stays usable: drag the window, or close it with x.
  local win = body:GetParent()
  shade = CreateFrame("Frame", nil, win)
  shade:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -30)
  shade:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
  shade:SetFrameLevel(body:GetFrameLevel() + 19)
  shade:EnableMouse(true)
  shade:EnableMouseWheel(true)
  shade:SetScript("OnMouseWheel", function() end)
  T:Fill(shade, { 0, 0, 0, 0.55 })
  card = CreateFrame("Frame", nil, shade)
  card:SetAllPoints(body)
  card:SetFrameLevel(body:GetFrameLevel() + 20)
  card:EnableMouse(true)
  -- In the theme, like the newer pages (owner, October 4-5): its background, edge and
  -- frame, a gold title on Default and Gilded, a line under the header, each step in its
  -- own card with its number in a badge, and the buttons in a footer band.
  local FOOT = 52
  T:Fill(card, { T.bg[1], T.bg[2], T.bg[3], 0.98 })
  T:Border(card)
  T:DecorateWindow(card, FOOT)
  if not T.theme.footer then   -- (Clean: just the line above the buttons)
    local t = card:CreateTexture(nil, "BORDER")
    t:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
    t:SetHeight(1)
    t:SetPoint("BOTTOMLEFT", 1, FOOT)
    t:SetPoint("BOTTOMRIGHT", -1, FOOT)
  end
  local W = math.max(body:GetWidth(), 600)
  local function rule(y)
    local t = card:CreateTexture(nil, "BORDER")
    t:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 1, -y)
    t:SetPoint("TOPRIGHT", -1, -y)
  end

  local title = T:Text(card, 16)
  T:StyleTitle(title, 16)
  title:SetPoint("TOPLEFT", 18, -16)
  title:SetText("Welcome to Forever Ledger")
  local sub = T:Text(card, 12, T.dim)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetPoint("RIGHT", card, "RIGHT", -18, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText("It finds gold for you: things to buy and sell on, and what your crafting is worth. Five things to start with:")
  rule(66)

  -- The steps, as cards from the top down; each as tall as its text needs.
  local edge = T.theme.cardEdge and { T.theme.cardEdge[1], T.theme.cardEdge[2], T.theme.cardEdge[3], 0.45 } or { 1, 1, 1, 0.08 }
  local badgeC = T.theme.heading or T.accent
  local y, BTN_W = 76, 150
  for i, s in ipairs(STEPS) do
    local row = CreateFrame("Frame", nil, card)
    row:SetPoint("TOPLEFT", 18, -y)
    row:SetWidth(W - 36)
    T:Fill(row, { 1, 1, 1, 0.025 })
    T:Border(row, edge)

    local badge = row:CreateTexture(nil, "ARTWORK")
    badge:SetSize(24, 24)
    badge:SetPoint("TOPLEFT", 10, -9)
    badge:SetColorTexture(badgeC[1], badgeC[2], badgeC[3], 0.16)
    local num = T:Text(row, 13, badgeC)
    num:SetPoint("CENTER", badge, "CENTER", 0, 0)
    num:SetText(tostring(i))

    local head = T:Text(row, 13)
    head:SetPoint("TOPLEFT", 46, -9)
    head:SetText(s[1])
    local text = T:Text(row, 12, T.dim)
    text:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
    text:SetWidth(W - 36 - 46 - (s[3] and BTN_W + 28 or 14))
    text:SetJustifyH("LEFT")
    text:SetText(s[2])
    local h = math.max(42, 9 + head:GetStringHeight() + 3 + text:GetStringHeight() + 9)
    row:SetHeight(h)
    if s[3] then
      local key = s[4]
      local b = T:Button(row, s[3], BTN_W, function()
        close()
        if key == "lists" then ns:ShowSidePanel("lists") else ns:ShowTab(key) end
      end, 22)
      b:SetPoint("RIGHT", -12, 0)
    end
    y = y + h + 6
  end

  -- The footer: a note, Open Help, and Got it as the main button (Magic, October 3: the
  -- way out stands out).
  local got = T:Button(card, "Got it", 110, close, 26)
  got:SetPoint("BOTTOMRIGHT", -18, 13)
  got:SetPrimary(true)
  local help = T:Button(card, "Open Help", 110, function()
    close()
    ns:ShowTab("help")
  end, 26)
  help:SetPoint("RIGHT", got, "LEFT", -8, 0)
  local note = T:Text(card, 11, T.dim)
  note:SetPoint("LEFT", card, "BOTTOMLEFT", 18, 26)
  note:SetPoint("RIGHT", help, "LEFT", -12, 0)
  note:SetJustifyH("LEFT")
  note:SetText("The Help tab explains every feature, and can show this again.")
end

function ns:ShowWelcome()
  if not card then build() end
  if card then shade:Show(); card:Show() end
end

---------------------------------------------------------------------------
-- What's new: after an update, chat lists the new version's highlights once (not on a
-- first install, which gets the welcome). At each release, copy the changelog's
-- Highlights here and set the version (docs/RELEASING.md). /fl new shows them again.
---------------------------------------------------------------------------
ns.WHATS_NEW = {
  version = "0.14.0",
  lines = {
    "A new look: three themes (FL Clean, FL Default, FL Gilded), your accent colour, and a Size from 75% to 150%. Settings, Appearance.",
    "New Settings: a sidebar, Global settings for every character, and profiles your characters can share.",
    "Dashboard redone: gold, profit, sales and expenses at a glance, the gold graph, your best sales and recent sessions.",
    "Sessions list: every session in the Ledger, with where its gold came from.",
    "Sold while you were away: one chat line when you open the auction house.",
    "Buy queue lights up when there's something to buy; the Disenchant finder picks item levels from a dropdown.",
    "Bag value: bag tooltips show what a slot costs and the cheapest bag right now.",
  },
}

-- What's new as a card over the main window, like the welcome (owner, October 5: a
-- release notes button on Help and the Dashboard). Each line's name (before the colon)
-- over its text.
local news, newsShade
local function buildNews()
  local body = ns:MainBody()
  if not body then return end
  local win = body:GetParent()
  newsShade = CreateFrame("Frame", nil, win)
  newsShade:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -30)
  newsShade:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
  newsShade:SetFrameLevel(body:GetFrameLevel() + 19)
  newsShade:EnableMouse(true)
  newsShade:EnableMouseWheel(true)
  newsShade:SetScript("OnMouseWheel", function() end)
  T:Fill(newsShade, { 0, 0, 0, 0.55 })
  news = CreateFrame("Frame", nil, newsShade)
  news:SetAllPoints(body)
  news:SetFrameLevel(body:GetFrameLevel() + 20)
  news:EnableMouse(true)
  local FOOT = 52
  T:Fill(news, { T.bg[1], T.bg[2], T.bg[3], 0.98 })
  T:Border(news)
  T:DecorateWindow(news, FOOT)
  local function line(y, fromBottom)
    local t = news:CreateTexture(nil, "BORDER")
    t:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
    t:SetHeight(1)
    if fromBottom then
      t:SetPoint("BOTTOMLEFT", 1, y)
      t:SetPoint("BOTTOMRIGHT", -1, y)
    else
      t:SetPoint("TOPLEFT", 1, -y)
      t:SetPoint("TOPRIGHT", -1, -y)
    end
  end
  if not T.theme.footer then line(FOOT, true) end
  local W = math.max(body:GetWidth(), 600)

  local w = ns.WHATS_NEW
  local title = T:Text(news, 16)
  T:StyleTitle(title, 16)
  title:SetPoint("TOPLEFT", 18, -16)
  title:SetText("What's new in " .. w.version)
  local sub = T:Text(news, 12, T.dim)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetPoint("RIGHT", news, "RIGHT", -18, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText("The highlights of this version. Every change is in the changelog on CurseForge and Wago.")
  line(66)

  local accent = T.theme.heading or T.accent
  local y = 80
  for _, l in ipairs(w.lines) do
    local name, text = l:match("^([^:]+):%s*(.+)$")
    if not name then name, text = l, "" end
    local dot = news:CreateTexture(nil, "ARTWORK")
    dot:SetSize(6, 6)
    dot:SetPoint("TOPLEFT", 20, -(y + 5))
    dot:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
    local head = T:Text(news, 13)
    head:SetPoint("TOPLEFT", 36, -y)
    head:SetText(name)
    local fs = T:Text(news, 12, T.dim)
    fs:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
    fs:SetWidth(W - 36 - 24)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    y = y + head:GetStringHeight() + 2 + (text ~= "" and fs:GetStringHeight() or 0) + 12
  end

  local close = T:Button(news, "Close", 110, function() newsShade:Hide() end, 26)
  close:SetPoint("BOTTOMRIGHT", -18, 13)
  close:SetPrimary(true)
  local note = T:Text(news, 11, T.dim)
  note:SetPoint("LEFT", news, "BOTTOMLEFT", 18, 26)
  note:SetPoint("RIGHT", close, "LEFT", -12, 0)
  note:SetJustifyH("LEFT")
  note:SetText("The Help tab explains every feature. /fl new shows this again.")
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
  for _, line in ipairs(w.lines) do print("  - " .. line) end
  print("  The Help tab explains everything; What's new there (or /fl new) shows this again.")
end

ns:OnReady(function()
  local v, s = ns.VERSION, ns.db.settings
  if v == "dev" then return end
  -- Versions before 0.10.0 didn't note the version seen: a saved full scan means it's
  -- an update, not a first install.
  local updated = (s.seenVersion and s.seenVersion ~= v) or (not s.seenVersion and ns.db.lastFullScan ~= nil)
  s.seenVersion = v
  if updated and ns.WHATS_NEW.version == v then
    C_Timer.After(8, function() ns:ShowWhatsNew() end)   -- after the login chat spam
  end
end)
