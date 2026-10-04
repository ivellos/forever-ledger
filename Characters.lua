local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Characters tab (owner, October 4: "rework it into something useful, or remove it";
-- with the roadmap's "view your alts' bags and bank" and "what it's all worth").
-- Characters down the left (this realm and faction first, then the rest greyed), with
-- their gold. On the right, the chosen character's professions and their bags and bank
-- (as of their last login, and their last bank visit), each item with what it's worth to
-- you and the best way to turn it into gold. "All characters" adds them up and says who
-- has what; the search box looks through everyone at once.
-- Reads ns.db.inventory (Inventory.lua), ns.db.chars and ns.db.gold. Changes nothing.
---------------------------------------------------------------------------
local NAV_W, ROW, MAX_ROWS = 180, 20, 400
local f
local navButtons, rows, heads = {}, {}, {}
local state = { char = nil, where = "both", sort = { key = "total", desc = true } }

local COLS = {
  { key = "name", label = "Item" },
  { key = "n", label = "Count", w = 50, right = true },
  { key = "each", label = "Each", w = 80, right = true },
  { key = "total", label = "Total", w = 90, right = true },
  { key = "how", label = "Best way", w = 190 },
}

local function dim(t) return "|cff888888" .. t .. "|r" end

local function className(c)
  local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class or ""]
  return cc and ("|c" .. (cc.colorStr or "ffffffff") .. (c.name or "?") .. "|r") or (c.name or "?")
end

-- A character's gold at their last login (the newest hour in History.lua's record).
local function goldOf(key)
  local best, at = nil, -1
  for hour, v in pairs((ns.db.gold or {})[key] or {}) do
    if type(hour) == "number" and hour > at then at, best = hour, v end
  end
  if key == ns.CharKey() then return GetMoney() end
  return best
end

-- This realm and faction first (you at the top), then the rest.
local function charOrder()
  local me, here, away = ns.CharKey(), {}, {}
  for k in pairs(ns.db.chars) do
    if k ~= me then
      if ns:SameMarketChar(k) then here[#here + 1] = k else away[#away + 1] = k end
    end
  end
  local function byName(a, b) return (ns.db.chars[a].name or a):lower() < (ns.db.chars[b].name or b):lower() end
  table.sort(here, byName)
  table.sort(away, byName)
  local out = {}
  if ns.db.chars[me] then out[1] = me end
  for _, k in ipairs(here) do out[#out + 1] = k end
  return out, away
end

-- What one is worth to you and how: the best way (auction house, vendor, disenchant,
-- craft); items that bind can only go to a vendor.
local function worth(id)
  local vendor = ns:GetSellPrice(id) or 0
  if ns.IsClassicBound and ns:IsClassicBound(id) then
    return vendor, vendor > 0 and "Sell to vendor" or dim("can't be sold")
  end
  local best, options = ns:GetValue(id)
  if best and best > 0 then return best, options[1].label end
  if vendor > 0 then return vendor, "Sell to vendor" end
  return 0, dim("no price yet")
end

-- The items to list: one character, or everyone on this realm ("all").
local function gather(key, where, search)
  local items, keys = {}, {}
  if key == "all" then keys = (charOrder()) else keys = { key } end
  for _, k in ipairs(keys) do
    local inv = ns.db.inventory[k]
    if inv then
      local c = ns.db.chars[k]
      local function add(list, place)
        for id, n in pairs(list or {}) do
          local e = items[id]
          if not e then e = { id = id, n = 0, who = {} }; items[id] = e end
          e.n = e.n + n
          local label = key == "all" and (c and c.name or k) or place
          e.who[label] = (e.who[label] or 0) + n
        end
      end
      if where ~= "bank" then add(inv.bags, "bags") end
      if where ~= "bags" then add(inv.bank, "bank") end
    end
  end
  local list = {}
  local q = search and search ~= "" and search:lower() or nil
  for id, e in pairs(items) do
    e.name = ns.ItemName(id) or ("item " .. id)
    if not q or e.name:lower():find(q, 1, true) then
      e.each, e.how = worth(id)
      e.total = e.each * e.n
      list[#list + 1] = e
    end
  end
  return list
end

---------------------------------------------------------------------------
-- Building the tab
---------------------------------------------------------------------------
local function navButton(i)
  if navButtons[i] then return navButtons[i] end
  local b = CreateFrame("Button", nil, f.nav)
  b:SetHeight(34)
  b.bg = T:Fill(b, { 1, 1, 1, 0.03 })
  b.sel = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.05)
  b.name = T:Text(b, 12)
  b.name:SetPoint("TOPLEFT", 8, -4)
  b.name:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.name:SetJustifyH("LEFT")
  b.name:SetWordWrap(false)
  b.sub = T:Text(b, 10, T.dim)
  b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
  b.sub:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.sub:SetJustifyH("LEFT")
  b.sub:SetWordWrap(false)
  b:SetScript("OnClick", function(self) state.char = self.key; ns:RefreshCharacters() end)
  navButtons[i] = b
  return b
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, f.content)
  r:SetHeight(ROW)
  r:EnableMouse(true)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cells = {}
  for _, c in ipairs(COLS) do
    local fs = T:Text(r, 11)
    fs:SetWordWrap(false)
    fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
    r.cells[c.key] = fs
  end
  r:SetScript("OnEnter", function(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(e.id)
    GameTooltip:AddLine(" ")
    local names = {}
    for who in pairs(e.who) do names[#names + 1] = who end
    table.sort(names)
    for _, who in ipairs(names) do GameTooltip:AddDoubleLine(who, tostring(e.who[who]), 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function getHead(i)
  if heads[i] then return heads[i] end
  local h = CreateFrame("Button", nil, f.header)
  h.fs = T:Text(h, 11, T.dim)
  h.fs:SetAllPoints()
  h:SetScript("OnClick", function(self)
    local s = state.sort
    if s.key == self.key then s.desc = not s.desc else s.key, s.desc = self.key, self.key ~= "name" and self.key ~= "how" end
    ns:RefreshCharacters()
  end)
  heads[i] = h
  return h
end

function ns:BuildCharacters(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f.navSf, f.nav = T:Scroll(f)
  f.navSf:SetPoint("TOPLEFT", 0, 0)
  f.navSf:SetPoint("BOTTOMLEFT", 0, 0)
  f.navSf:SetWidth(NAV_W)

  -- The chosen character: who, gold, professions.
  f.title = T:Text(f, 14)
  f.title:SetPoint("TOPLEFT", NAV_W + 12, -2)
  f.title:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  f.profs = T:Text(f, 11, T.dim)
  f.profs:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.profs:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.profs:SetJustifyH("LEFT")
  if f.profs.SetMaxLines then f.profs:SetMaxLines(2) end   -- a third line ran into Bags and bank

  -- Bags, bank or both; and a search through them.
  f.where = T:Choice(f, { { value = "both", label = "Bags and bank" }, { value = "bags", label = "Bags" }, { value = "bank", label = "Bank" } },
    function(v) state.where = v; ns:RefreshCharacters() end)
  f.where:SetPoint("TOPLEFT", NAV_W + 10, -58)
  f.search = T:EditBox(f, 160, "LEFT")
  f.search:SetPoint("TOPRIGHT", -6, -58)
  local hint = T:Text(f.search, 11, T.section)
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Search items")
  local typed = 0
  f.search:SetScript("OnTextChanged", function(self)
    hint:SetShown(self:GetText() == "" and not self:HasFocus())
    typed = typed + 1
    local mine = typed
    C_Timer.After(0.25, function() if mine == typed then ns:RefreshCharacters() end end)
  end)
  f.search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  f.search:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
  f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

  f.header = CreateFrame("Frame", nil, f)
  f.header:SetPoint("TOPLEFT", NAV_W + 6, -86)
  f.header:SetPoint("TOPRIGHT", 0, -86)
  f.header:SetHeight(20)
  T:Fill(f.header, { 1, 1, 1, 0.05 })
  f.sf, f.content = T:Scroll(f)
  f.sf:SetPoint("TOPLEFT", NAV_W + 6, -108)
  f.sf:SetPoint("BOTTOMRIGHT", 0, 22)
  f.empty = T:Text(f.content, 12, T.dim)
  f.empty:SetPoint("TOPLEFT", 8, -8)
  f.empty:SetPoint("RIGHT", f.content, "RIGHT", -8, 0)
  f.empty:SetJustifyH("LEFT")
  f.summary = T:Text(f, 11)
  f.summary:SetPoint("BOTTOMLEFT", NAV_W + 10, 4)
  f.summary:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.summary:SetJustifyH("LEFT")
  f.summary:SetWordWrap(false)
  f:SetScript("OnSizeChanged", function() if f:IsShown() then ns:RefreshCharacters() end end)
  return f
end

function ns:RefreshCharacters()
  if not (f and f:IsShown()) then return end
  local mine, away = charOrder()
  if not state.char or not (state.char == "all" or ns.db.chars[state.char]) then state.char = ns.CharKey() end

  -- The list on the left: All, this realm, then the rest.
  local entries = { { key = "all" } }
  for _, k in ipairs(mine) do entries[#entries + 1] = { key = k } end
  if #away > 0 then entries[#entries + 1] = { heading = "Other realms or factions" } end
  for _, k in ipairs(away) do entries[#entries + 1] = { key = k, away = true } end
  local y, n = 0, 0
  local navW = NAV_W - 14
  f.nav:SetWidth(navW)
  for _, e in ipairs(entries) do
    n = n + 1
    local b = navButton(n)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -y)
    b:SetWidth(navW)
    b.key = e.key
    if e.heading then
      b:SetHeight(22)
      b.name:SetText(dim(e.heading))
      b.sub:SetText("")
      b:EnableMouse(false)
      b.bg:Hide()
      b.sel:Hide()
    else
      b:SetHeight(34)
      b:EnableMouse(true)
      b.bg:Show()
      b.sel:SetShown(state.char == e.key)
      if e.key == "all" then
        local total = 0
        for _, k in ipairs(mine) do total = total + (goldOf(k) or 0) end
        b.name:SetText(T:AccentCode() .. "All characters|r")
        b.sub:SetText("this realm, gold " .. ns.MoneyPlain(total))
      else
        local c = ns.db.chars[e.key]
        local me = e.key == ns.CharKey()
        b.name:SetText((e.away and dim(c.name or e.key) or className(c)) .. (me and dim("  (you)") or ""))
        local g = goldOf(e.key)
        b.sub:SetText(("level %s%s"):format(c.level or "?", g and (", " .. ns.MoneyPlain(g)) or "")
          .. (e.away and (", " .. (c.realm or c.faction or "")) or ""))
      end
    end
    b:Show()
    y = y + b:GetHeight() + 2
  end
  for i = n + 1, #navButtons do navButtons[i]:Hide() end
  f.nav:SetHeight(y)
  f.navSf.UpdateScrollBar()

  -- The chosen one: who, and their professions (where to open the window if not saved).
  local key = state.char
  if key == "all" then
    f.title:SetText(T:AccentCode() .. "All characters|r " .. dim("on this realm and faction"))
    f.profs:SetText("What everyone has, added up; hover an item for who has it.")
  else
    local c = ns.db.chars[key]
    f.title:SetText(("%s  %s"):format(className(c), dim(("level %s %s %s"):format(c.level or "?",
      (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class or ""]) or c.class or "", c.faction or ""))))
    local parts = {}
    local names = {}
    for p in pairs(c.profs or {}) do names[#names + 1] = p end
    table.sort(names)
    for _, p in ipairs(names) do
      local info = c.profs[p]
      local saved = (info.recipeCount or 0) > 0 and dim((" (%d recipes)"):format(info.recipeCount))
        or " |cffee8597(open its window to save recipes)|r"
      parts[#parts + 1] = ("%s %s/%s%s"):format(p, info.rank or "?", info.max or "?", saved)
    end
    f.profs:SetText(#parts > 0 and table.concat(parts, "   ") or "No professions saved yet: open each profession's window once.")
  end
  f.where:SetValue(state.where)

  -- Items
  local list = gather(key, state.where, f.search:GetText())
  local s = state.sort
  table.sort(list, function(a, b)
    local va, vb = a[s.key], b[s.key]
    if type(va) == "string" then va, vb = va:lower(), (vb or ""):lower() end
    if va == vb then return a.name < b.name end
    if s.desc then return va > vb end
    return va < vb
  end)

  local width = f.sf:GetWidth() - 12
  local fixed = 0
  for _, c in ipairs(COLS) do fixed = fixed + (c.w or 0) + 8 end
  local x, lay = 4, {}
  for _, c in ipairs(COLS) do
    local w = c.w or math.max(120, width - fixed - 4)
    lay[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  for i, c in ipairs(COLS) do
    local h = getHead(i)
    h.key = c.key
    h:ClearAllPoints()
    h:SetPoint("LEFT", f.header, "LEFT", lay[c.key].x, 0)
    h:SetSize(lay[c.key].w, 20)
    h.fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
    local sorted = s.key == c.key
    h.fs:SetText(c.label .. (sorted and (s.desc and " v" or " ^") or ""))
    local col = sorted and T.accent or T.dim
    h.fs:SetTextColor(col[1], col[2], col[3], 1)
  end

  f.content:SetWidth(width)
  local shown = math.min(#list, MAX_ROWS)
  local total, vendorTrash = 0, 0
  for _, e in ipairs(list) do
    total = total + e.total
    if e.how == "Sell to vendor" then vendorTrash = vendorTrash + e.total end
  end
  for i = 1, shown do
    local e, r = list[i], getRow(i)
    r.entry = e
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    r.icon:ClearAllPoints()
    r.icon:SetPoint("LEFT", r, "LEFT", lay.name.x, 0)
    r.icon:SetTexture(ns:ItemIcon(e.id))
    for _, c in ipairs(COLS) do
      local fs = r.cells[c.key]
      fs:ClearAllPoints()
      local cx, cw = lay[c.key].x, lay[c.key].w
      if c.key == "name" then cx, cw = cx + 18, cw - 18 end
      fs:SetPoint("LEFT", r, "LEFT", cx, 0)
      fs:SetWidth(cw)
    end
    r.cells.name:SetText(e.name)
    r.cells.n:SetText(tostring(e.n))
    r.cells.each:SetText(e.each > 0 and ns.MoneyPlain(e.each) or dim("-"))
    r.cells.total:SetText(e.total > 0 and ("|cff7fd39c" .. ns.MoneyPlain(e.total) .. "|r") or dim("-"))
    r.cells.how:SetText(e.how or "")
    r:Show()
  end
  for i = shown + 1, #rows do rows[i]:Hide() end
  f.content:SetHeight(math.max(shown * ROW, 30))
  f.sf.UpdateScrollBar()

  local inv = key ~= "all" and ns.db.inventory[key]
  local noData = key ~= "all" and not inv
  f.empty:SetShown(#list == 0)
  f.empty:SetText((noData and "Nothing saved for this character yet: log in on it once (and open its bank to see that too).")
    or (f.search:GetText() ~= "" and "Nothing here matches the search.")
    or (state.where == "bank" and "Nothing saved from the bank yet: open the bank on this character once.")
    or "Nothing here.")
  local when = ""
  if inv then
    when = dim(("   Bags %s%s"):format(key == ns.CharKey() and "now" or (inv.t and ns.Age(inv.t) or "?"),
      inv.bankT and (", bank " .. ns.Age(inv.bankT)) or ", bank not seen yet"))
  end
  f.summary:SetText(("Worth about |cff7fd39c%s|r%s%s"):format(ns.MoneyPlain(math.floor(total)),
    vendorTrash > 0 and (", of which " .. ns.MoneyPlain(math.floor(vendorTrash)) .. " only to a vendor") or "", when))
end
