-- Sync.lua itself: messages between two clients, and the books' rules (Codex review,
-- November 5). Each test plays the partner by hand.
local T = ...
local ns = T.ns
local S = T.S

local PARTNER = "Regoril Bastiane"
local PREFIX = "FLedger1"
ns.RefreshUI = ns.RefreshUI or function() end

local sent
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.SendAddonMessage = function(_, text) sent[#sent + 1] = text; return true end

-- What the partner would read, whole messages in order.
local function read()
  T.runTimers()
  local parts, out = {}, {}
  for _, text in ipairs(sent) do
    local id, i, n, chunk = text:match("^(%d+):(%d+):(%d+):(.*)$")
    parts[id] = parts[id] or {}
    parts[id][tonumber(i)] = chunk
    if #parts[id] == tonumber(n) then out[#out + 1] = ns.Deserialize(table.concat(parts[id])) end
  end
  sent = {}
  return out
end

local counter = 0
local function deliver(payload)
  counter = counter + 1
  local text = ns.Serialize(payload)
  local n = math.ceil(#text / 200)
  for i = 1, n do
    T.fire("CHAT_MSG_ADDON", PREFIX, ("9%d:%d:%d:%s"):format(counter, i, n, text:sub((i - 1) * 200 + 1, i * 200)), "WHISPER", PARTNER)
  end
end

local function find(messages, key)
  for _, m in ipairs(messages) do
    if m[key] then return m end
  end
end

local function setup(share)
  sent = {}
  ns.db.settings.syncPartner = PARTNER
  ns.db.settings.syncMoney = share
  ns.db.sync = {}
  ns.db.chars[ns.CharKey()] = { name = "Tester", realm = "Testrealm", updated = S.now, profs = {} }
  ns.db.gold[ns.CharKey()] = { [100] = 5 }
  deliver({ k = "h", v = 1, books = 2, reply = true })
end

T.test("Gold and sales are off by default, and don't go until you say so", function()
  T.eq(ns.db.settings.syncMoney, false)
  setup(false)
  T.eq(find(read(), "books"), nil)
end)

T.test("Gold and sales go when on, and count as sent only once the partner says so", function()
  setup(true)
  local m = find(read(), "books")
  T.ok(m and type(m.books) == "table", "books sent")
  local st = ns.db.sync[PARTNER:lower()]
  T.eq(st.booksTo, nil, "not until the partner replies")
  deliver({ k = "a", books = m.books.to + 1 })
  T.eq(st.booksTo, nil, "a reply about something else")
  deliver({ k = "a", books = m.books.to })
  T.eq(st.booksTo, m.books.to)
end)

T.test("Received books get a reply", function()
  setup(true)
  read()
  local reply
  deliver({ k = "d", books = { from = 0, to = 777, chars = {} } })
  for _, x in ipairs(read()) do
    if x.k == "a" then reply = x end
  end
  T.ok(reply, "a reply")
  T.eq(reply.books, 777)
end)

T.test("A big message arrives however long it takes, while its pieces keep coming", function()
  setup(false)
  read()
  local prices = { ["Testrealm|Alliance"] = {} }
  for id = 1, 400 do prices["Testrealm|Alliance"][70000 + id] = { m = 5, q = 1, t = S.now, src = "scan" } end
  local text = ns.Serialize({ k = "d", prices = prices })
  local n = math.ceil(#text / 200)
  T.ok(n >= 40, "enough pieces")
  for i = 1, n do
    T.fire("CHAT_MSG_ADDON", PREFIX, ("5:%d:%d:%s"):format(i, n, text:sub((i - 1) * 200 + 1, i * 200)), "WHISPER", PARTNER)
    S.now = S.now + 10     -- well over the 2 minute limit in all
    for _, tick in ipairs(S.tickers) do tick() end
  end
  T.eq(ns.db.prices["Testrealm|Alliance"][70001].m, 5)
end)

T.test("A message that stops arriving is forgotten", function()
  setup(false)
  read()
  local text = ns.Serialize({ k = "d", prices = { Nowhere = { [1] = { m = 1, t = S.now } } } })
  local half = math.floor(#text / 2)
  T.fire("CHAT_MSG_ADDON", PREFIX, "6:1:2:" .. text:sub(1, half), "WHISPER", PARTNER)
  S.now = S.now + 200
  for _, tick in ipairs(S.tickers) do tick() end
  T.fire("CHAT_MSG_ADDON", PREFIX, "6:2:2:" .. text:sub(half + 1), "WHISPER", PARTNER)
  T.eq(ns.db.prices.Nowhere, nil)
end)

T.test("The sync chat filter doesn't look at hidden system text", function()
  local asked
  issecretvalue = function(v) asked = v; return true end
  local filter = S.chatFilters[1]
  T.ok(filter, "a filter")
  T.eq(filter(nil, nil, "hidden"), false)
  issecretvalue = nil
  T.eq(asked, "hidden")
end)

ns.db.settings.syncPartner = nil
