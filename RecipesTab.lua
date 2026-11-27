local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Recipes tab: every recipe of each profession (from RecipeBook.lua), who knows it,
-- where it comes from (as seen in game), what a craft makes at today's prices, and a
-- type: flip or shuffle, crafts that sell, not for sale, not profitable. Right-click a
-- row to set your own type. A Trainers view lists trainers seen, with map pins.
---------------------------------------------------------------------------
local SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true }
local ALWAYS_SHUFFLE = { [11287] = true, [11288] = true }   -- Lesser and Greater Magic Wand
local MIN_LISTED = 5
local MAX_ROWS = 300
local ROW = 22
local TYPES = {
  shuffle = { label = "Flip or shuffle", short = "Shuffle", color = "7fd39c" },
  sells = { label = "Crafts that sell", short = "Sells", color = "ffd100" },
  enchant = { label = "Enchant service", short = "Enchants", color = "66bbff" },   -- no item to sell; sold as a service
  notsale = { label = "Not for sale", short = "Not for sale", color = "888888" },
  loss = { label = "Not profitable", short = "Loss", color = "ee8597" },
}
local ORDER = { "shuffle", "sells", "enchant", "notsale", "loss" }
local typeRank = {}
for i, k in ipairs(ORDER) do typeRank[k] = i end

local function dim(t) return "|cff888888" .. t .. "|r" end
local function money(v)
  if not v then return dim("?") end
  return (v < 0 and "-" or "") .. ns.Money(math.floor(math.abs(v) + 0.5))
end

local function settings()
  local s = ns.db.settings.recipes
  s.view = s.view or "known"   -- "view", not the first test's "show", so everyone starts on Known
  s.type = s.type or "all"
  if s.custom == nil then s.custom = true end
  s.source = s.source or "all"
  s.skill = s.skill or "all"
  s.group = s.group or "all"
  s.least = tonumber(s.least) or 0
  -- s.sort = { key, desc } after a column heading is clicked; nil keeps the usual order.
  return s
end

---------------------------------------------------------------------------
-- Map pins
---------------------------------------------------------------------------
function ns:PinOnMap(mapID, x, y, label)
  if not (mapID and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint) then
    ns:Print("No position recorded for that yet.")
    return
  end
  local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y))
  if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  ns:Print(ok and ("Map pin set: %s, %s (%.1f, %.1f)."):format(label or "?", info and info.name or "?", x * 100, y * 100)
    or "The game didn't accept a map pin there.")
end

---------------------------------------------------------------------------
-- What a recipe is worth and which type it is
---------------------------------------------------------------------------
local function unitCost(id)
  -- The cheaper of a vendor and the auction house.
  local vendor, ah = ns:GetVendorBuyPrice(id), (ns:GetPrice(id))
  if vendor and ah then return math.min(vendor, ah) end
  return vendor or ah
end

-- Profit per craft at today's prices, and the output's best option (or nil).
local function craftValue(r)
  if not r.out then return end
  local best = ns:BestOption(r.out)
  if not best then return end
  local cost = 0
  for _, m in ipairs(r.r or {}) do
    local c = unitCost(m[1])
    if not c then return nil, best end
    cost = cost + c * m[2]
  end
  return best.value * (r.oq or 1) - cost, best
end

local function autoType(r, prof)
  if ALWAYS_SHUFFLE[r.out or 0] then return "shuffle" end
  -- Enchants make no item: their value is what players pay for the service. (By the
  -- profession, which is English on every client; the name only as a fallback.)
  if not r.out and (prof == "Enchanting" or (r.n or ""):find("^Enchant ")) then return "enchant" end
  local _, _, _, _, _, _, _, _, _, _, sell, _, _, bind = ns.GetItemInfo(r.out or 0)
  local profit, best = craftValue(r)
  if bind == 1 or not best then return "notsale", profit end
  if not profit or profit <= 0 then return "loss", profit end
  if best.kind == "ah" then
    local rec = (ns.db.prices[ns.MarketKey()] or {})[r.out]
    if rec and (rec.q or 0) >= MIN_LISTED then return "sells", profit end
    return "loss", profit
  end
  return "shuffle", profit
end

---------------------------------------------------------------------------
-- Recipes from the game's own data (ForeverCrafts.lua) that no profession window has
-- recorded yet, so a profession nobody of yours has opened still lists its recipes
-- (Frank, November 15: Recipes needs more data). Shaped like recipe book entries:
-- `fc` marks them, `learn` is the recipe item's required skill where the game has one
-- (so the recipe is taught by an item), `rank` the skill the craft starts at.
---------------------------------------------------------------------------
local fcByProf
local function foreverBook(prof)
  if not fcByProf then
    fcByProf = {}
    for _, e in ipairs(ns.FOREVER_CRAFTS or {}) do
      local t = fcByProf[e.prof] or {}
      fcByProf[e.prof] = t
      t[e.id] = { n = ns.SpellName(e.id) or e.n, en = e.n, out = e.out, oq = ((e.low or 1) + (e.high or e.low or 1)) / 2, r = e.r,
        fc = true, learn = e.learn, rank = e.skill }
    end
  end
  return fcByProf[prof] or {}
end
ns.ForeverRecipeBook = foreverBook

-- Every recipe of a profession: the recorded ones, then the game data's others.
local function eachRecipe(prof, fn)
  local book = ns.db.recipeBook[prof] or {}
  for id, r in pairs(book) do fn(id, r) end
  for id, r in pairs(foreverBook(prof)) do
    if not book[id] then fn(id, r) end
  end
end

local function hasRecipes(prof)
  return ns.db.recipeBook[prof] ~= nil or next(foreverBook(prof)) ~= nil
end

---------------------------------------------------------------------------
-- Classic data (ClassicRecipes.lua): turn an entry into a source like the ones seen
-- in game, with a map for pins.
---------------------------------------------------------------------------
-- Zone name -> map ID, from the game's own map list (Classic zone and city maps are
-- numbered 1411-1458; Stormwind City is 1453).
-- The Classic data's zone names are English, so on other clients the game's own map
-- names don't match: these give the map ID in every language (November 24).
local CLASSIC_ZONE_MAPS = {
  ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Alterac Mountains"] = 1416,
  ["Arathi Highlands"] = 1417, ["Badlands"] = 1418, ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420,
  ["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423,
  ["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426, ["Searing Gorge"] = 1427,
  ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429, ["Deadwind Pass"] = 1430, ["Duskwood"] = 1431,
  ["Loch Modan"] = 1432, ["Redridge Mountains"] = 1433, ["Stranglethorn Vale"] = 1434,
  ["Swamp of Sorrows"] = 1435, ["Westfall"] = 1436, ["Wetlands"] = 1437, ["Teldrassil"] = 1438,
  ["Darkshore"] = 1439, ["Ashenvale"] = 1440, ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442,
  ["Desolace"] = 1443, ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446,
  ["Azshara"] = 1447, ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450,
  ["Silithus"] = 1451, ["Winterspring"] = 1452, ["Stormwind City"] = 1453, ["Orgrimmar"] = 1454,
  ["Ironforge"] = 1455, ["Thunder Bluff"] = 1456, ["Darnassus"] = 1457, ["Undercity"] = 1458,
  ["Alterac Valley"] = 1459,
}
ns.CLASSIC_ZONE_MAPS = CLASSIC_ZONE_MAPS
local mapByName
function ns:MapIDForZone(zone)
  if not zone then return end
  if CLASSIC_ZONE_MAPS[zone] then return CLASSIC_ZONE_MAPS[zone] end
  if not mapByName then
    mapByName = {}
    if C_Map and C_Map.GetMapInfo then
      for id = 1400, 1460 do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if ok and info and info.name then mapByName[info.name] = mapByName[info.name] or id end
      end
    end
  end
  return mapByName[zone]
end

local myFaction
local function friendly(npc)
  myFaction = myFaction or ((UnitFactionGroup("player") == "Horde") and "H" or "A")
  return not npc.fac or npc.fac:find(myFaction, 1, true) ~= nil
end

function ns.OtherFaction()
  return UnitFactionGroup("player") == "Horde" and "Alliance" or "Horde"
end

-- Only the other faction can get it: for you, the neutral auction house is the way.
local function otherSideText()
  return (" |cffee8597%s only: neutral AH|r"):format(ns.OtherFaction())
end

-- An NPC from the Classic data as a source table.
local function classicNPC(id, kind)
  local n = ns.CLASSIC_NPCS and ns.CLASSIC_NPCS[id]
  if not n then return end
  return { kind = kind, conf = "classic", npc = n.name, npcID = id, zone = n.zone,
    x = n.x and n.x / 100, y = n.y and n.y / 100, mapID = ns:MapIDForZone(n.zone), fac = n.fac }
end

function ns:ClassicSource(name)
  local e = ns.CLASSIC_RECIPES and ns.CLASSIC_RECIPES[name:lower()]
  if not e then return end
  local s
  if e.kind == "vendor" then
    -- A vendor of your own faction (or neutral) with a position first.
    local best, bestScore
    for _, id in ipairs(e.vendors or {}) do
      local v = classicNPC(id, "vendor")
      if v then
        local score = (friendly(v) and 2 or 0) + (v.mapID and 1 or 0)
        if not best or score > bestScore then best, bestScore = v, score end
      end
    end
    s = best or { kind = "vendor", conf = "classic" }
    s.cost = e.cost
    s.otherSide = best and not friendly(best) or nil
  elseif e.kind == "mob" or e.kind == "drop" then
    local top = e.mobs and e.mobs[1]
    s = top and classicNPC(top[1], e.kind) or { kind = e.kind, conf = "classic" }
    s.chance = top and top[2] or e.chance
    s.mobCount = e.kind == "drop" and (e.mobCount or (e.mobs and #e.mobs)) or nil
  else
    s = { kind = e.kind, conf = "classic", quest = e.quest, otherSide = e.faction == ns.OtherFaction() or nil }
  end
  s.entry = e
  return s
end

-- Tooltip lines for every Classic source of a recipe: all vendors, the top mobs.
function ns:AddClassicSourceLines(tt, name)
  local e = name and ns.CLASSIC_RECIPES and ns.CLASSIC_RECIPES[name:lower()]
  if not e then return end
  ns:AddTooltipLine(tt, " ")
  ns:AddTooltipLine(tt, "In original Classic (unconfirmed in Forever):", 1, 0.82, 0)
  for _, id in ipairs(e.vendors or {}) do
    local v = classicNPC(id, "vendor")
    if v then
      ns:AddTooltipDoubleLine(tt, "Sold by " .. v.npc, (v.zone or "?") .. (v.x and (" %.0f, %.0f"):format(v.x * 100, v.y * 100) or "")
        .. (friendly(v) and "" or (" (%s only)"):format(ns.OtherFaction())), 1, 1, 1, 0.8, 0.8, 0.8)
    end
  end
  for _, m in ipairs(e.mobs or {}) do
    local v = classicNPC(m[1], "mob")
    if v then
      ns:AddTooltipDoubleLine(tt, ("%s (%s%%)"):format(v.npc, m[2] >= 1 and ("%.0f"):format(m[2]) or ("%.2f"):format(m[2])),
        v.zone or "?", 1, 1, 1, 0.8, 0.8, 0.8)
    end
  end
  if e.mobCount and e.mobCount > #(e.mobs or {}) then
    ns:AddTooltipLine(tt, ns.LocalizeText("...and %d more kinds of mob."):format(e.mobCount - #(e.mobs or {})), 0.8, 0.8, 0.8)
  end
  if e.quest then ns:AddTooltipLine(tt, "Quest: " .. e.quest, 1, 1, 1) end
  local s = ns:ClassicSource(name)
  if s and s.otherSide then
    ns:AddTooltipLine(tt, ns.LocalizeText("Only the %s can get this recipe. For you, the way is the neutral auction house (Booty Bay, Gadgetzan, Everlook)."):format(
      ns.OtherFaction()), 0.93, 0.52, 0.59, true)
  end
end

-- The most useful source: seen in game first (vendor or trainer with a position best),
-- otherwise where it came from in original Classic (ClassicRecipes.lua, unconfirmed).
local function bestSource(name, classic)
  if not name then return end
  local pick
  for _, s in pairs(ns.db.recipeSources[name:lower()] or {}) do
    local score = (s.mapID and 2 or 0) + ((s.kind == "vendor" or s.kind == "trainer") and 1 or 0)
    if not pick or score > pick.score then pick = { s = s, score = score } end
  end
  if pick then return pick.s end
  local fromClassic = ns:ClassicSource(classic or name)
  if fromClassic then return fromClassic end
  -- Nothing seen and not in Classic (new in Forever, like Savory Whimsyfin Delight):
  -- if its recipe item is on the auction house, that's where to get it.
  local item = ns.RecipeItemFor and ns.RecipeItemFor(name)
  local rec = item and (ns.db.prices[ns.MarketKey()] or {})[item]
  if rec and rec.m and not rec.none then
    return { kind = "ah", conf = "seen", item = item, price = rec.m, listed = rec.q }
  end
end

-- Recipe items by the recipe they teach ("Recipe: Savory Whimsyfin Delight" -> its item
-- ID), from every item name the addon has seen. Rebuilt when more names are known.
local RECIPE_PREFIXES = { "Formula", "Pattern", "Recipe", "Plans", "Schematic", "Manual", "Design", "Technique" }
local recipeItems, recipeItemsFrom, recipeItemsChecked = {}, -1, 0
function ns.RecipeItemFor(name)
  local names = ns.db.itemNames
  -- Count the names at most every 30 seconds (this runs for every row of the tab).
  local count = recipeItemsFrom
  if GetTime() - recipeItemsChecked > 30 then
    recipeItemsChecked, count = GetTime(), 0
    for _ in pairs(names) do count = count + 1 end
  end
  if count ~= recipeItemsFrom then
    recipeItems, recipeItemsFrom = {}, count
    for id, itemName in pairs(names) do
      for _, p in ipairs(RECIPE_PREFIXES) do
        local rest = itemName:match("^" .. p .. ":%s*(.+)$")
        if rest then recipeItems[rest:lower()] = id; break end
      end
    end
  end
  return recipeItems[name:lower()]
end

-- Chance is in percent.
local function percent(p)
  if not p then return "" end
  if p <= 0 then return "" end
  return dim((" (%s%%)"):format(p >= 1 and ("%.0f"):format(p) or p >= 0.1 and ("%.1f"):format(p)
    or p >= 0.01 and ("%.2f"):format(p) or "<0.01"))
end

-- The recipe item's cheapest auction house listing: price, record (or nil).
local function recipeAH(s)
  local item = s and (s.item or (s.entry and s.entry.item))
  local rec = item and (ns.db.prices[ns.MarketKey()] or {})[item]
  if rec and rec.m and not rec.none then return rec.m, rec end
  return nil, rec
end

local function ahText(s)
  local price, rec = recipeAH(s)
  if price then return "  |cffffd100" .. ns.LocalizeText("AH") .. " " .. ns.Money(price) .. "|r" end
  if rec and rec.none then return dim("  none on AH") end
  return ""
end

local function sourceText(s, fromItem)
  -- Recipes with no recipe item to find were taught by trainers in Classic.
  -- Forever also adds recipes Classic never had (Favor vendors, camping).
  if not s then
    return dim(ns.LocalizeText(fromItem and "a recipe item, not seen yet" or "trainer, or new in Forever"))
  end
  if s.kind == "ah" then
    return ("On the auction house: |cffffd100%s|r %s"):format(ns.Money(s.price), dim(("(%d listed)"):format(s.listed or 0)))
  end
  local classic = s.conf ~= "seen"
  local where = s.zone and (", " .. ns.LocalizeText(s.zone)) or ""
  local text
  if s.kind == "trainer" then
    -- Every trainer of a tier teaches the same list (owner, beta), and higher tiers teach
    -- the lower ones' too, so name the tier and give the one seen as an example.
    local v = s.npcID and ns.db.vendors[s.npcID]
    local prof, tier = v and v.profession, v and v.tier
    if v and not (prof and tier) then
      local p2, t2 = ns.TrainerFromTitle(v.title)   -- defined further down
      prof, tier = prof or p2, tier or t2
    end
    if tier and prof then
      text = ("Any %s+ %s trainer, e.g. %s%s"):format(tier, prof, s.npc or "?", where)
    else
      text = ("Trainer %s%s"):format(s.npc or "?", where)
    end
  elseif s.kind == "vendor" then
    local price = s.currency or (s.cost and ns.Money(s.cost)) or ""
    local side = (classic and s.otherSide) and otherSideText() or ""
    text = ("Vendor %s%s  %s%s%s"):format(s.npc or "?", where, price, s.limited and dim(" limited") or "", side)
  elseif s.kind == "mob" then
    text = ("Drops from %s%s"):format(s.npc or "?", where) .. percent(s.chance) .. ahText(s)
  elseif s.kind == "drop" then
    if s.mobCount then
      -- Kept short so the price fits; the mobs are in the hover.
      text = ("World drop, %d kinds of mob"):format(s.mobCount)
    else
      text = (s.npc and ("Drops from %s%s"):format(s.npc, where) or (s.zone and ("World drop in " .. s.zone) or "World drop, rare"))
        .. percent(s.chance)
    end
    text = text .. ahText(s)
  elseif s.kind == "quest" then
    text = ("Quest: %s"):format(s.quest or "?") .. (s.otherSide and otherSideText() or "")
  else
    text = s.kind or "?"
  end
  -- Short, so prices fit; the hover and summary line explain it.
  return text .. (classic and dim(ns.LocalizeText("  (Classic)")) or "")
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local f
local rows = {}
local drawRecipesVisible   -- fills the recipe rows in view (below)
local current     -- profession shown, or "Trainers:<profession>"
-- Bumped when your recipe types change: the list is built again at once (recipeRows).
local listGen = 0
function ns.RecipesListChanged() listGen = listGen + 1 end

-- num: sorts high to low first (text sorts A to Z first; Type in the usual group order).
local COLS = {
  { key = "name", label = "Recipe", w = 150, grow = 1 },
  { key = "skill", label = "Skill", w = 36, num = true },
  { key = "known", label = "Known by", w = 110 },
  { key = "source", label = "Where from (hover for all)", w = 250, grow = 1 },
  { key = "type", label = "Type", w = 104 },
  { key = "profit", label = "Per craft", w = 80, num = true },
  { key = "pin", label = "", w = 36 },
}
local NUMERIC = {}   -- [key] = true for numbers, false for text; columns with a label only
for _, c in ipairs(COLS) do if c.label ~= "" then NUMERIC[c.key] = c.num or false end end

-- The filters (November 16; Frank: Recipes needs filters, it's a long list).
local SOURCE_OPTS = {
  { value = "all", label = "Any source" }, { value = "trainer", label = "Trainer" }, { value = "vendor", label = "Vendor" },
  { value = "drop", label = "Drop" }, { value = "quest", label = "Quest" }, { value = "ah", label = "On the AH" },
  { value = "unseen", label = "Not seen yet" },
}
local SKILL_OPTS = { { value = "all", label = "Any skill" }, { value = "now", label = "Learnable now" }, { value = "later", label = "Need more skill" } }
local LEAST_OPTS = {
  { value = 0, label = "Any profit" }, { value = 100, label = "1s or more" }, { value = 1000, label = "10s or more" },
  { value = 5000, label = "50s or more" }, { value = 10000, label = "1g or more" }, { value = 50000, label = "5g or more" },
}

-- Which Where from choice a recipe's source falls under. No source: a trainer (or new in
-- Forever), unless the game's data says a recipe item teaches it.
local function sourceKind(src, fromItem)
  if not src then return fromItem and "unseen" or "trainer" end
  if src.kind == "mob" or src.kind == "drop" then return "drop" end
  return src.kind
end
ns.RecipeSourceKind = sourceKind   -- (tests)

-- The tabs: this character's professions (main ones first, then secondary), then
-- Trainers; every other profession with a recipe book goes in the "Other professions"
-- dropdown, starred when another character on this realm and faction has it (owner's
-- test, October 4: all professions as tabs was too many).
local function professions()
  local me = ns.db.chars[ns.CharKey()]
  local mine, others, seen = {}, {}, {}
  for p in pairs((me and me.profs) or {}) do
    if hasRecipes(p) then mine[#mine + 1] = p; seen[p] = true end
  end
  table.sort(mine, function(a, b)
    if (SECONDARY[a] or false) ~= (SECONDARY[b] or false) then return not SECONDARY[a] end
    return a < b
  end)
  foreverBook("")   -- (builds the index)
  for _, set in ipairs({ ns.db.recipeBook, fcByProf }) do
    for p in pairs(set) do
      if not seen[p] then others[#others + 1] = p; seen[p] = true end
    end
  end
  table.sort(others)
  return mine, others
end

-- The rank of a profession by its skill cap, as a coin: gold Artisan (300), silver Expert
-- (225), copper Journeyman (150), none for Apprentice (owner, October 4).
local RANKS = { { 300, "Artisan", "Interface\\MoneyFrame\\UI-GoldIcon" }, { 225, "Expert", "Interface\\MoneyFrame\\UI-SilverIcon" },
  { 150, "Journeyman", "Interface\\MoneyFrame\\UI-CopperIcon" }, { 0, "Apprentice", "Interface\\COMMON\\Indicator-Gray" } }   -- (a grey dot, so every tab lines up: owner, October 4)
local function rankOf(max)
  for _, r in ipairs(RANKS) do if (max or 0) >= r[1] then return r[2], r[3] end end
end

-- Who else on this realm and faction has a profession (first names), or nil.
local function othersWith(prof)
  local names = {}
  for key, c in pairs(ns.db.chars) do
    if key ~= ns.CharKey() and ns:SameMarketChar(key) and c.profs and c.profs[prof] then
      names[#names + 1] = (c.name or key):match("^(%S+)") or c.name
    end
  end
  table.sort(names)
  return #names > 0 and table.concat(names, ", ") or nil
end
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12:0:0|t "

StaticPopupDialogs["FOREVER_LEDGER_CLEAR_TYPES"] = {
  text = "Clear the types you set on %d recipes? They go back to automatic. This can't be undone.",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function()
    wipe(ns.db.recipeTypes)
    ns.RecipesListChanged()
    ns:Print("Your recipe types are cleared.")
    ns:RefreshRecipes()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

function ns:BuildRecipes(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f.tabs = {}
  -- Two rows of choices (redesign build step 6, November 16): what to show, then how
  -- to narrow it. Trainers and Crates hide both.
  f.second = CreateFrame("Frame", nil, f)
  f.second:SetPoint("TOPLEFT", 0, -30)
  f.second:SetPoint("TOPRIGHT", 0, -30)
  f.second:SetHeight(24)
  f.third = CreateFrame("Frame", nil, f)
  f.third:SetPoint("TOPLEFT", 0, -56)
  f.third:SetPoint("TOPRIGHT", 0, -56)
  f.third:SetHeight(24)

  local function tip(frame, title, text)
    frame:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      ns:TooltipAddLine(title, 1, 1, 1)
      ns:TooltipAddLine(text, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end

  local s = settings()
  f.show = T:Choice(f.second, { { value = "all", label = "All" }, { value = "unknown", label = "Not known" }, { value = "known", label = "Known" } },
    function(v) s.view = v; ns:RefreshRecipes() end)
  f.show:SetPoint("LEFT", 0, 0)
  -- Short labels so the row fits the window.
  -- A dropdown: six buttons pushed Use my types off the window with wider fonts
  -- (owner's test, October 4).
  local typeOpts = { { value = "all", label = "Any type" } }
  for _, k in ipairs(ORDER) do typeOpts[#typeOpts + 1] = { value = k, label = TYPES[k].short } end
  f.type = T:Dropdown(f.second, 120, function(v) s.type = v; ns:RefreshRecipes() end)
  f.type:SetOptions(typeOpts)
  f.type:SetPoint("LEFT", f.show, "RIGHT", 14, 0)
  tip(f.type, "Type", "Flip or shuffle, Crafts that sell, Enchant service, Not for sale or Not profitable, at today's prices. Right-click a recipe to give it your own.")
  f.source = T:Dropdown(f.second, 130, function(v) s.source = v; ns:RefreshRecipes() end)
  f.source:SetOptions(SOURCE_OPTS)
  f.source:SetPoint("LEFT", f.type, "RIGHT", 8, 0)
  tip(f.source, "Where from", "Where the recipe is learned: what you've seen in game first, else original Classic data. Not seen yet: taught by a recipe item nobody has spotted.")
  f.skill = T:Dropdown(f.second, 140, function(v) s.skill = v; ns:RefreshRecipes() end)
  f.skill:SetOptions(SKILL_OPTS)
  f.skill:SetPoint("LEFT", f.source, "RIGHT", 8, 0)
  tip(f.skill, "Skill", "Learnable now: one of your characters on this realm and faction has the skill. Need more skill: none has it yet.")

  f.group = T:Dropdown(f.third, 170, function(v) s.group = v; ns:RefreshRecipes() end)
  f.group:SetPoint("LEFT", 0, 0)
  tip(f.group, "Group", "What the recipe makes, by the Groups tab's groups: Potions, Cloth armor, Level 16-25... Only groups this profession makes something in are listed.")
  f.least = T:Dropdown(f.third, 110, function(v) s.least = v; ns:RefreshRecipes() end)
  f.least:SetOptions(LEAST_OPTS)
  f.least:SetPoint("LEFT", f.group, "RIGHT", 8, 0)
  tip(f.least, "Least profit", "Hide recipes that make less than this a craft at today's prices (and ones with no price).")
  f.search = T:EditBox(f.third, 130, "LEFT")
  f.search:SetPoint("LEFT", f.least, "RIGHT", 14, 0)
  f.custom = T:Check(f.third, function(self) s.custom = self:GetChecked(); ns:RefreshRecipes() end)
  f.custom.label:SetText("Use my types")
  f.custom:SetHitRectInsets(0, -(f.custom.label:GetStringWidth() + 8), 0, 0)   -- the name ticks it too
  f.custom:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ns:TooltipAddLine("Use my types", 1, 1, 1)
    ns:TooltipAddLine("On: recipes you right-clicked keep the type you gave them. Off: every recipe uses the automatic type (your choices are kept for later).", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  f.custom:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.custom:SetPoint("LEFT", f.search, "RIGHT", 14, 0)
  f.clear = T:Button(f.third, "Clear my types", 110, function()
    local n = 0
    for _ in pairs(ns.db.recipeTypes) do n = n + 1 end
    if n == 0 then ns:Print("You haven't set any types yet."); return end
    ns:ShowPopup("FOREVER_LEDGER_CLEAR_TYPES", n)
  end, 22)
  f.clear:SetPoint("LEFT", f.custom.label, "RIGHT", 14, 0)
  local hint = T:Text(f.search, 11, T.section)
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Search recipes")
  f.search:SetScript("OnTextChanged", function(self)
    hint:SetShown(self:GetText() == "" and not self:HasFocus())
    ns:RefreshRecipes()
  end)
  f.search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  f.search:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
  f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

  -- The header and list move up when Trainers hides the rows of choices.
  f.header = CreateFrame("Frame", nil, f)
  f.header:SetHeight(22)
  T:Fill(f.header, { 1, 1, 1, 0.05 })
  f.heads = {}
  f.sf, f.content = T:Scroll(f)
  f.sf:HookScript("OnVerticalScroll", function() drawRecipesVisible() end)
  f.sf:HookScript("OnSizeChanged", function() drawRecipesVisible() end)
  f.summary = T:Text(f, 11, T.dim)
  f.summary:SetPoint("BOTTOMLEFT", 4, 2)
  f.empty = T:Text(f.content, 12, T.dim)
  f.empty:SetPoint("TOPLEFT", 8, -8)
  f.empty:SetPoint("RIGHT", f.content, "RIGHT", -8, 0)
  f.empty:SetJustifyH("LEFT")

  -- Waylaid Crates live here too, as a tab after Trainers (Crates.lua builds the view).
  f.cratesHost = CreateFrame("Frame", nil, f)
  f.cratesHost:SetPoint("TOPLEFT", 0, -30)
  f.cratesHost:SetPoint("BOTTOMRIGHT")
  f.cratesHost:Hide()
  ns:BuildCrates(f.cratesHost)
  -- Craftsman's Writs beside them (Writs.lua).
  f.writsHost = CreateFrame("Frame", nil, f)
  f.writsHost:SetPoint("TOPLEFT", 0, -30)
  f.writsHost:SetPoint("BOTTOMRIGHT")
  f.writsHost:Hide()
  ns:BuildWrits(f.writsHost)
  return f
end

-- Profession sub-tabs (with their rank coin), Trainers, and the Other professions dropdown.
local function layoutTabs(list, others)
  local me = ns.db.chars[ns.CharKey()] or { profs = {} }
  me.profs = me.profs or {}
  local sig = table.concat(list, ",") .. "|" .. table.concat(others, ",") .. "|" .. tostring(ns.db.settings.crates)
  for _, p in ipairs(list) do sig = sig .. ":" .. tostring(me.profs[p] and me.profs[p].max) end
  if f.tabSig ~= sig then
    for _, b in pairs(f.tabs) do b:Hide() end
    f.tabs = {}
    local prev
    local function add(key, label, tip)
      local b = T:Tab(f, label, function() current = key; ns:RefreshRecipes() end)
      if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("TOPLEFT", -6, 4) end
      if tip then
        b:HookScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
          ns:TooltipAddLine(tip, 1, 1, 1)
          GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
      end
      f.tabs[key] = b
      prev = b
    end
    for _, p in ipairs(list) do
      local info = me.profs[p]
      local rank, icon = rankOf(info and info.max)
      add(p, (icon and ("|T" .. icon .. ":12:12:0:0|t ") or "") .. p,
        ("%s %s/%s, %s"):format(p, tostring(info and info.rank or "?"), tostring(info and info.max or "?"), rank))
    end
    add("trainers", "Trainers")
    if ns.db.settings.crates then add("crates", "Crates", "Waylaid Crates: the cheapest way to fill each one") end
    if ns.db.settings.crates then add("writs", "Writs", "Craftsman's Writs: what each order costs per point of reputation") end
    -- Other professions: a dropdown after the tabs.
    if not f.other then
      f.other = T:Dropdown(f, 170, function(v) if v ~= "" then current = v; ns:RefreshRecipes() end end)
      f.other:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        ns:TooltipAddLine("Other professions", 1, 1, 1)
        ns:TooltipAddLine("Professions this character doesn't have. A star: another of your characters on this realm and faction has it.", nil, nil, nil, true)
        GameTooltip:Show()
      end)
      f.other:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local opts = { { value = "", label = "Other professions" } }
    for _, p in ipairs(others) do
      local who = othersWith(p)
      opts[#opts + 1] = { value = p, label = who and (STAR .. p .. "  |cff888888" .. who .. "|r") or p }
    end
    f.other:SetOptions(opts)
    f.other:ClearAllPoints()
    f.other:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    f.other:SetShown(#others > 0)
    f.tabSig = sig
  end
  local isOther = false
  for _, p in ipairs(others) do if p == current then isOther = true end end
  if not current or not (f.tabs[current] or isOther) then current = list[1] or "trainers" end
  for key, b in pairs(f.tabs) do b:SetSelected(key == current) end
  f.other:SetValue(isOther and current or "")
  f.other:SetSelected(isOther)
end

-- Columns with grow share the room left over, so a wider window gives the recipe name
-- and Where from more space (owner's test, October 4: only the names got wider).
local function layout(cols, width)
  local fixed, grow = 0, 0
  for _, c in ipairs(cols) do fixed = fixed + (c.w or 150) + 8; grow = grow + (c.grow or 0) end
  local extra = math.max(0, width - fixed - 4)
  local x, out = 4, {}
  for _, c in ipairs(cols) do
    local w = (c.w or 150) + (grow > 0 and c.grow and math.floor(extra * c.grow / grow) or 0)
    out[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  return out
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, f.content)
  r:SetHeight(ROW)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.08)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cells = {}
  for _, c in ipairs(COLS) do
    if c.key ~= "pin" then
      local fs = T:Text(r, 11)
      fs:SetWordWrap(false)
      fs:SetJustifyH(c.key == "profit" and "RIGHT" or "LEFT")
      r.cells[c.key] = fs
    end
  end
  r.pin = T:Button(r, "Pin", 34, function(self)
    local s = self:GetParent().src
    if s then ns:PinOnMap(s.mapID, s.x, s.y, s.npc or s.name) end
  end, 18)
  -- Right-click: set your own type (cycles through the types, then back to automatic).
  r:SetScript("OnClick", function(self, button)
    if button ~= "RightButton" or not self.recipeID then return end
    if not settings().custom then
      ns:Print("Tick \"Use my types\" first to set your own types.")
      return
    end
    local overrides = ns.db.recipeTypes
    -- Shift-right-click: back to the automatic type.
    if IsShiftKeyDown() then
      overrides[self.recipeID] = nil
      ns.RecipesListChanged()
      ns:RefreshRecipes()
      return
    end
    local now = overrides[self.recipeID]
    local nextType
    if not now then nextType = ORDER[1] else
      for i, k in ipairs(ORDER) do if k == now then nextType = ORDER[i + 1] end end
    end
    overrides[self.recipeID] = nextType
    ns.RecipesListChanged()
    ns:RefreshRecipes()
  end)
  r:SetScript("OnEnter", function(self)
    if not self.out then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetItemByID(self.out)
    ns:AddClassicSourceLines(GameTooltip, self.recipeName)
    local price, rec = recipeAH(self.src)
    if price then
      ns:TooltipAddLine(" ")
      ns:TooltipAddDoubleLine("Recipe on the auction house", ns.Money(price), 1, 0.82, 0, 1, 1, 1)
      ns:TooltipAddLine(ns.LocalizeText("%d listed, scanned %s"):format(rec.q or 0, ns.Age(rec.t)), 0.8, 0.8, 0.8)
    elseif rec and rec.none then
      ns:TooltipAddLine(" ")
      ns:TooltipAddLine(ns.LocalizeText("Recipe not on the auction house (scanned %s)"):format(ns.Age(rec.t)), 0.8, 0.8, 0.8)
    end
    ns:TooltipAddLine(" ")
    ns:TooltipAddLine("Right-click to set your own type, shift-right-click for automatic.", T.accent[1], T.accent[2], T.accent[3])
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function knownBy(prof, recipeID)
  local names = {}
  -- Characters who could craft it for you: same ruleset and faction (Core.lua).
  for key, c in pairs(ns.db.chars) do
    local p = ns:SameMarketChar(key) and c.profs and c.profs[prof]
    if p and p.recipes and p.recipes[recipeID] then names[#names + 1] = c.name or key end
  end
  table.sort(names)
  return names
end

-- Skill needed to learn a recipe: from a trainer seen in game, else Classic's, else the
-- game's data (the recipe item's requirement, or the skill the craft starts at).
local function skillFor(prof, id, r)
  local name = r and r.n
  if name then
    for _, s in pairs(ns.db.recipeSources[name:lower()] or {}) do
      if s.skill and s.skill > 0 then return s.skill end
    end
  end
  local fc = foreverBook(prof)[id]
  local classic = (fc and fc.en) or name
  local e = classic and ns.CLASSIC_RECIPES and ns.CLASSIC_RECIPES[classic:lower()]
  if e and e.skill then return e.skill end
  return fc and (fc.learn or fc.rank)
end

-- Highest skill any of your characters has in a profession.
local function bestRank(prof)
  local best
  for key, c in pairs(ns.db.chars) do
    local p = ns:SameMarketChar(key) and c.profs and c.profs[prof]
    if p and p.rank then best = math.max(best or 0, p.rank) end
  end
  return best
end

-- Green: one of your characters has the skill; red: not yet.
local function skillText(skill, rank)
  if not skill then return dim("?") end
  if not rank then return tostring(skill) end
  return (rank >= skill and "|cff7fd39c%d|r" or "|cffee8597%d|r"):format(skill)
end

-- The Group choices for a profession: groups (built in, two levels deep, and yours) that
-- hold something it makes, with each output's set of groups. Worked out again when the
-- profession or its recipe count changes, or after a minute (groups can be edited).
local groupCache = {}
local function groupChoices(prof)
  local count = 0
  eachRecipe(prof, function() count = count + 1 end)
  local c = groupCache[prof]
  if c and c.count == count and GetTime() - c.t < 60 then return c end
  c = { count = count, t = GetTime(), sets = {}, opts = { { value = "all", label = "Any group" } } }
  local present = {}
  if ns.ItemGroupSet then
    -- Worked out in the list's slices (buildList), giving frames back: every recipe's
    -- groups, 43 ms in one frame on the tab (Frank's fifteenth /fl perf, November 21). The
    -- IDs first, as a recipe can be recorded in between.
    local book, fc = ns.db.recipeBook[prof] or {}, foreverBook(prof)
    local ids = ns.KeysOf(book)
    for id in pairs(fc) do if book[id] == nil then ids[#ids + 1] = id end end
    for _, id in ipairs(ids) do
      local r = book[id] or fc[id]
      if r and r.out and not c.sets[r.out] then
        c.sets[r.out] = ns:ItemGroupSet(r.out)
        for gid in pairs(c.sets[r.out]) do present[gid] = true end
      end
      if ns.MaybeYield then ns.MaybeYield() end
    end
    for _, g in ipairs(ns:GroupTree()) do
      if present[g.id] and (g.kind == "user" or (g.kind == "builtin" and g.depth <= 1)) then
        c.opts[#c.opts + 1] = { value = g.id, label = (g.depth > 0 and "   " or "") .. g.name }
      end
    end
  end
  groupCache[prof] = c
  return c
end
-- The group dropdown's choices: the profession's own once worked out; before that (its
-- first list) Any group and the chosen group kept, never another profession's choices
-- (Codex review, November 21).
local function groupOptions(gc, chosen)
  if gc then return gc.opts end
  local opts = { { value = "all", label = "Any group" } }
  if chosen ~= "all" then opts[2] = { value = chosen, label = "Working out groups..." } end
  return opts
end

-- What a row sorts by in a column (nil: no value, always last).
local function plain(text)
  return (text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):lower())
end
local function sortValue(e, key)
  if key == "name" then return e.r.n and e.r.n:lower() end
  if key == "skill" then return e.skill end
  if key == "known" then return #e.names > 0 and table.concat(e.names, ", "):lower() or nil end
  if key == "source" then return e.src and plain(sourceText(e.src)) or nil end
  if key == "type" then return typeRank[e.type] end   -- the usual group order, not A to Z
  if key == "profit" then return e.profit end
end

-- One recipe row (f.rdraw: the list and columns as last worked out).
local function drawRecipe(i)
  local d = f.rdraw
  local e, row, lay, rank, prof = d.list[i], getRow(i), d.lay, d.rank, d.prof
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW)
  row:SetWidth(d.width)
  row.stripe:SetShown(i % 2 == 0)
  row.recipeID, row.out, row.recipeName = e.id, e.r.out, e.en
  row.cells.profit:SetJustifyH("RIGHT")
  row.icon:SetTexture(e.r.out and ns:ItemIcon(e.r.out) or "Interface\\Icons\\INV_Misc_QuestionMark")
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", row, "LEFT", lay.name.x, 0)
  local src = e.src
  row.src = src
  local tinfo = TYPES[e.type]
  local values = {
    name = e.r.n or "?",
    skill = skillText(e.skill, rank),
    known = #e.names > 0 and table.concat(e.names, ", ") or (SECONDARY[prof] and "|cff7fd39canyone can learn|r" or dim("nobody yet")),
    source = sourceText(src, e.fromItem),
    type = ("|cff%s%s|r%s"):format(tinfo.color, tinfo.label, e.override and dim(" (yours)") or ""),
    profit = money(e.profit),
  }
  for key, fs in pairs(row.cells) do
    local x, w = lay[key].x, lay[key].w
    if key == "name" then x, w = x + 20, w - 20 end
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(w)
    fs:SetText(values[key])
    fs:Show()
  end
  row.pin:ClearAllPoints()
  row.pin:SetPoint("LEFT", row, "LEFT", lay.pin.x, 0)
  row.pin:SetShown(src and src.mapID and src.x and true or false)
  row:Show()
end

-- The recipe rows in view, and a screen's worth either side, each drawn once per refresh.
drawRecipesVisible = function()
  local d = f and f.rdraw
  if not d then return end
  local top, h = f.sf:GetVerticalScroll() or 0, f.sf:GetHeight() or 0
  if h <= 0 then h = 30 * ROW end
  local first = math.max(1, math.floor(top / ROW) + 1 - 10)
  local last = math.min(d.n, math.ceil((top + h) / ROW) + 10)
  for i = first, last do
    if not d.done[i] then d.done[i] = true; drawRecipe(i) end
  end
end

-- A profession's list for the choices above, built a little each frame (Frank's /fl perf,
-- November 21: 47-101 ms in one go on opening the tab or changing a choice). Kept until a
-- choice or what the list is made from changes (the recipe book, where recipes come from,
-- which character knows what at which skill, values, your recipe types), or a minute
-- passes (Codex review, November 21: a recipe just learned, a vendor just seen or a
-- material's new price waited for the minute).
-- Values change all the time while Live watch reads the auction house, so their changes
-- are taken in at most every VALUES_EVERY seconds (then the tab is drawn again).
local VALUES_EVERY = 10
local valuesSeen, valuesSeenAt, valuesTimer = nil, -math.huge, false
local function valuesKey()
  local now, v = GetTime(), ns.ValuesChanges and ns.ValuesChanges() or 0
  if v ~= valuesSeen then
    if now - valuesSeenAt >= VALUES_EVERY then
      valuesSeen, valuesSeenAt = v, now
    elseif not valuesTimer then
      valuesTimer = true
      C_Timer.After(VALUES_EVERY - (now - valuesSeenAt), function()
        valuesTimer = false
        if f and f:IsVisible() then ns:RefreshRecipes() end
      end)
    end
  end
  return valuesSeen
end
-- Each character's skill and recipes in this profession (a recipe learned here, or by
-- your other account's character, changes its count or time).
local function charsKey(prof)
  local parts = {}
  for key, c in pairs(ns.db.chars) do
    local p = c.profs and c.profs[prof]
    if p then parts[#parts + 1] = ("%s=%s:%s:%s"):format(key, tostring(p.rank), tostring(p.updated), tostring(p.recipeCount)) end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end
-- Returns the choices alone, and the whole stamp.
local function listStamp(prof, s, match)
  local sort = s.sort
  local choices = table.concat({ prof, tostring(s.view), tostring(s.group), tostring(s.type), tostring(s.least),
    tostring(s.skill), tostring(s.source), tostring(s.custom), tostring(sort and sort.key), tostring(sort and sort.desc),
    match }, "\1")
  return choices, table.concat({ choices, tostring(ns.recipeBookStamp or 0), tostring(ns.recipeSourceStamp or 0),
    charsKey(prof), tostring(ns.ValuesStamp and ns.ValuesStamp() or 0), tostring(valuesKey()), tostring(listGen),
    tostring(math.floor(time() / 60)) }, "\1")
end

local function buildList(prof, s, match)
  local rank = bestRank(prof)
  local groups = groupChoices(prof)
  local fc = foreverBook(prof)
  local ahlBefore = ns.AHledgerUses and ns.AHledgerUses() or 0
  -- (The IDs first: a recipe recorded while this waits for the next frame can't break the walk.)
  local book = ns.db.recipeBook[prof] or {}
  local ids = ns.KeysOf(book)
  for id in pairs(fc) do if book[id] == nil then ids[#ids + 1] = id end end
  local list = {}
  local total, knownCount = 0, 0
  local function visit(id, r)
    local names = knownBy(prof, id)
    local known = #names > 0
    total = total + 1
    if known then knownCount = knownCount + 1 end
    if not ((s.view == "all" or (s.view == "known") == known) and (match == "" or (r.n or ""):lower():find(match, 1, true))) then return end
    if s.group ~= "all" and not (r.out and groups.sets[r.out] and groups.sets[r.out][s.group]) then return end
    local auto, profit = autoType(r, prof)
    local mine = s.custom and ns.db.recipeTypes[id] or nil
    local t = mine or auto
    if s.type ~= "all" and s.type ~= t then return end
    if s.least > 0 and not (profit and profit >= s.least) then return end
    local skill = skillFor(prof, id, r)
    if s.skill == "now" and not (skill and rank and skill <= rank) then return end
    if s.skill == "later" and not (skill and (not rank or skill > rank)) then return end
    local fromItem = fc[id] and fc[id].learn and true or false
    local en = fc[id] and fc[id].en or r.n
    local src = bestSource(r.n, en)
    if s.source ~= "all" and sourceKind(src, fromItem) ~= s.source then return end
    list[#list + 1] = { id = id, r = r, names = names, type = t, override = mine ~= nil, profit = profit,
      skill = skill, src = src, fromItem = fromItem, en = en }
  end
  for _, id in ipairs(ids) do
    ns.MaybeYield()
    local r = book[id] or fc[id]
    if r then visit(id, r) end
  end
  -- Grouped by type (flip or shuffle first), then most profit first.
  local function usual(a, b)
    if a.type ~= b.type then return typeRank[a.type] < typeRank[b.type] end
    if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
    if a.profit and b.profit and a.profit ~= b.profit then return a.profit > b.profit end
    return (a.r.n or "") < (b.r.n or "")
  end
  -- A clicked column heading: by that column, ties and rows with no value in the usual order.
  local sort = s.sort
  if sort and NUMERIC[sort.key] ~= nil then
    for _, e in ipairs(list) do ns.MaybeYield(); e.sortBy = sortValue(e, sort.key) end
    ns.SortInSlices(list, function(a, b)
      local va, vb = a.sortBy, b.sortBy
      if va == nil or vb == nil or va == vb then
        if (va == nil) ~= (vb == nil) then return va ~= nil end
        return usual(a, b)
      end
      if sort.desc then return va > vb end
      return va < vb
    end)
  else
    ns.SortInSlices(list, usual)
  end
  return { prof = prof, list = list, total = total, knownCount = knownCount, rank = rank,
    ahl = (ns.AHledgerUses and ns.AHledgerUses() or 0) ~= ahlBefore or nil }
end

-- Returns how many rows are shown, the profession's recipe count, and whether the list is
-- still being worked out. The last list of the same profession stays on screen meanwhile.
local recipeRun, recipeBuilding, buildingChoices
local function recipeRows(prof, width, lay)
  local s = settings()
  local match = (f.search:GetText() or ""):lower()
  local choices, stamp = listStamp(prof, s, match)
  local cached = f.rcache and f.rcache.stamp == stamp and f.rcache
  if cached then
    -- Back to a list still kept: a build for something else isn't wanted any more (Codex
    -- review, November 21: another profession's build finished and took its place).
    if recipeBuilding then ns.StopSlices(recipeRun); recipeBuilding, buildingChoices = nil, nil end
  elseif buildingChoices ~= choices then
    -- (A choice changed during a build: that build is dropped. When only what the list is
    -- made from changed, the build under way finishes first and the next starts then, so
    -- changes coming often can't keep it from ever finishing.)
    ns.StopSlices(recipeRun)
    recipeBuilding, buildingChoices = stamp, choices
    if ns.FreshValues then ns.FreshValues() end   -- (values out of date go now: in slices they're kept)
    local inside = true
    recipeRun = ns.RunInSlices("Recipes list", function() return buildList(prof, s, match) end, function(result)
      if recipeBuilding ~= stamp then return end
      recipeBuilding, buildingChoices, result.stamp, f.rcache = nil, nil, stamp, result
      if not inside then ns:RefreshRecipes() end
    end, function() if recipeBuilding == stamp then recipeBuilding, buildingChoices = nil, nil end end)
    inside = false
    cached = f.rcache and f.rcache.stamp == stamp and f.rcache   -- (done within the first slice)
  end
  local shown = cached or (f.rcache and f.rcache.prof == prof and f.rcache) or nil
  -- (AHledger's credit, below, where its prices went into the profits shown.)
  if shown and shown.ahl then ns.ahledgerUses = (ns.ahledgerUses or 0) + 1 end
  local list = shown and shown.list or {}
  local n = math.min(#list, MAX_ROWS)
  -- Only the rows in view (and a few either side) are drawn, more as you scroll (Frank's
  -- tenth /fl perf, November 21: all 300 drawn on each refresh took 60 ms).
  f.rdraw = { list = list, lay = lay, width = width, rank = shown and shown.rank, prof = prof, n = n, done = {} }
  for _, r in pairs(rows) do r:Hide() end   -- (pairs: the pool has gaps after a scroll jump; Codex review)
  drawRecipesVisible()
  if shown then
    f.summary:SetText(ns.LocalizeText("%s: %d recipes, %d known. Showing %d%s. (Classic) = original Classic data, unconfirmed in Forever until you see it."):format(
      prof, shown.total, shown.knownCount, n, #list > MAX_ROWS and (" of " .. #list) or ""))
  else
    f.summary:SetText(ns.LocalizeText("%s: working out the list..."):format(prof))
  end
  return n, shown and shown.total or 0, not cached
end

-- The Trainers view has its own column widths (same keys, so rows can be shared).
local TRAINER_COLS = {
  { key = "name", label = "Trainer", w = 150, grow = 1 },
  { key = "skill", label = "", w = 0 },
  { key = "known", label = "Profession", w = 110 },
  { key = "source", label = "Where", w = 240, grow = 1 },
  { key = "type", label = "Tier", w = 90 },
  { key = "profit", label = "Title or note", w = 140 },   -- (330 + 230 ran off the window at its smallest: October 4)
  { key = "pin", label = "", w = 36 },
}

-- Profession and tier from a trainer's title: "Expert Tailor", "Tailoring Trainer".
local TITLE_PROF = {
  { "Tailor", "Tailoring" }, { "Enchant", "Enchanting" }, { "Cook", "Cooking" }, { "First Aid", "First Aid" },
  { "Physician", "First Aid" }, { "Fish", "Fishing" }, { "Alchemist", "Alchemy" }, { "Alchemy", "Alchemy" },
  { "Blacksmith", "Blacksmithing" }, { "Leatherwork", "Leatherworking" }, { "Engineer", "Engineering" },
  { "Herbalis", "Herbalism" }, { "Miner", "Mining" }, { "Mining", "Mining" }, { "Skinn", "Skinning" },
}
local TIERS = { Apprentice = true, Journeyman = true, Expert = true, Artisan = true }
local function fromTitle(title)
  if not title then return end
  local prof
  for _, p in ipairs(TITLE_PROF) do
    if title:find(p[1], 1, true) then prof = p[2]; break end
  end
  local first = title:match("^(%a+)")
  return prof, TIERS[first or ""] and first or nil
end
function ns.ProfessionFromTitle(title) return (fromTitle(title)) end
ns.TrainerFromTitle = fromTitle

local function trainerRows(width, lay)
  local list, seen = {}, {}
  -- Matched by NPC number (names differ by language), the name only as a fallback.
  local classicByName, classicByNpc, seenNpc = {}, {}, {}
  for _, t in ipairs(ns.CLASSIC_TRAINERS or {}) do
    classicByName[t.name:lower()] = t
    if t.npc then classicByNpc[t.npc] = t end
  end
  for npcID, v in pairs(ns.db.vendors) do
    if v.trainer then
      -- Fill what the trainer window didn't give: from the title, then the Classic list.
      local prof, tier = fromTitle(v.title)
      local c = classicByNpc[tonumber(npcID) or 0] or (v.name and classicByName[v.name:lower()])
      list[#list + 1] = { id = npcID, v = v, profession = v.profession or prof or (c and c.profession),
        tier = v.tier or tier or (c and c.tier) }
      if v.name then seen[v.name:lower()] = true end
      if tonumber(npcID) then seenNpc[tonumber(npcID)] = true end
    end
  end
  local classicCount = 0
  -- Classic trainers (ClassicRecipes.lua, positions from pfQuest) not visited yet.
  for _, t in ipairs(ns.CLASSIC_TRAINERS or {}) do
    if not (seen[t.name:lower()] or (t.npc and seenNpc[t.npc])) then
      local n = t.npc and classicNPC(t.npc, "trainer") or {}
      list[#list + 1] = { classic = true, profession = t.profession, tier = t.tier,
        v = { name = t.name, title = t.title, zone = n.zone or t.zone, x = n.x, y = n.y, mapID = n.mapID } }
      classicCount = classicCount + 1
    end
  end
  -- Where a city guard said each profession's trainer is (Probe.lua saves guard map
  -- flags with the option you picked). Forever's own positions: the shop, not the NPC.
  local PROFS = { Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
    Leatherworking = true, Mining = true, Skinning = true, Tailoring = true, Cooking = true, ["First Aid"] = true,
    Fishing = true }
  -- When the flag names a trainer we know (Lucan Cordell), their profession wins over the
  -- option recorded: early tests sometimes recorded the option next to the one picked.
  local knownProf = {}
  for _, t in ipairs(ns.CLASSIC_TRAINERS or {}) do knownProf[t.name:lower()] = t.profession end
  for _, v in pairs(ns.db.vendors) do
    if v.trainer and v.name then
      local p = v.profession or (ns.ProfessionFromTitle and ns.ProfessionFromTitle(v.title))
      if p then knownProf[v.name:lower()] = p end
    end
  end
  local guardCount, latest = 0, {}
  for _, g in ipairs(ns.db.guardPOIs or {}) do
    -- Flags saved before the option fix (no v) only count when they name a known trainer.
    local prof = (g.name and knownProf[g.name:lower()]) or (g.v == 2 and g.option) or nil
    if prof and PROFS[prof] and g.mapID and g.x then latest[prof .. ":" .. g.mapID] = { g = g, prof = prof } end
  end
  -- A flag that names a trainer already listed doesn't get a row of its own: a visited
  -- trainer is already Forever's real spot, and a Classic one takes the guard's position
  -- (Shaina Fuller moved from 43.1, 26.2 in Classic to 52.9, 44.9 in Forever).
  local byName = {}
  for _, e in ipairs(list) do if e.v.name then byName[e.v.name:lower()] = e end end
  for key, entry in pairs(latest) do
    local same = entry.g.name and byName[entry.g.name:lower()]
    if same then
      latest[key] = nil
      if same.classic then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(entry.g.mapID)
        same.classic, same.guard, same.named = nil, true, true
        same.v.zone, same.v.x, same.v.y, same.v.mapID = info and info.name or same.v.zone, entry.g.x, entry.g.y, entry.g.mapID
        classicCount = classicCount - 1
        guardCount = guardCount + 1
      end
    end
  end
  for _, entry in pairs(latest) do
    local g = entry.g
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(g.mapID)
    list[#list + 1] = { guard = true, profession = entry.prof,
      v = { name = g.name or "?", title = "from " .. (g.npc or "a city guard"), zone = info and info.name or "?",
        x = g.x, y = g.y, mapID = g.mapID } }
    guardCount = guardCount + 1
  end
  local TIER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }
  table.sort(list, function(a, b)
    -- Unknown professions last.
    local pa, pb = a.profession or "~", b.profession or "~"
    if pa ~= pb then return pa < pb end
    local ta, tb = TIER[a.tier or ""] or 0, TIER[b.tier or ""] or 0
    if ta ~= tb then return ta > tb end
    return (a.v.name or "") < (b.v.name or "")
  end)
  for i, e in ipairs(list) do
    local row = getRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW)
    row:SetWidth(width)
    row.stripe:SetShown(i % 2 == 0)
    row.recipeID, row.out, row.recipeName = nil, nil, nil
    row.cells.profit:SetJustifyH("LEFT")
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", lay.name.x, 0)
    row.src = e.v
    local values = {
      name = e.v.name or "?",
      skill = "",
      known = e.profession or dim("?"),
      source = ("%s%s%s"):format(ns.LocalizeText(e.v.zone or "?"), e.v.x and ("  (%.1f, %.1f)"):format(e.v.x * 100, e.v.y * 100) or "",
        e.classic and dim(ns.LocalizeText("  (Classic)")) or e.guard and "  |cff7fd39c(guard)|r" or ""),
      type = e.tier or (e.guard and not e.named and dim("shop") or dim("?")),
      profit = e.v.title and dim(e.v.title) or "",
    }
    for key, fs in pairs(row.cells) do
      local x, w = lay[key].x, lay[key].w
      if key == "name" then x, w = x + 20, w - 20 end
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", row, "LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetText(values[key])
      fs:Show()
    end
    row.pin:ClearAllPoints()
    row.pin:SetPoint("LEFT", row, "LEFT", lay.pin.x, 0)
    row.pin:SetShown(e.v.mapID and e.v.x and true or false)
    row:Show()
  end
  f.summary:SetText(ns.LocalizeText("%d trainers seen, %d from city guards, %d more from Classic (unconfirmed). Ask a guard for a profession trainer to add Forever's real spot."):format(
    #list - classicCount - guardCount, guardCount, classicCount))
  return #list
end

function ns:RefreshRecipes()
  if not f or not f:IsShown() then return end
  local ahlBefore = ns.AHledgerUses and ns.AHledgerUses() or 0
  local s = settings()
  f.show:SetValue(s.view)
  f.custom:SetChecked(s.custom)
  f.type:SetValue(s.type)
  f.source:SetValue(s.source)
  f.skill:SetValue(s.skill)
  f.least:SetValue(s.least)
  layoutTabs(professions())   -- (mine, others)
  local trainers, writs = current == "trainers", current == "writs"
  local crates = current == "crates" or writs   -- (the same: the list's parts hidden)
  f.second:SetShown(not trainers and not crates)
  f.third:SetShown(not trainers and not crates)
  f.header:SetShown(not crates)
  f.sf:SetShown(not crates)
  f.summary:SetShown(not crates)
  f.cratesHost:SetShown(crates and not writs)
  f.writsHost:SetShown(writs)
  if writs then ns:RefreshWrits(); return end
  if crates then ns:RefreshCrates(); return end
  local top = trainers and -30 or -84
  f.header:ClearAllPoints()
  f.header:SetPoint("TOPLEFT", 0, top)
  f.header:SetPoint("TOPRIGHT", 0, top)
  f.sf:ClearAllPoints()
  f.sf:SetPoint("TOPLEFT", 0, top - 24)
  f.sf:SetPoint("BOTTOMRIGHT", 0, 20)
  -- The group choices are worked out with the list (buildList); the last ones meanwhile.
  local function knownGroups() return not trainers and current and groupCache[current] or nil end
  local gc = knownGroups()
  if gc then
    -- A group chosen for another profession that makes nothing in it here: back to Any.
    local found = false
    for _, o in ipairs(gc.opts) do if o.value == s.group then found = true end end
    if not found then s.group = "all" end
  end

  local width = f:GetWidth() - 20   -- (clear of the scroll bar)
  local cols = trainers and TRAINER_COLS or COLS
  local lay = layout(cols, width)
  -- Recipe columns sort when their heading is clicked (not the Trainers view).
  local sort = not trainers and s.sort or nil
  for i, c in ipairs(cols) do
    local h = f.heads[i]
    if not h then
      h = CreateFrame("Button", nil, f.header)
      h.fs = T:Text(h, 11, T.dim)
      h.fs:SetAllPoints()
      h:SetScript("OnClick", function(self)
        if not self.key then return end
        local st = settings()
        local cur = st.sort
        if cur and cur.key == self.key then cur.desc = not cur.desc
        else st.sort = { key = self.key, desc = NUMERIC[self.key] and true or false } end
        ns:RefreshRecipes()
      end)
      f.heads[i] = h
    end
    local sortable = not trainers and c.label ~= ""
    h.key = sortable and c.key or nil
    h:EnableMouse(sortable)
    h:ClearAllPoints()
    h:SetPoint("LEFT", f.header, "LEFT", lay[c.key].x, 0)
    h:SetSize(math.max(lay[c.key].w, 1), 22)
    h.fs:SetJustifyH(c.key == "profit" and not trainers and "RIGHT" or "LEFT")
    local sorted = sort and sortable and sort.key == c.key
    h.fs:SetText(ns.LocalizeText(c.label) .. (sorted and (sort.desc and " v" or " ^") or ""))
    local col = sorted and { T.accent[1], T.accent[2], T.accent[3], 1 } or T.dim
    h.fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
  end

  f.content:SetWidth(width)
  local n, total, loading = 0, 0, false
  f.rdraw = nil   -- (the Trainers view draws all its rows: a few)
  if trainers then n = trainerRows(width, lay) elseif current then n, total, loading = recipeRows(current, width, lay) end
  gc = knownGroups()   -- (worked out just now if the list was done within its first frame)
  if not trainers and current then
    f.group:SetOptions(groupOptions(gc, s.group))
    f.group:SetValue(s.group)
  end
  for i, r in pairs(rows) do if i > n then r:Hide() end end   -- (pairs: gaps after a scroll jump)
  f.empty:SetShown(n == 0)
  -- Recipes there but all hidden by the choices above: say which (Frank, AN6, November 13:
  -- Skinning looked empty on Known, as none of his characters knows its 3 recipes).
  local why = {}
  if s.view == "known" then why[#why + 1] = "Known only" elseif s.view == "unknown" then why[#why + 1] = "Not known only" end
  if s.type ~= "all" and TYPES[s.type] then why[#why + 1] = TYPES[s.type].label end
  local function label(opts, v)
    for _, o in ipairs(opts) do if o.value == v then return (o.label:gsub("^%s+", "")) end end
    return tostring(v)
  end
  if s.source ~= "all" then why[#why + 1] = label(SOURCE_OPTS, s.source) end
  if s.skill ~= "all" then why[#why + 1] = label(SKILL_OPTS, s.skill) end
  if s.group ~= "all" and gc then why[#why + 1] = label(gc.opts, s.group) end
  if s.least > 0 then why[#why + 1] = label(LEAST_OPTS, s.least) end
  local match = f.search:GetText() or ""
  if match ~= "" then why[#why + 1] = ('search "%s"'):format(match) end
  if trainers then
    f.empty:SetText("No trainers seen yet. Open a profession trainer's window.")
  elseif loading and n == 0 then
    f.empty:SetText("Working out the list...")
  elseif total > 0 then
    f.empty:SetText(ns.LocalizeFormatted("%s has %d recipe%s, but none match what's chosen above (%s). Choose All and Any to see them.",
      current, total, total == 1 and "" or "s", table.concat(why, ", ")))
  else
    f.empty:SetText("No recipes yet. Open this profession's window once to record its recipes.")
  end
  -- AHledger's terms: its credit where its prices went into the costs and profits shown
  -- (Codex review, November 17).
  if ns.AHledgerUses and ns.AHledgerUses() ~= ahlBefore then
    f.summary:SetText((f.summary:GetText() or "") .. " " .. ns.AHLEDGER_CREDIT .. ".")
  end
  f.content:SetHeight(math.max(n * ROW, 30))
  f.sf.UpdateScrollBar()
end

ns.RefreshRecipes = ns.Timed("Recipes tab", ns.RefreshRecipes)
ns._recipesTest = { buildList = buildList, settings = settings, groupChoices = groupChoices, listStamp = listStamp, valuesKey = valuesKey, groupOptions = groupOptions, autoType = autoType }   -- (tests)
