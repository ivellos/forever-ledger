local _, ns = ...

---------------------------------------------------------------------------
-- Quiet mode (owner, November 5): music, effects, ambience and voices off, so only
-- sounds played on the Master channel get through (the flip chime and the addon's other
-- alerts), at full volume and with the game in the background. Addons can't tell when
-- the game loses focus, so it's by hand (/fl quiet) or while the flip watch runs
-- (settings.quietWatch). The player's own sound settings are kept in quietSaved and put
-- back afterward, and at the next login if the game closed before that.
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
local byHand = false

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

local function restore()
  local saved = ns.db.quietSaved
  if not saved then return end
  for name, value in pairs(saved) do setVar(name, value) end
  ns.db.quietSaved = nil
end

function ns:IsQuiet() return ns.db.quietSaved ~= nil end

-- On while you asked for it, or while the flip watch runs with the setting on.
function ns:UpdateQuiet()
  if byHand or (ns.db.settings.quietWatch and ns:IsFlipWatching()) then mute() else restore() end
end

function ns:ToggleQuiet()
  byHand = not ns:IsQuiet()
  ns:UpdateQuiet()
  ns:Print(ns:IsQuiet() and "Quiet mode on: game sound off, Forever Ledger's chimes at full volume. /fl quiet turns it off."
    or "Quiet mode off: your sound settings are back.")
end

ns:On("PLAYER_LOGOUT", function()
  if ns.db then restore() end
end)
ns:OnReady(restore)
