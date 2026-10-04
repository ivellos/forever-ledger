-- Forever Ledger's tests: plain Lua 5.1, no game. Run from the repository root:
--   lua5.1 tests/run.lua
-- Loads the addon's files the way WoW does (each gets the addon name and one shared
-- namespace table), fires ADDON_LOADED so the saved data gets its defaults, then runs
-- the test files listed in FILES below. Exits with 1 if any test fails.
package.path = "./tests/?.lua;" .. package.path
local S = require("stubs")

local ADDON, ns = "ForeverLedger", {}

-- The files to load, in the .toc's order, up to the last one the tests need.
local LOAD = { "Core.lua", "Prices.lua", "Values.lua", "Crates.lua", "Sessions.lua" }
local wanted = {}
for _, f in ipairs(LOAD) do wanted[f] = true end
local order = {}
for line in io.lines("ForeverLedger.toc") do
  line = line:gsub("\r", "")
  if wanted[line] then order[#order + 1] = line end
end
assert(#order == #LOAD, "a file the tests need isn't in ForeverLedger.toc")
for _, file in ipairs(order) do
  local chunk = assert(loadfile(file))
  chunk(ADDON, ns)
end

-- ADDON_LOADED: saved data with defaults, then the addon's ready callbacks.
ForeverLedgerDB = nil
for _, f in ipairs(S.frames) do
  if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", ADDON) end
end
assert(ns.db, "ADDON_LOADED didn't set up ns.db")

---------------------------------------------------------------------------
-- The runner
---------------------------------------------------------------------------
local T = { ns = ns, S = S }
local results = { pass = 0, fail = 0, xfail = 0, xpass = 0 }
local failures = {}
local current

local function show(v)
  if type(v) == "string" then return ("%q"):format(v) end
  return tostring(v)
end

function T.eq(got, want, what)
  if got ~= want then
    error(("%sexpected %s, got %s"):format(what and (what .. ": ") or "", show(want), show(got)), 2)
  end
end

function T.ok(v, what)
  if not v then error((what or "expected a true value"), 2) end
end

-- Deep comparison for tables.
function T.same(a, b, path)
  path = path or "value"
  if type(a) ~= type(b) then error(("%s: %s vs %s"):format(path, type(a), type(b)), 2) end
  if type(a) ~= "table" then
    if a ~= b then error(("%s: %s vs %s"):format(path, show(a), show(b)), 2) end
    return
  end
  for k, v in pairs(a) do T.same(v, b[k], path .. "." .. tostring(k)) end
  for k in pairs(b) do if a[k] == nil then error(path .. "." .. tostring(k) .. " is extra", 2) end end
end

-- test(name, fn): must pass. xfail(name, why, fn): the behaviour we think is right but
-- the code doesn't do (a possible bug, listed in the pull request). It's reported, and
-- only fails the run if it unexpectedly starts passing (so the mark gets removed).
function T.test(name, fn)
  local ok, err = pcall(fn)
  if ok then results.pass = results.pass + 1
  else results.fail = results.fail + 1; failures[#failures + 1] = ("%s > %s\n    %s"):format(current, name, tostring(err)) end
end
function T.xfail(name, why, fn)
  local ok = pcall(fn)
  if ok then
    results.xpass = results.xpass + 1
    failures[#failures + 1] = ("%s > %s\n    passed, but is marked as an expected failure (%s): remove the mark"):format(current, name, why)
  else
    results.xfail = results.xfail + 1
    print(("  expected failure: %s > %s (%s)"):format(current, name, why))
  end
end

-- Each test file can change saved data; it gets a fresh copy of the defaults first.
local pristine = ns.Deserialize(ns.Serialize(ns.db))
function T.resetDB()
  local fresh = ns.Deserialize(ns.Serialize(pristine))
  for k in pairs(ns.db) do ns.db[k] = nil end
  for k, v in pairs(fresh) do ns.db[k] = v end
  S.money, S.now = 0, 1790000000
end

-- The test files (listed here, so it runs the same on any system).
local FILES = { "money", "export", "prices", "cut" }
for _, name in ipairs(FILES) do
  local f = "tests/test_" .. name .. ".lua"
  current = f:match("test_(.-)%.lua$")
  T.resetDB()
  local chunk, err = loadfile(f)
  if not chunk then
    results.fail = results.fail + 1
    failures[#failures + 1] = f .. ": " .. err
  else
    local ok, e = pcall(chunk, T)
    if not ok then results.fail = results.fail + 1; failures[#failures + 1] = f .. ": " .. tostring(e) end
  end
end

for _, f in ipairs(failures) do print("FAIL " .. f) end
print(("%d passed, %d failed, %d expected failures%s"):format(results.pass, results.fail, results.xfail,
  results.xpass > 0 and (", " .. results.xpass .. " unexpectedly passed") or ""))
os.exit((results.fail > 0 or results.xpass > 0) and 1 or 0)
