-- Writs.lua: Craftsman's Writs (Frank, November 16): the order a writ item is, and what
-- filling it costs per point of reputation.
local T = ...
local ns, S = T.ns, T.S

T.test("Writs: 150 orders, each with a profession, tier and item", function()
  T.eq(#ns.WRITS, 150)
  local per = {}
  for _, e in ipairs(ns.WRITS) do
    T.ok(e.item and e.prof and ns.WRIT_TIERS[e.tier], "order " .. e.n)
    per[e.prof] = (per[e.prof] or 0) + 1
  end
  for _, p in ipairs({ "Alchemy", "Blacksmithing", "Engineering", "Leatherworking", "Tailoring" }) do T.eq(per[p], 30, p) end
end)

T.test("Writs: a writ item is found by its ID, its name, or its sealed tier", function()
  local e = ns:WritFor(264012)
  T.eq(e.item, 3383, "Elixir of Wisdom by the writ's ID")
  ns.db.itemNames[3391] = "Elixir of Ogre Strength"
  ns.db.itemNames[999001] = "Craftsman's Writ: Elixir of Ogre Strength"
  local ogre = ns:WritFor(999001)
  T.ok(ogre, "by name, for a writ whose ID isn't known")
  T.eq(ogre and ogre.item, 3391)
  local _, tier = ns:WritFor(262889)
  T.eq(tier.label, "Expert")
  ns.db.itemNames[999002] = "Sealed Artisan's Writ"
  _, tier = ns:WritFor(999002)
  T.eq(tier and tier.label, "Artisan")
  T.eq(ns:WritFor(2589), nil, "linen cloth is no writ")
end)

T.test("Writs: an order's cost from the auction house", function()
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][3383] = { m = 900, a = 900, q = 5, l = "900:5", t = S.now }
  local c = ns:WritCost(ns:WritFor(264012))
  T.ok(c, "priced from the auction house")
  T.eq(c and c.total, 900)
  T.eq(c and c.plan[3383].bought, 1)
end)

T.test("Writs: yours from the bags, and onto the Writs shopping list", function()
  ns.db.inventory = ns.db.inventory or {}
  ns.db.inventory[ns.CharKey()] = { bags = { [264012] = 1, [262888] = 2, [2589] = 20 }, bank = {} }
  local orders, sealed = ns:YourWrits()
  local wisdom = ns:WritFor(264012)
  T.eq(orders[wisdom], 1)
  T.eq(sealed.J, 2, "two sealed Journeyman's writs")
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][3383] = { m = 900, a = 900, q = 5, l = "900:2,950:5", t = S.now }
  local list = ns:WritsToShoppingList({ wisdom })
  T.eq(list.name, "Writs")
  T.eq(#list.items, 1)
  T.eq(list.items[1].id, 3383); T.eq(list.items[1].qty, 1); T.eq(list.items[1].max, 900)
  -- The same order again: still one item, not two.
  ns:WritsToShoppingList({ wisdom })
  T.eq(#list.items, 1)
  T.eq(list.items[1].qty, 1)
  ns.db.inventory[ns.CharKey()] = nil
end)

T.test("Writs: an order whose writ you don't have puts the writ on the list too", function()
  -- (Frank, November 23: the writs had to be searched for separately.)
  ns.db.inventory = ns.db.inventory or {}
  ns.db.inventory[ns.CharKey()] = { bags = {}, bank = {} }
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][3385] = { m = 500, a = 500, q = 5, l = "500:5", t = S.now }
  local mana = ns:WritFor(264013)
  local list = ns:WritsToShoppingList({ mana })
  local got = {}
  for _, it in ipairs(list.items) do got[it.id] = it end
  T.ok(got[3385], "the item")
  T.ok(got[264013], "and its writ")
  T.eq(got[264013] and got[264013].qty, 1)
  T.eq(got[264013] and got[264013].src, "usual", "up to the usual price")
  -- Once you have the writ, listing again leaves it off.
  ns.db.inventory[ns.CharKey()].bags[264013] = 1
  ns:WritsToShoppingList({ mana })
  got = {}
  for _, it in ipairs(list.items) do got[it.id] = it end
  T.eq(got[264013], nil)
  ns.db.inventory[ns.CharKey()] = nil
end)

T.test("Writs: zones without the guides' question mark, each once", function()
  local zones, seen = ns.WritZones(), {}
  for _, z in ipairs(zones) do
    T.ok(not z:find("?", 1, true), z)
    T.ok(not seen[z], "once: " .. z); seen[z] = true
  end
  T.ok(seen["Felwood"] and seen["Wetlands"])
  T.eq(ns.WritZoneOf({ zone = "Feralas?" }), "Feralas")
  T.eq(ns.WritZoneOf({}), nil)
end)

T.test("Crates: level and kind by item number, or from a later crate's name", function()
  local l, k = ns.CrateKind(248709)
  T.eq(l, 3); T.eq(k, "Ingots")
  l, k = ns.CrateKind(248691)
  T.eq(l, 3); T.eq(k, "Herbs", "Flowering herbs are Herbs")
  l, k = ns.CrateKind(999999, "Waylaid Crate: Journeyman Parts")
  T.eq(l, 2); T.eq(k, "Parts")
end)

T.test("Writs: a sealed writ's average is worked out in the background, then kept", function()
  -- (Frank's AN30, November 17: all of a tier's orders at once froze a hover for half a second.)
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][3383] = { m = 900, a = 900, q = 5, l = "900:5", t = S.now }
  local first = ns.WritTierAverage("J")
  T.runTimers()
  local a = ns.WritTierAverage("J")
  T.ok(a and a.avg and a.avg > 0, "ready once its timers ran")
  T.ok(first == nil or first == a, "not all at once in the tooltip (or already kept)")
  T.eq(ns.WritTierAverage("J"), a, "kept: not worked out again")
  T.eq(#S.timers, 0, "and nothing started again")
  local lines = ns:WritTooltipLines(262888)
  T.ok(lines and lines[1]:find("on average", 1, true), "the sealed writ's line has it")
end)

T.test("Writs: the view's costs are worked out over several frames, then kept", function()
  -- (Frank's thirteenth /fl perf, November 21: opening the Writs view took 967 ms.)
  local W = ns._writsTest
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][3383] = { m = 900, a = 900, q = 5, l = "900:5", t = S.now }
  local e = ns:WritFor(264012)
  W.forget()
  local realClock, ms = debugprofilestop, 0
  local finished = 0
  local ok, err = pcall(function()
    debugprofilestop = function() ms = ms + 1; return ms end   -- (each look at the clock: 1 ms)
    W.refreshCosts(ns.WRITS, function() finished = finished + 1 end)
    local known = 0
    for _, w in ipairs(ns.WRITS) do if W.knownCost(w) ~= nil then known = known + 1 end end
    T.ok(known < #ns.WRITS, "not all in the first frame: " .. known)
    T.runTimers()
    T.eq(finished, 1, "the view is told once they're all in")
    for _, w in ipairs(ns.WRITS) do T.ok(W.knownCost(w) ~= nil, "every order worked out") end
    T.eq(W.knownCost(e) and W.knownCost(e).total, 900, "the same cost as asked for on its own")
    W.refreshCosts(ns.WRITS, function() finished = finished + 1 end)
    T.runTimers()
    T.eq(finished, 1, "kept: nothing worked out again")
  end)
  debugprofilestop = realClock
  T.runTimers()
  assert(ok, err)
end)

-- Codex review, November 21: with some orders priced and some not, the redraw after the
-- costs came in compared "no price" (false) with a number and stopped with an error.
T.test("Writs: the view redraws with priced and unpriced orders, sorted per rep", function()
  local W = ns._writsTest
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][3383] = { m = 900, a = 900, q = 5, l = "900:5", t = S.now }
  local realSettings, realRefresh, realClock = ns.db.settings.writs, ns.RefreshWrits, debugprofilestop
  local errorsBefore, redraws, ms = #S.errors, 0, 0
  local ok, err = pcall(function()
    ns.db.settings.writs = nil   -- (the usual: sorted by cost per rep)
    if not W.frame() then ns:BuildWrits(S.dummy()) end
    local F = W.frame()
    F.IsShown = function() return true end
    F.IsVisible = function() return true end
    ns.RefreshWrits = function(...) redraws = redraws + 1; return realRefresh(...) end
    W.forget()
    debugprofilestop = function() ms = ms + 1; return ms end   -- (each look at the clock: 1 ms)
    ns:RefreshWrits()
    T.runTimers()
    T.eq(redraws, 2, "drawn, then drawn again once the costs were in")
    T.eq(#S.errors, errorsBefore, "no error: " .. tostring(S.errors[#S.errors]))
    T.eq(W.knownCost(ns:WritFor(264012)) and W.knownCost(ns:WritFor(264012)).total, 900)
    -- Left for another view: its parent is hidden, this frame still says shown.
    F.IsVisible = function() return false end
    W.forget()
    realRefresh(ns)
    T.runTimers()
    T.eq(redraws, 2, "a hidden view isn't drawn again")
  end)
  local F = W.frame()
  if F then F.IsShown = function() return false end; F.IsVisible = function() return false end end
  ns.db.settings.writs, ns.RefreshWrits, debugprofilestop = realSettings, realRefresh, realClock
  T.runTimers()
  assert(ok, err)
end)

-- Codex review, November 21: the background work put its old 900c back over the 1800c a
-- hover had just worked out (the kept costs being out of date), and it was then kept.
T.test("Writs: a cost worked out meanwhile isn't overwritten by the background's older one", function()
  local W = ns._writsTest
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][3383] = { m = 900, a = 900, q = 5, l = "900:5", t = S.now }
  if ns.InvalidateValues then ns:InvalidateValues(true) end
  local e = ns:WritFor(264012)
  local list = { e }
  for _, w in ipairs(ns.WRITS) do if w ~= e and #list < 3 then list[#list + 1] = w end end
  local realClock, realPlan, ms = debugprofilestop, ns.CraftPlan, 0
  local ok, err = pcall(function()
    debugprofilestop = function() return ms end
    -- (Each order's plan takes 10 ms: the work gives the frame back after the first.)
    ns.CraftPlan = function(...) local a, b = realPlan(...); ms = ms + 10; return a, b end
    W.forget()   -- (out of date)
    W.refreshCosts(list, nil)
    T.eq(W.knownCost(e), nil, "not merged yet")
    ns.db.prices[key][3383] = { m = 1800, a = 1800, q = 5, l = "1800:5", t = S.now }
    if ns.InvalidateValues then ns:InvalidateValues(true) end
    local hover = ns:WritCost(e)   -- (a hover: clears the out-of-date costs, works it out again)
    T.eq(hover and hover.total, 1800)
    T.runTimers()
    T.eq(W.knownCost(e) and W.knownCost(e).total, 1800, "the hover's newer cost stays")
    T.eq(ns:WritCost(e) and ns:WritCost(e).total, 1800)
  end)
  debugprofilestop, ns.CraftPlan = realClock, realPlan
  ns.db.prices[key][3383] = { m = 900, a = 900, q = 5, l = "900:5", t = S.now }
  if ns.InvalidateValues then ns:InvalidateValues(true) end
  W.forget()
  T.runTimers()
  assert(ok, err)
end)

T.test("Writs: per reputation is the cost divided by the reputation, the pouch not counted", function()
  T.eq(ns.WritPerRep(7500, "J"), 100, "7500 / 75")
  T.eq(ns.WritPerRep(1000, "J", 100), 10, "the order's own reputation, once learned")
  T.eq(ns.WritPerRep(nil, "J"), nil)
end)

T.test("Writs: the reputation chat line gives its number", function()
  local was = FACTION_STANDING_INCREASED
  FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."
  T.eq(ns.WritRepFromChat("Reputation with Azeroth Commerce Authority increased by 125."), 125)
  T.eq(ns.WritRepFromChat("You have gained 5 Merchant's Favor."), nil)
  FACTION_STANDING_INCREASED = was
end)

-- Frank, November 24: an order's amount, customer and reputation are learned from its quest,
-- and what a coin pouch paid from opening it.
T.test("Writs: learned from the quest, the turn-in and the coin pouch", function()
  local e = ns:WritFor(264014)
  T.eq(e and e.quest, 94214, "the writ's quest, from the game data")
  local saved = { qty = e.qty, who = e.who, zone = e.zone, rep = e.rep, seen = e.seen }
  local was = { C_QuestLog = C_QuestLog, C_Map = C_Map, GetQuestID = GetQuestID, F = FACTION_STANDING_INCREASED }
  local ok, err = pcall(function()
    C_QuestLog = { IsOnQuest = function(q) return q == 94214 end,
      GetQuestObjectives = function() return { { type = "item", numRequired = 3 } } end }
    ns.WritReadLog()   -- (what QUEST_LOG_UPDATE does a second later)
    T.eq(e.qty, 3, "the amount the quest asks for")
    T.eq(ns.db.writSeen[94214].qty, 3)
    -- The turn-in: who, where, and the reputation from the chat line.
    C_Map = { GetBestMapForUnit = function() return 1431 end, GetMapInfo = function() return { name = "Duskwood" } end }
    GetQuestID = function() return 94214 end
    FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."
    S.money = 10000
    T.fire("PLAYER_MONEY")
    T.fire("BAG_UPDATE_DELAYED")
    T.fire("QUEST_COMPLETE")
    T.fire("QUEST_TURNED_IN", 94214, 0, 0)
    T.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Azeroth Commerce Authority increased by 80.")
    T.eq(e.who, "Tester", "the customer")
    T.eq(e.zone, "Duskwood")
    T.eq(ns.WritRep(e), 80, "the reputation it gave")
    -- A coin pouch turns up: it came from a Journeyman order. Opened: it paid 45s.
    S.bags[284583] = 1
    T.fire("BAG_UPDATE_DELAYED")
    T.eq(ns.db.pouches[284583] and ns.db.pouches[284583].from, "J")
    T.eq(ns:PouchText("J"), nil, "none opened yet")
    S.bags[284583] = 0
    T.fire("BAG_UPDATE_DELAYED")
    S.money = 14500
    T.fire("PLAYER_MONEY")
    T.eq(ns.db.pouches[284583].n, 1)
    T.eq(ns.db.pouches[284583].sum, 4500)
    T.eq(ns:PouchText("J"), ns.Money(4500) .. " (1 opened)")
    T.eq(ns:PouchText("E"), nil, "nothing for another tier")
  end)
  C_QuestLog, C_Map, GetQuestID, FACTION_STANDING_INCREASED = was.C_QuestLog, was.C_Map, was.GetQuestID, was.F
  ns.db.writSeen[94214] = nil
  ns.db.pouches[284583] = nil
  S.bags[284583] = nil
  e.qty, e.who, e.zone, e.rep, e.seen = saved.qty, saved.who, saved.zone, saved.rep, saved.seen
  assert(ok, err)
end)
