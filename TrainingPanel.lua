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
  if not a then return "unknown", { reason = "Not in Forever Ledger's list for your class yet.", notes = {} } end
  local tree = ns.LevellingTree and ns:LevellingTree()
  -- Hover sections (owner, October 6: readable, not one block): verdict, reason, when to
  -- upgrade, notes.
  local why = { reason = a.r, notes = {} }
  local group
  -- The levelling tier (Codex's community research, October 6): one for every tree, or one
  -- per tree, read for the tree you level in. Without a tree yet, a spell the trees
  -- disagree on is your choice.
  local TIER = { must = "train", nice = "choice", skip = "skip" }
  if type(a.tr) == "string" and TIER[a.tr] then
    group = TIER[a.tr]
  elseif type(a.tr) == "table" then
    local tier = tree and a.tr[tree]
    if not tier and not tree then
      local seen, same = nil, true
      for _, v in pairs(a.tr) do if seen and v ~= seen then same = false end; seen = v end
      tier = same and seen or nil
    end
    if tier and TIER[tier] then
      group = TIER[tier]
      if tree then
        why.verdict = ((tier == "must" and "Must have for %s, your tree.") or (tier == "nice" and "Nice to have for %s, your tree.")
          or "Not needed levelling as %s."):format(tree)
      end
    else
      group = "choice"
      local parts = {}
      for t, v in pairs(a.tr) do parts[#parts + 1] = ("%s: %s"):format(t, (v == "must" and "must have") or (v == "nice" and "nice to have") or "skip") end
      table.sort(parts)
      why.verdict = "Depends on your tree: " .. table.concat(parts, ", ") .. "."
      why.notes[#why.notes + 1] = "Spend talent points and this gets clearer."
    end
  elseif a.c == "everyone" then
    group = "train"
  elseif a.c == "spec" then
    local mine = false
    for _, t in ipairs(a.t or {}) do if t == tree then mine = true end end
    if mine then
      group = "train"
      why.verdict = ("For %s, your tree."):format(tree)
    elseif tree then
      group = "skip"
      why.verdict = ("For %s; you level as %s."):format(table.concat(a.t or {}, " and "), tree)
    else
      group = "choice"
      why.verdict = ("For %s. Spend talent points and this gets clearer."):format(table.concat(a.t or {}, " and "))
    end
  elseif a.c == "nice" then
    group = "choice"
  else
    group = "skip"
  end
  if a.k then why.notes[#why.notes + 1] = a.k end
  if a.b then why.notes[#why.notes + 1] = a.b end
  -- When to upgrade, for every spell (owner, October 6: some hovers had only one short
  -- line), by its rank rule (Codex's research): current = keep every rank (main attacks,
  -- upkeep); learn = the first rank does the job; used = upgrade while you cast it;
  -- defer = wait until you need it. A higher rank of a spell you know (owner, October 5:
  -- is a higher Polymorph worth it?) can move down a group: a learn spell, or a used one
  -- you haven't cast in a week of counting.
  local key = ns.CharKey()
  local since = ns.db.castsSince and ns.db.castsSince[key]
  local counted = since and time() - since > WEEK
  local last = ns.LastCast and ns:LastCast(name)
  local castLately = last and time() - last <= WEEK
  if group == "skip" then
    why.upgrade = "Not while levelling. Come back to it at 60, or if you start using it."
  elseif a.p == "current" then
    why.upgrade = knowsLower and "Always: the old rank falls behind as you level."
      or "Keep every rank as it comes: it's a spell you lean on, and an old rank falls behind."
  elseif a.p == "learn" then
    if knowsLower then
      if group == "train" then group = "choice" end
      why.upgrade = "You have it, and the first rank does the job. A higher rank mostly lasts longer or reaches further: buy it with gold to spare."
    else
      why.upgrade = "The first rank does the job. Later ranks mostly last longer or reach further: buy them with gold to spare."
    end
  elseif a.p == "used" then
    if knowsLower and counted and not castLately then
      if group == "train" then group = "choice" end
      why.upgrade = "Only while you use it, and you haven't cast it in the last week."
    else
      why.upgrade = "Upgrade while you cast it often. Skip new ranks once you stop using it."
    end
  elseif a.p == "defer" then
    if knowsLower and counted and not castLately and group == "train" then group = "choice" end
    why.upgrade = "Can wait: train it when you need it (see why above), not just because it's there."
  end
  -- A plain verdict when the tree didn't give one, so every hover reads the same way.
  why.verdict = why.verdict or (group == "train" and "Must have while levelling.")
    or (group == "choice" and "Nice to have: worth it when gold allows.") or "Skip while levelling."
  return group, why
end

local function build()
  panel = CreateFrame("Frame", "ForeverLedgerTrainingPanel", UIParent)
  panel:SetSize(300, 360)
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)
  -- Dressed like the addon's other windows (owner, October 6: on Gilded it didn't fit):
  -- the theme's frame, a title bar with its line, a tinted footer.
  T:Fill(panel, { T.bg[1], T.bg[2], T.bg[3], 0.97 })
  T:Border(panel)
  local bar = CreateFrame("Frame", nil, panel)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(28)
  T:DecorateWindow(panel, 24, bar)
  panel.title = T:Text(bar, 13)
  panel.title:SetPoint("LEFT", 10, 0)
  panel.title:SetText("Training advice")
  T:StyleTitle(panel.title, 13)
  panel.close = T:Button(bar, "x", 20, function() panel:Hide() end, 18)
  panel.close:SetPoint("RIGHT", -5, 0)
  panel.sub = T:Text(panel, 11, T.dim)
  panel.sub:SetPoint("TOPLEFT", 10, -36)
  panel.sub:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
  panel.sub:SetJustifyH("LEFT")
  panel.sf, panel.content = T:Scroll(panel)
  panel.sf:SetPoint("TOPLEFT", 6, -74)
  panel.sf:SetPoint("BOTTOMRIGHT", -6, 28)
  panel.foot = T:Text(panel, 10, T.dim)
  panel.foot:SetPoint("BOTTOMLEFT", 10, 7)
  panel.foot:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
  panel.foot:SetJustifyH("LEFT")
  panel.foot:SetWordWrap(false)
  panel.foot:SetText("Hover a spell for why. Advice only.")
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
  -- Under a group heading: a faint line in the theme's frame colour (bronze on Gilded).
  r.line = r:CreateTexture(nil, "BORDER")
  r.line:SetHeight(1)
  r.line:SetPoint("BOTTOMLEFT", 2, 0)
  r.line:SetPoint("BOTTOMRIGHT", -2, 0)
  local c = T.theme.frame or T.accent
  r.line:SetColorTexture(c[1], c[2], c[3], T.theme.frame and 0.5 or 0.3)
  -- A faint band behind a group heading (tinted in its colour), and a soft highlight on
  -- a spell under the mouse, so it's clear the rows can be hovered.
  r.band = r:CreateTexture(nil, "BACKGROUND")
  r.band:SetAllPoints()
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.05)
  r:SetScript("OnEnter", function(self)
    if not self.why then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local w = self.why
    GameTooltip:AddLine(self.spell, 1, 1, 1)
    -- The verdict in its group's colour, then short labelled sections (owner, October 6).
    local col = self.color or "ffffff"
    local r, g, b = tonumber(col:sub(1, 2), 16) / 255, tonumber(col:sub(3, 4), 16) / 255, tonumber(col:sub(5, 6), 16) / 255
    if w.verdict then GameTooltip:AddLine(w.verdict, r, g, b, true) end
    if w.reason then GameTooltip:AddLine(w.reason, 0.85, 0.85, 0.85, true) end
    if w.upgrade then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("When to upgrade", 1, 0.82, 0)
      GameTooltip:AddLine(w.upgrade, 0.8, 0.8, 0.8, true)
    end
    if w.notes and #w.notes > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Note", 1, 0.82, 0)
      for _, n in ipairs(w.notes) do GameTooltip:AddLine(n, 0.65, 0.65, 0.65, true) end
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.rows[i] = r
  return r
end

-- list: the trainer's services as RecipeBook.lua read them (name, state, cost, level).
function ns:ShowTrainingAdvice(list)
  if ns.db.settings.trainerAdvice == false or not T then return end   -- (no Theme in the tests)
  if (UnitLevel("player") or 0) >= 60 then return end   -- nothing left to level for (owner, October 6)
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
  -- Two short lines (the long one wrapped to three: owner's screenshot, October 6).
  panel.sub:SetText((total > 0 and ("All of it %s, recommended %s.\n"):format(ns.Money(total), ns.Money(cost.train)) or "Nothing new to learn at this level.\n")
    .. (tree and ("Levelling as %s (from your talents)."):format(tree) or "No talent points yet: spec spells are your choice."))
  local y, n = 0, 0
  for _, g in ipairs(GROUPS) do
    if #groups[g.key] > 0 then
      n = n + 1
      local h = row(n)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", 0, -y)
      h:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
      -- Group headings in the theme's heading font (serif on Gilded), in the group's colour.
      if T.theme.serif then h.text:SetFont(T.SERIF, 13, "") else T:Font(h.text, 12) end
      h.text:SetText(("|cff%s%s|r"):format(g.color, g.title))
      h.cost:SetText(ns.Money(cost[g.key]))
      h.why, h.spell = nil, nil
      h:SetHeight(20)
      h.line:Show()
      h.band:SetColorTexture(tonumber(g.color:sub(1, 2), 16) / 255, tonumber(g.color:sub(3, 4), 16) / 255, tonumber(g.color:sub(5, 6), 16) / 255, 0.07)
      h.band:Show()
      h.hl:Hide()
      h:Show()
      y = y + 24
      table.sort(groups[g.key], function(a, b) return a.s.name < b.s.name end)
      for _, e in ipairs(groups[g.key]) do
        n = n + 1
        local r = row(n)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 10, -y)
        r:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
        T:Font(r.text, 11)
        r:SetHeight(18)
        r.line:Hide()
        r.band:Hide()
        r.hl:Show()
        r.text:SetText(e.s.name .. "  |cff888888" .. e.tag .. "|r")
        r.cost:SetText(ns.Money(e.s.cost or 0))
        r.why, r.spell, r.color = e.why, e.s.name, g.color
        r:Show()
        y = y + 18
      end
      y = y + 4
    end
  end
  for i = n + 1, #panel.rows do panel.rows[i]:Hide() end
  -- As tall as the list needs, up to the trainer window's height; past that it scrolls
  -- (owner, October 6), and the footer says so.
  local trainer = _G.ClassTrainerFrame
  local maxH = math.max(260, (trainer and trainer:IsShown() and trainer:GetHeight()) or 440)
  local want = 74 + math.max(y, 20) + 32
  panel:SetHeight(math.min(want, maxH))
  panel.foot:SetText(want > maxH and "Scroll for more. Hover a spell for why." or "Hover a spell for why. Advice only.")
  panel.content:SetWidth(300 - 12 - 12)
  panel.content:SetHeight(math.max(y, 20))
  panel.sf:SetVerticalScroll(0)
  if panel.sf.UpdateScrollBar then panel.sf.UpdateScrollBar() end
  -- Beside Blizzard's trainer window when it's there.
  panel:ClearAllPoints()
  if trainer and trainer:IsShown() then
    panel:SetPoint("TOPLEFT", trainer, "TOPRIGHT", 4, 0)
  else
    panel:SetPoint("LEFT", UIParent, "CENTER", 120, 0)
  end
  panel:Show()
end

ns:On("TRAINER_CLOSED", function() if panel then panel:Hide() end end)
