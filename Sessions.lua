local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Sessions (owner, October 3): start one any time and a small tracker counts what the
-- time was worth: gold in and out by where it came from (History.lua tells us each
-- change and its source), and what you looted, valued at the better of the auction
-- house (after the cut) and a vendor, or vendor only (setting). At the end, a summary
-- in chat and a line in the Dashboard's sessions. (The "Work it" shuffle sessions were
-- removed with that window, October 4; their finished ones still show.) Dungeon runs and chase items build on
-- this later (docs/ROADMAP.md).
--
-- ns.db.liveSession = { t, char, money = { [source] = signed copper }, loot = { [itemID] = count } }
-- Finished ones go to ns.db.sessions as { kind = "general", name, t, stop, earned, spent, loot, top }.
-- Nothing here runs without a session: the events return at once.
---------------------------------------------------------------------------
local TRACKER_SECONDS = 1   -- the tracker redraws this often, and only while a session runs

local function live() return ns.db and ns.db.liveSession end

-- Gold an hour, losses in red with a minus (owner's test, October 3: a session that
-- spent 16s said "0c an hour").
local function rateText(v)
  v = math.floor(v + 0.5)
  if v >= 0 then return ns.Money(v) end
  return "|cffee8597-|r" .. ns.Money(-v)
end

-- What one looted item is worth: the better of the auction house after the cut and a
-- vendor; items that bind when picked up only to a vendor (they can't be listed).
function ns:LootValue(id)
  local vendor = ns:GetSellPrice(id) or 0
  if ns.db.settings.sessionValue == "vendor" or (ns.IsClassicBound and ns:IsClassicBound(id)) then return vendor end
  local price = ns:GetPrice(id)
  local ah = price and math.floor(price * (1 - (ns.db.settings.ahCut or 5) / 100)) or 0
  return math.max(ah, vendor)
end

-- Totals so far: { secs, gained = net gold change, earned, spent, loot = value of what
-- was looted, items = { { id, n, value } } best first, perHour }.
function ns:SessionTotals(s)
  s = s or live()
  if not s then return end
  local earned, spent = 0, 0
  for _, v in pairs(s.money or {}) do
    if v > 0 then earned = earned + v else spent = spent - v end
  end
  local loot, items = 0, {}
  for id, n in pairs(s.loot or {}) do
    local value = ns:LootValue(id) * n
    loot = loot + value
    items[#items + 1] = { id = id, n = n, value = value }
  end
  table.sort(items, function(a, b) return a.value > b.value end)
  -- Time played, not time since it started: a session carried over a logout doesn't
  -- count the time offline (code review, October 4). s.active = seconds before the
  -- last logout, s.resume = when it carried on (old sessions: from the start).
  local secs
  if s.active == nil and s.resume == nil then
    secs = time() - s.t   -- a session from before this was counted (or a stored one)
  else
    secs = (s.active or 0) + (s.resume and (time() - s.resume) or 0)
  end
  secs = math.max(1, secs)
  local gained = earned - spent
  return { secs = secs, earned = earned, spent = spent, gained = gained, loot = loot, items = items,
    perHour = (gained + loot) / secs * 3600 }
end

local function duration(secs)
  local h, m = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  return ("%dm %02ds"):format(m, secs % 60)
end
local function signed(c) return (c < 0 and "-" or "+") .. ns.Money(math.abs(c)) end

---------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------
-- Every gold change, with where it came from (History.lua onMoney).
function ns:SessionMoney(source, delta)
  local s = live()
  if not s or s.char ~= ns.CharKey() then return end
  s.money[source] = (s.money[source] or 0) + delta
end

-- "You receive loot: [Linen Cloth]x2." in the client's own language, as patterns.
local lootPatterns
local function patterns()
  if lootPatterns then return lootPatterns end
  lootPatterns = {}
  local function add(fmt, multiple)
    if not fmt then return end
    -- Escape the pattern characters, then turn %s into the item and %d into the count.
    local p = fmt:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    p = "^" .. p .. "$"
    lootPatterns[#lootPatterns + 1] = { p = p, multiple = multiple }
  end
  -- Only "You receive loot" (mobs, chests, gathering). "You receive item" is also vendor
  -- purchases and quest rewards: those would count twice, as gold spent and as loot.
  add(LOOT_ITEM_SELF_MULTIPLE, true)   -- first: the single form would match it too
  add(LOOT_ITEM_SELF, false)
  return lootPatterns
end

ns:On("CHAT_MSG_LOOT", function(msg)
  local s = live()
  if not (s and msg) or s.char ~= ns.CharKey() then return end
  for _, pat in ipairs(patterns()) do
    local link, n = msg:match(pat.p)
    if link then
      local id = ns.ItemIDFromLink(link)
      if id then
        s.loot[id] = (s.loot[id] or 0) + (tonumber(n) or 1)
        ns:RememberItem(id)
      end
      return
    end
  end
end)

---------------------------------------------------------------------------
-- The tracker: a small window you can move, while a session runs.
---------------------------------------------------------------------------
local tracker, ticker
local drawTracker

-- Small and quiet, so it doesn't get in the way of playing (owner's test, October 3:
-- "make it look a little nicer while keeping it small"): a thin accent line on top, the
-- time, gold an hour in larger text (the number people watch), gold and loot under it.
-- Right-click folds it to one slim line (settings.sessionSmall).
local function layoutTracker(f)
  local small = ns.db.settings.sessionSmall
  f:SetSize(210, small and 22 or 64)
  f.title:ClearAllPoints()
  f.title:SetPoint(small and "LEFT" or "TOPLEFT", 8, small and 0 or -8)
  f.time:ClearAllPoints()
  f.time:SetPoint("LEFT", f.title, "RIGHT", 6, 0)
  f.rate:SetShown(not small)
  f.gold:SetShown(not small)
  f.loot:SetShown(not small)
  f.stop:SetShown(not small)
  f.smallRate:SetShown(small)
end

local function buildTracker()
  local f = CreateFrame("Frame", "ForeverLedgerSessionTracker", UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  -- In the theme (owner, October 4): its background a little see-through, its edge, the
  -- bronze top line on Default and Gilded (the accent on Clean), and Size.
  T:Fill(f, { T.bg[1], T.bg[2], T.bg[3], 0.85 })
  local edge = T.theme.frame and { T.theme.frame[1], T.theme.frame[2], T.theme.frame[3], 0.8 } or { 1, 1, 1, 0.12 }
  T:Border(f, edge)
  local top = T.theme.topLine or T.accent
  local bar = f:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(2)
  bar:SetColorTexture(top[1], top[2], top[3], 0.9)
  ns.scaledWindows = ns.scaledWindows or {}
  table.insert(ns.scaledWindows, f)
  f:SetScale(((ns.db and ns.db.settings.uiScale) or 100) / 100)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.settings.sessionPos = { point, rel, x, y }
  end)
  f:SetScript("OnMouseUp", function(self, button)
    if button ~= "RightButton" then return end
    ns.db.settings.sessionSmall = not ns.db.settings.sessionSmall or nil
    layoutTracker(self)
    drawTracker()
  end)
  local pos = ns.db.settings.sessionPos
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end

  f.title = T:Text(f, 11)
  T:StyleHeading(f.title, "Session")
  f.time = T:Text(f, 11, T.dim)
  f.rate = T:Text(f, 15, { 1, 0.82, 0, 1 })
  f.rate:SetPoint("TOPLEFT", 8, -24)
  f.gold = T:Text(f, 11)
  f.gold:SetPoint("BOTTOMLEFT", 8, 7)
  f.loot = T:Text(f, 11)
  f.loot:SetPoint("BOTTOMRIGHT", -8, 7)
  f.loot:SetJustifyH("RIGHT")
  f.smallRate = T:Text(f, 11, { 1, 0.82, 0, 1 })
  f.smallRate:SetPoint("RIGHT", -8, 0)
  f.smallRate:SetJustifyH("RIGHT")
  f.stop = T:Button(f, "Stop", 40, function() ns:StopGeneralSession() end, 16)
  f.stop:SetPoint("TOPRIGHT", -5, -6)
  f.stop:GetFontString():SetFont(T.font, 10, "")
  layoutTracker(f)
  f:SetScript("OnEnter", function(self)
    local st = ns:SessionTotals()
    if not st then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Session", 1, 1, 1)
    GameTooltip:AddDoubleLine("Gold in", ns.Money(st.earned), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Gold out", ns.Money(st.spent), 0.8, 0.8, 0.8, 1, 1, 1)
    -- Where it came from and went (owner's test, October 3: "+1g 84s, I don't think
    -- that's right"): auction sales, vendor, mail, loot..., biggest first.
    local by = {}
    for src, v in pairs((live() or {}).money or {}) do if v ~= 0 then by[#by + 1] = { src, v } end end
    table.sort(by, function(a, b) return math.abs(a[2]) > math.abs(b[2]) end)
    for _, x in ipairs(by) do
      local label = (ns.MONEY_LABELS and ns.MONEY_LABELS[x[1]]) or x[1]
      GameTooltip:AddDoubleLine("  " .. label, (x[2] < 0 and "|cffee8597-|r" or "|cff7fd39c+|r") .. ns.Money(math.abs(x[2])),
        0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Looted, worth about", ns.Money(st.loot), 0.8, 0.8, 0.8, 1, 1, 1)
    for k = 1, math.min(5, #st.items) do
      local it = st.items[k]
      GameTooltip:AddDoubleLine(("  %d x %s"):format(it.n, ns.ItemName(it.id) or "?"), ns.Money(it.value), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:AddLine("Loot counts at the better of the auction house (after the cut) and a vendor; Settings can make it vendor only.", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine(ns.db.settings.sessionSmall and "Drag to move. Right-click for the full view; Stop is there."
      or "Drag to move. Right-click to fold it to one line.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

drawTracker = function()
  local st = ns:SessionTotals()
  if not (tracker and st) then return end
  -- Gold an hour from 2 minutes in: before that one purchase swings it wildly (owner's
  -- test, October 3: "-21g 60s an hour" 20 seconds in).
  local rate = st.secs >= 120 and rateText(st.perHour) or "|cff888888...|r"
  tracker.time:SetText(duration(st.secs))
  tracker.rate:SetText(st.secs >= 120 and (rate .. " |cffbbbbbban hour|r") or "|cff888888an hour: after 2 min|r")   -- (shorter: the longer text ran past the tracker, October 4)
  tracker.smallRate:SetText(rate .. " |cffbbbbbb/h|r")
  tracker.gold:SetText(("|cff999999Gold|r |cff%s%s|r"):format(st.gained >= 0 and "7fd39c" or "ee8597", signed(st.gained)))
  tracker.loot:SetText(("|cff999999Loot|r %s"):format(ns.Money(st.loot)))
end

local function showTracker()
  if not tracker then tracker = buildTracker() end
  tracker:Show()
  drawTracker()
  if ticker then ticker:Cancel() end
  ticker = C_Timer.NewTicker(TRACKER_SECONDS, drawTracker)
end

local function hideTracker()
  if ticker then ticker:Cancel(); ticker = nil end
  if tracker then tracker:Hide() end
end

---------------------------------------------------------------------------
-- Start and stop
---------------------------------------------------------------------------
function ns:StartGeneralSession()
  local s = live()
  if s and s.char == ns.CharKey() then
    ns:Print("A session is already running: /fl session stop ends it.")
    return
  elseif s then
    -- One left running on another character: end it (kept with your sessions) and
    -- start this one, in one click (owner's test, October 4).
    -- One line, not two that disagree ("it's in your sessions", then "isn't kept":
    -- owner's test, October 4).
    local c = ns.db.chars[s.char]
    local kept = ns:StopGeneralSession(true)
    ns:Print(("Ended the session left running on %s (%s)."):format((c and c.name) or s.char,
      kept and "it's in your sessions" or "nothing happened in it, so it isn't kept"))
  end
  ns.db.liveSession = { t = time(), resume = time(), active = 0, char = ns.CharKey(), money = {}, loot = {} }
  ns:Print("Session started: gold in and out and what you loot are counted. /fl session stop (or Stop on the tracker) ends it.")
  showTracker()
  if ns.RefreshUI then ns:RefreshUI() end
end

-- quiet: no summary in chat (ending one left on another character says it in one line).
-- Returns true when the session was kept.
function ns:StopGeneralSession(quiet)
  local s = live()
  if not s then ns:Print("No session is running. /fl session start begins one."); return end
  local st = ns:SessionTotals(s)
  ns.db.liveSession = nil
  hideTracker()
  -- Started and stopped with nothing happening (a misclick, a test): not kept (owner's
  -- test, October 3: the Dashboard listed several "0 min, gold 0c" sessions).
  if st.secs < 60 and st.earned == 0 and st.spent == 0 and st.loot == 0 then
    if not quiet then ns:Print("Session stopped. Nothing happened in it, so it isn't kept.") end
    if ns.RefreshUI then ns:RefreshUI() end
    return false
  end
  local top = {}
  for k = 1, math.min(5, #st.items) do top[k] = { st.items[k].id, st.items[k].n, st.items[k].value } end
  table.insert(ns.db.sessions, { kind = "general", name = "Session", c = s.char, t = s.t, stop = time(), secs = st.secs, earned = st.earned,
    spent = st.spent, loot = st.loot, top = top, runs = 0, money = s.money })
  while #ns.db.sessions > 100 do table.remove(ns.db.sessions, 1) end
  if quiet then
    if ns.RefreshUI then ns:RefreshUI() end
    return true
  end
  ns:Print(("Session over after %s: gold %s, looted about %s, so about %s an hour."):format(duration(st.secs),
    signed(st.gained), ns.Money(st.loot), rateText(st.perHour)))
  -- Gold by where it came from, biggest first.
  local by = {}
  for src, v in pairs(s.money or {}) do if v ~= 0 then by[#by + 1] = { src, v } end end
  table.sort(by, function(a, b) return math.abs(a[2]) > math.abs(b[2]) end)
  local parts = {}
  for k = 1, math.min(4, #by) do
    parts[k] = ("%s %s"):format((ns.MONEY_LABELS and ns.MONEY_LABELS[by[k][1]]) or by[k][1], signed(by[k][2]))
  end
  if #parts > 0 then print("  Gold: " .. table.concat(parts, ", ") .. ".") end
  for k = 1, math.min(3, #st.items) do
    local it = st.items[k]
    print(("  %d x %s, about %s"):format(it.n, ns.ItemName(it.id) or "?", ns.Money(it.value)))
  end
  if ns.RefreshUI then ns:RefreshUI() end
  return true
end

-- Running on this character (one left running on another doesn't count here: owner's
-- test, October 4, the Dashboard's button stopped it instead of starting one).
function ns:GeneralSessionRunning()
  local s = live()
  return s ~= nil and s.char == ns.CharKey()
end

-- A session left running at logout carries on at login, on the same character.
ns:On("PLAYER_ENTERING_WORLD", function()
  local s = live()
  -- Carrying on after a logout or reload: count time again from now.
  if s and not s.resume then
    if s.active == nil then s.active = time() - s.t end   -- one started before this was counted
    s.resume = time()
  end
  if s and s.char == ns.CharKey() then showTracker() else hideTracker() end
end)
-- Logging out (or reloading): bank the time played so far, so time offline isn't counted.
ns:On("PLAYER_LOGOUT", function()
  local s = live()
  if not s then return end
  if s.resume then
    s.active = (s.active or 0) + (time() - s.resume)
  elseif s.active == nil then
    s.active = time() - s.t
  end
  s.resume = nil
end)
