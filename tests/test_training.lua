-- Training.lua: the riding fund (which riding, what it costs, when it shows) and what a
-- trainer read keeps.
local T = ...
local ns = T.ns

T.test("Riding fund: about 100g at 40 until a trainer has been seen", function()
  ns.db.settings.ridingFund = true
  ns.db.riding = {}
  local r = ns:RidingFund(250000, { days = 5 }, 200000)
  T.eq(r.cost, 1000000)
  T.eq(r.level, 40)
  T.eq(r.seen, false)
  T.eq(r.perDay, 10000, "5g up over 5 days: 1g a day")
end)

T.test("Riding fund: the cost seen at a riding trainer wins", function()
  ns.db.riding = { ["Apprentice Riding"] = { cost = 900000, level = 40 } }
  local r = ns:RidingFund(0)
  T.eq(r.cost, 900000)
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
  ns:TrainerRead({
    { name = "Frostbolt", sub = "Rank 2", state = "available", cost = 1000, level = 8 },
    { name = "Frostbolt", sub = "Rank 3", state = "unavailable", cost = 2000, level = 14 },
    { name = "Dampen Magic", sub = "Rank 1", state = "available", cost = 900, level = 12 },
    { name = "Apprentice Riding", sub = "", state = "unavailable", cost = 900000, level = 40 },
  }, "Jennea Cannon", 1, nil)
  local _, class = UnitClass("player")
  local spells = ns.db.trainers[class or "?"].spells
  T.eq(spells["Frostbolt"]["Rank 3"].level, 14)
  T.ok(spells["Dampen Magic"], "every class spell")
  T.eq(spells["Apprentice Riding"], nil, "riding kept apart")
  T.eq(ns.db.riding["Apprentice Riding"].cost, 900000)
end)

T.test("A profession trainer isn't read as a class trainer", function()
  ns.db.trainers = nil
  ns:TrainerRead({ { name = "Bolt of Linen Cloth", sub = "", state = "used", cost = 50, skill = "Tailoring" } }, "Sellandus", 2, "Tailoring")
  T.eq(ns.db.trainers, nil)
end)
