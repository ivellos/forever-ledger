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
  ns.db.quietChars = {}
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

-- Codex review, November 5.
T.test("Quiet mode: a sound setting you change meanwhile stays yours", function()
  reset()
  ns:ToggleQuiet()
  vars.Sound_MasterVolume = "0.2"
  vars.Sound_EnableMusic = "1"
  ns:ToggleQuiet()
  T.eq(vars.Sound_MasterVolume, "0.2")
  T.eq(vars.Sound_EnableMusic, "1")
  T.eq(vars.Sound_EnableSFX, "1", "the rest come back")
end)

T.test("Quiet mode: /fl quiet turns it off during the flip watch, until the next watch", function()
  reset()
  local watching = ns.IsFlipWatching
  ns.IsFlipWatching = function() return true end
  ns.db.settings.quietWatch = true
  ns:UpdateQuiet()
  T.ok(ns:IsQuiet())
  ns:ToggleQuiet()
  T.ok(not ns:IsQuiet(), "off by hand")
  ns:UpdateQuiet()
  T.ok(not ns:IsQuiet(), "stays off while this watch runs")
  ns.IsFlipWatching = function() return false end
  ns:UpdateQuiet()
  ns.IsFlipWatching = function() return true end
  ns:UpdateQuiet()
  T.ok(ns:IsQuiet(), "on again with the next watch")
  ns.IsFlipWatching = function() return false end
  ns:UpdateQuiet()
  ns.IsFlipWatching = watching
  ns.db.settings.quietWatch = false
end)

T.test("Quiet mode: winning an auction chimes, once per 2 seconds, only while quiet", function()
  reset()
  local S = T.S
  local now = S.now
  wipe(S.sounds)
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(#S.sounds, 0, "not when quiet mode is off")
  ns:ToggleQuiet()
  S.now = S.now + 10
  T.fire("COMMODITY_PURCHASE_SUCCEEDED")
  T.eq(#S.sounds, 1, "commodity bought")
  T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 555)
  T.eq(#S.sounds, 1, "not twice in a row")
  S.now = S.now + 3
  T.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 555)
  T.eq(#S.sounds, 2, "item bought")
  ns:ToggleQuiet()
  S.now = now
end)

-- Owner, November 8: "keep it toggled on after reloads on my alt".
T.test("Quiet mode: stays on for the character after a reload, until turned off", function()
  reset()
  ns:ToggleQuiet()
  T.eq(ns.db.quietChars[ns.CharKey()], true, "remembered for this character")
  T.fire("PLAYER_LOGOUT")
  T.ok(not ns:IsQuiet(), "the sound settings go back at logout, so the game never saves them muted")
  T.eq(vars.Sound_EnableSFX, "1")
  ns:UpdateQuiet()   -- (what loading does)
  T.ok(ns:IsQuiet(), "on again once loaded")
  T.eq(vars.Sound_EnableSFX, "0")
  ns:ToggleQuiet()
  T.eq(ns.db.quietChars[ns.CharKey()], nil, "turned off for good")
  T.fire("PLAYER_LOGOUT")
  ns:UpdateQuiet()
  T.ok(not ns:IsQuiet(), "stays off after a reload")
  T.eq(vars.Sound_MasterVolume, "0.4")
end)

T.test("Quiet mode: another character on the account isn't made quiet", function()
  reset()
  ns.db.quietChars["Someone Else-Testrealm"] = true
  ns:UpdateQuiet()
  T.ok(not ns:IsQuiet())
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
