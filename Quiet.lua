local _, ns = ...

---------------------------------------------------------------------------
-- Quiet mode (owner, November 5): music, effects, ambience and voices off, so only
-- sounds played on the Master channel get through (the flip chime and the addon's other
-- alerts), at full volume and with the game in the background. Addons can't tell when
-- the game loses focus, so it's by hand (/fl quiet) or while the flip watch runs
-- (settings.quietWatch). The player's own sound settings are kept in quietSaved and put
-- back afterward, and at the next login if the game closed before that.
-- /fl quiet is a lasting choice for the character it's typed on (owner, November 8:
-- "keep it toggled on after reloads on my alt"), in quietChars[charKey]. The sound
-- settings still go back at every logout and reload and off again once loaded, so the
-- game never saves them muted: they're shared by every account on this computer.
---------------------------------------------------------------------------
local MUTED = {
  Sound_EnableAllSound = "1",
  Sound_EnableSFX = "0",
  Sound_EnableMusic = "0",
  Sound_EnableAmbience = "0",
  Sound_EnableDialog = "0",
  Sound_EnableSoundWhenGameIsInBG = "1",
  Sound_MasterVolume = "1",
}
local offByHand = false   -- /fl quiet turned it off while the flip watch had it on

-- Quiet mode turned on with /fl quiet on this character.
local function onHere()
  return ns.db.quietChars ~= nil and ns.db.quietChars[ns.CharKey()] == true
end

local function getVar(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
  return GetCVar and GetCVar(name)
end

local function setVar(name, value)
  if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar(name, value)
  elseif SetCVar then SetCVar(name, value) end
end

local function mute()
  if ns.db.quietSaved then return end
  local saved = {}
  for name, value in pairs(MUTED) do
    saved[name] = getVar(name)
    setVar(name, value)
  end
  ns.db.quietSaved = saved
end

-- Numbers can come back as "1" or "1.0".
local function sameValue(a, b)
  return a == b or (tonumber(a) ~= nil and tonumber(a) == tonumber(b))
end

-- Only what's still as quiet mode left it: a sound setting you changed since stays yours
-- (Codex review, November 5).
local function restore()
  local saved = ns.db.quietSaved
  if not saved then return end
  for name, value in pairs(saved) do
    if sameValue(getVar(name), MUTED[name]) then setVar(name, value) end
  end
  ns.db.quietSaved = nil
end

function ns:IsQuiet() return ns.db.quietSaved ~= nil end

-- On while you asked for it on this character, or while the flip watch runs with the
-- setting on, unless you turned it off during this watch.
function ns:UpdateQuiet()
  local auto = ns.db.settings.quietWatch and ns:IsFlipWatching()
  if not auto then offByHand = false end
  if onHere() or (auto and not offByHand) then mute() else restore() end
end

function ns:ToggleQuiet()
  local on = not ns:IsQuiet()
  ns.db.quietChars = ns.db.quietChars or {}
  ns.db.quietChars[ns.CharKey()] = on or nil
  offByHand = not on
  ns:UpdateQuiet()
  ns:Print(ns:IsQuiet() and "Quiet mode on for this character: game sound off, Forever Ledger's chimes at full volume. It stays on after a reload or logout; /fl quiet turns it off."
    or "Quiet mode off: your sound settings are back.")
end

-- Quiet mode turns the game's effects off, and the game's own sound for winning an
-- auction with them (owner, November 7: "include the chime when you win an auction").
-- So while quiet, a purchase plays a chime on the Master channel: from the Buy queue
-- or the game's own page. One per 2 seconds, so a run of Buy clicks doesn't stack them.
local lastChime
local function wonChime()
  if not (ns.db and ns:IsQuiet() and PlaySound) then return end
  local now = GetTime()
  if lastChime and now - lastChime < 2 and now >= lastChime then return end
  lastChime = now
  -- The coin purse (owner, November 7: the quest chime sounded like a level up).
  pcall(PlaySound, (SOUNDKIT and SOUNDKIT.MONEY_FRAME_OPEN) or 891, "Master")
end
ns:On("COMMODITY_PURCHASE_SUCCEEDED", wonChime)
ns:On("AUCTION_HOUSE_PURCHASE_COMPLETED", wonChime)

ns:On("PLAYER_LOGOUT", function()
  if ns.db then restore() end
end)
-- At login and after a reload: back on for a quiet character, else the sound settings
-- left by a game that closed while quiet go back.
ns:OnReady(function()
  ns:UpdateQuiet()
  -- Nothing else shows it's on, and it lasts for days (UI pass, November 9).
  if onHere() then ns:Print("Quiet mode is on for this character. /fl quiet turns it off.") end
end)
