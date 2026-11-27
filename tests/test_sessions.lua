-- Sessions.lua (November 17): loot counted once (a player on CurseForge: sold loot counted
-- as loot and again as gold), pause, usual pace and the full view's lines.
local T = ...
local ns, S = T.ns, T.S

local A, B = 990101, 990102   -- items no other test uses

-- A running session on this character with loot already in it, each item worth 100c.
local function session(loot)
  ns.db.liveSession = { t = S.now - 600, resume = S.now - 600, active = 0, char = ns.CharKey(), money = {}, loot = loot }
  return ns.db.liveSession
end
local function withValues(fn)
  local real = ns.LootValue
  ns.LootValue = function(_, id) return (id == A or id == B) and 100 or 0 end
  local ok, err = pcall(fn)
  ns.LootValue = real
  ns.db.liveSession = nil
  S.bags[A], S.bags[B], S.bank[A] = nil, nil, nil
  if not ok then error(err, 0) end
end

T.test("Sessions: loot sold during the session counts once, as gold", function()
  withValues(function()
    S.items[A] = { name = "Session Test Cloth" }
    local s = session({ [A] = 5, [B] = 2 })
    S.bags[A], S.bags[B] = 5, 2
    T.eq(ns:SessionTotals().loot, 700, "all of it, still in the bags")
    -- Sold 2 to a vendor: they're gold now (History.lua passes the item ID).
    ns:SessionSold(A, 2)
    S.bags[A] = 3
    ns:SessionMoney("vendorSell", 200)
    local st = ns:SessionTotals()
    T.eq(st.loot, 500, "3 + 2 left as loot")
    T.eq(st.gained, 200, "the 2 sold, as gold")
    -- An auction sale names the item; it counts when posted during the session.
    ns:SessionPosted(A, 1)
    ns:SessionSold("Session Test Cloth", 1)
    T.eq(s.sold[A], 3)
    -- Never more sold than looted.
    ns:SessionSold(A, 50)
    T.eq(s.sold[A], 5)
    S.bags[A] = 10   -- (bought more: still only what was looted, less what was sold)
    T.eq(ns:SessionTotals().loot, 200, "only B left")
  end)
end)

T.test("Sessions: auction sales count only what was posted this session, random stats too", function()
  -- (Codex review, November 17: an old auction's money took new loot off; a sale named
  -- with random stats didn't match the looted item.)
  withValues(function()
    S.items[A] = { name = "Session Test Sword" }
    local oldName = ns.db.itemNames[A]
    ns.db.itemNames[A] = "Session Test Sword"   -- (saved names come first; an earlier test named it)
    local s = session({ [A] = 5 })
    S.bags[A] = 5
    ns:SessionSold("Session Test Sword", 5)   -- an auction posted before the session
    T.eq(s.sold and s.sold[A], nil, "not posted this session: the new loot stays loot")
    T.eq(ns:SessionTotals().loot, 500)
    ns:SessionPosted(A, 2)
    S.bags[A] = 3
    ns:SessionSold("Session Test Sword of Strength", 1)
    T.eq(s.sold[A], 1, "the version with random stats is the looted sword")
    ns:SessionSold("Session Test Sword of the Bear", 5)
    T.eq(s.sold[A], 2, "no more than was posted")
    T.eq(s.posted[A], 0)
    ns:SessionPosted(A, 1)
    ns:SessionSold("Session Test Swordfish", 1)
    T.eq(s.sold[A], 2, "another item whose name starts the same")
    T.eq(s.posted[A], 1)
    S.items[A], ns.db.itemNames[A] = nil, oldName
  end)
end)

T.test("Sessions: a sale whose mail came before the post isn't this session's loot", function()
  -- (Codex verification, November 18: loot 5 cloth, post them, then collect an old
  -- invoice for 20: the 5 still listed went from loot.)
  withValues(function()
    S.items[A] = { name = "Session Test Linen" }
    local oldName = ns.db.itemNames[A]
    ns.db.itemNames[A] = "Session Test Linen"
    local s = session({ [A] = 5 })
    ns:SessionPosted(A, 5)   -- posted now (S.now); bags empty, the 5 listed
    ns:SessionSold("Session Test Linen", 20, S.now - 7200)   -- an old sale's mail, 2 hours ago
    T.eq(s.sold and s.sold[A], nil, "the listed loot stays loot")
    T.eq(s.posted[A], 5, "and its posts are still there for its own sale")
    ns:SessionSold("Session Test Linen", 3, S.now + 3600)   -- one of them sold, mail an hour later
    T.eq(s.sold[A], 3)
    T.eq(s.posted[A], 2)
    T.eq(#s.postedAt[A], 1, "posts used oldest first")
    T.eq(s.postedAt[A][1][2], 2)
    ns:SessionSold("Session Test Linen", 9)   -- no mail time: as before, what's posted
    T.eq(s.sold[A], 5)
    S.items[A], ns.db.itemNames[A] = nil, oldName
  end)
end)

T.test("Sessions: posts from before their times were kept still count after a new one", function()
  -- (Codex verification, November 19: a session running across that update had posted 3
  -- with no times; one new post of 2 made those 3 unusable, so their sale left them as loot.)
  withValues(function()
    S.items[A] = { name = "Session Test Hoop" }
    local oldName = ns.db.itemNames[A]
    ns.db.itemNames[A] = "Session Test Hoop"
    local s = session({ [A] = 5 })
    s.posted = { [A] = 3 }   -- the older shape: counts, no times
    ns:SessionPosted(A, 2)
    T.eq(s.posted[A], 5)
    ns:SessionSold("Session Test Hoop", 3, S.now - 1800)   -- the older 3, mail before the new post
    T.eq(s.sold and s.sold[A], 3, "the 3 posted before times were kept")
    T.eq(s.posted[A], 2)
    T.eq(s.postedAt[A][1][2], 2, "the new post is still there for its own sale")
    ns:SessionSold("Session Test Hoop", 2, S.now - 1800)
    T.eq(s.sold[A], 3, "the new 2 can't be a sale whose mail came before them")
    S.items[A], ns.db.itemNames[A] = nil, oldName
  end)
end)

T.test("Sessions: a reset popup left open never clears a newer session", function()
  -- (Codex verification, November 19: stop, start again, then Accept cleared the new one.)
  withValues(function()
    local a = session({ [A] = 1 })
    local popup = {}
    local realShow = StaticPopup_Show
    StaticPopup_Show = function() return popup end
    ns:ResetGeneralSession()
    StaticPopup_Show = realShow
    T.eq(popup.data, a, "the popup holds the session it described")
    local b = session({ [B] = 2 })   -- a new one in its place
    ns:SessionMoney("loot", 900)
    StaticPopupDialogs.FOREVER_LEDGER_SESSION_RESET.OnAccept(popup, popup.data)
    T.eq(ns.db.liveSession, b, "the new session is untouched")
    T.eq(b.money.loot, 900)
    StaticPopupDialogs.FOREVER_LEDGER_SESSION_RESET.OnAccept(popup, b)
    T.ok(ns.db.liveSession ~= b, "the one it described is reset")
  end)
end)

T.test("Sessions: loot no longer held drops out; posted auctions still count", function()
  withValues(function()
    session({ [A] = 4 })
    S.bags[A], S.bank[A] = 1, 1
    T.eq(ns:SessionTotals().loot, 200, "disenchanted or used: only what's left")
    ns.db.myAuctions = ns.db.myAuctions or {}
    ns.db.myAuctions[ns.CharKey()] = { list = { { id = A, q = 2 }, { id = A, q = 5, sold = true } } }
    T.eq(ns:SessionTotals().loot, 400, "2 on the auction house, not sold yet")
    ns.db.myAuctions[ns.CharKey()] = nil
    S.bags[A], S.bank[A] = 0, 0
    local st = ns:SessionTotals()
    T.eq(st.loot, 0)
    T.eq(#st.items, 0)
  end)
end)

T.test("Sessions: items without a price are counted apart", function()
  withValues(function()
    session({ [A] = 1, [990103] = 3 })
    S.bags[A], S.bags[990103] = 1, 3
    local st = ns:SessionTotals()
    T.eq(st.loot, 100)
    T.eq(st.unpriced, 3)
    S.bags[990103] = nil
  end)
end)

T.test("Sessions: pause stops the clock and the counting", function()
  withValues(function()
    local s = session({})
    T.eq(ns:SessionTotals().secs, 600)
    ns:PauseGeneralSession(true)
    T.ok(s.paused, "paused")
    T.eq(s.active, 600, "the time so far banked")
    ns:SessionMoney("loot", 500)
    T.eq(s.money.loot, nil, "nothing counted while paused")
    S.now = S.now + 300
    T.eq(ns:SessionTotals().secs, 600, "the clock stood still")
    ns:PauseGeneralSession(false)
    T.eq(s.paused, nil)
    S.now = S.now + 60
    T.eq(ns:SessionTotals().secs, 660, "and runs again")
    ns:SessionMoney("loot", 500)
    T.eq(s.money.loot, 500)
    S.now = S.now - 360
  end)
end)

T.test("Sessions: reset asks first, then starts over from zero", function()
  withValues(function()
    local s = session({ [A] = 2 })
    S.bags[A] = 2
    ns:SessionMoney("loot", 500)
    ns:PauseGeneralSession(true)
    local asked
    local realShow = StaticPopup_Show
    StaticPopup_Show = function(which) asked = which end
    ns:ResetGeneralSession()
    StaticPopup_Show = realShow
    T.eq(asked, "FOREVER_LEDGER_SESSION_RESET", "asks first")
    T.eq(ns.db.liveSession, s, "nothing changed yet")
    local kept = #(ns.db.sessions or {})
    StaticPopupDialogs.FOREVER_LEDGER_SESSION_RESET.OnAccept()
    local st = ns:SessionTotals()
    T.ok(ns.db.liveSession ~= s, "a new one")
    T.eq(st.gained, 0)
    T.eq(st.loot, 0)
    T.eq(st.secs, 1, "the clock from zero")
    T.eq(ns.db.liveSession.paused, nil, "counting again")
    T.eq(#(ns.db.sessions or {}), kept, "the old one isn't kept")
  end)
end)

T.test("Sessions: gold an hour after 5 minutes, usual and best pace", function()
  T.eq(ns.SessionRate({ secs = 200, earned = 100 }), nil, "too short")
  T.eq(ns.SessionRate({ secs = 3600, earned = 1000, spent = 200, loot = 400 }), 1200, "gold and loot")
  local saved = ns.db.sessions
  ns.db.sessions = {
    { kind = "general", secs = 3600, earned = 1000 },
    { kind = "general", secs = 300, earned = 99999 },   -- under 10 minutes: not counted
    { kind = "general", secs = 3600, earned = 3000 },
  }
  T.eq(ns:SessionUsual(), nil, "needs 3 sessions")
  ns.db.sessions[#ns.db.sessions + 1] = { kind = "general", secs = 1800, earned = 1000 }   -- 2000 an hour
  ns.db.sessions[#ns.db.sessions + 1] = { kind = "general", secs = 3600, earned = 4000 }
  local u = ns:SessionUsual()
  T.eq(u and u.n, 4)
  T.eq(u and u.usual, 2500, "the median of 1000, 2000, 3000, 4000")
  T.eq(u and u.best, 4000)
  ns.db.sessions = saved
end)

T.test("Session window: pace points every half minute, never while paused, thinned", function()
  local s = { pace = nil }
  T.ok(ns.SessionPaceSample(s, { secs = 1, gained = 0, loot = 0 }), "the start")
  T.eq(ns.SessionPaceSample(s, { secs = 20, gained = 50, loot = 0 }), nil, "too soon")
  T.ok(ns.SessionPaceSample(s, { secs = 31, gained = 50, loot = 25 }))
  T.eq(s.pace[2][2], 75, "gold and loot")
  s.paused = true
  T.eq(ns.SessionPaceSample(s, { secs = 90, gained = 50, loot = 25 }), nil, "paused")
  s.paused = nil
  for i = 3, 241 do ns.SessionPaceSample(s, { secs = i * 30 + 1, gained = i, loot = 0 }) end
  T.ok(#s.pace <= 240, "kept small")
  T.eq(s.pace[1][1], 1, "from the start")
  T.eq(s.pace[#s.pace][1], 241 * 30 + 1, "to now")
end)

T.test("Session window: the loot table sorts, keeps gray items apart, names the best drop", function()
  local names = { [A] = "Bolt of Cloth", [B] = "Aqua Gem", [990104] = "Broken Tooth" }
  local realName = ns.ItemName
  ns.ItemName = function(id) return names[id] end
  local items = { { id = A, n = 10, value = 1000 }, { id = B, n = 1, value = 500 }, { id = 990104, n = 4, value = 40 } }
  local quality = function(id) return id == 990104 and 0 or 2 end
  local ok, err = pcall(function()
    local t = ns.SessionLootRows(items, "value", nil, quality)
    T.eq(#t.rows, 2)
    T.eq(t.rows[1].id, A, "biggest total first")
    T.eq(#t.grays, 1)
    T.eq(t.grayValue, 40)
    T.eq(t.best.id, B, "the best drop: worth most each (500 against 100)")
    T.eq(ns.SessionLootRows(items, "name", nil, quality).rows[1].id, B, "A to Z")
    T.eq(ns.SessionLootRows(items, "name", true, quality).rows[1].id, A, "turned around")
    T.eq(ns.SessionLootRows(items, "n", nil, quality).rows[1].id, A, "most first")
    T.eq(ns.SessionLootRows({ { id = 990104, n = 1, value = 5 } }, "value", nil, quality).best.id, 990104, "only gray: still a best drop")
  end)
  ns.ItemName = realName
  if not ok then error(err, 0) end
end)

T.test("Session window: past sessions, newest first, the best one marked", function()
  local saved = ns.db.sessions
  ns.db.sessions = {
    { kind = "general", t = 100, secs = 3600, earned = 1000 },
    { kind = "shuffle", t = 150, secs = 3600, earned = 99999 },
    { kind = "general", t = 200, secs = 3600, earned = 5000 },
    { kind = "general", t = 300, secs = 120, earned = 10 },
  }
  local rows = ns.SessionPastRows(6)
  ns.db.sessions = saved
  T.eq(#rows, 3, "general sessions only")
  T.eq(rows[1].t, 300, "newest first")
  T.eq(rows[1].rate, nil, "too short for a rate")
  T.ok(rows[2].best, "the best gold an hour")
  T.eq(rows[3].best, nil)
end)

-- Frank, November 24: "some sessions just recording at all times ... Daily and per login".
T.test("Sessions: each login and each day are recorded on their own", function()
  withValues(function()
    ns.db.autoLive, ns.db.autoSessions = { days = {} }, {}
    local now, me = S.now, ns.CharKey()
    T.fire("PLAYER_ENTERING_WORLD", true, false)
    local a = ns.db.autoLive
    local L = a.login
    T.ok(L and L.resume, "a login record")
    T.ok(a.days[me] and a.days[me].resume, "and today's")
    T.eq(ns.db.liveSession, nil, "no session of your own is started")
    ns:SessionMoney("vendorSell", 300)
    T.eq(L.money.vendorSell, 300); T.eq(a.days[me].money.vendorSell, 300)
    -- A loading screen is the same login.
    T.fire("PLAYER_ENTERING_WORLD", false, false)
    T.ok(a.login == L)
    -- A /reload carries on the same one.
    S.now = now + 600
    T.fire("PLAYER_LOGOUT")
    T.eq(L.resume, nil); T.ok(L.final, "its loot valued at logout")
    S.now = now + 630
    T.fire("PLAYER_ENTERING_WORLD", false, true)
    T.ok(a.login == L and L.resume, "the same login")
    T.eq(#ns.db.autoSessions, 0)
    T.eq(#ns:AutoSessionsRunning(), 2, "both show in the Ledger, counting")
    -- Logging out and in again: that login is finished; the day goes on.
    S.now = now + 1200
    T.fire("PLAYER_LOGOUT")
    S.now = now + 1500
    T.fire("PLAYER_ENTERING_WORLD", true, false)
    T.eq(#ns.db.autoSessions, 1)
    local e = ns.db.autoSessions[1]
    T.eq(e.kind, "login"); T.eq(e.earned, 300); T.eq(e.secs, 1170, "time played, not the time between")
    T.ok(a.login ~= L, "a new login")
    T.eq(a.days[me].money.vendorSell, 300, "the day carries on")
    -- Past midnight: the day is finished and a new one starts.
    S.now = now + 2 * 86400
    ns:SessionMoney("vendorSell", 50)
    local days = {}
    for _, x in ipairs(ns.db.autoSessions) do if x.kind == "day" then days[#days + 1] = x end end
    T.eq(#days, 1); T.eq(days[1].earned, 300)
    T.eq(a.days[me].money.vendorSell, 50)
    -- A login with nothing in it isn't kept.
    local before = #ns.db.autoSessions
    ns.FinishAutoSession({ t = S.now, active = 100, char = me, money = {}, loot = {} }, "login")
    T.eq(#ns.db.autoSessions, before)
    S.now = now
  end)
  ns.db.autoLive, ns.db.autoSessions = { days = {} }, {}
end)

T.test("Sessions: automatic records are kept 30 days (logins) and a year (days)", function()
  ns.db.autoSessions = {
    { kind = "login", t = S.now - 40 * 86400, stop = S.now - 40 * 86400, earned = 1 },
    { kind = "login", t = S.now - 10 * 86400, stop = S.now - 10 * 86400, earned = 1 },
    { kind = "day", t = S.now - 200 * 86400, stop = S.now - 200 * 86400, earned = 1 },
    { kind = "day", t = S.now - 400 * 86400, stop = S.now - 400 * 86400, earned = 1 },
  }
  ns.FinishAutoSession({ t = S.now, active = 100, char = ns.CharKey(), money = { vendorSell = 5 }, loot = {} }, "login")
  T.eq(#ns.db.autoSessions, 3)
  T.eq(ns.db.autoSessions[1].stop, S.now - 10 * 86400)
  T.eq(ns.db.autoSessions[2].kind, "day")
  ns.db.autoSessions = {}
end)

-- Codex review, November 24: an empty finish skipped the age limits.
T.test("Sessions: old automatic records go even when the finished one is empty", function()
  ns.db.autoSessions = {
    { kind = "login", t = S.now - 40 * 86400, stop = S.now - 40 * 86400, earned = 1 },
    { kind = "day", t = S.now - 400 * 86400, stop = S.now - 400 * 86400, earned = 1 },
    { kind = "day", t = S.now - 20 * 86400, stop = S.now - 20 * 86400, earned = 1 },
  }
  ns.FinishAutoSession({ t = S.now, active = 100, char = ns.CharKey(), money = {}, loot = {} }, "login")
  T.eq(#ns.db.autoSessions, 1)
  T.eq(ns.db.autoSessions[1].stop, S.now - 20 * 86400)
  ns.db.autoSessions = {}
end)

-- Codex review, November 24: a character played earlier today was missing from Each day
-- until midnight.
T.test("Sessions: today's days of characters played earlier show in the Ledger", function()
  withValues(function()
    local today = ns.LocalDay()
    ns.db.autoSessions = {}
    ns.db.autoLive = { days = {
      ["Other Alt-PvE"] = { day = today, t = S.now - 7200, active = 1800, out = S.now - 3600, char = "Other Alt-PvE",
        money = { vendorSell = 100 }, loot = {}, final = { loot = 0, top = {} } },
      ["Quiet Alt-PvE"] = { day = today, t = S.now - 7200, active = 60, out = S.now - 7000, char = "Quiet Alt-PvE", money = {}, loot = {} },
      ["Old Alt-PvE"] = { day = today - 1, t = S.now - 90000, active = 60, out = S.now - 89000, char = "Old Alt-PvE",
        money = { vendorSell = 5 }, loot = {} },
    } }
    local rows = ns:AutoSessionsRunning()
    T.eq(#rows, 1, "the one with money in it, from today")
    T.eq(rows[1].c, "Other Alt-PvE"); T.eq(rows[1].earned, 100); T.eq(rows[1].running, nil, "not counting now")
    T.eq(rows[1].secs, 1800); T.eq(rows[1].stop, S.now - 3600)
  end)
  ns.db.autoLive, ns.db.autoSessions = { days = {} }, {}
end)
