local _, ns = ...

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
local REASSEMBLE_TIMEOUT = 120

local queue, sending = {}, false
local incoming = {}          -- [sender .. id] = { parts, n, got, t }
local partnerOnline = false
local lastSentTo             -- when a message was last sent, for hiding "no player named" errors
local test                   -- running /fl sync test
local ping                   -- running /fl sync ping: { name, ok, failed }
local counter = 0

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
  if ping then
    ping.failed = true
  elseif test then
    ns:Print(("Sync test stopped: the game says there's no player named %s, so addon whispers to %s don't arrive."):format(
      me(), fullName(me())))
    test = nil
  elseif partnerOnline then
    partnerOnline = false
    ns:Print(("Sync: %s went offline."):format(partner()))
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
local function changes(since)
  local data = { k = "d", chars = {}, prices = {}, vendorBuy = {}, vendorSell = {} }
  local now = time()
  for key, c in pairs(ns.db.chars) do
    if (c.updated or 0) > since then data.chars[key] = c end
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
  return data, now
end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
local function countPrices(p) local n = 0; for _, items in pairs(p or {}) do n = n + count(items) end; return n end

function ns:SyncSend(full)
  local to = partner()
  if not to or not partnerOnline then return end
  local st = state()
  local data, now = changes(full and 0 or (st.sentUpTo or 0))
  if count(data.chars) + countPrices(data.prices) + count(data.vendorBuy) + count(data.vendorSell) == 0 then return end
  local n = send(data, to)
  -- If the partner goes offline before it all arrives, send it again next time.
  st.previous, st.sentUpTo = st.sentUpTo, now
  ns:Debug(("Sync: sending %d characters, %d prices, %d vendor prices to %s in %d messages."):format(
    count(data.chars), countPrices(data.prices), count(data.vendorBuy) + count(data.vendorSell), to, n))
end

-- Send changes a few seconds after the last one (scans save many prices in a row).
local soon
function ns:SyncSoon()
  if not partner() or not partnerOnline then return end
  if soon then soon:Cancel() end
  soon = C_Timer.NewTimer(DEBOUNCE, function() soon = nil; ns:SyncSend(false) end)
end

local function hello(reply)
  send({ k = "h", v = 1, reply = reply or nil, from = ns.CharKey() }, partner())
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
    if not payload.reply then hello(true) end
    if first then ns:Print(("Sync: connected to %s."):format(partner())) end
    ns:SyncSend(false)
  elseif payload.k == "d" then
    partnerOnline = true
    local c, p, v = ns:MergeData(payload)
    ns:Debug(("Sync: received %d characters, %d prices, %d vendor prices from %s."):format(c, p, v, sender))
    if c + p + v > 0 then ns:RefreshUI() end
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
  if not r then r = { parts = {}, n = n, got = 0, t = GetTime() }; incoming[key] = r end
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
function ns:SyncCommand(args)
  local cmd, rest = (args or ""):match("^(%S*)%s*(.-)$")
  if cmd == "pair" then
    local name = titleCase(rest)
    if name == "" then ns:Print("Use /fl pair First Last, on both characters."); return end
    ns.db.settings.syncPartner = name
    partnerOnline = false
    ns:Print(("Paired with %s. Do /fl pair %s on that character too. Syncing starts when both are online."):format(name, me()))
    hello(false)
  elseif cmd == "unpair" then
    ns.db.settings.syncPartner, partnerOnline = nil, false
    ns:Print("Sync turned off.")
  elseif cmd == "test" then
    test = { start = GetTime(), sent = 0, got = 0 }
    local data = changes(0)
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

function ns:SyncStatus()
  local p = partner()
  if not p then return "not paired (/fl pair Name)" end
  return ("%s, %s"):format(p, partnerOnline and "online" or "not seen online yet")
end
