local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Recipes tab: every recipe of each profession (from RecipeBook.lua), who knows it,
-- where it comes from (as seen in game), what a craft makes at today's prices, and a
-- type: flip or shuffle, crafts that sell, not for sale, not profitable. Right-click a
-- row to set your own type. A Trainers view lists trainers seen, with map pins.
---------------------------------------------------------------------------
local SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true }
local ALWAYS_SHUFFLE = { [11287] = true, [11288] = true }   -- Lesser and Greater Magic Wand
local MIN_LISTED = 5
local MAX_ROWS = 300
local ROW = 22
local TYPES = {
  shuffle = { label = "Flip or shuffle", color = "7fd39c" },
  sells = { label = "Crafts that sell", color = "ffd100" },
  notsale = { label = "Not for sale", color = "888888" },
  loss = { label = "Not profitable", color = "ee8597" },
}
local ORDER = { "shuffle", "sells", "notsale", "loss" }

local function dim(t) return "|cff888888" .. t .. "|r" end
local function money(v)
  if not v then return dim("?") end
  return (v < 0 and "-" or "") .. ns.Money(math.floor(math.abs(v) + 0.5))
end

local function settings()
  local s = ns.db.settings.recipes
  s.view = s.view or "known"   -- "view", not the first test's "show", so everyone starts on Known
  s.type = s.type or "all"
  if s.custom == nil then s.custom = true end
  return s
end

---------------------------------------------------------------------------
-- Map pins
---------------------------------------------------------------------------
function ns:PinOnMap(mapID, x, y, label)
  if not (mapID and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint) then
    ns:Print("No position recorded for that yet.")
    return
  end
  local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y))
  if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  ns:Print(ok and ("Map pin set: %s, %s (%.1f, %.1f)."):format(label or "?", info and info.name or "?", x * 100, y * 100)
    or "The game didn't accept a map pin there.")
end

---------------------------------------------------------------------------
-- What a recipe is worth and which type it is
---------------------------------------------------------------------------
local function unitCost(id)
  local vendor = ns:GetVendorBuyPrice(id)
  if vendor then return vendor end
  return (ns:GetPrice(id))
end

-- Profit per craft at today's prices, and the output's best option (or nil).
local function craftValue(r)
  if not r.out then return end
  local best = ns:BestOption(r.out)
  if not best then return end
  local cost = 0
  for _, m in ipairs(r.r or {}) do
    local c = unitCost(m[1])
    if not c then return nil, best end
    cost = cost + c * m[2]
  end
  return best.value * (r.oq or 1) - cost, best
end

local function autoType(r)
  if ALWAYS_SHUFFLE[r.out or 0] then return "shuffle" end
  local _, _, _, _, _, _, _, _, _, _, sell, _, _, bind = ns.GetItemInfo(r.out or 0)
  local profit, best = craftValue(r)
  if bind == 1 or not best then return "notsale", profit end
  if not profit or profit <= 0 then return "loss", profit end
  if best.kind == "ah" then
    local rec = (ns.db.prices[ns.MarketKey()] or {})[r.out]
    if rec and (rec.q or 0) >= MIN_LISTED then return "sells", profit end
    return "loss", profit
  end
  return "shuffle", profit
end

-- The most useful source seen: vendor or trainer with a position first.
local function bestSource(name)
  local list = name and ns.db.recipeSources[name:lower()]
  local pick
  for _, s in pairs(list or {}) do
    local score = (s.mapID and 2 or 0) + ((s.kind == "vendor" or s.kind == "trainer") and 1 or 0)
    if not pick or score > pick.score then pick = { s = s, score = score } end
  end
  return pick and pick.s
end

local function sourceText(s)
  if not s then return dim("not seen yet") end
  local where = s.zone and (", " .. s.zone) or ""
  if s.kind == "trainer" then
    return ("Trainer %s%s%s"):format(s.npc or "?", where, s.skill and (" (skill " .. s.skill .. ")") or "")
  elseif s.kind == "vendor" then
    local price = s.currency or (s.cost and ns.Money(s.cost)) or ""
    return ("Vendor %s%s  %s%s"):format(s.npc or "?", where, price, s.limited and dim(" limited") or "")
  elseif s.kind == "drop" then
    return ("Drop: %s%s"):format(s.npc or "unknown mob", where)
  end
  return s.kind or "?"
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local f
local rows = {}
local current     -- profession shown, or "Trainers:<profession>"

local COLS = {
  { key = "name", label = "Recipe" },
  { key = "known", label = "Known by", w = 120 },
  { key = "source", label = "Where from (seen in game)", w = 300 },
  { key = "type", label = "Type", w = 104 },
  { key = "profit", label = "Per craft", w = 80 },
  { key = "pin", label = "", w = 36 },
}

local function professions()
  local set = {}
  for _, c in pairs(ns.db.chars) do
    for p in pairs(c.profs or {}) do if ns.db.recipeBook[p] then set[p] = true end end
  end
  for p in pairs(SECONDARY) do if ns.db.recipeBook[p] then set[p] = true end end
  local list = {}
  for p in pairs(set) do list[#list + 1] = p end
  table.sort(list)
  return list
end

function ns:BuildRecipes(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f.tabs = {}
  f.second = CreateFrame("Frame", nil, f)
  f.second:SetPoint("TOPLEFT", 0, -30)
  f.second:SetPoint("TOPRIGHT", 0, -30)
  f.second:SetHeight(24)

  local s = settings()
  f.show = T:Choice(f.second, { { value = "all", label = "All" }, { value = "unknown", label = "Not known" }, { value = "known", label = "Known" } },
    function(v) s.view = v; ns:RefreshRecipes() end)
  f.show:SetPoint("LEFT", 0, 0)
  f.custom = T:Check(f.second, function(self) s.custom = self:GetChecked(); ns:RefreshRecipes() end)
  f.custom.label:SetText("Use my types")
  f.custom:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Use my types", 1, 1, 1)
    GameTooltip:AddLine("On: recipes you right-clicked keep the type you gave them. Off: every recipe uses the automatic type (your choices are kept for later).", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  f.custom:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local typeOpts = { { value = "all", label = "Every type" } }
  for _, k in ipairs(ORDER) do typeOpts[#typeOpts + 1] = { value = k, label = TYPES[k].label } end
  f.type = T:Choice(f.second, typeOpts, function(v) s.type = v; ns:RefreshRecipes() end)
  f.type:SetPoint("LEFT", f.show, "RIGHT", 14, 0)
  f.search = T:EditBox(f.second, 140, "LEFT")
  f.search:SetPoint("LEFT", f.type, "RIGHT", 14, 0)
  f.custom:SetPoint("LEFT", f.search, "RIGHT", 14, 0)
  f.search:SetScript("OnTextChanged", function() ns:RefreshRecipes() end)
  f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

  f.header = CreateFrame("Frame", nil, f)
  f.header:SetPoint("TOPLEFT", 0, -58)
  f.header:SetPoint("TOPRIGHT", 0, -58)
  f.header:SetHeight(22)
  T:Fill(f.header, { 1, 1, 1, 0.05 })
  f.heads = {}
  f.sf, f.content = T:Scroll(f)
  f.sf:SetPoint("TOPLEFT", 0, -82)
  f.sf:SetPoint("BOTTOMRIGHT", 0, 20)
  f.summary = T:Text(f, 11, T.dim)
  f.summary:SetPoint("BOTTOMLEFT", 4, 2)
  f.empty = T:Text(f.content, 12, T.dim)
  f.empty:SetPoint("TOPLEFT", 8, -8)
  return f
end

-- Profession sub-tabs, plus a Trainers view per profession.
local function layoutTabs(list)
  local sig = table.concat(list, ",")
  if f.tabSig ~= sig then
    for _, b in pairs(f.tabs) do b:Hide() end
    f.tabs = {}
    local prev
    local function add(key, label)
      local b = T:Tab(f, label, function() current = key; ns:RefreshRecipes() end)
      if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("TOPLEFT", -6, 4) end
      f.tabs[key] = b
      prev = b
    end
    for _, p in ipairs(list) do add(p, p) end
    add("trainers", "Trainers")
    f.tabSig = sig
  end
  if not current or not f.tabs[current] then current = list[1] or "trainers" end
  for key, b in pairs(f.tabs) do b:SetSelected(key == current) end
end

local function layout(cols, width)
  local fixed = 0
  for _, c in ipairs(cols) do fixed = fixed + (c.w or 0) + 8 end
  local x, out = 4, {}
  for _, c in ipairs(cols) do
    local w = c.w or math.max(150, width - fixed - 4)
    out[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  return out
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, f.content)
  r:SetHeight(ROW)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.08)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cells = {}
  for _, c in ipairs(COLS) do
    if c.key ~= "pin" then
      local fs = T:Text(r, 11)
      fs:SetWordWrap(false)
      fs:SetJustifyH(c.key == "profit" and "RIGHT" or "LEFT")
      r.cells[c.key] = fs
    end
  end
  r.pin = T:Button(r, "Pin", 34, function(self)
    local s = self:GetParent().src
    if s then ns:PinOnMap(s.mapID, s.x, s.y, s.npc or s.name) end
  end, 18)
  -- Right-click: set your own type (cycles through the types, then back to automatic).
  r:SetScript("OnClick", function(self, button)
    if button ~= "RightButton" or not self.recipeID then return end
    if not settings().custom then
      ns:Print("Tick \"Use my types\" first to set your own types.")
      return
    end
    local overrides = ns.db.recipeTypes
    local now = overrides[self.recipeID]
    local nextType
    if not now then nextType = ORDER[1] else
      for i, k in ipairs(ORDER) do if k == now then nextType = ORDER[i + 1] end end
    end
    overrides[self.recipeID] = nextType
    ns:RefreshRecipes()
  end)
  r:SetScript("OnEnter", function(self)
    if not self.out then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetItemByID(self.out)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click to set your own type.", T.accent[1], T.accent[2], T.accent[3])
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function knownBy(prof, recipeID)
  local names = {}
  for key, c in pairs(ns.db.chars) do
    local p = c.profs and c.profs[prof]
    if p and p.recipes and p.recipes[recipeID] then names[#names + 1] = c.name or key end
  end
  table.sort(names)
  return names
end

local function recipeRows(prof, width, lay)
  local s = settings()
  local match = (f.search:GetText() or ""):lower()
  local list = {}
  for id, r in pairs(ns.db.recipeBook[prof] or {}) do
    local names = knownBy(prof, id)
    local known = #names > 0
    if (s.view == "all" or (s.view == "known") == known) and (match == "" or (r.n or ""):lower():find(match, 1, true)) then
      local auto, profit = autoType(r)
      local mine = s.custom and ns.db.recipeTypes[id] or nil
      local t = mine or auto
      if s.type == "all" or s.type == t then
        list[#list + 1] = { id = id, r = r, names = names, type = t, override = mine ~= nil, profit = profit }
      end
    end
  end
  -- Grouped by type (flip or shuffle first), then most profit first.
  local rank = {}
  for i, k in ipairs(ORDER) do rank[k] = i end
  table.sort(list, function(a, b)
    if a.type ~= b.type then return rank[a.type] < rank[b.type] end
    if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
    if a.profit and b.profit and a.profit ~= b.profit then return a.profit > b.profit end
    return (a.r.n or "") < (b.r.n or "")
  end)
  local n = math.min(#list, MAX_ROWS)
  for i = 1, n do
    local e, row = list[i], getRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW)
    row:SetWidth(width)
    row.stripe:SetShown(i % 2 == 0)
    row.recipeID, row.out = e.id, e.r.out
    row.icon:SetTexture(e.r.out and ns:ItemIcon(e.r.out) or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", lay.name.x, 0)
    local src = bestSource(e.r.n)
    row.src = src
    local tinfo = TYPES[e.type]
    local values = {
      name = e.r.n or "?",
      known = #e.names > 0 and table.concat(e.names, ", ") or (SECONDARY[prof] and "|cff7fd39canyone can learn|r" or dim("nobody yet")),
      source = sourceText(src),
      type = ("|cff%s%s|r%s"):format(tinfo.color, tinfo.label, e.override and dim(" (yours)") or ""),
      profit = money(e.profit),
    }
    for key, fs in pairs(row.cells) do
      local x, w = lay[key].x, lay[key].w
      if key == "name" then x, w = x + 20, w - 20 end
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", row, "LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetText(values[key])
      fs:Show()
    end
    row.pin:ClearAllPoints()
    row.pin:SetPoint("LEFT", row, "LEFT", lay.pin.x, 0)
    row.pin:SetShown(src and src.mapID and src.x and true or false)
    row:Show()
  end
  local total, knownCount = 0, 0
  for id in pairs(ns.db.recipeBook[prof] or {}) do
    total = total + 1
    if #knownBy(prof, id) > 0 then knownCount = knownCount + 1 end
  end
  f.summary:SetText(("%s: %d recipes, %d known. Showing %d%s. Sources fill in as you visit vendors and trainers."):format(
    prof, total, knownCount, n, #list > MAX_ROWS and (" of " .. #list) or ""))
  return n
end

local function trainerRows(width, lay)
  local list = {}
  for npcID, v in pairs(ns.db.vendors) do
    if v.trainer then list[#list + 1] = { id = npcID, v = v } end
  end
  local TIER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }
  table.sort(list, function(a, b)
    if (a.v.profession or "") ~= (b.v.profession or "") then return (a.v.profession or "") < (b.v.profession or "") end
    return (TIER[a.v.tier or ""] or 0) > (TIER[b.v.tier or ""] or 0)
  end)
  for i, e in ipairs(list) do
    local row = getRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW)
    row:SetWidth(width)
    row.stripe:SetShown(i % 2 == 0)
    row.recipeID, row.out = nil, nil
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", lay.name.x, 0)
    row.src = e.v
    local values = {
      name = e.v.name or "?",
      known = e.v.profession or "?",
      source = ("%s%s"):format(e.v.zone or "?", e.v.x and ("  (%.1f, %.1f)"):format(e.v.x * 100, e.v.y * 100) or ""),
      type = e.v.tier or dim("?"),
      profit = e.v.title and dim(e.v.title) or "",
    }
    for key, fs in pairs(row.cells) do
      local x, w = lay[key].x, lay[key].w
      if key == "name" then x, w = x + 20, w - 20 end
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", row, "LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetText(values[key])
      fs:Show()
    end
    row.pin:ClearAllPoints()
    row.pin:SetPoint("LEFT", row, "LEFT", lay.pin.x, 0)
    row.pin:SetShown(e.v.mapID and e.v.x and true or false)
    row:Show()
  end
  f.summary:SetText(("%d trainers seen. Trainers you visit are added here with their position; Classic locations for the rest come later."):format(#list))
  return #list
end

function ns:RefreshRecipes()
  if not f or not f:IsShown() then return end
  local s = settings()
  f.show:SetValue(s.view)
  f.custom:SetChecked(s.custom)
  f.type:SetValue(s.type)
  layoutTabs(professions())
  local trainers = current == "trainers"
  f.second:SetShown(not trainers)

  local width = f:GetWidth() - 12
  local lay = layout(COLS, width)
  local labels = trainers and { name = "Trainer", known = "Profession", source = "Where", type = "Tier", profit = "Title", pin = "" }
  for i, c in ipairs(COLS) do
    local h = f.heads[i]
    if not h then h = T:Text(f.header, 11, T.dim); f.heads[i] = h end
    h:ClearAllPoints()
    h:SetPoint("LEFT", f.header, "LEFT", lay[c.key].x, 0)
    h:SetWidth(lay[c.key].w)
    h:SetJustifyH(c.key == "profit" and not trainers and "RIGHT" or "LEFT")
    h:SetText(labels and labels[c.key] or c.label)
  end

  f.content:SetWidth(width)
  local n = trainers and trainerRows(width, lay) or (current and recipeRows(current, width, lay) or 0)
  for i = n + 1, #rows do rows[i]:Hide() end
  f.empty:SetShown(n == 0)
  f.empty:SetText(trainers and "No trainers seen yet. Open a profession trainer's window." or
    "No recipes match. Open this profession's window once to record its recipes.")
  f.content:SetHeight(math.max(n * ROW, 30))
  f.sf.UpdateScrollBar()
end

ns.RefreshRecipes = ns.Timed("Recipes tab", ns.RefreshRecipes)
