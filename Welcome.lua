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
  T:Fill(card, { 0.06, 0.06, 0.07, 0.97 })
  T:Border(card)

  local title = T:Text(card, 16, T.accent)
  title:SetPoint("TOPLEFT", 18, -16)
  title:SetText("Welcome to Forever Ledger")
  local sub = T:Text(card, 12, T.dim)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetPoint("RIGHT", card, "RIGHT", -18, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText("It finds gold for you: things to buy and sell on, and what your crafting is worth. Five things to start with:")

  local prev = sub
  for i, s in ipairs(STEPS) do
    local num = T:Text(card, 15, T.accent)
    num:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12)
    num:SetWidth(22)
    num:SetJustifyH("LEFT")
    num:SetText(tostring(i))
    local head = T:Text(card, 13)
    head:SetPoint("TOPLEFT", num, "TOPRIGHT", 4, 0)
    head:SetText(s[1])
    local text = T:Text(card, 12, T.dim)
    text:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
    text:SetPoint("RIGHT", card, "RIGHT", s[3] and -170 or -18, 0)
    text:SetJustifyH("LEFT")
    text:SetText(s[2])
    if s[3] then
      local key = s[4]
      local b = T:Button(card, s[3], 140, function()
        close()
        if key == "lists" then ns:ShowSidePanel("lists") else ns:ShowTab(key) end
      end, 22)
      -- Right of the step's text (which stops 170 short of the edge), level with its heading.
      b:SetPoint("TOPLEFT", text, "TOPRIGHT", 12, 8)   -- a little below the heading (owner, October 3)
    end
    -- The next step goes under this one's text (left edge from the number).
    local anchor = CreateFrame("Frame", nil, card)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOP", text, "BOTTOM")
    anchor:SetPoint("LEFT", num, "LEFT")
    prev = anchor
  end

  local got = T:Button(card, "Got it", 110, close, 26)
  got:SetPoint("BOTTOMRIGHT", -18, 16)
  -- The main way out stands out (Magic, October 3), in the addon's accent colour like a
  -- chosen tab, rather than teal, which means "scroll here" on the Buy queue.
  got:SetSelected(true)
  got:HookScript("OnLeave", function(self) self:SetSelected(true) end)
  local help = T:Button(card, "Open Help", 110, function()
    close()
    ns:ShowTab("help")
  end, 26)
  help:SetPoint("RIGHT", got, "LEFT", -8, 0)
  local note = T:Text(card, 11, T.dim)
  note:SetPoint("LEFT", card, "BOTTOMLEFT", 18, 29)
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
  version = "0.11.0",
  lines = {
    "Shopping lists, simpler: one kind of list with Search all and what you own; tick one box to buy from it.",
    "Buy queue, clearer: Vendor flips and Shopping lists views, a glow where to scroll, profit you can afford.",
    "Spend at most: cap what the Buy queue spends each visit, or always keep some gold back.",
    "Ledger: every transaction in one list (All); select rows to see their total.",
    "Sessions and dungeon runs: a small tracker for gold an hour, and your runs and drops counted.",
    "Price history: hold Ctrl over an item for its recent range, trend and lowest price.",
    "Search Settings and Help: type a word to find any setting or help entry.",
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
