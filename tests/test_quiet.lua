-- Quiet mode (Quiet.lua): the game's sound settings go off, and come back as they were.
local T = ...
local ns = T.ns

local vars
local function reset()
  vars = { Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_EnableMusic = "1", Sound_EnableAmbience = "1",
    Sound_EnableDialog = "1", Sound_EnableSoundWhenGameIsInBG = "0", Sound_MasterVolume = "0.4" }
  GetCVar = function(name) return vars[name] end
  SetCVar = function(name, value) vars[name] = value end
  ns.db.quietSaved = nil
end

T.test("Quiet mode: only chimes left, at full volume, and everything comes back", function()
  reset()
  ns:ToggleQuiet()
  T.ok(ns:IsQuiet())
  T.eq(vars.Sound_EnableSFX, "0")
  T.eq(vars.Sound_EnableMusic, "0")
  T.eq(vars.Sound_EnableSoundWhenGameIsInBG, "1")
  T.eq(vars.Sound_MasterVolume, "1")
  ns:ToggleQuiet()
  T.ok(not ns:IsQuiet())
  T.eq(vars.Sound_EnableSFX, "1")
  T.eq(vars.Sound_EnableSoundWhenGameIsInBG, "0")
  T.eq(vars.Sound_MasterVolume, "0.4")
end)

T.test("Quiet mode: your settings are saved once, not over themselves", function()
  reset()
  ns:ToggleQuiet()
  ns:UpdateQuiet()
  ns:ToggleQuiet()
  T.eq(vars.Sound_MasterVolume, "0.4")
end)

T.test("Quiet mode: follows the flip watch only with the setting on", function()
  reset()
  local watching = ns.IsFlipWatching
  ns.IsFlipWatching = function() return true end
  ns.db.settings.quietWatch = false
  ns:UpdateQuiet()
  T.ok(not ns:IsQuiet())
  ns.db.settings.quietWatch = true
  ns:UpdateQuiet()
  T.ok(ns:IsQuiet())
  ns.IsFlipWatching = function() return false end
  ns:UpdateQuiet()
  T.ok(not ns:IsQuiet())
  ns.IsFlipWatching = watching
  ns.db.settings.quietWatch = false
end)
