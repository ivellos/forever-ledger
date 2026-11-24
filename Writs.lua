local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Craftsman's Writs (Frank, November 16: "items that give you a quest to deliver a
-- crafted item somewhere in the world and you get some reputation", where crates give
-- Merchant's Favor). A Sealed Journeyman's, Expert's or Artisan's Writ drops from mobs
-- and chests (tradable, sold on the auction house) and opens into one order,
-- "Craftsman's Writ: <item>": deliver that item to a customer somewhere in the world for
-- Azeroth Commerce Authority (Alliance) or Durotar Supply and Logistics (Horde)
-- reputation and a coin pouch, each order once a day; no profession needed.
--
-- The list below is from fan guides read November 16 (conquestcapped.com,
-- foreverchanges.pro, loreforeverwow.com, theforeverera.com; names checked against the
-- game's item names): 150 orders, Alchemy, Blacksmithing, Engineering, Leatherworking
-- and Tailoring. Reputation (75, 125, 200) and the coin pouch amounts are the guides'
-- numbers and not yet seen in game; customers marked nil aren't known yet.
---------------------------------------------------------------------------
local TIERS = {
  J = { key = "J", label = "Journeyman", rep = 75, pouch = 3300, sealed = 262888 },
  E = { key = "E", label = "Expert", rep = 125, pouch = 7000, sealed = 262889 },
  A = { key = "A", label = "Artisan", rep = 200, pouch = 7500, sealed = 262890 },
}
ns.WRIT_TIERS = TIERS

-- { item ID, profession, tier, skill to make it, customer, zone, writ item ID, how many }
local LIST = {
  -- Journeyman
  { 3383, "Alchemy", "J", 120, "Muggol Breezebeard", "Arathi Highlands", 264012 },
  { 3385, "Alchemy", "J", 145, "Ash'alari", "Ashenvale", 264013 },
  { 6048, "Alchemy", "J", 160, "Kzixx", "Duskwood", 264014 },
  { 5634, "Alchemy", "J", 175, "Webbed Mudsnout Gnoll", "Hillsbrad Foothills", 264015 },
  { 3390, "Alchemy", "J", 165, "Ziz Fizziks", "Stonetalon Mountains", 264016 },
  { 3388, "Alchemy", "J", 150, "Short John Mithril", "Stranglethorn Vale", 264017 },
  { 8951, "Alchemy", "J", 215, "Rizzle Brassbolts", "Thousand Needles", 264018 },
  { 5996, "Alchemy", "J", 120, "Kixxle", "Wetlands", 264019 },
  { 3391, "Alchemy", "J", 175, "Sos'mol", "Alterac Mountains" },
  { 5540, "Blacksmithing", "J", 115, "Alan Sneeks", "Alterac Mountains", 264020 },
  { 11128, "Blacksmithing", "J", 130, "Muggol Breezebeard", "Arathi Highlands", 264021 },
  { 5541, "Blacksmithing", "J", 145, "Cowardly Peon", "Ashenvale", 264022 },
  { 15869, "Blacksmithing", "J", 75, "Battered Trunk", "Duskwood", 264023 },
  { 3491, "Blacksmithing", "J", 135, "Gorgrash", "Hillsbrad Foothills", 264024 },
  { 2865, "Blacksmithing", "J", 120, "Ziz Fizziks", "Stonetalon Mountains", 264025 },
  { 3485, "Blacksmithing", "J", 155, "\"Sea Wolf\" MacKinley", "Stranglethorn Vale", 264026 },
  { 3848, "Blacksmithing", "J", 110, "\"Plucky\" Johnson", "Thousand Needles", 264027 },
  { 3484, "Blacksmithing", "J", 150, "Kixxle", "Wetlands", 264028 },
  { 5507, "Engineering", "J", 160, "Alan Sneeks", "Alterac Mountains", 264029 },
  { 4384, "Engineering", "J", 175, "Alyce", "Arathi Highlands", 264030 },
  { 4383, "Engineering", "J", 170, "Grembly", "Ashenvale", 264031 },
  { 4381, "Engineering", "J", 165, "Kzixx", "Duskwood", 264032 },
  { 6712, "Engineering", "J", 115, "Gorgrash", "Hillsbrad Foothills", 264033 },
  { 4373, "Engineering", "J", 145, "Ziz Fizziks", "Stonetalon Mountains", 264034 },
  { 7506, "Engineering", "J", 150, "Scooty", "Stranglethorn Vale", 264035 },
  { 4380, "Engineering", "J", 140, "Razzeric", "Thousand Needles", 264036 },
  { 8069, "Engineering", "J", 125, "Kixxle", "Wetlands", 264037, 200 },
  { 18662, "Leatherworking", "J", 125, "Sos'mol", "Alterac Mountains", 264038 },
  { 5958, "Leatherworking", "J", 105, "Alyce", "Arathi Highlands", 264039 },
  { 7349, "Leatherworking", "J", 135, "Murache", "Ashenvale", 264040 },
  { 2317, "Leatherworking", "J", 100, "Kzixx", "Duskwood", 264041 },
  { 7358, "Leatherworking", "J", 140, "Kris Legace", "Hillsbrad Foothills", 264042 },
  { 7371, "Leatherworking", "J", 145, "Ziz Fizziks", "Stonetalon Mountains", 264043 },
  { 4252, "Leatherworking", "J", 140, "Narkk", "Stranglethorn Vale", 264044 },
  { 4254, "Leatherworking", "J", 150, "Goblin Pit Boss", "Thousand Needles", 264045 },
  { 7284, "Leatherworking", "J", 120, "Kixxle", "Wetlands", 264046 },
  { 5766, "Tailoring", "J", 130, "Alan Sneeks", "Alterac Mountains", 264047 },
  { 6263, "Tailoring", "J", 100, "Alyce", "Arathi Highlands", 264048 },
  { 7048, "Tailoring", "J", 130, "Cowardly Peon", "Ashenvale", 264049 },
  { 4245, "Tailoring", "J", 145, "Kzixx", "Duskwood", 264050 },
  { 4317, "Tailoring", "J", 125, "Bath'rah the Windwatcher", "Alterac Mountains", 264051 },
  { 4313, "Tailoring", "J", 80, "Ziz Fizziks", "Stonetalon Mountains", 264052 },
  { 10048, "Tailoring", "J", 95, "Hekshi", "Stranglethorn Vale", 264053 },
  { 6264, "Tailoring", "J", 115, "Magus Tirth", "Thousand Needles", 264054 },
  { 4321, "Tailoring", "J", 135, "Kixxle", "Wetlands", 264055 },
  -- Expert
  { 6050, "Alchemy", "E", 205, "Lotwil Veriatus", "Badlands", 264056 },
  { 3823, "Alchemy", "E", 185, "Centaur Pariah", "Desolace", 264057 },
  { 4623, "Alchemy", "E", 230, "Mudcrush Durtfeet", "Dustwallow Marsh", 264058 },
  { 6052, "Alchemy", "E", 210, "Greta Mosshoof", "Felwood", 264059 },
  { 10592, "Alchemy", "E", 220, "Scout Raroul", "Feralas", 264060 },
  { 5633, "Alchemy", "E", 195, "Dendrite Starblaze", "Moonglade", 264061 },
  { 3827, "Alchemy", "E", 180, "Spek", "Riverglades", 264062 },
  { 6049, "Alchemy", "E", 210, "Durganon", "Searing Gorge", 264063 },
  { 3824, "Alchemy", "E", 190, "Mukomonji", "Swamp of Sorrows", 264064 },
  { 9061, "Alchemy", "E", 225, "Alchemist Pestlezugg", "Tanaris", 264065 },
  { 8949, "Alchemy", "E", 205, "Juo", "The Hinterlands", 264066 },
  { 9144, "Alchemy", "E", 225, "Spark Nilminer", "Un'Goro Crater", 264067 },
  { 7922, "Blacksmithing", "E", 210, "Furious Shadowforge Digger", "Badlands", 264068 },
  { 9060, "Blacksmithing", "E", 200, "Bibbly F'utzbuckle", "Desolace", 264069 },
  { 6041, "Blacksmithing", "E", 190, "Ugbert", "Dustwallow Marsh", 264070 },
  { 7928, "Blacksmithing", "E", 220, "Taronn Redfeather", "Felwood", 264071 },
  { 7942, "Blacksmithing", "E", 220, "Scout Raroul", "Feralas", 264072 },
  { 3853, "Blacksmithing", "E", 180, "Meliri", "Moonglade", 264073 },
  { 3837, "Blacksmithing", "E", 190, "Spek", "Riverglades", 264074 },
  { 7964, "Blacksmithing", "E", 175, "Master Smith Burninate", "Searing Gorge", 264075 },
  { 7943, "Blacksmithing", "E", 225, nil, nil, 264076 },
  { 11144, "Blacksmithing", "E", 180, "Spigot Operator Luglunket", "Tanaris", 264077 },
  { 9366, "Blacksmithing", "E", 200, nil, nil, 264078 },
  { 7941, "Blacksmithing", "E", 210, "Torwa Pathfinder", "Un'Goro Crater", 264079 },
  { 4396, "Engineering", "E", 220, nil, "Badlands?", 264080 },
  { 4392, "Engineering", "E", 185, "Bibbly F'utzbuckle", "Desolace", 264081 },
  { 4393, "Engineering", "E", 205, "The Ravenous", "Dustwallow Marsh", 264082 },
  { 4395, "Engineering", "E", 215, "Jessir Moonbow", "Felwood", 264083 },
  { 10501, "Engineering", "E", 240, "Scout Raroul", "Feralas", 264084 },
  { 10560, "Engineering", "E", 200, "Narianna", "Moonglade", 264085 },
  { 4852, "Engineering", "E", 185, "Spek", "Riverglades", 264086 },
  { 10500, "Engineering", "E", 225, "Durganon", "Searing Gorge", 264087 },
  { 10514, "Engineering", "E", 215, "Bullets Bigblast", "Swamp of Sorrows", 264088 },
  { 10498, "Engineering", "E", 175, "Jhordy Lapforge", "Tanaris", 264089 },
  { 11590, "Engineering", "E", 200, "Rhapsody Shindigger", "The Hinterlands", 264090 },
  { 16005, "Engineering", "E", 305, nil, nil, 264091 },
  { 8174, "Leatherworking", "E", 195, "Garek", "Badlands", 264092 },
  { 5965, "Leatherworking", "E", 180, "Azore Aldamort", "Desolace", 264093 },
  { 7378, "Leatherworking", "E", 180, "The Ravenous", "Dustwallow Marsh", 264094 },
  { 8214, "Leatherworking", "E", 220, "Ivy Leafrunner", "Felwood", 264095 },
  { 8210, "Leatherworking", "E", 215, nil, "Feralas?", 264096 },
  { 8217, "Leatherworking", "E", 220, "Narianna", "Moonglade", 264097 },
  { 7391, "Leatherworking", "E", 195, "Spek", "Riverglades", 264098 },
  { 8192, "Leatherworking", "E", 205, "Evonice Sootsmoker", "Searing Gorge", 264099 },
  { 8201, "Leatherworking", "E", 215, "Mukomonji", "Swamp of Sorrows", 264100 },
  { 8200, "Leatherworking", "E", 210, "Yeh'kinya", "Tanaris", 264101 },
  { 8189, "Leatherworking", "E", 205, "Juo", "The Hinterlands", 264102 },
  { 8218, "Leatherworking", "E", 220, "Nergal", "Un'Goro Crater", 264103 },
  { 10050, "Tailoring", "E", 205, "Rigglefuzz", "Badlands", 264104 },
  { 10023, "Tailoring", "E", 205, "Willow", "Desolace", 264105 },
  { 7063, "Tailoring", "E", 185, "Tabetha", "Dustwallow Marsh", 264106 },
  { 10004, "Tailoring", "E", 195, "Eridan Bluewind", "Felwood", 264107 },
  { 22246, "Tailoring", "E", 205, nil, "Felwood?", 264108 },
  { 4329, "Tailoring", "E", 185, "Mylentha Riverbend", "Moonglade", 264109 },
  { 9998, "Tailoring", "E", 185, "Spek", "Riverglades", 264110 },
  { 10009, "Tailoring", "E", 195, "Lookout Captain Lolo Longstriker", "Searing Gorge", 264111 },
  { 10052, "Tailoring", "E", 190, "Bullets Bigblast", "Swamp of Sorrows", 264112 },
  { 10008, "Tailoring", "E", 185, "Vizzklick", "Tanaris", 264113 },
  { 10042, "Tailoring", "E", 205, "Atal'ai Exile", "The Hinterlands", 264114 },
  { 7061, "Tailoring", "E", 180, "Petra Grossen", "Un'Goro Crater", 264115 },
  -- Artisan (most customers not known yet)
  { 9224, "Alchemy", "A", 265, "Archmage Xylem", "Azshara", 264116 },
  { 12190, "Alchemy", "A", 245, "Kum'isha the Collector", "Blasted Lands", 264117 },
  { 9233, "Alchemy", "A", 265, "Hastings", "Deadwind Pass", 264119 },
  { 9088, "Alchemy", "A", 255, "Adon", "Eastern Plaguelands", 264120 },
  { 13513, "Alchemy", "A", 315, nil, nil, 264121 },
  { 246948, "Alchemy", "A", 260 },
  { 3387, "Alchemy", "A", 275 },
  { 13457, "Alchemy", "A", 305 },
  { 18253, "Alchemy", "A", 310 },
  { 7929, "Blacksmithing", "A", 225 },
  { 7969, "Blacksmithing", "A", 230, nil, "Deadwind Pass?", 264128 },
  { 15872, "Blacksmithing", "A", 250 },
  { 12416, "Blacksmithing", "A", 255, "Kum'isha the Collector", "Blasted Lands", 264126 },
  { 7947, "Blacksmithing", "A", 255 },
  { 12775, "Blacksmithing", "A", 280 },
  { 12417, "Blacksmithing", "A", 290 },
  { 12422, "Blacksmithing", "A", 295 },
  { 20549, "Blacksmithing", "A", 320 },
  { 10548, "Engineering", "A", 260 },
  { 10504, "Engineering", "A", 265 },
  { 18631, "Engineering", "A", 270, "Khur Hornstriker", "Silithus", 264140 },
  { 18645, "Engineering", "A", 275 },
  { 15996, "Engineering", "A", 285 },
  { 18587, "Engineering", "A", 285 },
  { 16023, "Engineering", "A", 295 },
  { 18232, "Engineering", "A", 320 },
  { 21277, "Engineering", "A", 320 },
  { 15084, "Leatherworking", "A", 260, "Quartermaster Miranda Breechlock", "Eastern Plaguelands", 264147 },
  { 15092, "Leatherworking", "A", 270, "Fallen Adventurer", "Western Plaguelands", 264150 },
  { 15071, "Leatherworking", "A", 270 },
  { 15053, "Leatherworking", "A", 280 },
  { 15087, "Leatherworking", "A", 285 },
  { 18258, "Leatherworking", "A", 285 },
  { 15094, "Leatherworking", "A", 285, "Hastings", "Deadwind Pass", 264146 },
  { 15075, "Leatherworking", "A", 285 },
  { 15080, "Leatherworking", "A", 290 },
  { 10036, "Tailoring", "A", 155, "Hastings", "Deadwind Pass", 264155 },
  { 10025, "Tailoring", "A", 215, "Hermit Ortell", "Silithus", 264158 },
  { 14046, "Tailoring", "A", 230, "Kum'isha the Collector", "Blasted Lands", 264153 },
  { 21340, "Tailoring", "A", 230, nil, "Winterspring?", 264160 },
  { 14141, "Tailoring", "A", 240 },
  { 22251, "Tailoring", "A", 245 },
  { 13864, "Tailoring", "A", 250, "Gorzeeki Wildeyes", "Burning Steppes", 264154 },
  { 14108, "Tailoring", "A", 255 },
  { 14130, "Tailoring", "A", 275 },
}

-- Writ item IDs the list above lacks, from the game data (WritsData.lua, Codex, built from
-- the client's tables: it agrees with every ID above), matched by the item asked for. So a
-- writ is known by its ID, not its English name, on every client. Only IDs are taken:
-- tier, count and reward stay the list's (the game data doesn't have them).
-- Item 3391: the writ says "Ogre's Strength", the item "Ogre Strength" (FOREVER_WRITS.md).
local catalogWrit = { [3391] = 264011 }
for _, o in ipairs(ns.WRIT_DATA and ns.WRIT_DATA.orders or {}) do
  if o.item and o.writ then catalogWrit[o.item] = catalogWrit[o.item] or o.writ end
end

local WRITS, byWrit, byItem = {}, {}, {}
for i, w in ipairs(LIST) do
  local e = { item = w[1], prof = w[2], tier = w[3], skill = w[4], who = w[5], zone = w[6], writ = w[7] or catalogWrit[w[1]], qty = w[8] or 1, n = i }
  WRITS[i] = e
  if e.writ then byWrit[e.writ] = e end
  byItem[e.item] = e
end
ns.WRITS = WRITS

-- An order's zone without the guides' "?" (not confirmed), or nil; and every zone, sorted.
local function zoneOf(e) return e.zone and (e.zone:gsub("%?$", "")) or nil end
ns.WritZoneOf = zoneOf
function ns.WritZones()
  local seen, out = {}, {}
  for _, e in ipairs(WRITS) do
    local z = zoneOf(e)
    if z and not seen[z] then seen[z] = true; out[#out + 1] = z end
  end
  table.sort(out)
  return out
end
local SEALED = {}
for _, t in pairs(TIERS) do SEALED[t.sealed] = t end

-- The writ an item is: its ID first, else its name ("Craftsman's Writ: <item>"), since
-- some writs' IDs aren't known. Returns the order, or (sealed writs) the tier.
local function itemName(id)
  return (ns.db and ns.db.itemNames and ns.db.itemNames[id]) or (ns.FOREVER_ITEM_NAMES and ns.FOREVER_ITEM_NAMES[id])
end
local nameIndex
function ns:WritFor(id)
  if not id then return end
  if byWrit[id] then return byWrit[id] end
  if SEALED[id] then return nil, SEALED[id] end
  local name = ns.ItemName and ns.ItemName(id)
  if type(name) ~= "string" then return end
  local wanted = name:match("^Craftsman's Writ: (.+)$")
  if wanted then
    if not nameIndex then
      nameIndex = {}
      for _, e in ipairs(WRITS) do
        local n = itemName(e.item)
        if n then nameIndex[n:lower()] = e end
      end
    end
    return nameIndex[wanted:lower()]
  end
  local sealed = name:match("^Sealed (%a+)'s Writ$")
  for _, t in pairs(TIERS) do
    if sealed == t.label then return nil, t end
  end
end

---------------------------------------------------------------------------
-- What an order costs: the cheapest way to get the item (bought on the auction house or
-- from a vendor, or made from its materials, whichever is cheaper, as Gold making's How
-- it adds up), less the coin pouch, per point of reputation.
---------------------------------------------------------------------------
local fcByOut
local function foreverRecipe(id)
  if not fcByOut then
    fcByOut = {}
    for _, e in ipairs(ns.FOREVER_CRAFTS or {}) do
      if e.out and e.r and #e.r > 0 and not fcByOut[e.out] then fcByOut[e.out] = e end
    end
  end
  local e = fcByOut[id]
  if e then return { makes = math.max(1, math.floor(((e.low or 1) + (e.high or e.low or 1)) / 2)), mats = e.r } end
end

-- Gold making's source of an item, with the game's own recipe when no character's or
-- seen recipe makes it (Blacksmithing, Engineering... nobody of yours has).
local function source(id)
  local s = ns.GoldSource and ns:GoldSource(id) or {}
  if not s.recipe then s.recipe = foreverRecipe(id) end
  return s
end

-- Kept 5 minutes, or until the next full scan: worked out every 30 seconds, a writ's hover
-- hitched again each time (Frank's AN30, November 19).
local COST_KEEP = 300
-- costsGen: counts each time the kept costs are cleared as out of date, so the background
-- work below knows which of its results came before that (Codex review, November 21).
local costs, costsAt, costsScan, costsGen = {}, -math.huge, nil, 0
local function costsStale()
  return GetTime() - costsAt > COST_KEEP or (ns.db and ns.db.lastFullScan) ~= costsScan
end
-- yield: frames are given back while it's planned (only from the sliced run below).
local function workOutCost(e, yield)
  local ahlBefore = ns.ahledgerUses or 0
  local cache = {}
  local function src(id)
    if not cache[id] then cache[id] = source(id) end
    return cache[id]
  end
  local need = { [e.item] = e.qty }
  local total, plan = ns.CraftPlan(need, src, yield and { yield = true } or nil)
  local c = total and { total = total, plan = plan, need = need, src = src } or false
  if c and (ns.ahledgerUses or 0) ~= ahlBefore then c.ahl = true end
  return c
end
function ns:WritCost(e)
  if costsStale() then
    wipe(costs); costsAt, costsScan = GetTime(), ns.db and ns.db.lastFullScan
    costsGen = costsGen + 1
  end
  local c = costs[e.item]
  if c and c.ahl then ns.ahledgerUses = (ns.ahledgerUses or 0) + 1 end   -- (AHledger's credit: Values.lua)
  if c == nil then
    c = workOutCost(e)
    costs[e.item] = c
  end
  return c or nil
end

-- The Writs view: every order's cost worked out a little each frame (Frank's thirteenth
-- /fl perf, November 21: opening it worked all of them out in one go, 967 ms). The costs
-- already known (even out of date) are shown meanwhile, then the view is drawn again.
-- Returns an order's known cost (nil: not worked out yet, false: no price), never working
-- one out.
local costRun
local function knownCost(e)
  local c = costs[e.item]
  if c and c.ahl then ns.ahledgerUses = (ns.ahledgerUses or 0) + 1 end
  return c
end
local function refreshCosts(list, done)
  if costRun and not costRun.stopped then return end
  local missing = false
  for _, e in ipairs(list) do if costs[e.item] == nil then missing = true; break end end
  if not missing and not costsStale() then return end
  local fresh, scan, gen, startedAt = {}, ns.db and ns.db.lastFullScan, costsGen, GetTime()
  costRun = ns.RunInSlices("Writs: working out costs", function()
    for _, e in ipairs(list) do
      ns.MaybeYield()
      -- (What the cache held for it when this one began. Frames are given back while it's
      -- planned, so a hover or a clear meanwhile shows up as a change below.)
      local was, g = costs[e.item], costsGen
      fresh[#fresh + 1] = { item = e.item, c = workOutCost(e, true), was = was, gen = g }
    end
  end, function()
    -- Only where nothing changed the kept cost since it was worked out here: one a hover or
    -- a tier's average worked out meanwhile is newer, and costs cleared meanwhile as out of
    -- date make the ones worked out here before that old (Codex review, November 21: an
    -- old 900c put back over a hover's 1800c, then kept as fresh).
    for _, x in ipairs(fresh) do
      if x.gen == costsGen and costs[x.item] == x.was then costs[x.item] = x.c end
    end
    -- (From when this began, and only if nothing cleared them meanwhile: that set its own.)
    if gen == costsGen and costsStale() then costsAt, costsScan = startedAt, scan end
    if done then done() end
  end, function() costRun = nil end)
end
ns._writsTest = { refreshCosts = refreshCosts, knownCost = knownCost,
  forget = function() wipe(costs); costsAt = -math.huge; costsGen = costsGen + 1 end }   -- (tests)

-- A tier's average order cost: { avg, t }, or nil until the first is worked out. Done in
-- the background, about 4 ms a frame, and kept AVG_KEEP seconds (the old one is shown
-- while a new one is worked out).
local AVG_KEEP = 600
local tierAvg, tierBusy = {}, {}
local clock = debugprofilestop
function ns.WritTierAverage(key)
  local a = tierAvg[key]
  if a and a.ahl then ns.ahledgerUses = (ns.ahledgerUses or 0) + 1 end   -- (AHledger's credit)
  if (a and GetTime() - a.t < AVG_KEEP) or tierBusy[key] then return a end
  local ahlBefore = ns.ahledgerUses or 0
  local list = {}
  for _, w in ipairs(WRITS) do if w.tier == key then list[#list + 1] = w end end
  local i, sum, n = 0, 0, 0
  local function step()
    local stop = clock and clock() + 4
    repeat
      i = i + 1
      local w = list[i]
      if not w then
        tierAvg[key], tierBusy[key] = { avg = n > 0 and sum / n or nil, t = GetTime(), ahl = (ns.ahledgerUses or 0) ~= ahlBefore or nil }, nil
        return
      end
      local ok, c = pcall(ns.WritCost, ns, w)   -- (an error mustn't leave it busy for good)
      if ok and c then sum, n = sum + c.total, n + 1 end
    until not stop or clock() > stop
    if C_Timer and C_Timer.After then C_Timer.After(0, step) else step() end
  end
  tierBusy[key] = true
  step()
  return tierAvg[key] or a
end

-- Copper per point of reputation after the pouch (negative: the pouch pays more).
function ns.WritPerRep(cost, tier)
  local t = TIERS[tier]
  if not (cost and t) then return end
  return (cost - t.pouch) / t.rep
end

-- How the cheapest way gets it: "buy on the AH", "make it", "from a vendor".
local function howText(c, e)
  local p = c and c.plan and c.plan[e.item]
  if not p then return "" end
  if p.made > 0 then return "make" end
  if p.vendor > 0 then return "vendor" end
  if p.owned > 0 and p.bought == 0 then return "bags" end
  return "AH"
end

-- The writs this character has, in bags and bank (Frank, November 16, from SKTools'
-- idea: the orders you have and what each needs): { [order] = count }, and sealed writs
-- { [tier key] = count }. Found by item, so writs whose ID isn't listed count too.
function ns:YourWrits()
  local inv = ns.db.inventory and ns.db.inventory[ns.CharKey()]
  local orders, sealed = {}, {}
  for _, where in ipairs({ "bags", "bank" }) do
    for id, n in pairs(inv and inv[where] or {}) do
      local e, t = ns:WritFor(id)
      if e then orders[e] = (orders[e] or 0) + n
      elseif t then sealed[t.key] = (sealed[t.key] or 0) + n end
    end
  end
  return orders, sealed
end

-- Orders onto the "Writs" shopping list: every order on it is planned together (the
-- cheapest way, what you have used first, nothing counted twice) and the list holds what
-- to buy, on the auction house or from a vendor, up to the highest price the plan paid;
-- an order made from materials adds its materials. Kept a week, like crate lists.
local LIST_NAME = "Writs"
local function plan(need)
  local cache = {}
  return ns.CraftPlan(need, function(id)
    if not cache[id] then cache[id] = source(id) end
    return cache[id]
  end, { ownedFree = true })
end

function ns:WritsToShoppingList(add)
  local list
  for i, l in ipairs(ns:ShoppingLists()) do
    if l.name == LIST_NAME and l.writOrders then list = l; ns:SelectShoppingList(i) end
  end
  if not list then
    list = ns:NewShoppingList(LIST_NAME)
    list.writOrders = {}
  end
  list.temp, list.tempT = LIST_NAME, time()
  for _, e in ipairs(add) do list.writOrders[e.item] = true end
  local need = {}
  for item in pairs(list.writOrders) do
    local e = byItem[item]
    if e then need[item] = (need[item] or 0) + e.qty end
  end
  local _, p = plan(need)
  -- What this list added before goes, so the new plan replaces it.
  for id in pairs(list.writItems or {}) do
    for i = #list.items, 1, -1 do if list.items[i].id == id then table.remove(list.items, i) end end
  end
  list.writItems = {}
  local added, ready = 0, 0
  for id, x in pairs(p or {}) do
    local qty = x.bought + x.vendor
    if qty > 0 then
      local top = x.top or 0
      if x.vendor > 0 then top = math.max(top, math.ceil(x.vendorCost / x.vendor)) end
      ns:AddToShoppingList(list, id, top, qty)
      list.writItems[id] = true
      added = added + 1
    end
  end
  -- The writ itself for each order you don't have one of (Frank, November 23: they had to
  -- be bought separately), up to its usual price, as any list item without a price of yours.
  local yours = ns:YourWrits()
  local writs = 0
  for item in pairs(list.writOrders) do
    local e = byItem[item]
    if e and e.writ and not yours[e] then
      ns:AddToShoppingList(list, e.writ, nil, 1)
      list.writItems[e.writ] = true
      writs = writs + 1
    end
  end
  for item in pairs(need) do
    local x = p and p[item]
    if x and x.owned >= need[item] then ready = ready + 1 end
  end
  if ns.RefreshListsView then ns:RefreshListsView() end
  local orders = 0
  for _ in pairs(list.writOrders) do orders = orders + 1 end
  ns:Print(("Shopping list \"%s\": %d %s for %d %s, each up to the highest price the plan paid.%s%s Tick Buy from this list in the Buy queue (/fl lists)."):format(
    LIST_NAME, added, added == 1 and "item" or "items", orders, orders == 1 and "order" or "orders",
    writs > 0 and (" Also %d %s you don't have yet, up to the usual price."):format(writs, writs == 1 and "writ" or "writs") or "",
    ready > 0 and (" You already have the item for %d."):format(ready) or ""))
  return list
end

-- Tooltip lines on a writ (the crate setting covers both).
function ns:WritTooltipLines(id)
  local e, tier = ns:WritFor(id)
  if e then
    local t = TIERS[e.tier]
    local c = ns:WritCost(e)
    local lines = {}
    lines[1] = ("Writ: %s%s to %s, %d reputation"):format(e.qty > 1 and (e.qty .. " ") or "", itemName(e.item) or ns.ItemName(e.item),
      e.who and (e.who .. (e.zone and (" (" .. e.zone .. ")") or "")) or (e.zone and ("someone in " .. e.zone) or "a customer not known yet"), t.rep)
    if c then
      local per = ns.WritPerRep(c.total, e.tier)
      if per < 0 then
        lines[2] = ("Cheapest: %s (%s); the coin pouch pays %s more, about %s per reputation"):format(ns.Money(math.floor(c.total + 0.5)),
          howText(c, e), ns.Money(math.floor(t.pouch - c.total + 0.5)), ns.Money(math.floor(-per + 0.5)))
      else
        lines[2] = ("Cheapest: %s (%s), about %s per reputation after the coin pouch"):format(ns.Money(math.floor(c.total + 0.5)),
          howText(c, e), ns.Money(math.floor(per + 0.5)))
      end
    end
    return lines
  elseif tier then
    -- A sealed writ: the average order of its tier at today's prices. Worked out a few
    -- orders a frame and kept for 10 minutes (Frank's AN30, November 17: all of a tier's
    -- orders at once, again every 30 seconds, froze the game for half a second on a hover).
    local line = ("Opens into one %s order (%d reputation)"):format(tier.label, tier.rep)
    local a = ns.WritTierAverage(tier.key)
    if a and a.avg then line = line .. (", which costs about %s to fill on average"):format(ns.Money(math.floor(a.avg + 0.5))) end
    return { line }
  end
end

---------------------------------------------------------------------------
-- The Writs tab (under Professions, after Crates)
---------------------------------------------------------------------------
local ROW = 22
local f
local rows = {}
-- Columns (Frank's AH9, November 19: no room at any size). The tier shows in the filter and
-- the hover, the zone in the hover; prices are rounded here and exact in the hover.
local COLS = {
  { key = "name", label = "Order" },
  { key = "prof", label = "Profession", w = 96 },
  { key = "rep", label = "Rep", w = 34, right = true },
  { key = "where", label = "Deliver to", w = 116 },
  { key = "cost", label = "Cheapest", w = 104, right = true },
  { key = "perRep", label = "Per rep", w = 62, right = true },
  { key = "writ", label = "Writ AH", w = 62, right = true },
  { key = "add", label = "", w = 40 },
}

local function S()
  local s = ns.db.settings
  s.writs = type(s.writs) == "table" and s.writs or {}
  local w = s.writs
  w.tier = w.tier or "all"
  w.prof = w.prof or "all"
  w.zone = w.zone or "all"
  w.sort = w.sort or { key = "perRep" }
  if w.sort.key == "tier" then w.sort.key = "rep" end   -- (the Tier column went, November 19)
  return w
end

local function dim(t) return "|cff888888" .. t .. "|r" end

function ns:BuildWrits(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local opts = { { value = "all", label = "All" } }
  for _, k in ipairs({ "J", "E", "A" }) do opts[#opts + 1] = { value = k, label = TIERS[k].label } end
  opts[#opts + 1] = { value = "mine", label = "Yours" }   -- the writs in your bags and bank
  f.tier = T:Choice(f, opts, function(v) S().tier = v; ns:RefreshWrits() end)
  f.tier:SetPoint("TOPLEFT", 2, -2)
  f.prof = T:Dropdown(f, 150, function(v) S().prof = v; ns:RefreshWrits() end)
  f.prof:SetPoint("LEFT", f.tier, "RIGHT", 12, 0)
  local popts = { { value = "all", label = "Any profession" } }
  for _, p in ipairs({ "Alchemy", "Blacksmithing", "Engineering", "Leatherworking", "Tailoring" }) do popts[#popts + 1] = { value = p, label = p } end
  f.prof:SetOptions(popts)
  -- The zone the customer is in (Frank, November 23), to do the orders of one zone together.
  f.zone = T:Dropdown(f, 170, function(v) S().zone = v; ns:RefreshWrits() end)
  f.zone:SetPoint("LEFT", f.prof, "RIGHT", 10, 0)
  local zopts = { { value = "all", label = "Any zone" } }
  for _, z in ipairs(ns.WritZones()) do zopts[#zopts + 1] = { value = z, label = z } end
  zopts[#zopts + 1] = { value = "?", label = "Zone not known yet" }
  f.zone:SetOptions(zopts)
  f.info = T:Text(f, 11, T.dim)
  f.info:SetPoint("TOPLEFT", f.tier, "BOTTOMLEFT", 0, -6)
  f.info:SetPoint("RIGHT", f, "RIGHT", -2, 0)
  f.info:SetJustifyH("LEFT")
  f.info:SetText("Orders to deliver for reputation and a coin pouch, each once a day. Cheapest: buy or make the item at your last scan's prices. Per rep: that less the pouch, per point (green +: the pouch pays you that much). Click an order to search the auction house for its item, right-click for the writ itself.")
  f.header = CreateFrame("Frame", nil, f)
  f.header:SetPoint("TOP", f.info, "BOTTOM", 0, -6)
  f.header:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.header:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.header:SetHeight(22)
  T:Fill(f.header, { 1, 1, 1, 0.05 })
  f.heads = {}
  f.sf, f.content = T:Scroll(f)
  f.sf:SetPoint("TOP", f.header, "BOTTOM", 0, -2)
  f.sf:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.sf:SetPoint("BOTTOMRIGHT", 0, 22)
  f.summary = T:Text(f, 12)
  f.summary:SetPoint("BOTTOMLEFT", 4, 4)
  f.addMine = T:Button(f, "Add yours to a shopping list", 190, function()
    local add = {}
    for e in pairs(ns:YourWrits()) do add[#add + 1] = e end
    if #add == 0 then ns:Print("No Craftsman's Writs in your bags or bank (open sealed ones first).") return end
    ns:WritsToShoppingList(add)
  end, 20)
  f.addMine:SetPoint("BOTTOMRIGHT", 0, 2)
  f.summary:SetPoint("RIGHT", f.addMine, "LEFT", -8, 0)
  f.summary:SetJustifyH("LEFT")
  f.summary:SetWordWrap(false)
  return f
end

local function layout(width)
  local fixed = 0
  for _, c in ipairs(COLS) do fixed = fixed + (c.w or 0) + 8 end
  local x, out = 4, {}
  for _, c in ipairs(COLS) do
    local w = c.w or math.max(150, width - fixed - 4)
    out[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  return out
end

local function rowTooltip(self)
  local e, c = self.entry, self.cost
  if not e then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(e.item)
  ns:TooltipAddLine(" ")
  local t = TIERS[e.tier]
  ns:TooltipAddDoubleLine("Writ", ("%s, %d reputation"):format(t.label, t.rep), 0.7, 0.7, 0.7, 1, 1, 1)
  ns:TooltipAddDoubleLine("Deliver to", e.who and (e.who .. (e.zone and (", " .. e.zone) or "")) or (e.zone and ("not known yet (players say " .. e.zone:gsub("%?$", "") .. ")") or "not known yet"),
    0.7, 0.7, 0.7, 1, 1, 1)
  ns:TooltipAddDoubleLine("To make it", ("%s, skill %d"):format(e.prof, e.skill or 0), 0.7, 0.7, 0.7, 1, 1, 1)
  if c and ns.GoldPlanLines then
    ns:TooltipAddLine(" ")
    ns:TooltipAddLine("The cheapest way", 1, 0.82, 0)
    local lines = ns.GoldPlanLines(c.need, { e.item }, c.plan, function(id) return c.src(id).recipe end,
      function(v) return ns.Money(math.floor((v or 0) + 0.5)) end)
    for _, l in ipairs(lines) do
      ns:TooltipAddDoubleLine(("  "):rep(l.depth + 1) .. l.head:format(itemName(l.id) or ns.ItemName(l.id)), l.text, 0.85, 0.85, 0.85, 1, 1, 1)
    end
    ns:TooltipAddDoubleLine("In all", ns.Money(math.floor(c.total + 0.5)), 0.7, 0.7, 0.7, 1, 1, 1)
  elseif not c then
    ns:TooltipAddLine("No price for it or its materials yet: run a full scan.", 0.6, 0.6, 0.6, true)
  end
  ns:TooltipAddLine("Click to search the auction house for the item, right-click for the writ.", 0.5, 0.5, 0.5, true)
  GameTooltip:Show()
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, f.content)
  r:SetHeight(ROW)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cells = {}
  for _, c in ipairs(COLS) do
    if c.key == "add" then break end   -- (a button, below)
    local fs = T:Text(r, 12)
    fs:SetWordWrap(false)
    fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
    r.cells[c.key] = fs
  end
  -- This order onto the Writs shopping list.
  r.add = T:Button(r, "List", 38, function() if r.entry then ns:WritsToShoppingList({ r.entry }) end end, 18)
  r.add:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ns:TooltipAddLine("Add this order to the Writs shopping list", 1, 1, 1)
    ns:TooltipAddLine("What to buy for it, or its materials when making it is cheaper; what you have is used first.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  r.add:HookScript("OnLeave", function() GameTooltip:Hide() end)
  -- Click: the item. Right-click: the writ itself (Frank, November 23: the writs had to be
  -- searched for separately).
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
      if not e.writ then ns:Print("This writ's item number isn't known yet, so it can't be searched for.") return end
      if not ns:SearchAuctionHouse(e.writ) then ns:Print("Open the auction house, then right-click an order to search for its writ.") end
    elseif not ns:SearchAuctionHouse(e.item) then
      ns:Print("Open the auction house, then click an order to search for its item.")
    end
  end)
  r:SetScript("OnEnter", rowTooltip)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function bagHas(id) return ns.HaveCount and ns:HaveCount(id) or 0 end

function ns:RefreshWrits()
  local ahlBefore = ns.ahledgerUses or 0
  if not f or not f:IsShown() then return end
  local s = S()
  f.tier:SetValue(s.tier)
  f.prof:SetValue(s.prof)
  f.zone:SetValue(s.zone)
  local width = f:GetWidth() - 12
  local lay = layout(width)
  local sort = s.sort
  for i, c in ipairs(COLS) do
    local h = f.heads[i]
    if not h then
      h = CreateFrame("Button", nil, f.header)
      h.fs = T:Text(h, 11, T.dim)
      h.fs:SetAllPoints()
      h:SetScript("OnClick", function(self)
        local so = S().sort
        if so.key == self.key then so.desc = not so.desc else so.key, so.desc = self.key, false end
        ns:RefreshWrits()
      end)
      f.heads[i] = h
    end
    h.key = c.key
    h:ClearAllPoints()
    h:SetPoint("LEFT", f.header, "LEFT", lay[c.key].x, 0)
    h:SetSize(lay[c.key].w, 22)
    h.fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
    local on = sort.key == c.key
    h.fs:SetText(c.label .. (on and (sort.desc and " v" or " ^") or ""))
    local col = on and T.accent or T.dim
    h.fs:SetTextColor(col[1], col[2], col[3], 1)
  end

  -- Costs out of date or not known yet are worked out over the next frames, then drawn.
  -- (Visible, not shown: leaving the Writs view hides its parent, not this frame; Codex review.)
  refreshCosts(WRITS, function() if f and f:IsVisible() then ns:RefreshWrits() end end)
  local list, priced = {}, 0
  local yours, sealed = ns:YourWrits()
  for _, e in ipairs(WRITS) do
    if (s.tier == "all" or e.tier == s.tier or (s.tier == "mine" and yours[e])) and (s.prof == "all" or e.prof == s.prof)
      and (s.zone == "all" or (s.zone == "?" and not zoneOf(e)) or zoneOf(e) == s.zone) then
      local c = knownCost(e)   -- (nil until worked out: refreshCosts, above)
      if c then priced = priced + 1 end
      local writPrice = e.writ and ns:GetPrice(e.writ)
      list[#list + 1] = { e = e, c = c, name = (itemName(e.item) or ns.ItemName(e.item)),
        -- (nil, not false, where there is no price: the sort compares numbers; Codex review.)
        cost = c and c.total or nil, perRep = c and ns.WritPerRep(c.total, e.tier) or nil, writ = writPrice or nil,
        have = yours[e] ~= nil, ready = bagHas(e.item) >= e.qty }
    end
  end
  local tierRank = { J = 1, E = 2, A = 3 }
  local function value(x, key)
    if key == "name" then return x.name:lower() end
    if key == "prof" then return x.e.prof end
    if key == "tier" or key == "rep" then return tierRank[x.e.tier] end
    if key == "where" then return (x.e.who or x.e.zone or "~"):lower() end
    return x[key]
  end
  table.sort(list, function(a, b)
    if a.have ~= b.have then return a.have end   -- writs in your bags first
    local va, vb = value(a, sort.key), value(b, sort.key)
    if va == vb or va == nil or vb == nil then
      if va == nil and vb ~= nil then return false end
      if vb == nil and va ~= nil then return true end
      return a.e.n < b.e.n
    end
    if sort.desc then return va > vb end
    return va < vb
  end)

  f.content:SetWidth(width)
  for i, x in ipairs(list) do
    local r = getRow(i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    r.entry, r.cost = x.e, x.c
    r.icon:SetTexture(ns:ItemIcon(x.e.item))
    r.icon:ClearAllPoints()
    r.icon:SetPoint("LEFT", r, "LEFT", lay.name.x, 0)
    local e, t = x.e, TIERS[x.e.tier]
    local values = {
      name = (e.qty > 1 and (e.qty .. " x ") or "") .. x.name .. (x.have and (T:AccentCode() .. "  yours|r") or ""),
      prof = e.prof,
      rep = tostring(t.rep),
      where = e.who or dim(e.zone and "not confirmed" or "not known yet"),
      cost = x.ready and "|cff7fd39cyou have it|r" or x.cost and (ns.MoneyShort(x.cost) .. dim(" " .. howText(x.c, e))) or dim(x.c == nil and "working out..." or "no price"),
      -- Below zero the pouch pays more than the order costs: the gain per point, in green
      -- (Frank's AH9, November 20: every order read "free", so the column told them apart by nothing).
      perRep = x.perRep and (x.perRep < 0 and ("|cff7fd39c+" .. ns.MoneyShort(-x.perRep) .. "|r") or ns.MoneyShort(x.perRep)) or dim("?"),
      writ = x.writ and ns.MoneyShort(x.writ) or dim("-"),
    }
    for key, fs in pairs(r.cells) do
      fs:ClearAllPoints()
      local px, w = lay[key].x, lay[key].w
      if key == "name" then px, w = px + 20, w - 20 end
      fs:SetPoint("LEFT", r, "LEFT", px, 0)
      fs:SetWidth(w)
      fs:SetText(values[key])
    end
    r.add:ClearAllPoints()
    r.add:SetPoint("LEFT", r, "LEFT", lay.add.x, 0)
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  f.content:SetHeight(math.max(#list * ROW, 30))
  f.sf.UpdateScrollBar()
  local opened = {}
  for _, k in ipairs({ "J", "E", "A" }) do
    if sealed[k] then opened[#opened + 1] = ("%d Sealed %s's Writ"):format(sealed[k], TIERS[k].label) end
  end
  f.summary:SetText(("%d orders, %d with a price.   %s"):format(#list, priced,
    #opened > 0 and (T:AccentCode() .. "Still sealed in your bags: " .. table.concat(opened, ", ") .. ": open them to see their orders.|r") or dim((costRun and not costRun.stopped) and "Working out the costs..." or priced < #list and "Orders without a price: nothing listed at your last full scan, and no materials priced." or "Hover an order for the cheapest way to get it.")))
  if s.tier == "mine" and #list == 0 and #opened == 0 then
    f.summary:SetText(dim("No Craftsman's Writs in your bags or bank. They drop from mobs and chests, or buy one on the auction house."))
  end
  -- AHledger's terms: its credit where its prices went into the costs shown (Codex review, November 17).
  if (ns.ahledgerUses or 0) ~= ahlBefore then f.summary:SetText((f.summary:GetText() or "") .. "   " .. dim(ns.AHLEDGER_CREDIT)) end
end

ns.RefreshWrits = ns.Timed("Writs tab", ns.RefreshWrits)

ns._writsTest.frame = function() return f end   -- (tests)
