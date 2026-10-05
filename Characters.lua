local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Characters tab (owner, October 4: "rework it into something useful, or remove it";
-- with the roadmap's "view your alts' bags and bank" and "what it's all worth").
-- A realm and faction to look at (a dropdown above the list, this one by default; owner's
-- test, October 4: other realms must not count in what you're looking at), its
-- characters down the left with their gold. On the right, the chosen character's
-- professions and their bags and bank (as of their last login, and their last bank
-- visit), each item with what it's worth to you and the best way to turn it into gold.
-- "All characters" adds up everyone in the chosen group and says who has what; the
-- search box looks through everyone at once.
-- Reads ns.db.inventory (Inventory.lua), ns.db.chars and ns.db.gold. Changes nothing.
---------------------------------------------------------------------------
local NAV_W, ROW, MAX_ROWS = 190, 20, 400
local f
local navButtons, rows, heads, profCells = {}, {}, {}, {}
local state = { char = nil, group = nil, where = "both", sort = { key = "total", desc = true } }

local COLS = {
  { key = "name", label = "Item" },
  { key = "n", label = "Count", w = 50, right = true },
  { key = "each", label = "Each", w = 80, right = true,
    tip = "What one is worth to you: the best of selling it on the auction house (after the cut), to a vendor, disenchanting it or crafting it into something." },
  { key = "total", label = "Total", w = 90, right = true, tip = "Count times Each." },
  { key = "how", label = "Best way", w = 170, tip = "How to get the most for it. Hover an item for the whole way." },
}

-- Secondary professions go after the main ones on the professions line.
local SECONDARY = { ["Cooking"] = true, ["First Aid"] = true, ["Fishing"] = true }

local function dim(t) return "|cff888888" .. t .. "|r" end

local function className(c)
  local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class or ""]
  return cc and ("|c" .. (cc.colorStr or "ffffffff") .. (c.name or "?") .. "|r") or (c.name or "?")
end

-- "Mage" rather than the game's "MAGE".
local function classWord(c)
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class or ""]) or c.class or ""
end

---------------------------------------------------------------------------
-- Realm and faction groups. Forever's realm name is its ruleset; the beta's servers
-- were "Classic Beta PvE 2", shown as "PvE 2". Characters saved before realm and
-- faction were recorded count as this one.
---------------------------------------------------------------------------
local function realmOf(c) return c.realm or GetRealmName() or "?" end
local function factionOf(c) return c.faction or UnitFactionGroup("player") or "?" end

-- "Classic Beta PvE 2" without the prefix and the number: "PvE". At launch there's one
-- server per ruleset (owner, October 4), so the number only stays when two of your
-- realms would otherwise read the same ("PvE 1", "PvE 2").
local function trimRealm(realm)
  local s = realm:gsub("^Classic Beta%s+", ""):gsub("^WoW Forever%s+", ""):gsub("^Forever%s+", "")
  return s ~= "" and s or realm
end
local function shortRealm(realm)
  local trimmed = trimRealm(realm)
  local base = trimmed:gsub("%s+%d+$", "")
  for _, c in pairs(ns.db.chars) do
    local other = c.realm
    if other and other ~= realm and trimRealm(other):gsub("%s+%d+$", "") == base then return trimmed end
  end
  return base
end

local function hereGroup() return (GetRealmName() or "?") .. "|" .. (UnitFactionGroup("player") or "?") end

-- Does a character belong to a group: "realm|faction", "realm|*" (both factions) or "*".
local function inGroup(key, group)
  if group == "*" then return true end
  local c = ns.db.chars[key]
  local realm, faction = group:match("^(.*)|(.-)$")
  return realmOf(c) == realm and (faction == "*" or factionOf(c) == faction)
end

local function groupLabel(group)
  if group == "*" then return "All realms" end
  local realm, faction = group:match("^(.*)|(.-)$")
  return shortRealm(realm) .. (faction == "*" and ", both factions" or (" " .. faction))
end

-- The dropdown's choices: each realm and faction you have characters on (yours first),
-- both factions of a realm when you have both there, and all realms when there's more
-- than one group.
local function groupOptions()
  local realms, order = {}, {}
  for _, c in pairs(ns.db.chars) do
    local r = realmOf(c)
    if not realms[r] then realms[r] = {}; order[#order + 1] = r end
    realms[r][factionOf(c)] = true
  end
  local here = GetRealmName() or "?"
  table.sort(order, function(a, b)
    if (a == here) ~= (b == here) then return a == here end
    return a < b
  end)
  local opts, groups = {}, 0
  local mine = UnitFactionGroup("player")
  for _, r in ipairs(order) do
    local facs = {}
    for fac in pairs(realms[r]) do facs[#facs + 1] = fac end
    table.sort(facs, function(a, b)
      if (a == mine) ~= (b == mine) then return a == mine end
      return a < b
    end)
    for _, fac in ipairs(facs) do
      local g = r .. "|" .. fac
      opts[#opts + 1] = { value = g, label = groupLabel(g) }
      groups = groups + 1
    end
    if #facs > 1 then opts[#opts + 1] = { value = r .. "|*", label = groupLabel(r .. "|*") } end
  end
  if groups > 1 then opts[#opts + 1] = { value = "*", label = groupLabel("*") } end
  return opts, groups
end

-- A character's name in lists that span realms: "Ivellos Veren (PvP 2)".
local function whoName(key)
  local c = ns.db.chars[key]
  local name = c and c.name or key
  if state.group == "*" and c and realmOf(c) ~= GetRealmName() then name = name .. " (" .. shortRealm(realmOf(c)) .. ")" end
  return name
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

-- The chosen group's characters, you at the top, then by name.
local function charOrder()
  local me, out = ns.CharKey(), {}
  for k in pairs(ns.db.chars) do
    if k ~= me and inGroup(k, state.group) then out[#out + 1] = k end
  end
  table.sort(out, function(a, b) return (ns.db.chars[a].name or a):lower() < (ns.db.chars[b].name or b):lower() end)
  if ns.db.chars[me] and inGroup(me, state.group) then table.insert(out, 1, me) end
  return out
end

-- What one is worth to you and how: the best way (auction house, vendor, disenchant,
-- craft), short for the column ("Craft Minor Wizard Oil") and in full for the hover;
-- items that bind can only go to a vendor.
local function worth(id)
  local vendor = ns:GetSellPrice(id) or 0
  if ns.IsClassicBound and ns:IsClassicBound(id) then
    if vendor > 0 then return vendor, "Vendor", "Sell to vendor (it binds)", "vendor" end
    return 0, dim("can't be sold"), "It binds and no vendor buys it", "none"
  end
  local best, options = ns:GetValue(id)
  local o = options and options[1]
  if best and best > 0 and o then
    local short = (o.kind == "ah" and "Auction house") or (o.kind == "vendor" and "Vendor")
      or (o.kind == "disenchant" and "Disenchant") or o.step or o.label
    return best, short, o.label, o.kind
  end
  if vendor > 0 then return vendor, "Vendor", "Sell to vendor", "vendor" end
  return 0, dim("no price yet"), "No price yet: scan the auction house", "none"
end

-- The items to list: one character, or everyone in the chosen group ("all").
local function gather(key, where, search)
  local items, keys = {}, {}
  if key == "all" then keys = charOrder() else keys = { key } end
  for _, k in ipairs(keys) do
    local inv = ns.db.inventory[k]
    if inv then
      local function add(list, place)
        for id, n in pairs(list or {}) do
          local e = items[id]
          if not e then e = { id = id, n = 0, who = {} }; items[id] = e end
          e.n = e.n + n
          local label = key == "all" and whoName(k) or place
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
      e.each, e.how, e.howFull, e.kind = worth(id)
      e.total = e.each * e.n
      list[#list + 1] = e
    end
  end
  return list
end

-- What one character's bags and bank are worth (for hovers): total, bags, bank.
local function worthOf(key)
  local inv = ns.db.inventory[key]
  if not inv then return end
  local function sum(list)
    local t = 0
    for id, n in pairs(list or {}) do t = t + (worth(id)) * n end
    return math.floor(t)
  end
  local bags, bank = sum(inv.bags), sum(inv.bank)
  return bags + bank, bags, bank, inv
end

---------------------------------------------------------------------------
-- Building the tab
---------------------------------------------------------------------------
local function navButton(i)
  if navButtons[i] then return navButtons[i] end
  local b = CreateFrame("Button", nil, f.nav)
  b:SetHeight(36)
  b.bg = T:Fill(b, { 1, 1, 1, 0.03 })
  b.sel = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.05)
  -- An accent bar on the chosen one's left edge.
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetPoint("TOPLEFT")
  b.bar:SetPoint("BOTTOMLEFT")
  b.bar:SetWidth(2)
  b.bar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
  -- Class icon (or coins for All characters), name, then level and class with the gold
  -- on the right (owner's test, October 4: make the character list more appealing).
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(22, 22)
  b.icon:SetPoint("LEFT", 7, 0)
  b.name = T:Text(b, 12)
  b.name:SetPoint("TOPLEFT", 35, -4)
  b.name:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.name:SetJustifyH("LEFT")
  b.name:SetWordWrap(false)
  b.gold = T:Text(b, 10)
  b.gold:SetPoint("BOTTOMRIGHT", -6, 5)
  b.gold:SetJustifyH("RIGHT")
  b.sub = T:Text(b, 10, T.dim)
  b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
  b.sub:SetPoint("RIGHT", b.gold, "LEFT", -4, 0)
  b.sub:SetJustifyH("LEFT")
  b.sub:SetWordWrap(false)
  b:SetScript("OnClick", function(self) state.char = self.key; ns:RefreshCharacters() end)
  -- Hover: gold and what the bags and bank are worth, so the totals add up at a glance.
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.key == "all" then
      GameTooltip:AddLine("All characters: " .. groupLabel(state.group), 1, 1, 1)
      for _, k in ipairs(charOrder()) do
        local w = worthOf(k)
        GameTooltip:AddDoubleLine(whoName(k), (ns.MoneyPlain(goldOf(k) or 0)) .. dim("  items ") .. ns.MoneyPlain(w or 0), 0.8, 0.8, 0.8, 1, 1, 1)
      end
    else
      local c = ns.db.chars[self.key]
      GameTooltip:AddLine(whoName(self.key), 1, 1, 1)
      GameTooltip:AddDoubleLine("Gold", ns.MoneyPlain(goldOf(self.key) or 0), 0.8, 0.8, 0.8, 1, 1, 1)
      local w, bags, bank, inv = worthOf(self.key)
      if w then
        GameTooltip:AddDoubleLine("Bags worth", ns.MoneyPlain(bags), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Bank worth", inv.bankT and ns.MoneyPlain(bank) or dim("not seen yet"), 0.8, 0.8, 0.8, 1, 1, 1)
      else
        GameTooltip:AddLine("Bags not saved yet: log in on it once.", 0.6, 0.6, 0.6, true)
      end
      if c and c.realm then GameTooltip:AddLine(groupLabel(realmOf(c) .. "|" .. factionOf(c)), 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    if e.howFull then GameTooltip:AddLine("Best way: " .. e.howFull, 1, 0.82, 0) end
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
  h:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.label, 1, 1, 1)
    GameTooltip:AddLine(self.tip, nil, nil, nil, true)
    GameTooltip:AddLine("Click to sort.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  h:SetScript("OnLeave", function() GameTooltip:Hide() end)
  heads[i] = h
  return h
end

function ns:BuildCharacters(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  -- Which realm and faction (shown when you have characters on more than one).
  f.group = T:Dropdown(f, NAV_W - 14, function(v)
    state.group = v
    state.char = "all"
    ns:RefreshCharacters()
  end)
  f.group:SetPoint("TOPLEFT", 0, 0)
  f.group:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Realm and faction", 1, 1, 1)
    GameTooltip:AddLine("Whose characters to show and add up. Only characters on the same realm and faction share an auction house and can mail each other.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  f.group:HookScript("OnLeave", function() GameTooltip:Hide() end)
  f.navSf, f.nav = T:Scroll(f)
  f.navSf:SetPoint("BOTTOMLEFT", 0, 0)
  f.navSf:SetWidth(NAV_W)

  -- The chosen character: who, gold, professions.
  f.title = T:Text(f, 14)
  f.title:SetPoint("TOPLEFT", NAV_W + 12, -2)
  f.title:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  -- Professions in neat columns, three to a line (one wrapping line split "(7 recipes)"
  -- across lines: owner's test, October 4). f.profs is the line for everything else.
  f.profs = T:Text(f, 11, T.dim)
  f.profs:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.profs:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.profs:SetJustifyH("LEFT")
  f.profs:SetWordWrap(false)
  -- In a card of their own, set apart from the bags and bank below (owner's test,
  -- October 4: like the newer pages).
  f.profCard = CreateFrame("Frame", nil, f)
  f.profCard:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", -6, -3)
  f.profCard:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.profCard:SetHeight(38)
  T:Card(f.profCard)
  for i = 1, 6 do
    local fs = T:Text(f.profCard, 11)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    profCells[i] = fs
  end

  -- Bags, bank or both; and a search through them.
  f.where = T:Choice(f, { { value = "both", label = "Bags and bank" }, { value = "bags", label = "Bags" }, { value = "bank", label = "Bank" } },
    function(v) state.where = v; ns:RefreshCharacters() end)
  f.where:SetPoint("TOPLEFT", NAV_W + 10, -66)
  f.search = T:EditBox(f, 160, "LEFT")
  f.search:SetPoint("TOPRIGHT", -6, -66)
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
  f.header:SetPoint("TOPLEFT", NAV_W + 6, -94)
  f.header:SetPoint("TOPRIGHT", 0, -94)
  f.header:SetHeight(20)
  T:Fill(f.header, { 1, 1, 1, 0.05 })
  f.sf, f.content = T:Scroll(f)
  f.sf:SetPoint("TOPLEFT", NAV_W + 6, -116)
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
  -- Hover the bottom line: what it's made of (per character, or bags and bank).
  f.sumHit = CreateFrame("Frame", nil, f)
  f.sumHit:SetPoint("BOTTOMLEFT", NAV_W + 6, 0)
  f.sumHit:SetPoint("BOTTOMRIGHT", 0, 0)
  f.sumHit:SetHeight(20)
  f.sumHit:EnableMouse(true)
  f.sumHit:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("What it's worth", 1, 1, 1)
    GameTooltip:AddLine("Everything in the list above, each at its Each price. Search and the Bags / Bank buttons change it.", nil, nil, nil, true)
    if state.char == "all" then
      GameTooltip:AddLine(" ")
      for _, k in ipairs(charOrder()) do
        local w = worthOf(k)
        GameTooltip:AddDoubleLine(whoName(k), w and ns.MoneyPlain(w) or dim("not saved yet"), 0.8, 0.8, 0.8, 1, 1, 1)
      end
      GameTooltip:AddLine("(bags and bank, before any search)", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
  end)
  f.sumHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:SetScript("OnSizeChanged", function() if f:IsShown() then ns:RefreshCharacters() end end)
  return f
end

function ns:RefreshCharacters()
  if not (f and f:IsShown()) then return end
  -- The realm and faction: this one unless another was picked (and still exists).
  local opts, groups = groupOptions()
  local known = false
  for _, o in ipairs(opts) do if o.value == state.group then known = true end end
  if not known then state.group = hereGroup() end
  f.group:SetOptions(opts)
  f.group:SetValue(state.group)
  f.group:SetShown(groups > 1)
  f.navSf:SetPoint("TOPLEFT", 0, groups > 1 and -28 or 0)

  local mine = charOrder()
  if not state.char or not (state.char == "all" or (ns.db.chars[state.char] and inGroup(state.char, state.group))) then
    state.char = inGroup(ns.CharKey(), state.group) and ns.CharKey() or "all"
  end

  -- The list on the left: All, then the group's characters.
  local entries = { { key = "all" } }
  for _, k in ipairs(mine) do entries[#entries + 1] = { key = k } end
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
    b.sel:SetShown(state.char == e.key)
    b.bar:SetShown(state.char == e.key)
    b.icon:SetTexCoord(0, 1, 0, 1)
    if e.key == "all" then
      local total = 0
      for _, k in ipairs(mine) do total = total + (goldOf(k) or 0) end
      b.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.name:SetText(T:AccentCode() .. "All characters|r")
      b.sub:SetText(("%d %s"):format(#mine, #mine == 1 and "character" or "characters"))
      b.gold:SetText(ns.MoneyPlain(total))
    else
      local c = ns.db.chars[e.key]
      local me = e.key == ns.CharKey()
      local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class or ""]
      if tc then
        b.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        b.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      else
        b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      end
      b.name:SetText(className(c) .. (me and dim("  (you)") or ""))
      local g = goldOf(e.key)
      local other = state.group == "*" and realmOf(c) ~= GetRealmName()
      b.sub:SetText(("Level %s %s%s"):format(c.level or "?", classWord(c), other and (", " .. shortRealm(realmOf(c))) or ""))
      b.gold:SetText(g and ns.MoneyPlain(g) or "")
    end
    b:Show()
    y = y + b:GetHeight() + 2
  end
  for i = n + 1, #navButtons do navButtons[i]:Hide() end
  f.nav:SetHeight(y)
  f.navSf.UpdateScrollBar()

  -- The chosen one: who, and their professions (where to open the window if not saved).
  local key = state.char
  for _, fs in ipairs(profCells) do fs:Hide() end
  f.profCard:Hide()
  if key == "all" then
    f.title:SetText(T:AccentCode() .. "All characters|r " .. dim(groupLabel(state.group)))
    f.profs:SetText("What everyone has, added up; hover an item for who has it.")
    f.profs:Show()
  else
    local c = ns.db.chars[key]
    f.title:SetText(("%s  %s"):format(className(c), dim(("level %s %s %s"):format(c.level or "?", classWord(c), c.faction or ""))))
    local names = {}
    for p in pairs(c.profs or {}) do names[#names + 1] = p end
    table.sort(names, function(a, b)
      if (SECONDARY[a] or false) ~= (SECONDARY[b] or false) then return not SECONDARY[a] end
      return a < b
    end)
    local cellW = math.floor((f:GetWidth() - NAV_W - 34) / 3)
    for i, p in ipairs(names) do
      local fs = profCells[i]
      if not fs then break end
      local info = c.profs[p]
      local saved = (info.recipeCount or 0) > 0 and dim(("  %d recipes"):format(info.recipeCount))
        or "  |cffee8597open to save recipes|r"
      -- The rank coin, as on the Recipes tabs: gold Artisan, silver Expert, copper Journeyman.
      local max = info.max or 0
      local coin = (max >= 300 and "MoneyFrame\\UI-GoldIcon") or (max >= 225 and "MoneyFrame\\UI-SilverIcon")
        or (max >= 150 and "MoneyFrame\\UI-CopperIcon") or "COMMON\\Indicator-Gray"   -- (grey dot: Apprentice)
      fs:SetText(("|TInterface\\" .. coin .. ":11:11:0:0|t ")
        .. ("%s %s/%s%s"):format(p, info.rank or "?", info.max or "?", saved))
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", f.profCard, "TOPLEFT", 10 + ((i - 1) % 3) * cellW, -5 - math.floor((i - 1) / 3) * 15)
      fs:SetWidth(cellW - 8)
      fs:Show()
    end
    f.profCard:SetShown(#names > 0)
    f.profs:SetText(#names > 0 and "" or "No professions saved yet: open each profession's window once.")
    f.profs:SetShown(#names == 0)
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
    h.key, h.label, h.tip = c.key, c.label, c.tip
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
    if e.kind == "vendor" then vendorTrash = vendorTrash + e.total end
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
