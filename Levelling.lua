local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Levelling tab (owner, October 7): part of the Levelling help module (Settings, Global
-- settings, Modules). Its first page is "Getting started": ways to make gold while
-- levelling, priced from your scans, for characters under 20. From Codex's research
-- (planning/LAUNCH_GOLD_DRAFT.md in the notes repo, October 7), in our own words.
-- Forever = seen in Forever (patch notes, beta); otherwise Classic's, still to confirm.
-- Lines for a profession or class you don't have are dimmed, not hidden, so the list
-- also helps choose professions.
---------------------------------------------------------------------------
local MAX_LEVEL = 20   -- the tab shows below this level (owner, October 7: start there)

-- ids: items to price; the first is the one shown on the row. prof / class: what it
-- needs. zone: { Alliance, Horde }. vendor: priced at what a vendor pays (binds on pickup).
local LIST = {
  { title = "Skin the beasts you kill", prof = "Skinning", lvl = { 1, 20 }, forever = true,
    ids = { 2318, 2934, 783, 2319 },
    zone = { "Starting zone, then Westfall and Loch Modan", "Starting zone, then the Barrens and Silverpine" },
    how = "Skin every beast you kill anyway on quests. One skin per corpse in Forever. Sell leather when it's worth more than a vendor pays.",
    why = "Extra materials from kills you were making anyway, with almost no start-up cost." },
  { title = "Mine copper on your quest route", prof = "Mining", lvl = { 5, 15 },
    ids = { 2770, 2840, 2835 },
    zone = { "Elwynn Forest, Dun Morogh, Darkshore", "Durotar, Mulgore" },
    how = "Mine the veins along your path and keep the Rough Stone. Smelt only when bars sell for more than the ore. Forever has fewer copper veins than Classic.",
    why = "Many leveling professions need early metal and stone." },
  { title = "Pick herbs as you go", prof = "Herbalism", lvl = { 1, 20 },
    ids = { 2447, 765, 785, 2450, 2452, 2449 },
    zone = { "Elwynn, Dun Morogh, Teldrassil, then Westfall and Darkshore", "Durotar, Mulgore, Tirisfal, then the Barrens and Silverpine" },
    how = "Gather the herbs near your quests. Mageroyal and Briarthorn sometimes give Swiftthistle as a bonus.",
    why = "Herbs go into potions (now First Aid in Forever) and skill-ups, so they keep selling." },
  { title = "Linen and coin from humanoid camps", lvl = { 6, 16 },
    ids = { 2589, 2996 },
    zone = { "Elwynn kobolds and gnolls, then the Defias in Westfall", "Razormane camps in Durotar, then the pirates south of Ratchet" },
    how = "Kill humanoids on your quests: keep the Linen, vendor the gray items, check any greens. Move on when the camp is crowded.",
    why = "Cloth, coin and vendor loot from the same kills." },
  { title = "Make Linen Bags", prof = "Tailoring", lvl = { 1, 20 }, forever = true,
    ids = { 4238, 2589, 2996, 2320, 4496 },
    zone = { "Any town with customers", "Any town with customers" },
    how = "Make a few and sell them in Trade or a small batch on the auction house. A vendor's six-slot bag sets the most people will pay.",
    why = "Every new character needs bag space right away." },
  { title = "Wands for casters (sold to players)", prof = "Enchanting", lvl = { 5, 20 }, forever = true,
    ids = { 11287, 11288, 10938, 4470 },
    zone = { "Towns with new casters", "Towns with new casters" },
    how = "Make a Lesser Magic Wand (later a Greater) for a caster who wants one. Vendors pay only a little for them (Lesser 1s 10c, Greater 2s since the October 8 patch), so sell to players; the vendor price is just a floor.",
    why = "A useful early weapon can sell above what it costs to make." },
  { title = "Wool from the next camps", lvl = { 18, 26 },
    ids = { 2592, 2997 },
    zone = { "Blackrock orcs in Redridge, then Hillsbrad", "Syndicate camps and farms in Hillsbrad" },
    how = "When you're strong enough for the camp, farm Wool Cloth; sell it apart from Linen.",
    why = "The next cloth reaches buyers before most players get there." },
  { title = "Tin, Coarse Stone and Bronze", prof = "Mining", lvl = { 12, 25 },
    ids = { 2771, 3576, 2841, 2836 },
    zone = { "Loch Modan and Westfall, then Redridge", "The Barrens and Silverpine, then Ashenvale" },
    how = "Mine a safe loop. Smelt Bronze only when two bars sell for more than the copper and tin.",
    why = "Players moving past copper need tin and bronze." },
  -- (Minor Wizard Oil left the list: since the October 8 patch a vendor pays 1s for it,
  -- less than its Maple Seed and vial cost. Codex's research, October 10.)
  { title = "Disenchant cheap greens", prof = "Enchanting", lvl = { 5, 20 }, forever = true,
    ids = { 10940, 10938, 10939, 10978 },
    zone = { "The auction house", "The auction house" },
    how = "Buy greens for less than their dust and essences sell for: the Disenchant finder beside the auction house lists them.",
    why = "Gear and material prices often don't match." },
  { title = "Mage water and food", class = "MAGE", lvl = { 4, 20 }, forever = true, service = true,
    zone = { "Capitals and dungeon meeting points", "Capitals and dungeon meeting points" },
    how = "Offer your best water and food to groups and people asking in Trade, for a tip. The Customers window spots them.",
    why = "Almost free to make; people pay to skip the vendor." },
  { title = "Healing potions from First Aid", prof = "First Aid", lvl = { 5, 20 }, forever = true,
    ids = { 118, 858, 2447, 3371 },
    zone = { "Any town", "Any town" },
    how = "Healing potions are First Aid in Forever. Make a few to order; otherwise sell the herbs.",
    why = "Levelers buy them instead of training First Aid themselves." },
  { title = "Enchants as a service", prof = "Enchanting", lvl = { 5, 20 }, forever = true, service = true,
    zone = { "Trade chat or your group", "Trade chat or your group" },
    how = "Enchant with the customer's materials for a tip; the Customers window spots requests.",
    why = "Paid skill-ups with no stock to sell." },
  { title = "Fish what sells", prof = "Fishing", lvl = { 10, 20 },
    ids = { 6358, 6522, 21071 },
    zone = { "Westfall and Darkshore coasts, Loch Modan", "Ratchet, Barrens oases, Silverpine" },
    how = "Try a pool and sell a small catch before fishing for an hour.",
    why = "No fighting over mobs, and some fish go into potions and food." },
  -- (Recipe: Peace Tea left the list: it vends for 10c since the October 8 patch.)
}
ns.LEVELLING_START = LIST

local view

local function myProfs()
  local c = ns.db.chars[ns.CharKey()]
  local have = {}
  for name in pairs(c and c.profs or {}) do have[name] = true end
  return have
end

-- Can this character do it now (profession, class, faction)? And the reason if not.
local function fits(e, profs, class, faction)
  if e.class and e.class ~= class then return false, "needs a " .. e.class:sub(1, 1) .. e.class:sub(2):lower() end
  if e.faction and e.faction ~= faction then return false, e.faction .. " only" end
  if e.prof and not profs[e.prof] then return false, "with " .. e.prof end
  return true
end

-- What the row shows on the right: the first item's price.
local function priceText(e)
  if e.service then return "|cff999999service|r" end
  local id = e.ids and e.ids[1]
  if not id then return "" end
  local p = e.vendor and ns:GetSellPrice(id) or (ns:GetPrice(id))
  if not p then return "|cff999999scan to see|r" end
  return ns.Money(p) .. (e.vendor and " |cff999999vendor|r" or "")
end

local function row(i)
  local r = view.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, view.content)
  r:SetHeight(40)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.04)
  r.line = r:CreateTexture(nil, "BORDER")
  r.line:SetHeight(1)
  r.line:SetPoint("BOTTOMLEFT")
  r.line:SetPoint("BOTTOMRIGHT")
  r.line:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.5)
  r.title = T:Text(r, 13)
  r.title:SetPoint("TOPLEFT", 6, -5)
  r.title:SetPoint("RIGHT", r, "RIGHT", -140, 0)
  r.title:SetJustifyH("LEFT")
  r.title:SetWordWrap(false)
  r.sub = T:Text(r, 11, T.dim)
  r.sub:SetPoint("TOPLEFT", 6, -22)
  r.sub:SetPoint("RIGHT", r, "RIGHT", -140, 0)
  r.sub:SetJustifyH("LEFT")
  r.sub:SetWordWrap(false)
  r.price = T:Text(r, 12)
  r.price:SetPoint("RIGHT", -8, 0)
  r.price:SetJustifyH("RIGHT")
  r:RegisterForClicks("LeftButtonUp")
  r:SetScript("OnClick", function(self)
    local e = self.e
    if e.service then
      if ns.ShowCustomers then ns:ShowCustomers() end
    elseif e.ids and not e.vendor then
      if not ns:SearchAuctionHouse(e.ids[1]) then ns:Print("Open the auction house, then click a line to search for it.") end
    end
  end)
  r:SetScript("OnEnter", function(self)
    local e = self.e
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.title, 1, 1, 1)
    GameTooltip:AddLine(e.forever and "Seen in Forever" or "From Classic: not yet confirmed in Forever", 0.6, 0.6, 0.6)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("What to do", 1, 0.82, 0)
    GameTooltip:AddLine(e.how, 0.85, 0.85, 0.85, true)
    GameTooltip:AddLine("Why it pays", 1, 0.82, 0)
    GameTooltip:AddLine(e.why, 0.85, 0.85, 0.85, true)
    if e.ids then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(e.vendor and "A vendor pays" or "Prices from your scans", 1, 0.82, 0)
      for _, id in ipairs(e.ids) do
        local p = e.vendor and ns:GetSellPrice(id) or (ns:GetPrice(id))
        GameTooltip:AddDoubleLine("  " .. ns.ItemName(id), p and ns.Money(p) or "not scanned yet", 0.8, 0.8, 0.8, 1, 1, 1)
      end
    end
    if e.service then GameTooltip:AddLine("Click: the Customers window.", T.accent[1], T.accent[2], T.accent[3])
    elseif e.ids and not e.vendor then GameTooltip:AddLine("Click: search the auction house for it.", T.accent[1], T.accent[2], T.accent[3]) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  view.rows[i] = r
  return r
end

function ns:BuildLevelling(parent)
  view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints()
  view.head = T:Text(view, 12)
  T:StyleHeading(view.head, "Getting started")
  view.head:SetPoint("TOPLEFT", 4, -4)
  view.intro = T:Text(view, 11, T.dim)
  view.intro:SetPoint("TOPLEFT", 4, -24)
  view.intro:SetPoint("RIGHT", view, "RIGHT", -4, 0)
  view.intro:SetJustifyH("LEFT")
  view.intro:SetText("Ways to make gold while leveling, best first, priced from your scans. Dimmed lines need a profession this character doesn't have. Hover a line for what to do.")
  -- Only what this character can do: hides lines needing a profession it hasn't got
  -- (owner, October 7). Class-only lines never show for other classes.
  view.mine = T:Check(view, function(self)
    ns.db.settings.levellingMine = self:GetChecked()
    ns:RefreshLevelling()
  end)
  view.mine:SetPoint("TOPRIGHT", -150, -6)
  view.mine.label:SetText("Only my professions")
  view.mine:SetHitRectInsets(0, -140, 0, 0)
  view.sf, view.content = T:Scroll(view)
  view.sf:SetPoint("TOPLEFT", 0, -56)
  view.sf:SetPoint("BOTTOMRIGHT", 0, 0)
  view.rows = {}
  view:Hide()
  return view
end

function ns:RefreshLevelling()
  if not view then return end
  local profs, _, class = myProfs(), UnitClass("player")
  local faction = UnitFactionGroup("player")
  local level = UnitLevel("player") or 1
  -- What this character can do first (in the list's order), then the rest, dimmed.
  local onlyMine = ns.db.settings.levellingMine
  view.mine:SetChecked(onlyMine)
  local yes, no = {}, {}
  for _, e in ipairs(LIST) do
    local ok, why = fits(e, profs, class, faction)
    -- Another class's or faction's line is no use to this character: left out.
    local other = (e.class and e.class ~= class) or (e.faction and e.faction ~= faction)
    if not other and (ok or not onlyMine) then table.insert(ok and yes or no, { e = e, why = why }) end
  end
  local y, n = 0, 0
  for _, group in ipairs({ yes, no }) do
    for _, it in ipairs(group) do
      local e = it.e
      n = n + 1
      local r = row(n)
      r.e = e
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
      r:SetPoint("RIGHT", view.content, "RIGHT", 0, 0)
      local zone = e.zone and e.zone[faction == "Horde" and 2 or 1] or ""
      local lv = ("level %d-%d"):format(e.lvl[1], e.lvl[2])
      if level < e.lvl[1] then lv = lv .. ", later" end
      r.title:SetText(e.title .. (e.forever and "" or " |cff999999(Classic)|r"))
      local parts = { lv }
      if zone ~= "" then parts[#parts + 1] = zone end
      if it.why then parts[#parts + 1] = it.why end
      r.sub:SetText(table.concat(parts, ", "))
      r.price:SetText(priceText(e))
      r:SetAlpha(it.why and 0.45 or 1)
      r:Show()
      y = y + 42
    end
  end
  for i = n + 1, #view.rows do view.rows[i]:Hide() end
  view.content:SetWidth(math.max(view.sf:GetWidth() - 12, 300))
  view.content:SetHeight(math.max(y, 20))
  if view.sf.UpdateScrollBar then view.sf.UpdateScrollBar() end
end

-- The tab shows while the module is on and the character is under 20.
function ns:LevellingTabShown()
  return ns.LevellingOn and ns:LevellingOn() and (UnitLevel("player") or 0) < MAX_LEVEL
end
-- (UnitLevel catches up a moment after the event.)
ns:On("PLAYER_LEVEL_UP", function()
  if C_Timer then C_Timer.After(1, function() if ns.LayoutTabs then ns:LayoutTabs() end end) end
end)
