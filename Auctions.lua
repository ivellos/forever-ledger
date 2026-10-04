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
-- Views like the Ledger's (owner, October 4): All, Up, Undercut, Sold. Sold ones say
-- what you get after the cut and when the gold reaches the mailbox; the bottom line
-- says what's on the way and what's waiting in the mailbox. Cancel next undercut: one
-- button that cancels the next undercut auction per click, after asking once.
--
-- ns.db.myAuctions[charKey] = { t = time read, list = { { a = auctionID, id, link, q,
--   each, left = seconds left when read, sold, soldAt = first seen sold, mailed = gone
--   from the list after selling } } }: the last list seen per character.
-- ns.db.mailbox[charKey] = { t, money }: gold waiting in the mailbox at the last visit.
---------------------------------------------------------------------------
local SALE_MAIL_SECONDS = 3600   -- Classic: a sale's gold arrives an hour later (to check in Forever)
local KEEP_SOLD_SECONDS = 86400  -- sold ones stay listed a day after their gold is sent
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
-- The auction house answers one request at a time and can drop one sent while it's busy
-- (opening it starts scans too): with no answer in 3 seconds, ask once more.
local answered = 0
local function query(retry)
  if not (AH and AH.QueryOwnedAuctions and ns:IsAHOpen()) then return end
  local sorts = {}
  if Enum and Enum.AuctionHouseSortOrder then
    sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  end
  local asked = GetTime()
  pcall(AH.QueryOwnedAuctions, sorts)
  if not retry then
    C_Timer.After(3, function() if answered < asked then query(true) end end)
  end
end
ns:On("OWNED_AUCTIONS_UPDATED", function() answered = GetTime() end)

-- Gear checked by Check prices: looked up by name like Search all, each version on its
-- own (a plain item search finds nothing for gear: owner's test, October 4, the
-- leggings went "not priced"). [itemID .. version] = { t, min } for your version.
local gearChecked = {}
local GEAR_FRESH = 1800
local function gearKey(e)
  local _, suffix = ns.ResolveItemVersion and ns:ResolveItemVersion(e.link or "")
  return e.id .. "|" .. (suffix or ""), suffix
end

-- What the cheapest one of this item costs now: for gear, your version from Check
-- prices if recent, else the version from the last full scan. nil if not priced.
local function cheapestNow(e)
  local g = e.link and gearChecked[(gearKey(e))]
  if g and time() - g.t < GEAR_FRESH and g.min then return g.min, { t = g.t } end
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
  local list, now = {}, time()
  local sold = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1
  -- What we knew before: when each sold, and sold ones whose gold has gone to the mail.
  local before, seen = {}, {}
  for _, e in ipairs((mine() or {}).list or {}) do if e.a then before[e.a] = e end end
  for i = 1, n do
    local ok, info = pcall(AH.GetOwnedAuctionInfo, i)
    if ok and info and info.itemKey then
      local id = info.itemKey.itemID
      local e = { a = info.auctionID, id = id, link = info.itemLink, q = info.quantity or 1,
        each = eachPrice(info, id), left = info.timeLeftSeconds, sold = info.status == sold or nil }
      if e.sold then e.soldAt = (before[e.a] and before[e.a].soldAt) or now end
      list[#list + 1] = e
      if e.a then seen[e.a] = true end
    end
  end
  -- Sold before and gone from the list now: its gold was sent to the mailbox.
  for a, e in pairs(before) do
    if not seen[a] and e.sold and now - (e.soldAt or now) < KEEP_SOLD_SECONDS then
      e.mailed = true
      list[#list + 1] = e
    end
  end
  store()[ns.CharKey()] = { t = now, list = list }
end

-- What a sold auction brings after the auction house cut.
local function proceeds(e)
  return e.each and math.floor(e.each * (e.q or 1) * (1 - (ns.db.settings.ahCut or 5) / 100)) or 0
end

-- Gold waiting in the mailbox, read when you open it.
ns:On("MAIL_INBOX_UPDATE", function()
  if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
  local money = 0
  for i = 1, GetInboxNumItems() or 0 do
    local ok, _, _, _, _, m = pcall(GetInboxHeaderInfo, i)
    if ok and m and m > 0 then money = money + m end
  end
  ns.db.mailbox = ns.db.mailbox or {}
  ns.db.mailbox[ns.CharKey()] = { t = time(), money = money }
end)

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
  -- A list like a shopping list's: Search all looks up gear by name, each version
  -- apart (yours: its "of the ..."), and the rest with an ordinary search.
  local items, seen = {}, {}
  for _, e in ipairs(m.list) do
    if not e.sold then
      local key, suffix = gearKey(e)
      if not seen[key] then
        seen[key] = true
        items[#items + 1] = { id = e.id, suffix = suffix, key = key, max = 0 }
      end
    end
  end
  if #items == 0 then ns:Print("Nothing to check: everything you listed has sold."); return end
  ns.myAuctionCheck = { name = "your auctions", items = items, on = false }
  ns:SearchAllList(ns.myAuctionCheck)
end

-- Gear results from that look-up (ShoppingLists.lua keeps them on the entries).
ns:OnReady(function()
  C_Timer.NewTicker(1, function()
    local c = ns.myAuctionCheck
    if not c then return end
    for _, it in ipairs(c.items) do
      if it.found and (not gearChecked[it.key] or gearChecked[it.key].t < it.found.t) then
        gearChecked[it.key] = { t = it.found.t, min = it.found.min }
        if refresh then refresh() end
        checkAlerts()
      end
    end
  end)
end)

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local ROW = 22
local X = { name = 24, q = 182, each = 238, now = 292 }   -- the status gets the rest (it was cut off)
local VIEWS = { { "all", "All" }, { "up", "Up" }, { "undercut", "Undercut" }, { "sold", "Sold" } }
local view = "all"
local cancelState     -- nil, "asking" (first click, until asked = time), or "on" (each click cancels one)
local askedAt = 0
local pending = {}    -- [auctionID] = true: cancel sent, waiting for the list to update

local function shortLeft(secs)
  if not secs then return "" end
  if secs >= 3600 then return math.floor(secs / 3600) .. "h" end
  return math.max(1, math.floor(secs / 60)) .. "m"
end

-- When a sale's gold reaches the mailbox: "in 34m", or "in your mailbox".
-- By the clock, not by the sale leaving the list: Forever drops a sale from your list
-- before its gold arrives (owner's test, October 4: "gold mailed", mailbox empty).
local function mailText(e)
  local left = (e.soldAt or time()) + SALE_MAIL_SECONDS - time()
  if left <= 0 then return "gold mailed" end
  return "mail in " .. shortLeft(left)
end

-- The undercut ones, in the order shown, not already being cancelled.
local function undercutList(list)
  local out = {}
  for _, e in ipairs(list) do
    if e.a and not pending[e.a] and undercutBy(e) then out[#out + 1] = e end
  end
  return out
end

local function cancelOne(e)
  if not (e and e.a and AH and AH.CancelAuction) then return end
  pending[e.a] = true
  local ok, err = pcall(AH.CancelAuction, e.a)
  if not ok then pending[e.a] = nil; ns:Print("Couldn't cancel that auction: " .. tostring(err)) end
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, frame.content)
  r:SetHeight(ROW)
  r:EnableMouse(true)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  -- Undercut: the whole row tinted red (owner's test, October 4), not just the word.
  r.tint = T:Fill(r, { 0.93, 0.32, 0.38, 0.18 })
  r.tint:Hide()
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
  r.status:SetJustifyH("LEFT")
  r.status:SetWordWrap(false)
  -- One auction: two clicks (the deposit is lost).
  r.cancel = T:Button(r, "Cancel", 52, function(self)
    local e = self:GetParent().entry
    if not (e and e.a) then return end
    if armed[e.a] and GetTime() - armed[e.a] < 4 then
      armed[e.a] = nil
      cancelOne(e)
    else
      armed[e.a] = GetTime()
      self:SetText("Sure?")
    end
  end, 18)
  r.cancel:SetPoint("RIGHT", -4, 0)
  r.cancel:GetFontString():SetFont(T.font, 11, "")
  r.cancel:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Cancel this auction", 1, 1, 1)
    GameTooltip:AddLine("Click twice: the items come back by mail and the deposit is lost. Cancel next undercut at the bottom does them one after another.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  r.cancel:HookScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnEnter", function(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:SetItemByID(e.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Yours", e.each and (ns.Money(e.each) .. " each") or "?", 0.7, 0.7, 0.7, 1, 1, 1)
    if e.sold then
      GameTooltip:AddDoubleLine("You get, after the cut", ns.Money(proceeds(e)), 0.7, 0.7, 0.7, 0.5, 0.83, 0.61)
      GameTooltip:AddDoubleLine("Gold", mailText(e), 0.7, 0.7, 0.7, 1, 1, 1)
    else
      local _, rec = cheapestNow(e)
      if rec and rec.t then GameTooltip:AddDoubleLine("Prices checked", ns.Age(rec.t), 0.7, 0.7, 0.7, 1, 1, 1) end
      if e.left then GameTooltip:AddDoubleLine("Time left (when read)", shortLeft(e.left), 0.7, 0.7, 0.7, 1, 1, 1) end
    end
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
  local function rank(e) return e.sold and 3 or (undercutBy(e) and 1 or 2) end
  local order = {}
  for _, e in ipairs(list) do order[#order + 1] = e end
  table.sort(order, function(a, b)
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return ns.ItemName(a.id) < ns.ItemName(b.id)
  end)
  -- Counts for the view tabs, and the gold on its way.
  local counts = { all = #order, up = 0, undercut = 0, sold = 0 }
  local onWay, nextIn = 0, nil
  for _, e in ipairs(order) do
    if e.sold then
      counts.sold = counts.sold + 1
      local left = (e.soldAt or time()) + SALE_MAIL_SECONDS - time()
      if left > 0 then
        onWay = onWay + proceeds(e)
        nextIn = math.min(nextIn or left, left)
      end
    else
      counts.up = counts.up + 1
      if undercutBy(e) then counts.undercut = counts.undercut + 1 end
    end
  end
  for _, v in ipairs(VIEWS) do
    local b = frame.views[v[1]]
    b:SetText(v[2] .. (counts[v[1]] > 0 and (" |cff888888" .. counts[v[1]] .. "|r") or ""))
    b:SetWidth(b:GetFontString():GetStringWidth() + 20)
    b:SetSelected(view == v[1])
  end
  local shown = {}
  for _, e in ipairs(order) do
    if view == "all" or (view == "sold" and e.sold) or (view == "up" and not e.sold)
      or (view == "undercut" and undercutBy(e)) then shown[#shown + 1] = e end
  end

  local width = frame.sf:GetWidth() - 12
  frame.content:SetWidth(width)
  for i, e in ipairs(shown) do
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
    local now, by = cheapestNow(e), undercutBy(e)
    if e.sold then
      r.now:SetText("|cff7fd39c+" .. ns.MoneyPlain(proceeds(e)) .. "|r")
      r.status:SetText("|cff888888sold, " .. mailText(e) .. "|r")
    else
      r.now:SetText(now and ((by and "|cffee8597" or "|cff7fd39c") .. ns.MoneyPlain(now) .. "|r") or "|cff888888?|r")
      if e.a and pending[e.a] then r.status:SetText("|cff888888cancelling...|r")
      elseif by then r.status:SetText("|cffee8597undercut|r")
      elseif now then r.status:SetText("|cff7fd39ccheapest|r")
      else r.status:SetText("|cff888888not priced: Check prices|r") end
    end
    local canCancel = by ~= nil and e.a ~= nil and not pending[e.a]
    r.cancel:SetShown(canCancel)
    r.tint:SetShown(by ~= nil)
    -- The status runs to the edge, or up to the Cancel button.
    r.status:SetPoint("RIGHT", r, "RIGHT", canCancel and -60 or -4, 0)
    r.cancel:SetText((e.a and armed[e.a] and GetTime() - armed[e.a] < 4) and "Sure?" or "Cancel")
    r:Show()
  end
  for i = #shown + 1, #rows do rows[i]:Hide() end
  frame.content:SetHeight(math.max(#shown * ROW, 20))
  frame.sf.UpdateScrollBar()
  frame.empty:SetShown(#shown == 0)
  frame.empty:SetText((#order == 0 and (ns:IsAHOpen() and "Nothing listed on this character. What you put up on the auction house shows here."
    or "Open the auction house to see your auctions."))
    or (view == "undercut" and "None undercut at the last check.") or (view == "sold" and "Nothing sold lately.")
    or "Nothing here.")
  frame.check:SetEnabled(ns:IsAHOpen() and counts.up > 0 and not (ns.Scan.active and not ns.Scan.quiet))

  -- Cancel next undercut: asks once, then each click cancels the next one.
  local todo = undercutList(order)
  if cancelState == "asking" and GetTime() - askedAt > 8 then cancelState = nil end
  if #todo == 0 then cancelState = nil end
  frame.cancelNext:SetEnabled(#todo > 0 and ns:IsAHOpen())
  frame.cancelNext:SetText(cancelState == "asking" and ("Yes, cancel %d"):format(#todo)
    or (#todo > 0 and ("Cancel next undercut (%d)"):format(#todo)) or "Cancel next undercut")
  frame.cancelNext:SetSelected(cancelState == "asking")

  -- The bottom lines: what's next to cancel, or the gold on its way and in the mailbox.
  local box = (ns.db.mailbox or {})[ns.CharKey()]
  local gold = {}
  if onWay > 0 then gold[#gold + 1] = ("On the way: |cff7fd39c%s|r%s"):format(ns.MoneyPlain(onWay), nextIn and (" (next in " .. shortLeft(nextIn) .. ")") or "") end
  if box and box.money and box.money > 0 then gold[#gold + 1] = ("In your mailbox: |cff7fd39c%s|r (%s)"):format(ns.MoneyPlain(box.money), ns.Age(box.t)) end
  frame.gold:SetText(table.concat(gold, "   "))
  if cancelState == "asking" then
    frame.info:SetText(("|cffffd100Cancel your %d undercut %s? Each loses its deposit.|r Click again to start; then each click cancels the next."):format(
      #todo, #todo == 1 and "auction" or "auctions"))
  elseif #todo > 0 then
    local e = todo[1]
    frame.info:SetText(("Next: %s x%d, yours %s, cheapest %s.%s"):format(ns.ItemName(e.id), e.q or 1, ns.MoneyPlain(e.each), ns.MoneyPlain(undercutBy(e)),
      cancelState == "on" and "" or " |cff888888(First click asks, then one click each.)|r"))
  elseif counts.up > 0 then
    frame.info:SetText(("%d up, none undercut at the last check%s."):format(counts.up, m and m.t and (" (" .. ns.Age(m.t) .. ")") or ""))
  else
    frame.info:SetText("")
  end
end

-- Pending cancels clear when the list comes back.
ns:On("OWNED_AUCTIONS_UPDATED", function()
  local still = {}
  for _, e in ipairs((mine() or {}).list or {}) do if e.a then still[e.a] = true end end
  for a in pairs(pending) do if not still[a] then pending[a] = nil end end
end)
ns:On("AUCTION_HOUSE_CLOSED", function() cancelState = nil; wipe(pending) end)

function ns:YourAuctionsFrame(side)
  if frame or not side then return frame end
  frame = CreateFrame("Frame", "ForeverLedgerYourAuctions", side)
  frame:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -30)
  frame:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
  -- All | Up | Undercut | Sold, like the Ledger's views.
  frame.views = {}
  local prev
  for _, v in ipairs(VIEWS) do
    local b = T:Tab(frame, v[2], function() view = v[1]; refresh() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("TOPLEFT", 4, -2) end
    frame.views[v[1]] = b
    prev = b
  end
  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", 6, -34)
  header:SetPoint("TOPRIGHT", -6, -34)
  header:SetHeight(20)
  T:Fill(header, { 1, 1, 1, 0.05 })
  for _, c in ipairs({ { "Item", 8, "LEFT" }, { "Qty", X.q, "RIGHT" }, { "Yours", X.each, "RIGHT" },
                       { "Cheapest", X.now, "RIGHT" }, { "Status", X.now + 8, "LEFT" } }) do
    local fs = T:Text(header, 11, T.dim)
    if c[3] == "LEFT" then fs:SetPoint("LEFT", c[2], 0) else fs:SetPoint("RIGHT", header, "LEFT", c[2], 0) end
    fs:SetText(c[1])
  end
  frame.sf, frame.content = T:Scroll(frame)
  frame.sf:SetPoint("TOPLEFT", 6, -56)
  frame.sf:SetPoint("BOTTOMRIGHT", -6, 74)
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
  -- One button, always in the same place: asks once, then each click cancels the next
  -- undercut auction (owner, October 4: fewer clicks; Blizzard needs one per cancel).
  frame.cancelNext = T:Button(frame, "Cancel next undercut", 190, function()
    local m = mine()
    local todo = undercutList(m and m.list or {})
    if #todo == 0 then return end
    if cancelState == "on" then
      cancelOne(todo[1])
    elseif cancelState == "asking" and GetTime() - askedAt <= 8 then
      cancelState = "on"
      cancelOne(todo[1])
    else
      cancelState, askedAt = "asking", GetTime()
    end
    refresh()
  end, 22)
  frame.cancelNext:SetPoint("BOTTOMRIGHT", -10, 8)
  frame.cancelNext:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    -- Short lines under headings (owner's test, October 4: one block was hard to read).
    local A = T.accent
    GameTooltip:AddLine("Cancel next undercut", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("How it works", A[1], A[2], A[3])
    GameTooltip:AddLine("First click asks to confirm. After that, each click cancels one.", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("The line above says which one is next.", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("What happens", A[1], A[2], A[3])
    GameTooltip:AddLine("The items come back by mail. Each loses its deposit.", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Repost them just under the cheapest.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  frame.cancelNext:HookScript("OnLeave", function() GameTooltip:Hide() end)
  frame.info = T:Text(frame, 11, T.dim)
  frame.info:SetPoint("BOTTOMLEFT", 12, 36)
  frame.info:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
  frame.info:SetJustifyH("LEFT")
  frame.info:SetWordWrap(false)
  frame.gold = T:Text(frame, 11, T.dim)
  frame.gold:SetPoint("BOTTOMLEFT", 12, 54)
  frame.gold:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
  frame.gold:SetJustifyH("LEFT")
  frame.gold:SetWordWrap(false)
  frame:SetScript("OnShow", function() query(); refresh() end)
  frame:SetScript("OnHide", function() cancelState = nil end)
  C_Timer.NewTicker(2, function() if frame:IsVisible() then refresh() end end)   -- countdowns, "Sure?" times out
  frame:Hide()
  return frame
end
