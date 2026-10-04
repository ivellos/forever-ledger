local _, ns = ...

---------------------------------------------------------------------------
-- New version notice (owner, October 4, like DungeonJournal's): addons can't go online,
-- so copies tell each other. Each released copy says its version to your guild, and to
-- your party or raid when you join one; a copy that hears a newer version says so in
-- chat, once a session. Dev builds ("dev") never send, so testers don't spread one.
-- Its own prefix, separate from live sync (Sync.lua). Settings, Other: updateNotice.
---------------------------------------------------------------------------
local PREFIX = "FLedgerVer"
local told = false          -- the notice is shown once a session
local lastSent = {}         -- [channel] = time, at most once a minute each

-- "0.11.0" -> 0, 11, 0; nil for anything else (dev builds).
local function parts(v)
  local a, b, c = tostring(v or ""):match("^v?(%d+)%.(%d+)%.(%d+)$")
  if a then return tonumber(a), tonumber(b), tonumber(c) end
end
local function newer(theirs, mine)
  local a1, b1, c1 = parts(theirs)
  local a2, b2, c2 = parts(mine)
  if not (a1 and a2) then return false end
  if a1 ~= a2 then return a1 > a2 end
  if b1 ~= b2 then return b1 > b2 end
  return c1 > c2
end

local function send(channel)
  if not (parts(ns.VERSION) and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  if lastSent[channel] and GetTime() - lastSent[channel] < 60 then return end
  lastSent[channel] = GetTime()
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, ns.VERSION, channel)
end

local function announce()
  if IsInGuild and IsInGuild() then send("GUILD") end
  if IsInRaid and IsInRaid() then send("RAID") elseif IsInGroup and IsInGroup() then send("PARTY") end
end

ns:On("CHAT_MSG_ADDON", function(prefix, msg)
  if prefix ~= PREFIX or told then return end
  if ns.db and ns.db.settings.updateNotice == false then return end
  local mine = ns.VERSION
  if not parts(mine) then return end   -- dev builds: you're ahead of any release
  if newer(msg, mine) then
    told = true
    ns:Print(("Version %s is available (you have %s). Update on CurseForge or Wago."):format(msg, mine))
  elseif newer(mine, msg) then
    -- They're behind: answer once, so they hear about it too.
    announce()
  end
end)

ns:OnReady(function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)
-- Say it after logging in (once the guild is known), and on joining a group.
ns:On("PLAYER_ENTERING_WORLD", function(isLogin) if isLogin then C_Timer.After(15, announce) end end)
ns:On("GROUP_JOINED", function() C_Timer.After(3, announce) end)
