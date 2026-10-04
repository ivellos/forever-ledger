-- Money as text (Core.lua ns.Money, ns.MoneyPlain) and money typed in (ParseMoney,
-- ParseMoneyLoose). Outside the game there's no GetCoinTextureString, so ns.Money
-- writes plain "1g 2s 3c", the same as ns.MoneyPlain.
local T = ...
local ns = T.ns

T.test("Money: copper, silver, gold", function()
  T.eq(ns.Money(1), "1c")
  T.eq(ns.Money(75), "75c")
  T.eq(ns.Money(100), "1s")
  T.eq(ns.Money(150), "1s 50c")
  T.eq(ns.Money(10000), "1g")
  T.eq(ns.Money(12345), "1g 23s 45c")
  T.eq(ns.Money(10050), "1g 50c", "no 0s in the middle")
end)

T.test("Money: zero, rounding, big numbers, nil", function()
  T.eq(ns.Money(0), "0c")
  T.eq(ns.Money(0.4), "0c")
  T.eq(ns.Money(99.5), "1s", "rounds to the nearest copper")
  T.eq(ns.Money(123456789), "12345g 67s 89c")
  T.eq(ns.Money(nil), "?")
end)

T.test("Money uses the game's coin text when there is one", function()
  GetCoinTextureString = function(c) return "coins:" .. c end
  local ok, out = pcall(ns.Money, 12.6)
  GetCoinTextureString = nil
  T.ok(ok, out)
  T.eq(out, "coins:13")
end)

T.test("MoneyPlain", function()
  T.eq(ns.MoneyPlain(0), "0c")
  T.eq(ns.MoneyPlain(nil), "0c")
  T.eq(ns.MoneyPlain(25025), "2g 50s 25c")
  T.eq(ns.MoneyPlain(500000), "50g")
  T.eq(ns.MoneyPlain(9999999), "999g 99s 99c")
end)

T.test("ParseMoney (strict)", function()
  T.eq(ns.ParseMoney("1g50s"), 15000)
  T.eq(ns.ParseMoney("1g 50s 3c"), 15003)
  T.eq(ns.ParseMoney("75"), 75, "a plain number is copper")
  T.eq(ns.ParseMoney("25s"), 2500)
  T.eq(ns.ParseMoney("abc"), nil)
  T.eq(ns.ParseMoney(""), nil)
  T.eq(ns.ParseMoney("5x"), nil)
end)

T.test("ParseMoneyLoose: gold silver copper by spaces or dots", function()
  T.eq(ns.ParseMoneyLoose("2 50 25"), 25025)
  T.eq(ns.ParseMoneyLoose("2.50.25"), 25025)
  T.eq(ns.ParseMoneyLoose("2 50"), 25000, "two numbers are gold and silver")
  T.eq(ns.ParseMoneyLoose("12.50", "g"), 125000)
end)

T.test("ParseMoneyLoose: with units", function()
  T.eq(ns.ParseMoneyLoose("2g 50s"), 25000)
  T.eq(ns.ParseMoneyLoose("2g50s"), 25000)
  T.eq(ns.ParseMoneyLoose("2g 50s 25c"), 25025)
  T.eq(ns.ParseMoneyLoose("75c"), 75)
  T.eq(ns.ParseMoneyLoose("1.5g"), 15000)
  T.eq(ns.ParseMoneyLoose("2,5g"), 25000, "a comma for the decimal point")
  T.eq(ns.ParseMoneyLoose("2.5s"), 250)
  T.eq(ns.ParseMoneyLoose("  3G  "), 30000, "spaces and capitals")
end)

T.test("ParseMoneyLoose: plain numbers in the box's unit", function()
  T.eq(ns.ParseMoneyLoose("12"), 12, "copper by default")
  T.eq(ns.ParseMoneyLoose("12", "s"), 1200)
  T.eq(ns.ParseMoneyLoose("12", "g"), 120000)
end)

T.test("ParseMoneyLoose: off, any and junk", function()
  T.eq(ns.ParseMoneyLoose(""), 0)
  T.eq(ns.ParseMoneyLoose(nil), 0)
  T.eq(ns.ParseMoneyLoose("off"), 0)
  T.eq(ns.ParseMoneyLoose("0"), 0)
  T.eq(ns.ParseMoneyLoose("any"), -1)
  T.eq(ns.ParseMoneyLoose("abc"), nil)
  T.eq(ns.ParseMoneyLoose("2g 50"), nil, "a number without a unit after one with")
  T.eq(ns.ParseMoneyLoose("-5"), nil, "negative")
  T.eq(ns.ParseMoneyLoose("5x"), nil)
end)

-- One digit after a dot is a decimal (owner, October 4): "1.5" is one and a half gold, as
-- "1.5g" is. Two digits, or a space, stay gold and silver.
T.test("ParseMoneyLoose: 1.5 is 1g 50s", function()
  T.eq(ns.ParseMoneyLoose("1.5", "g"), 15000)
  T.eq(ns.ParseMoneyLoose("1.05", "g"), 10500)
  T.eq(ns.ParseMoneyLoose("1 5", "g"), 10500, "a space is gold then silver")
  T.eq(ns.ParseMoneyLoose("1.5.25"), 10525, "three numbers are gold silver copper")
end)
