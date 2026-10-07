-- Training.lua: the riding fund (which riding, what it costs, when it shows) and what a
-- trainer read keeps.
local T = ...
local ns = T.ns

T.test("Riding fund: training and a mount, 100g at 40, before a trainer is seen", function()
  ns.db.settings.ridingFund = true
  ns.db.riding = {}
  local r = ns:RidingFund(250000, { days = 5 }, 200000)
  T.eq(r.training, 900000, "90g (beta)")
  T.eq(r.mount, 100000, "about 10g")
  T.eq(r.cost, 1000000)
  T.eq(r.level, 40)
  T.eq(r.seen, false)
  T.eq(r.perDay, 10000, "5g up over 5 days: 1g a day")
end)

T.test("Riding fund: the training cost seen at a riding trainer wins", function()
  ns.db.riding = { ["Apprentice Riding"] = { cost = 950000, level = 40 } }
  local r = ns:RidingFund(0)
  T.eq(r.training, 950000)
  T.eq(r.cost, 1050000, "plus the mount")
  T.eq(r.seen, true)
end)

T.test("Riding fund: off everywhere, or hidden on this character", function()
  ns.db.settings.ridingFund = false
  T.eq(ns:RidingFund(0), nil)
  ns.db.settings.ridingFund = true
  ns.db.chars[ns.CharKey()] = ns.db.chars[ns.CharKey()] or { name = "Tester" }
  ns.db.chars[ns.CharKey()].noRidingFund = true
  T.eq(ns:RidingFund(0), nil)
  ns.db.chars[ns.CharKey()].noRidingFund = nil
  T.ok(ns:RidingFund(0))
end)

T.test("A class trainer read keeps spells by name and rank, riding apart", function()
  ns.db.trainers, ns.db.riding = nil, nil
  -- (Forever's second value is the icon, not the rank: owner's /fl trainer, October 5.)
  ns:TrainerRead({
    { name = "Frostbolt", sub = 135846, state = "available", cost = 2000, level = 20 },
    { name = "Frostbolt", sub = 135846, state = "unavailable", cost = 5000, level = 26 },
    { name = "Dampen Magic", sub = 136006, state = "unavailable", cost = 4000, level = 24 },
    { name = "Apprentice Riding", sub = 0, state = "unavailable", cost = 900000, level = 40 },
  }, "Jennea Cannon", 1, nil)
  local _, class = UnitClass("player")
  local spells = ns.db.trainers[class or "?"].spells
  T.eq(spells["Frostbolt"][26], 5000)
  local ranks = ns:SpellRanks("Frostbolt")
  T.eq(#ranks, 2)
  T.eq(ranks[1].level, 20, "lowest level first")
  T.ok(spells["Dampen Magic"], "every class spell")
  T.eq(spells["Apprentice Riding"], nil, "riding kept apart")
  T.eq(ns.db.riding["Apprentice Riding"].cost, 900000)
end)

T.test("A profession trainer isn't read as a class trainer", function()
  ns.db.trainers = nil
  ns:TrainerRead({ { name = "Bolt of Linen Cloth", sub = "", state = "used", cost = 50, skill = "Tailoring" } }, "Sellandus", 2, "Tailoring")
  T.eq(ns.db.trainers, nil)
end)

-- Codex review, October 6: a trainer visit adds to what earlier visits saw.
T.test("A specialist trainer doesn't wipe earlier spells", function()
  ns.db.trainers = nil
  ns:TrainerRead({
    { name = "Frostbolt", state = "available", cost = 2000, level = 20 },
    { name = "Fireball", state = "unavailable", cost = 4000, level = 24 },
  }, "Jennea Cannon", 1, nil)
  ns:TrainerRead({ { name = "Teleport: Stormwind", state = "available", cost = 10000, level = 20 } }, "Portal trainer", 2, nil)
  T.eq(#ns:SpellRanks("Frostbolt"), 1, "Frostbolt kept")
  T.eq(#ns:SpellRanks("Fireball"), 1, "Fireball kept")
  T.eq(#ns:SpellRanks("Teleport: Stormwind"), 1, "teleport added")
end)

T.test("A level seen again updates its cost and keeps the other ranks", function()
  ns.db.trainers = nil
  ns:TrainerRead({
    { name = "Frostbolt", state = "available", cost = 2000, level = 20 },
    { name = "Frostbolt", state = "unavailable", cost = 5000, level = 26 },
  }, "Jennea Cannon", 1, nil)
  ns:TrainerRead({ { name = "Frostbolt", state = "available", cost = 1900, level = 20 } }, "Another trainer", 3, nil)
  local ranks = ns:SpellRanks("Frostbolt")
  T.eq(#ranks, 2, "both ranks kept")
  T.eq(ranks[1].cost, 1900, "cost updated")
  T.eq(ranks[2].cost, 5000)
end)

T.test("Talent positions fall in the right tree, even stray ones", function()
  -- From the saved layouts (October 6): Hunter's Bestial Wrath, Trueshot Aura,
  -- Counterattack, and Lightning Reflexes at a stray x of 102800 (a Survival talent).
  T.eq(ns.TalentThird(1620), 1); T.eq(ns.TalentThird(2820), 1)
  T.eq(ns.TalentThird(5020), 2); T.eq(ns.TalentThird(5620), 2); T.eq(ns.TalentThird(6820), 2)
  T.eq(ns.TalentThird(9080), 3); T.eq(ns.TalentThird(10880), 3)
  T.eq(ns.TalentThird(102800), 3, "stray position")
end)
T.test("Levelling help off: no riding fund, no levelling features", function()
  local real = UnitLevel
  UnitLevel = function() return 20 end
  T.ok(ns:LevellingOn(), "on below 60")
  ns.db.settings.moduleLevelling = false
  T.eq(ns:LevellingOn(), false, "module off")
  T.eq(ns:RidingFund(0), nil, "no riding fund with the module off")
  ns.db.settings.moduleLevelling = true
  UnitLevel = function() return 60 end
  T.eq(ns:LevellingOn(), false, "off at 60")
  UnitLevel = real
end)
T.test("The Levelling tab's list is well formed", function()
  for i, e in ipairs(ns.LEVELLING_START or {}) do
    T.ok(e.title and e.how and e.why and e.lvl and e.zone, "entry " .. i .. " complete")
    T.ok(e.service or (e.ids and #e.ids > 0), "entry " .. i .. " has items to price or is a service")
  end
  T.ok(#(ns.LEVELLING_START or {}) >= 10, "the list loaded")
end)