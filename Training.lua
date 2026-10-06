local _, ns = ...

---------------------------------------------------------------------------
-- Training (owner, October 5): groundwork for "skip spell ranks you don't use" at the
-- class trainer, and the riding fund. Three things, all to be confirmed in the beta:
--  - What class and riding trainers teach, with cost and level, saved when a trainer
--    window is read (RecipeBook.lua reads it with every filter on and hands the list
--    here). /fl trainer shows the last one, to check names against the skip lists.
--  - Which spells each character casts (UNIT_SPELLCAST_SUCCEEDED, own unit only), by
--    name, with the last time: a rank of something never cast can be skipped.
--  - Riding: whether the character knows it (ns:RidingTier), and what training costs.
--
-- ns.db.trainers[class] = { t, npc, spells = { [name] = { [sub] = { cost, level } } } }
-- ns.db.riding = { [service name] = { cost, level, t } }
-- ns.db.casts[charKey] = { [spell name] = last time cast }
---------------------------------------------------------------------------
local lastRead   -- the last trainer read: { name, npc, prof, list }

local function isRiding(name) return name and name:find("Riding", 1, true) ~= nil end

function ns:TrainerRead(list, npc, npcID, prof)
  lastRead = { npc = npc, prof = prof, list = list, t = time() }
  ns.db.riding = ns.db.riding or {}
  local riding, spells = 0, {}
  for _, s in ipairs(list) do
    if isRiding(s.name) then
      ns.db.riding[s.name] = { cost = s.cost, level = s.level, t = time() }
      riding = riding + 1
    elseif not s.skill or s.skill == "" then
      -- No profession needed: a class spell (profession trainers' recipes name a skill).
      -- By level: Forever's second value is the spell's icon, not "Rank 2" (owner's
      -- /fl trainer, October 5), so ranks are counted from the levels (ns:SpellRanks).
      spells[s.name] = spells[s.name] or {}
      spells[s.name][s.level or 0] = s.cost or 0
    end
  end
  local n = 0
  for _ in pairs(spells) do n = n + 1 end
  -- A class trainer: more class spells than anything else and no profession.
  if n > 0 and not prof then
    local _, class = UnitClass("player")
    ns.db.trainers = ns.db.trainers or {}
    ns.db.trainers[class or "?"] = { t = time(), npc = npc, spells = spells }
    ns:Debug(("Training: %s teaches %d %s spells (%d services)."):format(npc or "?", n, class or "?", #list))
    if ns.ShowTrainingAdvice then ns:ShowTrainingAdvice(list) end
  end
  if riding > 0 then ns:Debug(("Training: %d riding services seen at %s."):format(riding, npc or "?")) end
end

-- Spells you cast, by name (ranks share a name): the last time each was cast.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" or not spellID then return end
  local name = ns.SpellName(spellID)
  if not name then return end
  ns.db.casts = ns.db.casts or {}
  local key = ns.CharKey()
  ns.db.casts[key] = ns.db.casts[key] or {}
  ns.db.casts[key][name] = time()
  -- When counting began for this character: "not cast lately" needs a week of counting.
  ns.db.castsSince = ns.db.castsSince or {}
  ns.db.castsSince[key] = ns.db.castsSince[key] or time()
end)

function ns:LastCast(name, key)
  local c = ns.db.casts and ns.db.casts[key or ns.CharKey()]
  return c and c[name]
end

-- Riding the character knows: 0 none, 1 riding, 2 epic riding. Tried several ways, as
-- Forever's client may keep riding as spells (modern) or as a skill (Classic); the
-- beta check (/fl api, "Riding") says which works.
local RIDING_SPELLS = { { 33388, 1 }, { 33391, 2 }, { 34090, 2 }, { 34091, 2 } }
function ns:RidingTier()
  local best = 0
  for _, r in ipairs(RIDING_SPELLS) do
    local ok, known = pcall(function()
      return (IsPlayerSpell and IsPlayerSpell(r[1])) or (IsSpellKnown and IsSpellKnown(r[1]))
    end)
    if ok and known and r[2] > best then best = r[2] end
  end
  if best > 0 then return best end
  -- The spellbook, by name (Forever has no Classic skill list: owner's /fl api, October 5).
  for _, name in ipairs(ns:SpellbookRiding()) do
    local tier = (name:find("Apprentice", 1, true) and 1) or 2
    if tier > best then best = tier end
  end
  if best > 0 then return best end
  -- Classic's skill list: "Riding" and the old per-mount skills (Horse Riding, Ram Riding...).
  if GetNumSkillLines and GetSkillLineInfo then
    local ok, n = pcall(GetNumSkillLines)
    for i = 1, (ok and n or 0) do
      local okI, name, _, _, rank = pcall(GetSkillLineInfo, i)
      if okI and isRiding(name) then
        local tier = (rank or 0) >= 150 and 2 or 1
        if tier > best then best = tier end
      end
    end
  end
  return best
end

-- Spells in the spellbook with "Riding" in their name: the modern spellbook, else the
-- older one. Empty when neither can be read.
function ns:SpellbookRiding()
  local found = {}
  local SB = C_SpellBook
  local ok = pcall(function()
    if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemName then
      local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
      for i = 1, SB.GetNumSpellBookSkillLines() or 0 do
        local info = SB.GetSpellBookSkillLineInfo(i)
        for j = (info and info.itemIndexOffset or 0) + 1, (info and (info.itemIndexOffset + info.numSpellBookItems) or 0) do
          local name = SB.GetSpellBookItemName(j, bank)
          if name and isRiding(name) then found[#found + 1] = name end
        end
      end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
      for i = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(i)
        for j = (offset or 0) + 1, (offset or 0) + (count or 0) do
          local name = GetSpellBookItemName(j, BOOKTYPE_SPELL or "spell")
          if name and isRiding(name) then found[#found + 1] = name end
        end
      end
    end
  end)
  return ok and found or {}
end

-- The spells you know, by name, with the highest rank number the spellbook shows ("Rank 3"
-- under the name; 0 when it shows none). The trainer list in Forever only goes back to
-- about level 20, so the ranks you know come from here (owner's screenshot, October 5:
-- the panel said "rank 1" for Frostbolt, really rank 4).
function ns:KnownSpellRanks()
  local known = {}
  local function add(name, sub)
    if not name then return end
    local r = tonumber(type(sub) == "string" and sub:match("(%d+)") or "") or 0
    known[name] = math.max(known[name] or 0, r)
  end
  local SB = C_SpellBook
  pcall(function()
    if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemName then
      local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
      for i = 1, SB.GetNumSpellBookSkillLines() or 0 do
        local info = SB.GetSpellBookSkillLineInfo(i)
        for j = (info and info.itemIndexOffset or 0) + 1, (info and (info.itemIndexOffset + info.numSpellBookItems) or 0) do
          add(SB.GetSpellBookItemName(j, bank))
        end
      end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
      for i = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(i)
        for j = (offset or 0) + 1, (offset or 0) + (count or 0) do add(GetSpellBookItemName(j, BOOKTYPE_SPELL or "spell")) end
      end
    end
  end)
  return known
end

-- For /fl api: what each way of telling says.
function ns:RidingReport()
  local parts = {}
  for _, r in ipairs(RIDING_SPELLS) do
    local ok, a, b = pcall(function()
      return IsPlayerSpell and IsPlayerSpell(r[1]), IsSpellKnown and IsSpellKnown(r[1])
    end)
    parts[#parts + 1] = ("%d %s/%s"):format(r[1], ok and tostring(a) or "err", ok and tostring(b) or "err")
  end
  local book = ns:SpellbookRiding()
  return ("tier %d; spells (player/known): %s; spellbook: %s"):format(ns:RidingTier(), table.concat(parts, ", "),
    #book > 0 and table.concat(book, ", ") or "no Riding spell")
end

-- Talents (to tell which tree a character levels in): name and points per tab. Forever
-- has no Classic talent functions (owner's /fl api, October 5), so the newer ones are
-- tried and reported too.
function ns:TalentReport()
  if not GetNumTalentTabs then
    local parts = {}
    local function try(label, fn)
      local ok, a, b = pcall(fn)
      parts[#parts + 1] = ("%s=%s"):format(label, ok and (tostring(a) .. (b ~= nil and ("/" .. tostring(b)) or "")) or "err")
    end
    try("GetSpecialization", function() return GetSpecialization and GetSpecialization() end)
    try("C_SpecializationInfo", function() return C_SpecializationInfo ~= nil, C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization() end)
    try("C_ClassTalents.GetActiveConfigID", function() return C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() end)
    try("C_Traits", function() return C_Traits ~= nil end)
    try("C_Talent", function() return C_Talent ~= nil end)
    try("GetNumTalents", function() return GetNumTalents and GetNumTalents() end)
    try("GetActiveTalentGroup", function() return GetActiveTalentGroup and GetActiveTalentGroup() end)
    try("UnitCharacterPoints", function() return UnitCharacterPoints and UnitCharacterPoints("player") end)
    return "no GetNumTalentTabs; " .. table.concat(parts, ", ")
  end
  local ok, n = pcall(GetNumTalentTabs)
  if not ok then return "GetNumTalentTabs error" end
  local parts = {}
  for i = 1, (n or 0) do
    local okT, a, b, c, d, e = pcall(GetTalentTabInfo, i)
    -- Classic: name, icon, pointsSpent, fileName; later clients: id, name, desc, icon, points.
    if okT then
      local name = type(a) == "string" and a or b
      local points = type(c) == "number" and c or e
      parts[#parts + 1] = ("%s %s"):format(tostring(name), tostring(points))
    else
      parts[#parts + 1] = "tab " .. i .. " error"
    end
  end
  return ("%d tabs: %s"):format(n or 0, table.concat(parts, ", "))
end

-- /fl trainer: the last trainer read this session, every service with its state, rank,
-- cost and level, to check against the skip lists and see riding costs.
function ns:PrintTrainer()
  if not lastRead then
    ns:Print("Open a trainer first (class or riding); then /fl trainer lists what it teaches.")
    return
  end
  -- One line per spell, its ranks as "level cost" (owner, October 5: one line per rank
  -- was too long for chat), * on ranks you can learn now, + on ones you know.
  ns:Print(("%s (%s), %d services:"):format(lastRead.npc or "?", lastRead.prof or "class or riding", #lastRead.list))
  local order, by = {}, {}
  for _, s in ipairs(lastRead.list) do
    if not by[s.name] then by[s.name] = {}; order[#order + 1] = s.name end
    table.insert(by[s.name], s)
  end
  for _, name in ipairs(order) do
    local list = by[name]
    table.sort(list, function(a, b) return (a.level or 0) < (b.level or 0) end)
    local parts = {}
    for _, s in ipairs(list) do
      local mark = (s.state == "available" and "*") or (s.state == "used" and "+") or ""
      parts[#parts + 1] = ("%s%s %s"):format(mark, tostring(s.level or "?"), s.cost and ns.MoneyPlain(s.cost) or "?")
    end
    print(("  %s: %s"):format(name, table.concat(parts, ", ")))
  end
  print("  (* you can learn it now, + you know it)")
  -- Where Forever keeps the rank (Blizzard's window shows "Rank 4"; the list gives the
  -- state and icon): every value of the first service, and the spellbook's rank text.
  if GetTrainerServiceInfo and GetNumTrainerServices and (GetNumTrainerServices() or 0) > 0 then
    local vals = { pcall(GetTrainerServiceInfo, 1) }
    local parts = {}
    for i = 2, #vals do parts[#parts + 1] = tostring(vals[i]) end
    print("  First service, every value: " .. table.concat(parts, " | "))
    local ok, desc = pcall(function() return GetTrainerServiceDescription and GetTrainerServiceDescription(1) end)
    if ok and desc then print("  Its description: " .. tostring(desc):sub(1, 120)) end
  end
  local book = ns:KnownSpellRanks()
  local n, sample = 0, {}
  for name, r in pairs(book) do
    n = n + 1
    if #sample < 6 then sample[#sample + 1] = name .. " " .. r end
  end
  print(("  Spellbook: %d spells; ranks read: %s"):format(n, table.concat(sample, ", ")))
end

-- A spell's ranks at the trainer, lowest level first: { { level, cost }, ... }.
function ns:SpellRanks(name, class)
  local t = ns.db.trainers and ns.db.trainers[class or select(2, UnitClass("player")) or "?"]
  local ranks = {}
  for level, cost in pairs(t and t.spells[name] or {}) do ranks[#ranks + 1] = { level = level, cost = cost } end
  table.sort(ranks, function(a, b) return a.level < b.level end)
  return ranks
end

---------------------------------------------------------------------------
-- Riding fund (Dashboard.lua): the next riding this character doesn't know, what it
-- costs (as seen at a riding trainer, else the beta's reported price, marked "about"),
-- and the gold and pace from the Dashboard's own numbers. nil when it shouldn't show:
-- switched off (Settings, Global settings, Advanced), hidden on this character (Hide
-- here; /fl fund brings it back), or the character knows epic riding.
---------------------------------------------------------------------------
-- Training as seen in the beta (owner, October 5, Binjy Featherwhistle: Apprentice
-- Riding 90g at 40, Journeyman Riding 900g at 60), plus a mount: about a ninth of the
-- training (owner's estimate: 10g and 100g; mounts are per character, so each needs
-- its own). The fund is the two together: 100g, then 1,000g.
local RIDING_GUESS = {
  { name = "Apprentice Riding", short = "Riding at 40", level = 40, training = 900000, mount = 100000, match = "Apprentice" },
  { name = "Journeyman Riding", short = "Epic riding at 60", level = 60, training = 9000000, mount = 1000000, match = "Journeyman" },
}
function ns:RidingFund(goldNow, totals, goldFirst)
  if ns.db.settings.ridingFund == false then return end
  local c = ns.db.chars[ns.CharKey()]
  if c and c.noRidingFund then return end
  local tier = ns:RidingTier()
  local want = RIDING_GUESS[tier + 1]
  if not want then return end
  local out = { name = want.name, short = want.short, level = want.level, training = want.training,
    mount = want.mount, seen = false }
  -- Seen at a riding trainer: the service whose name says its tier (Apprentice Riding...).
  for svc, r in pairs(ns.db.riding or {}) do
    if svc:find(want.match, 1, true) and r.cost then
      out.training, out.seen, out.name = r.cost, true, svc
      if r.level and r.level > 0 then out.level = r.level end
    end
  end
  out.cost = out.training + out.mount
  out.gold = goldNow or GetMoney()
  if goldNow and goldFirst and totals and totals.days and totals.days > 0 then
    out.perDay = (goldNow - goldFirst) / totals.days
  end
  return out
end

function ns:FundCommand()
  local c = ns.db.chars[ns.CharKey()]
  if c then c.noRidingFund = nil end
  if ns.db.settings.ridingFund == false then
    ns:Print("The riding fund is switched off everywhere: Settings, Global settings, Advanced.")
  else
    ns:Print("Riding fund shown on this character's Dashboard again.")
  end
  ns:RefreshUI()
end

---------------------------------------------------------------------------
-- /fl talents: how Forever's talents read (owner's /fl api, October 5: no Classic talent
-- functions; C_ClassTalents and C_Traits exist, config 1041811, C_SpecializationInfo
-- says 1). Prints the config, its trees, and the talents with points in them (by spell
-- name), so the tree a character levels in can be worked out. Everything in pcall.
---------------------------------------------------------------------------
function ns:TalentProbe()
  local function try(fn) local ok, a, b, c = pcall(fn); if ok then return a, b, c end end
  ns:Print("Talents (send this to Claude):")
  local configID = try(function() return C_ClassTalents.GetActiveConfigID() end)
  print("  Active config: " .. tostring(configID))
  local spec = try(function() return C_SpecializationInfo.GetSpecialization() end)
  print("  Specialization: " .. tostring(spec))
  for i = 1, 3 do
    local a, b, c = try(function() return C_SpecializationInfo.GetSpecializationInfo(i) end)
    if a or b then print(("  Spec %d: %s, %s, %s"):format(i, tostring(a), tostring(b), tostring(c))) end
  end
  local thirds = ns.TalentThirds and ns:TalentThirds()
  if thirds then
    print(("  Points by tree: %s %d, %s %d, %s %d; levelling as: %s"):format(thirds.names[1], thirds.points[1],
      thirds.names[2], thirds.points[2], thirds.names[3], thirds.points[3], tostring(ns:LevellingTree())))
  end
  if not (configID and C_Traits) then return end
  local info = try(function() return C_Traits.GetConfigInfo(configID) end)
  local trees = info and info.treeIDs or {}
  print(("  Config: type %s, name %s, %d trees"):format(tostring(info and info.type), tostring(info and info.name), #trees))
  for _, treeID in ipairs(trees) do
    local nodes = try(function() return C_Traits.GetTreeNodes(treeID) end) or {}
    local picked, xs = {}, {}
    for _, nodeID in ipairs(nodes) do
      local node = try(function() return C_Traits.GetNodeInfo(configID, nodeID) end)
      if node then
        xs[#xs + 1] = node.posX
        if (node.ranksPurchased or node.activeRank or 0) > 0 then
          local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
          local entry = entryID and try(function() return C_Traits.GetEntryInfo(configID, entryID) end)
          local def = entry and entry.definitionID and try(function() return C_Traits.GetDefinitionInfo(entry.definitionID) end)
          local name = def and (def.overrideName or (def.spellID and ns.SpellName(def.spellID)))
          picked[#picked + 1] = ("%s %d (x %s, y %s)"):format(tostring(name or nodeID), node.ranksPurchased or node.activeRank or 0,
            tostring(node.posX), tostring(node.posY))
        end
      end
    end
    table.sort(xs)
    print(("  Tree %s: %d nodes, x from %s to %s; with points: %s"):format(tostring(treeID), #nodes, tostring(xs[1]),
      tostring(xs[#xs]), #picked > 0 and table.concat(picked, "; ") or "none"))
  end
end

---------------------------------------------------------------------------
-- Which tree a character levels in. Forever has one talent tree per class (owner's
-- /fl talents, October 5: Mage, tree 1112, 54 talents, x 1020 to 10880), with Classic's
-- three trees side by side, in Classic's order left to right: a Mage's Frost talents
-- were on the right (x 9080 to 10280). So: thirds of the x range, the most points wins.
-- Classic's order per class; to be confirmed for the other classes.
---------------------------------------------------------------------------
local TREES = {
  MAGE = { "Arcane", "Fire", "Frost" }, WARRIOR = { "Arms", "Fury", "Protection" },
  PALADIN = { "Holy", "Protection", "Retribution" }, PRIEST = { "Discipline", "Holy", "Shadow" },
  ROGUE = { "Assassination", "Combat", "Subtlety" }, HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
  WARLOCK = { "Affliction", "Demonology", "Destruction" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
  DRUID = { "Balance", "Feral Combat", "Restoration" },
}

-- { names, points = { a, b, c } } or nil when talents can't be read.
function ns:TalentThirds()
  local ok, result = pcall(function()
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    local info = configID and C_Traits and C_Traits.GetConfigInfo(configID)
    local treeID = info and info.treeIDs and info.treeIDs[1]
    if not treeID then return end
    local nodes, minX, maxX = {}, nil, nil
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      if node and node.posX then
        nodes[#nodes + 1] = node
        minX, maxX = math.min(minX or node.posX, node.posX), math.max(maxX or node.posX, node.posX)
      end
    end
    if #nodes == 0 or maxX == minX then return end
    local points = { 0, 0, 0 }
    for _, node in ipairs(nodes) do
      local spent = node.ranksPurchased or node.activeRank or 0
      if spent > 0 then
        local third = math.min(3, math.floor((node.posX - minX) / (maxX - minX) * 3) + 1)
        points[third] = points[third] + spent
      end
    end
    local _, class = UnitClass("player")
    return { names = TREES[class or ""] or { "Left", "Middle", "Right" }, points = points }
  end)
  return ok and result or nil
end

-- The tree with the most points ("Frost"), or nil with no points spent. A choice made
-- for the character (c.levelTree, Settings later) wins.
function ns:LevellingTree(key)
  local c = ns.db.chars[key or ns.CharKey()]
  if c and c.levelTree then return c.levelTree end
  if key and key ~= ns.CharKey() then return c and c.tree end
  local t = ns:TalentThirds()
  if not t then return c and c.tree end
  local best, most = nil, 0
  for i, p in ipairs(t.points) do if p > most then best, most = t.names[i], p end end
  if c then c.tree = best end
  return best
end
