local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- "Work it": a small window for doing one shuffle. Click an item to search the
-- auction house for it, or to buy it from the open vendor (one click, one
-- purchase). A session tracks what you spend on the shuffle's materials, what you
-- earn from its products, and how many runs you do.
---------------------------------------------------------------------------
local MAX_LINES = 10
local MAX_SESSIONS = 100

local win, current

local function itemName(id) return (ns.GetItemInfo(id)) or ("item " .. id) end
local function dim(t) return "|cff888888" .. t .. "|r" end

local function duration(secs)
  local m = math.floor(secs / 60)
  if m < 60 then return m .. " min" end
  return ("%d h %02d min"):format(math.floor(m / 60), m % 60)
end

---------------------------------------------------------------------------
-- Actions (each runs from one click)
---------------------------------------------------------------------------
-- Search the open auction house for an item by its exact name. (Filling in the
-- Quantity box was tried and removed: the auction house kept its old amount and price,
-- so purchases failed with "no longer available".)
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

-- Profession skill line numbers, for opening a profession window.
local SKILL_LINES = {
  Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Leatherworking = 165,
  Tailoring = 197, Cooking = 185, ["First Aid"] = 129, Mining = 186, Fishing = 356,
}

-- Start crafting a recipe from a click. Only works while that profession's window is open.
function ns:CraftFromClick(opt, count)
  local TS = C_TradeSkillUI
  if not (TS and TS.CraftRecipe and opt.recipeID) then
    ns:Print("This game client can't start crafts from an addon.")
    return
  end
  local base = TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
  local openProf = type(base) == "table" and base.professionName
  -- If the window's name isn't one we know, trust GetBaseProfessionInfo alone.
  local frame = ProfessionsFrame or TradeSkillFrame
  local windowOpen = not frame or frame:IsShown()
  if not windowOpen or not openProf or (opt.prof and openProf ~= opt.prof) then
    -- Open the profession for the player; crafting waits for a second click, since a
    -- craft started after the window loads wouldn't count as coming from their click.
    local line = SKILL_LINES[opt.prof or ""]
    if line and TS.OpenTradeSkill and pcall(TS.OpenTradeSkill, line) then
      ns:Print(("Opening %s. Click Craft again once it's open."):format(opt.prof))
    else
      ns:Print(("Open your %s window first, then click Craft."):format(opt.prof or "profession"))
    end
    return
  end
  local ok, err = pcall(TS.CraftRecipe, opt.recipeID, count)
  if not ok then ns:Print("Couldn't start the craft: " .. tostring(err)) end
end

-- Buy from the open vendor. Returns true, or false and why.
function ns:BuyFromVendor(id, qty)
  if not (MerchantFrame and MerchantFrame:IsShown()) then return false end
  for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
    if GetMerchantItemID(i) == id then
      local most = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(i)) or qty
      BuyMerchantItem(i, math.min(qty, most))
      if qty > most then
        ns:Print(("Bought %d. A vendor sells at most %d at a time, so click again for more."):format(most, most))
      end
      return true
    end
  end
  return false, itemName(id) .. " isn't sold by this vendor."
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
function ns:StartSession(s, goal)
  local inputs, products, run = ns:ShuffleItems(s)
  local names = {}
  for id in pairs(products) do
    local n = ns.GetItemInfo(id)
    if n then names[n] = true end
  end
  -- Runs are matched by spell name too: in Forever a recipe's number isn't its spell's.
  local spellName
  if s.opt.kind == "craft" then
    spellName = s.opt.rec and s.opt.rec.n
  elseif s.opt.kind == "disenchant" then
    spellName = ns.SpellName(run.spell) or "Disenchant"
  end
  ns.db.session = {
    key = s.key, name = ns:ShuffleName(s), t = time(), goal = goal ~= 0 and goal or nil, char = ns.CharKey(),
    inputs = inputs, products = products, names = names, spell = run.spell, spellName = spellName,
    sellItem = run.sellItem, kind = s.opt.kind, craftItem = s.opt.kind == "craft" and s.opt.rec and s.opt.rec.out or nil,
    runs = 0,
  }
  ns:Print(("Session started: %s. Buy, craft and sell as usual; the ledger keeps count."):format(ns.db.session.name))
end

-- Spent on materials, earned from products, runs, seconds, profit per hour.
function ns:SessionStats()
  local sess = ns.db.session
  if not sess then return end
  local spent, earned, sold = 0, 0, 0
  local function mine(e) return e.t >= sess.t and e.c == sess.char end
  for _, e in ipairs(ns.db.vendorLog) do
    if mine(e) and e.id then
      if e.s == "buy" and sess.inputs[e.id] then spent = spent + e.a end
      if e.s == "sell" and sess.products[e.id] then
        earned = earned + e.a
        if e.id == sess.sellItem then sold = sold + (e.q or 1) end
      end
    end
  end
  for _, e in ipairs(ns.db.purchases) do
    if mine(e) and e.id and sess.inputs[e.id] then spent = spent + e.a end
  end
  for _, e in ipairs(ns.db.sales) do
    if mine(e) and e.n and sess.names[e.n] then earned = earned + e.a end
  end
  local secs = math.max(time() - sess.t, 1)
  local profit = earned - spent
  return {
    spent = spent, earned = earned, profit = profit, secs = secs,
    runs = sess.sellItem and sold or sess.runs, perHour = profit / secs * 3600,
  }
end

function ns:StopSession()
  local sess, st = ns.db.session, ns:SessionStats()
  if not sess then return end
  table.insert(ns.db.sessions, {
    name = sess.name, t = sess.t, stop = time(), spent = st.spent, earned = st.earned, runs = st.runs, goal = sess.goal,
  })
  while #ns.db.sessions > MAX_SESSIONS do table.remove(ns.db.sessions, 1) end
  ns.db.session = nil
  ns:Print(("Session on %s: %d runs in %s. Spent %s, earned %s, profit %s%s."):format(
    sess.name, st.runs, duration(st.secs), ns.Money(st.spent), ns.Money(st.earned),
    st.profit < 0 and "-" or "", ns.Money(math.abs(st.profit))))
end

function ns.SpellName(spellID)
  if not spellID then return end
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
  if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

local function addRuns(n)
  local sess = ns.db.session
  sess.runs = sess.runs + n
  -- Tell the player when the goal is reached, once.
  if sess.goal and not sess.goalDone and sess.runs >= sess.goal then
    sess.goalDone = true
    local text = ("Goal reached: %d %s"):format(sess.runs, sess.name)
    if RaidNotice_AddMessage and RaidWarningFrame then
      RaidNotice_AddMessage(RaidWarningFrame, text, { r = T.accent[1], g = T.accent[2], b = T.accent[3] })
    end
    if ns.db.settings.dealSound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
      PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
    ns:Print(text .. ".")
  end
  if win and win:IsShown() then win:RefreshSession() end
end

-- Crafts: count "You create: [item]." (or "[item]x5") for the shuffle's first product.
-- This doesn't depend on spell or recipe numbers, which differ in Forever.
local CREATED = LOOT_ITEM_CREATED_SELF and LOOT_ITEM_CREATED_SELF:match("^(.-)%%s") or "You create: "
local function onCreated(msg)
  local sess = ns.db and ns.db.session
  if not (sess and sess.craftItem and type(msg) == "string") then return end
  if msg:sub(1, #CREATED) ~= CREATED then return end
  local id = ns.ItemIDFromLink(msg)
  ns:Debug("Created", id or "?", "- session counts", sess.craftItem)
  if id == sess.craftItem then addRuns(tonumber(msg:match("x(%d+)%.?$")) or 1) end
end
ns:On("CHAT_MSG_LOOT", onCreated)
ns:On("CHAT_MSG_TRADESKILLS", onCreated)

-- Disenchanting: count each successful Disenchant cast.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  local sess = ns.db and ns.db.session
  if unit ~= "player" or not sess or sess.kind ~= "disenchant" then return end
  local name = ns.SpellName(spellID)
  ns:Debug("Cast", spellID, name or "?")
  if spellID == sess.spell or (sess.spellName and name == sess.spellName) then addRuns(1) end
end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function money(v) return (v < 0 and "-" or "") .. ns.Money(math.abs(v)) end

local function buildWindow()
  win = ns.ThemedWindow("ForeverLedgerWork", 440, 540, T:AccentCode() .. "Work it|r")
  win:ClearAllPoints()
  win:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)

  win.name = T:Text(win, 14)
  win.name:SetPoint("TOPLEFT", 14, -42)
  win.name:SetPoint("RIGHT", win, "RIGHT", -14, 0)
  win.name:SetJustifyH("LEFT")

  local runsLabel = T:Text(win, 12, T.dim)
  runsLabel:SetPoint("TOPLEFT", 14, -72)
  runsLabel:SetText("Buy for")
  win.runs = T:Number(win, { min = 1, max = 999, suffix = "runs" }, function() win:RefreshList() end)
  win.runs:SetPoint("LEFT", runsLabel, "RIGHT", 10, 0)
  win.runs:SetValue(1)

  win.listTitle = T:Text(win, 12, T.accent)
  win.listTitle:SetPoint("TOPLEFT", 14, -102)
  win.listTitle:SetText("Shopping list: click to search the auction house, or buy from the open vendor")

  win.lines = {}
  for i = 1, MAX_LINES do
    local b = CreateFrame("Button", nil, win)
    b:SetHeight(22)
    b:SetPoint("TOPLEFT", 10, -(118 + (i - 1) * 23))
    b:SetPoint("RIGHT", win, "RIGHT", -10, 0)
    T:Fill(b, { 1, 1, 1, 0.03 })
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.12)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 4, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.right = T:Text(b, 11, T.dim)
    b.right:SetPoint("RIGHT", -6, 0)
    b.text = T:Text(b, 12)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
      local qty = self.qty * (win.runs.value or 1)
      if ns:SearchAuctionHouse(self.id) then return end
      local ok, why = ns:BuyFromVendor(self.id, qty)
      if ok then return end
      ns:Print(why or "Open the auction house or a vendor first, then click an item.")
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(self.id)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(("At the auction house: click to search for it, then buy %d."):format(self.qty * (win.runs.value or 1)), T.accent[1], T.accent[2], T.accent[3])
      GameTooltip:AddLine(("At a vendor: click to buy %d."):format(self.qty * (win.runs.value or 1)), T.accent[1], T.accent[2], T.accent[3])
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.lines[i] = b
  end

  win.stepsTitle = T:Text(win, 12, T.accent)
  win.stepsTitle:SetText("Steps")
  -- Starts the first craft, as many times as "Buy for" says. Needs its profession window open.
  win.craft = T:Button(win, "Craft", 120, function()
    if current and current.opt.kind == "craft" then ns:CraftFromClick(current.opt, win.runs.value or 1) end
  end, 22)
  win.craft:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Starts the first craft", 1, 1, 1)
    GameTooltip:AddLine(("Open your %s window first."):format(current and current.opt.prof or "profession"), 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end)
  win.craft:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.steps = T:Text(win, 11, { 1, 1, 1, 0.85 })
  win.steps:SetJustifyH("LEFT")
  win.steps:SetJustifyV("TOP")
  win.steps:SetSpacing(3)

  -- Session area, along the bottom.
  local sessTitle = T:Text(win, 12, T.accent)
  sessTitle:SetPoint("BOTTOMLEFT", 14, 150)
  sessTitle:SetText("Session")
  local goalLabel = T:Text(win, 12, T.dim)
  goalLabel:SetPoint("BOTTOMLEFT", 14, 122)
  goalLabel:SetText("Goal")
  win.goal = T:Number(win, { min = 0, max = 9999, suffix = "runs (0 = none)" }, function() end)
  win.goal:SetPoint("LEFT", goalLabel, "RIGHT", 10, 0)
  win.goal:SetValue(0)
  win.startStop = T:Button(win, "Start session", 130, function()
    if ns.db.session then ns:StopSession() elseif current then ns:StartSession(current, win.goal.value or 0) end
    win:RefreshSession()
  end)
  win.startStop:SetPoint("BOTTOMRIGHT", -14, 116)
  win.stats = T:Text(win, 12)
  win.stats:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 14, 102)
  win.stats:SetPoint("RIGHT", win, "RIGHT", -14, 0)
  win.stats:SetJustifyH("LEFT")
  win.stats:SetJustifyV("TOP")
  win.stats:SetSpacing(4)

  function win:RefreshList()
    if not current then
      for _, b in ipairs(self.lines) do b:Hide() end
      self.stepsTitle:Hide()
      self.steps:Hide()
      self.craft:Hide()
      return
    end
    local runs = self.runs.value or 1
    local buys = ns:ShuffleBuys(current)
    local shown = 0
    for i, b in ipairs(self.lines) do
      local item = buys[i]
      if item then
        shown = i
        b.id, b.qty = item.id, current.group and 1 or item.qty
        b.icon:SetTexture(ns:ItemIcon(item.id))
        b.text:SetText(("%d x %s"):format(b.qty * runs, itemName(item.id)))
        b.right:SetText(ns.Money(item.price) .. " each  " .. (item.listed and "auction house" or "vendor"))
        b:Show()
      else
        b:Hide()
      end
    end
    local y = 118 + shown * 23 + 12
    self.stepsTitle:ClearAllPoints()
    self.stepsTitle:SetPoint("TOPLEFT", 14, -y)
    self.stepsTitle:Show()
    local canCraft = current.opt.kind == "craft" and current.opt.recipeID ~= nil
    self.craft:ClearAllPoints()
    self.craft:SetPoint("TOPRIGHT", self, "TOPRIGHT", -14, -(y - 4))
    self.craft:SetText(("Craft %d"):format(runs))
    self.craft:SetShown(canCraft)
    self.steps:ClearAllPoints()
    self.steps:SetPoint("TOPLEFT", 14, -(y + 18))
    self.steps:SetPoint("RIGHT", self, "RIGHT", -14, 0)
    self.steps:SetText(ns:ShuffleSteps(current) .. "\n\n" .. ns:ShuffleProfitLine(current))
    self.steps:Show()
  end

  function win:RefreshSession()
    local sess = ns.db.session
    if sess then
      local st = ns:SessionStats()
      local goal = sess.goal and (" of " .. sess.goal) or ""
      self.stats:SetText(table.concat({
        ("Working on %s for %s"):format(sess.name, duration(st.secs)),
        ("Runs: %d%s"):format(st.runs, goal),
        ("Spent: %s    Earned: %s"):format(ns.Money(st.spent), ns.Money(st.earned)),
        ("Profit: %s    About %s an hour"):format(money(st.profit), money(math.floor(st.perHour / 100) * 100)),
      }, "\n"))
      self.startStop:SetText("Stop session")
      self.startStop:SetEnabled(true)
    else
      self.stats:SetText(dim("Set a goal if you like, then Start session. Spending on this shuffle's materials, sales of its products and runs are counted until you stop."))
      self.startStop:SetText("Start session")
      self.startStop:SetEnabled(current ~= nil)
    end
  end

  C_Timer.NewTicker(1, function()
    if win:IsShown() and ns.db.session then win:RefreshSession() end
  end)
end

-- Open the window for a shuffle, or with none to see the running session.
function ns:OpenWork(s)
  if not win then buildWindow() end
  current = s or current
  win.name:SetText(current and ns:ShuffleName(current) or (ns.db.session and ns.db.session.name) or "")
  win:RefreshList()
  win:RefreshSession()
  win:Show()
end

function ns:OnMoneyLogged()
  if win and win:IsShown() and ns.db.session then win:RefreshSession() end
end
