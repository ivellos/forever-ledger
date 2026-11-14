local _, ns = ...
local print = ns.LocalizedPrint

---------------------------------------------------------------------------
-- Live sync between two clients (for example a main and an auction house character
-- on a second account). Uses hidden addon messages whispered to the paired
-- character. Data travels in the same plain-text format as Export/Import and is
-- merged the same way (newer wins); nothing received is ever run as code.
---------------------------------------------------------------------------
local PREFIX = "FLedger1"
local CHUNK = 230            -- characters of data per message (the limit is 255)
local SEND_GAP = 0.3         -- seconds between messages, about 800 characters a second
local THROTTLE_WAIT = 1.5    -- seconds to wait when the game says we're sending too fast
local PRICE_HOURS = 48       -- only prices this recent are sent
local DEBOUNCE = 5           -- seconds to wait after a change before sending
local BOOKS_WAIT = 60        -- gold and sales changes go at most this often
local BOOKS_OVERLAP = 300    -- each send repeats this many seconds (recent entries can change)
local BOOKS_FULL_DAYS = 20   -- away longer: send everything (older entries become monthly totals)
local BOOKS_REPLY_WAIT = 60  -- seconds after the last message before sending them again
local BOOKS_TRIES = 3        -- sends with no reply before waiting for the next hello or change
local REASSEMBLE_TIMEOUT = 120   -- seconds with nothing new for a half-received message
local CATCHUP_DAYS = 14      -- finished days of price history a partner can fill in
local CATCHUP_POLL = 2       -- seconds between checks for a quiet moment to send the next day

local queue, sending = {}, false
local incoming = {}          -- [sender .. id] = { parts, n, got, t }
local partnerOnline = false
local lastSentTo             -- when a message was last sent, for hiding "no player named" errors
local test                   -- running /fl sync test
local ping                   -- running /fl sync ping: { name, ok, failed }
local counter = 0
local booksChanged = true    -- anything new for the partner's Dashboard and Ledger
local booksWaiting = false
local partnerBooks = false   -- the partner's version takes them (said in its hello)
local booksSent              -- books on their way: { to = cursor, waitUntil = GetTime(), tries }
local askedFor               -- who the question about gold and sales was about
local catchUp                -- price history days on their way: { days = { { day, markets } }, i }
local historyGot             -- days of price history received in this catch-up: { days, items }

-- In Forever, UnitName's second value is the last name ("Iveilos", "Veren"), not a server.
local function me()
  local first, last = UnitName("player")
  return (last and last ~= "") and (first .. " " .. last) or first
end
local function partner() return ns.db.settings.syncPartner end

local function realmSuffix()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if not realm or realm == "" then realm = (GetRealmName() or ""):gsub("[%s%-]", "") end
  return realm
end

-- Forever names have a first and last name ("Tamia Corvidae"). Whether whispers
-- need "-Server" on the end is found out by /fl sync ping (settings.syncAddRealm).
local function fullName(name)
  if not name or name:find("-", 1, true) or not ns.db.settings.syncAddRealm then return name end
  local realm = realmSuffix()
  return realm ~= "" and (name .. "-" .. realm) or name
end
local function shortName(name) return name and name:match("^[^-]+") end

-- "tamia corvidae" to "Tamia Corvidae" (the slash command arrives in lower case).
local function titleCase(s)
  s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

local function state()
  local p = (partner() or ""):lower()
  ns.db.sync[p] = ns.db.sync[p] or {}
  return ns.db.sync[p]
end

---------------------------------------------------------------------------
-- Sending: split into chunks, send at a steady pace, back off if throttled
---------------------------------------------------------------------------
local function pump()
  if #queue == 0 then sending = false; return end
  sending = true
  local m = table.remove(queue, 1)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, "WHISPER", m.to)
  lastSentTo = GetTime()
  local sent = ok and (result == nil or result == true or result == 0)
  if not sent then
    table.insert(queue, 1, m)
    ns:Debug("Sync: throttled, waiting", ok and tostring(result) or tostring(result))
    C_Timer.After(THROTTLE_WAIT, pump)
    return
  end
  if test and m.to == fullName(me()) then test.sent = test.sent + 1 end
  C_Timer.After(SEND_GAP, pump)
end

local function send(payload, to)
  if not to then return 0 end
  to = fullName(to)
  counter = counter + 1
  local id = ("%d%d"):format(time() % 100000, counter)
  local text = ns.Serialize(payload)
  local n = math.ceil(#text / CHUNK)
  for i = 1, n do
    queue[#queue + 1] = { to = to, text = ("%s:%d:%d:"):format(id, i, n) .. text:sub((i - 1) * CHUNK + 1, i * CHUNK) }
  end
  if not sending then pump() end
  return n
end

-- The game's "No player named X is currently playing", right after we whispered X:
-- stop sending (once is enough), note they're offline, and hide the message.
local NOT_FOUND = ERR_CHAT_PLAYER_NOT_FOUND_S and ERR_CHAT_PLAYER_NOT_FOUND_S:match("^(.-)%%s") or "No player named "
local function notFound(msg)
  -- (the chat filter below runs outside ns:On, which keeps hidden text away from handlers)
  if issecretvalue and issecretvalue(msg) then return false end
  if not (lastSentTo and GetTime() - lastSentTo < 5 and type(msg) == "string") then return false end
  if msg:sub(1, #NOT_FOUND) ~= NOT_FOUND and not msg:find("No player named", 1, true) then return false end
  local target = (ping and ping.name) or (test and me()) or partner()
  -- The game names only the first word, so match on that.
  local first = target and target:match("^[^%s%-]+")
  return first ~= nil and msg:lower():find(first:lower(), 1, true) ~= nil
end

local function failed()
  local unsent = #queue > 0
  queue = {}
  sending = false
  if unsent and partner() then
    local st = state()
    st.sentUpTo = st.previous
  end
  if booksSent then booksSent, booksChanged = nil, true end
  catchUp = nil   -- (the next hello says which days are still missing)
  if ping then
    ping.failed = true
  elseif test then
    ns:Print(("Sync test stopped: the game says there's no player named %s, so addon whispers to %s don't arrive."):format(
      me(), fullName(me())))
    test = nil
  elseif partnerOnline then
    partnerOnline = false
    ns:Print(("Sync: %s went offline."):format(partner()))
    if ns.RefreshSettings then ns:RefreshSettings() end
  end
end

if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg) return notFound(msg) end)
end
ns:On("CHAT_MSG_SYSTEM", function(msg)
  if notFound(msg) and (ping or test or #queue > 0 or partnerOnline) then failed() end
end)

---------------------------------------------------------------------------
-- What to send
---------------------------------------------------------------------------
-- Everything the partner hasn't had yet: characters updated, prices scanned and
-- vendor prices seen since the last send (prices only from the last PRICE_HOURS).
-- Two parts: your characters (and, if shared, their bags and bank) first, in a small
-- message of their own, then the prices, which can take minutes (owner's test, October
-- 5: 1,451 messages, and nothing showed until the last one arrived). Characters that
-- came from the partner (c.via) aren't sent back.
local function changes(since)
  local who = { k = "d", chars = {}, inventory = {} }
  local data = { k = "d", prices = {}, vendorBuy = {}, vendorSell = {} }
  local now = time()
  for key, c in pairs(ns.db.chars) do
    if not c.via and (c.updated or 0) > since then who.chars[key] = c end
  end
  if ns.db.settings.syncBags then
    for key, inv in pairs(ns.db.inventory or {}) do
      if not inv.via and math.max(inv.t or 0, inv.bankT or 0) > since then who.inventory[key] = inv end
    end
  end
  local watch = {}
  for _, id in ipairs(ns:WatchList()) do watch[id] = true end
  local priceSince = math.max(since, now - PRICE_HOURS * 3600)
  for market, items in pairs(ns.db.prices) do
    for id, rec in pairs(items) do
      if (rec.t or 0) > priceSince then
        data.prices[market] = data.prices[market] or {}
        -- The price ladder only for materials and products of recipes, to keep it small.
        local copy = { m = rec.m, a = rec.a, q = rec.q, t = rec.t, src = rec.src, none = rec.none }
        if watch[id] then copy.l = rec.l end
        data.prices[market][id] = copy
      end
    end
  end
  -- What vendors pay comes from the game on every client, so it isn't sent.
  for id, rec in pairs(ns.db.vendorBuy) do
    if (rec.t or 0) > since then data.vendorBuy[id] = rec end
  end
  return who, data, now
end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
local function countPrices(p) local n = 0; for _, items in pairs(p or {}) do n = n + count(items) end; return n end

function ns:SyncSend(full)
  local to = partner()
  if not to or not partnerOnline then return end
  local st = state()
  local who, data, now = changes(full and 0 or (st.sentUpTo or 0))
  local nWho = count(who.chars) + count(who.inventory)
  local nData = countPrices(data.prices) + count(data.vendorBuy) + count(data.vendorSell)
  -- The Dashboard and Ledger's books: everything the first time, then what's new.
  -- Only to a version that takes them: an older one would drop them, and they wouldn't
  -- be sent again (owner's test, November 5: one client not reloaded yet). Off until you
  -- say so: these name your buyers, and a partner can be a friend (Codex review).
  -- st.booksTo moves on only when the partner says they arrived. With no reply in time
  -- they go again, even with nothing new (Codex review, November 6: the partner reloaded
  -- partway through and the history stayed missing).
  local books
  local waiting = booksSent and GetTime() < booksSent.waitUntil
  if not ns.db.settings.syncMoney then
    st.booksTo = nil   -- (turned on again: everything goes again)
  elseif partnerBooks and not waiting and (full or booksChanged or booksSent) then
    local from = (not full and st.booksTo or 0) - BOOKS_OVERLAP
    if from < now - BOOKS_FULL_DAYS * 86400 then from = 0 end
    books = ns:BooksSince(from)
    books.to = now
  end
  if nWho + nData == 0 and not books then return end
  local n = nWho > 0 and send(who, to) or 0
  if books then
    n = n + send({ k = "d", books = books }, to)
    local wait = (#queue * SEND_GAP) + BOOKS_REPLY_WAIT
    local these = { to = now, waitUntil = GetTime() + wait, tries = (booksSent and booksSent.tries or 0) + 1 }
    booksSent = these
    booksChanged = false
    if these.tries < BOOKS_TRIES then
      C_Timer.After(wait + 1, function()
        if booksSent == these then ns:SyncSend(false) end
      end)
    end
  end
  n = n + (nData > 0 and send(data, to) or 0)
  -- If the partner goes offline before it all arrives, send it again next time.
  st.previous, st.sentUpTo = st.sentUpTo, now
  ns:Debug(("Sync: sending %d characters, %d with bags, %d prices, %d vendor prices to %s in %d messages."):format(
    count(who.chars), count(who.inventory), countPrices(data.prices), count(data.vendorBuy) + count(data.vendorSell), to, n))
end

-- Send changes a few seconds after the last one (scans save many prices in a row).
local soon
function ns:SyncSoon()
  if not partner() or not partnerOnline then return end
  if soon then soon:Cancel() end
  soon = C_Timer.NewTimer(DEBOUNCE, function() soon = nil; ns:SyncSend(false) end)
end

-- Gold changed or a sale was logged (History.lua).
function ns:BooksChanged()
  booksChanged = true
  if booksWaiting or not partner() or not partnerOnline then return end
  booksWaiting = true
  C_Timer.After(BOOKS_WAIT, function()
    booksWaiting = false
    ns:SyncSend(false)
  end)
end

---------------------------------------------------------------------------
-- Price history catch-up (owner, November 8): each day's prices are saved by the
-- account that scanned, and live sync only carries the latest prices, so an account
-- that was offline missed those days in its graphs and usual prices. Each hello says
-- how many items have a price on each of the last CATCHUP_DAYS finished days, and each
-- side sends the days where it has more. One day at a time, only while nothing else is
-- waiting to go, so live prices aren't held up; a full scan's day takes about a minute.
-- Nothing to remember between sessions: if a day doesn't arrive, the next hello's
-- counts still show it missing.
---------------------------------------------------------------------------
local function lastDays()
  local d = ns.LocalDay(time())
  return d - CATCHUP_DAYS, d - 1
end

local function catchUpNext(c)
  if catchUp ~= c then return end
  if not partnerOnline then catchUp = nil; return end
  if sending or #queue > 0 then C_Timer.After(CATCHUP_POLL, function() catchUpNext(c) end); return end
  c.i = c.i + 1
  local job = c.days[c.i]
  if not job then
    catchUp = nil
    ns:Debug("Sync: price history catch-up sent.")
    return
  end
  local payload, items = { k = "hd", d = job.day, left = #c.days - c.i, m = {} }, 0
  for _, market in ipairs(job.markets) do
    local packed, n = ns:PackHistoryDay(market, job.day)
    if n > 0 then payload.m[market], items = packed, items + n end
  end
  if items > 0 then
    local msgs = send(payload, partner())
    ns:Debug(("Sync: sending one day of price history, %d items in %d messages (%d days to go)."):format(items, msgs, payload.left))
  end
  C_Timer.After(CATCHUP_POLL, function() catchUpNext(c) end)
end

-- theirs: the partner's counts from its hello, { [market] = { [day] = items } }.
local function startCatchUp(theirs)
  if type(theirs) ~= "table" then return end
  local from, to = lastDays()
  local mine = ns:HistoryDayCounts(from, to)
  local days = {}
  for day = from, to do
    local markets = {}
    for market, counts in pairs(mine) do
      local t = type(theirs[market]) == "table" and theirs[market] or {}
      if (counts[day] or 0) > (tonumber(t[day]) or 0) then markets[#markets + 1] = market end
    end
    if #markets > 0 then
      table.sort(markets)
      days[#days + 1] = { day = day, markets = markets }
    end
  end
  catchUp = #days > 0 and { days = days, i = 0 } or nil
  if catchUp then
    ns:Debug(("Sync: %s is missing price history for %d days; sending them in the background."):format(partner(), #days))
    local c = catchUp
    C_Timer.After(CATCHUP_POLL, function() catchUpNext(c) end)
  end
end

local function hello(reply)
  local from, to = lastDays()
  send({ k = "h", v = 1, books = 2, reply = reply or nil, from = ns.CharKey(), hc = ns:HistoryDayCounts(from, to) }, partner())
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function handle(payload, sender)
  if type(payload) ~= "table" then return end
  if test and sender == me() then
    test.got = test.got + 1
    test.chars, test.prices = count(payload.chars), countPrices(payload.prices)
    test.vendor = count(payload.vendorBuy) + count(payload.vendorSell)
    local secs = GetTime() - test.start
    ns:Print(("Sync test passed: %d characters, %d prices and %d vendor prices came back intact in %d messages, %.0f seconds."):format(
      test.chars, test.prices, test.vendor, test.sent, secs))
    test = nil
    return
  end
  if payload.k == "h" then
    local first = not partnerOnline
    partnerOnline = true
    partnerBooks = payload.books == 2   -- (2: says when they've arrived)
    if not payload.reply then hello(true) end
    if first then
      ns:Print(("Sync: connected to %s."):format(partner()))
      if ns.RefreshSettings then ns:RefreshSettings() end
    end
    ns:SyncSend(false)
    -- (a version from before November 8 sends no counts, and wouldn't read the days)
    if payload.hc then startCatchUp(payload.hc) end
  elseif payload.k == "hd" then
    partnerOnline = true
    local n = 0
    for market, packed in pairs(type(payload.m) == "table" and payload.m or {}) do
      n = n + ns:MergeHistoryDay(market, payload.d, packed)
    end
    ns:Debug(("Sync: received one day of price history from %s, %d items changed."):format(sender, n))
    historyGot = historyGot or { days = 0, items = 0 }
    if n > 0 then historyGot.days, historyGot.items = historyGot.days + 1, historyGot.items + n end
    if n > 0 and ns.InvalidateValues then ns:InvalidateValues() end
    if payload.left == 0 then
      if historyGot.days > 0 then
        ns:Print(("Sync: filled in %d %s of price history from %s."):format(historyGot.days, historyGot.days == 1 and "day" or "days", partner()))
        ns:RefreshUI()
      end
      historyGot = nil
    end
  elseif payload.k == "d" then
    partnerOnline = true
    -- Tagged with the partner's name, so /fl unpair can take it out again.
    local c, p, v, b, m = ns:MergeData(payload, partner())
    ns:Debug(("Sync: received %d characters, %d with bags, %d prices, %d vendor prices, %d sets of books from %s."):format(c, b, p, v, m, sender))
    if c + p + v + b + m > 0 then ns:RefreshUI() end
    if type(payload.books) == "table" and payload.books.to then send({ k = "a", books = payload.books.to }, partner()) end
  elseif payload.k == "a" then
    -- The partner has the books up to here.
    if booksSent and payload.books == booksSent.to then
      state().booksTo = booksSent.to
      booksSent = nil
      if booksChanged then ns:BooksChanged() end
    end
  end
end

ns:On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
  if prefix ~= PREFIX or channel ~= "WHISPER" then return end
  local name = shortName(Ambiguate and Ambiguate(sender, "none") or sender)
  local fromPartner = partner() and name:lower() == shortName(partner()):lower()
  local fromSelf = test and name == me()
  if not fromPartner and not fromSelf then return end

  local id, i, n, chunk = msg:match("^(%d+):(%d+):(%d+):(.*)$")
  i, n = tonumber(i), tonumber(n)
  if not id or not i or not n then return end
  local key = name .. id
  local r = incoming[key]
  if not r then r = { parts = {}, n = n, got = 0 }; incoming[key] = r end
  -- Timed from the last piece, not the first: a big send takes minutes (Codex review,
  -- November 5: 1,500 sales take almost 4, and were thrown away after 2).
  r.t = GetTime()
  if not r.parts[i] then r.parts[i] = chunk; r.got = r.got + 1 end
  if r.got < r.n then return end
  incoming[key] = nil
  local data, err = ns.Deserialize(table.concat(r.parts))
  if not data then ns:Debug("Sync: couldn't read a message from", name, err); return end
  handle(data, name)
end)

-- Forget half-received messages after a while.
C_Timer.NewTicker(30, function()
  local now = GetTime()
  for k, r in pairs(incoming) do
    if now - r.t > REASSEMBLE_TIMEOUT then incoming[k] = nil end
  end
end)

ns:OnReady(function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
end)
ns:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if (isLogin or isReload) and partner() then C_Timer.After(8, function() hello(false) end) end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
-- Paired characters are often one that plays and one that waits at the auction house, so
-- pairing offers quiet mode (owner, November 5). Settings has it too.
local function offerQuiet()
  if not ns.db.settings.quietWatch and StaticPopup_Show then ns:ShowPopup("FOREVER_LEDGER_BANK_CHAR") end
end

-- Gold and sales go only if you say the other character is yours: they name your buyers.
StaticPopupDialogs["FOREVER_LEDGER_SHARE_BOOKS"] = {
  text = "Is this your own account?\n\nForever Ledger can share your gold, sales and purchases with it, so both Dashboards and Ledgers show the same. These include your buyers' names, so only say yes if it's yours. You can change this later in Settings, Global settings, Advanced.",
  button1 = "Yes, share", button2 = "No",
  OnAccept = function()
    -- The yes was about one character: a link changed since then doesn't get it.
    local p = partner()
    if not (p and askedFor and p:lower() == askedFor:lower()) then return end
    ns.db.settings.syncMoney = true
    ns:BooksChanged()
    ns:Print("Your gold and sales will be shared with your sync partner.")
    offerQuiet()
  end,
  OnCancel = offerQuiet,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["FOREVER_LEDGER_BANK_CHAR"] = {
  text = "Is this your auction house character?\n\nForever Ledger can turn the game's sound off while the flip watch runs and play its chimes at full volume, even with the game in the background. You can change this later in Settings, Auction house, Alerts.",
  button1 = "Yes, turn it on", button2 = "No",
  OnAccept = function()
    ns.db.settings.quietWatch = true
    if ns.UpdateQuiet then ns:UpdateQuiet() end
    ns:Print("Quiet mode will come on while the flip watch runs.")
  end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

-- What goes to a partner was agreed for that partner, never for whoever is linked next
-- (Codex review, November 6: your own account, Unlink, then a friend, and the friend got
-- your buyers' names without being asked). Nothing already on its way goes on to them.
-- True if something was being shared.
local function endLink()
  local s = ns.db.settings
  local shared = s.syncMoney or s.syncBags
  s.syncMoney, s.syncBags = false, false
  queue, sending, booksSent, booksChanged, partnerBooks, partnerOnline = {}, false, nil, true, false, false
  askedFor, catchUp, historyGot = nil, nil, nil
  return shared
end

function ns:SyncCommand(args)
  local cmd, rest = (args or ""):match("^(%S*)%s*(.-)$")
  if cmd == "pair" then
    local name = titleCase(rest)
    if name == "" then ns:Print("Use /fl pair First Last, on both characters."); return end
    -- Whispers need the whole name, and addon whispers to yourself never arrive.
    if not name:find(" ", 1, true) then ns:Print("Use the character's first and last name."); return end
    if name:lower() == me():lower() then ns:Print("That's this character: link a character on your other account."); return end
    local old = partner()
    if not (old and old:lower() == name:lower()) then endLink() end
    ns.db.settings.syncPartner = name
    partnerOnline = false
    ns:Print(("Paired with %s. Do /fl pair %s on that character too. Syncing starts when both are online."):format(name, me()))
    hello(false)
    if not ns.db.settings.syncMoney and StaticPopup_Show then
      askedFor = name
      ns:ShowPopup("FOREVER_LEDGER_SHARE_BOOKS")
    else
      offerQuiet()
    end
  elseif cmd == "unpair" then
    local p = partner()
    ns.db.settings.syncPartner = nil
    local shared = endLink()
    if p then ns.db.sync[p:lower()] = nil end
    -- What came from them goes (their characters, bags and bank); prices stay.
    local n = p and ns:RemoveSyncedFrom(p) or 0
    ns:Print(n > 0 and ("Sync turned off. Removed %d %s from %s; the auction prices stay."):format(n, n == 1 and "character" or "characters", p)
      or "Sync turned off.")
    if shared then ns:Print("Sharing gold, sales, bags and bank is off too. Your next link starts fresh.") end
  elseif cmd == "test" then
    test = { start = GetTime(), sent = 0, got = 0 }
    local who, data = changes(0)
    data.chars = who.chars
    local n = send(data, me())
    ns:Print(("Sync test: sending %d characters, %d prices and %d vendor prices to yourself in %d messages. This takes about %d seconds."):format(
      count(data.chars), countPrices(data.prices), count(data.vendorBuy) + count(data.vendorSell), n, math.ceil(n * SEND_GAP)))
  elseif cmd == "ping" then
    -- Try "First Last", then "First Last-Server", and report which the game accepts.
    local name = titleCase(rest)
    if name == "" then ns:Print("Use /fl sync ping First Last, with someone who's online."); return end
    local realm = realmSuffix()
    local tries = { name, realm ~= "" and (name .. "-" .. realm) or nil }
    local results = {}
    local function try(i)
      local target = tries[i]
      if not target then
        local works = {}
        for j, r in ipairs(results) do if r then works[#works + 1] = j end end
        if #works == 0 then
          ns:Print(("Sync ping: neither form reached %s. Check they're online and the name is spelled exactly."):format(name))
        else
          ns.db.settings.syncAddRealm = works[1] == 2
          ns:Print(("Sync ping: whispers to \"%s\" work. Sync will use that form."):format(tries[works[1]]))
        end
        return
      end
      ping = { name = target }
      queue[#queue + 1] = { to = target, text = "0:1:1:" .. ns.Serialize({ k = "p" }) }
      if not sending then pump() end
      C_Timer.After(3, function()
        results[i] = not ping.failed
        ns:Print(("Sync ping: \"%s\" %s."):format(target, results[i] and "was accepted" or "got \"no player named\""))
        ping = nil
        try(i + 1)
      end)
    end
    ns:Print(("Sync ping: sending one hidden message to %s, in two forms, 3 seconds apart."):format(name))
    try(1)
  elseif cmd == "whoami" then
    local n1, r1 = UnitName("player")
    local fn, fr = UnitFullName and UnitFullName("player")
    local gn = GetUnitName and GetUnitName("player", true)
    ns:Print("How the game names this character:")
    print(("  UnitName: %s / %s"):format(tostring(n1), tostring(r1)))
    print(("  UnitFullName: %s / %s"):format(tostring(fn), tostring(fr)))
    print(("  GetUnitName with server: %s"):format(tostring(gn)))
    print(("  Server for whispers: %s"):format(realmSuffix()))
  elseif cmd == "now" then
    if not partner() then ns:Print("Pair first with /fl pair Charactername."); return end
    hello(false)
    C_Timer.After(3, function() ns:SyncSend(true) end)
    ns:Print("Sending everything to " .. partner() .. " if they're online.")
  else
    local p = partner()
    ns:Print(p and ("Paired with %s, %s. %d messages waiting to send."):format(p, partnerOnline and "online" or "not seen online yet", #queue)
      or "Not paired. Use /fl pair Charactername on both characters.")
    print("  /fl pair Name, /fl unpair, /fl sync now (send everything), /fl sync ping Name (check whispers reach someone online)")
  end
end

-- Who you're linked to and whether they're online, for the Settings page.
function ns:SyncInfo() return partner(), partnerOnline end

function ns:SyncStatus()
  local p = partner()
  if not p then return "not paired (/fl pair Name)" end
  return ("%s, %s"):format(p, partnerOnline and "online" or "not seen online yet")
end
