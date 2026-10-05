-- Your auctions (Auctions.lua): reading the owned-auctions list, what sold while you
-- were away, undercut alerts, and deposits. Driven through the game's own events:
-- OWNED_AUCTIONS_UPDATED (the game's answer with your auctions in S.owned),
-- AUCTION_HOUSE_SHOW, PLAYER_ENTERING_WORLD and PLAYER_MONEY.
-- Confirmed in the game: an owned auction's buyout is per item; a sale's gold reaches
-- the mailbox about an hour later with the deposit back; the game drops a sold auction
-- from the list before its gold arrives.
local T = ...
local ns, S = T.ns, T.S
local ME = ns.CharKey()
local HOUR, DAY = 3600, 86400
local NOW = os.time({ year = 2026, month = 3, day = 15, hour = 12 })

-- An auction as GetOwnedAuctionInfo gives it.
local function auction(a, id, each, q, left, sold)
  return { auctionID = a, itemKey = { itemID = id }, quantity = q or 1, buyoutAmount = each,
    timeLeftSeconds = left or 2 * DAY, status = sold and 1 or 0 }
end

-- The game answers with this list of your auctions.
local function read(list)
  S.owned = list
  T.fire("OWNED_AUCTIONS_UPDATED")
end

local function mine() return ns.db.myAuctions[ME] end
local function entry(a)
  for _, e in ipairs(mine().list) do if e.a == a then return e end end
end

-- What the addon printed in chat while fn ran.
local function chat(fn)
  local out, real = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    out[#out + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(fn)
  print = real
  if not ok then error(err, 0) end
  return out
end
local function count(lines, text)
  local n = 0
  for _, l in ipairs(lines) do if l:find(text, 1, true) then n = n + 1 end end
  return n
end

-- A fresh start at the auction house (the list is only read there): no saved auctions,
-- nothing waiting on a first read after opening.
local function fresh()
  S.now = NOW
  T.fire("AUCTION_HOUSE_CLOSED")
  ns.db.myAuctions = {}
  T.fire("AUCTION_HOUSE_SHOW")
  read({})   -- (the first read after opening, with nothing saved to compare)
  ns.db.myAuctions = {}
  ns.db.prices[ns.MarketKey()] = {}
  wipe(S.sounds)
  local s = ns.db.settings
  s.soldSummary, s.undercutAlerts, s.undercutSound, s.ahCut = nil, true, true, 5
end

local function cheapest(id, copper) ns.db.prices[ns.MarketKey()][id] = { m = copper, a = copper, q = 10, t = S.now } end

---------------------------------------------------------------------------
-- Reading the list
---------------------------------------------------------------------------
T.test("A sold auction keeps the time it was first seen sold", function()
  fresh()
  read({ auction(1, 70001, 100, 1, HOUR, true) })
  S.now = NOW + 600
  read({ auction(1, 70001, 100, 1, HOUR, true) })
  T.eq(entry(1).soldAt, NOW)
end)

T.test("A sold auction gone from the list is kept a day as mailed", function()
  fresh()
  read({ auction(1, 70001, 100, 1, HOUR, true) })
  S.now = NOW + 60
  read({})
  T.ok(entry(1), "still listed")
  T.eq(entry(1).mailed, true)
  S.now = NOW + DAY + 1
  read({})
  T.eq(entry(1), nil, "gone a day after it sold")
end)

T.test("Gone unsold with plenty of time left: it sold while you were away", function()
  fresh()
  read({ auction(2, 70002, 100, 1, 2 * DAY) })
  S.now = NOW + HOUR
  read({})
  local e = entry(2)
  T.ok(e, "kept")
  T.eq(e.sold, true)
  T.eq(e.mailed, true)
  T.eq(e.soldAt, NOW + HOUR)
end)

T.test("Gone unsold with little time left: it may have expired, so not counted", function()
  fresh()
  read({ auction(3, 70003, 100, 1, 30 * 60) })
  S.now = NOW + HOUR
  read({})
  T.eq(entry(3), nil)
end)

---------------------------------------------------------------------------
-- What sold while you were away
---------------------------------------------------------------------------
T.test("Sold while away: one line on the first read after opening the auction house", function()
  fresh()
  S.items[70010] = { name = "Empty Vial" }
  read({ auction(10, 70010, 8, 10) })
  entry(10).dep = 50
  T.fire("AUCTION_HOUSE_SHOW")
  S.now = NOW + HOUR
  local said = chat(function() read({ auction(10, 70010, 8, 10, nil, true) }) end)
  T.eq(count(said, "Sold since you were last here"), 1)
  -- 10 at 8c = 80c, less the 5% cut = 76c, plus the 50c deposit back.
  T.eq(count(said, "Empty Vial x10"), 1)
  T.eq(count(said, "About " .. ns.Money(126)), 1, table.concat(said, " / "))
  said = chat(function() read({ auction(10, 70010, 8, 10, nil, true) }) end)
  T.eq(count(said, "Sold since"), 0, "not again until the auction house is opened again")
end)

T.test("Sold while away: only the newly sold ones", function()
  fresh()
  S.items[70011], S.items[70012] = { name = "Old Sale" }, { name = "New Sale" }
  read({ auction(11, 70011, 100, 1, nil, true), auction(12, 70012, 100, 1) })
  T.fire("AUCTION_HOUSE_SHOW")
  local said = chat(function() read({ auction(11, 70011, 100, 1, nil, true), auction(12, 70012, 100, 1, nil, true) }) end)
  T.eq(count(said, "New Sale x1"), 1)
  T.eq(count(said, "Old Sale"), 0)
end)

T.test("Sold while away: ones gone from the list with time left count", function()
  fresh()
  S.items[70013] = { name = "Gone Sale" }
  read({ auction(13, 70013, 100, 2, 2 * DAY) })
  S.now = NOW + HOUR
  T.fire("AUCTION_HOUSE_SHOW")
  local said = chat(function()
    read({})   -- an empty first answer is asked again (it can be the game not ready yet)
    read({})   -- a second one is believed
  end)
  T.eq(count(said, "Gone Sale x2"), 1)
end)

T.test("Sold while away: an empty first answer alone isn't taken as everything sold", function()
  fresh()
  S.items[70016] = { name = "Still Up" }
  read({ auction(16, 70016, 100, 1, 2 * DAY) })
  T.fire("AUCTION_HOUSE_SHOW")
  local said = chat(function()
    read({})
    read({ auction(16, 70016, 100, 1, 2 * DAY) })   -- the real answer
  end)
  T.eq(count(said, "Sold since"), 0)
  T.eq(entry(16).sold, nil)
end)

T.test("Sold while away: part of a stack bought counts", function()
  fresh()
  S.items[70017] = { name = "Strange Dust" }
  read({ auction(17, 70017, 100, 10) })
  T.fire("AUCTION_HOUSE_SHOW")
  local said = chat(function() read({ auction(17, 70017, 100, 7) }) end)
  T.eq(count(said, "Strange Dust x3"), 1, table.concat(said, " / "))
end)

T.test("Your auctions: not read while the auction house is closed", function()
  fresh()
  read({ auction(18, 70018, 100, 1, 2 * DAY) })
  T.fire("AUCTION_HOUSE_CLOSED")
  read({})   -- an answer away from the auction house
  T.ok(entry(18), "still there")
  T.eq(entry(18).sold, nil)
end)

T.test("Sold while away: nothing on the very first read (nothing to compare with)", function()
  fresh()
  T.fire("AUCTION_HOUSE_SHOW")
  local said = chat(function() read({ auction(14, 70014, 100, 1, nil, true) }) end)
  T.eq(count(said, "Sold since"), 0)
end)

T.test("Sold while away: nothing when the setting is off", function()
  fresh()
  ns.db.settings.soldSummary = false
  read({ auction(15, 70015, 100, 1) })
  T.fire("AUCTION_HOUSE_SHOW")
  local said = chat(function() read({ auction(15, 70015, 100, 1, nil, true) }) end)
  T.eq(count(said, "Sold since"), 0)
end)

---------------------------------------------------------------------------
-- Undercut alerts
---------------------------------------------------------------------------
local UP = { auction(20, 70020, 100, 5) }   -- 5 at 1s each

T.test("Undercut: one alert per item, price and quantity", function()
  fresh()
  cheapest(70020, 90)
  local said = chat(function() read(UP) end)
  T.eq(count(said, "Undercut:"), 1)
  T.eq(#S.sounds, 1, "with a sound")
  said = chat(function() read(UP) end)
  T.eq(count(said, "Undercut:"), 0, "not again at the same price")
  T.eq(#S.sounds, 1)
end)

T.test("Undercut: two of the same auction make one alert, another quantity its own", function()
  fresh()
  cheapest(70021, 90)
  local said = chat(function()
    read({ auction(21, 70021, 100, 5), auction(22, 70021, 100, 5), auction(23, 70021, 100, 2) })
  end)
  T.eq(count(said, "Undercut:"), 2)
end)

T.test("Undercut: again only when the cheapest drops further", function()
  fresh()
  cheapest(70020, 90)
  chat(function() read(UP) end)
  cheapest(70020, 80)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 1, "cheaper again")
  cheapest(70020, 85)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 0, "back up a little")
end)

T.test("Undercut: an empty or partial list doesn't make it forget", function()
  fresh()
  cheapest(70020, 90)
  cheapest(70024, 90)
  local both = { UP[1], auction(24, 70024, 100, 1) }
  T.eq(count(chat(function() read(both) end), "Undercut:"), 2)
  chat(function() read({}) end)                 -- right after a reload
  chat(function() read({ both[2] }) end)        -- part of the list
  T.eq(count(chat(function() read(both) end), "Undercut:"), 0)
end)

T.test("Undercut: alerts are remembered over a reload, reminded after a login", function()
  fresh()
  cheapest(70020, 90)
  chat(function() read(UP) end)
  T.fire("PLAYER_ENTERING_WORLD", false, true)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 0, "reload: not again")
  T.fire("PLAYER_ENTERING_WORLD", true, false)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 1, "login: a reminder")
end)

T.test("Undercut: an alert older than two days is forgotten", function()
  fresh()
  cheapest(70020, 90)
  chat(function() read(UP) end)
  S.now = NOW + DAY
  cheapest(70020, 90)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 0, "a day later")
  S.now = NOW + 2 * DAY + 1
  cheapest(70020, 90)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 1, "over two days later")
end)

T.test("Undercut: nothing when alerts are off", function()
  fresh()
  ns.db.settings.undercutAlerts = false
  cheapest(70020, 90)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 0)
  T.eq(#S.sounds, 0)
end)

T.test("Undercut: no sound when the sound is off", function()
  fresh()
  ns.db.settings.undercutSound = false
  cheapest(70020, 90)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 1)
  T.eq(#S.sounds, 0)
end)

T.test("Undercut: not when yours is the cheapest, or sold", function()
  fresh()
  cheapest(70020, 100)
  T.eq(count(chat(function() read(UP) end), "Undercut:"), 0, "the same price")
  cheapest(70020, 90)
  T.eq(count(chat(function() read({ auction(20, 70020, 100, 5, nil, true) }) end), "Undercut:"), 0, "sold")
end)

---------------------------------------------------------------------------
-- Deposits
---------------------------------------------------------------------------
-- Posting: the hooked game function, with the item it posts.
local function post(id)
  C_Item = { GetItemID = function(loc) return loc.id end }
  C_AuctionHouse.PostItem({ id = id }, 1, 1, 100)
  C_Item = nil
end

T.test("Deposit: the money a post took within 5 seconds goes to that item's next new auction", function()
  fresh()
  S.money = 100000
  read({ auction(30, 70030, 100, 1) })   -- one already up
  post(70030)
  S.money = 99950
  T.fire("PLAYER_MONEY")
  read({ auction(30, 70030, 100, 1), auction(31, 70030, 100, 1) })
  T.eq(entry(31).dep, 50, "the new one")
  T.eq(entry(30).dep, nil, "not the one already up")
  read({ auction(30, 70030, 100, 1), auction(31, 70030, 100, 1) })
  T.eq(entry(31).dep, 50, "kept on the next read")
end)

T.test("Deposit: a money change over 5 seconds after posting isn't a deposit", function()
  fresh()
  S.money = 100000
  post(70032)
  S.now = NOW + 6
  S.money = 99950
  T.fire("PLAYER_MONEY")
  read({ auction(32, 70032, 100, 1) })
  T.eq(entry(32).dep, nil)
end)

T.test("Deposit: no post, no deposit", function()
  fresh()
  S.money = 100000
  S.money = 99950
  T.fire("PLAYER_MONEY")
  read({ auction(33, 70033, 100, 1) })
  T.eq(entry(33).dep, nil)
end)

T.test("Deposit: the sale's gold counts it", function()
  fresh()
  S.items[70034] = { name = "Deposit Vial" }
  S.money = 100000
  read({})
  post(70034)
  S.money = 99960
  T.fire("PLAYER_MONEY")
  read({ auction(34, 70034, 8, 10) })
  T.fire("AUCTION_HOUSE_SHOW")
  local said = chat(function() read({ auction(34, 70034, 8, 10, nil, true) }) end)
  T.eq(count(said, "About " .. ns.Money(76 + 40)), 1, table.concat(said, " / "))
end)
