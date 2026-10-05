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
  version = "0.13.0",
  lines = {
    "Characters tab: every character's bags and bank, with what it's all worth and the best way to turn it into gold.",
    "Per realm and faction: pick which characters to look at at the top of the list; only those count.",
    "Price helper: the usual price and the cheapest now on the Sell tab, with Undercut and Usual buttons.",
    "One Export / import button: Export, Import and Prices as text in one window.",
    "Easier money boxes: type 1.5 for one and a half gold.",
    "Fixes: undercut reminders once per login, steadier Your auctions, a tidier session tracker.",
  },
}

function ns:ShowWhatsNew()
  local w = ns.WHATS_NEW
  ns:Print(("What's new in %s:"):format(w.version))
  for _, line in ipairs(w.lines) do print("  - " .. line) end
  print("  The Help tab explains everything; /fl new shows this again.")
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
