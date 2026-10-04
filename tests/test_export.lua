-- The FL1 export format (Core.lua ns.Serialize / ns.Deserialize, ns:Export / ns:Import):
-- plain text in and out, and nothing in it is ever run as code.
local T = ...
local ns = T.ns

T.test("Serialize and Deserialize give the same table back", function()
  local data = {
    n = 42, neg = -7, half = 0.5, big = 1234567890, yes = true, no = false,
    s = "plain", tricky = "a:b;c}{n1;s3:x", empty = "", nested = { list = { 1, 2, 3 }, deep = { deeper = { "x" } } },
    [5] = "number key", [12345] = { m = 100, q = 3 },
  }
  local text = ns.Serialize(data)
  T.eq(text:sub(1, 4), "FL1:")
  T.same(ns.Deserialize(text), data)
end)

T.test("Functions and odd keys are left out", function()
  local back = ns.Deserialize(ns.Serialize({ a = 1, f = function() end, [true] = "bool key" }))
  T.same(back, { a = 1 })
end)

T.test("Deserialize turns away text that isn't an export", function()
  local v, err = ns.Deserialize("hello")
  T.eq(v, nil)
  T.ok(type(err) == "string" and err ~= "", "says why")
  v, err = ns.Deserialize("FL1:{s1:an1;")
  T.eq(v, nil, "cut short")
  T.ok(err and err:find("ends early"), "says it ends early: " .. tostring(err))
  v = ns.Deserialize("FL1:{s1:an1;Q}")
  T.eq(v, nil, "damaged")
  T.eq(ns.Deserialize(nil), nil)
end)

T.test("Deserialize keeps spaces around the text out", function()
  T.same(ns.Deserialize("  \n" .. ns.Serialize({ a = 1 }) .. "\n "), { a = 1 })
end)

T.test("Import never runs code", function()
  local ran = {}
  local saved = {}
  for _, name in ipairs({ "loadstring", "load", "dofile", "loadfile", "setfenv", "require", "RunScript" }) do
    saved[name] = _G[name]
    _G[name] = function() ran[#ran + 1] = name end
  end
  local inputs = {
    'FL1:{s4:chars{s3:keys5:print}}',
    'FL1:return os.exit(1)',
    'FL1:{s1:as23:"); os.exit(1) --[[}',
    'FL1:{s1:an999999999999999999999999;}',
    'FL1:s-1:x',
    'FL1:' .. ('{'):rep(50),
  }
  for _, text in ipairs(inputs) do pcall(ns.Import, ns, text) end
  for name, fn in pairs(saved) do _G[name] = fn end
  T.eq(#ran, 0, "code-loading functions called: " .. table.concat(ran, ", "))
end)

T.test("Export, then Import into a fresh database, gives the same data", function()
  local key = ns.MarketKey()
  ns.db.chars["Tester-Testrealm"] = { name = "Tester", realm = "Testrealm", class = "MAGE", level = 60, updated = 100,
    profs = { Tailoring = { rank = 300, max = 300, recipes = { [1] = true } } } }
  ns.db.prices[key] = { [2589] = { m = 12, a = 15, q = 40, t = 500, l = "12:10,14:40" }, [4306] = { none = true, t = 600 } }
  ns.db.vendorBuy[2320] = { p = 10, t = 700 }
  ns.db.vendorSell[2589] = 3
  local wanted = ns.Deserialize(ns.Serialize({ chars = ns.db.chars, prices = ns.db.prices,
    vendorBuy = ns.db.vendorBuy, vendorSell = ns.db.vendorSell }))

  local text = ns:Export()
  T.resetDB()
  T.eq(next(ns.db.chars), nil, "fresh database has no characters")
  local ok, msg = ns:Import(text)
  T.ok(ok, msg)
  T.eq(msg, "Imported 1 characters and 2 prices.")
  T.same(ns.db.chars, wanted.chars, "chars")
  T.same(ns.db.prices, wanted.prices, "prices")
  T.same(ns.db.vendorBuy, wanted.vendorBuy, "vendorBuy")
  T.same(ns.db.vendorSell, wanted.vendorSell, "vendorSell")
end)

T.test("Import keeps whichever is newer", function()
  local key = ns.MarketKey()
  ns.db.prices[key] = { [1] = { m = 100, t = 1000 }, [2] = { m = 200, t = 1000 } }
  ns.db.vendorSell[9] = 5
  local text = ns.Serialize({ prices = { [key] = { [1] = { m = 1, t = 500 }, [2] = { m = 2, t = 2000 }, [3] = { m = 3, t = 1 } } },
    vendorSell = { [9] = 99 } })
  local ok = ns:Import(text)
  T.ok(ok)
  T.eq(ns.db.prices[key][1].m, 100, "older import doesn't replace")
  T.eq(ns.db.prices[key][2].m, 2, "newer import replaces")
  T.eq(ns.db.prices[key][3].m, 3, "new item added")
  T.eq(ns.db.vendorSell[9], 5, "a vendor price you have is kept")
end)
