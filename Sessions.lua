local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Sessions (owner, October 3): start one any time and a small tracker counts what the
-- time was worth: gold in and out by where it came from (History.lua tells us each
-- change and its source), and what you looted, valued at the better of the auction
-- house (after the cut) and a vendor, or vendor only (setting). At the end, a summary
-- in chat and a line in the Ledger's Sessions. (The "Work it" shuffle sessions were
-- removed with that window, October 4; their finished ones still show.) Archived November
-- 13 and back November 15 at a player's request, without the Dashboard's button and table
-- (Frank: "We can sort out how to utilize it in the new version"): start and stop with
-- /fl session or Ctrl-click on the minimap button.
--
-- ns.db.liveSession = { t, char, money = { [source] = signed copper }, loot = { [itemID] = count } }
-- Finished ones go to ns.db.sessions as { kind = "general", name, t, stop, earned, spent, loot, top }.
-- Nothing here runs without a session: the events return at once.
---------------------------------------------------------------------------
local TRACKER_SECONDS = 1   -- the tracker redraws this often, and only while a session runs

local function live() return ns.db and ns.db.liveSession end
local drawTracker   -- (the tracker, below; the loot event redraws it)

-- Automatic records (Frank, November 24: "some sessions just recording at all times ...
-- Daily and per login"): ns.db.autoLive = { login = record, days = { [charKey] = record } },
-- counted like a session you start (the same fields, day = the local day for a day's),
-- never paused. A login's record runs from logging in to logging out, and a /reload
-- carries on the same one; a day's, from the character's first login that day to midnight
-- or its last logout. Finished ones go to ns.db.autoSessions like ns.db.sessions, with
-- kind = "login" or "day", for the Ledger's Sessions. While one runs, resume = when its
-- clock last started and seen = when it was last seen running (the game closing without a
-- logout counts up to then); at logout, final = its loot then, while this character's bags
-- can still say what's held.
local AUTO_KEEP = { login = 30 * 86400, day = 365 * 86400 }
local AUTO_MAX = 2000
local RELOAD_SECONDS = 120   -- a login this soon after a logout on the same character is a /reload
local function autoLive()
  if not ns.db then return end
  ns.db.autoLive = ns.db.autoLive or {}
  local a = ns.db.autoLive
  a.days = a.days or {}
  return a
end
local rollDays   -- (below)

-- The records counting for this character now: your session (not while paused, unless
-- evenPaused) and the automatic ones.
local function counting(evenPaused)
  local out = {}
  if not ns.db then return out end
  local me = ns.CharKey()
  local s = live()
  if s and s.char == me and (evenPaused or not s.paused) then out[#out + 1] = s end
  local a = ns.db.autoLive
  if a then
    local d = a.days and a.days[me]
    if d and d.resume and d.day ~= ns.LocalDay() and rollDays then rollDays(); d = a.days[me] end
    if a.login and a.login.char == me and a.login.resume then out[#out + 1] = a.login end
    if d and d.resume then out[#out + 1] = d end
  end
  return out
end

-- Gold an hour, losses in red with a minus (owner's test, October 3: a session that
-- spent 16s said "0c an hour").
local function rateText(v)
  v = math.floor(v + 0.5)
  if v >= 0 then return ns.Money(v) end
  return "|cffee8597-|r" .. ns.Money(-v)
end

-- What one looted item is worth: ns:LootValue (Values.lua; Settings, Sessions, Count loot at).

-- Gold an hour shows from this far in: before that one kill or purchase swings it wildly
-- (owner's test, October 3: "-21g 60s an hour" 20 seconds in; 5 minutes since November 17,
-- as Blackthornes Farmer does).
local RATE_SECONDS = 300
ns.SESSION_RATE_SECONDS = RATE_SECONDS

-- Of a session's loot, how many still count as loot: looted, less what was sold during it,
-- and no more than this character still has (bags, bank, its auctions not yet sold).
-- Selling looted items counted them twice, as loot and again as the gold they brought (a
-- player on CurseForge, November 16); disenchanting, using or destroying them likewise
-- left them counted. What a sale brought is in the gold; what's gone is gone.
local function stillHeld(s)
  if s.char ~= ns.CharKey() then return nil end   -- another character's bags say nothing
  local posted = {}
  for _, key in ipairs({ s.char, s.char .. " (neutral)" }) do
    local mine = ns.db.myAuctions and ns.db.myAuctions[key]
    for _, e in ipairs(mine and mine.list or {}) do
      if e.id and not e.sold then posted[e.id] = (posted[e.id] or 0) + (e.q or 1) end
    end
  end
  return function(id) return ns.ItemCount(id, true) + (posted[id] or 0) end
end

-- Totals so far: { secs, gained = net gold change, earned, spent, loot = value of what
-- was looted and is still held, items = { { id, n, value } } best first, unpriced = items
-- with no price (not counted), perHour }.
function ns:SessionTotals(s)
  s = s or live()
  if not s then return end
  local earned, spent = 0, 0
  for _, v in pairs(s.money or {}) do
    if v > 0 then earned = earned + v else spent = spent - v end
  end
  local loot, items, unpriced = 0, {}, 0
  local held = stillHeld(s)
  for id, n in pairs(s.loot or {}) do
    n = n - ((s.sold or {})[id] or 0)
    if held then n = math.min(n, held(id)) end
    if n > 0 then
      local value = ns:LootValue(id) * n
      if value > 0 then
        loot = loot + value
        items[#items + 1] = { id = id, n = n, value = value }
      else
        unpriced = unpriced + n
      end
    end
  end
  table.sort(items, function(a, b) return a.value > b.value end)
  -- Time played, not time since it started: a session carried over a logout doesn't
  -- count the time offline (code review, October 4). s.active = seconds before the
  -- last logout, s.resume = when it carried on (old sessions: from the start).
  local secs
  if s.active == nil and s.resume == nil then
    secs = time() - s.t   -- a session from before this was counted (or a stored one)
  else
    -- The clock runs only while its own character plays (Codex review of 893cbbd: another
    -- character's hour went into it).
    local mine = s.char == ns.CharKey()
    secs = (s.active or 0) + ((mine and s.resume) and (time() - s.resume) or 0)
  end
  secs = math.max(1, secs)
  local gained = earned - spent
  return { secs = secs, earned = earned, spent = spent, gained = gained, loot = loot, items = items,
    unpriced = unpriced, perHour = (gained + loot) / secs * 3600 }
end

-- Gold an hour of a finished session (gold and loot), or nil when it was too short to say.
function ns.SessionRate(e)
  local secs = e and (e.secs or ((e.stop or e.t or 0) - (e.t or 0)))
  if not secs or secs < RATE_SECONDS then return nil end
  return ((e.earned or 0) - (e.spent or 0) + (e.loot or 0)) / secs * 3600
end

-- Your usual and best gold an hour, from finished sessions of 10 minutes or more on this
-- character's realm and faction (the newest 20; usual = their median). nil with fewer than 3.
local USUAL_MIN_SECONDS, USUAL_COUNT = 600, 20
function ns:SessionUsual()
  local rates = {}
  local list = ns.db.sessions or {}
  for i = #list, 1, -1 do
    local e = list[i]
    if e.kind == "general" and (e.secs or 0) >= USUAL_MIN_SECONDS and (not e.c or not ns.SameMarketChar or ns:SameMarketChar(e.c)) then
      rates[#rates + 1] = ns.SessionRate(e)
      if #rates >= USUAL_COUNT then break end
    end
  end
  if #rates < 3 then return nil end
  local best = math.max(unpack(rates))
  table.sort(rates)
  local n = #rates
  local usual = n % 2 == 1 and rates[(n + 1) / 2] or (rates[n / 2] + rates[n / 2 + 1]) / 2
  return { usual = usual, best = best, n = n }
end

local function duration(secs)
  local h, m = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  return ("%dm %02ds"):format(m, secs % 60)
end
local function signed(c) return (c < 0 and "-" or "+") .. ns.Money(math.abs(c)) end
ns.SessionFormat = { duration = duration, signed = signed, rate = rateText }   -- (SessionWindow.lua)

---------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------
-- Every gold change, with where it came from (History.lua onMoney).
function ns:SessionMoney(source, delta)
  for _, s in ipairs(counting()) do s.money[source] = (s.money[source] or 0) + delta end
end

-- Something sold to a vendor or on the auction house (History.lua, with the gold it
-- brought): looted this session, it now counts as that gold, not as loot as well. item is
-- an item ID (vendor) or a name (auction sales name the item). Counted while paused too:
-- the loot it was is still in the totals.
-- An auction sale counts only against what was posted during this session (Codex review,
-- November 17: the money for an auction posted before it took this session's new loot of
-- the same item off), and its name may carry random stats ("Short Bastard Sword of
-- Strength" for the looted Short Bastard Sword). Copies are alike, so what's sold during
-- the session comes off its loot first: never counted twice, at worst a little under.
-- And the sale's mail must have come after the post (Codex verification, November 18: an
-- old auction's mail, collected while this session's loot of the same item was still
-- listed, took that loot off): arrived = when the mail came (History.lua, from its days
-- left), and only posts made by then count. A little slack for the days-left rounding.
local function nameMatches(sale, base)
  if not (sale and base) then return false end
  if sale == base then return true end
  return sale:sub(1, #base + 4) == base .. " of "
end
local MAIL_SLACK = 300
-- How many of this session's posts of id a sale whose mail came at arrived can be.
-- Posts from before their times were kept (a session running across that update): what
-- posted counts beyond the timed batches. They stay usable once a timed one is added
-- (Codex verification, November 19: the first new post made the older ones vanish), and
-- as the oldest they are used first.
local function batchSum(batches)
  local m = 0
  for _, b in ipairs(batches or {}) do m = m + b[2] end
  return m
end
local function untimed(s, id)
  return math.max(0, ((s.posted or {})[id] or 0) - batchSum(s.postedAt and s.postedAt[id]))
end
local function postsBefore(s, id, arrived)
  local n = (s.posted or {})[id] or 0
  local batches = s.postedAt and s.postedAt[id]
  if not (arrived and batches) then return n end   -- (no mail time, or no timed posts)
  local m = untimed(s, id)
  for _, b in ipairs(batches) do if b[1] <= arrived + MAIL_SLACK then m = m + b[2] end end
  return math.min(n, m)
end
local function usePosts(s, id, qty)
  local old = untimed(s, id)
  s.posted[id] = s.posted[id] - qty
  qty = qty - math.min(qty, old)
  local batches = s.postedAt and s.postedAt[id]
  while batches and qty > 0 and batches[1] do   -- the oldest first
    local take = math.min(qty, batches[1][2])
    batches[1][2], qty = batches[1][2] - take, qty - take
    if batches[1][2] <= 0 then table.remove(batches, 1) end
  end
end
local function soldIn(s, item, qty, arrived)
  qty = tonumber(qty) or 1
  local id = type(item) == "number" and item or nil
  if not id then
    -- The posted item it was: the exact name first, then a version with random stats.
    local loose
    for postedID in pairs(s.posted or {}) do
      if postsBefore(s, postedID, arrived) > 0 and s.loot[postedID] then
        local base = ns.ItemName(postedID)
        if base == item then id = postedID; break end
        if not loose and nameMatches(item, base) then loose = postedID end
      end
    end
    id = id or loose
    if not id then return end
    qty = math.min(qty, postsBefore(s, id, arrived))
    usePosts(s, id, qty)
  end
  if not (id and s.loot[id]) then return end
  s.sold = s.sold or {}
  s.sold[id] = math.min(s.loot[id], (s.sold[id] or 0) + qty)
end
function ns:SessionSold(item, qty, arrived)
  if not item then return end
  for _, s in ipairs(counting(true)) do soldIn(s, item, qty, arrived) end
end

-- Posted on the auction house during the session (the hooks below): what its sales can
-- count against.
local function postedIn(s, id, qty)
  s.posted = s.posted or {}
  s.posted[id] = (s.posted[id] or 0) + qty
  -- When, so a sale's mail from before it can't be this post's (postsBefore above).
  s.postedAt = s.postedAt or {}
  s.postedAt[id] = s.postedAt[id] or {}
  table.insert(s.postedAt[id], { time(), qty })
end
function ns:SessionPosted(id, qty)
  if not id then return end
  qty = tonumber(qty) or 1
  for _, s in ipairs(counting(true)) do postedIn(s, id, qty) end
end
ns:OnReady(function()
  local AH = C_AuctionHouse
  local function onPost(loc, _, qty)
    local ok, id = pcall(function() return C_Item and C_Item.GetItemID and C_Item.GetItemID(loc) end)
    if ok and id then ns:SessionPosted(id, qty) end
  end
  if AH and AH.PostItem then hooksecurefunc(AH, "PostItem", onPost) end
  if AH and AH.PostCommodity then hooksecurefunc(AH, "PostCommodity", onPost) end
end)

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
  if not msg or not ns.db then return end
  local list = counting()
  if #list == 0 then return end
  for _, pat in ipairs(patterns()) do
    local link, n = msg:match(pat.p)
    if link then
      local id = ns.ItemIDFromLink(link)
      if id then
        n = tonumber(n) or 1
        for _, s in ipairs(list) do s.loot[id] = (s.loot[id] or 0) + n end
        ns:RememberItem(id)
        -- The tracker shows what came in for a few seconds ("+2 Linen Cloth").
        ns.sessionLastLoot = { id = id, n = n, t = GetTime and GetTime() or time() }
        if drawTracker then drawTracker() end
      end
      return
    end
  end
end)

---------------------------------------------------------------------------
-- The tracker: a small window you can move, while a session runs.
---------------------------------------------------------------------------
local tracker, ticker

-- Small and quiet, so it doesn't get in the way of playing (owner's test, October 3:
-- "make it look a little nicer while keeping it small"): a thin accent line on top, the
-- time, gold an hour in larger text (the number people watch), gold and loot under it.
-- Right-click folds it to one slim line (settings.sessionSmall). More opens the full view
-- under it (settings.sessionFull; Frank, November 17: "a mini version... then the full
-- version that lets people see all the data live"): gold by where it came from, every
-- item looted with its worth (hover one for its tooltip), and your usual pace.
local W_MINI, W_SMALL = 244, 210   -- (wider for Reset, November 18: four icons and the time with "paused")
local FLASH_SECONDS = 4   -- (new loot shows on the tracker and is lit in the window this long)
local LOOT_NOTE = "Loot counts at the better of the auction house (after the cut) and a vendor (Settings, Sessions: vendor only), and only while you still have it: what you sell during the session counts once, as the gold it brought."
local function fullView() return ns.SessionWindowShown and ns.SessionWindowShown() end   -- (SessionWindow.lua)

-- A small icon button with its name and what it does on hover; SetIcon changes both (Pause / Carry on).
local ICONS = "Interface\\AddOns\\ForeverLedger\\media\\icons\\session-"
local function iconButton(parent, icon, name, what, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 18)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetSize(12, 12)
  b.tex:SetPoint("CENTER")
  local function tint(on) b.tex:SetVertexColor(on and 1 or 0.75, on and 0.85 or 0.75, on and 0.45 or 0.75) end
  function b:SetIcon(i, n, w)
    if i ~= b.icon then b.icon = i; b.tex:SetTexture(ICONS .. i) end
    b.name, b.what = n, w or b.what
  end
  b:SetIcon(icon, name, what)
  tint(false)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    tint(true)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ns:TooltipAddLine(self.name, 1, 1, 1)
    if self.what then ns:TooltipAddLine(self.what, 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() tint(false); GameTooltip:Hide() end)
  return b
end

local function layoutTracker(f)
  local small = ns.db.settings.sessionSmall
  f:SetSize(small and W_SMALL or W_MINI, small and 22 or 64)
  f.title:ClearAllPoints()
  f.title:SetPoint(small and "LEFT" or "TOPLEFT", 8, small and 0 or -8)
  f.time:ClearAllPoints()
  f.time:SetPoint("LEFT", f.title, "RIGHT", 6, 0)
  f.rate:SetShown(not small)
  f.gold:SetShown(not small)
  f.loot:SetShown(not small)
  f.stop:SetShown(not small)
  f.pause:SetShown(not small)
  f.reset:SetShown(not small)
  f.more:SetShown(not small)
  f.more:SetIcon(fullView() and "less" or "more", fullView() and "Less" or "More",
    fullView() and "Closes the session window." or "Opens the session window: a graph of your pace, every item looted (sort by any column), gold by where it came from and your past sessions.")
  f.smallRate:SetShown(small)
end
ns.SessionTrackerLayout = function() if tracker then layoutTracker(tracker) end end

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
  f.loot:SetWidth(118)   -- (a new item's name, "+2 Linen Cloth", is cut short, not run into Gold)
  f.loot:SetWordWrap(false)
  f.smallRate = T:Text(f, 11, { 1, 0.82, 0, 1 })
  f.smallRate:SetPoint("RIGHT", -8, 0)
  f.smallRate:SetJustifyH("RIGHT")
  -- Small icons, not words (Frank, AN29, November 17: "More Pause Stop" ran over the time;
  -- media/icons/session-*, drawn by tools/make-icons.ps1). A hover names each one.
  f.stop = iconButton(f, "stop", "Stop", "Ends the session and puts its summary in chat and the Ledger's Sessions.", function() ns:StopGeneralSession() end)
  f.stop:SetPoint("TOPRIGHT", -5, -5)
  -- Pause (Blackthornes Farmer has one; Frank, November 17): the clock stops and nothing is
  -- counted until Carry on (the play icon).
  f.pause = iconButton(f, "pause", "Pause", "The clock stops and nothing is counted until you carry on.", function() ns:PauseGeneralSession() end)
  f.pause:SetPoint("RIGHT", f.stop, "LEFT", -2, 0)
  f.reset = iconButton(f, "reset", "Reset", "Clears what this session has counted and starts its clock again from zero. Asks first.", function() ns:ResetGeneralSession() end)
  f.reset:SetPoint("RIGHT", f.pause, "LEFT", -2, 0)
  f.more = iconButton(f, "more", "More", "", function() ns:ToggleSessionWindow() end)
  f.more:SetPoint("RIGHT", f.reset, "LEFT", -2, 0)
  layoutTracker(f)
  f:SetScript("OnEnter", function(self)
    local ahlBefore = ns.AHledgerUses and ns.AHledgerUses() or 0
    local st = ns:SessionTotals()
    -- (The full view shows all of it already.)
    if not st or fullView() then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    ns:TooltipAddLine("Session", 1, 1, 1)
    ns:TooltipAddDoubleLine("Gold in", ns.Money(st.earned), 0.8, 0.8, 0.8, 1, 1, 1)
    ns:TooltipAddDoubleLine("Gold out", ns.Money(st.spent), 0.8, 0.8, 0.8, 1, 1, 1)
    -- Where it came from and went (owner's test, October 3: "+1g 84s, I don't think
    -- that's right"): auction sales, vendor, mail, loot..., biggest first.
    local by = {}
    for src, v in pairs((live() or {}).money or {}) do if v ~= 0 then by[#by + 1] = { src, v } end end
    table.sort(by, function(a, b) return math.abs(a[2]) > math.abs(b[2]) end)
    for _, x in ipairs(by) do
      local label = (ns.MONEY_LABELS and ns.MONEY_LABELS[x[1]]) or x[1]
      ns:TooltipAddDoubleLine("  " .. label, (x[2] < 0 and "|cffee8597-|r" or "|cff7fd39c+|r") .. ns.Money(math.abs(x[2])),
        0.7, 0.7, 0.7, 1, 1, 1)
    end
    ns:TooltipAddDoubleLine("Looted, worth about", ns.Money(st.loot), 0.8, 0.8, 0.8, 1, 1, 1)
    for k = 1, math.min(5, #st.items) do
      local it = st.items[k]
      ns:TooltipAddDoubleLine(("  %d x %s"):format(it.n, ns.ItemName(it.id) or "?"), ns.Money(it.value), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    if #st.items > 5 then ns:TooltipAddLine(("  and %d more: the arrow (More) shows them all"):format(#st.items - 5), 0.6, 0.6, 0.6) end
    ns:TooltipAddLine(LOOT_NOTE, 0.6, 0.6, 0.6, true)
    if ns.AHledgerUses and ns.AHledgerUses() ~= ahlBefore then ns:TooltipAddLine(ns.AHLEDGER_CREDIT, 0.5, 0.5, 0.5) end
    ns:TooltipAddLine(ns.db.settings.sessionSmall and "Drag to move. Right-click for the bigger view, with More (the arrow), Reset, Pause and Stop."
      or "Drag to move. Right-click to fold it to one line. The arrow shows everything as it comes in.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

drawTracker = function()
  local ahlBefore = ns.AHledgerUses and ns.AHledgerUses() or 0
  local st = ns:SessionTotals()
  if st then st.ahledger = ns.AHledgerUses and ns.AHledgerUses() ~= ahlBefore end   -- (loot valued with its prices: its credit)
  if not (tracker and st) then return end
  local s = live()
  local rate = st.secs >= RATE_SECONDS and rateText(st.perHour) or "|cff888888...|r"
  tracker.time:SetText(duration(st.secs) .. (s.paused and " |cffffd100paused|r" or ""))
  tracker.rate:SetText(st.secs >= RATE_SECONDS and (rate .. " |cffbbbbbban hour|r") or "|cff888888an hour: after 5 min|r")   -- (shorter: the longer text ran past the tracker, October 4)
  tracker.smallRate:SetText(s.paused and "|cffffd100paused|r" or (rate .. " |cffbbbbbb/h|r"))
  tracker.pause:SetIcon(s.paused and "play" or "pause", s.paused and "Carry on" or "Pause",
    s.paused and "The clock runs and counting starts again." or "The clock stops and nothing is counted until you carry on.")
  tracker.gold:SetText(("|cff999999Gold|r |cff%s%s|r"):format(st.gained >= 0 and "7fd39c" or "ee8597", signed(st.gained)))
  -- What just came in, for a few seconds (as Blackthornes Farmer's "+2").
  local last = ns.sessionLastLoot
  local now = GetTime and GetTime() or time()
  local flashID = last and now - last.t < FLASH_SECONDS and last.id or nil
  if flashID then
    tracker.loot:SetText(("|cff7fd39c+%d %s|r"):format(last.n, ns.ItemName(last.id) or "?"))
  else
    tracker.loot:SetText(("|cff999999Loot|r %s"):format(ns.Money(st.loot)))
  end
  -- Gold and Loot side by side ran into each other with gold, silver and copper in both
  -- (Frank's screenshot, November 24): the tracker grows to fit them, never narrower.
  if not ns.db.settings.sessionSmall then
    local function textW(fs) return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0 end
    local lootW = math.min(textW(tracker.loot), 160)
    tracker.loot:SetWidth(math.max(lootW, 1))
    local need = 8 + textW(tracker.gold) + 14 + lootW + 8
    tracker:SetWidth(math.max(W_MINI, math.ceil(need)))
  end
  if ns.SessionPaceSample then ns.SessionPaceSample(s, st) end   -- (the window's graph)
  if ns.DrawSessionWindow then ns:DrawSessionWindow(st, s, flashID) end
end

-- Pause or carry on (on = true pauses, false carries on, nil switches). While paused the
-- clock stops and nothing new is counted; selling what was looted still moves it to gold.
function ns:PauseGeneralSession(on)
  local s = live()
  if not s or s.char ~= ns.CharKey() then ns:Print("No session is running here. /fl session start begins one."); return end
  if on == nil then on = not s.paused end
  if on and not s.paused then
    if s.resume then s.active = (s.active or 0) + (time() - s.resume) end
    s.resume, s.paused = nil, true
  elseif not on and s.paused then
    s.paused, s.resume = nil, time()
  end
  if drawTracker then drawTracker() end
end

-- Start over (Frank, November 18: a reset button, with a confirm): what this session
-- counted goes, not kept in your sessions, and the clock starts again from zero. A paused
-- one carries on. Asks first unless sure is true.
StaticPopupDialogs["FOREVER_LEDGER_SESSION_RESET"] = {
  text = "Reset the session?\n\nWhat it has counted so far (%s) is cleared and the clock starts again from zero. It isn't kept in your sessions.",
  button1 = "Reset", button2 = CANCEL or "Cancel",
  -- The session it described, never a newer one started while it stayed open (Codex
  -- verification, November 19: stop, start again, then Accept cleared the new one).
  OnAccept = function(_, which) ns:ResetGeneralSession(true, which) end,
  timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}
function ns:ResetGeneralSession(sure, which)
  local s = live()
  if not s or s.char ~= ns.CharKey() then ns:Print("No session is running here. /fl session start begins one."); return end
  if which and which ~= s then ns:Print("That session has ended, so nothing was reset."); return end
  if not sure then
    local st = ns:SessionTotals(s)
    local popup = StaticPopup_Show("FOREVER_LEDGER_SESSION_RESET", ns.LocalizeText("%s, gold %s, loot %s"):format(duration(st.secs), signed(st.gained), ns.Money(st.loot)))
    if popup then popup.data = s end
    return
  end
  if StaticPopup_Hide then StaticPopup_Hide("FOREVER_LEDGER_SESSION_RESET") end
  ns.db.liveSession = { t = time(), resume = time(), active = 0, char = s.char, money = {}, loot = {} }
  ns.sessionLastLoot = nil
  ns:Print("Session reset: counting again from now.")
  if drawTracker then drawTracker() end
end

local function showTracker()
  if not tracker then tracker = buildTracker() end
  tracker:Show()
  drawTracker()
  if ns.db.settings.sessionFull and ns.ToggleSessionWindow then ns:ToggleSessionWindow(true) end
  if ticker then ticker:Cancel() end
  ticker = C_Timer.NewTicker(TRACKER_SECONDS, drawTracker)
end

local function hideTracker()
  if ticker then ticker:Cancel(); ticker = nil end
  if tracker then tracker:Hide() end
  if ns.HideSessionWindow then ns.HideSessionWindow() end
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
  if StaticPopup_Hide then StaticPopup_Hide("FOREVER_LEDGER_SESSION_RESET") end
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
  if StaticPopup_Hide then StaticPopup_Hide("FOREVER_LEDGER_SESSION_RESET") end
  hideTracker()
  -- Started and stopped with nothing happening (a misclick, a test): not kept (owner's
  -- test, October 3: the Dashboard listed several "0 min, gold 0c" sessions).
  if st.secs < 60 and st.earned == 0 and st.spent == 0 and st.loot == 0 then
    if not quiet then ns:Print("Session stopped. Nothing happened in it, so it isn't kept.") end
    if ns.RefreshUI then ns:RefreshUI() end
    return false
  end
  local usual = ns:SessionUsual()   -- (before this one joins them)
  local top = {}
  for k = 1, math.min(5, #st.items) do top[k] = { st.items[k].id, st.items[k].n, st.items[k].value } end
  table.insert(ns.db.sessions, { kind = "general", name = "Session", c = s.char, t = s.t, stop = time(), secs = st.secs, earned = st.earned,
    spent = st.spent, loot = st.loot, top = top, runs = 0, money = s.money })
  while #ns.db.sessions > 100 do table.remove(ns.db.sessions, 1) end
  if ns.BooksChanged then ns:BooksChanged() end
  if quiet then
    if ns.RefreshUI then ns:RefreshUI() end
    return true
  end
  ns:Print(("Session over after %s: gold %s, looted about %s, so about %s an hour."):format(duration(st.secs),
    signed(st.gained), ns.Money(st.loot), rateText(st.perHour)))
  -- Against your usual pace, and a cheer for your best yet (as Blackthornes Farmer does).
  if usual and st.secs >= USUAL_MIN_SECONDS then
    if st.perHour > usual.best then
      print(("  |cff7fd39cYour best session yet!|r (best before: %s an hour)"):format(rateText(usual.best)))
    else
      print(("  Your usual: %s an hour."):format(rateText(usual.usual)))
    end
  end
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

-- A session left running at logout carries on at login, on the same character. Another
-- character leaves it paused until its own comes back (Codex review of 893cbbd: logging in
-- on another character resumed it, and its logout put that character's hour into it).
ns:On("PLAYER_ENTERING_WORLD", function(isLogin)
  local s = live()
  -- Settings, Sessions, Start one when I log in (Frank, November 24): unless one is
  -- already running on this character, which carries on.
  if isLogin and ns.db.settings.sessionAtLogin and not (s and s.char == ns.CharKey()) then
    ns:StartGeneralSession()
    return
  end
  -- Carrying on after a logout or reload: count time again from now.
  if s and s.char == ns.CharKey() and not s.resume and not s.paused then
    if s.active == nil then s.active = time() - s.t end   -- one started before this was counted
    s.resume = time()
  end
  if s and s.char == ns.CharKey() then showTracker() else hideTracker() end
end)
-- Logging out (or reloading): bank the time played so far, so time offline isn't counted.
ns:On("PLAYER_LOGOUT", function()
  local s = live()
  if not s then return end
  if s.char ~= ns.CharKey() then
    -- Not this character's: nothing to bank, and a resume an older version set here goes.
    s.resume = nil
    return
  end
  if s.resume then
    s.active = (s.active or 0) + (time() - s.resume)
  elseif s.active == nil then
    s.active = time() - s.t
  end
  s.resume = nil
end)

---------------------------------------------------------------------------
-- Automatic records: each login and each day (see autoLive at the top)
---------------------------------------------------------------------------
local function newRecord(day)
  local now = time()
  return { t = now, resume = now, seen = now, active = 0, char = ns.CharKey(), money = {}, loot = {}, day = day }
end
-- Stops its clock at `at` (a logout, or when it was last seen running).
local function bank(rec, at)
  if rec.resume then
    rec.active = (rec.active or 0) + math.max(0, (at or time()) - rec.resume)
    rec.resume = nil
  end
end
local function topOf(st)
  local top = {}
  for k = 1, math.min(5, #st.items) do top[k] = { st.items[k].id, st.items[k].n, st.items[k].value } end
  return top
end
-- A record as the Ledger lists it (finished, or running = true for the one counting now).
function ns.AutoSessionEntry(rec, kind, running)
  local st = ns:SessionTotals(rec)
  local loot, top = st.loot, topOf(st)
  if rec.final and not running then loot, top = rec.final.loot or 0, rec.final.top or {} end
  return { kind = kind, c = rec.char, t = rec.t, stop = rec.out or time(), secs = st.secs, earned = st.earned,
    spent = st.spent, loot = loot, top = top, money = rec.money, day = rec.day, running = running or nil }
end
-- Older ones than AUTO_KEEP go, and the oldest past AUTO_MAX. Run at each finish and each
-- login, whether or not anything was kept (Codex review, November 24: an empty finish
-- skipped it).
local function trimAuto()
  local list = ns.db and ns.db.autoSessions
  if not list then return end
  local now, i = time(), 1
  while list[i] do
    local x = list[i]
    if (x.stop or x.t or 0) < now - (AUTO_KEEP[x.kind] or AUTO_KEEP.day) then table.remove(list, i) else i = i + 1 end
  end
  while #list > AUTO_MAX do table.remove(list, 1) end
end

-- Into autoSessions, unless nothing happened in it.
local function finishAuto(rec, kind)
  if not rec then return end
  local e = ns.AutoSessionEntry(rec, kind)
  if e.earned ~= 0 or e.spent ~= 0 or e.loot ~= 0 then
    ns.db.autoSessions = ns.db.autoSessions or {}
    local list = ns.db.autoSessions
    list[#list + 1] = e
  end
  trimAuto()
end
ns.FinishAutoSession = finishAuto   -- (tests)

-- Days that are over: finished. This character's, if it's playing across midnight, goes on
-- in a new day from now.
rollDays = function()
  local a = autoLive()
  if not a then return end
  local today, me = ns.LocalDay(), ns.CharKey()
  for c, rec in pairs(a.days) do
    if rec.day ~= today then
      local playing = c == me and rec.resume
      finishAuto(rec, "day")
      a.days[c] = playing and newRecord(today) or nil
    end
  end
end

local autoTicker
local function autoTick()
  local a = autoLive()
  if not a then return end
  local me, now = ns.CharKey(), time()
  if a.login and a.login.char == me and a.login.resume then a.login.seen = now end
  local d = a.days[me]
  if d and d.resume then d.seen = now end
  if d and d.day ~= ns.LocalDay() then rollDays() end
end

ns:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  local a = autoLive()
  if not a then return end
  local me, now = ns.CharKey(), time()
  local fresh = isLogin or isReload
  if fresh then
    -- Left running when the game closed without a logout: counted up to when last seen.
    local recs = { a.login }
    for _, rec in pairs(a.days) do recs[#recs + 1] = rec end
    for _, rec in pairs(recs) do
      if rec.resume then bank(rec, rec.seen or rec.resume); rec.out = rec.out or rec.seen end
    end
  end
  rollDays()
  if fresh then trimAuto() end
  -- This login: a /reload carries on the one before it, anything else starts a new one.
  local L = a.login
  if fresh or not (L and L.char == me) then
    if L and L.char == me and isReload and L.out and now - L.out <= RELOAD_SECONDS then
      L.resume, L.seen, L.final, L.out = now, now, nil, nil
    else
      finishAuto(L, "login")
      a.login = newRecord()
    end
  end
  -- Today, for this character: carried on from an earlier login today, or a new day.
  local D = a.days[me]
  if not D then
    a.days[me] = newRecord(ns.LocalDay())
  elseif fresh or not D.resume then
    D.resume, D.seen, D.final, D.out = now, now, nil, nil
  end
  if not autoTicker and C_Timer and C_Timer.NewTicker then autoTicker = C_Timer.NewTicker(60, autoTick) end
end)

-- Logging out (or reloading): the loot is valued now, while the bags can say what's held,
-- and the clocks stop.
ns:On("PLAYER_LOGOUT", function()
  local a = ns.db and ns.db.autoLive
  if not a then return end
  local me, now = ns.CharKey(), time()
  for _, rec in pairs({ a.login or false, (a.days or {})[me] or false }) do
    if rec and rec.char == me and rec.resume then
      local st = ns:SessionTotals(rec)
      rec.final = { loot = st.loot, top = topOf(st) }
      bank(rec, now)
      rec.out = now
    end
  end
end)

-- The records not yet finished, as Ledger rows: this character's login and day (running =
-- true), and today's days of characters that logged out earlier today, as they were at their
-- logout (Codex review, November 24: those were missing from Each day until midnight).
function ns:AutoSessionsRunning()
  local a = ns.db and ns.db.autoLive
  local me, out = ns.CharKey(), {}
  if not a then return out end
  if a.login and a.login.char == me and a.login.resume then out[#out + 1] = ns.AutoSessionEntry(a.login, "login", true) end
  local today = ns.LocalDay()
  for c, d in pairs(a.days or {}) do
    if c == me and d.resume then
      out[#out + 1] = ns.AutoSessionEntry(d, "day", true)
    elseif d.day == today and not d.resume then
      local e = ns.AutoSessionEntry(d, "day")
      if e.earned ~= 0 or e.spent ~= 0 or e.loot ~= 0 then out[#out + 1] = e end
    end
  end
  return out
end
