-- First and full sync build the books from time 0. In the old offset calculation, a
-- clock east of UTC can interpret that instant's UTC fields as a pre-epoch timestamp.
-- Model a clock that refuses that conversion. Two synthetic accounts exchange messages
-- through Sync.lua's hello, send and receive paths.
local T = ...
local ns, S = T.ns, T.S

---------------------------------------------------------------------------
-- The made-up clock
---------------------------------------------------------------------------
local DAY = 86400

-- Days since January 1, 1970 of a date, and back (the usual civil calendar sums).
local function daysOf(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end
local function dateOf(days)
  local z = days + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local m = mp + (mp < 10 and 3 or -9)
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, doy - math.floor((153 * mp + 2) / 5) + 1
end

-- A zone: std seconds ahead of UTC; with summer time, dst seconds ahead from the UTC time
-- `from` until `to` (the 2026 changes of central Europe and the eastern United States).
local function at(y, m, d, h) return daysOf(y, m, d) * DAY + h * 3600 end
local EAST = { std = 3600, dst = 7200, from = at(2026, 3, 29, 1), to = at(2026, 10, 25, 1) }
local WEST = { std = -18000, dst = -14400, from = at(2026, 3, 8, 7), to = at(2026, 11, 1, 6) }

local function ahead(zone, t)
  local summer = zone.dst ~= nil and t >= zone.from and t < zone.to
  return summer and zone.dst or zone.std, summer
end

local function fields(t, isdst)
  local days = math.floor(t / DAY)
  local secs = t - days * DAY
  local y, m, d = dateOf(days)
  return { year = y, month = m, day = d, hour = math.floor(secs / 3600), min = math.floor(secs / 60) % 60, sec = secs % 60,
    wday = (days + 4) % 7 + 1, yday = days - daysOf(y, 1, 1) + 1, isdst = isdst }
end

local realTime, realDate = time, date
local zoneNow   -- the made-up clock's zone, or nil for this computer's clock

-- LocalDay keeps each quarter hour's offset and starts over after 4096 of them (History.lua):
-- another clock's are pushed out with as many quarter hours no test uses.
local forgotten = 0
local function forgetOffsets()
  for i = 1, 4096 do ns.LocalDay(3000000000 + (forgotten * 4096 + i) * 900) end
  forgotten = forgotten + 1
end

local function setClock(zone)
  zoneNow = zone
  if not zone then
    time, date = realTime, realDate
  else
    date = function(fmt, t)
      t = t or S.now
      if fmt == "!*t" then return fields(t, false) end
      if fmt == "*t" then
        local off, summer = ahead(zone, t)
        return fields(t + off, summer)
      end
      return realDate(fmt, t)
    end
    time = function(d)
      if not d then return S.now end
      local wall = daysOf(d.year, d.month, d.day) * DAY + (d.hour or 12) * 3600 + (d.min or 0) * 60 + (d.sec or 0)
      local t
      if d.isdst == nil then
        t = wall - zone.std
        if ahead(zone, t) ~= zone.std then t = wall - zone.dst end
      else
        t = wall - (d.isdst and zone.dst or zone.std)
      end
      if t < 0 then return nil end   -- (the made-up clock's limit: no local date before 1970)
      return t
    end
  end
  forgetOffsets()
end

-- Run fn on the made-up clock, and put this computer's back whatever happens.
local function onClock(zone, fn)
  setClock(zone)
  local ok, err = pcall(fn)
  setClock(nil)
  assert(ok, err)
end

-- The local day the made-up clock itself says a time is on.
local function dayOn(zone, t) return math.floor((t + ahead(zone, t)) / DAY) end

---------------------------------------------------------------------------
-- LocalDay
---------------------------------------------------------------------------
T.test("LocalDay: the start of 1970 has a local day in every zone, on a clock that converts no date before 1970", function()
  -- ahead: seconds ahead of UTC; day: the local day of time 0; midnight: the first local
  -- midnight after it.
  for _, z in ipairs({ { ahead = 3600, day = 0, midnight = 23 * 3600 }, { ahead = 14 * 3600, day = 0, midnight = 10 * 3600 },
    { ahead = 20700, day = 0, midnight = DAY - 20700 }, { ahead = 0, day = 0, midnight = DAY },
    { ahead = -18000, day = -1, midnight = 18000 }, { ahead = -12 * 3600, day = -1, midnight = 12 * 3600 } }) do
    onClock({ std = z.ahead }, function()
      local what = ("%+d seconds from UTC"):format(z.ahead)
      T.eq(ns.LocalDay(0), z.day, what)
      T.eq(ns.LocalDay(z.midnight - 1), z.day, what .. ", the last second of that day")
      T.eq(ns.LocalDay(z.midnight), z.day + 1, what .. ", the next local midnight")
    end)
  end
end)

-- (Passes before the repair too: ordinary dates were never the trouble.)
T.test("LocalDay: local days across summer time changes and midnights, east and west of UTC", function()
  for _, zone in ipairs({ EAST, WEST }) do
    onClock(zone, function()
      for _, change in ipairs({ zone.from, zone.to }) do
        for t = change - 2 * DAY, change + 2 * DAY, 900 do
          local want = dayOn(zone, t)
          if ns.LocalDay(t) ~= want then error(("at %d: expected day %d, got %d"):format(t, want, ns.LocalDay(t))) end
        end
      end
      -- The second before and at local midnight, in winter and in summer.
      for _, noonUTC in ipairs({ at(2026, 1, 15, 12), at(2026, 7, 15, 12) }) do
        local midnight = (dayOn(zone, noonUTC) + 1) * DAY - ahead(zone, noonUTC)
        T.eq(ns.LocalDay(midnight - 1), dayOn(zone, noonUTC))
        T.eq(ns.LocalDay(midnight), dayOn(zone, noonUTC) + 1)
      end
    end)
  end
end)

-- This computer's own clock and zone (try TZ=Europe/Berlin, America/New_York,
-- Australia/Lord_Howe, Pacific/Kiritimati): the day is the date the clock itself shows.
T.test("LocalDay: the same day as this computer's own calendar, every quarter hour of two years", function()
  forgetOffsets()
  local function check(t)
    local d = os.date("*t", t)
    local want = daysOf(d.year, d.month, d.day)
    if ns.LocalDay(t) ~= want then error(("at %d (%s): expected day %d, got %d"):format(t, os.date("%c", t), want, ns.LocalDay(t))) end
  end
  for t = at(2025, 12, 31, 0), at(2027, 1, 2, 0), 900 do check(t) end
  for t = 0, 3 * DAY, 900 do check(t) end
  forgetOffsets()
end)

---------------------------------------------------------------------------
-- Two accounts
---------------------------------------------------------------------------
local PREFIX = "FLedger1"
local REALM = "Testrealm"
local pristine = ns.Serialize(ns.db)
ns.RefreshUI = ns.RefreshUI or function() end

local sent = {}
C_ChatInfo = C_ChatInfo or {}
local realSend, realUnitName = C_ChatInfo.SendAddonMessage, UnitName
C_ChatInfo.SendAddonMessage = function(_, text, channel, to)
  sent[#sent + 1] = { text = text, channel = channel, to = to }
  return true
end

-- An account's saved data with one character played on it, linked to partner and sharing
-- gold, sales, bags and bank. salt keeps the two accounts' numbers apart.
local function account(first, last, partner, salt)
  local key = first .. " " .. last .. "-" .. REALM
  local now = S.now
  -- (days counted by hand: LocalDay is what's being tested)
  local today = math.floor(now / DAY)
  local db = ns.Deserialize(pristine)
  db.settings.syncPartner = partner
  db.settings.syncMoney, db.settings.syncBags = true, true
  db.chars[key] = { name = first .. " " .. last, realm = REALM, faction = "Alliance", updated = now - salt, profs = {} }
  db.inventory[key] = { bags = { [2589] = 10 + salt }, bank = { [2592] = 20 + salt }, t = now - salt, bankT = now - 2 * salt }
  db.gold[key] = { [math.floor(now / 3600)] = 5000 + salt, [math.floor(now / 3600) - 24 * 500] = 100 + salt }
  db.money[key] = { [today] = { loot = 7 + salt }, [today - 500] = { quest = 3 + salt } }
  db.sales = { { t = now - 20 * DAY, c = key, id = 2589, q = 2, a = 400 + salt }, { t = now - 60, c = key, id = 2592, q = 1, a = 90 + salt } }
  db.purchases = { { t = now - 120, c = key, id = 2589, q = 1, a = 30 + salt } }
  db.vendorLog = { { t = now - 30, c = key, id = 2592, q = 1, a = 2 + salt, s = "sell" } }
  db.ledgerMonths = { { t = now - 400 * DAY, c = key, k = "sale", id = 2589, q = 9, a = 900 + salt, cnt = 3, mx = 500 } }
  return { first = first, last = last, name = first .. " " .. last, key = key, db = db }
end
-- Both synthetic characters share a first name, so the tests check their full names.
local function twoAccounts()
  return account("Test", "Copper", "Test Silver", 1), account("Test", "Silver", "Test Copper", 2)
end

-- This client logs in on an account. The last one's session (queue, books on their way, the
-- partner seen online) is ended by unlinking in saved data nobody keeps.
local playing
local function login(acct)
  local function load(db)
    for k in pairs(ns.db) do ns.db[k] = nil end
    for k, v in pairs(db) do ns.db[k] = v end
  end
  if playing then
    playing.db = {}
    for k, v in pairs(ns.db) do playing.db[k] = v end
  end
  load(ns.Deserialize(pristine))
  ns:SyncCommand("unpair")
  T.runTimers()
  playing = acct
  if acct then
    UnitName = function() return acct.first, acct.last end
    load(acct.db)
  else
    UnitName = realUnitName
  end
  sent = {}
end

-- The whispers this client sent since the last look, as they went.
local function take()
  T.runTimers()
  local out = sent
  sent = {}
  return out
end

-- The whole messages in some whispers.
local function messages(wire)
  local parts, out = {}, {}
  for _, w in ipairs(wire) do
    local id, i, n, chunk = w.text:match("^(%d+):(%d+):(%d+):(.*)$")
    parts[id] = parts[id] or {}
    parts[id][tonumber(i)] = chunk
    if #parts[id] == tonumber(n) then out[#out + 1] = ns.Deserialize(table.concat(parts[id])) end
  end
  return out
end
local function find(list, want)
  for _, m in ipairs(list) do if want(m) then return m end end
end
local function isWho(m) return m.k == "d" and m.chars ~= nil end
local function isBooks(m) return m.k == "d" and m.books ~= nil end

-- Whispers arrive, from a character by that name.
local function receive(wire, from)
  for _, w in ipairs(wire) do T.fire("CHAT_MSG_ADDON", PREFIX, w.text, "WHISPER", from) end
  T.runTimers()
end

-- A partner's hello, by hand.
local function helloFrom(acct)
  local text = ns.Serialize({ k = "h", v = 1, books = 2, reply = true })
  receive({ { text = "71:1:1:" .. text } }, acct.name)
end

local function noErrors(before, what)
  if #S.errors > before then error(("%s: %s"):format(what, S.errors[#S.errors]), 2) end
end

-- What one account's saved data must hold of the other's after a sync: the character, its
-- bags and bank, and all of its books.
local function hasAll(of, mark, what)
  local c, was = ns.db.chars[of.key], of.db.chars[of.key]
  T.ok(c, what .. ": the character is listed")
  T.eq(c.name, of.name, what)
  T.eq(c.via, mark, what .. ": marked as the partner's")
  local inv = ns.db.inventory[of.key]
  T.ok(inv, what .. ": bags and bank")
  T.same(inv.bags, of.db.inventory[of.key].bags, what .. " bags")
  T.same(inv.bank, of.db.inventory[of.key].bank, what .. " bank")
  T.eq(inv.t, of.db.inventory[of.key].t, what .. ": the bags' own time")
  T.eq(inv.bankT, of.db.inventory[of.key].bankT, what .. ": the bank's own time")
  T.eq(c.updated, was.updated, what .. ": the character's own time")
  T.same(ns.db.gold[of.key], of.db.gold[of.key], what .. " gold")
  T.same(ns.db.money[of.key], of.db.money[of.key], what .. " money")
  for _, log in ipairs({ "sales", "purchases", "vendorLog", "ledgerMonths" }) do
    local here, there = {}, {}
    for _, e in ipairs(ns.db[log]) do if e.c == of.key then here[#here + 1] = e end end
    for _, e in ipairs(of.db[log]) do if e.c == of.key then there[#there + 1] = e end end
    T.same(here, there, what .. " " .. log)
  end
end

-- Both accounts log in and sync for the first time, sharing gold, sales, bags and bank.
local function firstSync()
  local a, b = twoAccounts()
  local errors = #S.errors

  -- The second account logs in and does /fl sync now: a hello, with the first not seen yet.
  login(b)
  ns:SyncCommand("now")
  local fromB = take()
  T.ok(find(messages(fromB), function(m) return m.k == "h" end), "a hello")

  -- The first hears it, answers, and sends everything.
  login(a)
  receive(fromB, b.name)
  noErrors(errors, "the first account's send")
  T.eq(select(2, ns:SyncInfo()), true, "online")
  local fromA = take()
  for _, w in ipairs(fromA) do T.eq(w.to, b.name, "whispered to the partner only") end
  local list = messages(fromA)
  local who, books = find(list, isWho), find(list, isBooks)
  T.ok(who, "the first account's characters went")
  T.ok(who.chars[a.key] and who.inventory[a.key], "with bags and bank")
  T.ok(books, "and its books")
  T.eq(books.books.from, 0, "everything, the first time")
  T.eq(#books.books.months, 1, "with the monthly totals")

  -- The second takes it in, answers, and sends its own.
  login(b)
  receive(fromA, "Test Stranger")
  T.eq(ns.db.chars[a.key], nil, "nothing from someone else with the same first name")
  receive(fromA, a.name)
  noErrors(errors, "the second account taking it in")
  hasAll(a, a.name, "the first account, on the second")
  T.eq(ns.db.chars[b.key].via, nil, "its own character stays its own")
  fromB = take()
  list = messages(fromB)
  T.eq((find(list, function(m) return m.k == "a" end) or {}).books, books.books.to, "the books are answered")
  T.ok(find(list, isWho) and find(list, isBooks), "the second account's characters and books went")

  -- And the first takes in the second's.
  login(a)
  local own = ns.Serialize({ ns.db.chars[a.key], ns.db.inventory[a.key], ns.db.gold[a.key], ns.db.money[a.key] })
  receive(fromB, b.name)
  noErrors(errors, "the first account taking it in")
  hasAll(b, b.name, "the second account, on the first")
  T.ok(find(messages(take()), function(m) return m.k == "a" end), "the second's books are answered")
  -- A newer record of the first account's own character, from the partner, changes nothing of it.
  local later = S.now + 999
  receive({ { text = "75:1:1:" .. ns.Serialize({ k = "d",
    chars = { [a.key] = { name = a.name, realm = REALM, faction = "Alliance", updated = later, profs = {} } },
    inventory = { [a.key] = { bags = {}, bank = {}, t = later, bankT = later } },
    books = { from = 0, to = later, chars = { [a.key] = { gold = {}, money = {} } } } }) } }, b.name)
  noErrors(errors, "the first account taking that in")
  T.eq(ns.Serialize({ ns.db.chars[a.key], ns.db.inventory[a.key], ns.db.gold[a.key], ns.db.money[a.key] }), own,
    "its own character, bags, gold and money untouched")
  take()
  login(nil)
end

T.test("A first sync on a clock that converts no date before 1970: characters, bags and books both ways", function()
  onClock(EAST, firstSync)
end)

-- (Passes before the repair too: west of UTC the date asked for is in 1970, and converts.)
T.test("A first sync on a clock west of UTC, where the date converts: the same", function()
  onClock(WEST, firstSync)
end)

-- (Passes before the repair too: with gold and sales off, no books are made.)
T.test("With nothing shared, only the characters go, on a clock that converts no date before 1970 too", function()
  onClock(EAST, function()
    local a, b = twoAccounts()
    a.db.settings.syncMoney, a.db.settings.syncBags = false, false
    local errors = #S.errors
    login(a)
    helloFrom(b)
    noErrors(errors, "the send")
    local list = messages(take())
    local who = find(list, isWho)
    T.ok(who and who.chars[a.key], "the character went")
    T.eq(next(who.inventory), nil, "no bags or bank without a yes")
    T.eq(find(list, isBooks), nil, "no books without a yes")
    login(nil)
  end)
end)

T.test("Full books count as arrived once answered, then only what's new goes, until /fl sync now", function()
  onClock(EAST, function()
    local a, b = twoAccounts()
    local errors = #S.errors
    login(a)
    helloFrom(b)
    local first = find(messages(take()), isBooks)
    T.ok(first, "the books went")
    local st = ns.db.sync[b.name:lower()]
    T.eq(st.booksTo, nil, "not until the partner answers")
    receive({ { text = "72:1:1:" .. ns.Serialize({ k = "a", books = first.books.to }) } }, b.name)
    T.eq(st.booksTo, first.books.to, "arrived")

    -- A sale a little later: only the recent stretch goes.
    S.now = S.now + 600
    table.insert(ns.db.sales, { t = S.now, c = a.key, id = 2589, q = 1, a = 77 })
    ns:BooksChanged(true)
    local list = messages(take())
    local later = find(list, isBooks)
    T.ok(later, "the new sale's books went")
    T.eq(later.books.from, first.books.to - 300)
    T.eq(later.books.months, nil, "no monthly totals with a stretch")
    T.eq(#later.books.sales, 2, "the sales since then, the new one and one from the minutes sent again")
    T.eq(later.books.chars[a.key].money[math.floor(S.now / DAY) - 500], nil, "old days of money stay out of a stretch")
    T.eq(find(list, isWho), nil, "the character, unchanged, doesn't go again")
    receive({ { text = "73:1:1:" .. ns.Serialize({ k = "a", books = later.books.to }) } }, b.name)

    -- /fl sync now: everything again.
    S.now = S.now + 600
    ns:SyncCommand("now")
    list = messages(take())
    local who, all = find(list, isWho), find(list, isBooks)
    T.ok(who and who.chars[a.key] and who.inventory[a.key], "the character, bags and bank again")
    T.ok(all, "the books again")
    T.eq(all.books.from, 0, "all of them")
    T.eq(#all.books.months, 1)
    T.eq(#all.books.sales, 3)
    T.ok(all.books.chars[a.key].money[math.floor(S.now / DAY) - 500], "old days of money too")
    noErrors(errors, "the sends")
    login(nil)
  end)
end)

T.test("Books that can't be made don't stop the characters going, and are due again at the next send", function()
  local a, b = twoAccounts()
  local realBooks = ns.BooksSince
  local function broken() error("no books today") end
  local ok, err = pcall(function()
    -- At the first hello.
    local errors = #S.errors
    login(a)
    ns.BooksSince = broken
    helloFrom(b)
    local list = messages(take())
    local who = find(list, isWho)
    T.ok(who and who.chars[a.key] and who.inventory[a.key], "the character, bags and bank went")
    T.eq(find(list, isBooks), nil, "no books")
    T.ok(#S.errors > errors and S.errors[#S.errors]:find("no books today", 1, true), "the error is still reported")
    ns.BooksSince = realBooks
    ns:SyncSend(false)
    local books = find(messages(take()), isBooks)
    T.ok(books, "the books go at the next send")
    T.eq(books.books.from, 0, "all of them: none had arrived")

    -- And at /fl sync now, with the books arrived and nothing new since.
    receive({ { text = "74:1:1:" .. ns.Serialize({ k = "a", books = books.books.to }) } }, b.name)
    errors = #S.errors
    S.now = S.now + 600
    ns.BooksSince = broken
    ns:SyncCommand("now")
    list = messages(take())
    T.ok(find(list, isWho), "the character went again")
    T.eq(find(list, isBooks), nil, "no books")
    T.ok(#S.errors > errors, "reported again")
    ns.BooksSince = realBooks
    ns:SyncSend(false)
    T.ok(find(messages(take()), isBooks), "the books go at the next send")
  end)
  ns.BooksSince = realBooks
  login(nil)
  assert(ok, err)
end)

-- Leave the next test file this computer's clock, the usual character and no link.
C_ChatInfo.SendAddonMessage = realSend
login(nil)
setClock(nil)
