-- Settings profiles (Core.lua ApplyCharSettings, ProfileOf, the schema 5 change and
-- PLAYER_LOGOUT; Settings.lua's profile functions through ns._test).
-- Global settings are account-wide on every profile; every other setting belongs to
-- the character's profile: "Default" is the shared table itself, any other profile is
-- ns.db.profiles[name], and a setting a profile has no value for reads its default.
local T = ...
local ns, S = T.ns, T.S
local P = ns._test
local ME = ns.CharKey()

-- Settings to test with, picked from the Settings pages: a per-character tick box whose
-- default is on, a per-character number, money box and choice, and a Global number.
local function pick(test)
  local keys = {}
  for k, d in pairs(P.DEFS) do if test(k, d) then keys[#keys + 1] = k end end
  table.sort(keys)
  return keys[1], P.DEFS[keys[1]]
end
local CHECK = pick(function(k, d) return ns.PER_CHAR_SETTINGS[k] and d.kind == "check" and ns.DEFAULT_SETTINGS[k] == true end)
local NUM, NUMD = pick(function(k, d) return ns.PER_CHAR_SETTINGS[k] and d.kind == "number" and d.min and d.max end)
local MONEY = pick(function(k, d) return ns.PER_CHAR_SETTINGS[k] and d.kind == "money" end)
local CHOICE, CHOICED = pick(function(k, d) return ns.PER_CHAR_SETTINGS[k] and d.kind == "choice" end)
local GLOBAL = "ahCut"

-- A fresh start on the Default profile, with no profiles.
local function fresh()
  T.resetDB()
  ns.db.profiles, ns.db.charProfile, ns.db.settingsAccount = {}, {}, nil
  ns.accountSettings = nil
  ns:ApplyCharSettings()
end

-- Quiet: the profile functions say what they did in chat.
local function quiet(fn, ...)
  local real = print
  print = function() end
  local r = { pcall(fn, ...) }
  print = real
  if not r[1] then error(r[2], 0) end
  return unpack(r, 2)
end

-- A login with this saved data (ADDON_LOADED, as the game sends it); hooks on game
-- functions are left out so nothing is hooked twice.
local function login(db)
  ForeverLedgerDB = db
  ns.accountSettings = nil
  local real = hooksecurefunc
  hooksecurefunc = function() end
  T.fire("ADDON_LOADED", "ForeverLedger")
  hooksecurefunc = real
end

T.test("The settings to test with were found", function()
  T.ok(CHECK and NUM and MONEY and CHOICE, "a check, number, money and choice setting in a profile")
  T.eq(ns.PER_CHAR_SETTINGS[GLOBAL], nil, "the auction house cut is a Global setting")
end)

---------------------------------------------------------------------------
-- Reading and writing
---------------------------------------------------------------------------
T.test("Default: the settings are the shared table itself", function()
  fresh()
  T.eq(ns:ProfileOf(), "Default")
  T.eq(ns.db.settings, ns.accountSettings)
  T.eq(getmetatable(ns.db.settings), nil)
end)

T.test("Global settings are shared on any profile, read and written", function()
  fresh()
  ns.db.settings[GLOBAL] = 7
  quiet(P.newProfile, "Alt")
  T.eq(ns.db.settings[GLOBAL], 7, "read from the shared table")
  ns.db.settings[GLOBAL] = 12
  T.eq(ns.accountSettings[GLOBAL], 12, "written to the shared table")
  T.eq(ns.db.profiles.Alt[GLOBAL], nil, "never in the profile")
  quiet(P.useProfile, "Default")
  T.eq(ns.db.settings[GLOBAL], 12, "Default sees it")
end)

T.test("Per-character settings are the profile's own", function()
  fresh()
  quiet(P.newProfile, "Alt")
  ns.db.settings[CHECK] = false
  T.eq(ns.db.profiles.Alt[CHECK], false, "written to the profile")
  T.eq(ns.accountSettings[CHECK], true, "Default's value unchanged")
  quiet(P.useProfile, "Default")
  T.eq(ns.db.settings[CHECK], true)
end)

T.test("A profile without a value reads the setting's default, not Default's value", function()
  fresh()
  ns.db.settings[CHECK] = false            -- Default's value
  ns.db.profiles.Alt = {}                  -- a profile with nothing in it
  quiet(P.useProfile, "Alt")
  T.eq(ns.db.settings[CHECK], ns.DEFAULT_SETTINGS[CHECK])
end)

-- Core.lua:427: a per-character setting with no default (tipBagSlot, the bag value
-- line in tooltips, isn't in Core.lua's DEFAULTS) falls through to the shared table, so
-- a profile without its own value takes Default's value instead of the setting's default.
T.xfail("A setting with no default doesn't take Default's value on another profile", "falls through to the shared table", function()
  fresh()
  T.ok(ns.PER_CHAR_SETTINGS.tipBagSlot and ns.DEFAULT_SETTINGS.tipBagSlot == nil, "a per-character setting with no default")
  ns.db.settings.tipBagSlot = false         -- turned off on Default
  ns.db.profiles.Alt = {}
  quiet(P.useProfile, "Alt")
  T.eq(ns.db.settings.tipBagSlot, nil, "Alt never turned it off")
end)

T.test("A character on a profile that no longer exists is on Default", function()
  fresh()
  ns.db.charProfile[ME] = "Gone"
  T.eq(ns:ProfileOf(), "Default")
end)

---------------------------------------------------------------------------
-- Saving and loading
---------------------------------------------------------------------------
T.test("Logging out puts the real shared table back for saving", function()
  fresh()
  local account = ns.accountSettings
  quiet(P.newProfile, "Alt")
  T.ok(ns.db.settings ~= account, "a stand-in while on a profile")
  T.fire("PLAYER_LOGOUT")
  T.eq(ns.db.settings, account)
  T.eq(getmetatable(ns.db.settings), nil)
  T.eq(ns.db.settingsAccount, nil)
end)

T.test("Loading with settingsAccount saved brings the shared settings back", function()
  login({ schema = 5, settings = { [GLOBAL] = 99 }, settingsAccount = { [GLOBAL] = 9, [CHECK] = false },
    profiles = {}, charProfile = {} })
  T.eq(ns.db.settings[GLOBAL], 9)
  T.eq(ns.db.settings[CHECK], false)
  T.eq(ns.db.settingsAccount, nil)
end)

T.test("Loading on a profile uses it", function()
  login({ schema = 5, settings = { [CHECK] = true }, profiles = { Alt = { [CHECK] = false } }, charProfile = { [ME] = "Alt" } })
  T.eq(ns:ProfileOf(), "Alt")
  T.eq(ns.db.settings[CHECK], false)
  T.eq(ns.accountSettings[CHECK], true)
end)

T.test("Schema 5: a character's own settings become a profile named after it", function()
  login({
    schema = 4,
    chars = { ["Ann-R"] = { name = "Ann" }, ["Bob-R"] = { name = "Default" }, ["Cy-R"] = { name = "Cy" } },
    profiles = { Ann = { [CHECK] = true } },
    charSettings = {
      ["Ann-R"] = { own = true, values = { [CHECK] = false } },   -- "Ann" is taken
      ["Bob-R"] = { own = true, values = { [CHECK] = false } },   -- named Default
      ["Cy-R"] = { own = false, values = { [CHECK] = false } },   -- not its own
      ["Dee-R"] = { own = true, values = { [CHECK] = false } },   -- no character record
    },
  })
  local db = ns.db
  T.eq(db.schema >= 5, true)
  T.eq(db.charSettings, nil, "charSettings goes")
  T.eq(db.charProfile["Ann-R"], "Ann 2")
  T.eq(db.profiles["Ann 2"][CHECK], false)
  T.eq(db.profiles.Ann[CHECK], true, "the profile already there is untouched")
  T.eq(db.charProfile["Bob-R"], "Default 2")
  T.eq(db.profiles.Default, nil, "never a profile called Default")
  T.eq(db.charProfile["Cy-R"], nil, "without own: nothing")
  T.eq(db.profiles.Cy, nil)
  T.eq(db.charProfile["Dee-R"], "Dee-R", "named by its key")
end)

---------------------------------------------------------------------------
-- New, rename, delete, reset
---------------------------------------------------------------------------
T.test("New profile: a copy of the current per-character settings, used at once", function()
  fresh()
  ns.db.settings[CHECK] = false
  ns.db.settings[GLOBAL] = 8
  quiet(P.newProfile, "Raid")
  T.eq(ns.db.charProfile[ME], "Raid")
  T.eq(ns.db.profiles.Raid[CHECK], false)
  T.eq(ns.db.profiles.Raid[GLOBAL], nil, "no Global settings in it")
  T.eq(ns.db.settings[CHECK], false)
end)

T.test("New profile: no second one with the same name, and never Default", function()
  fresh()
  quiet(P.newProfile, "Raid")
  quiet(P.newProfile, "raid")
  quiet(P.newProfile, "default")
  local n = 0
  for _ in pairs(ns.db.profiles) do n = n + 1 end
  T.eq(n, 1)
end)

T.test("Rename: the profile and every character on it", function()
  fresh()
  quiet(P.newProfile, "Raid")
  ns.db.charProfile["Alt-R"] = "Raid"
  ns.db.charProfile["Other-R"] = "Else"
  ns.db.profiles.Else = {}
  quiet(P.renameProfile, "Main")
  T.eq(ns.db.profiles.Raid, nil)
  T.ok(ns.db.profiles.Main, "renamed")
  T.eq(ns.db.charProfile[ME], "Main")
  T.eq(ns.db.charProfile["Alt-R"], "Main")
  T.eq(ns.db.charProfile["Other-R"], "Else", "others untouched")
end)

T.test("Rename: Default keeps its name", function()
  fresh()
  quiet(P.renameProfile, "Main")
  T.eq(ns.db.profiles.Main, nil)
  T.eq(ns:ProfileOf(), "Default")
end)

T.test("Delete: the characters on it go back to Default", function()
  fresh()
  quiet(P.newProfile, "Raid")
  ns.db.charProfile["Alt-R"] = "Raid"
  quiet(P.deleteProfile)
  T.eq(ns.db.profiles.Raid, nil)
  T.eq(ns.db.charProfile[ME], nil)
  T.eq(ns.db.charProfile["Alt-R"], nil)
  T.eq(ns.db.settings, ns.accountSettings, "this character is on the shared table again")
end)

T.test("Reset: per-character settings to their defaults, Global ones left alone", function()
  fresh()
  quiet(P.newProfile, "Raid")
  ns.db.settings[CHECK] = false
  ns.db.settings[NUM] = NUMD.min
  ns.db.settings[GLOBAL] = 13
  quiet(P.resetProfile)
  T.eq(ns.db.settings[CHECK], ns.DEFAULT_SETTINGS[CHECK])
  T.eq(ns.db.settings[NUM], ns.DEFAULT_SETTINGS[NUM])
  T.eq(ns.db.settings[GLOBAL], 13)
end)

T.test("Reset on Default leaves Global settings alone too", function()
  fresh()
  ns.db.settings[CHECK] = false
  ns.db.settings[GLOBAL] = 13
  quiet(P.resetProfile)
  T.eq(ns.db.settings[CHECK], ns.DEFAULT_SETTINGS[CHECK])
  T.eq(ns.db.settings[GLOBAL], 13)
end)

---------------------------------------------------------------------------
-- Export and import
---------------------------------------------------------------------------
local function profileText(name, values) return ns.Serialize({ kind = "profile", v = 1, name = name, values = values }) end

T.test("Export: only per-character settings, only from the ticked pages", function()
  fresh()
  local page = P.DEFS[CHECK].page
  local data = ns.Deserialize(P.exportProfile({ [page] = true, global = true }))
  T.eq(data.kind, "profile")
  T.ok(data.values[CHECK] ~= nil, "the ticked page's settings")
  for k in pairs(data.values) do
    T.ok(ns.PER_CHAR_SETTINGS[k], k .. " is per character")
    T.eq(P.DEFS[k].page, page, k .. " is on the ticked page")
  end
  T.eq(data.values[GLOBAL], nil, "never a Global setting")
end)

T.test("Import: keeps only known per-character settings with valid values", function()
  fresh()
  ns.db.settings[GLOBAL] = 5
  local ok = quiet(P.importProfile, profileText("Shared", {
    [CHECK] = false, [NUM] = NUMD.max, [MONEY] = 1500, [CHOICE] = CHOICED.options[1][1],
    [GLOBAL] = 50, notASetting = true,
  }))
  T.ok(ok, "imported")
  local p = ns.db.profiles.Shared
  T.eq(p[CHECK], false)
  T.eq(p[NUM], NUMD.max)
  T.eq(p[MONEY], 1500)
  T.eq(p[CHOICE], CHOICED.options[1][1])
  T.eq(p.notASetting, nil)
  T.eq(p[GLOBAL], nil)
  T.eq(ns.db.settings[GLOBAL], 5, "Global settings never change")
  T.eq(ns:ProfileOf(), "Shared", "used at once")
end)

T.test("Import: wrong kinds of value are left out", function()
  fresh()
  local ok = quiet(P.importProfile, profileText("Bad", {
    [CHECK] = "yes", [NUM] = NUMD.max + 1, [MONEY] = -1, [CHOICE] = "not an option", [GLOBAL] = 1,
  }))
  T.eq(ok, false, "nothing valid, so refused")
  T.eq(ns.db.profiles.Bad, nil)
  ok = quiet(P.importProfile, profileText("Some", { [CHECK] = false, [NUM] = NUMD.min - 1, [MONEY] = "lots" }))
  T.ok(ok)
  T.eq(ns.db.profiles.Some[CHECK], false)
  T.eq(ns.db.profiles.Some[NUM], ns.accountSettings[NUM], "an out-of-range number: this character's value instead")
end)

T.test("Import: refuses text that isn't a profile", function()
  fresh()
  T.eq((quiet(P.importProfile, "hello")), false)
  T.eq((quiet(P.importProfile, ns.Serialize({ chars = {}, prices = {} }))), false, "a data export")
  T.eq((quiet(P.importProfile, ns.Serialize({ kind = "profile" }))), false, "no values")
end)

T.test("Import: a unique name, never Default", function()
  fresh()
  quiet(P.importProfile, profileText("Default", { [CHECK] = false }))
  quiet(P.importProfile, profileText("default", { [CHECK] = false }))
  quiet(P.importProfile, profileText("Raid", { [CHECK] = false }))
  quiet(P.importProfile, profileText("Raid", { [CHECK] = false }))
  quiet(P.importProfile, profileText(nil, { [CHECK] = false }))
  for name in pairs(ns.db.profiles) do T.ok(name:lower() ~= "default", "named " .. name) end
  T.ok(ns.db.profiles.Raid and ns.db.profiles["Raid 2"], "Raid and Raid 2")
  T.ok(ns.db.profiles.Imported, "no name: Imported")
end)

T.test("Import: a long name is shortened and doesn't loop", function()
  fresh()
  local long = ("A very long profile name that goes on"):rep(3)
  debug.sethook(function() error("importing didn't finish") end, "", 5e6)
  local ok1 = pcall(P.importProfile, profileText(long, { [CHECK] = false }))
  local ok2 = pcall(P.importProfile, profileText(long, { [CHECK] = false }))
  debug.sethook()
  T.ok(ok1 and ok2, "finished")
  local n = 0
  for name in pairs(ns.db.profiles) do n = n + 1; T.ok(#name <= 30, name .. " fits") end
  T.eq(n, 2)
end)

T.test("The data import refuses a profile", function()
  fresh()
  local ok, msg = ns:Import(profileText("Raid", { [CHECK] = false }))
  T.eq(ok, false)
  T.ok(msg:find("Settings, Profiles", 1, true), msg)
  T.eq(ns.db.profiles.Raid, nil)
end)
