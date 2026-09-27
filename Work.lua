local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- "Work it": a small window for doing one shuffle. Click an item to search the
-- auction house for it, or to buy it from the open vendor (one click, one
-- purchase). A session tracks what you spend on the shuffle's materials, what you
-- earn from its products, and how many runs you do.
---------------------------------------------------------------------------
local MAX_LINES = 8
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

-- The skill line to open a profession: the character's own, else the usual number.
local function skillLineFor(prof)
  if GetProfessions and GetProfessionInfo then
    local list = { GetProfessions() }
    for i = 1, 6 do
      local idx = list[i]
      if idx then
        local name, _, _, _, _, _, line = GetProfessionInfo(idx)
        if name == prof and line then return line end
      end
    end
  end
  return SKILL_LINES[prof or ""]
end

-- The profession window sometimes opens on the last profession used. When it does,
-- switch it to the one asked for (a couple of tries, within a few seconds).
local pendingOpen
local function checkOpened()
  local p = pendingOpen
  if not p then return end
  if GetTime() - p.t > 5 then pendingOpen = nil; return end
  local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  local open = type(base) == "table" and base.professionName
  if open == p.prof then
    pendingOpen = nil
  elseif open and p.tries < 3 then
    p.tries = p.tries + 1
    pcall(C_TradeSkillUI.OpenTradeSkill, p.line)
  end
end
ns:On("TRADE_SKILL_SHOW", function() C_Timer.After(0.2, checkOpened) end)
ns:On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() C_Timer.After(0.2, checkOpened) end)

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
    local line = skillLineFor(opt.prof)
    if line and TS.OpenTradeSkill and pcall(TS.OpenTradeSkill, line) then
      pendingOpen = { prof = opt.prof, line = line, t = GetTime(), tries = 1 }
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
-- Disenchant button: a secure button (the only kind allowed to cast a spell) set to
-- "Disenchant this bag slot". It only ever points at the current shuffle's items, and
-- can't be changed in combat, so it's updated out of combat when bags change.
---------------------------------------------------------------------------
local DISENCHANT_SPELL = 13262
local deButton, deTargets

local function nextTarget()
  if not deTargets or not (C_Container and C_Container.GetContainerNumSlots) then return end
  local found, count
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and deTargets[info.itemID] then
        count = (count or 0) + (info.stackCount or 1)
        if not found and not info.isLocked then found = { bag = bag, slot = slot, id = info.itemID } end
      end
    end
  end
  return found, count or 0
end

local function updateDisenchantButton()
  if not deButton then return end
  if InCombatLockdown() then deButton.pending = true; return end
  deButton.pending = false
  if not deTargets then deButton:Hide(); return end
  local target, count = nextTarget()
  if target then
    deButton:SetAttribute("type", "spell")
    deButton:SetAttribute("spell", ns.SpellName(DISENCHANT_SPELL) or "Disenchant")
    deButton:SetAttribute("target-bag", target.bag)
    deButton:SetAttribute("target-slot", target.slot)
    deButton.text:SetText(("Disenchant: %s (%d left)"):format((ns.GetItemInfo(target.id)) or "?", count))
    deButton.icon:SetTexture(ns:ItemIcon(target.id))
    deButton.icon:Show()
    deButton:SetAlpha(1)
  else
    deButton:SetAttribute("type", nil)
    deButton.text:SetText("Nothing from this shuffle to disenchant in your bags")
    deButton.icon:Hide()
    deButton:SetAlpha(0.6)
  end
  deButton:Show()
end

ns:On("BAG_UPDATE_DELAYED", function() if deButton and deButton:IsVisible() then updateDisenchantButton() end end)
ns:On("PLAYER_REGEN_ENABLED", function() if deButton and deButton.pending then updateDisenchantButton() end end)

local function buildDisenchantButton(parent)
  local b = CreateFrame("Button", "ForeverLedgerDisenchantButton", parent, "SecureActionButtonTemplate")
  b:SetSize(300, 26)
  b:RegisterForClicks("AnyUp", "AnyDown")
  local c = T.button
  T:Fill(b, c)
  T:Border(b, { T.accent[1], T.accent[2], T.accent[3], 0.6 })
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(18, 18)
  b.icon:SetPoint("LEFT", 5, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.text = T:Text(b, 12)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetPoint("RIGHT", -6, 0)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  b:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Disenchants the next item from this shuffle in your bags", 1, 1, 1, true)
    GameTooltip:AddLine("One click, one disenchant. Only this shuffle's items are ever picked.", 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function money(v) return (v < 0 and "-" or "") .. ns.Money(math.abs(v)) end

local function buildWindow()
  win = ns.ThemedWindow("ForeverLedgerWork", 440, 620, T:AccentCode() .. "Work it|r")
  win:ClearAllPoints()
  win:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)

  win.name = T:Text(win, 14)
  win.name:SetPoint("TOPLEFT", 14, -42)
  win.name:SetPoint("RIGHT", win, "RIGHT", -14, 0)
  win.name:SetJustifyH("LEFT")

  -- One number for everything: amounts to buy, crafts, and the session goal.
  local runsLabel = T:Text(win, 12, T.dim)
  runsLabel:SetPoint("TOPLEFT", 14, -72)
  runsLabel:SetText("Runs")
  win.runs = T:Number(win, { min = 1, max = 999, suffix = "(what to buy, craft, and the session goal)" }, function(v)
    local sess = ns.db.session
    if sess then
      sess.goal = v
      if sess.runs < v then sess.goalDone = nil end
    end
    win:RefreshList()
    win:RefreshSession()
  end)
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
  deButton = buildDisenchantButton(win)
  win.craftNote = T:Text(win, 10, T.dim)
  win.craftNote:SetPoint("TOPRIGHT", win.craft, "BOTTOMRIGHT", 0, -3)
  win.craftNote:SetJustifyH("RIGHT")
  win.steps = T:Text(win, 11, { 1, 1, 1, 0.85 })
  win.steps:SetJustifyH("LEFT")
  win.steps:SetJustifyV("TOP")
  win.steps:SetSpacing(3)

  -- Session area, along the bottom.
  local sessTitle = T:Text(win, 12, T.accent)
  sessTitle:SetPoint("BOTTOMLEFT", 14, 124)
  sessTitle:SetText("Session")
  win.startStop = T:Button(win, "Start session", 220, function()
    if ns.db.session then ns:StopSession() elseif current then ns:StartSession(current, win.runs.value or 1) end
    win:RefreshSession()
  end)
  win.startStop:SetPoint("BOTTOMRIGHT", -14, 118)
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
      self.craftNote:Hide()
      deTargets = nil
      updateDisenchantButton()
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
    self.craftNote:SetText("First click opens the profession\nSecond click crafts")
    self.craftNote:SetShown(canCraft)
    self.steps:ClearAllPoints()
    self.steps:SetPoint("TOPLEFT", 14, -(y + 18))
    self.steps:SetPoint("RIGHT", self, "RIGHT", -14, 0)
    self.steps:SetText(ns:ShuffleSteps(current) .. "\n\n" .. ns:ShuffleProfitLine(current))
    self.steps:Show()

    -- The Disenchant button sits under the steps (moved only out of combat).
    deTargets = ns:ShuffleDisenchantTargets(current)
    if not InCombatLockdown() then
      deButton:ClearAllPoints()
      deButton:SetPoint("TOPLEFT", self.steps, "BOTTOMLEFT", 0, -10)
      deButton:SetPoint("RIGHT", self, "RIGHT", -14, 0)
    end
    updateDisenchantButton()
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
      self.stats:SetText(dim("Start a session to count what you spend on this shuffle's materials, what you earn selling its products, and your runs, until you stop. The goal is the Runs number at the top."))
      self.startStop:SetText(("Start session (goal: %d runs)"):format(self.runs.value or 1))
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
  win:Raise()
end

function ns:OnMoneyLogged()
  if win and win:IsShown() and ns.db.session then win:RefreshSession() end
end
