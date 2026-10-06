local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Training advice (owner, October 5: "skip spell ranks you don't use"). Beside the class
-- trainer: what you can learn now, sorted into Train / Your choice / Skip while levelling,
-- with the gold each costs and why (hover). From TrainerAdvice.lua (Codex's research,
-- by class and spell name), the tree you level in (Training.lua LevellingTree: your
-- talent points, or a choice), and the spells you cast. Advice only: you still click
-- Train in Blizzard's window for everything. Settings, Global settings, Advanced.
---------------------------------------------------------------------------
local WEEK = 7 * 86400
local panel

local GROUPS = {
  { key = "train", title = "Must have", color = "7fd39c" },
  { key = "choice", title = "Nice to have", color = "e8c27a" },
  { key = "skip", title = "Skip while levelling", color = "ee8597" },
  { key = "unknown", title = "Not reviewed yet", color = "999999" },
}

-- One spell's advice: group key, and the reasons to show on hover.
function ns:SpellAdvice(name, knowsLower)
  local _, class = UnitClass("player")
  local a = ns.TRAINER_ADVICE and ns.TRAINER_ADVICE[class or ""] and ns.TRAINER_ADVICE[class or ""][name]
  if not a then return "unknown", { "Not in Forever Ledger's list for your class yet." } end
  local tree = ns.LevellingTree and ns:LevellingTree()
  local why = { a.r }
  local group
  if a.c == "everyone" then
    group = "train"
  elseif a.c == "spec" then
    local mine = false
    for _, t in ipairs(a.t or {}) do if t == tree then mine = true end end
    if mine then
      group = "train"
      why[#why + 1] = ("For %s, your tree."):format(tree)
    elseif tree then
      group = "skip"
      why[#why + 1] = ("For %s; you level as %s."):format(table.concat(a.t or {}, " and "), tree)
    else
      group = "choice"
      why[#why + 1] = ("For %s. Spend talent points (or pick your tree) and this gets clearer."):format(table.concat(a.t or {}, " and "))
    end
  elseif a.c == "nice" then
    group = "choice"
  else
    group = "skip"
  end
  if a.k then why[#why + 1] = a.k end
  -- A higher rank of a spell you know (owner, October 5: is a higher Polymorph worth it?),
  -- by the spell's rank rule (Codex's research): current = keep every rank (main
  -- attacks, upkeep); learn = the first rank does the job; used = upgrade only if you
  -- cast it (after a week of counting your casts).
  if group == "train" and knowsLower then
    local key = ns.CharKey()
    local since = ns.db.castsSince and ns.db.castsSince[key]
    local counted = since and time() - since > WEEK
    local last = ns.LastCast and ns:LastCast(name)
    local castLately = last and time() - last <= WEEK
    if a.p == "learn" then
      group = "choice"
      why[#why + 1] = "You have it already, and the first rank does the job; a higher rank mostly lasts longer or reaches further. Buy it when you have gold to spare."
    elseif a.p == "used" or a.p == "defer" then
      if counted and not castLately then
        group = "choice"
        why[#why + 1] = "Upgrade it only while you use it: you haven't cast it in the last week."
      else
        why[#why + 1] = "Worth upgrading while you use it."
      end
    elseif a.p == "current" then
      why[#why + 1] = "Keep it current: the old rank falls behind as you level."
    end
  end
  return group, why
end

local function build()
  panel = CreateFrame("Frame", "ForeverLedgerTrainingPanel", UIParent)
  panel:SetSize(300, 360)
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)
  T:Fill(panel, T.bg or (T.theme and T.theme.bg) or { 0.06, 0.06, 0.07, 0.96 })
  T:Border(panel)
  panel.title = T:Text(panel, 13)
  panel.title:SetPoint("TOPLEFT", 10, -8)
  panel.title:SetText("Training advice")
  if T.StyleTitle then T:StyleTitle(panel.title, 13) end
  panel.close = T:Button(panel, "x", 20, function() panel:Hide() end, 18)
  panel.close:SetPoint("TOPRIGHT", -6, -6)
  panel.sub = T:Text(panel, 11, T.dim)
  panel.sub:SetPoint("TOPLEFT", 10, -28)
  panel.sub:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
  panel.sub:SetJustifyH("LEFT")
  panel.sf, panel.content = T:Scroll(panel)
  panel.sf:SetPoint("TOPLEFT", 6, -70)
  panel.sf:SetPoint("BOTTOMRIGHT", -6, 26)
  panel.foot = T:Text(panel, 10, T.dim)
  panel.foot:SetPoint("BOTTOMLEFT", 10, 8)
  panel.foot:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
  panel.foot:SetJustifyH("LEFT")
  panel.foot:SetText("Advice only: train in Blizzard's window. Hover a spell for why.")
  panel.rows = {}
  panel:Hide()
end

local function row(i)
  local r = panel.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, panel.content)
  r:SetHeight(18)
  r.text = T:Text(r, 11)
  r.text:SetPoint("LEFT", 4, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -64, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.cost = T:Text(r, 11)
  r.cost:SetJustifyH("RIGHT")
  r.cost:SetPoint("RIGHT", -4, 0)
  r:SetScript("OnEnter", function(self)
    if not self.why then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.spell, 1, 1, 1)
    for _, w in ipairs(self.why) do GameTooltip:AddLine(w, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.rows[i] = r
  return r
end

-- list: the trainer's services as RecipeBook.lua read them (name, state, cost, level).
function ns:ShowTrainingAdvice(list)
  if ns.db.settings.trainerAdvice == false or not T then return end   -- (no Theme in the tests)
  if not panel then build() end
  -- What you know, from the spellbook ("Rank 3"): the trainer list in Forever starts
  -- around level 20, so counting its entries gave every spell "rank 1" (owner's
  -- screenshot, October 5). Known ones are upgrades; the rest are new.
  local book = ns.KnownSpellRanks and ns:KnownSpellRanks() or {}
  for _, s in ipairs(list) do
    if s.state == "used" and not book[s.name] then book[s.name] = 0 end
  end
  local groups, cost, total = {}, {}, 0
  for _, g in ipairs(GROUPS) do groups[g.key], cost[g.key] = {}, 0 end
  for _, s in ipairs(list) do
    if s.state == "available" then
      local knownRank = book[s.name]
      local group, why = ns:SpellAdvice(s.name, knownRank ~= nil)
      local tag = (knownRank == nil and "new") or (knownRank > 0 and ("rank " .. (knownRank + 1))) or "upgrade"
      table.insert(groups[group], { s = s, why = why, tag = tag })
      cost[group] = cost[group] + (s.cost or 0)
      total = total + (s.cost or 0)
    end
  end
  local tree = ns.LevellingTree and ns:LevellingTree()
  panel.sub:SetText((total > 0 and ("Everything you can learn now: %s. Recommended: %s.\n"):format(ns.Money(total), ns.Money(cost.train)) or "Nothing new to learn at this level.\n")
    .. (tree and ("Levelling as %s (from your talents)."):format(tree) or "No talent points yet: spec spells are your choice."))
  local y, n = 0, 0
  for _, g in ipairs(GROUPS) do
    if #groups[g.key] > 0 then
      n = n + 1
      local h = row(n)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", 0, -y)
      h:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
      h.text:SetText(("|cff%s%s|r"):format(g.color, g.title))
      h.cost:SetText(ns.Money(cost[g.key]))
      h.why, h.spell = nil, nil
      h:Show()
      y = y + 20
      table.sort(groups[g.key], function(a, b) return a.s.name < b.s.name end)
      for _, e in ipairs(groups[g.key]) do
        n = n + 1
        local r = row(n)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 10, -y)
        r:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
        r.text:SetText(e.s.name .. "  |cff888888" .. e.tag .. "|r")
        r.cost:SetText(ns.Money(e.s.cost or 0))
        r.why, r.spell = e.why, e.s.name
        r:Show()
        y = y + 18
      end
      y = y + 4
    end
  end
  for i = n + 1, #panel.rows do panel.rows[i]:Hide() end
  panel.content:SetWidth(panel.sf:GetWidth() - 12)
  panel.content:SetHeight(math.max(y, 20))
  if panel.sf.UpdateScrollBar then panel.sf.UpdateScrollBar() end
  -- Beside Blizzard's trainer window when it's there.
  panel:ClearAllPoints()
  local trainer = _G.ClassTrainerFrame
  if trainer and trainer:IsShown() then
    panel:SetPoint("TOPLEFT", trainer, "TOPRIGHT", 4, 0)
  else
    panel:SetPoint("LEFT", UIParent, "CENTER", 120, 0)
  end
  panel:Show()
end

ns:On("TRAINER_CLOSED", function() if panel then panel:Hide() end end)
