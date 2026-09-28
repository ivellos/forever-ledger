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

---------------------------------------------------------------------------
-- Classic data (ClassicRecipes.lua): turn an entry into a source like the ones seen
-- in game, with a map for pins.
---------------------------------------------------------------------------
-- Zone name -> map ID, from the game's own map list (Classic zone and city maps are
-- numbered 1411-1458; Stormwind City is 1453).
local mapByName
function ns:MapIDForZone(zone)
  if not zone then return end
  if not mapByName then
    mapByName = {}
    if C_Map and C_Map.GetMapInfo then
      for id = 1400, 1460 do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if ok and info and info.name then mapByName[info.name] = mapByName[info.name] or id end
      end
    end
  end
  return mapByName[zone]
end

local myFaction
local function friendly(npc)
  myFaction = myFaction or ((UnitFactionGroup("player") == "Horde") and "H" or "A")
  return not npc.fac or npc.fac:find(myFaction, 1, true) ~= nil
end

-- An NPC from the Classic data as a source table.
local function classicNPC(id, kind)
  local n = ns.CLASSIC_NPCS and ns.CLASSIC_NPCS[id]
  if not n then return end
  return { kind = kind, conf = "classic", npc = n.name, npcID = id, zone = n.zone,
    x = n.x and n.x / 100, y = n.y and n.y / 100, mapID = ns:MapIDForZone(n.zone), fac = n.fac }
end

function ns:ClassicSource(name)
  local e = ns.CLASSIC_RECIPES and ns.CLASSIC_RECIPES[name:lower()]
  if not e then return end
  local s
  if e.kind == "vendor" then
    -- A vendor of your own faction (or neutral) with a position first.
    local best, bestScore
    for _, id in ipairs(e.vendors or {}) do
      local v = classicNPC(id, "vendor")
      if v then
        local score = (friendly(v) and 2 or 0) + (v.mapID and 1 or 0)
        if not best or score > bestScore then best, bestScore = v, score end
      end
    end
    s = best or { kind = "vendor", conf = "classic" }
    s.cost = e.cost
    s.hordeOnly = best and not friendly(best) or nil
  elseif e.kind == "mob" or e.kind == "drop" then
    local top = e.mobs and e.mobs[1]
    s = top and classicNPC(top[1], e.kind) or { kind = e.kind, conf = "classic" }
    s.chance = top and top[2] or e.chance
    s.mobCount = e.kind == "drop" and (e.mobCount or (e.mobs and #e.mobs)) or nil
  else
    s = { kind = e.kind, conf = "classic", quest = e.quest, hordeOnly = e.faction == "Horde" or nil }
  end
  s.entry = e
  return s
end

-- Tooltip lines for every Classic source of a recipe: all vendors, the top mobs.
function ns:AddClassicSourceLines(tt, name)
  local e = name and ns.CLASSIC_RECIPES and ns.CLASSIC_RECIPES[name:lower()]
  if not e then return end
  tt:AddLine(" ")
  tt:AddLine("In original Classic (unconfirmed in Forever):", 1, 0.82, 0)
  for _, id in ipairs(e.vendors or {}) do
    local v = classicNPC(id, "vendor")
    if v then
      tt:AddDoubleLine("Sold by " .. v.npc, (v.zone or "?") .. (v.x and (" %.0f, %.0f"):format(v.x * 100, v.y * 100) or "")
        .. (friendly(v) and "" or " (Horde)"), 1, 1, 1, 0.8, 0.8, 0.8)
    end
  end
  for _, m in ipairs(e.mobs or {}) do
    local v = classicNPC(m[1], "mob")
    if v then
      tt:AddDoubleLine(("%s (%s%%)"):format(v.npc, m[2] >= 1 and ("%.0f"):format(m[2]) or ("%.2f"):format(m[2])),
        v.zone or "?", 1, 1, 1, 0.8, 0.8, 0.8)
    end
  end
  if e.mobCount and e.mobCount > #(e.mobs or {}) then
    tt:AddLine(("...and %d more kinds of mob."):format(e.mobCount - #(e.mobs or {})), 0.8, 0.8, 0.8)
  end
  if e.quest then tt:AddLine("Quest: " .. e.quest, 1, 1, 1) end
end

-- The most useful source: seen in game first (vendor or trainer with a position best),
-- otherwise where it came from in original Classic (ClassicRecipes.lua, unconfirmed).
local function bestSource(name)
  if not name then return end
  local pick
  for _, s in pairs(ns.db.recipeSources[name:lower()] or {}) do
    local score = (s.mapID and 2 or 0) + ((s.kind == "vendor" or s.kind == "trainer") and 1 or 0)
    if not pick or score > pick.score then pick = { s = s, score = score } end
  end
  if pick then return pick.s end
  return ns:ClassicSource(name)
end

-- Chance is in percent.
local function percent(p)
  if not p then return "" end
  return dim((" (%s%%)"):format(p >= 1 and ("%.0f"):format(p) or p >= 0.1 and ("%.1f"):format(p) or ("%.2f"):format(p)))
end

-- The recipe item's cheapest auction house listing: price, record (or nil).
local function recipeAH(s)
  local item = s and (s.item or (s.entry and s.entry.item))
  local rec = item and (ns.db.prices[ns.MarketKey()] or {})[item]
  if rec and rec.m and not rec.none then return rec.m, rec end
  return nil, rec
end

local function ahText(s)
  local price, rec = recipeAH(s)
  if price then return "  |cffffd100AH " .. ns.Money(price) .. "|r" end
  if rec and rec.none then return dim("  none on AH") end
  return ""
end

local function sourceText(s)
  -- Recipes with no recipe item to find were taught by trainers in Classic.
  if not s then return dim("probably a trainer") end
  local classic = s.conf ~= "seen"
  local where = s.zone and (", " .. s.zone) or ""
  local text
  if s.kind == "trainer" then
    text = ("Trainer %s%s%s"):format(s.npc or "?", where, s.skill and (" (skill " .. s.skill .. ")") or "")
  elseif s.kind == "vendor" then
    local price = s.currency or (s.cost and ns.Money(s.cost)) or ""
    local side = (classic and s.hordeOnly) and dim(" Horde only") or ""
    text = ("Vendor %s%s  %s%s%s"):format(s.npc or "?", where, price, s.limited and dim(" limited") or "", side)
  elseif s.kind == "mob" then
    text = ("Drops from %s%s"):format(s.npc or "?", where) .. percent(s.chance) .. ahText(s)
  elseif s.kind == "drop" then
    if s.mobCount then
      -- Kept short so the price fits; the mobs are in the hover.
      text = ("World drop, %d kinds of mob"):format(s.mobCount)
    else
      text = (s.npc and ("Drops from %s%s"):format(s.npc, where) or (s.zone and ("World drop in " .. s.zone) or "World drop, rare"))
        .. percent(s.chance)
    end
    text = text .. ahText(s)
  elseif s.kind == "quest" then
    text = ("Quest: %s"):format(s.quest or "?") .. (s.hordeOnly and dim(" Horde only") or "")
  else
    text = s.kind or "?"
  end
  return text .. (classic and dim("  Classic, unconfirmed") or "")
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
  { key = "source", label = "Where from (hover for all)", w = 300 },
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

StaticPopupDialogs["FOREVER_LEDGER_CLEAR_TYPES"] = {
  text = "Clear the types you set on %d recipes? They go back to automatic. This can't be undone.",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function()
    wipe(ns.db.recipeTypes)
    ns:Print("Your recipe types are cleared.")
    ns:RefreshRecipes()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

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
  f.clear = T:Button(f.second, "Clear my types", 110, function()
    local n = 0
    for _ in pairs(ns.db.recipeTypes) do n = n + 1 end
    if n == 0 then ns:Print("You haven't set any types yet."); return end
    StaticPopup_Show("FOREVER_LEDGER_CLEAR_TYPES", n)
  end, 22)
  f.clear:SetPoint("LEFT", f.custom.label, "RIGHT", 14, 0)
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
    -- Shift-right-click: back to the automatic type.
    if IsShiftKeyDown() then
      overrides[self.recipeID] = nil
      ns:RefreshRecipes()
      return
    end
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
    ns:AddClassicSourceLines(GameTooltip, self.recipeName)
    local price, rec = recipeAH(self.src)
    if price then
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("Recipe on the auction house", ns.Money(price), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddLine(("%d listed, scanned %s"):format(rec.q or 0, ns.Age(rec.t)), 0.8, 0.8, 0.8)
    elseif rec and rec.none then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(("Recipe not on the auction house (scanned %s)"):format(ns.Age(rec.t)), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click to set your own type, shift-right-click for automatic.", T.accent[1], T.accent[2], T.accent[3])
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
    row.recipeID, row.out, row.recipeName = e.id, e.r.out, e.r.n
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
  local list, seen = {}, {}
  for npcID, v in pairs(ns.db.vendors) do
    if v.trainer then
      list[#list + 1] = { id = npcID, v = v }
      if v.name then seen[v.name:lower()] = true end
    end
  end
  local classicCount = 0
  -- Classic trainers (ClassicRecipes.lua, positions from pfQuest) not visited yet.
  for _, t in ipairs(ns.CLASSIC_TRAINERS or {}) do
    if not seen[t.name:lower()] then
      local n = t.npc and classicNPC(t.npc, "trainer") or {}
      list[#list + 1] = { classic = true, v = { name = t.name, profession = t.profession, tier = t.tier, title = t.title,
        zone = n.zone or t.zone, x = n.x, y = n.y, mapID = n.mapID } }
      classicCount = classicCount + 1
    end
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
    row.recipeID, row.out, row.recipeName = nil, nil, nil
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", lay.name.x, 0)
    row.src = e.v
    local values = {
      name = e.v.name or "?",
      known = e.v.profession or "?",
      source = ("%s%s%s"):format(e.v.zone or "?", e.v.x and ("  (%.1f, %.1f)"):format(e.v.x * 100, e.v.y * 100) or "",
        e.classic and dim("  Classic, unconfirmed") or ""),
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
  f.summary:SetText(("%d trainers seen, %d more from Classic (unconfirmed; pins show where they stood in Classic). Visit one to confirm it."):format(
    #list - classicCount, classicCount))
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
