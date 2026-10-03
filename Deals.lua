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

local LEVEL_ORDER = { thin = 1, fair = 2, good = 3 }

local function dim(t) return "|cff888888" .. t .. "|r" end

local function sortState()
  local s = ns.db.settings.dealsSort
  if not s.key then s.key, s.desc = "total", true end
  return s
end

local f
local rows, headers = {}, {}

-- The columns shown (a column marked debugOnly only with /fl debug on).
local function shownColumns()
  local out = {}
  for _, c in ipairs(COLUMNS) do
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

local function showTip(self)
  local d = self.deal
  if not d then return end
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
    if ns:SearchAuctionHouse(d.id) then
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
  return d[key] or 0
end

function ns:RefreshDeals()
  if not f or not f:IsShown() then return end
  local set = ns.db.settings
  f.thin:SetChecked(set.dealShowThin)

  -- Filter by kind and by name (owner, October 2: 193 deals is too many to read).
  local kind = set.dealKind or "all"
  local search = (f.search and f.search:GetText() or ""):lower()
  local list, hidden, filtered, newest = {}, 0, 0, nil
  for _, d in ipairs(ns:FindDeals(MAX_AGE)) do
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
    if va == vb then return a.total > b.total end
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

  if #list == 0 and filtered > 0 then
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

  local parts = { ("%d %s"):format(#list, #list == 1 and "deal" or "deals") }
  if hidden > 0 then
    parts[#parts + 1] = ("%d hidden (thin data, prices that dropped, or under %s profit)"):format(hidden, ns.Money(set.dealUsualMin or 0))
  end
  if filtered > 0 then parts[#parts + 1] = ("%d filtered out"):format(filtered) end
  if newest then parts[#parts + 1] = "prices from " .. date("%H:%M", newest) end
  if #list > MAX_ROWS then parts[#parts + 1] = ("showing the first %d"):format(MAX_ROWS) end
  f.summary:SetText(table.concat(parts, ", ") .. ". Rules in Settings, Deal alerts.")
end

ns.RefreshDeals = ns.Timed("Deals tab", ns.RefreshDeals)
