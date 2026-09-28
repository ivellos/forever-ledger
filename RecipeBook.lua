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
function ns:CaptureRecipeBook(profName)
  local TS = C_TradeSkillUI
  if not (TS and TS.GetAllRecipeIDs and profName) then return end
  local book = ns.db.recipeBook[profName] or {}
  ns.db.recipeBook[profName] = book
  local added = 0
  for _, id in ipairs(TS.GetAllRecipeIDs() or {}) do
    if not book[id] then
      local ok, info = pcall(TS.GetRecipeInfo, id)
      if ok and type(info) == "table" and info.name then
        local rec = ns:ReadRecipe(id, info)
        book[id] = { n = rec.n, out = rec.out, oq = rec.oq, r = rec.r }
        added = added + 1
      end
    end
  end
  if added > 0 then ns:Debug("Recipe book:", added, "new", profName, "recipes recorded") end
end

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
  for i = 1, (GetNumTrainerServices() or 0) do
    local service, _, category = GetTrainerServiceInfo(i)
    if service and category ~= "header" then
      local reqName, skill = GetTrainerServiceSkillReq and GetTrainerServiceSkillReq(i)
      if reqName and reqName ~= "" then profCount[reqName] = (profCount[reqName] or 0) + 1 end
      local t = service:match("^(%a+)")
      if TIERS[t] and (not tier or TIERS[t] > TIERS[tier]) then tier = t end
      local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
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
  for _, c in pairs(ns.db.chars) do
    for prof, p in pairs(c.profs or {}) do
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
