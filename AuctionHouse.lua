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

-- A row's price per item and its item ID, whichever way the row stores them.
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
  return d.unitPrice or d.buyoutAmount, id
end

-- How many are listed at or below a price, from the auction house's own results.
local function availableAt(id, limit, commodity)
  local n = 0
  if commodity then
    for i = 1, (C_AuctionHouse.GetNumCommoditySearchResults(id) or 0) do
      local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
      if r and r.unitPrice and r.unitPrice <= limit then n = n + (r.quantity or 0) end
    end
  else
    local key = C_AuctionHouse.MakeItemKey(id)
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

-- Watch one buy page (commodities or items).
local function watch(page, commodity)
  if not page or page.flWatcher then return end
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

    local shownID = ns.LastShownItem and ns.LastShownItem()
    local id, anyPrice, limit
    local found = eachRow(list, function(row)
      local price, rowID = rowInfo(row, shownID)
      id = id or rowID
      limit = limit or ns:BuyLimit(rowID)
      if price then anyPrice = true end
      tint(row, price ~= nil and limit ~= nil and price <= limit)
    end)
    if not found then debugOnce("list" .. tostring(commodity), "Auction house: couldn't find the price list rows.") end
    if found and not anyPrice then
      debugOnce("price" .. tostring(commodity), "Auction house: found rows but couldn't read their prices.")
    end

    id = id or shownID
    limit = limit or ns:BuyLimit(id)
    if id and limit then
      w.note:SetText(("Worth buying up to %s: %d available"):format(ns.Money(limit), availableAt(id, limit, commodity)))
    else
      w.note:SetText("")
    end
  end)
end

function ns:SetUpAuctionHighlights()
  local ah = AuctionHouseFrame
  if not ah then return end
  watch(ah.CommoditiesBuyFrame, true)
  watch(ah.ItemBuyFrame, false)
end
ns:On("AUCTION_HOUSE_SHOW", function() C_Timer.After(0.1, function() ns:SetUpAuctionHighlights() end) end)
