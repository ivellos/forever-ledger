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
  w:SetScript("OnUpdate", function(_, dt)
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
    if not found then debugOnce("list" .. kind, "Auction house: couldn't find the rows on the", kind, "page.") end
    if found and not anyPrice then debugOnce("price" .. kind, "Auction house: couldn't read prices on the", kind, "page.") end

    if browse then return end
    id = id or shownID
    local limit = limitFor(id)
    if id and limit then
      w.note:SetText(("Worth buying up to %s: %d available"):format(ns.Money(limit), availableAt(id, limit, commodity, key)))
    else
      w.note:SetText("")
    end
  end)
end

function ns:SetUpAuctionHighlights()
  local ah = AuctionHouseFrame
  if not ah then return end
  watch(ah.CommoditiesBuyFrame, "commodity")
  watch(ah.ItemBuyFrame, "item")
  watch(ah.BrowseResultsFrame, "browse")
end
ns:On("AUCTION_HOUSE_SHOW", function() C_Timer.After(0.1, function() ns:SetUpAuctionHighlights() end) end)
