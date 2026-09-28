local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Waylaid Crates: fill one with any bundle from its list (read from the crate's
-- tooltip), turn it in for Merchant's Favor. This works out the cheapest bundle at
-- today's prices, the total with the crate's own price, and gold per Favor.
-- Favor per crate starts from an estimate per tier and is learned from turn-ins.
---------------------------------------------------------------------------
local FAVOR = 3402
local PREFIX = "Waylaid Crate"
local TIER_FAVOR = { Apprentice = 5, Journeyman = 10, Expert = 15, Artisan = 20 }   -- estimates

local function dim(t) return "|cff888888" .. t .. "|r" end
local function money(v) return v and ns.Money(math.floor(v + 0.5)) or dim("?") end

local function isCrate(name) return name and name:sub(1, #PREFIX) == PREFIX end
local function tierOf(name)
  for tier in pairs(TIER_FAVOR) do if name:find(tier, 1, true) then return tier end end
end

---------------------------------------------------------------------------
-- Reading a crate's bundles from its tooltip
---------------------------------------------------------------------------
-- "- 20 Strange Dust" lines -> { { qty = 20, name = "Strange Dust" }, ... } per bundle.
-- A bundle of several items ("- 10 Copper Bar and 5 Tin Bar") becomes several parts.
local function parseBundles(lines)
  local bundles, inList = {}, false
  for _, text in ipairs(lines) do
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      if line:find("any bundle", 1, true) then inList = true end
      local rest = line:match("^%s*%-%s*(.+)$")
      if inList and rest then
        local parts = {}
        for piece in (rest .. " and "):gmatch("(.-)%s+and%s+") do
          for sub in (piece .. ","):gmatch("%s*([^,]+),") do
            local qty, name = sub:match("^(%d+)%s*x?%s+(.+)$")
            if qty then parts[#parts + 1] = { qty = tonumber(qty), name = name:gsub("%s+$", "") } end
          end
        end
        if #parts > 0 then bundles[#bundles + 1] = parts end
      end
    end
  end
  return bundles
end

-- Bundles for a crate, read once from its tooltip and saved.
local function crateInfo(id)
  local saved = ns.db.crates[id]
  if saved and saved.bundles and #saved.bundles > 0 then return saved end
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
  if not ok or not data or not data.lines then return end
  local texts = {}
  for _, l in ipairs(data.lines) do texts[#texts + 1] = l.leftText or "" end
  local bundles = parseBundles(texts)
  if #bundles == 0 then return end
  local name, _, _, _, minLevel = ns.GetItemInfo(id)
  saved = { name = name or ns.ItemName(id), level = minLevel, bundles = bundles }
  ns.db.crates[id] = saved
  return saved
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------
-- Item names to IDs, from everything priced or named so far.
local nameIndex, nameIndexTime = {}, 0
local function idForName(name)
  if GetTime() - nameIndexTime > 30 then
    nameIndex, nameIndexTime = {}, GetTime()
    for id, n in pairs(ns.db.itemNames) do nameIndex[n] = id end
    for id in pairs(ns.db.prices[ns.MarketKey()] or {}) do
      local n = ns.GetItemInfo(id)
      if n then nameIndex[n] = id end
    end
    for id in pairs(ns.db.vendorBuy) do
      local n = ns.GetItemInfo(id)
      if n then nameIndex[n] = id end
    end
  end
  return nameIndex[name]
end

-- What buying qty of an item costs: from a vendor, or across the cheapest auction
-- listings (the price ladder saved by scans). nil if unknown or not enough listed.
function ns:CostToBuy(id, qty)
  local vendor = ns:GetVendorBuyPrice(id)
  if vendor then return vendor * qty end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not rec or rec.none or not rec.m then return end
  if rec.l then
    local cost, got = 0, 0
    for p, c in rec.l:gmatch("(%d+):(%d+)") do
      p, c = tonumber(p), tonumber(c)
      local take = math.min(c - got, qty - got)
      if take > 0 then cost, got = cost + take * p, got + take end
      if got >= qty then return cost end
    end
    -- More than the ladder holds: the rest at the average price.
    return cost + (qty - got) * (rec.a or rec.m)
  end
  return qty * (rec.a or rec.m)
end

local function bagCount(id)
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  return id and count and count(id, false, false, true) or 0
end

-- Favor a crate pays: learned from turn-ins, otherwise the tier estimate.
local function favorFor(name)
  local learned = ns.db.crateFavor[name]
  if learned and learned.n > 0 then return learned.sum / learned.n, true end
  return TIER_FAVOR[tierOf(name) or ""], false
end

-- Everything about one crate: bundles with costs, the cheapest, totals.
function ns:CrateReport(id)
  local info = crateInfo(id)
  if not info then return end
  local r = { id = id, name = info.name, level = info.level, bundles = {} }
  for _, parts in ipairs(info.bundles) do
    local b = { parts = {}, cost = 0, have = true }
    for _, p in ipairs(parts) do
      local pid = idForName(p.name)
      local cost = pid and ns:CostToBuy(pid, p.qty)
      local bags, bank, alts, byAlt = ns:ItemLocations(pid)
      local owned = bags + bank + alts
      b.parts[#b.parts + 1] = { id = pid, name = p.name, qty = p.qty, cost = cost, owned = owned,
        bags = bags, bank = bank, alts = alts, byAlt = byAlt }
      if cost then b.cost = b.cost + cost else b.cost = nil end
      if owned < p.qty then b.have = false end
    end
    r.bundles[#r.bundles + 1] = b
    if b.cost and (not r.cheapest or b.cost < r.cheapest.cost) then r.cheapest = b end
  end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  r.owned = bagCount(id) > 0
  r.cratePrice = (not r.owned) and rec and not rec.none and rec.m or nil
  r.favor, r.learned = favorFor(info.name)
  if r.cheapest then
    r.total = r.cheapest.cost + (r.cratePrice or 0)
    if r.favor and r.favor > 0 then r.perFavor = r.total / r.favor end
  end
  return r
end

-- Every crate seen: in the last scan or in the bags.
function ns:KnownCrates()
  local ids, seen = {}, {}
  local function consider(id)
    if seen[id] then return end
    seen[id] = true
    if isCrate(ns.ItemName(id)) then ids[#ids + 1] = id end
  end
  for id in pairs(ns.db.prices[ns.MarketKey()] or {}) do consider(id) end
  for id in pairs(ns.db.crates) do consider(id) end
  if C_Container then
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
      for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then consider(info.itemID) end
      end
    end
  end
  return ids
end

---------------------------------------------------------------------------
-- Learning Favor from turn-ins: when Favor goes up, credit the crate that most
-- recently left the bags.
---------------------------------------------------------------------------
local lastFavor, cratesInBags, lastCrateGone = nil, {}, nil

local function crateCounts()
  local counts = {}
  if not C_Container then return counts end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local name = info and info.itemID and ns.ItemName(info.itemID)
      if isCrate(name) then counts[name] = (counts[name] or 0) + (info.stackCount or 1) end
    end
  end
  return counts
end

local function favorNow()
  local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, FAVOR)
  return ok and info and info.quantity or nil
end

ns:On("BAG_UPDATE_DELAYED", function()
  if not ns.db then return end
  local now = crateCounts()
  for name, n in pairs(cratesInBags) do
    if (now[name] or 0) < n then lastCrateGone = { name = name, t = GetTime() } end
  end
  cratesInBags = now
end)

ns:On("CURRENCY_DISPLAY_UPDATE", function(currencyID)
  if currencyID and currencyID ~= FAVOR then return end
  local q = favorNow()
  if not q then return end
  if lastFavor and q > lastFavor and lastCrateGone and GetTime() - lastCrateGone.t < 600 then
    local gain = q - lastFavor
    -- The first crate ever pays a one-time 50 through a quest; don't learn from that.
    if gain < 40 then
      local l = ns.db.crateFavor[lastCrateGone.name] or { sum = 0, n = 0 }
      l.sum, l.n = l.sum + gain, l.n + 1
      ns.db.crateFavor[lastCrateGone.name] = l
      ns:Debug("Crate", lastCrateGone.name, "paid", gain, "Favor")
    end
    lastCrateGone = nil
  end
  lastFavor = q
  if ns.db then ns.db.favor[ns.CharKey()] = q end
end)

ns:On("PLAYER_ENTERING_WORLD", function()
  C_Timer.After(3, function()
    lastFavor = favorNow()
    if lastFavor and ns.db then ns.db.favor[ns.CharKey()] = lastFavor end
    cratesInBags = crateCounts()
  end)
end)

---------------------------------------------------------------------------
-- Tooltip line on crates
---------------------------------------------------------------------------
function ns:CrateTooltipLine(id)
  if not ns.db.settings.crates then return end
  if not isCrate(ns.ItemName(id)) then return end
  local r = ns:CrateReport(id)
  if not r or not r.cheapest then return end
  local parts = {}
  for _, p in ipairs(r.cheapest.parts) do parts[#parts + 1] = p.qty .. " " .. p.name end
  local per = r.perFavor and (", about %s per Favor"):format(money(r.cheapest.cost / r.favor)) or ""
  return ("Cheapest fill: %s, %s%s"):format(table.concat(parts, " + "), money(r.cheapest.cost), per)
end

---------------------------------------------------------------------------
-- The Crates tab
---------------------------------------------------------------------------
local ROW = 24
local f
local rows, details = {}, {}
local openID
local COLS = {
  { key = "name", label = "Crate" },
  { key = "level", label = "Level", w = 44 },
  { key = "fill", label = "Cheapest fill", w = 190 },
  { key = "fillCost", label = "Fill cost", w = 80 },
  { key = "cratePrice", label = "Crate", w = 74 },
  { key = "total", label = "Total", w = 80 },
  { key = "favor", label = "Favor", w = 50 },
  { key = "perFavor", label = "Per Favor", w = 80 },
}

function ns:BuildCrates(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f.info = T:Text(f, 12, T.dim)
  f.info:SetPoint("TOPLEFT", 2, -2)
  f.info:SetPoint("RIGHT", f, "RIGHT", -2, 0)
  f.info:SetJustifyH("LEFT")
  f.header = CreateFrame("Frame", nil, f)
  f.header:SetPoint("TOPLEFT", 0, -38)
  f.header:SetPoint("TOPRIGHT", 0, -38)
  f.header:SetHeight(22)
  T:Fill(f.header, { 1, 1, 1, 0.05 })
  f.heads = {}
  f.sf, f.content = T:Scroll(f)
  f.sf:SetPoint("TOPLEFT", 0, -62)
  f.sf:SetPoint("BOTTOMRIGHT")
  f.empty = T:Text(f.content, 12, T.dim)
  f.empty:SetPoint("TOPLEFT", 8, -8)
  f.empty:SetText("No Waylaid Crates seen yet. Run a full scan, or put a crate in your bags.")
  return f
end

local function layout(width)
  local fixed = 0
  for _, c in ipairs(COLS) do fixed = fixed + (c.w or 0) + 8 end
  local x, out = 4, {}
  for _, c in ipairs(COLS) do
    local w = c.w or math.max(160, width - fixed - 4)
    out[c.key] = { x = x, w = w }
    x = x + w + 8
  end
  return out
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, f.content)
  r:SetHeight(ROW)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cells = {}
  for _, c in ipairs(COLS) do
    local fs = T:Text(r, 12)
    fs:SetWordWrap(false)
    fs:SetJustifyH((c.key == "name" or c.key == "fill") and "LEFT" or "RIGHT")
    r.cells[c.key] = fs
  end
  r:SetScript("OnClick", function(self) openID = (openID ~= self.id) and self.id or nil; ns:RefreshCrates() end)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetItemByID(self.id)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

-- Opened crate: every bundle, cheapest marked, click an item to search for it.
local function getDetail(i)
  if details[i] then return details[i] end
  local d = CreateFrame("Frame", nil, f.content)
  T:Fill(d, { 1, 1, 1, 0.035 })
  d.lines = {}
  details[i] = d
  return d
end

local function detailLine(d, j)
  if d.lines[j] then return d.lines[j] end
  local b = CreateFrame("Button", nil, d)
  b:SetHeight(20)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(14, 14)
  b.icon:SetPoint("LEFT", 14, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.text = T:Text(b, 11)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetJustifyH("LEFT")
  b.right = T:Text(b, 11)
  b.right:SetPoint("RIGHT", -10, 0)
  b.right:SetJustifyH("RIGHT")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
  b:SetScript("OnClick", function(self)
    if self.itemID and not ns:SearchAuctionHouse(self.itemID) then
      ns:Print("Open the auction house, then click an item to search for it.")
    end
  end)
  -- Hover: which alts have it.
  b:SetScript("OnEnter", function(self)
    local p = self.part
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(p.name, 1, 1, 1)
    GameTooltip:AddDoubleLine("In your bags", tostring(p.bags or 0), 0.85, 0.85, 0.85, 1, 1, 1)
    GameTooltip:AddDoubleLine("In your bank", tostring(p.bank or 0), 0.85, 0.85, 0.85, 1, 1, 1)
    for name, n in pairs(p.byAlt or {}) do GameTooltip:AddDoubleLine(name, tostring(n), 0.85, 0.85, 0.85, 1, 1, 1) end
    GameTooltip:AddLine("Bank and alts as of their last visit. Click to search the auction house.", T.accent[1], T.accent[2], T.accent[3], true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  d.lines[j] = b
  return b
end

function ns:RefreshCrates()
  if not f or not f:IsShown() then return end
  local width = f:GetWidth() - 12
  local lay = layout(width)
  for i, c in ipairs(COLS) do
    local h = f.heads[i]
    if not h then h = T:Text(f.header, 11, T.dim); f.heads[i] = h end
    h:ClearAllPoints()
    h:SetPoint("LEFT", f.header, "LEFT", lay[c.key].x, 0)
    h:SetWidth(lay[c.key].w)
    h:SetJustifyH((c.key == "name" or c.key == "fill") and "LEFT" or "RIGHT")
    h:SetText(c.label .. (c.key == "perFavor" and " ^" or ""))
  end

  local reports, unread = {}, 0
  for _, id in ipairs(ns:KnownCrates()) do
    local r = ns:CrateReport(id)
    if r then reports[#reports + 1] = r else unread = unread + 1 end
  end
  table.sort(reports, function(a, b)
    if (a.perFavor ~= nil) ~= (b.perFavor ~= nil) then return a.perFavor ~= nil end
    if a.perFavor and b.perFavor and a.perFavor ~= b.perFavor then return a.perFavor < b.perFavor end
    return (a.name or "") < (b.name or "")
  end)

  local favor = ns.db.favor[ns.CharKey()]
  f.info:SetText(("Cheapest way to fill each Waylaid Crate at your last scan's prices, best Favor per gold first. You have %s Merchant's Favor on this character.%s Favor marked * is an estimate until you turn one in. Click a crate for every bundle."):format(
    favor and tostring(favor) or "?", unread > 0 and (" %d crates still loading."):format(unread) or ""))

  f.content:SetWidth(width)
  local y, n, nd = 0, 0, 0
  for i, r in ipairs(reports) do
    n = n + 1
    local row = getRow(n)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    row.id = r.id
    row.stripe:SetShown(i % 2 == 0)
    row.icon:SetTexture(ns:ItemIcon(r.id))
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", lay.name.x, 0)
    local parts = {}
    for _, p in ipairs(r.cheapest and r.cheapest.parts or {}) do parts[#parts + 1] = p.qty .. " " .. p.name end
    local values = {
      name = (r.name or "?"):gsub("^Waylaid Crate: ", "") .. (r.owned and dim("  in bags") or ""),
      level = r.level and tostring(r.level) or "",
      fill = #parts > 0 and table.concat(parts, " + ") .. (r.cheapest.have and dim(" (have)") or "") or dim("no prices yet"),
      fillCost = r.cheapest and money(r.cheapest.cost) or dim("?"),
      cratePrice = r.owned and dim("owned") or money(r.cratePrice),
      total = money(r.total),
      favor = r.favor and (("%g"):format(math.floor(r.favor * 10 + 0.5) / 10) .. (r.learned and "" or "*")) or "?",
      perFavor = r.perFavor and ("|cff7fd39c" .. money(r.perFavor) .. "|r") or dim("?"),
    }
    for key, fs in pairs(row.cells) do
      fs:ClearAllPoints()
      local x, w = lay[key].x, lay[key].w
      if key == "name" then x, w = x + 22, w - 22 end
      fs:SetPoint("LEFT", row, "LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetText(values[key])
    end
    row:Show()
    y = y + ROW

    if openID == r.id then
      nd = nd + 1
      local d = getDetail(nd)
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
      d:SetWidth(width)
      local j = 0
      for _, b in ipairs(r.bundles) do
        for k, p in ipairs(b.parts) do
          j = j + 1
          local line = detailLine(d, j)
          line:ClearAllPoints()
          line:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -(4 + (j - 1) * 20))
          line:SetWidth(width)
          line.itemID, line.part = p.id, p
          line.icon:SetTexture(p.id and ns:ItemIcon(p.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
          local mark = (b == r.cheapest and k == 1) and (T:AccentCode() .. "cheapest|r  ") or ""
          line.text:SetText(("%s%d x %s  %s"):format(mark, p.qty, p.name,
            dim(("you have %d (bags %d, bank %d, alts %d)%s"):format(p.owned, p.bags or 0, p.bank or 0, p.alts or 0,
              p.id and "" or ", price unknown"))))
          line.right:SetText(k == 1 and (b.cost and money(b.cost) or dim("?")) or "")
          line:Show()
        end
      end
      for k = j + 1, #d.lines do d.lines[k]:Hide() end
      d:SetHeight(j * 20 + 8)
      d:Show()
      y = y + j * 20 + 12
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  for i = nd + 1, #details do details[i]:Hide() end
  f.empty:SetShown(n == 0)
  f.content:SetHeight(math.max(y, 30))
  f.sf.UpdateScrollBar()
end
