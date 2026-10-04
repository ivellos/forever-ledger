local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Ledger tab: every transaction in one list (All), every sale and purchase (auction
-- house and vendor), a resale summary for items both bought and sold, and other money
-- in and out. Filter by time, character and item name; click a column heading to sort.
-- Select rows (click, Shift-click, Ctrl-click or drag) to see their total (owner,
-- October 3: "a single view for all transactions" and "select several to see the
-- gold in or out").
---------------------------------------------------------------------------
local DAY = 86400
local ROW_HEIGHT = 20
local MAX_ROWS = 500
local RANGES = {
  { key = "week", label = "Week", secs = 7 * DAY },
  { key = "month", label = "Month", secs = 30 * DAY },
  { key = "3months", label = "3 months", secs = 91 * DAY },
  { key = "year", label = "Year", secs = 365 * DAY },
  { key = "all", label = "All" },
}
local SUBTABS = {
  { key = "all", label = "All" },
  { key = "sales", label = "Sales" },
  { key = "purchases", label = "Purchases" },
  { key = "resale", label = "Resale" },
  { key = "other", label = "Other" },
}
local OTHER = {
  ahFee = "Auction house fees", repair = "Repairs", mailIn = "Mail received", mailOut = "Mail sent",
  tradeIn = "Trade received", tradeOut = "Trade given", loot = "Loot", quest = "Quests",
  training = "Training", flight = "Flights", otherIn = "Other income", otherOut = "Other spending",
}
local OTHER_IN = { mailIn = true, tradeIn = true, loot = true, quest = true, otherIn = true }

local COLUMNS = {
  all = {
    { key = "t", label = "Time", width = 96 },
    { key = "kind", label = "Type", width = 118 },
    { key = "item", label = "Item" },
    { key = "qty", label = "Qty", width = 40, right = true },
    { key = "each", label = "Each", width = 86, right = true },
    { key = "amount", label = "Amount", width = 100, right = true },
    { key = "char", label = "Character", width = 84 },
  },
  sales = {
    { key = "t", label = "Time", width = 96 },
    { key = "item", label = "Item" },
    { key = "qty", label = "Qty", width = 40, right = true },
    { key = "each", label = "Each", width = 86, right = true },
    { key = "total", label = "Total", width = 96, right = true },
    { key = "where", label = "Where", width = 60 },
    { key = "who", label = "Buyer", width = 96 },
    { key = "char", label = "Character", width = 84 },
  },
  purchases = {
    { key = "t", label = "Time", width = 96 },
    { key = "item", label = "Item" },
    { key = "qty", label = "Qty", width = 40, right = true },
    { key = "each", label = "Each", width = 86, right = true },
    { key = "total", label = "Total", width = 96, right = true },
    { key = "where", label = "Where", width = 60 },
    { key = "char", label = "Character", width = 84 },
  },
  resale = {
    { key = "item", label = "Item" },
    { key = "bought", label = "Bought", width = 56, right = true },
    { key = "avgBuy", label = "Avg buy", width = 90, right = true },
    { key = "sold", label = "Sold", width = 50, right = true },
    { key = "avgSell", label = "Avg sell", width = 90, right = true },
    { key = "profit", label = "Profit", width = 100, right = true },
  },
  other = {
    { key = "t", label = "Day", width = 96 },
    { key = "item", label = "Type" },
    { key = "total", label = "Amount", width = 110, right = true },
    { key = "char", label = "Character", width = 84 },
  },
}

local function dim(t) return "|cff888888" .. t .. "|r" end
local function money(v) return (v < 0 and "-" or "") .. ns.Money(math.abs(v)) end

local function settings()
  local s = ns.db.settings.ledger
  -- (The tab opens on All each time: UI.lua's setView.)
  s.tab = s.tab or "all"
  s.range = s.range or "month"
  s.char = s.char or "all"
  s.sort = s.sort or {}
  return s
end

local function charName(key)
  local c = ns.db.chars[key]
  return (c and c.name) or (key and key:match("^[^-]+")) or "?"
end

local function nameOf(id) return id and ns.ItemName(id) or "Unknown item" end

-- An item's icon from its ID or name (names only work once the game knows the item).
local function iconOf(idOrName)
  if not idOrName then return end
  if type(idOrName) == "number" then return ns:ItemIcon(idOrName) end
  local ok, _, _, _, _, _, _, _, _, _, icon = pcall(ns.GetItemInfo, idOrName)
  return ok and icon or nil
end

-- Seconds ahead of UTC, to turn a local day number back into a time for display.
local function utcOffset()
  local now = time()
  local utc = date("!*t", now)
  utc.isdst = date("*t", now).isdst
  return now - time(utc)
end

---------------------------------------------------------------------------
-- Records for each sub-tab
---------------------------------------------------------------------------
local GROUP_SECONDS = 60

-- Combine trades of the same item, at the same price each, in the same place, by the
-- same character, within a minute of each other (selling 10 oils one by one is one row).
local function groupSimilar(list)
  table.sort(list, function(a, b) return a.t < b.t end)
  local out, last = {}, nil
  for _, r in ipairs(list) do
    if last and not r.month and not last.month and r.item == last.item and r.where == last.where and r.char == last.char and r.who == last.who
      and r.each and last.each and math.abs(r.each - last.each) < 1 and r.t - last.t <= GROUP_SECONDS then
      last.qty = (last.qty or 1) + (r.qty or 1)
      last.total = last.total + r.total
      last.t = r.t
    else
      last = r
      out[#out + 1] = r
    end
  end
  return out
end

local function records(tab, from, charOK, match)
  local out = {}
  local function keep(e) return (e.t or 0) >= from and charOK(e.c) end

  if tab == "sales" or tab == "purchases" or tab == "resale" or tab == "all" then
    local sales, buys = {}, {}
    for _, e in ipairs(ns.db.sales) do
      if keep(e) then
        sales[#sales + 1] = { t = e.t, item = e.n or "?", icon = iconOf(e.n), qty = e.q, total = e.a,
          where = "Auction", who = e.b, char = e.c, kind = "Auction sale" }
      end
    end
    for _, e in ipairs(ns.db.purchases) do
      if keep(e) then
        -- No quantity means a non-commodity purchase, which is always one item.
        buys[#buys + 1] = { t = e.t, id = e.id, item = nameOf(e.id), icon = iconOf(e.id), qty = e.q or 1, total = e.a,
          where = "Auction", char = e.c, kind = "Auction purchase" }
      end
    end
    for _, e in ipairs(ns.db.vendorLog) do
      if keep(e) and e.id then
        local sold = e.s == "sell"
        local r = { t = e.t, id = e.id, item = nameOf(e.id), icon = iconOf(e.id), qty = e.q, total = e.a, where = "Vendor",
          char = e.c, kind = sold and "Sold to vendor" or "Bought from vendor" }
        if sold then sales[#sales + 1] = r else buys[#buys + 1] = r end
      end
    end
    -- Older than 30 days: one line per item and month (History.lua foldLedger).
    for _, m in ipairs(ns.db.ledgerMonths or {}) do
      if keep(m) then
        local auction = m.k == "sale" or m.k == "buy"
        local sold = m.k == "sale" or m.k == "vsell"
        local r = { t = m.t, month = true, id = m.id, item = m.id and nameOf(m.id) or m.n or "?", icon = iconOf(m.id or m.n),
          qty = m.q, total = m.a, where = auction and "Auction" or "Vendor", char = m.c,
          kind = auction and (sold and "Auction sales" or "Auction purchases") or (sold and "Sold to vendors" or "Bought from vendors") }
        if sold then sales[#sales + 1] = r else buys[#buys + 1] = r end
      end
    end
    for _, list in ipairs({ sales, buys }) do
      for _, r in ipairs(list) do r.each = r.qty and r.qty > 0 and r.total / r.qty or nil end
    end

    if tab == "sales" then out = groupSimilar(sales) elseif tab == "purchases" then out = groupSimilar(buys)
    elseif tab == "all" then
      -- Everything, money in (+) and out (-); the other money is added below.
      for _, r in ipairs(groupSimilar(sales)) do r.amount = r.total; out[#out + 1] = r end
      for _, r in ipairs(groupSimilar(buys)) do r.amount = -r.total; out[#out + 1] = r end
    else
      -- Resale: items both bought and sold.
      local by = {}
      local function add(r, sold)
        local x = by[r.item] or { item = r.item, icon = r.icon, bought = 0, boughtTotal = 0, sold = 0, soldTotal = 0 }
        by[r.item] = x
        x.icon = x.icon or r.icon
        local q = r.qty or 1
        if sold then x.sold, x.soldTotal = x.sold + q, x.soldTotal + r.total
        else x.bought, x.boughtTotal = x.bought + q, x.boughtTotal + r.total end
      end
      for _, r in ipairs(sales) do add(r, true) end
      for _, r in ipairs(buys) do add(r, false) end
      for _, x in pairs(by) do
        if x.bought > 0 and x.sold > 0 then
          x.avgBuy, x.avgSell = x.boughtTotal / x.bought, x.soldTotal / x.sold
          x.profit = (x.avgSell - x.avgBuy) * math.min(x.bought, x.sold)
          out[#out + 1] = x
        end
      end
    end
  end
  if tab == "other" or tab == "all" then
    -- Other money: daily totals by type (repairs, mail, loot, quests...). Auction and
    -- vendor money isn't here: the lists above have it item by item.
    local fromDay, offset = ns.LocalDay(from), utcOffset()
    for key, days in pairs(ns.db.money) do
      if charOK(key) then
        for day, src in pairs(days) do
          if day >= fromDay then
            for s, amt in pairs(src) do
              if OTHER[s] then
                local signed = OTHER_IN[s] and amt or -amt
                out[#out + 1] = { t = day * DAY - offset + DAY / 2, day = true, item = tab == "other" and OTHER[s] or "",
                  kind = OTHER[s], total = signed, amount = signed, char = key }
              end
            end
          end
        end
      end
    end
  end

  -- Search: the item's name, or (All) the type too.
  if match ~= "" then
    local kept = {}
    for _, r in ipairs(out) do
      if ((r.item or "") .. " " .. (r.kind or "")):lower():find(match, 1, true) then kept[#kept + 1] = r end
    end
    out = kept
  end
  return out
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local f
local rows, headers = {}, {}
local shown = {}          -- the records on screen, in order (for selecting by row)
local sel = {}            -- [record key] = true: the selected rows
local anchor, dragging    -- the row a Shift-click or drag starts from; a drag under way

-- A key that stays the same for a record across redraws (selections survive them).
local function recKey(rec)
  return ("%s|%s|%s|%s|%s"):format(rec.t or 0, rec.item or "", rec.kind or "", rec.total or rec.profit or 0, rec.char or "")
end

local function columnLayout(cols, width)
  local fixed = 0
  for _, c in ipairs(cols) do fixed = fixed + (c.width or 0) + 8 end
  local x, out = 4, {}
  for _, c in ipairs(cols) do
    local w = c.width or math.max(140, width - fixed - 4)
    out[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  return out
end

-- What a record adds to a total: money in positive, out negative (resale: its profit).
local function signedOf(rec, tab)
  if rec.amount then return rec.amount end
  if tab == "resale" then return rec.profit or 0 end
  if tab == "purchases" then return -(rec.total or 0) end
  return rec.total or 0
end

-- The bottom line: the selection's total when rows are selected, else the list's.
local function updateSummary()
  local s = settings()
  local n, inn, out = 0, 0, 0
  for _, rec in ipairs(shown) do
    if sel[recKey(rec)] then
      n = n + 1
      local v = signedOf(rec, s.tab)
      if v >= 0 then inn = inn + v else out = out - v end
    end
  end
  f.clear:SetShown(n > 0)
  if n > 0 then
    local net = inn - out
    f.summary:SetText(("%s%d selected:|r in %s, out %s, net %s"):format(T:AccentCode(), n,
      "|cff7fd39c+" .. ns.Money(math.floor(inn + 0.5)) .. "|r", "|cffee8597-" .. ns.Money(math.floor(out + 0.5)) .. "|r",
      "|cff" .. (net >= 0 and "7fd39c+" or "ee8597-") .. ns.Money(math.floor(math.abs(net) + 0.5)) .. "|r"))
    return
  end
  local total = 0
  for _, rec in ipairs(f.list or {}) do total = total + signedOf(rec, s.tab) end
  local words = { all = "entries", sales = "sales", purchases = "purchases", resale = "items bought and sold", other = "entries" }
  local label = (s.tab == "resale" and "profit") or ((s.tab == "other" or s.tab == "all") and "net") or "total"
  local shownTotal = s.tab == "purchases" and -total or total
  local extra = (f.list and #f.list > MAX_ROWS) and dim((" (showing the first %d)"):format(MAX_ROWS)) or ""
  f.summary:SetText(("%d %s, %s %s%s   %s"):format(f.list and #f.list or 0, words[s.tab] or "entries", label,
    money(math.floor(shownTotal + 0.5)), extra, dim("Click, Shift-click or drag rows to total them.")))
end

-- Selected rows get the accent tint.
local function paint()
  for i, r in ipairs(rows) do
    local rec = shown[i]
    r.sel:SetShown(rec ~= nil and r:IsShown() and sel[recKey(rec)] or false)
  end
  updateSummary()
end

local function selectRange(a, b)
  if a > b then a, b = b, a end
  for i = a, b do if shown[i] then sel[recKey(shown[i])] = true end end
end

local function clearSelection()
  wipe(sel)
  anchor, dragging = nil, false
end

function ns:BuildLedger(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  f.subtabs = {}
  local prev
  for _, st in ipairs(SUBTABS) do
    local b = T:Tab(f, st.label, function() settings().tab = st.key; clearSelection(); ns:RefreshLedger() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("TOPLEFT", -6, 4) end
    f.subtabs[st.key] = b
    prev = b
  end
  f.range = T:Choice(f, (function()
    local o = {}
    for _, r in ipairs(RANGES) do o[#o + 1] = { value = r.key, label = r.label } end
    return o
  end)(), function(v) settings().range = v; clearSelection(); ns:RefreshLedger() end)
  f.range:SetPoint("TOPRIGHT", 0, 0)

  f.searchLabel = T:Text(f, 12, T.dim)
  f.searchLabel:SetPoint("TOPLEFT", 4, -40)
  f.searchLabel:SetText("Search")
  f.search = T:EditBox(f, 180, "LEFT")
  f.search:SetPoint("LEFT", f.searchLabel, "RIGHT", 8, 0)
  f.search:SetScript("OnTextChanged", function() clearSelection(); ns:RefreshLedger() end)
  f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  f.charLabel = T:Text(f, 12, T.dim)
  f.charLabel:SetPoint("LEFT", f.search, "RIGHT", 18, 0)
  f.charLabel:SetText("Characters")

  f.header = CreateFrame("Frame", nil, f)
  f.header:SetPoint("TOPLEFT", 0, -66)
  f.header:SetPoint("TOPRIGHT", 0, -66)
  f.header:SetHeight(22)
  T:Fill(f.header, { 1, 1, 1, 0.05 })

  f.sf, f.content = T:Scroll(f)
  f.sf:SetPoint("TOPLEFT", 0, -90)
  f.sf:SetPoint("BOTTOMRIGHT", 0, 24)
  f.empty = T:Text(f.content, 12, T.dim)
  f.empty:SetPoint("TOPLEFT", 8, -8)
  f.empty:SetPoint("RIGHT", f.content, "RIGHT", -8, 0)
  f.empty:SetJustifyH("LEFT")

  f.summary = T:Text(f, 12)
  f.summary:SetPoint("BOTTOMLEFT", 4, 4)
  f.summary:SetJustifyH("LEFT")
  f.summary:SetWordWrap(false)
  -- Clear the selection (right-clicking a row does the same).
  f.clear = T:Button(f, "Clear selection", 110, function() clearSelection(); paint() end, 20)
  f.clear:SetPoint("BOTTOMRIGHT", 0, 2)
  f.clear:Hide()
  f.summary:SetPoint("RIGHT", f.clear, "LEFT", -8, 0)
  return f
end

-- Which characters: a dropdown (Dashboard.lua's ns:CharacterOptions).
local function charChoice()
  if not f.chars then
    f.chars = T:Dropdown(f, 200, function(v) settings().char = v; clearSelection(); ns:RefreshLedger() end)
    f.chars:SetPoint("LEFT", f.charLabel, "RIGHT", 10, 0)
  end
  f.chars:SetOptions(ns:CharacterOptions())
end

local function getHeader(i)
  if not headers[i] then
    local h = CreateFrame("Button", nil, f.header)
    h.fs = T:Text(h, 11, T.dim)
    h.fs:SetAllPoints()
    h:SetScript("OnClick", function(self)
      local s = settings()
      local sort = s.sort[s.tab] or {}
      if sort.key == self.key then sort.desc = not sort.desc else sort.key, sort.desc = self.key, self.key ~= "item" and self.key ~= "kind" end
      s.sort[s.tab] = sort
      ns:RefreshLedger()
    end)
    headers[i] = h
  end
  return headers[i]
end

-- The text shown for one value.
local function show(rec, key)
  local v = rec[key]
  if key == "t" then return dim(date((rec.month and "%B %Y") or (rec.day and "%b %d") or "%b %d %H:%M", v)) end
  if key == "char" then return charName(v) end
  if key == "qty" or key == "bought" or key == "sold" then return v and tostring(v) or dim(rec.day and "" or "?") end
  if key == "each" or key == "avgBuy" or key == "avgSell" then return v and ns.Money(math.floor(v + 0.5)) or dim(rec.day and "" or "?") end
  if key == "total" then return rec.day and ("|cff" .. (v >= 0 and "7fd39c" or "ee8597") .. money(v) .. "|r") or ns.Money(v) end
  if key == "amount" or key == "profit" then
    return "|cff" .. (v >= 0 and "7fd39c+" or "ee8597-") .. ns.Money(math.floor(math.abs(v) + 0.5)) .. "|r"
  end
  if key == "who" then return v or dim("-") end
  if key == "item" and v == "" then return dim("-") end
  return v or ""
end

-- Hover: the item's own tooltip where we know it, then the row in full.
local function rowTooltip(r)
  local rec = shown[r.index]
  if not rec then return end
  -- Beside the window, not at the cursor: at the cursor it could run off the screen's
  -- edge (owner's test, October 3).
  GameTooltip:SetOwner(r, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  local scale, right = f:GetEffectiveScale(), f:GetRight() or 0
  if right * scale + 320 < (GetScreenWidth() * UIParent:GetEffectiveScale()) then
    GameTooltip:SetPoint("TOPLEFT", r, "TOPLEFT", f:GetWidth() + 16, 0)
  else
    GameTooltip:SetPoint("TOPRIGHT", r, "TOPLEFT", -16, 0)
  end
  if rec.id then GameTooltip:SetItemByID(rec.id); GameTooltip:AddLine(" ")
  else GameTooltip:AddLine(rec.item ~= "" and rec.item or (rec.kind or "?"), 1, 1, 1) end
  local function line(a, b) if b then GameTooltip:AddDoubleLine(a, b, 0.7, 0.7, 0.7, 1, 1, 1) end end
  line("When", date((rec.month and "%B %Y, month total") or (rec.day and "%b %d, day total") or "%b %d %H:%M", rec.t or 0))
  line("Type", rec.kind)
  if rec.qty and rec.each then line("Quantity", ("%d x %s"):format(rec.qty, ns.Money(math.floor(rec.each + 0.5)))) end
  if rec.amount or rec.total then line("Amount", show(rec, rec.amount and "amount" or "total")) end
  if rec.profit then line("Profit", show(rec, "profit")) end
  line("Buyer", rec.who)
  if rec.char then line("Character", charName(rec.char)) end
  GameTooltip:AddLine("Click to select; Shift-click or drag for several, Ctrl-click to add one. Right-click clears.", 0.5, 0.5, 0.5, true)
  GameTooltip:Show()
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, f.content)
  r:SetHeight(ROW_HEIGHT)
  r:EnableMouse(true)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.sel:SetAllPoints()
  r.sel:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.2)
  r.sel:Hide()
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.05)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cells = {}
  -- Selecting: click one (again to unselect), Shift-click a range, Ctrl-click to add or
  -- take one, or press and drag across rows. Right-click clears.
  r:SetScript("OnMouseDown", function(self, button)
    local rec = shown[self.index]
    if not rec then return end
    if button == "RightButton" then clearSelection(); paint(); return end
    local key = recKey(rec)
    if IsShiftKeyDown() and anchor then
      wipe(sel)
      selectRange(anchor, self.index)
    elseif IsControlKeyDown() then
      sel[key] = not sel[key] or nil
      anchor = self.index
    else
      local only = sel[key] and next(sel, next(sel)) == nil
      wipe(sel)
      if not only then sel[key] = true end
      anchor, dragging = self.index, true
    end
    paint()
  end)
  r:SetScript("OnMouseUp", function() dragging = false end)
  r:SetScript("OnEnter", function(self)
    if dragging and anchor and IsMouseButtonDown("LeftButton") then
      wipe(sel)
      selectRange(anchor, self.index)
      paint()
      return
    end
    dragging = false
    rowTooltip(self)
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

-- What each view says when it's empty, and how to fill it.
local EMPTY = {
  all = "Nothing recorded for these filters yet. Auction sales are logged when you take the money from the mailbox; purchases, vendor trades and other money as they happen.",
  sales = "No sales for these filters yet. Auction sales are logged when you take the money from the mailbox; vendor sales as you sell.",
  purchases = "No purchases for these filters yet. Auction and vendor purchases are logged as you buy.",
  resale = "No items both bought and sold for these filters yet. Once you've bought and sold the same item, its profit shows here.",
  other = "No other money for these filters yet: repairs, mail, trades, loot, quests, training and flights show here by day.",
}

function ns:RefreshLedger()
  if not f or not f:IsShown() then return end
  local s = settings()
  if s.char ~= "all" and not ns.db.chars[s.char] then s.char = "all" end
  if not COLUMNS[s.tab] then s.tab = "all" end
  for key, b in pairs(f.subtabs) do b:SetSelected(key == s.tab) end
  f.range:SetValue(s.range)
  charChoice()
  f.chars:SetValue(s.char)

  -- Records for the filters
  local from = 0
  for _, r in ipairs(RANGES) do if r.key == s.range and r.secs then from = time() - r.secs end end
  local function charOK(c) return s.char == "all" or c == s.char end
  local list = records(s.tab, from, charOK, (f.search:GetText() or ""):lower())
  f.list = list

  local cols = COLUMNS[s.tab]
  local sort = s.sort[s.tab] or { key = s.tab == "resale" and "profit" or "t", desc = true }
  table.sort(list, function(a, b)
    local va, vb = a[sort.key], b[sort.key]
    if type(va) == "string" then va = va:lower() end
    if type(vb) == "string" then vb = vb:lower() end
    if va == vb or va == nil or vb == nil then
      if va == nil and vb ~= nil then return false end
      if vb == nil and va ~= nil then return true end
      return (a.t or 0) > (b.t or 0)
    end
    if sort.desc then return va > vb end
    return va < vb
  end)

  -- Header
  local width = f:GetWidth() - 12
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
  wipe(shown)
  for i = 1, n do
    local rec, r = list[i], getRow(i)
    shown[i] = rec
    r.index = i
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    for key, fs in pairs(r.cells) do fs:SetShown(lay[key] ~= nil) end
    for _, c in ipairs(cols) do
      local fs = cell(r, c.key)
      fs:ClearAllPoints()
      local x, w = lay[c.key].x, lay[c.key].w
      if c.key == "item" and rec.icon then
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "LEFT", x, 0)
        r.icon:SetTexture(rec.icon)
        x, w = x + 18, w - 18
      end
      fs:SetPoint("LEFT", r, "LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
      fs:SetText(show(rec, c.key))
      fs:Show()
    end
    r.icon:SetShown(lay.item ~= nil and rec.icon ~= nil)
    r:Show()
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  f.empty:SetText(EMPTY[s.tab] or EMPTY.all)
  f.empty:SetShown(#list == 0)
  f.content:SetHeight(math.max(n * ROW_HEIGHT, 30))
  f.sf.UpdateScrollBar()
  paint()
end

ns.RefreshLedger = ns.Timed("Ledger tab", ns.RefreshLedger)
