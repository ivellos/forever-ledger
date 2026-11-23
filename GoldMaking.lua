local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Gold making tab (redesign build step 6, November 15; planning/REDESIGN_PLAN.md sections
-- 2 and 8, the Gold making mockup): one list of every way to make gold the addon finds,
-- instead of the Shuffles and Deals tabs. Each finder stays where it was (Shuffles.lua:
-- shuffles, vendor flips, deals; Values.lua NeutralCompare: Booty Bay); this tab puts
-- their results into one shape and one table:
--   kind     craftVendor | craftAH | convert | flip | deal | disenchant | bootybay
--   id       the item whose icon and price window the row opens
--   name, who, cost, brings, profit (each), count (how many: nil = no limit)
-- Chips across the top pick the kind (with counts), then least profit, only recipes your
-- characters know, a name search, and saved filter sets as quick buttons.
-- Selecting a craft opens "How it adds up" on the right: the cheapest way to get the
-- materials for that many crafts (CraftPlan.lua): the cheap end of each price ladder
-- bought, the rest made where that's cheaper, your bags first, each unit counted once
-- (Frank's mockup comment, November 15). State in settings.goldMaking.
---------------------------------------------------------------------------

local KINDS = {
  { key = "all", label = "Everything" },
  { key = "craftVendor", label = "Vendor crafts", tag = "Craft, vendor" },
  { key = "craftAH", label = "AH crafts", tag = "Craft, AH" },
  { key = "convert", label = "Conversions", tag = "Conversion" },
  { key = "flip", label = "Vendor flips", tag = "Vendor flip" },
  { key = "deal", label = "Deals", tag = "Deal" },
  { key = "disenchant", label = "Disenchant", tag = "Disenchant" },
  { key = "bootybay", label = "Booty Bay", tag = "Booty Bay" },
}
local KIND_TAG = {}
for _, k in ipairs(KINDS) do KIND_TAG[k.key] = k.tag end

local KIND_TIP = {
  all = "Every kind below together, except Booty Bay, which needs a trip there: pick it on its own.",
  craftVendor = "Crafts a vendor pays more for than their materials cost.",
  craftAH = "Crafts that sell on the auction house for more than their materials cost, after the cut.",
  convert = "Turning one thing into another (essences, transmutes) that's worth more.",
  flip = "Listed for less than a vendor pays: buy, then sell to a vendor. Live watch at the auction house buys these for you.",
  deal = "Listed well below their usual price: buy and resell. A bet on the price coming back, so hover one for how sure it is.",
  disenchant = "Gear worth more as enchanting materials than it costs.",
  bootybay = "The same item cheaper at one auction house than it sells for at the other, after each one's cut (15% at Booty Bay). Needs a scan at Booty Bay.",
}

local DEAL_AGE = 3600          -- deals from prices of the last hour, as the Deals tab
local NEUTRAL_MIN = 0.10       -- Booty Bay: at least 10% better after both cuts
local NEUTRAL_LISTED = 3       -- and at least this many listed where you buy
local NEUTRAL_FRESH = 3 * 86400 -- Booty Bay prices from the last 3 days only (Frank's screenshot, November
                                -- 15: a thousand rows from old asking prices filled Everything)
local PLAN_DEFAULT = 10        -- crafts planned when nothing says how many
local PLAN_MAX = 200
local STALE = 120              -- seconds before opening the tab works the list out again
local MAX_ROWS = 300
local ROW_H = 20
local PANEL_W = 250
local LEAST = { 0, 10, 50, 100, 1000, 10000 }
local MAX_SETS = 5

---------------------------------------------------------------------------
-- Pure helpers (tests/test_gold_making.lua)
---------------------------------------------------------------------------

-- A saved price ladder ("price:runningCount,...", the counts running totals) as
-- { { price, count at that price }, ... }, cheapest first.
function ns.LadderLevels(l)
  local out, prev = {}, 0
  for p, c in (l or ""):gmatch("(%d+):(%d+)") do
    p, c = tonumber(p), tonumber(c)
    if c > prev then
      out[#out + 1] = { p, c - prev }
      prev = c
    end
  end
  return out
end

-- Whether a row passes the filters { kind, least, mine, search }; kind nil counts every
-- kind (for the chips' counts).
function ns.GoldRowShown(row, f)
  if f.kind and f.kind ~= "all" and row.kind ~= f.kind then return false end
  -- Everything leaves Booty Bay out: it needs a trip, and its thin market would fill the list.
  if f.kind == "all" and row.kind == "bootybay" then return false end
  if (row.profit or 0) < (f.least or 0) then return false end
  if f.mine and row.unknown then return false end
  if f.prof and f.prof ~= "all" and row.prof ~= f.prof then return false end
  local s = f.search and f.search:lower() or ""
  if s ~= "" and not ((row.name or ""):lower():find(s, 1, true)) then return false end
  return true
end

-- What a row is worth ranking by: profit each times how many (at most 20; no limit
-- counts as 20), so a big one-off doesn't hide a steady earner, nor the reverse.
function ns.GoldRowTotal(row)
  return (row.profit or 0) * math.min(row.count or 20, 20)
end

-- The lines of a plan (CraftPlan's result) for "How it adds up": each material the recipe
-- needs, then, under a material that's made, the materials it's made from. recipeOf(id)
-- returns { mats = { { id, qty } } } or nil. Returns { { depth, id, text } }.
function ns.GoldPlanLines(need, order, plan, recipeOf, money)
  local lines, shown = {}, {}
  local function add(id, depth)
    if shown[id] then return end
    shown[id] = true
    local e = plan[id]
    if not e then return end
    local parts = {}
    if e.owned > 0 then parts[#parts + 1] = ("%d from your bags"):format(e.owned) end
    if e.bought > 0 then
      parts[#parts + 1] = ("buy %d on the AH, up to %s (%s)"):format(e.bought, money(e.top), money(e.boughtCost))
    end
    if e.vendor > 0 then parts[#parts + 1] = ("%d from a vendor (%s)"):format(e.vendor, money(e.vendorCost)) end
    if e.made > 0 then parts[#parts + 1] = ("make %d"):format(e.made) end
    local head = depth == 0 and ("%d %s"):format(need[id] or 0, "%s") or "%s"
    lines[#lines + 1] = { depth = depth, id = id, head = head, text = table.concat(parts, ", "), parts = parts, entry = e }
    if e.made > 0 then
      local r = recipeOf(id)
      for _, m in ipairs(r and r.mats or {}) do add(m[1], depth + 1) end
    end
  end
  for _, id in ipairs(order) do add(id, 0) end
  return lines
end

---------------------------------------------------------------------------
-- The data: every finder's results as rows
---------------------------------------------------------------------------
local function S()
  local s = ns.db.settings
  s.goldMaking = s.goldMaking or {}
  local g = s.goldMaking
  g.kind = g.kind or "all"
  if g.mine == nil then g.mine = true end
  g.least = g.least or 0
  g.prof = g.prof or "all"
  g.sort = g.sort or { key = "total", desc = true }
  g.sets = g.sets or {}
  return g
end

local function firstName(name) return name and name:match("^(%S+)") or name end

local function myName()
  local c = ns.db.chars[ns.CharKey()]
  return firstName(c and c.name) or "you"
end

local function shuffleRow(s, section)
  local o = s.opt
  local kind
  if o.kind == "craft" then kind = section == "ah" and "craftAH" or "craftVendor"
  elseif o.kind == "convert" then kind = "convert"
  elseif o.kind == "disenchant" then kind = "disenchant"
  else return end
  local id = s.group and s.members[1].id or s.id
  if o.kind == "craft" and o.rec and o.rec.out then id = o.rec.out end
  local row = { key = s.key, kind = kind, s = s, id = id, name = ns:ShuffleName(s),
    cost = s.cost, profit = s.profit, brings = s.cost + s.profit, count = ns:ShuffleRuns(s) }
  if o.kind == "craft" then
    row.prof = o.prof
    row.who = firstName(o.who) or myName()
    row.whoLong = o.who and ("Known by " .. o.who) or "You know this recipe."
  elseif o.kind == "disenchant" then
    row.prof = "Enchanting"
    local who = ns:BestEnchanter()
    row.who = firstName(who) or "an enchanter"
  else
    row.who = "anyone"
  end
  return row
end

-- Every profession's crafts that sell to a vendor (Shuffles.lua FindAllVendorCrafts):
-- only the ones none of your characters know (the known ones are in FindShuffles' list).
local function unknownCraftRow(s)
  if s.known then return end
  local row = shuffleRow(s, "vendor")
  if not row then return end
  row.unknown = true
  row.who = s.prof or "?"
  row.whoLong = ("%s recipe none of your characters know%s."):format(s.prof or "A",
    s.classic and " (from Classic: Forever may have changed it)" or (s.forever and " (from Forever's game data)" or ""))
  return row
end

local function flipRow(f)
  return { key = f.key, kind = "flip", s = f, id = f.id, name = ns.ItemName(f.id), who = "anyone",
    cost = f.cost, brings = f.opt.value, profit = f.profit, count = f.buys[1].listed }
end

local function dealRow(d)
  local below = d.worth and d.worth > 0 and math.floor((1 - d.price / d.worth) * 100 + 0.5) or nil
  return { key = "deal:" .. d.id, kind = "deal", d = d, id = d.id, name = ns.ItemName(d.id), who = "anyone",
    cost = d.price, brings = d.price + (d.each or 0), profit = d.each or 0, count = d.listed,
    tag = below and ("Deal -%d%%"):format(below) or nil }
end

-- Booty Bay against your own auction house, both ways (Values.lua NeutralCompare).
local function neutralRows(out)
  local realm = ns.RealmName() or "?"
  for _, id in ipairs(ns.KeysOf(ns.db.prices[realm .. "|Neutral"])) do
    if ns.MaybeYield then ns.MaybeYield() end
    local c = ns:NeutralCompare(id)
    if c and c.t and time() - c.t <= NEUTRAL_FRESH then
      -- Buy at Booty Bay, sell here.
      if c.buyProfit > 0 and c.there > 0 and c.buyProfit / c.there >= NEUTRAL_MIN and c.listedThere >= 1
        and c.listedHere >= NEUTRAL_LISTED then
        out[#out + 1] = { key = "bb:in:" .. id, kind = "bootybay", c = c, dir = "in", id = id, name = ns.ItemName(id),
          who = "anyone", cost = c.there, brings = c.netHere, profit = c.buyProfit, count = c.listedThere,
          tag = "Buy at BB" }
      end
      -- Buy here, sell at Booty Bay.
      local gain = c.netThere - c.here
      if gain > 0 and c.here > 0 and gain / c.here >= NEUTRAL_MIN and c.listedHere >= 1
        and c.listedThere >= NEUTRAL_LISTED then
        out[#out + 1] = { key = "bb:out:" .. id, kind = "bootybay", c = c, dir = "out", id = id, name = ns.ItemName(id),
          who = "anyone", cost = c.here, brings = c.netThere, profit = gain, count = c.listedHere,
          tag = "Sell at BB" }
      end
    end
  end
end

-- Works every finder out once. Returns the rows and how many crafts were left out for a
-- material with no price.
function ns:GoldIdeas()
  -- (Each part listed in /fl perf on its own when worked out in slices.)
  local part = ns.SlicePart or function() end
  local rows = {}
  part("shuffles")
  local vendor, ah, flips = (ns.FindShufflesUntimed or ns.FindShuffles)(ns)
  for _, s in ipairs(vendor) do rows[#rows + 1] = shuffleRow(s, "vendor") end
  for _, s in ipairs(ah) do rows[#rows + 1] = shuffleRow(s, "ah") end
  for _, f in ipairs(flips) do rows[#rows + 1] = flipRow(f) end
  local noPrice = 0
  if ns.FindAllVendorCrafts then
    part("every profession's crafts")
    local all
    all, noPrice = ns:FindAllVendorCrafts()
    for _, s in ipairs(all) do rows[#rows + 1] = unknownCraftRow(s) end
  end
  part("deals")
  for _, d in ipairs(ns:FindDeals(DEAL_AGE)) do
    if d.kind == "usual" and ns:DealShown(d) then rows[#rows + 1] = dealRow(d) end
  end
  part("Booty Bay")
  neutralRows(rows)
  part(nil)
  return rows, noPrice or 0
end

---------------------------------------------------------------------------
-- How it adds up: the cheapest way to get a craft's materials, for that many
---------------------------------------------------------------------------

-- An item as CraftPlan wants it: its ladder on this auction house, a vendor that sells it,
-- a recipe of yours (or the recipe book's) that makes it, and how many you have, valued
-- at what they'd bring (the better of a vendor and the auction house after the cut).
function ns:GoldSource(id)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  local ladder
  if rec and rec.m and not rec.none then
    ladder = rec.l and ns.LadderLevels(rec.l) or {}
    if #ladder == 0 then ladder = { { rec.m, rec.q or 1 } } end
    -- The ladder keeps the cheapest 20 price levels; the rest of what's listed is counted
    -- at the last of them (a little low, but better than "can't be had" for a big batch).
    local covered = 0
    for _, lv in ipairs(ladder) do covered = covered + lv[2] end
    if (rec.q or 0) > covered then ladder[#ladder + 1] = { ladder[#ladder][1], rec.q - covered } end
  end
  local r = ns.RecipeFor and ns:RecipeFor(id)
  local recipe
  if r and not r.classic and r.r and #r.r > 0 then
    recipe = { makes = math.max(1, math.floor(r.oq or 1)), mats = r.r }
  end
  local ah = ns:GetPrice(id)
  local value = math.max(ns:GetSellPrice(id) or 0, ah and ns:AfterCut(ah) or 0)
  return { ladder = ladder, vendor = ns:GetVendorBuyPrice(id), recipe = recipe,
    owned = ns.HaveCount and ns:HaveCount(id) or 0, ownedValue = value }
end

-- The plan for n crafts of a craft row: { n, total, plan, need, order, brings (each craft) }.
function ns:GoldPlan(row, n, ownedFree)
  local o = row and row.s and row.s.opt
  if not (o and o.kind == "craft" and o.rec and o.rec.r) then return end
  local need, order = {}, {}
  for _, m in ipairs(o.rec.r) do
    if not need[m[1]] then order[#order + 1] = m[1] end
    need[m[1]] = (need[m[1]] or 0) + m[2] * n
  end
  local cache = {}
  local function src(id)
    if not cache[id] then cache[id] = ns:GoldSource(id) end
    return cache[id]
  end
  local total, plan = ns.CraftPlan(need, src, { ownedFree = ownedFree })
  local brings = o.next and o.next.value and o.next.value * (o.rec.oq or 1)
  return { n = n, total = total, plan = plan, need = need, order = order, brings = brings, src = src,
    perCraft = {}, rec = o.rec }
end

-- How many crafts to plan for: what's listed cheaply enough (Runs), capped by how many sell
-- a day on the auction house for an AH craft (Frank's mockup comment: don't plan 40 bags).
local function planCount(row)
  local n = row.count or PLAN_DEFAULT
  if row.kind == "craftAH" and ns.SellSpeed then
    local sp = ns:SellSpeed(row.id)
    if sp and sp.perDay then n = math.min(n, math.max(1, math.ceil(sp.perDay))) end
  end
  return math.max(1, math.min(n, PLAN_MAX))
end

-- The plan's materials onto a shopping list: what's bought (AH or vendor), up to the
-- highest price the plan paid. Made items aren't added; their materials are.
local function planToList(p)
  local list = ns:NewShoppingList((p.rec.n or ns.ItemName(p.rec.out) or "Craft") .. " x" .. p.n)
  local added = 0
  for id, e in pairs(p.plan) do
    local qty = e.bought + e.vendor
    if qty > 0 then
      local top = e.top or 0
      if e.vendor > 0 then top = math.max(top, math.ceil(e.vendorCost / e.vendor)) end
      ns:AddToShoppingList(list, id, top, qty)
      added = added + 1
    end
  end
  for i, l in ipairs(ns:ShoppingLists()) do if l == list then ns:SelectShoppingList(i); break end end
  if ns.RefreshListsView then ns:RefreshListsView() end
  ns:Print(("Added %d %s to shopping list \"%s\", each up to the highest price the plan paid (/fl lists)."):format(
    added, added == 1 and "material" or "materials", list.name))
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local f
local rows, noPrice, workedAt = nil, 0, nil
local shown = {}
local selected               -- the selected row's key
local planN = {}             -- crafts to plan, per row key, when changed by hand
local refresh

-- Columns from the right edge: right-aligned numbers, then Who and Kind left-aligned.
local COL = { count = -4, countW = 60, profit = -68, brings = -138, cost = -208, who = -346, whoW = 62, kind = -452, kindW = 100 }
local MONEY_W = 66
local HEADERS = {
  { key = "name", label = "Idea", tip = "What to buy or craft. Click a row for how it adds up; right-click for its price window." },
  { key = "kind", label = "Kind", tip = "How it makes gold. Hover a row for the details." },
  { key = "who", label = "Who", tip = "Which of your characters can do it." },
  { key = "cost", label = "Costs", tip = "What it costs each time: one item, or one craft's materials at today's prices." },
  { key = "brings", label = "Brings", tip = "What it brings each time, after the auction house cut where it's sold there." },
  { key = "profit", label = "Profit each", tip = "Brings minus costs." },
  { key = "count", label = "How many", tip = "How many times you could do it with what's listed cheaply enough now. No limit: everything comes from vendors." },
}
local SORT = {
  name = function(r) return (r.name or ""):lower() end,
  kind = function(r) return r.tag or KIND_TAG[r.kind] or "" end,
  who = function(r) return (r.who or ""):lower() end,
  cost = function(r) return r.cost or 0 end,
  brings = function(r) return r.brings or 0 end,
  profit = function(r) return r.profit or 0 end,
  count = function(r) return r.count or math.huge end,
  total = ns.GoldRowTotal,
}

local function money(c) return c and ns.Money(c) or "" end
-- Shorter money for the table: to the silver from 1g, to the gold from 100g, so big prices
-- fit their column (Frank's screenshot: 116g 82s... cut off). The panel and hovers keep it all.
local function short(c)
  if not c then return "" end
  c = math.floor(c + 0.5)
  if c >= 1000000 then c = math.floor(c / 10000 + 0.5) * 10000
  elseif c >= 10000 then c = math.floor(c / 100 + 0.5) * 100 end
  return ns.Money(c)
end

-- A vendor flip in words (ShuffleDetails adds a per-hour line that means nothing for a flip).
local function flipText(r)
  local s = r.s
  return ("Buy at up to %s: %d listed at or under that, %s each on average.\nA vendor pays %s.\nProfit %s each (%d%%)."):format(
    money(s.maxBuy), s.buys[1].listed or 0, money(s.cost), money(s.opt.value), money(s.profit),
    s.cost > 0 and math.floor(s.profit / s.cost * 100 + 0.5) or 0)
end

local function filters(kind)
  local g = S()
  return { kind = kind, least = g.least, mine = g.mine, prof = g.prof, search = f and f.search:GetText() or "" }
end

local workedAHledger   -- (AHledger prices went into the list: its credit in the status line)
-- Worked out over several frames (Frank's /fl perf, November 21: 855 ms in one go froze
-- the game on opening the tab). The last list stays on screen until the new one is done.
local working   -- the run in progress, if any
-- A settings change stops the run and starts again (generation), so an old run can't put
-- its list back after it (Codex review, November 21). A run during which every value was
-- thrown away (a scan, a setting) is shown, but worked out again at the next look (redo).
local generation, redo = 0, false
local function work()
  if working and not working.stopped then return end
  local before = ns.AHledgerUses and ns.AHledgerUses() or 0
  local finished, gen, startedAt = false, generation, time()
  if ns.FreshValues then ns.FreshValues() end   -- (values out of date go now: in slices they're kept)
  local stamp = ns.ValuesStamp and ns.ValuesStamp()
  working = ns.RunInSlices("Gold making list", function() return ns:GoldIdeas() end, function(r, n)
    finished = true
    working = nil
    if gen ~= generation then return end
    rows, noPrice = r, n
    workedAt = startedAt
    redo = stamp ~= (ns.ValuesStamp and ns.ValuesStamp())
    workedAHledger = ns.AHledgerUses and ns.AHledgerUses() ~= before
    if refresh then refresh() end
  end)
  if finished then working = nil end   -- (done within the first slice)
end

local function sortRows(list)
  local s = S().sort
  local get = SORT[s.key] or SORT.total
  table.sort(list, function(a, b)
    local va, vb = get(a), get(b)
    if va == vb then return (a.key or "") < (b.key or "") end
    if s.desc then return va > vb end
    return va < vb
  end)
end

local function rowTip(self)
  local r = self.entry
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetItemByID(r.id)
  ns:TooltipAddLine(" ")
  if r.kind == "deal" then
    for _, l in ipairs(ns:DealExplain(r.d)) do
      if l.head then ns:TooltipAddLine(l.head, 1, 0.82, 0)
      elseif l.note then
        local c = l.color or { 0.8, 0.8, 0.8 }
        ns:TooltipAddLine(l.note, c[1], c[2], c[3], true)
      else ns:TooltipAddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1) end
    end
  elseif r.kind == "bootybay" then
    local c = r.c
    ns:TooltipAddLine(r.dir == "in" and "Buy at Booty Bay, sell here" or "Buy here, sell at Booty Bay", 1, 0.82, 0)
    ns:TooltipAddDoubleLine("Booty Bay, cheapest", ("%s (%d listed)"):format(money(c.there), c.listedThere), 0.8, 0.8, 0.8, 1, 1, 1)
    ns:TooltipAddDoubleLine("Here, cheapest", ("%s (%d listed)"):format(money(c.here), c.listedHere), 0.8, 0.8, 0.8, 1, 1, 1)
    ns:TooltipAddDoubleLine("Brings where you sell, after the cut", money(r.brings), 0.8, 0.8, 0.8, 1, 1, 1)
    ns:TooltipAddLine("Each auction house's cut and one unsold listing's deposit are counted. Its prices are from your last scan there (" .. ns.Age(c.t) .. ").", 0.6, 0.6, 0.6, true)
  else
    if r.whoLong then ns:TooltipAddLine(r.whoLong, 0.8, 0.8, 0.8, true) end
    for line in (r.kind == "flip" and flipText(r) or ns:ShuffleDetails(r.s)):gmatch("[^\n]+") do ns:TooltipAddLine(line, 0.85, 0.85, 0.85, true) end
  end
  ns:TooltipAddLine(" ")
  ns:TooltipAddLine("Click for how it adds up. Right-click for its price window.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function getRow(i)
  local r = f.list.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, f.list.content)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.sel = T:Fill(r, { T.accent[1], T.accent[2], T.accent[3], 0.18 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  for _, k in ipairs({ "count", "profit", "brings", "cost" }) do
    r[k] = T:Text(r, 11)
    r[k]:SetPoint("RIGHT", r, "RIGHT", COL[k], 0)
    if k ~= "count" then r[k]:SetWidth(MONEY_W) end
    r[k]:SetJustifyH("RIGHT")
    r[k]:SetWordWrap(false)
  end
  r.who = T:Text(r, 11, T.dim)
  r.who:SetPoint("LEFT", r, "RIGHT", COL.who, 0)
  r.who:SetWidth(COL.whoW)
  r.who:SetJustifyH("LEFT")
  r.who:SetWordWrap(false)
  r.kind = T:Text(r, 10, T.dim)
  r.kind:SetPoint("LEFT", r, "RIGHT", COL.kind, 0)
  r.kind:SetWidth(COL.kindW)
  r.kind:SetJustifyH("LEFT")
  r.kind:SetWordWrap(false)
  r.name = T:Text(r, 11)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
  r.name:SetPoint("RIGHT", r.kind, "LEFT", -6, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if ns.ShowPriceWindow then ns:ShowPriceWindow(self.entry.id) end
      return
    end
    selected = self.entry.key
    refresh()
  end)
  r:SetScript("OnEnter", rowTip)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.list.rows[i] = r
  return r
end

local function qualityName(id, name)
  local q = select(3, ns.GetItemInfo(id))
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c and c.hex then return c.hex .. name .. "|r" end
  return name
end

local function drawChips()
  local counts = {}
  local base = filters(nil)
  for _, r in ipairs(rows or {}) do
    if ns.GoldRowShown(r, base) then
      counts[r.kind] = (counts[r.kind] or 0) + 1
      if r.kind ~= "bootybay" then counts.all = (counts.all or 0) + 1 end
    end
  end
  local kind = S().kind
  local x = 0
  for _, k in ipairs(KINDS) do
    local b = f.chips[k.key]
    b:SetText(("%s  |cff999999%d|r"):format(k.label, counts[k.key] or 0))
    b:SetWidth(b:GetFontString():GetStringWidth() + 14)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
    x = x + b:GetWidth() + 4
    b:SetSelected(k.key == kind)
  end
end

local function drawSets()
  local g = S()
  local prev = f.setsLabel
  for i = 1, MAX_SETS do
    local b = f.sets[i]
    local set = g.sets[i]
    if set then
      b:SetText(set.name)
      b:SetWidth(math.min(110, b:GetFontString():GetStringWidth() + 18))
      b:ClearAllPoints()
      b:SetPoint("LEFT", prev, "RIGHT", prev == f.setsLabel and 8 or 4, 0)
      b:Show()
      prev = b
    else
      b:Hide()
    end
  end
  f.setsHint:SetShown(#g.sets == 0)
  f.saveSet:SetEnabled(#g.sets < MAX_SETS)
end

local function drawList()
  local g = S()
  local fil = filters(g.kind)
  shown = {}
  for _, r in ipairs(rows or {}) do
    if ns.GoldRowShown(r, fil) then shown[#shown + 1] = r end
  end
  sortRows(shown)
  local n = math.min(#shown, MAX_ROWS)
  local w = f.list.sf:GetWidth() - 12
  for i = 1, n do
    local e = shown[i]
    local r = getRow(i)
    r.entry = e
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.list.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetWidth(w)
    r.stripe:SetShown(i % 2 == 0)
    r.sel:SetShown(e.key == selected)
    r.icon:SetTexture(ns:ItemIcon(e.id))
    r.name:SetText(qualityName(e.id, e.name or ns.ItemName(e.id) or "?") .. (e.unknown and " |cff888888(learn)|r" or ""))
    r.kind:SetText(e.tag or KIND_TAG[e.kind] or "")
    r.who:SetText(e.who or "")
    r.cost:SetText(short(e.cost))
    r.brings:SetText(short(e.brings))
    r.profit:SetText("|cff7fd39c" .. short(e.profit) .. "|r")
    r.count:SetText(e.count and tostring(e.count) or "|cff888888no limit|r")
    r:Show()
  end
  for i = n + 1, #f.list.rows do f.list.rows[i]:Hide() end
  f.list.content:SetHeight(math.max(n * ROW_H, ROW_H))
  f.list.sf.UpdateScrollBar()
  for _, h in ipairs(f.headers) do
    local mark = g.sort.key == h.key and (g.sort.desc and " v" or " ^") or ""
    h.fs:SetText(h.label .. mark)
  end

  -- Translated part by part: the joined line matches no translation.
  local L = ns.LocalizeText
  local parts = {}
  if working then parts[#parts + 1] = L("Working out the list") end
  if workedAt then
    local last = ns.db.lastFullScan
    parts[#parts + 1] = L("Worked out %s%s"):format(date("%H:%M", workedAt),
      last and L(", full scan %s"):format(L(ns.Age(last))) or "")
  end
  if #shown > MAX_ROWS then parts[#parts + 1] = L("The best %d of %d shown"):format(MAX_ROWS, #shown) end
  if noPrice > 0 and not g.mine then
    parts[#parts + 1] = L("%d left out: a material has no price"):format(noPrice)
  end
  if workedAHledger then parts[#parts + 1] = ns.AHLEDGER_CREDIT end   -- (its terms: credit where its prices show)
  f.status:SetText(table.concat(parts, ". ") .. (#parts > 0 and "." or ""))
  f.empty:SetShown(#shown == 0)
  if #shown == 0 then
    f.empty:SetText(working and not rows and "Working out the list: a moment..." or not next(ns.db.prices[ns.MarketKey()] or {}) and
      "No prices yet: run a Full scan at the auction house, then come back."
      or "Nothing here with these filters. Try Everything, a lower Least profit, or clear the search.")
  end
end

---------------------------------------------------------------------------
-- The right panel
---------------------------------------------------------------------------
local function selectedRow()
  for _, r in ipairs(shown) do if r.key == selected then return r end end
end

-- The panel is a list of lines, each one of a few kinds (Frank, November 15: the text was
-- "quite busy"; numbers now line up on the right and each material is a row of its own):
--   big   the profit, large      note  a short wrapped line, gray
--   head  a section heading      pair  a label with its amount on the right
--   item  an icon, a name and its cost, with a gray line under it (sub)
local GREEN, RED = "|cff7fd39c", "|cffee8597"

local function profitText(c, unit)
  if not c then return "" end
  if c < 0 then return RED .. ns.Money(-c) .. " lost " .. unit .. "|r" end
  return GREEN .. "+" .. ns.Money(c) .. " " .. unit .. "|r"
end

local function stepsSpec(spec, s)
  local steps = ns:ShuffleSteps(s)
  local n = 0
  for _ in steps:gmatch("[^\n]+") do n = n + 1 end
  if n <= 2 then return end   -- craft then sell, or buy then sell: the row's Kind says it
  spec[#spec + 1] = { style = "head", left = "Steps" }
  for line in steps:gmatch("[^\n]+") do spec[#spec + 1] = { style = "note", left = line } end
end

-- A craft row: its plan for that many crafts.
local function craftSpec(r, spec)
  local n = planN[r.key] or planCount(r)
  local free = f.ownedFree:GetChecked() and true or false
  -- Worked out again only when the row, the number of crafts, the bags switch or the
  -- list's prices change: scans redraw the tab up to once a second.
  local key = ("%s:%d:%s:%s"):format(r.key, n, tostring(free), tostring(workedAt))
  if f.panel.planKey ~= key then
    local before = ns.AHledgerUses and ns.AHledgerUses() or 0
    f.panel.planKey, f.panel.planFor = key, ns:GoldPlan(r, n, free)
    f.panel.planAHledger = ns.AHledgerUses and ns.AHledgerUses() ~= before
  end
  local plan = f.panel.planFor
  f.panel.plan = plan
  if not (plan and plan.total) then
    spec[#spec + 1] = { style = "note", left = RED .. "A material can't be had at today's prices: none listed, and no vendor or recipe.|r" }
    return
  end
  local each = plan.total / plan.n
  local profit = plan.brings and (plan.brings - each)
  spec[#spec + 1] = { style = "big", left = profitText(profit, "a craft") }
  local bits = {}
  if profit and each > 0 then bits[#bits + 1] = ("%d%% on what it costs"):format(math.floor(profit / each * 100 + 0.5)) end
  if r.kind == "craftAH" and ns.SellSpeed then
    local sp = ns:SellSpeed(r.id)
    if sp and sp.perDay then
      bits[#bits + 1] = sp.key == "none" and "no sales seen yet"
        or ("sells: %s, about %d a day"):format(sp.label, math.floor(sp.perDay + 0.5))
    end
    if sp and sp.from == "AHledger" then bits.credit = true end
  end
  if #bits > 0 then spec[#spec + 1] = { style = "note", left = table.concat(bits, ", ") } end
  -- AHledger's terms: credit where its figures show (Prices.lua): its sell speed, or its
  -- prices in the plan (Codex review, November 17).
  if bits.credit or f.panel.planAHledger then spec[#spec + 1] = { style = "note", left = ns.AHLEDGER_CREDIT } end
  spec[#spec + 1] = { style = "head", left = ("For %d %s"):format(plan.n, plan.n == 1 and "craft" or "crafts") }
  spec[#spec + 1] = { style = "pair", left = "Materials, a craft", right = ns.Money(each) }
  if plan.brings then
    spec[#spec + 1] = { style = "pair", left = r.kind == "craftAH" and "Brings, after the cut" or "A vendor pays",
      right = ns.Money(plan.brings) }
  end
  spec[#spec + 1] = { style = "pair", left = "All materials", right = ns.Money(plan.total) }
  spec[#spec + 1] = { style = "head", left = "Materials" }
  local lines = ns.GoldPlanLines(plan.need, plan.order, plan.plan,
    function(id) return plan.src(id).recipe end, money)
  for _, l in ipairs(lines) do
    local e = l.entry
    local cost = e.boughtCost + e.vendorCost
    if e.owned > 0 and not free then cost = cost + e.owned * (plan.src(l.id).ownedValue or 0) end
    local name = ns.ItemName(l.id) or ("item " .. l.id)
    local count = l.depth == 0 and plan.need[l.id] or (e.owned + e.bought + e.vendor + e.made)
    spec[#spec + 1] = { style = "item", icon = ns:ItemIcon(l.id), indent = l.depth,
      left = ("%d %s"):format(count, name), right = cost > 0 and ns.Money(cost) or "" }
    local how = {}
    if e.owned > 0 then how[#how + 1] = ("%d from your bags"):format(e.owned) end
    if e.bought > 0 then how[#how + 1] = ("%d on the AH, up to %s"):format(e.bought, ns.Money(e.top)) end
    if e.vendor > 0 then how[#how + 1] = ("%d from a vendor"):format(e.vendor) end
    if e.made > 0 then how[#how + 1] = ("make %d"):format(e.made) end
    spec[#spec + 1] = { style = "sub", indent = l.depth, left = table.concat(how, ", ") }
  end
  stepsSpec(spec, r.s)
end

local function panelSpec(r)
  local spec = {}
  if r.kind == "craftVendor" or r.kind == "craftAH" then
    craftSpec(r, spec)
  elseif r.kind == "deal" then
    spec[#spec + 1] = { style = "big", left = profitText(r.profit, "each") }
    for _, l in ipairs(ns:DealExplain(r.d)) do
      if l.head then spec[#spec + 1] = { style = "head", left = l.head }
      elseif l.note then spec[#spec + 1] = { style = "note", left = l.note }
      else spec[#spec + 1] = { style = "pair", left = l[1], right = tostring(l[2]) } end
    end
  elseif r.kind == "bootybay" then
    local c = r.c
    spec[#spec + 1] = { style = "big", left = profitText(r.profit, "each") }
    spec[#spec + 1] = { style = "note", left = r.dir == "in" and "Buy it at Booty Bay, sell it here."
      or "Buy it here, sell it at Booty Bay." }
    spec[#spec + 1] = { style = "pair", left = ("Booty Bay, %d listed"):format(c.listedThere), right = ns.Money(c.there) }
    spec[#spec + 1] = { style = "pair", left = ("Here, %d listed"):format(c.listedHere), right = ns.Money(c.here) }
    spec[#spec + 1] = { style = "pair", left = "Brings, after the cut", right = ns.Money(r.brings) }
    spec[#spec + 1] = { style = "note", left = "Booty Bay takes 15%. Its prices are from your scan there " .. ns.Age(c.t)
      .. ": scan again when you get there." }
  elseif r.kind == "flip" then
    local s = r.s
    spec[#spec + 1] = { style = "big", left = profitText(r.profit, "each") }
    spec[#spec + 1] = { style = "pair", left = "Buy at up to", right = ns.Money(s.maxBuy) }
    spec[#spec + 1] = { style = "pair", left = ("%d listed, each on average"):format(s.buys[1].listed or 0), right = ns.Money(s.cost) }
    spec[#spec + 1] = { style = "pair", left = "A vendor pays", right = ns.Money(s.opt.value) }
    spec[#spec + 1] = { style = "note", left = "Live watch at the auction house (Buy tab) buys these for you, one click each." }
  else
    spec[#spec + 1] = { style = "big", left = profitText(r.profit, r.s.single and "each" or "a time") }
    spec[#spec + 1] = { style = "pair", left = "Costs", right = ns.Money(r.cost) }
    spec[#spec + 1] = { style = "pair", left = "Brings", right = ns.Money(r.brings) }
    if r.s.maxBuy and (r.s.single or r.s.group) then
      spec[#spec + 1] = { style = "pair", left = "Buy at up to", right = ns.Money(r.s.maxBuy) }
    end
    spec[#spec + 1] = { style = "head", left = "Steps" }
    for line in ns:ShuffleSteps(r.s):gmatch("[^\n]+") do spec[#spec + 1] = { style = "note", left = line } end
  end
  return spec
end

local function panelLine(i)
  local p = f.panel
  local l = p.lines[i]
  if l then return l end
  l = CreateFrame("Frame", nil, p.content)
  l.icon = l:CreateTexture(nil, "ARTWORK")
  l.icon:SetSize(14, 14)
  l.icon:SetPoint("TOPLEFT", 0, 0)
  l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  l.left = T:Text(l, 11)
  l.left:SetJustifyH("LEFT")
  l.left:SetJustifyV("TOP")
  l.right = T:Text(l, 11)
  l.right:SetJustifyH("RIGHT")
  l.right:SetPoint("TOPRIGHT", 0, 0)
  l.right:SetWordWrap(false)
  p.lines[i] = l
  return l
end

local function drawSpec(spec)
  local p = f.panel
  local w = PANEL_W - 26
  local y = 0
  for i, d in ipairs(spec) do
    local l = panelLine(i)
    local indent = (d.indent or 0) * 12 + (d.style == "sub" and 18 or 0)
    if d.style == "head" then y = y + (i > 1 and 10 or 0)
    elseif d.style ~= "sub" and i > 1 then y = y + 3 end
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", p.content, "TOPLEFT", indent, -y)
    l:SetWidth(w - indent)
    local size, color = 11, T.text
    if d.style == "big" then size = 15
    elseif d.style == "head" then size, color = 10, { 1, 0.82, 0, 1 }
    elseif d.style == "note" or d.style == "sub" then size, color = 10, T.dim end
    T:Font(l.left, size, color)
    T:Font(l.right, 11, T.text)
    l.icon:SetShown(d.icon ~= nil)
    if d.icon then l.icon:SetTexture(d.icon) end
    l.right:SetText(d.right or "")
    local rightW = (d.right and d.right ~= "") and (l.right:GetStringWidth() + 6) or 0
    local iconW = d.icon and 18 or 0
    l.left:ClearAllPoints()
    l.left:SetPoint("TOPLEFT", iconW, d.icon and -1 or 0)
    l.left:SetWidth(math.max(40, w - indent - iconW - rightW))
    l.left:SetWordWrap(d.style == "note" or d.style == "sub" or d.style == "head")
    l.left:SetText(d.left or "")
    local h = math.max(l.left:GetStringHeight(), d.icon and 14 or 0, size)
    l:SetHeight(h)
    y = y + h
    l:Show()
  end
  for i = #spec + 1, #p.lines do p.lines[i]:Hide() end
  p.content:SetHeight(y + 8)
  p.sf.UpdateScrollBar()
end

local function drawPanel()
  local p = f.panel
  local r = selectedRow()
  local spec
  if not r then
    p.title:SetText("How it adds up")
    spec = { { style = "note", left = "Click an idea on the left: what it costs, what it brings and, for a craft, the cheapest way to get its materials for that many crafts." } }
    p.count:Hide(); p.countLabel:Hide(); p.ownedFree:Hide()
    p.add:Hide(); p.price:Hide()
  else
    p.title:SetText(qualityName(r.id, r.name or ns.ItemName(r.id) or "?"))
    local isCraft = r.kind == "craftVendor" or r.kind == "craftAH"
    p.count:SetShown(isCraft); p.countLabel:SetShown(isCraft); p.ownedFree:SetShown(isCraft)
    if isCraft then p.count:SetValue(planN[r.key] or planCount(r)) end
    spec = panelSpec(r)
    p.add:SetShown(r.kind ~= "bootybay" and r.kind ~= "flip")
    p.add:SetText(isCraft and "Add materials to a shopping list" or "Add to a shopping list")
    p.price:Show()
  end
  local top = p.count:IsShown() and 74 or 34
  p.sf:ClearAllPoints()
  p.sf:SetPoint("TOPLEFT", 8, -top)
  p.sf:SetPoint("BOTTOMRIGHT", -4, p.add:IsShown() and 64 or 36)
  p.content:SetWidth(PANEL_W - 24)
  drawSpec(spec)
end

local function addToList()
  local r = selectedRow()
  if not r then return end
  if r.kind == "craftVendor" or r.kind == "craftAH" then
    local plan = f.panel.plan
    if not (plan and plan.total) then ns:Print("Nothing to add: a material can't be had at today's prices."); return end
    planToList(plan)
  elseif r.kind == "deal" then
    local list = ns:NewShoppingList(ns.ItemName(r.id) or "Deal")
    ns:AddToShoppingList(list, r.id, r.d.limit or r.d.price, r.d.listed or 1)
    for i, l in ipairs(ns:ShoppingLists()) do if l == list then ns:SelectShoppingList(i); break end end
    if ns.RefreshListsView then ns:RefreshListsView() end
    ns:Print(("Added %s to shopping list \"%s\", up to %s (/fl lists)."):format(ns.ItemName(r.id) or "?", list.name, money(r.d.limit or r.d.price)))
  else
    local list, err = ns:ShuffleToShoppingList(r.s, nil, math.max(1, math.min(r.count or 1, 20)))
    if not list then ns:Print(err) end
  end
end

---------------------------------------------------------------------------
-- Saved filter sets
---------------------------------------------------------------------------
local function askName(onName)
  StaticPopupDialogs["FOREVER_LEDGER_GOLD_SET"] = {
    text = ns.LocalizeText("Name these filters (a quick button on Gold making):"), button1 = SAVE or "Save", button2 = CANCEL or "Cancel",
    hasEditBox = true,
    OnShow = function(self)
      local eb = self.editBox or self.EditBox
      if eb then eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self)
      local eb = self.editBox or self.EditBox
      local name = eb and eb:GetText() or ""
      if not name:match("^%s*$") then onName(name) end
    end,
    EditBoxOnEnterPressed = function(self)
      local name = self:GetText()
      if not name:match("^%s*$") then onName(name) end
      self:GetParent():Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show("FOREVER_LEDGER_GOLD_SET")
end

local function confirmDelete(i)
  local set = S().sets[i]
  if not set then return end
  StaticPopupDialogs["FOREVER_LEDGER_GOLD_SET_DELETE"] = {
    text = ns.LocalizeText("Delete the saved filters \"%s\"? This can't be undone."):format(set.name),
    button1 = ns.LocalizeText("Delete"), button2 = CANCEL or "Cancel",
    OnAccept = function()
      for j, s in ipairs(S().sets) do if s == set then table.remove(S().sets, j); break end end
      refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show("FOREVER_LEDGER_GOLD_SET_DELETE")
end

local function applySet(set)
  local g = S()
  g.kind, g.least, g.mine, g.prof = set.kind or "all", set.least or 0, set.mine ~= false, set.prof or "all"
  f.search:SetText(set.search or "")
  f.least:SetValue(g.least)
  f.mine:SetChecked(g.mine)
  refresh()
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------
local function leastOptions()
  local opts = {}
  for _, c in ipairs(LEAST) do opts[#opts + 1] = { value = c, label = c == 0 and "Any" or ns.MoneyPlain(c) } end
  return opts
end

function ns:BuildGoldMaking(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f:Hide()

  -- Row 1: the kinds, as chips with counts.
  f.chips = {}
  for _, k in ipairs(KINDS) do
    local b = T:Button(f, k.label, 80, function()
      S().kind = k.key
      refresh()
    end, 22)
    b:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      ns:TooltipAddLine(k.label, 1, 1, 1)
      ns:TooltipAddLine(KIND_TIP[k.key], nil, nil, nil, true)
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.chips[k.key] = b
  end

  -- Row 2: least profit, only known recipes, search, refresh.
  local lt = T:Text(f, 12, T.dim)
  lt:SetPoint("TOPLEFT", 2, -34)
  lt:SetText("Least profit")
  f.least = T:Dropdown(f, 80, function(v) S().least = v; refresh() end)
  f.least:SetPoint("LEFT", lt, "RIGHT", 8, 0)
  f.least:SetOptions(leastOptions())
  f.mine = T:Check(f, function(self) S().mine = self:GetChecked(); refresh() end)
  -- Profession (Frank, November 15: no way to filter by profession). Disenchanting counts as
  -- Enchanting; flips, deals and Booty Bay have none, so they go when one is picked.
  f.prof = T:Dropdown(f, 130, function(v) S().prof = v; refresh() end)
  f.prof:SetPoint("LEFT", f.least, "RIGHT", 10, 0)
  f.mine:SetPoint("LEFT", f.prof, "RIGHT", 14, 0)
  f.mine.label:SetText("Only my recipes")
  f.mine:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    ns:TooltipAddLine("Only my recipes", 1, 1, 1)
    ns:TooltipAddLine("On: only recipes one of your characters knows. Off: also every profession's crafts that sell to a vendor for more than they cost, from recipes none of your characters know yet (marked learn). Hover one for where its recipe data comes from.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  f.mine:HookScript("OnLeave", function() GameTooltip:Hide() end)

  f.refreshBtn = T:Button(f, "Refresh", 80, function() work(); refresh() end, 22)
  f.refreshBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -30)
  f.refreshBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    ns:TooltipAddLine("Work it out again", 1, 1, 1)
    ns:TooltipAddLine("From the prices you have now. It's worked out by itself when you open this tab, if it's more than 2 minutes old.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  f.refreshBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  f.search = T:EditBox(f, 150, "LEFT")
  f.search:SetPoint("RIGHT", f.refreshBtn, "LEFT", -8, 0)
  f.search:SetScript("OnTextChanged", function() refresh() end)
  f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  local hint = T:Text(f.search, 11, T.dim)
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Search names")
  f.search:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)

  -- Row 3: saved filter sets.
  f.setsLabel = T:Text(f, 12, T.dim)
  f.setsLabel:SetPoint("TOPLEFT", 2, -62)
  f.setsLabel:SetText("Saved filters:")
  f.sets = {}
  for i = 1, MAX_SETS do
    local b = T:Button(f, "", 80, nil, 20)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
      if button == "RightButton" then confirmDelete(i) else
        local set = S().sets[i]
        if set then applySet(set) end
      end
    end)
    b:HookScript("OnEnter", function(self)
      local set = S().sets[i]
      if not set then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      ns:TooltipAddLine(set.name, 1, 1, 1)
      local kindLabel = "Everything"
      for _, k in ipairs(KINDS) do if k.key == set.kind then kindLabel = k.label end end
      ns:TooltipAddLine(("%s%s, least profit %s%s%s"):format(kindLabel, (set.prof and set.prof ~= "all") and (", " .. set.prof) or "", (set.least or 0) > 0 and ns.MoneyPlain(set.least) or "any",
        set.mine == false and ", every recipe" or "", (set.search or "") ~= "" and (", \"" .. set.search .. "\"") or ""), nil, nil, nil, true)
      ns:TooltipAddLine("Click to use. Right-click to delete.", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.sets[i] = b
  end
  f.setsHint = T:Text(f, 11, T.dim)
  f.setsHint:SetPoint("LEFT", f.setsLabel, "RIGHT", 8, 0)
  f.setsHint:SetText("none yet: pick filters above, then Save these filters.")
  f.saveSet = T:Button(f, "Save these filters", 130, function()
    askName(function(name)
      local g = S()
      if #g.sets >= MAX_SETS then return end
      g.sets[#g.sets + 1] = { name = name:sub(1, 30), kind = g.kind, least = g.least, mine = g.mine, prof = g.prof, search = f.search:GetText() }
      refresh()
    end)
  end, 20)
  f.saveSet:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -59)

  -- The list (left) and How it adds up (right).
  local box = CreateFrame("Frame", nil, f)
  box:SetPoint("TOPLEFT", 0, -86)
  box:SetPoint("BOTTOMRIGHT", -(PANEL_W + 8), 18)
  T:Border(box)
  local header = CreateFrame("Frame", nil, box)
  header:SetPoint("TOPLEFT", 4, -3)
  header:SetPoint("TOPRIGHT", -16, -3)
  header:SetHeight(16)
  f.headers = {}
  local spots = {
    name = { "LEFT", 22, "LEFT" }, kind = { "LEFT", COL.kind, "RIGHTEDGE" }, who = { "LEFT", COL.who, "RIGHTEDGE" },
    cost = { "RIGHT", COL.cost }, brings = { "RIGHT", COL.brings }, profit = { "RIGHT", COL.profit }, count = { "RIGHT", COL.count },
  }
  for _, h in ipairs(HEADERS) do
    local b = CreateFrame("Button", nil, header)
    b:SetHeight(16)
    local fs = T:Text(b, 10, T.dim)
    fs:SetAllPoints()
    local spot = spots[h.key]
    if spot[1] == "LEFT" and spot[3] == "LEFT" then
      b:SetPoint("LEFT", header, "LEFT", spot[2], 0); b:SetWidth(120); fs:SetJustifyH("LEFT")
    elseif spot[3] == "RIGHTEDGE" then
      b:SetPoint("LEFT", header, "RIGHT", spot[2], 0); b:SetWidth(70); fs:SetJustifyH("LEFT")
    else
      b:SetPoint("RIGHT", header, "RIGHT", spot[2], 0); b:SetWidth(h.key == "count" and COL.countW or MONEY_W); fs:SetJustifyH("RIGHT")
    end
    b:SetScript("OnClick", function()
      local s = S().sort
      if s.key == h.key then s.desc = not s.desc
      else s.key, s.desc = h.key, h.key ~= "name" and h.key ~= "kind" and h.key ~= "who" end
      refresh()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      ns:TooltipAddLine(h.label, 1, 1, 1)
      ns:TooltipAddLine(h.tip, nil, nil, nil, true)
      ns:TooltipAddLine("Click to sort by it, again to reverse.", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.headers[#f.headers + 1] = { key = h.key, label = h.label, fs = fs }
  end
  f.list = { rows = {} }
  f.list.sf, f.list.content = T:Scroll(box)
  f.list.sf:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -2)
  f.list.sf:SetPoint("BOTTOMRIGHT", -3, 3)
  f.empty = T:Text(box, 12, T.dim)
  f.empty:SetPoint("CENTER")
  f.empty:SetWidth(360)
  f.status = T:Text(f, 11, T.dim)
  f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 2)
  f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PANEL_W + 8), 2)
  f.status:SetJustifyH("LEFT")
  f.status:SetWordWrap(false)

  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPRIGHT", 0, -86)
  p:SetPoint("BOTTOMRIGHT", 0, 0)
  p:SetWidth(PANEL_W)
  T:Border(p)
  T:Fill(p, { 1, 1, 1, 0.02 })
  f.panel = p
  p.title = T:Text(p, 13)
  p.title:SetPoint("TOPLEFT", 8, -8)
  p.title:SetWidth(PANEL_W - 16)
  p.title:SetJustifyH("LEFT")
  p.title:SetWordWrap(false)
  p.countLabel = T:Text(p, 11, T.dim)
  p.countLabel:SetPoint("TOPLEFT", 8, -32)
  p.countLabel:SetText("Crafts")
  -- The explanation the panel used to start with, on a hover (Frank: the panel was busy).
  local countHover = CreateFrame("Frame", nil, p)
  countHover:SetAllPoints(p.countLabel)
  countHover:EnableMouse(true)
  countHover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ns:TooltipAddLine("How many crafts", 1, 1, 1)
    ns:TooltipAddLine("The materials are worked out for this many crafts, the cheapest way for that many: each one from your bags, the next listing on the auction house, a vendor, or made from its own materials, whichever is cheapest next, and nothing counted twice. It starts at what's listed cheaply enough and, for an auction house craft, about a day's sales.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  countHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p.count = T:Number(p, { min = 1, max = PLAN_MAX, step = 1 }, function(v)
    local r = selectedRow()
    if r then planN[r.key] = math.floor(v) end
    drawPanel()
  end)
  p.count:SetPoint("LEFT", p.countLabel, "RIGHT", 8, 0)
  p.ownedFree = T:Check(p, function() drawPanel() end)
  p.ownedFree:SetPoint("TOPLEFT", 8, -52)
  p.ownedFree.label:SetText("Count my bags as paid for")
  p.ownedFree:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ns:TooltipAddLine("Count my bags as paid for", 1, 1, 1)
    ns:TooltipAddLine("Off: materials in your bags are used first, at what they'd sell for (they aren't free: you could sell them). On: they cost nothing here.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  p.ownedFree:HookScript("OnLeave", function() GameTooltip:Hide() end)
  f.ownedFree = p.ownedFree
  p.sf, p.content = T:Scroll(p)
  p.lines = {}
  p.add = T:Button(p, "Add materials to a shopping list", PANEL_W - 16, addToList, 24)
  p.add:SetPoint("BOTTOMLEFT", 8, 34)
  p.add:SetPrimary(true)
  p.price = T:Button(p, "Price window", PANEL_W - 16, function()
    local r = selectedRow()
    if r and ns.ShowPriceWindow then ns:ShowPriceWindow(r.id) end
  end, 22)
  p.price:SetPoint("BOTTOMLEFT", 8, 6)

  f:SetScript("OnShow", function()
    if not workedAt or redo or time() - workedAt > STALE then work() end
    refresh()
  end)
  f:SetScript("OnSizeChanged", function() if f:IsVisible() then refresh() end end)
  return f
end

refresh = function()
  if not (f and f:IsVisible()) then return end
  if not rows then work() end
  local g = S()
  f.least:SetValue(g.least)
  -- The professions in the list (and the one picked, even when none of its rows are left).
  local profs, seen = {}, {}
  for _, r in ipairs(rows or {}) do
    if r.prof and not seen[r.prof] then seen[r.prof] = true; profs[#profs + 1] = r.prof end
  end
  if g.prof ~= "all" and not seen[g.prof] then profs[#profs + 1] = g.prof end
  table.sort(profs)
  local opts = { { value = "all", label = "All professions" } }
  for _, p in ipairs(profs) do opts[#opts + 1] = { value = p, label = p } end
  f.prof:SetOptions(opts)
  f.prof:SetValue(g.prof)
  f.mine:SetChecked(g.mine)
  drawChips()
  drawSets()
  drawList()
  drawPanel()
end

function ns:RefreshGoldMaking() refresh() end
function ns:ReworkGoldMaking()
  generation = generation + 1
  ns.StopSlices(working)
  working, rows = nil, nil
  refresh()
end
ns._goldMakingTest = { work = function() work() end, rows = function() return rows, working end }   -- (tests)
