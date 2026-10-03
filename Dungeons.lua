local _, ns = ...

---------------------------------------------------------------------------
-- Dungeon runs (owner, October 3: players count their runs and what dropped, chasing
-- appearances and valuable drops). Counted always, not only in a session: entering a
-- dungeon starts a run; coming back into the same one within 5 minutes (a wipe, a quick
-- hop out) is the same run. Each run keeps its time, the coin looted and what you looted.
-- Per dungeon: runs, time, coin, and how often each item dropped for you.
--
-- ns.db.dungeons[name] = { runs, secs, coin, drops = { [itemID] = runs it dropped in } }
-- ns.db.dungeonRun = the run under way { name, t, left (time you went out, or nil),
--   coin, loot = { [itemID] = count } }
-- Only instance checks on zone changes, and loot reading while inside a dungeon.
---------------------------------------------------------------------------
local SAME_RUN_SECONDS = 300

local function inDungeon()
  if not (IsInInstance and GetInstanceInfo) then return end
  local inside, kind = IsInInstance()
  if not inside or (kind ~= "party" and kind ~= "raid") then return end
  local name = GetInstanceInfo()
  return name
end

-- "under a minute" or "12 min".
local function mins(secs)
  if secs < 60 then return "under a minute" end
  return ("%d min"):format(math.floor(secs / 60))
end

-- The run is over: add it to its dungeon's totals. A quick walk in and out (under 2
-- minutes, nothing looted) isn't a run (owner's test, October 3: "Stockade, 0 min").
local function finishRun(run)
  if not run then return end
  local secs = math.max(0, (run.left or time()) - run.t)
  local looted = 0
  for _ in pairs(run.loot or {}) do looted = looted + 1 end
  if secs < 120 and looted == 0 and (run.coin or 0) == 0 then
    ns:Debug(("Dungeon run not counted: %s, %s and nothing looted."):format(run.name, mins(secs)))
    return
  end
  local d = ns.db.dungeons[run.name] or { runs = 0, secs = 0, coin = 0, drops = {} }
  ns.db.dungeons[run.name] = d
  d.runs = d.runs + 1
  d.secs = d.secs + secs
  d.coin = d.coin + (run.coin or 0)
  for id in pairs(run.loot or {}) do d.drops[id] = (d.drops[id] or 0) + 1 end
  ns:Debug(("Dungeon run counted: %s, %s, %d items looted."):format(run.name, mins(secs), looted))
end

local function check()
  if not ns.db then return end
  local name = inDungeon()
  local run = ns.db.dungeonRun
  if name then
    if run and run.name == name and run.left and time() - run.left <= SAME_RUN_SECONDS then
      run.left = nil   -- back in: the same run
    elseif not (run and run.name == name and not run.left) then
      if run then finishRun(run) end
      ns.db.dungeonRun = { name = name, t = time(), coin = 0, loot = {} }
      ns:Debug("Dungeon run started:", name)
    end
  elseif run then
    if not run.left then run.left = time() end
    -- Gone longer than a quick hop out: the run is over.
    if time() - run.left > SAME_RUN_SECONDS then
      finishRun(run)
      ns.db.dungeonRun = nil
    end
  end
end

ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, check) end)
ns:On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(1, check) end)
-- A run left a while ago gets finished even if you don't change zones again.
ns:OnReady(function()
  C_Timer.NewTicker(60, function()
    local run = ns.db and ns.db.dungeonRun
    if run and run.left then check() end
  end)
end)

-- Loot and coin while inside: the loot message, and coin from History.lua's money hook.
local lootPattern, lootMultiple
local function patterns()
  if lootPattern ~= nil then return end
  local function make(fmt)
    if not fmt then return false end
    local p = fmt:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
  end
  lootMultiple, lootPattern = make(LOOT_ITEM_SELF_MULTIPLE), make(LOOT_ITEM_SELF)
end

ns:On("CHAT_MSG_LOOT", function(msg)
  local run = ns.db and ns.db.dungeonRun
  if not (run and not run.left and msg) then return end
  patterns()
  local link, n
  if lootMultiple then link, n = msg:match(lootMultiple) end
  if not link and lootPattern then link = msg:match(lootPattern) end
  local id = link and ns.ItemIDFromLink(link)
  if id then
    run.loot[id] = (run.loot[id] or 0) + (tonumber(n) or 1)
    ns:RememberItem(id)
  end
end)

function ns:DungeonMoney(source, delta)
  local run = ns.db and ns.db.dungeonRun
  if run and not run.left and source == "loot" and delta > 0 then run.coin = (run.coin or 0) + delta end
end

---------------------------------------------------------------------------
-- Showing it: /fl runs, and a tooltip line on items that dropped for you.
---------------------------------------------------------------------------
-- "Dropped for you: Deadmines, 2 in 14 runs" (up to two dungeons), or nil.
function ns:DropLine(id)
  local parts = {}
  for name, d in pairs(ns.db and ns.db.dungeons or {}) do
    local n = d.drops and d.drops[id]
    if n then parts[#parts + 1] = { name = name, n = n, runs = d.runs } end
  end
  if #parts == 0 then return end
  table.sort(parts, function(a, b) return a.n / a.runs > b.n / b.runs end)
  local out = {}
  for i = 1, math.min(2, #parts) do
    out[i] = ("%s, %d in %d %s"):format(parts[i].name, parts[i].n, parts[i].runs, parts[i].runs == 1 and "run" or "runs")
  end
  return "Dropped for you: " .. table.concat(out, "; ")
end

function ns:PrintRuns()
  local list = {}
  for name, d in pairs(ns.db.dungeons or {}) do list[#list + 1] = { name = name, d = d } end
  local run = ns.db.dungeonRun
  if #list == 0 and not run then
    ns:Print("No dungeon runs counted yet. Runs are counted as you go: just run a dungeon.")
    return
  end
  table.sort(list, function(a, b) return a.d.runs > b.d.runs end)
  ns:Print("Your dungeon runs (this account):")
  if run and not run.left then
    print(("  Now: %s, %s so far."):format(run.name, mins(time() - run.t)))
  end
  for _, e in ipairs(list) do
    local d = e.d
    -- The best drops by worth (Sessions.lua's loot value).
    local drops = {}
    for id, n in pairs(d.drops or {}) do
      drops[#drops + 1] = { id = id, n = n, value = ns.LootValue and ns:LootValue(id) or 0 }
    end
    table.sort(drops, function(a, b) return a.value > b.value end)
    local best = {}
    for i = 1, math.min(3, #drops) do
      best[i] = ("%s (%d)"):format(ns.ItemName(drops[i].id) or "?", drops[i].n)
    end
    print(("  %s: %d %s, about %s each, %s coin a run.%s"):format(e.name, d.runs, d.runs == 1 and "run" or "runs",
      mins(d.secs / math.max(d.runs, 1)), ns.Money(math.floor(d.coin / math.max(d.runs, 1))),
      #best > 0 and (" Best drops: " .. table.concat(best, ", ") .. ".") or ""))
  end
end
