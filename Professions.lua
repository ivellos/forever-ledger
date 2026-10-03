local _, ns = ...

local PROFESSIONS = {
  Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
  Leatherworking = true, Mining = true, Skinning = true, Tailoring = true,
  Cooking = true, Fishing = true, ["First Aid"] = true,
}

local function safe(fn, ...)
  if not fn then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

function ns:GetChar()
  local key = ns.CharKey()
  local c = ns.db.chars[key]
  if not c then c = { profs = {} }; ns.db.chars[key] = c end
  c.profs = c.profs or {}
  c.name = ns.FullName()
  c.realm = GetRealmName()
  c.class = select(2, UnitClass("player"))
  c.level = UnitLevel("player")
  c.faction = UnitFactionGroup("player")
  c.updated = time()
  return c
end

---------------------------------------------------------------------------
-- Which professions this character has, and their skill
---------------------------------------------------------------------------
function ns:ScanSkillLines()
  if not ns.db then return end
  local c = ns:GetChar()
  local found = {}

  if GetProfessions and GetProfessionInfo then
    local p1, p2, arch, fish, cook, aid = GetProfessions()
    for _, idx in ipairs({ p1 or false, p2 or false, arch or false, fish or false, cook or false, aid or false }) do
      if idx then
        local name, _, rank, maxRank = GetProfessionInfo(idx)
        if name then found[name] = { rank, maxRank } end
      end
    end
  end

  if not next(found) and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if name and not isHeader and PROFESSIONS[name] then found[name] = { rank, maxRank } end
    end
  end

  if not next(found) then
    ns:Debug("Couldn't read profession list yet.")
    return
  end
  local changed = false
  for name, v in pairs(found) do
    local p = c.profs[name] or { recipes = {} }
    p.recipes = p.recipes or {}
    if not c.profs[name] or p.rank ~= v[1] or p.max ~= v[2] then changed = true end
    p.rank, p.max, p.updated = v[1], v[2], time()
    c.profs[name] = p
  end
  -- Drop professions this character unlearned (for example Skinning after Ironforge).
  for name in pairs(c.profs) do
    if not found[name] then c.profs[name] = nil; changed = true end
  end
  -- Only redraw for a real change (this runs on every skill line update).
  if not changed then return end
  ns:BuildUsageIndex()
  ns:RefreshUI()
end

---------------------------------------------------------------------------
-- Recipes, captured whenever a profession window is open
---------------------------------------------------------------------------
function ns:ReadRecipe(id, info)
  local T = C_TradeSkillUI
  local rec = { n = info.name, d = info.relativeDifficulty, r = {} }
  local s = safe(T.GetRecipeSchematic, id, false)
  if type(s) == "table" then
    rec.out = s.outputItemID
    if s.quantityMin then rec.oq = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2 end
    local basicType = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
      local isBasic = slot.reagentType == nil or basicType == nil or slot.reagentType == basicType
      local r1 = slot.reagents and slot.reagents[1]
      if isBasic and r1 and r1.itemID then rec.r[#rec.r + 1] = { r1.itemID, slot.quantityRequired or 1 } end
    end
  else
    local n = safe(T.GetRecipeNumReagents, id) or 0
    for i = 1, n do
      local _, _, count = safe(T.GetRecipeReagentInfo, id, i)
      local rid = ns.ItemIDFromLink(safe(T.GetRecipeReagentItemLink, id, i))
      if rid then rec.r[#rec.r + 1] = { rid, count or 1 } end
    end
    rec.out = ns.ItemIDFromLink(safe(T.GetRecipeItemLink, id))
    local lo, hi = safe(T.GetRecipeNumItemsProduced, id)
    if lo then rec.oq = ((lo or 1) + (hi or lo or 1)) / 2 end
  end
  if rec.out then ns:RememberItem(rec.out) end
  for _, r in ipairs(rec.r) do ns:RememberItem(r[1]) end
  return rec
end

local lastCapture = {}   -- [profName] = what the last capture saw (skill, recipes learned)
function ns:CaptureTradeSkill()
  local T = C_TradeSkillUI
  if not T or not ns.db then return end
  -- Skip other players' linked profession windows.
  if safe(T.IsTradeSkillLinked) or safe(T.IsTradeSkillGuild) or safe(T.IsNPCCrafting) then return end

  local profName, rank, maxRank
  local base = safe(T.GetBaseProfessionInfo)
  if type(base) == "table" and base.professionName then
    profName, rank, maxRank = base.professionName, base.skillLevel, base.maxSkillLevel
  end
  if not profName then
    local _, name, r, m = safe(T.GetTradeSkillLine)
    profName, rank, maxRank = name, r, m
  end
  if not profName then ns:Debug("Couldn't read which profession is open."); return end

  local ids = safe(T.GetAllRecipeIDs)
  if type(ids) ~= "table" or #ids == 0 then return end

  local learned = {}
  for _, id in ipairs(ids) do
    local info = safe(T.GetRecipeInfo, id)
    if type(info) == "table" and info.learned then learned[#learned + 1] = { id, info } end
  end
  -- The game sends a list update after every craft (bags changed). Nothing to save then,
  -- and redrawing the window each time made the Deals tab stutter while crafting
  -- (/fl perf, October 3: 261 redraws in 7 minutes making Minor Wizard Oil).
  local sig = ("%s:%s:%s:%d"):format(profName, tostring(rank), tostring(maxRank), #learned)
  if lastCapture[profName] == sig then return end
  lastCapture[profName] = sig

  local c = ns:GetChar()
  local p = c.profs[profName] or { recipes = {} }
  c.profs[profName] = p
  p.recipes = {}
  if rank and rank > 0 then p.rank = rank end
  if maxRank and maxRank > 0 then p.max = maxRank end
  p.updated = time()

  local count = 0
  for _, l in ipairs(learned) do
    local rec = ns:ReadRecipe(l[1], l[2])
    if rec then p.recipes[l[1]] = rec; count = count + 1 end
  end
  p.recipeCount = count
  if ns.CaptureRecipeBook then ns:CaptureRecipeBook(profName) end
  if count ~= (p.lastAnnounced or -1) then
    ns:Print(("Saved %d %s recipes for %s."):format(count, profName, c.name or "?"))
    p.lastAnnounced = count
  end
  ns:BuildUsageIndex()
  ns:RefreshUI()
  if ns.SyncSoon then ns:SyncSoon() end
end

local pendingCapture = false
local function queueCapture()
  if pendingCapture then return end
  pendingCapture = true
  C_Timer.After(0.6, function()
    pendingCapture = false
    ns:CaptureTradeSkill()
  end)
end
ns:On("TRADE_SKILL_SHOW", queueCapture)
ns:On("TRADE_SKILL_LIST_UPDATE", queueCapture)
ns:On("TRADE_SKILL_DATA_SOURCE_CHANGED", queueCapture)

---------------------------------------------------------------------------
-- Which of your characters use each item
---------------------------------------------------------------------------
function ns:BuildUsageIndex()
  local usage, byReagent = {}, {}
  for key, c in pairs(ns.db.chars) do
    for prof, p in pairs(c.profs or {}) do
      for recipeID, rec in pairs(p.recipes or {}) do
        for _, r in ipairs(rec.r or {}) do
          local id = r[1]
          usage[id] = usage[id] or {}
          local k = (c.name or "?") .. "|" .. prof
          usage[id][k] = (usage[id][k] or 0) + 1
          byReagent[id] = byReagent[id] or {}
          table.insert(byReagent[id], { rec = rec, key = key, who = c.name, prof = prof, recipeID = recipeID })
        end
      end
    end
  end
  ns.usage = usage
  ns.recipesByReagent = byReagent
  if ns.InvalidateValues then ns:InvalidateValues() end
end

ns:OnReady(function() ns:BuildUsageIndex() end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, function() ns:ScanSkillLines() end) end)
ns:On("SKILL_LINES_CHANGED", function() C_Timer.After(0.5, function() ns:ScanSkillLines() end) end)
