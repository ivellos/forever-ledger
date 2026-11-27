local _, ns = ...

local LR, LG, LB = 0.73, 0.64, 1.0   -- label colour
local clock = debugprofilestop or function() return GetTime() * 1000 end

-- What shows is set in Settings (tester feedback: the tooltip grew long): compact mode
-- shows one line and the rest while Shift is held; each section can be turned off; and
-- "Worth to you" lists only the best few ways.
-- The item on GameTooltip right now, and whether its full lines are already there
-- (compact mode: pressing Shift adds them to the tooltip that's showing).
local shownID, shownFull, shownHistory, shownCopyPrice
local debugLinks = {}   -- tooltip links already shown in debug

-- Price history while Ctrl is held (ForeverForge has the same; owner, October 3):
-- the range of the cheapest price over the last 14 days, which way it's heading, the
-- usual price this month, how many are usually listed and the lowest price ever seen.
local function historyLines(tt, id)
  local days = ns.PriceHistory and ns:PriceHistory(id) or {}
  if #days == 0 then
    ns:AddTooltipLine(tt, "No price history yet: it builds up with each scan", 0.5, 0.5, 0.5, true)
    return
  end
  -- The range of each day's typical price (the average of the cheapest 20): the very
  -- cheapest swings with one odd listing (owner's test, October 3: Strange Dust showed
  -- "20c to 2s 31c" from a single 20c listing). The lowest ever seen is still below.
  local lo, hi
  for _, d in ipairs(days) do
    lo, hi = math.min(lo or d[3], d[3]), math.max(hi or d[3], d[3])
  end
  ns:AddTooltipLine(tt, "Price history", LR, LG, LB)
  ns:AddTooltipDoubleLine(tt, "  typical, last " .. #days .. (#days == 1 and " day" or " days"),
    lo == hi and ns.Money(lo) or (ns.Money(lo) .. " to " .. ns.Money(hi)), 0.7, 0.7, 0.7, 1, 1, 1)
  -- Trend: the last 3 days' typical price against the days before them.
  if #days >= 5 then
    local recent, older, rn, pn = 0, 0, 0, 0
    for i, d in ipairs(days) do
      if i > #days - 3 then recent, rn = recent + d[3], rn + 1 else older, pn = older + d[3], pn + 1 end
    end
    local change = older > 0 and (recent / rn) / (older / pn) - 1 or 0
    local text, r, g, b = "steady", 0.7, 0.7, 0.7
    if change >= 0.1 then text, r, g, b = ("rising, %d%% up"):format(change * 100 + 0.5), 0.5, 0.83, 0.61
    elseif change <= -0.1 then text, r, g, b = ("falling, %d%% down"):format(-change * 100 + 0.5), 1, 0.5, 0.4 end
    ns:AddTooltipDoubleLine(tt, "  heading", text, 0.7, 0.7, 0.7, r, g, b)
  end
  local stats = ns.PriceStats and ns:PriceStats(id, "month")
  if stats then
    ns:AddTooltipDoubleLine(tt, "  usual this month", ns.Money(stats.usual), 0.7, 0.7, 0.7, 1, 1, 1)
    if stats.listed then
      ns:AddTooltipDoubleLine(tt, "  usually listed", tostring(math.floor(stats.listed + 0.5)), 0.7, 0.7, 0.7, 1, 1, 1)
    end
  end
  -- Lowest ever: the all-time record only gets finished days, so today's (and the
  -- recent days' cheapest, and what's listed now) count too (Magic, October 3: "lowest
  -- ever seen 35g" with one listed at 20g).
  local allLow = ns.AllTimePrice and ns:AllTimePrice(id)
  for _, d in ipairs(days) do allLow = math.min(allLow or d[2], d[2]) end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if rec and rec.m and not rec.none then allLow = math.min(allLow or rec.m, rec.m) end
  if allLow then ns:AddTooltipDoubleLine(tt, "  lowest ever seen", ns.Money(allLow), 0.7, 0.7, 0.7, 1, 1, 1) end
end

---------------------------------------------------------------------------
-- Bag value (roadmap, October 4): on a bag, what one slot costs at today's cheapest
-- price (auction house or a vendor), and which bag is the cheapest per slot right now,
-- so you buy the cheapest space first. Plain bags only (not profession bags).
---------------------------------------------------------------------------
local bagSlots = {}   -- [itemID] = slots, or false (not a plain bag / unknown), this session
local function slotsPattern(format)
  local p = format:gsub("|4[^;]*;", "\1"):gsub("%%%d+%$", "%%"):gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1")
  return (p:gsub("\1", ".-"):gsub("%%d", "(%%d+)"):gsub("%%s", ".+"))
end
local SLOTS_PATTERN = slotsPattern(CONTAINER_SLOTS or "%d Slot %s")
local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local function slotsOf(id)
  if bagSlots[id] ~= nil then return bagSlots[id] end
  local slots = false
  local ok, _, _, _, _, _, classID, subclassID = pcall(instant, id)
  local container = (Enum and Enum.ItemClass and Enum.ItemClass.Container) or 1
  if ok and classID == container and subclassID == 0 and C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok2, data = pcall(C_TooltipInfo.GetItemByID, id)
    for _, line in ipairs(ok2 and data and data.lines or {}) do
      local text = ns.Readable(line.leftText)
      local n = text and tonumber(text:match(SLOTS_PATTERN))
      if n then slots = n; break end
    end
  end
  bagSlots[id] = slots
  return slots
end

-- The cheapest one costs now: the auction house's cheapest or a vendor's price.
local function bagCost(id, market)
  local rec = market[id]
  local ah = rec and not rec.none and rec.m
  local buy = ns.db.vendorBuy[id]
  local vendor = buy and buy.p
  if ah and vendor then return math.min(ah, vendor) end
  return ah or vendor
end

local cheapestBag, cheapestAt = nil, 0
local function cheapestPerSlot()
  if cheapestBag ~= nil and GetTime() - cheapestAt < 300 then return cheapestBag end
  cheapestAt = GetTime()
  local market, best = ns.db.prices[ns.MarketKey()] or {}, false
  local ids = {}
  for id in pairs(market) do ids[id] = true end
  for id in pairs(ns.db.vendorBuy) do ids[id] = true end
  for id in pairs(ids) do
    local slots = slotsOf(id)
    local cost = slots and slots > 0 and bagCost(id, market)
    if cost then
      local per = cost / slots
      if not best or per < best.per then best = { id = id, per = per, slots = slots } end
    end
  end
  cheapestBag = best
  return best
end

-- What a disenchant gives and what each material brings, so the number can be checked by
-- hand (Magic and the owner, November 6). True if anything was added.
function ns:AddDisenchantLines(tt, id)
  local total, parts = ns:DisenchantSaleValue(id)
  if not total then return end
  if #parts == 0 then
    local names = {}
    for _, y in ipairs(ns:DisenchantYield(id)) do
      names[#names + 1] = ("%.2f %s"):format(y[2], ns:DisenchantMaterialName(y[1]))
    end
    ns:AddTooltipLine(tt, "Disenchants to about " .. table.concat(names, ", "), LR, LG, LB, true)
    return true
  end
  ns:AddTooltipDoubleLine(tt, "Disenchants to, average after the cut", ns.Money(total), LR, LG, LB, 1, 1, 1)
  for _, p in ipairs(parts) do
    local amount = p.low == p.high and tostring(p.low) or (p.low .. "-" .. p.high)
    ns:AddTooltipDoubleLine(tt, ns.LocalizeText("  %d%%: %s %s at %s"):format(p.chance, amount, ns:DisenchantMaterialName(p.id), ns.Money(p.each)),
      ns.Money(p.when), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
  end
  ns:AddTooltipLine(tt, "  You get one of these each time.", 0.5, 0.5, 0.5)
  return true
end

local function bagLines(tt, id)
  local slots = slotsOf(id)
  if not slots or slots <= 0 then return end
  local market = ns.db.prices[ns.MarketKey()] or {}
  local cost = bagCost(id, market)
  if not cost then return end
  ns:AddTooltipDoubleLine(tt, ns.LocalizeText("Per slot (%d slots)"):format(slots), ns.Money(math.floor(cost / slots + 0.5)), LR, LG, LB, 1, 1, 1)
  local best = cheapestPerSlot()
  if best and best.id ~= id and best.per < cost / slots then
    ns:AddTooltipDoubleLine(tt, "  cheapest per slot now", ns.LocalizeText("%s, %s"):format(ns.ItemName(best.id) or "?", ns.Money(math.floor(best.per + 0.5))),
      0.7, 0.7, 0.7, 0.5, 0.83, 0.61)
  elseif best and best.id == id then
    ns:AddTooltipLine(tt, "  the cheapest bag per slot right now", 0.5, 0.83, 0.61)
  end
end

-- Quests and crafts (Frank, November 14: the information helps you see what an item is
-- for, but the lists made tooltips very long). The normal view has one short line for each,
-- "Quests (3)" and "Used in crafts (12): Tailoring 8, Leatherworking 4"; holding Shift (at
-- the hover or pressed later) lists them.
local ORANGE = { 1, 0.62, 0.3 }
local function summaryLines(tt, id, s)
  if s.tipQuest ~= false and ns.QuestSummary then
    local n, keep = ns:QuestSummary(id)
    if n then
      if keep > 0 then ns:AddTooltipLine(tt, ns.LocalizeText("Quests (%d): keep it"):format(n), 1, 0.82, 0)
      else ns:AddTooltipLine(tt, ns.LocalizeText("Quests (%d)"):format(n), ORANGE[1], ORANGE[2], ORANGE[3]) end
    end
  end
  if s.tipUsedBy ~= false and ns.CraftsUsingSummary then
    local line = ns:CraftsUsingSummary(id)
    if line then ns:AddTooltipLine(tt, line, ORANGE[1], ORANGE[2], ORANGE[3], true) end
  end
end
local function listLines(tt, id, s)
  if s.tipQuest ~= false and ns.QuestLines then
    for _, q in ipairs(ns:QuestLines(id, false) or {}) do
      if q.keep then ns:AddTooltipLine(tt, q.text .. ": keep it", 1, 0.82, 0, true)
      else ns:AddTooltipLine(tt, q.text, LR, LG, LB, true) end
    end
  end
  if s.tipUsedBy == false or not ns.CraftsUsingByProfession then return end
  -- Every craft that uses it, one a line by profession, lowest skill first, like
  -- ProfTooltip (Frank, AN12, November 14); green when one of your characters knows it.
  -- (Two calls: "a and f()" keeps only f's first value, which made the count 0.)
  local order, total = ns:CraftsUsingByProfession(id)
  if not order then return end
  ns:AddTooltipLine(tt, ns.LocalizeText("Used to craft (%d):"):format(total), 1, 0.82, 0)
  for i, p in ipairs(order) do
    if i > 5 then ns:AddTooltipLine(tt, ns.LocalizeText("  and %d more professions"):format(#order - 5), 0.6, 0.6, 0.6); break end
    ns:AddTooltipLine(tt, "  " .. p.prof, ORANGE[1], ORANGE[2], ORANGE[3])
    for j, c in ipairs(p.crafts) do
      if j > 10 then ns:AddTooltipLine(tt, ns.LocalizeText("   - and %d more"):format(#p.crafts - 10), 0.6, 0.6, 0.6); break end
      local mine = ns.KnowsRecipe and ns:KnowsRecipe(p.prof, c.rid)
      local skill = c.skill and (" |cff999999(%d)|r"):format(c.skill) or ""
      if mine then ns:AddTooltipLine(tt, "   - " .. (c.n or "?") .. skill, 0.5, 0.83, 0.61)
      else ns:AddTooltipLine(tt, "   - " .. (c.n or "?") .. skill, 1, 1, 1) end
    end
  end
end
local shownLists   -- GameTooltip already has the lists (Shift)

-- copyPrice: what a vendor pays for this copy (ns.TooltipSellPrice), if the game said.
local function addLines(tt, id, forceFull, copyPrice)
  local s = ns.db and ns.db.settings
  if not id or not s or not s.tooltip then return end
  -- Each section's time, in /fl perf as "Tooltip: ..." (Frank's AN30, November 17: one freeze
  -- was 468 ms in our tooltip lines); a freeze names the slowest section and the item.
  if ns.NoteTipItem then ns.NoteTipItem(id) end
  local lapAt = clock()
  -- AHledger's credit, once, wherever its prices went into what this tooltip shows (Codex
  -- review, November 17: Worth to you from an AHledger material price had none).
  local ahlBefore = ns.AHledgerUses and ns.AHledgerUses() or 0
  local credited
  local function credit()
    if credited then return end
    credited = true
    ns:AddTooltipLine(tt, ns.AHLEDGER_CREDIT, 0.5, 0.5, 0.5)
  end
  local function usedAHledger() return ns.AHledgerUses and ns.AHledgerUses() ~= ahlBefore end
  local lapMem = ns.MemKB and ns.MemKB()
  local function lap(label)
    local now = clock()
    local mem = ns.MemKB and ns.MemKB()
    if ns.PerfNote then ns.PerfNote("Tooltip: " .. label, now - lapAt, true, mem and lapMem and mem - lapMem) end
    lapAt, lapMem = now, mem
  end
  ns:RememberItem(id)
  if tt == GameTooltip then
    copyPrice = copyPrice or (forceFull and shownCopyPrice) or nil   -- (Shift pressed later)
    shownCopyPrice = copyPrice
  end
  local full = forceFull or s.tipMode ~= "compact" or IsShiftKeyDown()
  local function on(key) return s[key] ~= false end
  -- Sell suggestion (SellAdvice.lua): bound and usable read from the game's own lines,
  -- before ours are added. (Not again when Shift adds the details to a compact tooltip.)
  local sellBound, sellUsable
  local sellOn = not forceFull and on("tipSell") and ns.AddSellLines and ns.ItemCount(id) > 0
  if sellOn and ns.SellTooltipFlags then sellBound, sellUsable = ns.SellTooltipFlags(tt) end
  local function sellLines()
    if sellOn then
      local ok, err = pcall(ns.AddSellLines, ns, tt, id, sellBound, sellUsable, copyPrice)
      if not ok then
        ns:Debug("Sell suggestion skipped for", id, err)
        -- Once a session to BugSack too, so a line that never shows can be found.
        if not ns.sellErrorShown and geterrorhandler then
          ns.sellErrorShown = true
          geterrorhandler()("Sell suggestion: " .. tostring(err))
        end
      end
    end
  end
  -- (Shift pressed on a compact tooltip calls this again: don't repeat the history.)
  local had = forceFull and tt == GameTooltip and shownHistory
  local withHistory = not had and on("tipHistory") and IsControlKeyDown()
  if tt == GameTooltip then shownID, shownFull, shownHistory = id, full, had or withHistory end

  local price, src, t, rec = ns:GetPrice(id)
  lap("price")
  -- Quests and crafts (summaryLines, listLines above): the lists with Shift held.
  local expanded = forceFull or IsShiftKeyDown()
  local function questsAndCrafts()
    -- Darkmoon Faire turn-ins: one line in coral red, always (Frank, November 14:
    -- "something noticeable"). Not again when Shift adds the rest to a compact tooltip.
    if not forceFull and on("tipDarkmoon") and ns.DarkmoonLine then
      local dmf = ns:DarkmoonLine(id)
      if dmf then ns:AddTooltipLine(tt, dmf, 1, 0.45, 0.4) end
    end
    if expanded then
      listLines(tt, id, s)
      if tt == GameTooltip then shownLists = true end
    else
      summaryLines(tt, id, s)
    end
  end
  -- Why Worth to you is under today's price (CurseForge comment, October 22: "tooltip
  -- prices don't update after scans"): an auction sale is valued at the lowest of today's
  -- cheapest, the average of the cheapest 20 and, with under 20 listed, this month's usual
  -- cheapest, after the cut and a deposit. When the auction house line is under what
  -- today's cheapest would bring, say why.
  local function whyLower(best, options)
    if not (rec and rec.m and not rec.none and not ns.EXTERNAL_NAMES[src or ""]) then return end
    local o
    for _, x in ipairs(options or {}) do if x.kind == "ah" then o = x; break end end
    if not o then return end
    local today = ns:AfterCut(rec.m) - (o.deposit or 0)
    if o.value < today - 1 then
      ns:AddTooltipLine(tt, "  Auction house value is below today's cheapest: with few listed it uses this month's usual price, so a sudden rise doesn't count yet.", 0.5, 0.5, 0.5, true)
    end
  end

  -- The sell suggestion goes first, straight under the game's own lines (Frank, AN4,
  -- November 13: below Worth to you and its ways he didn't see it).
  sellLines()
  lap("sell suggestion")

  if not full then
    questsAndCrafts()
    lap("quests and crafts")
    -- Today's cheapest too, so a new scan shows at once (CurseForge comment, October 22).
    local shownCheapest
    if price and on("tipPrice") and rec and rec.m and not rec.none and not ns.EXTERNAL_NAMES[src or ""] then
      local age = t and ns.Age(t) or ""
      ns:AddTooltipDoubleLine(tt, "Auction, cheapest", ns.Money(rec.m) .. (age ~= "" and (" |cff999999" .. age .. "|r") or ""), LR, LG, LB, 1, 1, 1)
      shownCheapest = true
    end
    local best, options = ns:GetValue(id, true)
    best, options = ns:WorthOfCopy(best, options, copyPrice)
    lap("worth to you")
    if best then
      local how = options and options[1] and options[1].label
      ns:AddTooltipDoubleLine(tt, "Worth to you" .. (how and (" |cff999999(" .. how .. ")|r") or ""), ns.Money(best), LR, LG, LB, 1, 1, 1)
      whyLower(best, options)
    elseif price then
      -- (Not again when "Auction, cheapest" above already says it: owner's screenshot,
      -- October 22, Small Glimmering Shard showed 3s 4c twice.)
      if not (shownCheapest and price == rec.m) then
        ns:AddTooltipDoubleLine(tt, "Auction price", ns.Money(price), LR, LG, LB, 1, 1, 1)
      end
    elseif not shownCheapest then
      return
    end
    if withHistory then historyLines(tt, id) end
    -- AHledger's terms: credit wherever its prices show (Prices.lua).
    if src == "AHledger" or usedAHledger() then credit() end
    ns:AddTooltipLine(tt, ns.LocalizeText(on("tipHistory") and "Hold Shift for Forever Ledger details, Ctrl for price history"
      or "Hold Shift for Forever Ledger details") .. (on("priceWindow") and (", " .. ns:PriceClickName() .. " for a graph") or ""), 0.5, 0.5, 0.5, true)
    return
  end

  -- The cheapest listing first (what people expect), then the average of the cheapest
  -- 20 (what values use, so one odd listing doesn't sway them), only when it differs.
  -- Was "Ledger price" + "cheapest listing": Magic, October 3, asked which was which.
  if price and on("tipPrice") then
    local age = t and ns.Age(t) or ""
    age = age ~= "" and (" |cff999999" .. age .. "|r") or ""
    local own = rec and rec.m and not ns.EXTERNAL_NAMES[src or ""]
    if own then
      local listed = rec.q and (" |cff999999" .. rec.q .. " listed|r") or ""
      ns:AddTooltipDoubleLine(tt, "Auction, cheapest", ns.Money(rec.m) .. listed .. age, LR, LG, LB, 1, 1, 1)
      if rec.a and rec.a ~= rec.m then
        -- With 20 or fewer listed it's the average of all of them, so say so (Magic, October 3).
        ns:AddTooltipDoubleLine(tt, (rec.q and rec.q <= 20) and ("  avg of all " .. rec.q) or "  avg of cheapest 20",
          ns.Money(rec.a), 0.7, 0.7, 0.7, 1, 1, 1)
      end
    else
      -- AHledger's own packaged copy (no sync running) can be weeks old: say so.
      local label = src or "?"
      if src == "AHledger" then
        local p = ns.AHledgerInfo(id)
        if p and p.snapshot then label = ns.LocalizeText("AHledger, packaged copy") end
      end
      ns:AddTooltipDoubleLine(tt, ns.LocalizeText("Auction price (%s)"):format(label), ns.Money(price) .. age, LR, LG, LB, 1, 1, 1)
    end
  elseif rec and rec.none and on("tipPrice") then
    ns:AddTooltipDoubleLine(tt, "Auction, cheapest", "none listed " .. ns.Age(rec.t), LR, LG, LB, 0.7, 0.7, 0.7)
  end

  -- How fast it sells, once there are enough scans to say (History.lua SellSpeed).
  if on("tipSpeed") and ns.SellSpeed then
    local ok, sp = pcall(ns.SellSpeed, ns, id)
    if ok and sp then ns:AddTooltipDoubleLine(tt, ns.LocalizeText("Sells"), ns:SellSpeedText(sp), LR, LG, LB, 1, 1, 1) end
    if (src == "AHledger" and on("tipPrice")) or (ok and sp and sp.from == "AHledger") then
      credit()
    end
  elseif src == "AHledger" and price and on("tipPrice") then
    credit()
  end
  lap("sell speed")

  -- Gear with random stats: the price of this exact version ("of the Eagle"). An auction
  -- house group ("Items in this group may vary") has no one version: its link carries a
  -- general bonus ID (3524, beta September 30) and the plain name, so it lists the
  -- cheapest versions on sale instead.
  if on("tipPrice") and tt.GetItem then
    local _, link = tt:GetItem()
    local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
    local suffix = ns:VersionOfLink(id, link)
    if suffix then
      ns:LearnVersionName(id, suffix, link)
      local m, q = ns:SuffixPrice(id, suffix)
      local vname = ns:VersionName(suffix) or "these stats"
      if m and m > 0 then
        ns:AddTooltipDoubleLine(tt, "  this version (" .. vname .. ")", ns.Money(m) .. " |cff999999" .. q .. " listed|r",
          0.7, 0.7, 0.7, 1, 1, 1)
      elseif m == 0 then
        ns:AddTooltipDoubleLine(tt, "  this version (" .. vname .. ")", "none listed", 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
      end
    elseif rec and rec.sx then
      local list = {}
      for s, m, q in rec.sx:gmatch("(%-?%d+):(%d+):(%d+)") do
        list[#list + 1] = { s = tonumber(s), m = tonumber(m), q = tonumber(q) }
      end
      table.sort(list, function(a, b) return a.m < b.m end)
      if #list > 0 then
        ns:AddTooltipDoubleLine(tt, "  versions on sale", tostring(#list), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        for i = 1, math.min(3, #list) do
          local v = list[i]
          ns:AddTooltipDoubleLine(tt, "    " .. (ns:VersionName(v.s) or "other stats"), ns.Money(v.m) .. " |cff999999" .. v.q .. " listed|r",
            0.7, 0.7, 0.7, 1, 1, 1)
        end
      end
    end
    -- Checking tooltip links against the scan (/fl debug), once per link.
    if link and rec and rec.sx and ns.db.settings.debug and not debugLinks[link] then
      debugLinks[link] = true
      ns:Debug("Tooltip version:", link:match("%[(.-)%]") or "?", "=", link:match("item:[%-%d:]*") or "?",
        "version:", suffix or "none (group)", "scan has:", rec.sx:sub(1, 80))
    end
  end
  lap("versions")

  -- Booty Bay, only when it's clearly better there (owner, October 5: neutral prices
  -- mustn't muddle these; off by default, and never while you're at a neutral one,
  -- where the prices above are its own already).
  if s.tipNeutral and not ns.neutralAH and ns.NeutralCompare then
    local c = ns:NeutralCompare(id)
    if c and c.gain > 0 and c.pct >= 0.25 then
      ns:AddTooltipDoubleLine(tt, "Booty Bay (15% cut)", ns.LocalizeText("%s, |cff7fd39c+%d%%|r %s"):format(ns.Money(c.there),
        math.floor(c.pct * 100 + 0.5), "|cff999999" .. ns.Age(c.t) .. "|r"), LR, LG, LB, 1, 1, 1)
    end
  end

  local buy = ns.db.vendorBuy[id]
  if buy and on("tipPrice") then
    -- The standing it was seen at, when above Neutral (reputation discounts).
    local standing = buy.rep and buy.rep > 4 and (_G["FACTION_STANDING_LABEL" .. buy.rep] or ("standing " .. buy.rep))
    -- Under a copper each (ammo): the stack price, "1c for 5".
    local shown = (buy.p < 1 and buy.n) and (ns.Money(math.floor(buy.p * buy.n + 0.5)) .. " for " .. buy.n) or ns.Money(buy.p)
    ns:AddTooltipDoubleLine(tt, "Vendor sells it for", shown .. (buy.lim and " |cff999999limited|r" or "")
      .. (standing and (" |cff999999at " .. standing .. "|r") or ""), LR, LG, LB, 1, 1, 1)
  end
  lap("Booty Bay and vendor")

  local best, options = ns:GetValue(id, true)
  best, options = ns:WorthOfCopy(best, options, copyPrice)
  lap("worth to you")
  if best and on("tipWorth") then
    ns:AddTooltipDoubleLine(tt, "Worth to you", ns.Money(best), LR, LG, LB, 1, 1, 1)
    whyLower(best, options)
    local limit = s.tipOptions or 3
    for i, o in ipairs(options) do
      if i > limit then
        ns:AddTooltipLine(tt, ns.LocalizeText("  and %d more ways"):format(#options - limit), 0.5, 0.5, 0.5)
        break
      end
      if i == 1 then
        ns:AddTooltipDoubleLine(tt, "  " .. o.label, ns.Money(o.value), 0.5, 0.83, 0.61, 0.5, 0.83, 0.61)
      else
        ns:AddTooltipDoubleLine(tt, "  " .. o.label, ns.Money(o.value), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
      end
    end
  end

  lap("worth lines")

  -- Green when the auction price is already at or below it.
  local maxBuy = on("tipBuy") and ns:BuyAtOrBelow(id, true)
  if maxBuy then
    if price and price <= maxBuy then
      ns:AddTooltipDoubleLine(tt, "Buy at or below", ns.Money(maxBuy), LR, LG, LB, 0.5, 0.83, 0.61)
    else
      ns:AddTooltipDoubleLine(tt, "Buy at or below", ns.Money(maxBuy), LR, LG, LB, 1, 1, 1)
    end
  end

  lap("buy at or below")
  local crateLine = on("tipCrate") and ns.CrateTooltipLine and ns:CrateTooltipLine(id)
  if crateLine then ns:AddTooltipLine(tt, crateLine, LR, LG, LB, true) end
  -- Craftsman's Writs: what the order asks for and costs (Writs.lua; the same setting).
  local writLines = on("tipCrate") and ns.WritTooltipLines and ns:WritTooltipLines(id)
  for _, l in ipairs(writLines or {}) do ns:AddTooltipLine(tt, l, LR, LG, LB, true) end
  lap("crates and writs")

  if on("tipBagSlot") then bagLines(tt, id) end
  lap("bag slots")

  if on("tipDisenchant") and ns:AddDisenchantLines(tt, id) then ns.disenchantLinesFor = id end
  lap("disenchant")

  questsAndCrafts()
  lap("quests and crafts")
  if usedAHledger() then credit() end
  -- The hint says what Shift, Ctrl and the click show (AN12, November 14: Frank held Ctrl,
  -- as only Ctrl was named, and didn't see the craft list Shift gives).
  local hints = {}
  if not expanded then
    local quests = on("tipQuest") and ns.QuestSummary and ns:QuestSummary(id)
    local crafts = on("tipUsedBy") and ns.CraftsUsing and ns:CraftsUsing(id)
    local what = (crafts and quests and "crafts and quests") or (crafts and "crafts") or (quests and "quests") or nil
    if what then hints[#hints + 1] = ns.LocalizeText("Shift for the ") .. ns.LocalizeText(what) end
  end
  if withHistory then
    historyLines(tt, id)
  elseif not had and on("tipHistory") and price and #(ns:PriceHistory(id)) > 1 then
    hints[#hints + 1] = ns.LocalizeText("Ctrl for price history")
  end
  local click = not had and on("priceWindow") and price and (ns:PriceClickName() .. ns.LocalizeText(#hints > 0 and " for a graph" or " for a price graph"))
  local text = #hints > 0 and (ns.LocalizeText("Hold ") .. table.concat(hints, ", ")) or ""
  if click then text = text .. (text ~= "" and ", " or "") .. click end
  if text ~= "" then ns:AddTooltipLine(tt, text, 0.5, 0.5, 0.5, true) end
  lap("hints and history")
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
    if tt == GameTooltip or tt == ItemRefTooltip then addLines(tt, data and data.id, nil, ns.TooltipSellPrice(data)) end
  end)
else
  local function hook(tt)
    local _, link = tt:GetItem()
    addLines(tt, ns.ItemIDFromLink(link))
  end
  GameTooltip:HookScript("OnTooltipSetItem", hook)
  ItemRefTooltip:HookScript("OnTooltipSetItem", hook)
end

addLines = ns.Timed("Tooltip lines", addLines)   -- for /fl perf

-- Compact mode: pressing Shift adds the full details to the tooltip that's showing.
-- (Tests 1 and 2: asking the game to redraw the tooltip, by RefreshData or by hovering
-- the item again, did nothing with the owner's EllesmereUI bags, so add the lines
-- directly.) They stay until the next hover; holding Shift before hovering shows them too.
GameTooltip:HookScript("OnHide", function() shownID, shownFull, shownHistory, shownCopyPrice, shownLists = nil, nil, nil, nil, nil end)
if GameTooltip.HookScript then
  pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function() shownID, shownFull, shownHistory, shownCopyPrice, shownLists = nil, nil, nil, nil, nil end)
end
ns:On("MODIFIER_STATE_CHANGED", function(key, down)
  if not key then return end
  -- Pressed is 1 in most clients; some report true. Anything else is a release.
  local pressed = down == 1 or down == true
  if not pressed then return end   -- (tested September 30: works in bags with EllesmereUI)
  -- Ctrl adds the price history the same way (the hint line stays; harmless).
  if key:find("CTRL") then
    if not (ns.db and ns.db.settings.tooltip and ns.db.settings.tipHistory ~= false) then return end
    if not GameTooltip:IsShown() or not shownID or shownHistory then return end
    shownHistory = true
    historyLines(GameTooltip, shownID)
    GameTooltip:Show()
    return
  end
  if not key:find("SHIFT") then return end
  if not (ns.db and ns.db.settings.tooltip) then return end
  if not GameTooltip:IsShown() or not shownID then return end
  if ns.db.settings.tipMode == "compact" then
    if shownFull then return end
    addLines(GameTooltip, shownID, true)
  else
    -- Full mode: Shift adds the quest and craft lists under the tooltip that's showing.
    if shownLists then return end
    shownLists = true
    listLines(GameTooltip, shownID, ns.db.settings)
  end
  GameTooltip:Show()   -- resize to fit the new lines
end)
