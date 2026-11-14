local _, ns = ...

---------------------------------------------------------------------------
-- Recipe book, part 1: record every recipe of each profession (learned or not),
-- and where recipes come from as they're seen in game: vendors (with position for
-- map pins), trainers, and drops. Forever gives no source text for recipes, so
-- sources come from what's seen, and later a data file (Classic / Forever database
-- entries, marked unconfirmed until seen in game).
--
-- recipeBook[profession][recipeID] = { n = name, out = itemID, oq, r = { {itemID, qty} } }
-- recipeSources[recipe name lowercased] = { [key] = { kind, conf, npc, npcID, mapID, x, y,
--   cost, currency, skill, limited, zone, t } }   (key = kind .. npcID, so each is kept once)
-- vendors[npcID] = { name, mapID, x, y, zone, t }
---------------------------------------------------------------------------
local PREFIXES = { "Formula", "Pattern", "Recipe", "Plans", "Schematic", "Manual", "Design", "Technique" }

-- "Formula: Enchant Bracer - Minor Health" -> "enchant bracer - minor health"
local function recipeNameFromItem(itemName)
  if not itemName then return end
  for _, p in ipairs(PREFIXES) do
    local rest = itemName:match("^" .. p .. ":%s*(.+)$")
    if rest then return rest:lower() end
  end
end

local function npcInfo(unit)
  local guid = UnitGUID(unit)
  local npcID = guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
  local first, last = UnitName(unit)
  local name = (first and last and last ~= "") and (first .. " " .. last) or first
  return npcID, name
end

local function here()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local x, y
  if mapID and C_Map.GetPlayerMapPosition then
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos and pos.GetXY then x, y = pos:GetXY() end
  end
  local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  return mapID, x, y, info and info.name or GetZoneText()
end

local function addSource(recipeName, s)
  if not recipeName then return end
  local list = ns.db.recipeSources[recipeName] or {}
  ns.db.recipeSources[recipeName] = list
  s.conf, s.t = "seen", time()
  list[s.kind .. (s.npcID or s.npc or "?")] = s
end

---------------------------------------------------------------------------
-- Every recipe of an open profession
---------------------------------------------------------------------------
-- The game's list for a profession window can still hold the recipes of a window opened
-- before it (Frank's All professions list, November 13: a new character's Skinning window
-- listed 768 Tailoring, Enchanting, First Aid and Fishing recipes beside Skinning's own 3,
-- so they showed twice). Which profession a recipe belongs to comes from evidence, never
-- from which book is smaller (Codex review of c4dd71a: the smaller book can be the wrong
-- one, and its copy can be the less complete one):
--   - a character of yours knows it under that profession (profiles keep only learned
--     recipes);
--   - Classic's data says that profession makes its item (ClassicCrafts.lua, Classic crafts
--     only; an item two professions make names both);
--   - one book holds another's whole list besides its own: the recipes they share are the
--     other's. Only for a list of at least 3 (every profession has its camping recipes),
--     so a book with one or two stray recipes proves nothing. Used only when the first
--     two say nothing.
-- When the evidence names one of the professions a recipe is saved under, that book keeps
-- it, with anything only the other copy had; when it names none or several, every copy
-- stays.
local MIN_LIST = 3

-- [recipeID] = { [profession] = true } from every character's learned recipes.
local function learnedIndex()
  local idx = {}
  for _, c in pairs(ns.db.chars or {}) do
    for prof, p in pairs(c.profs or {}) do
      for id in pairs(p.recipes or {}) do
        local t = idx[id]
        if not t then t = {}; idx[id] = t end
        t[prof] = true
      end
    end
  end
  return idx
end

-- { [profession] = true } that make an item in Classic's data, or nil.
local makers, makersFrom
local function classicMakers(out)
  local list = ns.CLASSIC_CRAFT_LIST
  if not (out and list) then return nil end
  if makersFrom ~= list then
    makers, makersFrom = {}, list
    for _, c in ipairs(list) do
      local t = makers[c[3]]
      if not t then t = {}; makers[c[3]] = t end
      t[c[1]] = true
    end
  end
  return makers[out]
end

-- Is every recipe of book a also in b (a table of recipe IDs)?
local function within(a, b)
  for id in pairs(a) do
    if not b[id] then return false end
  end
  return true
end

-- The professions the learned recipes and Classic's data point to (only those in `among`,
-- if given): each is added to `named`.
local function nameFromFacts(id, out, among, learned, named)
  for p in pairs(learned[id] or {}) do
    if not among or among[p] then named[p] = true end
  end
  for p in pairs(classicMakers(out) or {}) do
    if not among or among[p] then named[p] = true end
  end
end

-- The one key of a table, or nil if it has none or several.
local function onlyKey(t)
  local k = next(t)
  if k ~= nil and next(t, k) == nil then return k end
end

function ns:CaptureRecipeBook(profName)
  local TS = C_TradeSkillUI
  if not (TS and TS.GetAllRecipeIDs and profName) then return end
  local books = ns.db.recipeBook
  local book = books[profName] or {}
  books[profName] = book
  local ids = TS.GetAllRecipeIDs() or {}
  local inList = {}
  for _, id in ipairs(ids) do inList[id] = true end
  -- Books whose whole list (3 or more, as in the cleanup below: one or two stray recipes
  -- prove nothing) is in this window: their recipes here are leftovers.
  local leftover = {}
  for prof, b in pairs(books) do
    if prof ~= profName and next(b) and within(b, inList) then
      local n = 0
      for _ in pairs(b) do n = n + 1 end
      if n >= MIN_LIST then leftover[prof] = true end
    end
  end
  local learned = learnedIndex()
  local added, shared = 0, false
  for _, id in ipairs(ids) do
    if not book[id] then
      local holders, skip, out = {}, false, nil
      for prof, b in pairs(books) do
        if prof ~= profName and b[id] then
          holders[#holders + 1] = prof
          if leftover[prof] then skip = true end
          if type(b[id]) == "table" and b[id].out then out = b[id].out end
        end
      end
      -- The facts outweigh the leftover test when they name one profession: this one, it's
      -- this book's; another, it isn't. The item it makes comes from a saved copy, or from
      -- reading the recipe when no copy has it (Codex review of b7c7eb2: a leftover was
      -- skipped before Classic's data could say it was this profession's).
      local rec
      if not skip or not out then
        local ok, info = pcall(TS.GetRecipeInfo, id)
        if ok and type(info) == "table" and info.name then
          rec = ns:ReadRecipe(id, info)
          out = out or rec.out
        end
      end
      local named = {}
      nameFromFacts(id, out, nil, learned, named)
      local only = onlyKey(named)
      if only == profName then skip = false elseif only then skip = true end
      if not skip and not rec then
        local ok, info = pcall(TS.GetRecipeInfo, id)
        if ok and type(info) == "table" and info.name then rec = ns:ReadRecipe(id, info) end
      end
      if not skip and rec then
        book[id] = { n = rec.n, out = rec.out, oq = rec.oq, r = rec.r }
        added = added + 1
        if #holders > 0 then shared = true end
      end
    end
  end
  if added > 0 then ns:Debug("Recipe book:", added, "new", profName, "recipes recorded") end
  -- Saved under another profession too: the evidence decides where it stays.
  if shared then ns:CleanRecipeBook() end
end

-- Recipes saved under more than one profession, by the mix-up above (an older version saved
-- them all) or added while it couldn't be told: each goes to the profession the evidence
-- names, with anything only another copy had; the rest stay where they are. Run at every
-- login (cheap), so a book mixed up by an older version is put right. Returns how many
-- copies were removed and how many recipes stay in more than one book.
function ns:CleanRecipeBook()
  local books = ns.db.recipeBook or {}
  local where, shared = {}, false
  for prof, book in pairs(books) do
    for id in pairs(book) do
      local t = where[id]
      if t then shared = true else t = {}; where[id] = t end
      t[#t + 1] = prof
    end
  end
  if not shared then return 0, 0 end
  local learned = learnedIndex()
  local count, inside = {}, {}
  local function holdsAll(a, b)    -- b holds a's whole list (worked out before any change)
    local row = inside[a]
    if not row then row = {}; inside[a] = row end
    if row[b] == nil then row[b] = within(books[a], books[b]) end
    return row[b]
  end
  local function size(p)
    if not count[p] then
      local n = 0
      for _ in pairs(books[p]) do n = n + 1 end
      count[p] = n
    end
    return count[p]
  end
  -- Decide everything first, then change the books (a removal would change what holds what).
  local owners, unsure = {}, 0
  for id, profs in pairs(where) do
    if #profs > 1 then
      local among, named = {}, {}
      for _, p in ipairs(profs) do among[p] = true end
      for _, p in ipairs(profs) do nameFromFacts(id, type(books[p][id]) == "table" and books[p][id].out, among, learned, named) end
      -- The facts first (as when a window opens); which book holds which only when they
      -- say nothing.
      if not next(named) then
        for _, a in ipairs(profs) do
          for _, b in ipairs(profs) do
            if a ~= b and size(a) >= MIN_LIST and holdsAll(a, b) and not holdsAll(b, a) then named[a] = true end
          end
        end
      end
      local owner = onlyKey(named)
      if owner then owners[id] = owner else unsure = unsure + 1 end
    end
  end
  local removed = 0
  for id, owner in pairs(owners) do
    local keep = books[owner][id]
    for _, p in ipairs(where[id]) do
      if p ~= owner then
        if type(keep) == "table" and type(books[p][id]) == "table" then
          for k, v in pairs(books[p][id]) do
            local mine = keep[k]
            if mine == nil or (type(mine) == "table" and next(mine) == nil) then keep[k] = v end
          end
        end
        books[p][id] = nil
        removed = removed + 1
      end
    end
  end
  if removed > 0 then ns:Debug("Recipe book:", removed, "recipes saved under two professions put right") end
  if unsure > 0 then ns:Debug("Recipe book:", unsure, "recipes saved under two professions kept in both (can't tell whose)") end
  return removed, unsure
end
ns:OnReady(function() ns:CleanRecipeBook() end)

---------------------------------------------------------------------------
-- Vendors: recipes they sell, and where they stand
---------------------------------------------------------------------------
local function captureVendor()
  if not (GetMerchantNumItems and C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return end
  local npcID, name = npcInfo("npc")
  if not npcID then return end
  local mapID, x, y, zone = here()
  ns.db.vendors[npcID] = { name = name, mapID = mapID, x = x, y = y, zone = zone, t = time() }
  local found = 0
  for i = 1, GetMerchantNumItems() do
    local id = GetMerchantItemID and GetMerchantItemID(i)
    local info = C_MerchantFrame.GetItemInfo(i)
    local itemName = (id and ns.GetItemInfo(id)) or (info and info.name)
    local recipe = recipeNameFromItem(itemName)
    if recipe and info then
      local cost, currency = info.price, nil
      if info.hasExtendedCost and GetMerchantItemCostItem then
        local _, value, _, currencyName = GetMerchantItemCostItem(i, 1)
        currency = value and ("%s %s"):format(value, currencyName or "")
      end
      addSource(recipe, { kind = "vendor", npc = name, npcID = npcID, mapID = mapID, x = x, y = y, zone = zone,
        cost = (cost and cost > 0) and cost or nil, currency = currency,
        limited = info.numAvailable and info.numAvailable >= 0 or nil, item = id })
      found = found + 1
    end
  end
  if found > 0 then ns:Debug("Recipe book:", found, "recipes sold by", name) end
end
ns:On("MERCHANT_SHOW", function() C_Timer.After(0.6, captureVendor) end)

---------------------------------------------------------------------------
-- Trainers: what they teach
---------------------------------------------------------------------------
-- The trainer window hides what you already know or can't learn yet. Show every kind
-- while reading, then put the player's filter back as it was.
local FILTERS = { "available", "unavailable", "used" }
local reading, lastRead = false, 0
local function captureTrainer()
  if reading or not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
  local npcID, name = npcInfo("npc")
  local mapID, x, y, zone = here()
  -- Keep what an earlier visit learned (title, profession, tier) if this read misses it.
  local old = npcID and ns.db.vendors[npcID] or {}
  if npcID then
    ns.db.vendors[npcID] = { name = name or old.name, mapID = mapID, x = x, y = y, zone = zone, t = time(), trainer = true,
      title = old.title, profession = old.profession, tier = old.tier }
  end
  reading = true
  local saved = {}
  if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
    for _, f in ipairs(FILTERS) do
      saved[f] = GetTrainerServiceTypeFilter(f)
      if not saved[f] then pcall(SetTrainerServiceTypeFilter, f, 1) end
    end
  end
  local found = 0
  -- Which profession this trainer teaches (most common skill needed) and their tier
  -- (the highest rank spell they offer: Apprentice, Journeyman, Expert, Artisan).
  local TIERS = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }
  local profCount, tier = {}, nil
  local all = {}   -- everything read, for Training.lua (class and riding trainers)
  for i = 1, (GetNumTrainerServices() or 0) do
    local service, second, third = GetTrainerServiceInfo(i)
    -- Which value is the state ("available", "unavailable", "used", "header"): Forever
    -- gives it second and the icon third (owner's /fl trainer, October 5: "Fire Ward
    -- (available): 135806"); Classic gave the rank second and the state third.
    local STATES = { available = true, unavailable = true, used = true, header = true }
    local category = (STATES[second] and second) or (STATES[third] and third) or third
    local sub = (STATES[second] and nil) or second
    if service and category ~= "header" then
      local reqName, skill = GetTrainerServiceSkillReq and GetTrainerServiceSkillReq(i)
      if reqName and reqName ~= "" then profCount[reqName] = (profCount[reqName] or 0) + 1 end
      local t = service:match("^(%a+)")
      if TIERS[t] and (not tier or TIERS[t] > TIERS[tier]) then tier = t end
      local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
      local ok, level = pcall(function() return GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) end)
      all[#all + 1] = { name = service, sub = sub, state = category, cost = cost, level = ok and level or nil,
        skill = reqName, skillLevel = skill }
      addSource(service:lower(), { kind = "trainer", npc = name, npcID = npcID, mapID = mapID, x = x, y = y,
        zone = zone, skill = skill, cost = cost })
      found = found + 1
    end
  end
  for f, on in pairs(saved) do
    if not on then pcall(SetTrainerServiceTypeFilter, f, 0) end
  end
  local prof, most = nil, 0
  for p, n in pairs(profCount) do if n > most then prof, most = p, n end end
  local v = npcID and ns.db.vendors[npcID]
  if v then
    v.profession, v.tier = prof or v.profession, tier or v.tier
    -- The title under the name, e.g. "Tailoring Trainer" or "Artisan Enchanter".
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
      local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
      local line = ok and data and data.lines and data.lines[2]
      if line and line.leftText and line.leftText ~= "" then v.title = line.leftText end
    end
    -- Forever's trainer list may not name the skill, so the title fills in the profession.
    if not v.profession and ns.ProfessionFromTitle then v.profession = ns.ProfessionFromTitle(v.title) end
    -- Forever shows the rank in the window's header, not in the list, so the title
    -- ("Expert Tailor") is the reliable place for the tier.
    local fromTitle = v.title and v.title:match("^(%a+)")
    if fromTitle and TIERS[fromTitle] then v.tier = fromTitle end
    ns:Debug("Trainer", name or "?", "teaches", prof or "?", "up to", tier or "?", "title", v.title or "?")
  end
  -- Class and riding trainers (Training.lua), once the profession (if any) is known.
  if ns.TrainerRead then
    local ok, err = pcall(ns.TrainerRead, ns, all, name, npcID, (v and v.profession) or prof)
    if not ok then ns:Debug("Training: couldn't read the trainer:", tostring(err)) end
  end
  reading = false
  lastRead = GetTime()
  if found > 0 then ns:Debug("Recipe book:", found, "trainer recipes from", name or "?") end
end

-- The trainer sends many updates in a row (each purchase, each filter change): read
-- once, a moment after the last one.
local trainerTimer
local function queueTrainer()
  -- Changing the filter while reading sends updates too; don't read again because of those.
  if reading or GetTime() - lastRead < 2 then return end
  if trainerTimer then trainerTimer:Cancel() end
  trainerTimer = C_Timer.NewTimer(0.8, function() trainerTimer = nil; captureTrainer() end)
end
ns:On("TRAINER_SHOW", queueTrainer)
ns:On("TRAINER_UPDATE", queueTrainer)

---------------------------------------------------------------------------
-- Drops: a recipe in a loot window, with the mob it came from
---------------------------------------------------------------------------
ns:On("LOOT_OPENED", function()
  if not GetNumLootItems then return end
  for i = 1, GetNumLootItems() do
    local id = ns.ItemIDFromLink(GetLootSlotLink and GetLootSlotLink(i))
    local itemName = id and ns.GetItemInfo(id)
    local recipe = recipeNameFromItem(itemName)
    if recipe then
      local guid = GetLootSourceInfo and GetLootSourceInfo(i)
      local npcID = guid and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
      local mob = (UnitExists("target") and UnitIsDead("target")) and (UnitName("target")) or nil
      local mapID, x, y, zone = here()
      addSource(recipe, { kind = "drop", npc = mob, npcID = npcID or mob, mapID = mapID, x = x, y = y, zone = zone, item = id })
      ns:Debug("Recipe book: recipe drop", itemName, "from", mob or npcID or "?", "in", zone or "?")
    end
  end
end)

---------------------------------------------------------------------------
-- /fl book: what's been gathered so far
---------------------------------------------------------------------------
function ns:PrintRecipeBook()
  ns:Print("Recipe book so far:")
  local known = {}
  -- (Your characters on this ruleset and faction, as everywhere else: Core.lua.)
  for key, c in pairs(ns.db.chars) do
    for prof, p in pairs(ns:SameMarketChar(key) and c.profs or {}) do
      known[prof] = known[prof] or {}
      for id in pairs(p.recipes or {}) do known[prof][id] = true end
    end
  end
  for prof, book in pairs(ns.db.recipeBook) do
    local total, have, withSource = 0, 0, 0
    for id, r in pairs(book) do
      total = total + 1
      if known[prof] and known[prof][id] then have = have + 1 end
      if r.n and ns.db.recipeSources[r.n:lower()] then withSource = withSource + 1 end
    end
    print(("  %s: %d recipes, %d known by your characters, %d with a source seen"):format(prof, total, have, withSource))
  end
  local kinds, vendors = {}, 0
  for _, list in pairs(ns.db.recipeSources) do
    for _, s in pairs(list) do kinds[s.kind] = (kinds[s.kind] or 0) + 1 end
  end
  for _ in pairs(ns.db.vendors) do vendors = vendors + 1 end
  print(("  Sources seen: %d from vendors, %d from trainers, %d drops. %d vendors and trainers with positions."):format(
    kinds.vendor or 0, kinds.trainer or 0, kinds.drop or 0, vendors))
end
