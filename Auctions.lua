local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Your auctions (owner, October 3: undercut alerts "absolutely", from the ForeverForge
-- list). The side panel's fourth tab lists what you have up: quantity, your price each,
-- the cheapest now, and whether you've been undercut. Scans (and the flip watch) check
-- it as they save prices; Check prices looks up all of yours at once. An undercut gets
-- a sound and a chat line once per price. Cancel is one auction per click, two clicks
-- each (cancelling loses the deposit). Blizzard needs a click for every cancel and post.
--
-- ns.db.myAuctions[charKey] = { t = time read, list = { { a = auctionID, id, link, q,
--   each, left = seconds left when read, sold } } }: the last list seen per character,
-- for when the auction house is closed (and the mail panel later).
---------------------------------------------------------------------------
local AH = C_AuctionHouse
local frame, rows = nil, {}
local alerted = {}        -- [auctionID] = the cheapest price we alerted at
local armed = {}          -- [auctionID] = time Cancel was clicked once ("Sure?")

local function store()
  ns.db.myAuctions = ns.db.myAuctions or {}
  return ns.db.myAuctions
end
local function mine() return store()[ns.CharKey()] end

-- The game's own auctions list needs the auction house open; it answers with
-- OWNED_AUCTIONS_UPDATED.
local function query()
  if not (AH and AH.QueryOwnedAuctions and ns:IsAHOpen()) then return end
  local sorts = {}
  if Enum and Enum.AuctionHouseSortOrder then
    sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  end
  pcall(AH.QueryOwnedAuctions, sorts)
end

-- What the cheapest one of this item costs now, from your scans: for gear, the same
-- version when the scan knows it. nil if not priced.
local function cheapestNow(e)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[e.id]
  if not rec or rec.none then return nil, rec end
  if e.link and ns.VersionOfLink and ns.SuffixPrice then
    local suffix = ns:VersionOfLink(e.id, e.link)
    if suffix then
      local m = ns:SuffixPrice(e.id, suffix)
      if m and m > 0 then return m, rec end
    end
  end
  return rec.m, rec
end

-- Whether it Forever reports buyout per item or for the whole stack isn't confirmed:
-- take whichever is closer to what the item sells for (per item when there's nothing
-- to go by). Logged with /fl debug, to settle it in the beta.
local debugged = {}
local function eachPrice(info, id)
  local buy = info.buyoutAmount or info.bidAmount
  local q = math.max(info.quantity or 1, 1)
  if not buy or buy <= 0 then return nil end
  local per, split = buy, buy / q
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  local market = rec and not rec.none and (rec.a or rec.m)
  local each = per
  if q > 1 and market and market > 0 then
    local function off(v) return math.abs(math.log(v / market)) end
    if off(split) < off(per) then each = split end
  end
  if q > 1 and not debugged[id] then
    debugged[id] = true
    ns:Debug(("Your auctions: %s x%d, buyout %s, market %s: taken as %s each."):format(ns.ItemName(id), q,
      ns.MoneyPlain(buy), market and ns.MoneyPlain(market) or "?", ns.MoneyPlain(math.floor(each))))
  end
  return math.floor(each + 0.5)
end

local function readOwned()
  if not (AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo) then return end
  local n = AH.GetNumOwnedAuctions() or 0
  local list = {}
  local sold = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1
  for i = 1, n do
    local ok, info = pcall(AH.GetOwnedAuctionInfo, i)
    if ok and info and info.itemKey then
      local id = info.itemKey.itemID
      list[#list + 1] = { a = info.auctionID, id = id, link = info.itemLink, q = info.quantity or 1,
        each = eachPrice(info, id), left = info.timeLeftSeconds, sold = info.status == sold or nil }
    end
  end
  store()[ns.CharKey()] = { t = time(), list = list }
end

-- Undercut: someone (or a cheaper one of yours) is listed below your price.
local function undercutBy(e)
  if e.sold or not e.each then return end
  local now = cheapestNow(e)
  if now and now < e.each then return now end
end

-- A sound and a chat line, once per auction and price (again if it drops further).
local function checkAlerts()
  local m = mine()
  if not m or ns.db.settings.undercutAlerts == false then return end
  local news = {}
  for _, e in ipairs(m.list) do
    local now = undercutBy(e)
    if now and e.a and (not alerted[e.a] or now < alerted[e.a]) then
      alerted[e.a] = now
      news[#news + 1] = e
    end
  end
  if #news == 0 then return end
  for _, e in ipairs(news) do
    ns:Print(("Undercut: %s x%d, yours %s each, cheapest now %s. The Auctions tab beside the auction house lists them."):format(
      ns.ItemName(e.id), e.q, ns.Money(e.each), ns.Money(undercutBy(e))))
  end
  if ns.db.settings.undercutSound ~= false and PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_2) or 12867, "Master")
  end
end

local refresh   -- the tab's redraw

ns:On("OWNED_AUCTIONS_UPDATED", function()
  readOwned()
  checkAlerts()
  if refresh then refresh() end
end)
-- A sale or a cancel changes the list: ask again.
ns:On("AUCTION_CANCELED", function() C_Timer.After(0.5, query) end)
ns:On("AUCTION_HOUSE_AUCTION_CREATED", function() C_Timer.After(0.5, query) end)
ns:On("AUCTION_HOUSE_SHOW", function() C_Timer.After(1, query) end)

-- New prices from any scan: check your auctions against them.
ns:OnReady(function()
  local function after() checkAlerts(); if refresh then refresh() end end
  if ns.CheckDeals then hooksecurefunc(ns, "CheckDeals", after) end
  if ns.CheckFlip then
    hooksecurefunc(ns, "CheckFlip", function(_, id)
      local m = mine()
      if not m then return end
      for _, e in ipairs(m.list) do if e.id == id then after(); return end end
    end)
  end
end)

-- Look up every item you have listed (prices saved like any scan), then check.
function ns:CheckMyAuctions()
  local m = mine()
  if not (m and #m.list > 0) then ns:Print("You have no auctions up on this character (or the list isn't loaded yet)."); return end
  if not ns:IsAHOpen() then ns:Print("Open the auction house first."); return end
  local ids, seen = {}, {}
  for _, e in ipairs(m.list) do
    if not e.sold and not seen[e.id] then seen[e.id] = true; ids[#ids + 1] = e.id end
  end
  if #ids == 0 then ns:Print("Nothing to check: everything you listed has sold."); return end
  if ns.Scan.active then
    if ns.Scan.quiet then ns.Scan:Stop("Paused the flip watch's checks to check your auctions.")
    else ns:Print("A scan is running: check your auctions when it's done."); return end
  end
  ns.Scan:StartList(ids, "your auctions")
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local ROW = 22
local X = { name = 24, q = 200, each = 262, now = 324 }

local function shortLeft(secs)
  if not secs then return "" end
  if secs >= 3600 then return math.floor(secs / 3600) .. "h" end
  return math.max(1, math.floor(secs / 60)) .. "m"
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, frame.content)
  r:SetHeight(ROW)
  r:EnableMouse(true)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 4, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = T:Text(r, 11)
  r.name:SetPoint("LEFT", X.name, 0)
  r.name:SetWidth(X.q - X.name - 34)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.q, r.each, r.now = T:Text(r, 11), T:Text(r, 11), T:Text(r, 11)
  r.q:SetPoint("RIGHT", r, "LEFT", X.q, 0)
  r.each:SetPoint("RIGHT", r, "LEFT", X.each, 0)
  r.now:SetPoint("RIGHT", r, "LEFT", X.now, 0)
  r.status = T:Text(r, 11)
  r.status:SetPoint("LEFT", X.now + 8, 0)
  -- Cancel: two clicks (the deposit is lost), only on undercut ones.
  r.cancel = T:Button(r, "Cancel", 52, function(self)
    local e = self:GetParent().entry
    if not (e and e.a) then return end
    if armed[e.a] and GetTime() - armed[e.a] < 4 then
      armed[e.a] = nil
      local ok, err = pcall(AH.CancelAuction, e.a)
      if not ok then ns:Print("Couldn't cancel that auction: " .. tostring(err)) end
    else
      armed[e.a] = GetTime()
      self:SetText("Sure?")
      C_Timer.After(4, function() if refresh then refresh() end end)
    end
  end, 18)
  r.cancel:SetPoint("RIGHT", -4, 0)
  r.cancel:GetFontString():SetFont(T.font, 11, "")
  r.cancel:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Cancel this auction", 1, 1, 1)
    GameTooltip:AddLine("Click twice: the items come back by mail and the deposit is lost. Then repost them just under the cheapest.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  r.cancel:HookScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnEnter", function(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:SetItemByID(e.id) end
    GameTooltip:AddLine(" ")
    local _, rec = cheapestNow(e)
    GameTooltip:AddDoubleLine("Yours", e.each and (ns.Money(e.each) .. " each") or "?", 0.7, 0.7, 0.7, 1, 1, 1)
    if rec and rec.t then GameTooltip:AddDoubleLine("Prices checked", ns.Age(rec.t), 0.7, 0.7, 0.7, 1, 1, 1) end
    if e.left and not e.sold then GameTooltip:AddDoubleLine("Time left (when read)", shortLeft(e.left), 0.7, 0.7, 0.7, 1, 1, 1) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

refresh = function()
  if not (frame and frame:IsVisible()) then return end
  local m = mine()
  local list = m and m.list or {}
  -- Undercut first, then the rest; sold at the end.
  local order = {}
  for _, e in ipairs(list) do order[#order + 1] = e end
  local function rank(e) return e.sold and 3 or (undercutBy(e) and 1 or 2) end
  table.sort(order, function(a, b)
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return ns.ItemName(a.id) < ns.ItemName(b.id)
  end)
  local width = frame.sf:GetWidth() - 12
  frame.content:SetWidth(width)
  local under, cheapest = 0, 0
  for i, e in ipairs(order) do
    local r = getRow(i)
    r.entry = e
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(i - 1) * ROW)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    r.icon:SetTexture(ns:ItemIcon(e.id))
    r.icon:SetDesaturated(e.sold or false)
    local name = e.link and e.link:match("%[(.-)%]") or ns.ItemName(e.id)
    r.name:SetText(e.sold and ("|cff888888" .. name .. "|r") or name)
    r.q:SetText(tostring(e.q or 1))
    r.each:SetText(e.each and ns.MoneyPlain(e.each) or "|cff888888?|r")
    local now = cheapestNow(e)
    local by = undercutBy(e)
    r.now:SetText(now and ((by and "|cffee8597" or "|cff7fd39c") .. ns.MoneyPlain(now) .. "|r") or "|cff888888?|r")
    if e.sold then
      r.status:SetText("|cff888888sold|r")
    elseif by then
      under = under + 1
      r.status:SetText("|cffee8597undercut|r")
    elseif now then
      cheapest = cheapest + 1
      r.status:SetText("|cff7fd39ccheapest|r")
    else
      r.status:SetText("|cff888888not priced|r")
    end
    r.cancel:SetShown(by ~= nil and e.a ~= nil)
    r.cancel:SetText((e.a and armed[e.a] and GetTime() - armed[e.a] < 4) and "Sure?" or "Cancel")
    r:Show()
  end
  for i = #order + 1, #rows do rows[i]:Hide() end
  frame.content:SetHeight(math.max(#order * ROW, 20))
  frame.sf.UpdateScrollBar()
  frame.empty:SetShown(#order == 0)
  frame.empty:SetText(ns:IsAHOpen() and "Nothing listed on this character. What you put up on the auction house shows here."
    or "Open the auction house to see your auctions.")
  frame.check:SetEnabled(ns:IsAHOpen() and #order > 0 and not (ns.Scan.active and not ns.Scan.quiet))
  if #order == 0 then
    frame.info:SetText("")
  elseif under > 0 then
    frame.info:SetText(("|cffee8597%d undercut.|r Cancel (twice) and repost just under the cheapest. %d still cheapest."):format(under, cheapest))
  else
    frame.info:SetText(("%d up, none undercut at the last check%s."):format(#order,
      m and m.t and (" (" .. ns.Age(m.t) .. ")") or ""))
  end
end

function ns:YourAuctionsFrame(side)
  if frame or not side then return frame end
  frame = CreateFrame("Frame", "ForeverLedgerYourAuctions", side)
  frame:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -30)
  frame:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", 6, -8)
  header:SetPoint("TOPRIGHT", -6, -8)
  header:SetHeight(20)
  T:Fill(header, { 1, 1, 1, 0.05 })
  for _, c in ipairs({ { "Item", 8, "LEFT" }, { "Qty", X.q, "RIGHT" }, { "Yours", X.each, "RIGHT" },
                       { "Cheapest", X.now, "RIGHT" }, { "Status", X.now + 8, "LEFT" } }) do
    local fs = T:Text(header, 11, T.dim)
    if c[3] == "LEFT" then fs:SetPoint("LEFT", c[2], 0) else fs:SetPoint("RIGHT", header, "LEFT", c[2], 0) end
    fs:SetText(c[1])
  end
  frame.sf, frame.content = T:Scroll(frame)
  frame.sf:SetPoint("TOPLEFT", 6, -30)
  frame.sf:SetPoint("BOTTOMRIGHT", -6, 58)
  frame.empty = T:Text(frame.content, 12, T.dim)
  frame.empty:SetPoint("TOPLEFT", 8, -8)
  frame.empty:SetPoint("RIGHT", frame.content, "RIGHT", -8, 0)
  frame.empty:SetJustifyH("LEFT")
  frame.check = T:Button(frame, "Check prices", 110, function() ns:CheckMyAuctions() end, 22)
  frame.check:SetPoint("BOTTOMLEFT", 10, 8)
  frame.check:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Check prices", 1, 1, 1)
    GameTooltip:AddLine("Looks up everything you have listed on the auction house now, one item at a time, and marks the ones that have been undercut. Full scans and the flip watch check them too.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  frame.check:HookScript("OnLeave", function() GameTooltip:Hide() end)
  frame.info = T:Text(frame, 11, T.dim)
  frame.info:SetPoint("BOTTOMLEFT", 12, 36)
  frame.info:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
  frame.info:SetJustifyH("LEFT")
  frame.info:SetWordWrap(false)
  frame:SetScript("OnShow", function() query(); refresh() end)
  C_Timer.NewTicker(2, function() if frame:IsVisible() then refresh() end end)   -- "Sure?" times out, prices arrive
  frame:Hide()
  return frame
end
