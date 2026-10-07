local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Deals tab: listings well below an item's usual price, each with why it's a deal
-- (hover) and how sure that is. Vendor flips (below what a vendor pays) have their
-- own tab; these are a bet that the item resells, so the tab shows as much as it
-- can: usual price and its spread, days of data, how many are usually listed, the
-- next listing up, and profit after the auction house cut. Click to search the AH.
-- The judging is in Shuffles.lua (FindDeals, DealExplain).
---------------------------------------------------------------------------
local ROW_HEIGHT = 20
local MAX_ROWS = 300
local MAX_AGE = 3600   -- prices from the last hour (alerts use the last 10 minutes)

local COLUMNS = {
  { key = "item", label = "Item" },
  { key = "price", label = "Now", width = 80, right = true },
  { key = "worth", label = "Usual low", width = 80, right = true },   -- the usual cheapest price
  { key = "pct", label = "Below", width = 46, right = true },
  { key = "listed", label = "Cheap", width = 44, right = true },
  { key = "sold", label = "Sells", width = 60, right = true },   -- the sell speed rating
  { key = "each", label = "Profit each", width = 80, right = true },
  { key = "total", label = "Profit all", width = 84, right = true },
  { key = "level", label = "Sure", width = 70 },
}

-- The Booty Bay view (owner, October 5): the neutral auction house against yours, each
-- after its own cut (15% there, yours here). Its prices stay in their own market and
-- only this view (and an optional tooltip line) reads them (Values.lua NeutralCompare).
local NEUTRAL_COLUMNS = {
  { key = "item", label = "Item" },
  { key = "there", label = "Booty Bay", width = 80, right = true },
  { key = "here", label = "Here", width = 80, right = true },
  { key = "better", label = "Better by", width = 80, right = true },
  { key = "npct", label = "%", width = 46, right = true },
  { key = "lthere", label = "Listed there", width = 80, right = true },
  { key = "lhere", label = "Listed here", width = 80, right = true },   -- (UI pass, October 6: two "Here" columns)
}
local NEUTRAL_MIN = 0.10   -- at least 10% better after both cuts
-- Listings needed on the side you'd sell to, unless "Show thin data too" (owner's
-- screenshot, October 5: one Bauxite listed at 55g at Booty Bay read as 44,637% better;
-- one listing is someone's asking price, not what it sells for).
local NEUTRAL_LISTED = 3

local LEVEL_ORDER = { thin = 1, fair = 2, good = 3 }

local function dim(t) return "|cff888888" .. t .. "|r" end

local function neutralMode() return ns.db.settings.dealsMode == "neutral" end

local function sortState()
  local key = neutralMode() and "neutralSort" or "dealsSort"
  ns.db.settings[key] = ns.db.settings[key] or {}
  local s = ns.db.settings[key]
  if not s.key then s.key, s.desc = neutralMode() and "better" or "total", true end
  return s
end

local f
local rows, headers = {}, {}

-- The columns shown (a column marked debugOnly only with /fl debug on).
local function shownColumns()
  local out = {}
  for _, c in ipairs(neutralMode() and NEUTRAL_COLUMNS or COLUMNS) do
    if not c.debugOnly or ns.db.settings.debug then out[#out + 1] = c end
  end
  return out
end

local function columnLayout(cols, width)
  local fixed = 0
  for _, c in ipairs(cols) do fixed = fixed + (c.width or 0) + 8 end
  local x, out = 4, {}
  for _, c in ipairs(cols) do
    local w = c.width or math.max(120, width - fixed - 4)
    out[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  return out
end

function ns:BuildDeals(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  f.intro = T:Text(f, 11, T.dim)
  f.intro:SetPoint("TOPLEFT", 4, -2)
  f.intro:SetPoint("RIGHT", f, "RIGHT", -220, 0)
  f.intro:SetJustifyH("LEFT")
  f.intro:SetText("Listings well below the price they're usually cheapest at, to buy and resell. Hover a deal for why it's one; "
    .. "click it to search the auction house. Items below what a vendor pays are in the Buy queue at the auction house.")

  f.thin = T:Check(f, function(self)
    ns.db.settings.dealShowThin = self:GetChecked()
    ns:RefreshDeals()
  end)
  f.thin:SetPoint("TOPRIGHT", -150, -4)
  f.thin.label:SetText("Show thin data too")
  -- Booty Bay: which way round.
  f.dir = T:Choice(f, { { value = "sell", label = "Sells for more there" }, { value = "buy", label = "Cheaper there" } },
    function(v) ns.db.settings.neutralDir = v; ns:RefreshDeals() end)
  f.dir:SetPoint("TOPRIGHT", -4, -2)

  -- Deals, or the Booty Bay comparison.
  f.mode = T:Choice(f, { { value = "deals", label = "Deals" }, { value = "neutral", label = "Booty Bay" } }, function(v)
    ns.db.settings.dealsMode = v
    f.sf:SetVerticalScroll(0)
    ns:RefreshDeals()
  end)
  f.mode:SetPoint("TOPRIGHT", -4, -42)
  f.mode:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Deals or Booty Bay", 1, 1, 1)
    GameTooltip:AddLine("Booty Bay compares the neutral auction house (Booty Bay, Gadgetzan, Everlook) with yours, each after its own cut: 15% there. Its prices come from opening it and scanning there, and are kept apart from yours everywhere else.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  f.mode:HookScript("OnLeave", function() GameTooltip:Hide() end)

  -- Filter: which kind of item, and a name search.
  f.kind = T:Choice(f, { { value = "all", label = "All" }, { value = "goods", label = "Materials" },
    { value = "gear", label = "Gear" }, { value = "other", label = "Other" } }, function(value)
    ns.db.settings.dealKind = value
    ns:RefreshDeals()
  end)
  f.kind:SetPoint("TOPLEFT", 4, -42)
  f.kind:SetValue(ns.db.settings.dealKind or "all")
  f.search = T:EditBox(f, 180, "LEFT")
  f.search:SetPoint("LEFT", f.kind, "RIGHT", 12, 0)
  local hint = T:Text(f.search, 11, T.section)
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Search by name")
  -- Redraw once you pause typing, not on every letter (each redraw takes about 0.1 s).
  local pending
  f.search:SetScript("OnTextChanged", function(self)
    hint:SetShown(self:GetText() == "" and not self:HasFocus())
    if pending then pending:Cancel() end
    pending = C_Timer.NewTimer(0.3, function() pending = nil; ns:RefreshDeals() end)
  end)
  f.search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  f.search:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
  f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

  f.header = CreateFrame("Frame", nil, f)
  f.header:SetPoint("TOPLEFT", 0, -70)
  f.header:SetPoint("TOPRIGHT", 0, -70)
  f.header:SetHeight(22)
  T:Fill(f.header, { 1, 1, 1, 0.05 })

  f.sf, f.content = T:Scroll(f)
  f.sf:SetPoint("TOPLEFT", 0, -94)
  f.sf:SetPoint("BOTTOMRIGHT", 0, 22)
  f.empty = T:Text(f.content, 12, T.dim)
  f.empty:SetPoint("TOPLEFT", 8, -8)
  f.empty:SetPoint("RIGHT", f.content, "RIGHT", -8, 0)
  f.empty:SetJustifyH("LEFT")

  f.summary = T:Text(f, 11, T.dim)
  f.summary:SetPoint("BOTTOMLEFT", 4, 2)
  f.summary:SetPoint("RIGHT", f, "RIGHT", -4, 0)
  f.summary:SetJustifyH("LEFT")
  f.summary:SetWordWrap(false)
  return f
end

local function getHeader(i)
  if not headers[i] then
    local h = CreateFrame("Button", nil, f.header)
    h.fs = T:Text(h, 11, T.dim)
    h.fs:SetAllPoints()
    h:SetScript("OnClick", function(self)
      local s = sortState()
      if s.key == self.key then s.desc = not s.desc else s.key, s.desc = self.key, self.key ~= "item" end
      ns:RefreshDeals()
    end)
    headers[i] = h
  end
  return headers[i]
end

local function neutralTip(self, d)
  local a = T.accent
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ns.ItemName(d.id) or "?", 1, 1, 1)
  GameTooltip:AddLine("Allows for one listing that doesn't sell (its deposit is lost).", 0.7, 0.7, 0.7, true)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Booty Bay (15% cut)", a[1], a[2], a[3])
  GameTooltip:AddDoubleLine("  Cheapest", ns.Money(d.there) .. " |cff999999" .. d.listedThere .. " listed|r", 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("  Selling there brings", ns.Money(d.netThere), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("  Seen", ns.Age(d.t), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddLine(("Your auction house (%g%% cut)"):format(ns:AHCut(false) * 100), a[1], a[2], a[3])
  GameTooltip:AddDoubleLine("  Cheapest", ns.Money(d.here) .. " |cff999999" .. d.listedHere .. " listed|r", 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("  Selling here brings", ns.Money(d.netHere), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddLine(" ")
  if d.dir == "buy" then
    GameTooltip:AddLine(("Buy at Booty Bay for %s, sell here for %s after the cut: %s more each."):format(
      ns.Money(d.there), ns.Money(d.netHere), ns.Money(d.buyProfit)), 0.5, 0.83, 0.61, true)
  else
    GameTooltip:AddLine(("Selling at Booty Bay instead brings %s more each."):format(ns.Money(d.gain)), 0.5, 0.83, 0.61, true)
  end
  GameTooltip:AddLine("Prices move: Booty Bay's are only as fresh as your last visit there.", 0.5, 0.5, 0.5, true)
  GameTooltip:Show()
end

local function showTip(self)
  local d = self.deal
  if not d then return end
  if d.neutral then return neutralTip(self, d) end
  local a = T.accent
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddDoubleLine(ns.ItemName(d.id) or "?", ("%d%% below usual"):format(math.floor(d.pct * 100 + 0.5)),
    1, 1, 1, 0.5, 0.83, 0.61)
  for _, e in ipairs(ns:DealExplain(d)) do
    if e.head then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(e.head, a[1], a[2], a[3])
    elseif e.note then
      GameTooltip:AddLine(e.note, e.color[1], e.color[2], e.color[3], true)
    else
      GameTooltip:AddDoubleLine("  " .. e[1], e[2], 0.7, 0.7, 0.7, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to search the auction house.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, f.content)
  r:SetHeight(ROW_HEIGHT)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cells = {}
  r:SetScript("OnEnter", showTip)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    local d = self.deal
    if not d then return end
    if d.neutral then
      if not ns:SearchAuctionHouse(d.id) then ns:Print("Open the auction house, then click an item to search for it.") end
    elseif ns:SearchAuctionHouse(d.id) then
      ns:Print(("%s: %d at %s or less (usually %s). Hover the deal for the details."):format(
        ns.ItemName(d.id) or "?", d.listed, ns.Money(d.limit), ns.Money(d.worth)))
    else
      ns:Print("Open the auction house, then click a deal to search for it.")
    end
  end)
  rows[i] = r
  return r
end

local function cell(r, key)
  if not r.cells[key] then
    local fs = T:Text(r, 11)
    fs:SetWordWrap(false)
    r.cells[key] = fs
  end
  return r.cells[key]
end

local function show(d, key)
  if key == "item" then return ns.ItemName(d.id) or ("item " .. d.id) end
  if key == "there" or key == "here" then return ns.Money(d[key]) end
  if key == "better" then return "|cff7fd39c" .. ns.Money(d.better) .. "|r" end
  -- Ten times or more as "x12" (owner's screenshot: "44637..." was cut off).
  if key == "npct" then
    if d.npct >= 9 then return ("x%d"):format(math.floor(d.npct + 1)) end
    return ("%d%%"):format(math.floor(d.npct * 100 + 0.5))
  end
  if key == "lthere" then return tostring(d.listedThere) end
  if key == "lhere" then return tostring(d.listedHere) end
  if key == "price" or key == "worth" then return ns.Money(d[key]) end
  if key == "pct" then return ("%d%%"):format(math.floor(d.pct * 100 + 0.5)) end
  if key == "listed" then return tostring(d.listed) end
  if key == "sold" then
    -- The rating's first word (Fast, Steady, Slow, Rare, No); "?" until there are 3
    -- hours of scans to judge by.
    if not d.speed then return dim("?") end
    local short = d.speed.key == "none" and "None" or d.speed.label:match("^(%a+)")
    return ("|cff%s%s|r"):format(d.speed.color, short)
  end
  if key == "each" or key == "total" then
    local v = d[key]
    return v > 0 and ("|cff7fd39c" .. ns.Money(v) .. "|r") or ("|cffee8597" .. ns.Money(0) .. "|r")
  end
  if key == "level" then
    local days = d.stats and d.stats.points
    return (ns.DEAL_LEVEL_TEXT[d.level] or d.level) .. (days and dim((" %dd"):format(days)) or dim(" TSM"))
  end
  return ""
end

local function sortValue(d, key)
  if key == "item" then return (ns.ItemName(d.id) or ""):lower() end
  if key == "level" then return LEVEL_ORDER[d.level] * 1000 + (d.stats and d.stats.points or 0) end
  if key == "sold" then return d.soldPerDay or -1 end
  if key == "lthere" then return d.listedThere or 0 end
  if key == "lhere" then return d.listedHere or 0 end
  return d[key] or 0
end

-- The Booty Bay rows: items at least NEUTRAL_MIN better one way round, after both cuts.
local function neutralList(dir, kind, search, thin)
  local realm = GetRealmName() or "?"
  local list, filtered, newest, any, hidden = {}, 0, nil, false, 0
  for id in pairs(ns.db.prices[realm .. "|Neutral"] or {}) do
    any = true
    local c = ns:NeutralCompare(id)
    if c then
      newest = math.max(newest or 0, c.t or 0)
      local better = dir == "buy" and c.buyProfit or c.gain
      local base = dir == "buy" and c.there or c.netHere
      -- Selling there: enough listed there to trust its price; buying there to sell
      -- here: enough listed here.
      local listed = dir == "buy" and c.listedHere or c.listedThere
      if better > 0 and base > 0 and better / base >= NEUTRAL_MIN and not thin and listed < NEUTRAL_LISTED then
        hidden = hidden + 1
      elseif better > 0 and base > 0 and better / base >= NEUTRAL_MIN then
        if (kind == "all" or ns:ItemKind(id) == kind)
          and (search == "" or (ns.ItemName(id) or ""):lower():find(search, 1, true)) then
          c.id, c.neutral, c.dir, c.better, c.npct = id, true, dir, better, better / base
          list[#list + 1] = c
        else
          filtered = filtered + 1
        end
      end
    end
  end
  return list, filtered, newest, any, hidden
end

function ns:RefreshDeals()
  if not f or not f:IsShown() then return end
  local set = ns.db.settings
  local neutral = neutralMode()
  f.thin:SetChecked(set.dealShowThin)
  f.mode:SetValue(neutral and "neutral" or "deals")
  -- Booty Bay: "Show thin data too" sits left of the two direction buttons.
  f.thin:ClearAllPoints()
  f.thin:SetPoint("TOPRIGHT", neutral and -(math.max(f.mode:GetWidth(), 180) + 150) or -150, neutral and -44 or -4)
  f.dir:SetShown(neutral)
  f.dir:SetValue(set.neutralDir or "sell")
  f.intro:SetPoint("RIGHT", f, "RIGHT", neutral and -(math.max(f.dir:GetWidth(), 250) + 16) or -220, 0)
  f.intro:SetText(neutral
    and "Booty Bay against your auction house, each after its own cut (15% there): items worth 10% more to sell there, or cheaper to buy there. Hover for the numbers."
    or ("Listings well below the price they're usually cheapest at, to buy and resell. Hover a deal for why it's one; "
      .. "click it to search the auction house. Items below what a vendor pays are in the Buy queue at the auction house."))

  -- Filter by kind and by name (owner, October 2: 193 deals is too many to read).
  local kind = set.dealKind or "all"
  local search = (f.search and f.search:GetText() or ""):lower()
  local list, hidden, filtered, newest = {}, 0, 0, nil
  local anyNeutral
  if neutral then
    list, filtered, newest, anyNeutral, hidden = neutralList(set.neutralDir or "sell", kind, search, set.dealShowThin)
  end
  for _, d in ipairs(neutral and {} or ns:FindDeals(MAX_AGE)) do
    if d.kind == "usual" then
      local keep = (kind == "all" or ns:ItemKind(d.id) == kind)
        and (search == "" or (ns.ItemName(d.id) or ""):lower():find(search, 1, true))
      if not keep then
        filtered = filtered + 1
      elseif ns:DealShown(d) then
        list[#list + 1] = d
      else
        hidden = hidden + 1
      end
      newest = math.max(newest or 0, d.t or 0)
    end
  end
  f.filtered = filtered

  local sort = sortState()
  table.sort(list, function(a, b)
    local va, vb = sortValue(a, sort.key), sortValue(b, sort.key)
    if va == vb then return (a.total or a.better or 0) > (b.total or b.better or 0) end
    if sort.desc then return va > vb end
    return va < vb
  end)

  -- Header
  local width = f:GetWidth() - 12
  local cols = shownColumns()
  local lay = columnLayout(cols, width)
  for i, c in ipairs(cols) do
    local h = getHeader(i)
    h.key = c.key
    h:ClearAllPoints()
    h:SetPoint("LEFT", f.header, "LEFT", lay[c.key].x, 0)
    h:SetSize(lay[c.key].w, 22)
    h.fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
    local sorted = sort.key == c.key
    h.fs:SetText(c.label .. (sorted and (sort.desc and " v" or " ^") or ""))
    local col = sorted and { T.accent[1], T.accent[2], T.accent[3], 1 } or T.dim
    h.fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    h:Show()
  end
  for i = #cols + 1, #headers do headers[i]:Hide() end

  -- Rows
  f.content:SetWidth(width)
  local n = math.min(#list, MAX_ROWS)
  for i = 1, n do
    local d, r = list[i], getRow(i)
    r.deal = d
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    local icon = ns:ItemIcon(d.id)
    for key, fs in pairs(r.cells) do fs:SetShown(lay[key] ~= nil) end
    for _, c in ipairs(cols) do
      local fs = cell(r, c.key)
      fs:Show()
      fs:ClearAllPoints()
      local x, w = lay[c.key].x, lay[c.key].w
      if c.key == "item" then
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "LEFT", x, 0)
        r.icon:SetTexture(icon)
        x, w = x + 18, w - 18
      end
      fs:SetPoint("LEFT", r, "LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
      fs:SetText(show(d, c.key))
    end
    r.icon:SetShown(icon ~= nil)
    r:Show()
  end
  for i = n + 1, #rows do rows[i]:Hide() end

  if neutral and #list == 0 and filtered == 0 then
    f.empty:SetText(anyNeutral
      and ((set.neutralDir == "buy") and "Nothing is at least 10% cheaper at Booty Bay than it sells for here, after the cut."
        or "Nothing sells for at least 10% more at Booty Bay than here, after both cuts.")
      or "No Booty Bay prices yet. Open the auction house in Booty Bay, Gadgetzan or Everlook and run a full scan there: its prices are kept apart from yours.")
  elseif #list == 0 and filtered > 0 then
    f.empty:SetText(("Nothing here matches the filter: %d %s hidden by it. Click All, or clear the search box."):format(
      filtered, filtered == 1 and "deal is" or "deals are"))
  elseif #list == 0 then
    f.empty:SetText(newest and "No deals that pass the checks right now. Tick \"Show thin data too\" to see the doubtful ones."
      or "No deals yet. Deals need prices from the last hour (a full scan or the flip watch) and at least 4 days of scans "
      .. "to know an item's usual price (or TSM installed).")
  end
  f.empty:SetShown(#list == 0)
  f.content:SetHeight(math.max(n * ROW_HEIGHT, 30))
  f.sf.UpdateScrollBar()

  if neutral then
    local parts = { ("%d %s"):format(#list, #list == 1 and "item" or "items") }
    if hidden > 0 then parts[#parts + 1] = ("%d hidden (under %d listed)"):format(hidden, NEUTRAL_LISTED) end
    if filtered > 0 then parts[#parts + 1] = ("%d filtered out"):format(filtered) end
    if newest then parts[#parts + 1] = "Booty Bay prices from " .. ns.Age(newest) end
    if #list > MAX_ROWS then parts[#parts + 1] = ("showing the first %d"):format(MAX_ROWS) end
    f.summary:SetText(table.concat(parts, ", ") .. ". Kept apart from your prices; tooltips can show it (Settings, Tooltips).")
    return
  end
  local parts = { ("%d %s"):format(#list, #list == 1 and "deal" or "deals") }
  if hidden > 0 then
    parts[#parts + 1] = ("%d hidden (thin data, prices that dropped, or under %s profit)"):format(hidden, ns.Money(set.dealUsualMin or 0))
  end
  if filtered > 0 then parts[#parts + 1] = ("%d filtered out"):format(filtered) end
  if newest then parts[#parts + 1] = "prices from " .. date("%H:%M", newest) end
  if #list > MAX_ROWS then parts[#parts + 1] = ("showing the first %d"):format(MAX_ROWS) end
  f.summary:SetText(table.concat(parts, ", ") .. ". Rules in Settings, Global settings, Flips and deals.")
end

ns.RefreshDeals = ns.Timed("Deals tab", ns.RefreshDeals)
