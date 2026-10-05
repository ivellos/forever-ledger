local _, ns = ...

---------------------------------------------------------------------------
-- Quest turn-in items (owner's idea, October 2): items quests ask for that you can buy
-- on the auction house. Leveling players need each once per character, so they sell;
-- and your own characters should keep them for later. From a community spreadsheet of
-- Classic quests (in the private game-data notes); Forever may have changed some. Items are named,
-- not numbered, and matched to the Classic item list at load: a name that doesn't match
-- is left out rather than guessed.
-- { quest, where, level, faction (A, H or B), { item, count, item, count, ... }, class }
---------------------------------------------------------------------------
local QUESTS = {
  { "Stocking Jetsteam", "Dun Morogh", 6, "A", { "Chunk of Boar Meat", 4 } },
  { "Pie for Billy", "Elwynn Forest", 6, "A", { "Chunk of Boar Meat", 4 } },
  { "Beer Basted Boar Ribs", "Dun Morogh", 7, "A", { "Crag Boar Rib", 6, "Rhapsody Malt", 1 } },
  { "Recipe of the Kaldorei", "Teldrassil", 7, "A", { "Small Spider Leg", 7 } },
  { "Elixirs for the Bladeleafs", "Teldrassil", 8, "A", { "Elixir of Minor Defense", 2, "Elixir of Lion's Strength", 6 } },
  { "Gathering Leather", "Thunder Bluff", 8, "H", { "Light Leather", 12 } },
  { "Kodo Hide Bag", "Thunder Bluff", 10, "H", { "Light Leather", 4, "Coarse Thread", 4 } },
  { "Wild Hearts", "Silverpine Forest", 11, "H", { "Discolored Worg Heart", 6 } },
  { "Thelsamar Blood Sausage", "Loch Modan", 11, "A", { "Boar Intestines", 3, "Bear Meat", 3, "Spider Ichor", 3 } },
  { "Goretusk Liver Pie", "Westfall", 12, "A", { "Goretusk Liver", 10 } },
  { "Easy Strider Living", "Darkshore", 12, "A", { "Strider Meat", 5 } },
  { "A Donation of Wool", "a capital city", 12, "B", { "Wool Cloth", 60 } },
  { "Westfall Stew", "Westfall", 13, "A", { "Stringy Vulture Meat", 3, "Murloc Eye", 3, "Goretusk Snout", 3, "Okra", 3 } },
  { "The Family and the Fishing Pole", "Darkshore", 14, "A", { "Darkshore Grouper", 6 } },
  { "Gathering the Cure", "Darkshore", 14, "A", { "Earthroot", 5 }, "DRUID" },
  { "Crocolisk Hunting", "Loch Modan", 15, "A", { "Crocolisk Meat", 5 } },
  { "Gathering Materials", "Stormwind", 15, "B", { "Linen Cloth", 10 }, "MAGE" },
  { "Keeper of the Flame", "Westfall", 16, "A", { "Flask of Oil", 5 } },
  { "Redridge Goulash", "Redridge Mountains", 18, "A", { "Great Goretusk Snout", 5, "Tough Condor Meat", 5, "Crisp Spider Meat", 5 } },
  { "Dusky Crab Cakes", "Duskwood", 20, "A", { "Gooey Spider Leg", 6 } },
  { "Murloc Poachers", "Redridge Mountains", 20, "A", { "Murloc Fin", 8 } },
  { "The Touch of Zanzil", "Stormwind", 20, "B", { "Leaded Vial", 1, "Bronze Tube", 1, "Simple Wildflowers", 1, "Spool of Light Chartreuse Silk Thread", 1 }, "ROGUE" },
  { "Ineptitude + Chemicals = Fun", "Stonetalon Mountains", 21, "A", { "Minor Mana Potion", 4, "Elixir of Minor Fortitude", 2 } },
  { "Blood Shards of Agamaggan", "The Barrens", 21, "H", { "Blood Shard", 1 } },
  { "Search for Incendicite", "Loch Modan", 22, "A", { "Incendicite Ore", 6 } },
  { "Rethban Ore", "Redridge Mountains", 24, "A", { "Rethban Ore", 5 } },
  { "Seasoned Wolf Kabobs", "Duskwood", 25, "A", { "Lean Wolf Flank", 10, "Stormwind Seasoning Herbs", 1 } },
  { "Look to the Stars", "Duskwood", 25, "A", { "Bronze Tube", 1 } },
  { "A Donation of Silk", "a capital city", 26, "B", { "Silk Cloth", 60 } },
  { "Warsong Supplies", "Ashenvale", 27, "H", { "Deadly Blunderbuss", 1 } },
  { "Elixir of Agony", "Hillsbrad Foothills", 30, "H", { "Strong Troll's Blood Elixir", 1 } },
  { "Items of Some Consequence", "Stormwind", 31, "A", { "Silk Cloth", 3 } },
  { "Soothing Turtle Bisque", "Hillsbrad Foothills", 31, "B", { "Turtle Meat", 10, "Soothing Spices", 1 } },
  { "Barbaric Battlements", "Orgrimmar", 32, "H", { "Patterned Bronze Bracers", 2, "Bronze Greatsword", 2, "Sharp Claw", 2 } },
  { "Bad Medicine", "Stranglethorn Vale", 34, "A", { "Jungle Remedy", 7 } },
  { "Bartolo's Yeti Fur Cloak", "Hillsbrad Foothills", 34, "A", { "Bolt of Woolen Cloth", 1, "Fine Thread", 1, "Hillman's Cloak", 1 } },
  { "Gnome Improvement", "Ironforge", 35, "A", { "Silver Bar", 1, "Moss Agate", 1 } },
  { "Gizmo for Warug", "Desolace", 35, "B", { "Advanced Target Dummy", 1 } },
  { "Stranglethorn Fever", "Stranglethorn Vale", 35, "B", { "Gorilla Fang", 10 } },
  { "Catch of the Day", "Desolace", 37, "H", { "Bloodbelly Fish", 2 } },
  { "Pearl Diving", "Stranglethorn Vale", 37, "B", { "Blue Pearl", 9 } },
  { "Favor for Krazek", "Stranglethorn Vale", 37, "A", { "Lesser Bloodstone Ore", 4 } },
  { "Gyro... What?", "Badlands", 37, "B", { "Gyrochronatom", 1 } },
  { "Liquid Stone", "Badlands", 37, "B", { "Lesser Invisibility Potion", 1, "Healing Potion", 1 } },
  { "Coolant Heads Prevail", "Badlands", 37, "B", { "Frost Oil", 1 } },
  { "Barbecued Buzzard Wings", "Badlands", 40, "B", { "Buzzard Wing", 4 } },
  { "A Donation of Mageweave", "a capital city", 40, "B", { "Mageweave Cloth", 60 } },
  { "Items of Power", "Dustwallow Marsh", 40, "B", { "Jade", 1 }, "MAGE" },
  { "Cyclonian", "Alterac Mountains", 40, "B", { "Liferoot", 8 }, "WARRIOR" },
  { "Lore for a Price", "Ironforge", 41, "A", { "Silver Bar", 5 } },
  { "Stone Is Better than Cloth", "Badlands", 42, "B", { "Patterned Bronze Bracers", 1 } },
  { "Wastewander Water Pouch", "Tanaris", 44, "B", { "Wastewander Water Pouch", 5 } },
  { "Sweet Amber", "Westfall", 44, "A", { "Truesilver Bar", 1 } },
  { "Caught!", "Searing Gorge", 45, "B", { "Silk Cloth", 15 } },
  { "Clamlette Surprise", "Tanaris", 45, "B", { "Giant Egg", 12, "Zesty Clam Meat", 10, "Alterac Swiss", 20 } },
  { "A Short Incubation", "Thousand Needles", 47, "B", { "Elixir of Fortitude", 2 } },
  { "Another Message to the Wildhammer", "The Hinterlands", 48, "H", { "Long Elegant Feather", 10 } },
  { "Blasted Lands quests (five)", "Blasted Lands", 50, "B", { "Blasted Boar Lung", 6, "Scorpok Pincer", 6, "Basilisk Brain", 11, "Vulture Gizzard", 14, "Snickerfang Jowl", 5 } },
  { "Un'Goro Soil", "Darnassus", 50, "B", { "Un'Goro Soil", 20 } },
  { "Morrowgrain Research", "Darnassus", 50, "A", { "Morrowgrain", 10 } },
  { "A Donation of Runecloth", "a capital city", 50, "B", { "Runecloth", 60 } },
  { "Chasing A-Me 01", "Un'Goro Crater", 53, "B", { "Mithril Casing", 1 } },
  { "Bungle in the Jungle", "Tanaris", 53, "B", { "Un'Goro Soil", 5 } },
  { "The Love Potion", "Blackrock Depths", 54, "B", { "Gromsblood", 4 } },
  { "Spectral Chalice", "Blackrock Depths", 55, "B", { "Star Ruby", 2, "Gold Bar", 20, "Truesilver Bar", 10 } },
  { "Salve via Disenchanting", "Felwood", 55, "B", { "Lesser Nether Essence", 1 } },
  { "Sacred Cloth", "Felwood", 55, "B", { "Mooncloth", 2 } },
  { "Runecloth", "Felwood", 55, "B", { "Runecloth", 30 } },
  { "Fragments of the Past", "Eastern Plaguelands", 57, "A", { "Enchanted Thorium Bar", 1 } },
  { "Fire Plume Forged", "Un'Goro Crater", 57, "A", { "Thorium Bar", 2 } },
  { "Kitchen Assistance", "Silithus", 57, "B", { "Smoked Desert Dumplings", 10 } },
  { "That's Asking a Lot", "Eastern Plaguelands", 58, "B", { "Unstable Trigger", 8, "Hi-Explosive Bomb", 8, "Thorium Bar", 2, "Golden Rod", 1 } },
}

-- itemID -> { { quest, where, level, faction, count, class }, ... }, built once.
local byItem
local function build()
  byItem = {}
  local idOf = {}
  for id, name in pairs(ns.CLASSIC_ITEMS or {}) do
    local key = name:lower()
    -- Several items can share a name; the lowest number is the original one.
    if not idOf[key] or id < idOf[key] then idOf[key] = id end
  end
  local missing = {}
  for _, q in ipairs(QUESTS) do
    local items = q[5]
    for i = 1, #items, 2 do
      local id = idOf[items[i]:lower()]
      if id then
        byItem[id] = byItem[id] or {}
        table.insert(byItem[id], { quest = q[1], where = q[2], level = q[3], faction = q[4], count = items[i + 1], class = q[6] })
      else
        missing[#missing + 1] = items[i]
      end
    end
  end
  for _, list in pairs(byItem) do table.sort(list, function(a, b) return a.level < b.level end) end
  if #missing > 0 then ns:Debug("Quest items not in the Classic list:", table.concat(missing, ", ")) end
end

---------------------------------------------------------------------------
-- Quests this character has done (owner, October 3: hide them). The game lists the
-- numbers of completed quests; their names come from the game's quest data, which may
-- have to load first. Only names on the list above are kept, per character:
-- chars[key].questsDone = { [quest name, lower case] = true }.
---------------------------------------------------------------------------
local wanted   -- [quest name, lower case] = true
local function wantedNames()
  if not wanted then
    wanted = {}
    for _, q in ipairs(QUESTS) do wanted[q[1]:lower()] = true end
  end
  return wanted
end

local function doneTable()
  local c = ns.db and ns.db.chars[ns.CharKey()]
  if not c then return {} end
  c.questsDone = c.questsDone or {}
  return c.questsDone
end

local function noteTitle(title)
  if title and wantedNames()[title:lower()] then doneTable()[title:lower()] = true end
end

local loading = {}   -- [questID] = true while its name loads
local function titleOf(questID)
  local get = C_QuestLog and C_QuestLog.GetTitleForQuestID
  local ok, title = pcall(get or error, questID)
  if ok and title and title ~= "" then return title end
  if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
    loading[questID] = true
    pcall(C_QuestLog.RequestLoadQuestByID, questID)
  end
end

ns:On("QUEST_DATA_LOAD_RESULT", function(questID, success)
  if not (questID and loading[questID]) then return end
  loading[questID] = nil
  if success then noteTitle(titleOf(questID)) end
end)

-- Once a session, a little at a time: every completed quest's name.
local function readCompleted()
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(list) == "table" then ids = list end
  elseif GetQuestsCompleted then
    local ok, set = pcall(GetQuestsCompleted)
    if ok and type(set) == "table" then for id in pairs(set) do ids[#ids + 1] = id end end
  end
  local i = 0
  local function step()
    for _ = 1, 50 do
      i = i + 1
      local id = ids[i]
      if not id then
        ns:Debug("Quests done read:", #ids, "completed quests, of which on the quest-items list:", (function()
          local n = 0
          for _ in pairs(doneTable()) do n = n + 1 end
          return n
        end)())
        return
      end
      noteTitle(titleOf(id))
    end
    C_Timer.After(0.1, step)
  end
  step()
end
ns:OnReady(function() C_Timer.After(15, readCompleted) end)
ns:On("QUEST_TURNED_IN", function(questID) if questID then noteTitle(titleOf(questID)) end end)

-- How many levels below you a quest turns grey (the game's green range).
local function greenRange(level)
  if GetQuestGreenRange then
    local ok, r = pcall(GetQuestGreenRange)
    if ok and type(r) == "number" and r > 0 then return r end
  end
  -- Classic's rule when the game doesn't say: 5 levels at low level, growing to 10.
  return level <= 5 and 5 or math.min(10, 5 + math.floor(level / 10))
end

-- Quests that need this item, for your faction: { { quest, where, level, count, class,
-- keep = true if this character will want it later, mine = false if it's done, grey or
-- another class's }, ... }, or nil.
function ns:QuestNeeds(id)
  if not byItem then build() end
  local list = id and byItem[id]
  if not list then return end
  local mine = (UnitFactionGroup("player") or ""):sub(1, 1)
  local level = UnitLevel("player") or 1
  local _, class = UnitClass("player")
  local done = doneTable()
  local grey = level - greenRange(level)
  local out = {}
  for _, q in ipairs(list) do
    if q.faction == "B" or q.faction == mine then
      local copy = {}
      for k, v in pairs(q) do copy[k] = v end
      copy.done = done[q.quest:lower()] or false
      copy.grey = q.level <= grey
      copy.otherClass = q.class ~= nil and q.class ~= class
      copy.mine = not (copy.done or copy.grey or copy.otherClass)
      copy.keep = copy.mine and level <= q.level
      out[#out + 1] = copy
    end
  end
  return #out > 0 and out or nil
end

-- Tooltip lines (Tooltip.lua). compact: only the "keep it" ones.
function ns:QuestLines(id, compact)
  local needs = ns:QuestNeeds(id)
  if not needs then return end
  local lines, more = {}, 0
  -- Settings, Tooltips: only quests this character still has ahead (on by default).
  local onlyMine = ns.db.settings.tipQuestMine ~= false
  for _, q in ipairs(needs) do
    if (not compact or q.keep) and (q.mine or not onlyMine) then
      if #lines < 3 then
        lines[#lines + 1] = {
          text = ("Quest: %s (%s, level %d%s), needs %d%s"):format(q.quest, q.where, q.level,
            q.class and (", " .. q.class:sub(1, 1) .. q.class:sub(2):lower()) or "", q.count,
            q.done and " |cff888888(done)|r" or q.grey and " |cff888888(too low)|r"
              or q.otherClass and " |cff888888(other class)|r" or ""),
          keep = q.keep,
        }
      else
        more = more + 1
      end
    end
  end
  if more > 0 then lines[#lines + 1] = { text = ("and %d more %s"):format(more, more == 1 and "quest" or "quests") } end
  return #lines > 0 and lines or nil
end

-- For the Deals tab: leveling players need it for a quest (any faction).
function ns:IsQuestItem(id)
  if not byItem then build() end
  return id and byItem[id] ~= nil
end
