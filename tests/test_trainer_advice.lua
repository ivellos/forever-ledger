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

T.test("A known spell not cast for a week becomes your choice", function()
  asTree("Frost")
  local key = ns.CharKey()
  ns.db.castsSince = { [key] = time() - 10 * 86400 }
  ns.db.casts = { [key] = { ["Frostbolt"] = time() - 9 * 86400 } }
  T.eq((ns:SpellAdvice("Frostbolt", true)), "choice")
  ns.db.casts[key]["Frostbolt"] = time() - 3600
  T.eq((ns:SpellAdvice("Frostbolt", true)), "train", "cast an hour ago")
  ns.db.castsSince, ns.db.casts = nil, nil
end)
