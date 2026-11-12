local T = ...
local function loadLocale(locale)
  local previous = GetLocale
  GetLocale = function() return locale end
  local ns = {}
  local ok, err = pcall(function()
    for _, file in ipairs({ "Locale.lua", "Locales/zhCN.lua" }) do
      assert(loadfile(file))("ForeverLedger", ns)
    end
  end)
  GetLocale = previous
  assert(ok, err)
  return ns
end

T.test("Localization: English clients and command/data syntax pass through", function()
  local english, chinese = loadLocale("enUS"), loadLocale("zhCN")
  T.eq(english.LocalizeText("Buy"), "Buy")
  T.eq(chinese.LocalizeText("Buy"), "购买")
  T.eq(chinese.LocalizeText(nil), nil)
  T.eq(chinese.LocalizeText(12345), 12345)
  for _, input in ipairs({ "/fl source auctionator", "any", "off", "2g 50s", "item_id,name," }) do
    T.eq(chinese.LocalizeText(input), input)
  end
end)

T.test("Localization: the actual purchase summary renders after repeated local updates", function()
  local ns = loadLocale("zhCN")
  local file = assert(io.open("BuyQueue.lua", "rb"))
  local code = file:read("*a"); file:close()
  local body = assert(code:match("(  local profit = Q.vendorValue.-)  %-%- What's left of this visit's limit"))
  local got
  local run = assert(loadstring("return function(ns, Q, money, v, total)\n" .. body .. "\nend"))()
  run(ns, { bought = 2, spent = 100, vendorValue = 140, vendorCost = 100 },
    function(n) return tostring(n) .. "c" end,
    { totals = { SetText = function(_, text) got = ns.LocalizeDisplayText(text) end } }, 0)
  T.ok(got and got:find("利润", 1, true))
  T.ok(not got:find("profit", 1, true))
  T.ok(got:find("40铜", 1, true))
end)

T.test("Localization: dictionaries and formatted messages preserve placeholders", function()
  local ns = loadLocale("zhCN")
  local spec = "%%[%-%+#0]*%d*%.?%d*[cdiouxXeEfgGqs]"
  for source, target in pairs(ns.GetLocaleData().strings) do
    T.eq(ns.LocalizeText(source), target, source)
    local args, original, translated = {}, {}, {}
    for token in source:gmatch(spec) do
      original[#original + 1] = token
      local kind = token:sub(-1)
      args[#args + 1] = kind:find("[sq]") and "装备甲" or kind:find("[eEfgG]") and 1.25 or 42
    end
    for token in target:gmatch(spec) do translated[#translated + 1] = token end
    T.same(original, translated, source)
    if #args > 0 and (ns.GetLocaleData().short[source] or #source:gsub(spec, ""):gsub("[^%a]", "") >= 5) then
      -- Colors use a string capture instead of an ordinary displayed value.
      local i = 0
      local at = 1
      while true do
        local a, b = source:find(spec, at)
        if not a then break end
        i = i + 1
        if source:sub(1, a - 1):sub(-4) == "|cff" then args[i] = "ff0000"
        elseif source:sub(1, a - 1):sub(-2) == "|c" then args[i] = "ffff0000" end
        at = b + 1
      end
      local ok, rendered = pcall(string.format, source, unpack(args))
      local valid, expected = pcall(string.format, target, unpack(args))
      if ok and valid then T.eq(ns.LocalizeText(rendered), expected, source) end
    end
  end
end)

T.test("Localization: composed messages preserve hyperlink targets, icons and URLs", function()
  local ns = loadLocale("zhCN")
  local link = "|Hitem:2318:0:0:0:0|h[Leather]|h"
  T.eq(ns.LocalizeText("Craft " .. link .. ", sell to vendor"), "制作" .. link .. "，卖给商店")
  for _, token in ipairs({ "https://example.org/Buy?id=1:2", "|TInterface/Icons/Buy:16:16|t", "|Aadventure:16:16|a", "|Kq12345:0|k" }) do
    T.eq(ns.LocalizeText(token), token)
    T.eq(ns.LocalizeText(token .. " Buy"), token .. " 购买")
  end
  T.eq(ns.LocalizeText("|cff7fd39cAll characters|r |cff888888Horde|r"), "|cff7fd39c所有角色|r |cff888888部落|r")
  T.eq(ns.LocalizeText("Best way: Craft Leather, sell to vendor"), "最佳用途：制作Leather，卖给商店")
end)

T.test("Localization: display wrappers leave input controls and popup data intact", function()
  local ns = loadLocale("zhCN")
  local display = { SetText = function(self, text) self.text = text end,
    SetFormattedText = function(self, format, ...) self.text = string.format(format, ...) end }
  local input = { SetText = display.SetText }
  ns.LocalizeFontString(display)
  ns.LocalizeFontString(display)
  display:SetText("Buy")
  T.eq(display.text, "购买")
  display:SetFormattedText("Buy %s", "Horde")
  T.eq(display.text, "购买部落")
  input:SetText("any")
  T.eq(input.text, "any")
  local original, payload, call = StaticPopup_Show, { id = 2318, price = 123 }, nil
  StaticPopup_Show = function(...) call = { ... }; return payload end
  local ok, result = pcall(ns.ShowPopup, ns, "FOREVER_LEDGER_TEST", "Buy", "Sell", payload)
  StaticPopup_Show = original
  T.ok(ok)
  T.eq(result, payload)
  T.eq(call[1], "FOREVER_LEDGER_TEST")
  T.eq(call[2], "购买")
  T.eq(call[3], "出售")
  T.eq(call[4], payload)
end)

T.test("Localization: hooks translate owned dialogs without changing settings or unrelated dialogs", function()
  local ns, callback = loadLocale("zhCN"), nil
  ns.OnReady = function(_, fn) callback = fn end
  local settings = { keepGold = 12345, custom = true }
  ns.db = { settings = settings }
  ns.Print = function(_, text) return text end
  local previous = StaticPopupDialogs
  StaticPopupDialogs = { FOREVER_LEDGER_TEST = { text = "Buy", button1 = "Sell" }, OTHER_ADDON_TEST = { text = "Buy" } }
  assert(loadfile("LocaleHooks.lua"))("ForeverLedger", ns)
  local ok, err = pcall(callback)
  local own, other = StaticPopupDialogs.FOREVER_LEDGER_TEST, StaticPopupDialogs.OTHER_ADDON_TEST
  StaticPopupDialogs = previous
  assert(ok, err)
  T.eq(own.text, "购买")
  T.eq(own.button1, "出售")
  T.eq(other.text, "Buy")
  T.eq(ns:Print("Buy"), "购买")
  T.same(settings, { keepGold = 12345, custom = true })
end)

T.test("Localization: explicit templates preserve link targets and player names", function()
  local ns = loadLocale("zhCN")
  local player = "|Hplayer:Master|h[Master]|h"
  T.eq(ns.LocalizeText(player), player)
  T.eq(ns.LocalizeText("Customer? " .. player .. " (Horde, Trade): Buy"),
    "潜在客户？" .. player .. "（部落，交易）：购买")
  ns.GetLocaleData().strings["Texture |T%s|t %s"] = "纹理 |T%s|t %s"
  ns.GetLocaleData().strings["Atlas |A%s|a %s"] = "图集 |A%s|a %s"
  -- A fresh namespace rebuilds the template cache with these test-only templates.
  local testNS = loadLocale("zhCN")
  testNS.GetLocaleData().strings["Texture |T%s|t %s"] = ns.GetLocaleData().strings["Texture |T%s|t %s"]
  testNS.GetLocaleData().strings["Atlas |A%s|a %s"] = ns.GetLocaleData().strings["Atlas |A%s|a %s"]
  T.eq(testNS.LocalizeText("Texture |TMaster|t Horde"), "纹理 |TMaster|t 部落")
  T.eq(testNS.LocalizeText("Atlas |ATrade|a Horde"), "图集 |ATrade|a 部落")
end)

-- Load this with the repository test runner's T after merging fragment-strings.json.
local T = ...
local function locale()
  local old = GetLocale
  GetLocale = function() return "zhCN" end
  local ns = {}
  for _, file in ipairs({"Locale.lua", "Locales/zhCN.lua"}) do
    assert(loadfile(file))("ForeverLedger", ns)
  end
  GetLocale = old
  return ns
end
local function source(file)
  local f = assert(io.open(file, "rb"))
  local s = f:read("*a"):gsub("\r\n", "\n")
  f:close()
  return s
end
T.test("Localization: actual shuffle step is translated before its number", function()
  local ns, s = locale(), source("Shuffles.lua")
  local body = s:match("(local function stepText.-)\n%-%- Plain%-text steps")
  local step = assert(loadstring("local ns = ...\n" .. body .. "\nreturn stepText"))(ns)
  T.eq("1. " .. step({kind="convert",step="Combine into Greater Magic Essence"}), "1. 合成强效魔法精华")
end)
T.test("Localization: settings help is translated separately from default values", function()
  local ns, s = locale(), source("Settings.lua")
  ns.DEFAULT_SETTINGS = { actionSeconds = 3, source = "auto" }
  local body = s:match("(local function defaultText.-)\n%-%- One setting's row")
  local default = assert(loadstring("local ns = ...\n" .. body .. "\nreturn defaultText"))(ns)
  T.eq(default({key="actionSeconds",kind="number",suffix="seconds"}), "默认：3 秒。")
  T.eq(default({key="source",kind="choice",options={{"auto","Auto"}}}), "默认：自动。")
  T.ok(s:find("local help = d.help and ns.LocalizeText(d.help)", 1, true))
end)
T.test("Localization: dashboard titles and suffixes translate before composition", function()
  local ns = locale()
  T.eq(ns.LocalizeText("Profit %s"):format(ns.LocalizeText("this week")), "本周利润")
  T.eq(ns.LocalizeText("Gold over %s"):format(ns.LocalizeText("the week")), "金币变化（本周）")
  T.eq(ns.LocalizeText("top: %s"):format("迅猛龙的外皮"), "最多：迅猛龙的外皮")
  T.eq(ns.LocalizeText("%s a day"):format("4银59铜"), "日均4银59铜")
end)
T.test("Localization: price, screen alert and count fragments keep their values", function()
  local ns = locale()
  local alert=ns.LocalizeText("Vendor flip: %s at %s (vendor pays %s)"):format("战士宽刃剑", "34银", "34银50铜")
    ..ns.LocalizeText(" and %d more"):format(24)
  T.eq(alert,"卖店套利：战士宽刃剑，买价34银，商店收购价34银50铜，另有24项")
  T.eq(ns.LocalizeText("New list: %s"):format("次级魔法精华"),"新建清单：次级魔法精华")
end)

T.test("Localization: visible money and dates use Chinese without changing input or link targets", function()
  local ns=loadLocale("zhCN")
  T.eq(ns.LocalizeDisplayText("1g 97s 30c"),"1金 97银 30铜")
  T.eq(ns.LocalizeDisplayText("1g97s30c"),"1金97银30铜")
  T.eq(ns.LocalizeDisplayText("|cff7fd39c+4s 59c|r"),"|cff7fd39c+4银 59铜|r")
  T.eq(ns.LocalizeDisplayText("Nov 09"),"11月9日")
  T.eq(ns.LocalizeDisplayText("1m 02s"),"1分02秒")
  T.eq(ns.LocalizeDisplayText("5m ago"),"5分钟前")
  T.eq(ns.LocalizeText("2g 50s"),"2g 50s")
  local link="|Hplayer:25s|h[25s]|h"
  T.eq(ns.LocalizeDisplayText(link.." 34s 50c"),link.." 34银 50铜")
  T.eq(ns.LocalizeDisplayText("|Tpath/25s:16|t 30c"),"|Tpath/25s:16|t 30铜")
end)
T.test("Localization: adjacent parentheses do not swallow coordinate and source groups", function()
  local ns=loadLocale("zhCN")
  local zone=ns.LocalizeText("Tanaris").." (52.6, 28.1) "..ns.LocalizeText("(Classic)")
  local rendered=ns.LocalizeDisplayText(zone)
  T.ok(not rendered:find("Tanaris",1,true))
  T.ok(rendered:find("52.6",1,true));T.ok(rendered:find("28.1",1,true))
  T.ok(not rendered:find("28.1) (",1,true))
end)

T.test("Localization: actual scan elapsed seconds are not currency", function()
  local ns=loadLocale("zhCN")
  local s=source("Prices.lua")
  local body=s:match("(local function took%(%).-)%s*local SORTS")
  local run=assert(loadstring("local ns,Scan=...\n"..body.."\nreturn took"))(ns,{started=GetTime()-42})
  T.eq(ns.LocalizeDisplayText(run()),"42秒")
  T.eq(ns.LocalizeDisplayText("0.2c"),"0.2铜")
end)

T.test("Localization: displayed input instructions keep copyable money syntax", function()
  local ns=loadLocale("zhCN")
  for _,text in ipairs({"也可输入 2g 50s。","请填写 2g 50s 25c。","使用 /fl deals vendor 1s 调整。"}) do
    T.eq(ns.LocalizeDisplayText(text),text)
  end
  T.eq(ns.LocalizeDisplayText("当前金币：2g 50s"),"当前金币：2金 50银")
end)

T.test("Localization: profile users and faction fragments translate before names", function()
  local ns=loadLocale("zhCN")
  T.eq(ns.LocalizeText("Used by: %s"):format("Master"),"使用角色：Master")
  T.eq(("%s %s"):format("CN1 Realm 2 PvE",ns.LocalizeText("Horde")),"CN1 Realm 2 PvE 部落")
  T.eq(ns.LocalizeText("%d you can't afford yet (grayed below)."):format(5),"5 项金币不足，已显示为灰色。")
end)
T.test("Buy queue: item hover omits calculation explanations", function()
  local s=source("BuyQueue.lua")
  local hover=s:match('(local function laneRow.-)\n%-%- One section:')
  T.ok(hover)
  T.ok(not hover:find("ROI =",1,true))
  T.ok(not hover:find('"Estimated ROI"',1,true))
  T.ok(hover:find("local poor = cantAfford",1,true))
end)

T.test("Localization: latest upstream UI messages and colored fragments", function()
  local ns = loadLocale("zhCN")
  T.eq(ns.LocalizeText("Watch paused while an item's page is open"), "物品买卖页面打开时，暂停套利监测")
  T.eq(ns.LocalizeText("Watch waits while you search"), "正在搜索，套利监测暂缓")
  T.eq(ns.LocalizeText("%d new %s below the usual price: see the Deals tab (/fl deals)"), "发现 %d 个%s，价格低于常见价格。查看“低价机会”页（/fl deals）。")
  T.eq(ns.LocalizeText("deal"), "低价机会")
  T.eq(ns.LocalizeText("deals"), "低价机会")
  T.eq(ns.LocalizeText("On the auction house: keeps scanning while it stays open and chimes when a new vendor flip turns up. It can only scan with the auction house open: it pauses when you close it and picks up again when you come back (Settings, Auction house: Resume the flip watch). It also waits while you're on one item's buy or sell page, so it doesn't change what the page shows; the status line says so, and it carries on when you go back to the list."), "拍卖行打开时持续扫描，发现卖店套利机会时提示。关闭拍卖行后暂停，返回时可继续（设置→拍卖行→恢复套利监测）。查看单件物品的买卖页面或自行搜索时会暂缓查询，避免替换当前页面；状态栏会显示暂停原因。返回列表后继续。")
  T.eq(ns.LocalizeText("Passive defense helps repeated melee fights in every build."), "被动防御有助于所有天赋应对反复近战。")
  T.eq(ns.LocalizeText("Forever adds melee Attack Power; prioritize it for Survival melee play."), "无限服增加近战攻击强度加成，生存近战玩法优先。")
  T.eq(ns.LocalizeText("Optional Mana recovery for long fights; prioritize your actual seal and healing needs."), "长时间战斗中可选择的法力恢复手段；优先满足常用圣印和治疗需求。")
  T.eq(ns.LocalizeText("Forever gives it to every race; prioritize when your route or group faces fear."), "时光服向所有种族开放；路线或队伍需要应对恐惧时优先学习。")
  T.eq(ns.LocalizeText("Observed Forever upgrades; prioritize only when your build actually uses this hybrid nuke."), "已观察到无限服升级；仅在实际使用这种混合直接伤害法术时优先。")
  T.eq(ns.LocalizeText("Shield-based tank damage and defense suit Protection; talent acquisition still gates it."), "依赖盾牌的坦克伤害和防御适合防护天赋；仍需先获得对应天赋。")
  T.eq(ns.LocalizeText("Optional racial attack; prioritize your main damage spells unless you use it regularly."), "可选种族攻击；除非经常使用，否则优先升级主要输出法术。")
  T.eq(ns.LocalizeText("Classic guide prioritizes rank 5 at level 40 for better recovery. Forever offers a level-40 service; use observed client ranks and tooltips for its exact label."), "经典版指南优先在40级学习5级以改善恢复。已观察到无限服40级服务，准确名称应以客户端等级和提示为准。")
  T.eq(ns.LocalizeText("Use a current defense buff; Demon Armor eventually replaces Demon Skin."), "保持防御增益适合当前等级；恶魔护甲最终会取代恶魔皮肤。")
  T.eq(ns.LocalizeText("A Feral damage cooldown candidate; prioritize only after its unlock and actual use are confirmed."), "可能适合野性的爆发技能；先核实解锁方式和实际用途。")
  T.eq(ns.LocalizeText("Forever effects need confirmation; prioritize only when this stone suits your actual build."), "时光服效果仍需确认；此类石头适合当前天赋时再优先考虑。")
  T.eq(ns.LocalizeText("Survival's melee defense matters once unlocked; ranged builds may also value the safety."), "解锁后的生存近战防御很重要，远程路线也可能受益于额外安全性。")
  T.eq(ns.LocalizeText("Central pet-based Demonology defense once unlocked."), "恶魔学识解锁后，依赖宠物的核心防御技能。")
  T.eq(ns.LocalizeText("Prioritize Arcane burst when the talent is unlocked; it is not ordinary first-rank training."), "天赋解锁后优先考虑奥术爆发，不属于普通基础技能学习。")
  T.eq(ns.LocalizeText("Hover any item to see what it's worth to you. Settings can make it short (today's cheapest price and what it's worth to you), with Shift for more. With 20 or more listed, selling on the auction house is valued from today's prices; with fewer, from this month's usual price if that's lower, so a few hopeful listings don't fool it, and a gray line says so."), "悬停物品可查看对你的价值。设置中可选择精简提示（今日最低价与物品价值），按 Shift 查看更多。拍卖挂单至少有 20 件时按今日价格估值；更少时，若本月常见价更低则采用常见价，并以灰字说明，避免少量高价挂单影响判断。")
  T.eq(ns.LocalizeText("Classic Arms and Fury guides prioritize its level-36 unlock even for single targets; confirm Forever acquisition."), "经典旧世武器和狂暴指南优先学习 36 级解锁的此技能，单体也适用；请确认时光服获取方式。")
  T.eq(ns.LocalizeText("Passive defense helps every build through repeated melee fights."), "被动防御有助于所有天赋应对反复近战。")
  T.eq(ns.LocalizeText("Provisional Protection attack; only prioritize after its Forever unlock is confirmed."), "暂定为防护攻击技能；确认其在时光服的解锁条件后再优先学习。")
  T.eq(ns.LocalizeText("Strong but self-damaging group AoE; only prioritize for that leveling method."), "强力但会伤害自身的团队范围攻击；仅在采用此升级方式时优先学习。")
  T.eq(ns.LocalizeText("Observed Forever Frost upgrades; prioritize if it is part of your frozen-target rotation."), "已观察到无限服冰霜升级；属于冻结目标输出循环时优先。")
  T.eq(ns.LocalizeText("Stances and transitions support movement, interruption and defense in every tree."), "姿态及切换有助于所有天赋的移动、打断和防御。")
  T.eq(ns.LocalizeText("Protection's primary shield attack once unlocked; prioritize for tanking."), "防护解锁后的主要盾牌攻击；承担坦克时优先升级。")
  T.eq(ns.LocalizeText("Provisional Restoration recovery; confirm Forever availability, then prioritize if used."), "暂定为恢复续航技能；确认时光服可获取后，实际使用时优先学习。")
  T.eq(ns.LocalizeText("Prioritize when your Assassination build unlocks and uses its burst."), "刺杀天赋已解锁且使用此爆发技能时优先升级。")
  T.eq(ns.LocalizeText("Prioritize for a Fury two-weapon route; two-handed builds can defer it."), "狂暴双持路线优先学习；双手武器路线可暂缓。")
  T.eq(ns.LocalizeText("Only prioritize repeated ranks for planned pack damage."), "仅在计划进行群怪输出时优先购买后续等级。")
  T.eq(ns.LocalizeText("Optional physical defense; core attacks and recovery come first."), "可选物理防御；核心攻击和恢复技能优先。")
  T.eq(ns.LocalizeText("Optional party weapon support; prioritize the totem your actual party uses."), "可选的队伍武器辅助；优先升级队伍实际使用的图腾。")
  T.eq(ns.LocalizeText("Optional Subtlety attack or defense; buy only if unlocked and used."), "可选敏锐攻击或防御技能；已解锁并实际使用时再购买。")
  T.eq(ns.LocalizeText("Official Forever Protection defense; prioritize only after the talent unlock."), "时光服官方防护防御技能；解锁天赋后再优先考虑。")
  T.eq(ns.LocalizeText("An alternative caster nuke; prioritize it when your talents and gear favor Arcane damage."), "可替代的直接伤害法术；天赋和装备偏向奥术伤害时优先。")
  T.eq(ns.LocalizeText("Forever's tank seal enables the Judgement taunt; prioritize for tanking in any tree."), "时光服坦克圣印可让审判产生嘲讽效果；任何天赋承担坦克职责时都应优先学习。")
  T.eq(ns.LocalizeText("Forever replaces the old cat resource tool; prioritize in cat play when its current unlock is confirmed."), "无限服替换了旧版猫形态资源技能；核实当前解锁方式后，猫形态玩法优先学习。")
  T.eq(ns.LocalizeText("Forever Holy can heal both caster and ally; prioritize when unlocked and healing groups."), "时光服神圣天赋可同时治疗施法者和队友；解锁后用于团队治疗时优先学习。")
  T.eq(ns.LocalizeText("Forever Arcane trainer upgrades are observed; prioritize when unlocked as your regular attack."), "已观察到无限服奥术训练师升级，解锁并作为常用攻击后优先。")
  T.eq(ns.LocalizeText("Optional Survival control attack; prioritize when it fits your melee play."), "可选生存控制攻击，适合你的近战玩法时优先。")
  T.eq(ns.LocalizeText("Classic Holy or Discipline guide can stop upgrades once Holy Fire is used as the opener; Shadow still prioritizes Mind Blast."), "经典旧世神圣或戒律路线可在改用神圣之火起手后停止升级；暗影仍优先升级心灵震爆。")
  T.eq(ns.LocalizeText("Classic Frost guide prioritizes rank 4 at 20 and rank 5 at 26; Fire can keep rank 1 for a quick slow: since October 8 a rank that low still slows but gets almost no spell power and never triggers Frost talents (Blizzard's own example)."), "经典版冰霜指南20级学4级、26级学5级；火焰可保留1级快速减速。10月8日起，如此低的等级虽仍减速，但几乎不享受法术强度且不会触发冰霜天赋，这是暴雪给出的示例。")
  T.eq(ns.LocalizeText("Before Frostbolt is learned, this is your starter damage even on a future Frost route. Classic Fire guide prioritizes rank 5 at 24; later Frost builds can skip unused Fireball upgrades."), "学会寒冰箭前，即使计划走冰霜路线也需用它输出。经典版火焰指南24级优先学5级；后续冰霜可跳过不用的火球术等级。")
  T.eq(ns.LocalizeText("A strong leveling imbue when you melee; prioritize the imbue you actually choose."), "近战升级时有力的武器附魔；优先升级实际选用的附魔。")
  T.eq(ns.LocalizeText("Optional racial defense or damage; only buy upgrades you use."), "可选种族防御或伤害技能；只升级实际使用的等级。")
  T.eq(ns.LocalizeText("The first time you open the window, a short welcome lists the five things to start with. Show it again with the button at the bottom left of this tab, or /fl welcome."), "首次打开窗口会显示五项入门操作。可点击本页左下角按钮，或输入 /fl welcome，再次查看。")
  T.eq(ns.LocalizeText("The best of selling on the auction house, selling to a vendor, disenchanting, or crafting it into something, with the best few ways listed. Disenchanting counts what the materials sell for, as an average: each disenchant gives one result, and the tooltip shows the chance of each. Hover damaged gear and the vendor way counts what a vendor pays for it as it is. Settings, Tooltips chooses which ways it counts (turn off crafting to leave out what your alts could make); shuffles and the Buy queue still count every way."), "比较拍卖出售、卖给商店、分解和加工后的价值，并列出较优方案。分解价值按各结果的概率估算，物品提示会显示概率。查看受损装备时，商店价值按它当前状态下的卖价计算。可在“设置→物品提示”选择计入哪些用途；关闭加工可排除其他角色的配方。加工套利和购买队列仍会比较所有用途。")
  T.eq(ns.LocalizeText("Click Buy queue on the auction house: a panel beside it lines up vendor flips and your shopping lists. It finds the next one by itself, and a click on Buy (or, with Scroll to buy ticked, a tick of the mouse wheel down over its top strip) buys it. Stacks of materials take a second tick to confirm the final price. Bottom right: what you bought this visit, what it cost and the profit if you vendored it (hover for the numbers). /fl queue."), "点击拍卖行的“购买队列”，即可在侧栏查看卖店套利和购物清单。队列会自动寻找下一项，点击“购买”或在顶部提示区域向下滚轮购买。材料购买需要再确认一次最终价格。右下角显示本次买入数量、花费及卖店利润，悬停查看详情。也可输入 /fl queue 打开。")
  T.eq(ns.LocalizeText("The panel's bottom row has Watch flips, Full scan and Scan materials (Stop watching and Stop scan while they run), with the scan's progress just above. While the panel is open beside the auction house, the same buttons under the auction house window are hidden."), "侧栏底部提供套利监测、全量扫描和专业材料扫描，运行时可点击停止，进度显示在按钮上方。侧栏打开时，拍卖行窗口下方的同类按钮会隐藏。")
  T.eq(ns.LocalizeText("Vendor flips or Shopping lists, switched at the top of the panel, one at a time; the one you're on is the one that buys, so a list never buys a flip by accident. Each has its own buttons at the bottom. When there is something to buy, the strip at the top glows (gold for Vendor flips, purple for Shopping lists); with Scroll to buy ticked it also shows a mouse wheel: that's where to scroll. A new flip that chimes switches the panel to Vendor flips, unless you're using a shopping list (something on it being looked up or bought, or a click or scroll there in the last 30 seconds); then a gold count on the Vendor flips button (and on the Buy queue tab) says it's there."), "侧栏顶部可切换“卖店套利”和“购物清单”，只会购买当前视图中的物品。有可买物品时，顶部提示区域会发光：套利为金色，清单为紫色；开启滚轮购买后，此处会显示滚轮图标。新的套利提示会切到卖店套利视图；若购物清单正在查询、购买，或最近30秒内有点击或滚动，则保持清单视图，并在套利按钮及购买队列标签上显示金色数量。")
  T.eq(ns.LocalizeText("Unlimited-stock vendor items show vendor under Up to on lists and stay out of the auction house queue, including hand-added items. Settings > Auction house > Buying: Buy vendor items on the auction house too (off by default) permits buying at the vendor price; a lower price or off that you typed is still respected. Your stored price is kept. Right-click an item's Up to box to use its automatic price again; the hover shows the underlying shuffle cap or usual price plus the list allowance while a typed price is in force. Limited-stock vendor items remain ordinary auction house items."), "不限量的商店物品会在购物清单的价格上限下标为“商店”，默认不进拍卖购买队列，手动添加的物品也一样。可在“设置→拍卖行→购买”开启从拍卖行购买商店物品，以商店价格为上限；手动填的更低价格或 off 仍有效。右键价格框可恢复自动价格，悬停可查看加工套利上限或常见价格加清单溢价。限量商店物品仍按普通拍卖物品处理。")
  T.eq(ns.LocalizeText("When most of what's listed is that cheap, the price has dropped and it's no bargain: rated Thin. Deals need at least 4 days of scans (or TSM). Thin data (few days, jumpy prices, usually only one listed) is hidden unless you tick Show doubtful deals too."), "若多数挂单都已降到这个价格，通常说明市场价下跌，不能视为低价机会，可靠程度会标为“数据不足”。判断低价机会需要至少四天的扫描记录，或安装 TSM。扫描天数少、价格波动大、通常只有一件挂单的机会默认隐藏；勾选“显示存疑机会”可查看。")
  T.eq(ns.LocalizeText("Sales and purchases one by one for 30 days, then as one line per item per month for a year. Gold and money in and out per day for a year, then per month. Prices per day for 90 days, then weekly for a year. Recipes, vendors, items and your characters are kept for good. Nothing is lost at a reload: only data past these ages is summed up or dropped."), "买卖明细保存30天，之后按物品汇总为月记录，保留一年。金币及每日收支保存一年，之后按月汇总。每日价格保存90天，之后按周保存一年。配方、商店、物品及角色资料长期保留。重载不会清空数据，仅会汇总或清理超过保存期限的记录。")
  T.eq(ns.LocalizeText("Type /idea on the Discord. You'll get updates in your post."), "在 Discord 输入 /idea 提交建议，后续进展会回复在你的帖子中。")
  T.eq(ns.LocalizeText("Only live sync to your own paired character (off until /fl pair), ads in Trade when you click an ad button, and your Forever Ledger version number to your guild and group, which can be turned off (Settings, Minimap and updates)."), "仅会向你配对的角色实时同步数据（输入 /fl pair 前默认关闭）、在点击广告按钮后向交易频道发广告，以及向公会和队伍发送 Forever Ledger 版本号。版本广播可在“设置→小地图与更新”关闭。")
  T.eq(ns.LocalizeText("The Price window: look up any item's price history."), "价格窗口：查询任意物品的价格历史。")
  T.eq(ns.LocalizeText("The Buy queue or shopping lists."), "打开购买队列或购物清单。")
  T.eq(ns.LocalizeText("Sessions: /fl session start or stop."), "游玩统计：/fl session start 开始，/fl session stop 停止。")
  T.eq(ns.LocalizeText("Your dungeon runs."), "查看地下城记录。")
  T.eq(ns.LocalizeText("Link or unlink your other account."), "配对或解除配对自己的另一个账号。")
  T.eq(ns.LocalizeText("The welcome card; what's new in this version."), "查看欢迎页和当前版本更新内容。")
  T.eq(ns.LocalizeText("Someone else bought them first, or their price is too old: finds over 15 minutes old are left out until a scan finds them again."), "可能已被别人买走，或扫描结果已过期。超过15分钟的套利机会会暂时隐藏，下次扫描再次发现后恢复。")
  T.eq(ns.LocalizeText("Shows new flips and deals in large text at the top of the screen, where raid warnings go. Turn it off if it covers your windows."), "在屏幕顶部的团队警告位置显示新的套利与低价机会。若遮挡窗口，可关闭。")
  T.eq(ns.LocalizeText("Chat line for new flips and deals"), "在聊天中提示新的套利与低价机会")
  T.eq(ns.LocalizeText("Lists each new vendor flip and deal in chat."), "在聊天中逐项提示新的卖店套利与低价机会。")
  T.eq(ns.LocalizeText("Reads every listing at once. The game allows one about every 15 minutes."), "一次读取全部挂单，通常每15分钟允许一次。")
  T.eq(ns.LocalizeText("Looks up the materials your recipes use, one item at a time."), "逐项查询已知配方所需的材料。")
  T.eq(ns.LocalizeText("No characters are ticked: pick some with the characters button above."), "未勾选角色，请点击上方角色按钮选择。")
  T.eq(ns.LocalizeText("No recipes saved yet. Open each profession's window once, then click Refresh."), "尚未保存配方。打开一次各专业窗口，再点击“刷新”。")
  T.eq(ns.LocalizeText("Press Ctrl+A, then Ctrl+C to copy. Paste it into Import on your other account."), "按 Ctrl+A 全选、Ctrl+C 复制，再粘贴到另一个账号的“导入”窗口。")
  T.eq(ns.LocalizeText("Press Ctrl+A, then Ctrl+C. Paste this into a spreadsheet to work with today's prices."), "按 Ctrl+A 全选、Ctrl+C 复制，可粘贴到电子表格中分析当前价格。")
  T.eq(ns.LocalizeText("A coordinated wipe tool can wait until organized group content."), "团队灭团时使用的协作技能，可等开始有组织的团队活动后再学。")
  T.eq(ns.LocalizeText("Search recipes"), "搜索配方")
  T.eq(ns.LocalizeText("The auction house shows what's listed, not what sold. \"Sells\" counts listings that vanished before they could have expired (bought, or canceled): a low estimate that gets better the more full scans you run, fastest with Watch flips."), "拍卖行提供挂单数据，不提供成交数据。“售出速度”按到期前消失的挂单估算，其中也可能包括撤拍，因此只能作为参考。全量扫描越多，估算通常越准确，开启套利监测可更快积累数据。")
  T.eq(ns.LocalizeText("New vendor flip: %s, %d at %s or less (vendor pays %s). It's in the Buy queue, under Vendor flips."), "新的卖店套利：%s，共 %d 个，买价不高于 %s（商店收购价 %s）。请查看购买队列的“卖店套利”。")
  T.eq(ns.LocalizeText("Nothing at these item levels is worth disenchanting right now. Untick Only worth disenchanting, or run a full scan."), "这些物品等级内暂无适合分解的挂单。可取消“仅显示值得分解的物品”，或执行全量扫描。")
  T.eq(ns.LocalizeText("Nothing listed at these item levels. Run a full scan, or pick other levels."), "这些物品等级内暂无挂单。可执行全量扫描，或选择其他等级。")
  T.eq(ns.LocalizeText("The cheapest one listed right now."), "当前最低挂单价。")
  T.eq(ns.LocalizeText("What it's usually cheapest at, from your scans."), "根据扫描记录估算的常见最低价。")
  T.eq(ns.LocalizeText("How far today's price is under the usual low."), "当前价格低于常见最低价的幅度。")
  T.eq(ns.LocalizeText("How many are listed at the deal price."), "当前低价挂单中的物品数量。")
  T.eq(ns.LocalizeText("How quickly it sells, from your scans."), "根据扫描记录估算的售出速度。")
  T.eq(ns.LocalizeText("What one brings after the cut and deposit, less what it costs."), "每件卖出后，扣除手续费、保证金和买入成本的利润。")
  T.eq(ns.LocalizeText("The same for every one at the deal price."), "以当前低价买下全部物品后的预计总利润。")
  T.eq(ns.LocalizeText("How far to trust it: Good, Fair or Thin. Hover a deal for why."), "可靠程度分为可靠、一般和数据不足。悬停挂单可查看原因。")
  T.eq(ns.LocalizeText("Show doubtful deals too"), "显示存疑机会")
  T.eq(ns.LocalizeText("Also lists deals with few days of prices, or prices that jump around, so the usual price is more of a guess."), "也显示扫描天数较少或价格波动较大的机会；这些物品的常见价格估算不够可靠。")
  T.eq(ns.LocalizeText("No deals that pass the checks right now. Tick \"Show doubtful deals too\" to see them."), "当前没有通过检查的低价机会。勾选“显示存疑机会”可查看其余结果。")
  T.eq(ns.LocalizeText("Quiet mode is on for this character. /fl quiet turns it off."), "此角色已开启静音模式。输入 /fl quiet 可关闭。")
  T.eq(ns.LocalizeText("Price window|r"), "价格窗口|r")
  T.eq(ns.LocalizeText("the list has all it wants, counting %d still waiting for an answer."), "已达到清单数量，其中 %d 件仍在等待购买结果。")
  T.eq(ns.LocalizeText("the list has all it wants."), "已达到清单所需数量。")
  T.eq(ns.LocalizeText("Checking how many the list still wants."), "正在核对清单还需购买的数量。")
  T.eq(ns.LocalizeText("Open the auction house to scan and buy."), "打开拍卖行后可扫描和购买。")
  T.eq(ns.LocalizeText("Click to buy this one next. Right-click to skip it until you reload."), "点击后优先购买此物品。右键跳过，重载后恢复。")
  T.eq(ns.LocalizeText("API check (include this in a bug report if something isn't working):"), "API 检查（反馈功能异常时可附上此输出）：")
  T.eq(ns.LocalizeText("Sure?"), "确认？")
  T.eq(ns.LocalizeText("canceling..."), "正在撤拍…")
  T.eq(ns.LocalizeText("check prices"), "请刷新价格")
  T.eq(ns.LocalizeText("not priced"), "尚无价格")
  T.eq(ns.LocalizeText("auction"), "挂单")
  T.eq(ns.LocalizeText("auctions"), "挂单")
  T.eq(ns.LocalizeText("its deposit"), "该挂单的保证金")
  T.eq(ns.LocalizeText("their deposits"), "这些挂单的保证金")
  T.eq(ns.LocalizeText("|cffffd100Cancel %d undercut %s and lose %s?|r Click again."), "|cffffd100撤下 %d 个被压价的%s，将损失%s？|r 再次点击确认。")
  T.eq(ns.LocalizeText("Sell speed: compared with the full scan %d minutes ago. Bought (or canceled) for sure: %d units; reposted cheaper: %d; might have expired, not counted: %d."), "售出速度：对比 %d 分钟前的全量扫描。确定成交或撤拍：%d 件；低价重新上架：%d 件；可能到期、未计入：%d 件。")
  T.eq(ns.LocalizeText("Commands: /fl (window), /fl scan, /fl scan full, /fl scan materials, /fl stop, /fl watch, /fl quiet, /fl price, /fl queue, /fl lists, /fl pull, /fl export, /fl csv, /fl import, /fl source <auto/own/auctionator>, /fl shuffles, /fl shuffles all, /fl cut <percent>, /fl margin <percent>, /fl seconds <n>, /fl deals, /fl deals settings, /fl minimap, /fl money, /fl session start, /fl session stop, /fl runs, /fl de, /fl pair <name>, /fl sync, /fl tooltip, /fl welcome, /fl new, /fl api, /fl debug"), "命令：/fl （主窗口）, /fl scan, /fl scan full, /fl scan materials, /fl stop, /fl watch, /fl quiet, /fl price, /fl queue, /fl lists, /fl pull, /fl export, /fl csv, /fl import, /fl source <auto/own/auctionator>, /fl shuffles, /fl shuffles all, /fl cut <percent>, /fl margin <percent>, /fl seconds <n>, /fl deals, /fl deals settings, /fl minimap, /fl money, /fl session start, /fl session stop, /fl runs, /fl de, /fl pair <name>, /fl sync, /fl tooltip, /fl welcome, /fl new, /fl api, /fl debug")
  T.eq(ns.LocalizeDisplayText("|cff888888check prices|r"), "|cff888888请刷新价格|r")
end)

T.test("Localization: another language registers without business-code changes", function()
  local previous = GetLocale
  GetLocale = function() return "ruRU" end
  local ns = {}
  assert(loadfile("Locale.lua"))("ForeverLedger", ns)
  GetLocale = previous
  ns.RegisterLocale("zhCN", { strings = { Buy = "wrong language" } })
  T.eq(ns.LocalizeText("Buy"), "Buy")
  ns.RegisterLocale("ruRU", { strings = { Buy = "purchase in Russian", ["Buy %s"] = "Russian %s" }, short = { ["Buy %s"] = true }, font = "Fonts/example.ttf" })
  T.eq(ns.LocalizeText("Buy"), "purchase in Russian")
  T.eq(ns.LocalizeText("Buy item"), "Russian item")
  T.eq(ns.localeFont, "Fonts/example.ttf")
  ns.GetLocaleData().strings.Buy = "changed"
  ns.InvalidateLocale()
  T.eq(ns.LocalizeText("Buy"), "changed")
end)
