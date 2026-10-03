local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Waylaid Crates: fill one with any bundle from its list (read from the crate's
-- tooltip), turn it in for Merchant's Favor. This works out the cheapest bundle at
-- today's prices, the total with the crate's own price, and gold per Favor.
-- Every turn-in pays the same (TURN_IN_FAVOR, TURN_IN_PAY).
---------------------------------------------------------------------------
local FAVOR = 3402
local PREFIX = "Waylaid Crate"
-- What a turn-in pays: every filled crate becomes a Sealed Apprentice Crate, which pays
-- 5s and 10 Merchant's Favor whatever the crate's tier or quality (owner's turn-ins,
-- beta, October 3). The first turn-in is a one-time quest with more; not counted.
local TURN_IN_FAVOR = 10
local TURN_IN_PAY = 500

local function dim(t) return "|cff888888" .. t .. "|r" end
local function money(v) return v and ns.Money(math.floor(v + 0.5)) or dim("?") end

local function isCrate(name) return name and name:sub(1, #PREFIX) == PREFIX end
-- A filled crate: "Sealed Apprentice Crate".
local function isSealed(name) return name and name:find("^Sealed") and name:find("Crate", 1, true) and true or false end

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
-- Whichever is cheaper, a vendor or the auction house (a limited vendor's price used
-- to win even when the auction house was far cheaper).
local function ahCostToBuy(id, qty)
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

-- The most you'd pay for one, buying qty from the cheapest listings up (the last price
-- level needed), so a shopping list's limit can get them all. nil if not listed.
local function priceToGet(id, qty)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not rec or rec.none or not rec.m then return end
  local top
  for p, c in (rec.l or ""):gmatch("(%d+):(%d+)") do
    top = tonumber(p)
    if tonumber(c) >= qty then return top end
  end
  return math.max(top or 0, rec.a or rec.m)
end

-- Puts a crate's cheapest fill (or the bundle given) on a shopping list named after the
-- crate (owner, October 3). "Keep this many", so what's in your bags and bank counts.
function ns:CrateToShoppingList(r, bundle)
  bundle = bundle or (r and (r.cheapest or r.bundles[1]))
  if not bundle then return end
  local name = "Crate: " .. (r.name or "?"):gsub("^Waylaid Crate: ", "")
  local list
  for _, l in ipairs(ns:ShoppingLists()) do if l.name == name then list = l end end
  if not list then
    list = ns:NewShoppingList(name)
  else
    for i, l in ipairs(ns:ShoppingLists()) do if l == list then ns:SelectShoppingList(i) end end
  end
  -- Temporary (owner, October 3): it goes when the last crate is filled, or after a week.
  list.temp, list.tempT = r.name, time()
  -- How many crates: the crate's own Want (kept if the list was made before).
  local count = 1
  for _, e in ipairs(list.items) do
    if e.id == r.id and e.qty then count = e.qty end
  end
  -- A different bundle than last time: the old bundle's items go.
  local newParts, keep = {}, { [r.id or 0] = true }
  for _, p in ipairs(bundle.parts) do
    if p.id then newParts[#newParts + 1] = { p.id, p.qty }; keep[p.id] = true end
  end
  for _, old in ipairs(list.crateParts or {}) do
    if not keep[old[1]] then
      for i = #list.items, 1, -1 do if list.items[i].id == old[1] then table.remove(list.items, i) end end
    end
  end
  list.crateID, list.crateParts = r.id, newParts

  local added, unknown = 0, {}
  -- The crate itself too (owner, October 3): done if you have enough of them.
  if r.id then
    local e = ns:AddToShoppingList(list, r.id, priceToGet(r.id, count) or ns:GetVendorBuyPrice(r.id) or 0, count)
    e.done = nil
    added = added + 1
  end
  for _, p in ipairs(bundle.parts) do
    if p.id then
      local e = ns:AddToShoppingList(list, p.id, priceToGet(p.id, p.qty * count) or ns:GetVendorBuyPrice(p.id) or 0)
      e.done = nil   -- sent again: back in the queue if you're short
      added = added + 1
    else
      unknown[#unknown + 1] = p.name
    end
  end
  ns:ScaleCrateList(list)
  ns:Print(("Added %d %s for %s to the shopping list \"%s\". Set the crate's Want there to fill more than one; tick Use in the buy queue to buy what you're short (/fl lists). The list goes when you fill the last crate.%s"):format(
    added, added == 1 and "item" or "items", r.name or "the crate", name,
    #unknown > 0 and (" Not added (not seen in a scan yet): " .. table.concat(unknown, ", ") .. ".") or ""))
  return list
end

-- A crate list's crate Want is how many crates to fill: each bundle item wants its
-- amount times that, like a Craft item's materials (owner, October 3). Limits go up
-- if more are needed than the old limit could buy. Returns the item IDs changed.
function ns:ScaleCrateList(list)
  local count = 1
  for _, e in ipairs(list.items) do
    if e.id == list.crateID then count = e.qty or 1 end
  end
  local ids = {}
  for _, part in ipairs(list.crateParts or {}) do
    for _, e in ipairs(list.items) do
      if e.id == part[1] then
        local want = part[2] * count
        if e.qty ~= want then
          e.qty = want
          if ns:HaveCount(e.id) < want then e.done = nil end
          local need = priceToGet(e.id, want)
          if need and (e.max or 0) > 0 and need > e.max then e.max = need end
          ids[#ids + 1] = e.id
        end
      end
    end
  end
  return ids
end

-- Temporary crate lists: filling a crate (crateName) takes one off its list, and the
-- list goes with the last one; with no name, lists older than a week go.
local TEMP_LIST_SECONDS = 7 * 86400
local function dropCrateLists(crateName)
  local lists = ns:ShoppingLists()
  for i = #lists, 1, -1 do
    local l = lists[i]
    if l.temp and crateName and l.temp == crateName then
      local crate
      for _, e in ipairs(l.items) do if e.id == l.crateID then crate = e end end
      local left = crate and (crate.qty or 1) - 1 or 0
      if left > 0 then
        crate.qty = left
        ns:ScaleCrateList(l)
        ns:Print(("Shopping list \"%s\": %d %s left to fill."):format(l.name or "?", left, left == 1 and "crate" or "crates"))
      else
        ns:DeleteShoppingList(i)
        ns:Print(("Removed the shopping list \"%s\" (last crate filled)."):format(l.name or "?"))
      end
    elseif l.temp and not crateName and time() - (l.tempT or 0) > TEMP_LIST_SECONDS then
      ns:DeleteShoppingList(i)
      ns:Print(("Removed the shopping list \"%s\" (a week old)."):format(l.name or "?"))
    end
  end
end
ns:OnReady(function() dropCrateLists() end)

function ns:CostToBuy(id, qty)
  local vendor = ns:GetVendorBuyPrice(id)
  local ah = ahCostToBuy(id, qty)
  if vendor and ah then return math.min(vendor * qty, ah) end
  return vendor and vendor * qty or ah
end

local function bagCount(id)
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  return id and count and count(id, false, false, true) or 0
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
  r.favor, r.pay = TURN_IN_FAVOR, TURN_IN_PAY
  if r.cheapest then
    r.total = r.cheapest.cost + (r.cratePrice or 0)
    -- What it really costs once the turn-in's money is back. Below zero, the crate is
    -- a straight gold profit (the "raw gold shuffle" with cheap crates).
    r.net = r.total - (r.pay or 0)
    if r.favor and r.favor > 0 then r.perFavor = math.max(r.net, 0) / r.favor; r.sortKey = r.net / r.favor end
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
-- Filling a crate: the Waylaid Crate leaves the bags and a Sealed Apprentice Crate
-- turns up in the same update. That's when its materials are used, so its shopping
-- list counts down then (a crate sold or mailed away doesn't count).
---------------------------------------------------------------------------
local lastFavor, cratesInBags, sealedInBags = nil, {}, 0

local function crateCounts()
  local counts, sealed = {}, 0
  if not C_Container then return counts, sealed end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local name = info and info.itemID and ns.ItemName(info.itemID)
      if isCrate(name) then counts[name] = (counts[name] or 0) + (info.stackCount or 1)
      elseif isSealed(name) then sealed = sealed + (info.stackCount or 1) end
    end
  end
  return counts, sealed
end

local function favorNow()
  local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, FAVOR)
  return ok and info and info.quantity or nil
end

ns:On("BAG_UPDATE_DELAYED", function()
  if not ns.db then return end
  local now, sealed = crateCounts()
  if sealed > sealedInBags then
    for name, n in pairs(cratesInBags) do
      if (now[name] or 0) < n then
        ns:Debug("Crate filled:", name)
        dropCrateLists(name)
      end
    end
  end
  cratesInBags, sealedInBags = now, sealed
end)

ns:On("CURRENCY_DISPLAY_UPDATE", function(currencyID)
  if currencyID and currencyID ~= FAVOR then return end
  local q = favorNow()
  if not q then return end
  if lastFavor and q > lastFavor then ns:Debug("Merchant's Favor:", "+" .. (q - lastFavor)) end
  lastFavor = q
  if ns.db then ns.db.favor[ns.CharKey()] = q end
end)

ns:On("PLAYER_ENTERING_WORLD", function()
  C_Timer.After(3, function()
    lastFavor = favorNow()
    lastMoney = GetMoney and GetMoney()
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
  local per = ""
  if r.net and r.net < 0 then
    per = (", turn-in pays %s more than that"):format(money(-r.net))
  elseif r.perFavor then
    per = (", about %s per Favor after the turn-in's money"):format(money(r.perFavor))
  end
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
  { key = "fill", label = "Cheapest fill", w = 150 },
  { key = "fillCost", label = "Fill cost", w = 74 },
  { key = "cratePrice", label = "Crate", w = 70 },
 { key = "total", label = "Net cost", w = 80 },
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
  -- The cheapest fill onto a shopping list, to buy with the Buy queue.
  d.toList = T:Button(d, "Add cheapest fill to a shopping list", 240, function()
    if d.report then ns:CrateToShoppingList(d.report) end
  end, 20)
  d.toList:SetPoint("BOTTOMLEFT", 14, 6)
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
    if (a.sortKey ~= nil) ~= (b.sortKey ~= nil) then return a.sortKey ~= nil end
    if a.sortKey and b.sortKey and a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
    return (a.name or "") < (b.name or "")
  end)

  local favor = ns.db.favor[ns.CharKey()]
  f.info:SetText(("Cheapest way to fill each Waylaid Crate at your last scan's prices, best Favor per gold first. After your first turn-in (a one-time quest), every crate pays 5s and 10 Merchant's Favor; Net cost takes the 5s off, and shows green if a crate somehow pays for itself. You have %s Merchant's Favor on this character.%s Click a crate for every bundle."):format(
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
     total = r.net and (r.net < 0 and ("|cff7fd39c+" .. money(-r.net) .. "|r") or money(r.net)) or dim("?"),
      perFavor = r.net and r.net <= 0 and "|cff7fd39cfree|r" or r.perFavor and ("|cff7fd39c" .. money(r.perFavor) .. "|r") or dim("?"),
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
      d.report = r
      d.toList:SetShown(r.cheapest ~= nil)
      local extra = r.cheapest and 30 or 0
      d:SetHeight(j * 20 + 8 + extra)
      d:Show()
      y = y + j * 20 + 12 + extra
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  for i = nd + 1, #details do details[i]:Hide() end
  f.empty:SetShown(n == 0)
  f.content:SetHeight(math.max(y, 30))
  f.sf.UpdateScrollBar()
end
