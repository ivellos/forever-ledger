-- Just enough of the WoW API for the addon's files to load in plain Lua 5.1, and for
-- the tested functions to run. Anything the game would draw is a dummy whose methods
-- do nothing. Values tests depend on are set explicitly (realm, faction, money, time).
local S = {}

-- A frame, texture or font string: every method does nothing and returns nil, except
-- the ones that create more objects, which return another dummy. Scripts and events
-- are remembered so the runner can fire ADDON_LOADED.
local frames = {}
S.frames = frames
local function dummy()
  local o = { scripts = {}, events = {} }
  local mt = {}
  mt.__index = function(_, k)
    if k:find("^Create") or k:find("^Get%u%l*Frame") or k == "GetFontString" then
      return function() return dummy() end
    end
    return function() end
  end
  setmetatable(o, mt)
  o.SetScript = function(self, name, fn) self.scripts[name] = fn end
  o.HookScript = function(self, name, fn) self.scripts[name] = self.scripts[name] or fn end
  o.GetScript = function(self, name) return self.scripts[name] end
  o.RegisterEvent = function(self, ev) self.events[ev] = true end
  o.RegisterUnitEvent = o.RegisterEvent
  o.IsShown = function() return false end
  o.IsVisible = function() return false end
  o.GetWidth = function() return 600 end
  o.GetHeight = function() return 400 end
  o.GetFrameLevel = function() return 1 end
  o.GetName = function() return nil end
  return o
end
S.dummy = dummy

function CreateFrame()
  local f = dummy()
  frames[#frames + 1] = f
  return f
end
UIParent, GameTooltip, WorldFrame, Minimap = dummy(), dummy(), dummy(), dummy()

-- The world the tests run in.
S.now = 1790000000            -- a fixed "now" (2026), so ages and days don't drift
S.money = 0
local realTime = os.time
time = function(t) if t then return realTime(t) end return S.now end
date = os.date
GetTime = function() return S.now % 100000 end
debugprofilestop = function() return os.clock() * 1000 end
GetRealmName = function() return "Testrealm" end
UnitFactionGroup = function() return "Alliance" end
UnitName = function() return "Tester" end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 60 end
UnitExists = function() return false end
GetMoney = function() return S.money end
GetLocale = function() return "enUS" end
InCombatLockdown = function() return false end
IsLoggedIn = function() return false end

-- Timers run never on their own (the tests don't wait); tickers can be cancelled.
C_Timer = {
  After = function() end,
  NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function() return { Cancel = function() end } end,
}

-- hooksecurefunc(table, "name", fn) or hooksecurefunc("name", fn): call fn after.
function hooksecurefunc(a, b, c)
  local t, name, fn = a, b, c
  if type(a) == "string" then t, name, fn = _G, a, b end
  local orig = t[name]
  if type(orig) ~= "function" then return end
  t[name] = function(...)
    local r = { orig(...) }
    fn(...)
    return unpack(r)
  end
end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
function strsplit(sep, s)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
  return unpack(out)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
-- Errors the game would only show in its error frame (an OnReady callback of a file
-- the tests don't load): noted, not fatal.
S.errors = {}
geterrorhandler = function() return function(err) S.errors[#S.errors + 1] = tostring(err) end end

StaticPopupDialogs, UISpecialFrames, SlashCmdList = {}, {}, {}
SOUNDKIT = {}
Enum = {}
RAID_CLASS_COLORS = {}

return S
