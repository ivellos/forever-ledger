-- Training advice (TrainingPanel.lua ns:SpellAdvice, data in TrainerAdvice.lua): which
-- group a trainer spell goes in for a Mage, by its advice and the tree you level in.
local T = ...
local ns = T.ns

local function asTree(tree)
  local key = ns.CharKey()
  ns.db.chars[key] = ns.db.chars[key] or { name = "Tester" }
  ns.db.chars[key].levelTree = tree
end

T.test("The data covers the nine classes", function()
  local n = 0
  for _ in pairs(ns.TRAINER_ADVICE) do n = n + 1 end
  T.eq(n, 9)
  T.eq(ns.TRAINER_ADVICE.MAGE["Dampen Magic"].c, "skip")
end)

T.test("Everyone's spells are Train, skips are Skip", function()
  asTree("Frost")
  T.eq((ns:SpellAdvice("Polymorph")), "train")
  T.eq((ns:SpellAdvice("Dampen Magic")), "skip")
  T.eq((ns:SpellAdvice("Mage Armor")), "choice", "nice to have")
end)

T.test("Spec spells follow the tree you level in", function()
  asTree("Frost")
  T.eq((ns:SpellAdvice("Frostbolt")), "train")
  T.eq((ns:SpellAdvice("Fireball")), "skip", "a Fire spell for a Frost Mage")
  T.eq((ns:SpellAdvice("Arcane Explosion")), "train", "Frost AoE levelling uses it")
  asTree("Fire")
  T.eq((ns:SpellAdvice("Fireball")), "train")
end)

T.test("Spells not in the list are marked not reviewed", function()
  T.eq((ns:SpellAdvice("Felfire")), "unknown")
end)

T.test("Higher ranks follow the spell's rank rule", function()
  asTree("Frost")
  local key = ns.CharKey()
  ns.db.castsSince = { [key] = time() - 10 * 86400 }
  ns.db.casts = { [key] = { ["Frostbolt"] = time() - 9 * 86400, ["Blizzard"] = time() - 9 * 86400 } }
  T.eq((ns:SpellAdvice("Frostbolt", true)), "train", "keep current: always")
  T.eq((ns:SpellAdvice("Blizzard", true)), "choice", "upgrade if used: not cast for a week")
  ns.db.casts[key]["Blizzard"] = time() - 3600
  T.eq((ns:SpellAdvice("Blizzard", true)), "train", "cast an hour ago")
  T.eq((ns:SpellAdvice("Polymorph", true)), "choice", "learn once: you have it")
  T.eq((ns:SpellAdvice("Polymorph", false)), "train", "learn once: first rank")
  ns.db.castsSince, ns.db.casts = nil, nil
end)
