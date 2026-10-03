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
  { "Price everything", "At the auction house, click Full scan below the auction house window. It reads every listing in a few seconds; the game allows one about every 15 minutes." },
  { "Buy vendor flips", "At the auction house, click Buy queue: a panel beside it lists things selling for less than a vendor pays. Click Buy to buy the next one, or tick Scroll to buy and scroll down over its top strip. Watch flips keeps scanning while you stand there." },
  { "Find deals", "The Deals tab lists items selling well below their usual price, to buy and resell.", "Open Deals", "deals" },
  { "Plan your shopping", "Shopping lists hold what you want to buy and the most you'd pay. Plan anywhere; they show beside the auction house when you get there.", "Open shopping lists", "lists" },
}

local card

local function build()
  local body = ns:MainBody()
  if not body then return end
  card = CreateFrame("Frame", nil, body)
  card:SetAllPoints()
  card:SetFrameLevel(body:GetFrameLevel() + 20)
  card:EnableMouse(true)   -- the tab underneath can't be clicked through it
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
        if key == "lists" then ns:ShowSidePanel("lists"); return end
        ns.db.settings.welcomeSeen = true
        card:Hide()
        ns:ShowTab(key)
      end, 22)
      -- Right of the step's text (which stops 170 short of the edge), level with its heading.
      b:SetPoint("TOPLEFT", text, "TOPRIGHT", 12, 18)
    end
    -- The next step goes under this one's text (left edge from the number).
    local anchor = CreateFrame("Frame", nil, card)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOP", text, "BOTTOM")
    anchor:SetPoint("LEFT", num, "LEFT")
    prev = anchor
  end

  local got = T:Button(card, "Got it", 110, function()
    ns.db.settings.welcomeSeen = true
    card:Hide()
  end, 26)
  got:SetPoint("BOTTOMRIGHT", -18, 16)
  local help = T:Button(card, "Open Help", 110, function()
    ns.db.settings.welcomeSeen = true
    card:Hide()
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
  if card then card:Show() end
end
