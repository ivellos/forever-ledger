local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- On the auction house buy pages, tint the listings worth buying: at or below the
-- item's "buy at or below" price, or below what a vendor pays. A line above the
-- list says how many are available at that price.
---------------------------------------------------------------------------
local REFRESH = 0.3          -- seconds between checks while a buy page is open
local reported = {}          -- debug messages already shown, so they print once

local function debugOnce(key, ...)
  if reported[key] then return end
  reported[key] = true
  ns:Debug(...)
end

-- The most worth paying for one of an item, or nil if nothing makes it worth buying.
function ns:BuyLimit(id)
  if not id then return end
  local limit = ns:BuyAtOrBelow(id)
  local sell = ns:GetSellPrice(id)
  if sell and sell > 1 and (not limit or sell - 1 > limit) then limit = sell - 1 end
  return limit
end

-- Call fn(row) for each row frame the list shows.
local function eachRow(list, fn)
  local box = list and list.ScrollBox
  if box and box.ForEachFrame then box:ForEachFrame(fn); return true end
  if box and box.GetFrames then
    for _, f in ipairs(box:GetFrames()) do fn(f) end
    return true
  end
  local sf = list and list.ScrollFrame
  if sf and sf.buttons then
    for _, b in ipairs(sf.buttons) do if b:IsShown() then fn(b) end end
    return true
  end
  return false
end

-- A row's price per item, item ID and item key, whichever way the row stores them.
-- Buy pages have unitPrice (commodities) or buyoutAmount (items); the search results
-- list has minPrice.
local function rowInfo(row, fallbackID)
  local d = row.rowData
  if not d and row.GetElementData then
    local ok, e = pcall(row.GetElementData, row)
    if ok then d = e end
  end
  if type(d) == "table" and d.rowData then d = d.rowData end
  if type(d) == "number" and fallbackID and C_AuctionHouse.GetCommoditySearchResultInfo then
    d = C_AuctionHouse.GetCommoditySearchResultInfo(fallbackID, d)
  end
  if type(d) ~= "table" then return end
  local id = d.itemID or (d.itemKey and d.itemKey.itemID) or fallbackID
  return d.unitPrice or d.buyoutAmount or d.minPrice, id, d.itemKey
end

-- How many are listed at or below a price, from the auction house's own results.
-- Items with random suffixes ("of the Bear") each have their own item key, so use
-- the key of what the page shows.
local function availableAt(id, limit, commodity, itemKey)
  local n = 0
  if commodity then
    for i = 1, (C_AuctionHouse.GetNumCommoditySearchResults(id) or 0) do
      local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
      if r and r.unitPrice and r.unitPrice <= limit then n = n + (r.quantity or 0) end
    end
  else
    local key = itemKey or C_AuctionHouse.MakeItemKey(id)
    for i = 1, (C_AuctionHouse.GetNumItemSearchResults(key) or 0) do
      local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
      if r and r.buyoutAmount and r.buyoutAmount <= limit then n = n + math.max(r.quantity or 1, 1) end
    end
  end
  return n
end

local function tint(row, on)
  if not row.flTint then
    if not on then return end
    -- Above the row's own background, below its text.
    row.flTint = row:CreateTexture(nil, "ARTWORK", nil, -8)
    row.flTint:SetAllPoints()
    row.flTint:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.22)
  end
  row.flTint:SetShown(on)
end

-- Watch one page: "commodity" or "item" buy pages (one item, with a line above the
-- list), or "browse" (search results, each row a different item).
local function watch(page, kind)
  if not page or page.flWatcher then return end
  local commodity, browse = kind == "commodity", kind == "browse"
  local list = page.ItemList
  local w = CreateFrame("Frame", nil, page)
  page.flWatcher = w
  w.note = T:Text(page, 12, T.accent, "OVERLAY")
  if list then
    w.note:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 4, 6)
  else
    w.note:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -8)
  end
  local elapsed = 0
  w:SetScript("OnUpdate", ns.Timed("Auction house tint", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < REFRESH then return end
    elapsed = 0
    if not ns.db.settings.ahHighlight then
      w.note:SetText("")
      eachRow(list, function(row) tint(row, false) end)
      return
    end

    local shownID = not browse and ns.LastShownItem and ns.LastShownItem() or nil
    -- Limits per item, kept for a few seconds so a list of many items stays cheap.
    if not w.limits or GetTime() - w.limitsTime > 5 then w.limits, w.limitsTime = {}, GetTime() end
    local limits = w.limits
    local function limitFor(itemID)
      if not itemID then return end
      if limits[itemID] == nil then limits[itemID] = ns:BuyLimit(itemID) or false end
      return limits[itemID] or nil
    end
    local id, key, anyPrice
    local found = eachRow(list, function(row)
      local price, rowID, rowKey = rowInfo(row, shownID)
      id, key = id or rowID, key or rowKey
      local limit = limitFor(rowID)
      if price then anyPrice = true end
      tint(row, price ~= nil and limit ~= nil and price <= limit)
    end)
    -- Report only if it keeps failing (about 3 seconds): during a purchase the list
    -- is briefly empty, which is normal.
    w.fails = (not found or not anyPrice) and (w.fails or 0) + 1 or 0
    if w.fails >= 10 then
      if not found then debugOnce("list" .. kind, "Auction house: couldn't find the rows on the", kind, "page.") end
      if found and not anyPrice then debugOnce("price" .. kind, "Auction house: couldn't read prices on the", kind, "page.") end
    end

    if browse then return end
    id = id or shownID
    local limit = limitFor(id)
    if id and limit then
      w.note:SetText(("Worth buying up to %s: %d available"):format(ns.Money(limit), availableAt(id, limit, commodity, key)))
    else
      w.note:SetText("")
    end
  end))
end

function ns:SetUpAuctionHighlights()
  local ah = AuctionHouseFrame
  if not ah then return end
  watch(ah.CommoditiesBuyFrame, "commodity")
  watch(ah.ItemBuyFrame, "item")
  watch(ah.BrowseResultsFrame, "browse")
end
ns:On("AUCTION_HOUSE_SHOW", function() C_Timer.After(0.1, function() ns:SetUpAuctionHighlights() end) end)


---------------------------------------------------------------------------
-- Disenchant finder: a panel beside the auction house listing green armor and
-- weapons in chosen item level bands, from the last scan, with what each is worth
-- to disenchant. Blizzard's search can't filter by item level, so this does.
---------------------------------------------------------------------------
local finder
local FINDER_ROWS = 200
local asked = {}        -- itemID = when item details were requested (asked once per session)
local GIVE_UP = 10      -- seconds before an item that never loads stops counting as "loading"

local function finderSettings()
  local s = ns.db.settings.deFinder
  if not s.bands then s.bands = { [20] = true } end
  if s.armor == nil then s.armor = true end
  if s.weapon == nil then s.weapon = true end
  if s.profitable == nil then s.profitable = true end
  return s
end

-- Items to list: { id, ilvl, price, worth, profit, locked = skill needed or nil }.
local function finderItems()
  local s = finderSettings()
  local market = ns.db.prices[ns.MarketKey()] or {}
  local skill = ns.EnchantingSkill and ns.EnchantingSkill() or 0
  local out, waiting, now = {}, 0, GetTime()
  for id, rec in pairs(market) do
    if rec.m and not rec.none then
      local name, _, _, ilvl = ns.GetItemInfo(id)
      if not name then
        -- Ask once; some items never load, and asking again every refresh made the game lag.
        if not asked[id] then
          asked[id] = now
          if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        end
        if now - asked[id] < GIVE_UP then waiting = waiting + 1 end
      else
        local yield = ns:DisenchantYield(id)
        if yield and s.bands[yield.band] and s[yield.kind] then
          local worth
          for _, o in ipairs(ns:Options(id)) do
            if o.kind == "disenchant" then worth = o.value; break end
          end
          local locked = skill < (yield.skill or 1) and yield.skill or nil
          local profit = worth and worth - rec.m or nil
          if not s.profitable or (profit and profit > 0) then
            out[#out + 1] = { id = id, ilvl = ilvl, price = rec.m, worth = worth, profit = profit, locked = locked }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if (a.profit or -math.huge) ~= (b.profit or -math.huge) then return (a.profit or -math.huge) > (b.profit or -math.huge) end
    return a.price < b.price
  end)
  return out, waiting
end

local function buildFinder()
  local ah = AuctionHouseFrame
  finder = CreateFrame("Frame", "ForeverLedgerDisenchantFinder", ah)
  finder:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
  finder:SetPoint("BOTTOMLEFT", ah, "BOTTOMRIGHT", 4, 0)
  finder:SetWidth(420)
  finder:EnableMouse(true)
  T:Fill(finder, T.bg)
  T:Border(finder)

  local title = T:Text(finder, 14, T.accent)
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Disenchant finder")
  finder.info = T:Text(finder, 11, T.dim)
  finder.info:SetPoint("TOPLEFT", 12, -30)
  finder.info:SetPoint("RIGHT", finder, "RIGHT", -12, 0)
  finder.info:SetJustifyH("LEFT")

  local s = finderSettings()
  local function changed() ns:RefreshDisenchantFinder() end

  -- Item level band checkboxes, four to a row.
  local y = 52
  for i, b in ipairs(ns.DISENCHANT_BANDS) do
    local cb = T:Check(finder, function(self) s.bands[b.key] = self:GetChecked() or nil; changed() end)
    cb:SetPoint("TOPLEFT", 12 + ((i - 1) % 4) * 100, -(y + math.floor((i - 1) / 4) * 20))
    cb.label:SetText(b.label)
    cb:SetChecked(s.bands[b.key])
  end
  y = y + math.ceil(#ns.DISENCHANT_BANDS / 4) * 20 + 6

  local opts = { { "armor", "Armor" }, { "weapon", "Weapons" }, { "profitable", "Only worth disenchanting" } }
  local x = 12
  for _, o in ipairs(opts) do
    local cb = T:Check(finder, function(self) s[o[1]] = self:GetChecked(); changed() end)
    cb:SetPoint("TOPLEFT", x, -y)
    cb.label:SetText(o[2])
    cb:SetChecked(s[o[1]])
    x = x + 20 + cb.label:GetStringWidth() + 18
  end
  y = y + 26

  local header = CreateFrame("Frame", nil, finder)
  header:SetPoint("TOPLEFT", 6, -y)
  header:SetPoint("TOPRIGHT", -6, -y)
  header:SetHeight(20)
  T:Fill(header, { 1, 1, 1, 0.05 })
  local cols = { { "Item", 8, "LEFT" }, { "Price", 250, "RIGHT" }, { "Worth", 320, "RIGHT" }, { "Profit", 396, "RIGHT" } }
  for _, c in ipairs(cols) do
    local fs = T:Text(header, 11, T.dim)
    if c[3] == "LEFT" then fs:SetPoint("LEFT", c[2], 0) else fs:SetPoint("RIGHT", header, "LEFT", c[2], 0) end
    fs:SetText(c[1])
  end
  y = y + 22

  finder.sf, finder.content = T:Scroll(finder)
  finder.sf:SetPoint("TOPLEFT", 6, -y)
  finder.sf:SetPoint("BOTTOMRIGHT", -6, 36)
  finder.rows = {}

  local refresh = T:Button(finder, "Refresh", 90, changed, 22)
  refresh:SetPoint("BOTTOMLEFT", 10, 8)
  finder.count = T:Text(finder, 11, T.dim)
  finder.count:SetPoint("LEFT", refresh, "RIGHT", 10, 0)

  finder:SetScript("OnShow", changed)
  finder:SetShown(s.shown)
  if s.shown then C_Timer.After(0.1, changed) end
end

local function finderRow(i)
  local r = finder.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, finder.content)
  r:SetHeight(20)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.12)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = T:Text(r, 11)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.name:SetWidth(180)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.price, r.worth, r.profit = T:Text(r, 11), T:Text(r, 11), T:Text(r, 11)
  r.price:SetPoint("RIGHT", r, "LEFT", 244, 0)
  r.worth:SetPoint("RIGHT", r, "LEFT", 314, 0)
  r.profit:SetPoint("RIGHT", r, "LEFT", 390, 0)
  r:SetScript("OnClick", function(self) ns:SearchAuctionHouse(self.id) end)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(self.id)
    if self.locked then GameTooltip:AddLine(("Needs Enchanting %d to disenchant."):format(self.locked), 1, 0.4, 0.4) end
    GameTooltip:AddLine("Click to search the auction house for it.", T.accent[1], T.accent[2], T.accent[3])
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  finder.rows[i] = r
  return r
end

function ns:RefreshDisenchantFinder()
  if not finder or not finder:IsShown() then return end
  local items, waiting = finderItems()
  local n = math.min(#items, FINDER_ROWS)
  local width = finder.sf:GetWidth() - 12
  finder.content:SetWidth(width)
  for i = 1, n do
    local it, r = items[i], finderRow(i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", finder.content, "TOPLEFT", 0, -(i - 1) * 20)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    r.id, r.locked = it.id, it.locked
    r.icon:SetTexture(ns:ItemIcon(it.id))
    r.name:SetText(("%s |cff888888(%d)|r"):format(ns.ItemName(it.id), it.ilvl or 0))
    r.price:SetText(ns.Money(it.price))
    r.worth:SetText(it.locked and "|cffee8597skill|r" or (it.worth and ns.Money(math.floor(it.worth)) or "?"))
    local p = it.profit
    r.profit:SetText(p and ("|cff" .. (p >= 0 and "7fd39c" or "ee8597") .. (p < 0 and "-" or "") .. ns.Money(math.abs(math.floor(p))) .. "|r") or "")
    r:Show()
  end
  for i = n + 1, #finder.rows do finder.rows[i]:Hide() end
  finder.content:SetHeight(math.max(n * 20, 20))
  finder.sf.UpdateScrollBar()
  local newest = 0
  for _, rec in pairs(ns.db.prices[ns.MarketKey()] or {}) do newest = math.max(newest, rec.t or 0) end
  finder.info:SetText(("From your last scan (%s). Click an item to search for it."):format(newest > 0 and ns.Age(newest) or "none yet"))
  finder.count:SetText(("%d items%s"):format(#items, waiting > 0 and (", %d still loading"):format(waiting) or ""))
end

-- Item details arrive a moment after they're asked for; redraw once some of ours have,
-- at most every 3 seconds.
local finderQueued = false
ns:On("GET_ITEM_INFO_RECEIVED", function(id)
  if finderQueued or not asked[id] or not finder or not finder:IsShown() then return end
  finderQueued = true
  C_Timer.After(3, function() finderQueued = false; ns:RefreshDisenchantFinder() end)
end)

ns:On("AUCTION_HOUSE_SHOW", function()
  C_Timer.After(0.2, function()
    if not AuctionHouseFrame then return end
    if not finder then buildFinder() end
    if not ns.ahFinderButton then
      local b = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
      b:SetSize(150, 24)
      b:SetText("Disenchant finder")
      if ns.ahFullButton then b:SetPoint("RIGHT", ns.ahFullButton, "LEFT", -4, 0)
      else b:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -260, -2) end
      b:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 20)
      b:SetScript("OnClick", function()
        local s = finderSettings()
        s.shown = not finder:IsShown()
        finder:SetShown(s.shown)
      end)
      ns.ahFinderButton = b
    end
  end)
end)
ns.RefreshDisenchantFinder = ns.Timed("Disenchant finder", ns.RefreshDisenchantFinder)
