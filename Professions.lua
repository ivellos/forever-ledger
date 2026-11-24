local _, ns = ...

local PROFESSIONS = {
  Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
  Leatherworking = true, Mining = true, Skinning = true, Tailoring = true,
  Cooking = true, Fishing = true, ["First Aid"] = true,
}

-- Professions are saved under their English name, found from the game's skill line ID,
-- so a German or Russian client keys them the same as the recipe data ("Enchanting", not
-- "Verzauberkunst"). The game's own names are remembered account-wide (profAliases), so
-- entries saved under them, yours or a partner's from sync, move to the English key.
local SKILL_LINES = {
  [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
  [182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning",
  [197] = "Tailoring", [185] = "Cooking", [356] = "Fishing", [129] = "First Aid",
}
ns.PROFESSION_SKILL_LINES = SKILL_LINES
local function aliases()
  if ns.db then
    ns.db.profAliases = ns.db.profAliases or {}
    return ns.db.profAliases
  end
  ns.profAliasesEarly = ns.profAliasesEarly or {}
  return ns.profAliasesEarly
end
function ns.ProfessionKey(name, skillLine)
  local en = skillLine and SKILL_LINES[skillLine]
  local known = aliases()
  if en then
    if type(name) == "string" and name ~= en and known[name] ~= en then
      known[name] = en
      if ns.AddLocaleText then ns.AddLocaleText(en, name) end
      if ns.db and ns.NormalizeProfessions then ns.NormalizeProfessions(ns.db) end
    end
    return en
  end
  if name and known[name] then return known[name] end
  return name
end

-- Two saved entries for one profession become one, losing nothing (Codex review, November
-- 19: keeping the English one whole dropped newer recipes saved under the game's name).
-- Every recipe of both is kept; where both have one, the newer entry's wins, and the newer
-- entry's rank, max and time win too.
function ns.MergeProfession(a, b)
  if not a then return b end
  if not b then return a end
  local newer, older = a, b
  if (b.updated or 0) > (a.updated or 0) then newer, older = b, a end
  local out = {}
  for k, v in pairs(older) do out[k] = v end
  for k, v in pairs(newer) do out[k] = v end
  local recipes, n = {}, 0
  for id, r in pairs(older.recipes or {}) do recipes[id] = r end
  for id, r in pairs(newer.recipes or {}) do recipes[id] = r end
  for _ in pairs(recipes) do n = n + 1 end
  out.recipes = recipes
  if out.recipeCount then out.recipeCount = math.max(out.recipeCount, n) end
  return out
end
-- An entry saved under the game's own name moves to the English key, merged with any
-- entry already there. True if anything changed.
function ns.MoveProfessionKey(profs, name, key)
  if not profs or not name or not key or name == key or not profs[name] then return false end
  profs[key] = ns.MergeProfession(profs[key], profs[name])
  profs[name] = nil
  return true
end
-- Every character's professions under the English keys the game's names are known for.
-- Names not known yet stay as they are (never dropped). True if anything moved.
function ns.NormalizeProfessions(db)
  local known = db and db.profAliases
  if not known or not next(known) then return false end
  local changed = false
  for _, c in pairs(db.chars or {}) do
    local move = {}   -- (collected first: adding keys while walking a table isn't safe)
    for name in pairs(c.profs or {}) do if known[name] then move[#move + 1] = name end end
    for _, name in ipairs(move) do
      if ns.MoveProfessionKey(c.profs, name, known[name]) then changed = true end
    end
  end
  local books, move = db.recipeBook or {}, {}
  for name in pairs(books) do if known[name] and known[name] ~= name then move[#move + 1] = name end end
  for _, name in ipairs(move) do
    local book = books[known[name]] or {}
    for id, recipe in pairs(books[name]) do if book[id] == nil then book[id] = recipe end end
    books[known[name]], books[name] = book, nil
  end
  if #move > 0 then
    ns.recipeBookStamp = (ns.recipeBookStamp or 0) + 1
    changed = true
  end
  if changed and ns.BuildUsageIndex and ns.usage then ns:BuildUsageIndex() end
  return changed
end

-- At login: the game's names for every profession it will tell (not only this character's),
-- then every saved entry under one of them moves to its English key.
ns:OnReady(function()
  for name, en in pairs(ns.profAliasesEarly or {}) do ns.db.profAliases[name] = ns.db.profAliases[name] or en end
  local get = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
  if get then
    for line in pairs(SKILL_LINES) do
      local ok, info = pcall(get, line)
      if ok and type(info) == "table" and type(info.professionName) == "string" and info.professionName ~= "" then
        ns.ProfessionKey(info.professionName, line)
      end
    end
  end
  ns.NormalizeProfessions(ns.db)
end)

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
  c.realm = ns.RealmName()
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
  local found, moved = {}, false

  if GetProfessions and GetProfessionInfo then
    local p1, p2, arch, fish, cook, aid = GetProfessions()
    for _, idx in ipairs({ p1 or false, p2 or false, arch or false, fish or false, cook or false, aid or false }) do
      if idx then
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
        if name then
          local key = ns.ProfessionKey(name, skillLine)
          if ns.MoveProfessionKey(c.profs, name, key) then moved = true end
          found[key] = { rank, maxRank }
        end
      end
    end
  end

  if not next(found) and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      local key = name and ns.ProfessionKey(name)
      if key and not isHeader and PROFESSIONS[key] then found[key] = { rank, maxRank } end
    end
  end

  if not next(found) then
    ns:Debug("Couldn't read profession list yet.")
    return
  end
  local changed = moved
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
    local line = SKILL_LINES[base.professionID or 0] and base.professionID or base.parentProfessionID
    local key = ns.ProfessionKey(profName, line)
    if key ~= profName then ns.MoveProfessionKey(ns:GetChar().profs, profName, key) end
    profName = key
  end
  if not profName then
    local _, name, r, m = safe(T.GetTradeSkillLine)
    profName, rank, maxRank = name and ns.ProfessionKey(name), r, m
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
-- What the index and values were last built from, to tell whether anything changed: each
-- counted character's name, each profession's rank (Enchanting's sets disenchanting) and
-- each recipe's contents. Checked without making anything (Frank's twentieth /fl perf,
-- November 22: the index was rebuilt at every loading screen and threw every value away
-- each time, so Gold making worked out all 7,000 values again).
-- Each recipe is compared on its own, not as part of a sum (Codex reviews, November 22: two
-- recipes' changes could cancel out in any added-up number, as two real Blacksmithing
-- recipes showed).
local P = 2147483629   -- (a prime under 2^31: h * 257 + x stays exact in a double)
local function mix(h, x) return (h * 257 + (x or 0)) % P end
local function mixText(h, s)
  if type(s) ~= "string" then return mix(h, 1) end
  for i = 1, #s do h = mix(h, s:byte(i)) end
  return mix(h, 2)
end
-- One recipe's contents in order: its name, output, output count, each material and count.
local function recipeHash(rec)
  local h = mix(mix(7, tonumber(rec.out) or 0), math.floor((tonumber(rec.oq) or 1) * 1000))
  h = mixText(h, rec.n)
  for _, r in ipairs(rec.r or {}) do h = mix(mix(h, tonumber(r[1]) or 0), math.floor((tonumber(r[2]) or 0) * 1000)) end
  return mix(h, #(rec.r or {}))
end
local built   -- [charKey] = { name, n = professions, profs = { [prof] = { rank, n = recipes, recipes = { [id] = hash } } } }; n = characters
local function sameAsBuilt()
  if not built then return false end
  local chars = 0
  for key, c in pairs(ns.db.chars) do
    if ns:SameMarketChar(key) then
      chars = chars + 1
      local b = built[key]
      if not b or b.name ~= c.name then return false end
      local profs = 0
      for prof, p in pairs(c.profs or {}) do
        profs = profs + 1
        local bp = b.profs[prof]
        if not bp or bp.rank ~= p.rank then return false end
        local count = 0
        for recipeID, rec in pairs(p.recipes or {}) do
          count = count + 1
          if bp.recipes[recipeID] ~= recipeHash(rec) then return false end
        end
        if count ~= bp.n then return false end
      end
      if profs ~= b.n then return false end
    end
  end
  return chars == built.n
end
local function rememberBuilt()
  local out = { n = 0 }
  for key, c in pairs(ns.db.chars) do
    if ns:SameMarketChar(key) then
      out.n = out.n + 1
      local b = { name = c.name, n = 0, profs = {} }
      for prof, p in pairs(c.profs or {}) do
        b.n = b.n + 1
        local bp = { rank = p.rank, n = 0, recipes = {} }
        for recipeID, rec in pairs(p.recipes or {}) do
          bp.n = bp.n + 1
          bp.recipes[recipeID] = recipeHash(rec)
        end
        b.profs[prof] = bp
      end
      out[key] = b
    end
  end
  built = out
end
-- Rebuilt only when what it's made from changed (then every value goes, as before).
function ns:BuildUsageIndex()
  if ns.usage and sameAsBuilt() then return end
  rememberBuilt()
  local usage, byReagent = {}, {}
  -- Only characters who could craft for you: same ruleset and faction (Core.lua).
  for key, c in pairs(ns.db.chars) do
    for prof, p in pairs(ns:SameMarketChar(key) and c.profs or {}) do
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
-- Again once the character's realm and faction are surely known (the index is per ruleset).
ns:On("PLAYER_ENTERING_WORLD", function() ns:BuildUsageIndex() end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, function() ns:ScanSkillLines() end) end)
ns:On("SKILL_LINES_CHANGED", function() C_Timer.After(0.5, function() ns:ScanSkillLines() end) end)
