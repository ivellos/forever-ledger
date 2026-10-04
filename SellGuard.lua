local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Sell protection (owner's idea, October 3): on the auction house Sell tab, when a
-- vendor pays more than the listing would bring after the auction house cut, say so
-- above the Post button and grey Post out until "Post anyway" (Settings: sellGuard
-- off keeps just the warning). It only ever stops a click; it never posts or sells.
-- Works on Blizzard's sell pages (ItemSellFrame for gear, CommoditiesSellFrame for
-- stacks). Their pieces are looked up by name and anything missing is skipped, and
-- /fl debug says what was found (first test in the beta).
---------------------------------------------------------------------------
local unlocked = {}   -- ["itemID:price"] = true after Post anyway, for this listing only
local guards = {}

local function call(obj, method, ...)
  if not (obj and obj[method]) then return end
  local ok, a = pcall(obj[method], obj, ...)
  if ok then return a end
end

-- The item and price per item on a sell page, or nil.
local function listing(frame)
  local loc = call(frame, "GetItem")
  local id = loc and C_Item and C_Item.GetItemID and select(2, pcall(C_Item.GetItemID, loc))
  if type(id) ~= "number" then return end
  local price = call(frame, "GetUnitPrice") or call(frame.PriceInput, "GetAmount")
  if not price or price <= 0 then return end
  return id, price
end

local function evaluate(g)
  local frame, post = g.frame, g.frame.PostButton
  local id, price = listing(frame)
  local sell = id and ns:GetSellPrice(id)
  local cut = (ns.db.settings.ahCut or 5) / 100
  local net = price and math.floor(price * (1 - cut))
  local bad = sell and net and net < sell
  g.key = bad and (id .. ":" .. price) or nil
  if not bad then
    g.text:SetText("")
    g.text2:SetText("")
    g.anyway:Hide()
    return
  end
  -- Two short lines, centred under Post (owner, October 3: "centred and clean").
  g.text:SetText(("|cffff7070Vendor pays: %s|r"):format(ns.Money(sell)))
  g.text2:SetText(("Auction house: %s after the %d%% cut"):format(ns.Money(net), math.floor(cut * 100 + 0.5)))
  local lock = ns.db.settings.sellGuard ~= false and not unlocked[g.key]
  g.anyway:SetShown(lock)
  if lock and post and post:IsEnabled() then post:Disable() end
end

local function guard(frame, name)
  if not frame or guards[frame] then return end
  local post = frame.PostButton
  local g = { frame = frame }
  guards[frame] = g
  -- Two single lines (one text with a line break was cut to "Vendor pays: 26s 92c...").
  g.text = T:Text(frame, 11)
  g.text:SetJustifyH("CENTER")
  g.text:SetWordWrap(false)
  g.text2 = T:Text(frame, 11)
  g.text2:SetJustifyH("CENTER")
  g.text2:SetWordWrap(false)
  g.text2:SetPoint("TOP", g.text, "BOTTOM", 0, -3)
  -- Under the Post button, where both sell pages have room (above it, it ran into Total
  -- Price, and Post anyway went off the left edge: owner's screenshots, October 3).
  if post then
    -- Centred on Post with no set width, so long amounts grow evenly to both sides.
    g.text:SetPoint("TOP", post, "BOTTOM", 0, -8)
  else
    g.text:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 40)
  end
  g.anyway = T:Button(frame, "Post anyway", 76, function()
    if g.key then unlocked[g.key] = true end
    g.anyway:Hide()
    -- Let the game decide if Post can be used (an item and a price are set), then make
    -- sure our hold is off (October 3: clicking did nothing).
    call(frame, "UpdatePostButtonState")
    if post and not post:IsEnabled() then post:Enable() end
    ns:Debug("Sell protection: Post anyway for", g.key or "?", "- Post is", post and (post:IsEnabled() and "on" or "still off") or "missing")
  end, 20)
  -- Above everything on the sell page, so nothing invisible covers it.
  g.anyway:SetFrameStrata("DIALOG")
  g.anyway:SetFrameLevel((post and post:GetFrameLevel() or frame:GetFrameLevel()) + 10)
  -- Beside Post (under the text it sat on Buyout Mode on gear pages, October 3).
  if post then g.anyway:SetPoint("LEFT", post, "RIGHT", 3, 0)
  else g.anyway:SetPoint("TOPLEFT", g.text, "BOTTOMLEFT", 0, -6) end
  g.anyway:GetFontString():SetFont(T.font, 10, "")
  g.anyway:Hide()
  -- Blizzard turns Post back on as you type: check again after it does, and a few times
  -- a second while the page is open.
  if frame.UpdatePostButtonState then hooksecurefunc(frame, "UpdatePostButtonState", function() evaluate(g) end) end
  local since = 0
  frame:HookScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.25 then return end
    since = 0
    evaluate(g)
  end)
  ns:Debug(("Sell protection on %s: PostButton %s, GetItem %s, price from %s."):format(name, post and "yes" or "no",
    frame.GetItem and "yes" or "no", frame.GetUnitPrice and "GetUnitPrice" or (frame.PriceInput and "PriceInput" or "nothing")))
end

---------------------------------------------------------------------------
-- Price helper (October 4, after Your auctions: cancel, then repost): a line above the
-- price box with the usual price and the cheapest now, and two buttons that fill the
-- price in: just under the cheapest, or the usual price. When the cheapest is far below
-- usual (someone dumping), it says so, so you can wait rather than follow it down. It
-- only fills the box; you still click Post. Settings, Auction house: priceHelper.
---------------------------------------------------------------------------
local helpers = {}
local DUMP = 0.7   -- cheapest under 70% of usual: "well below usual"

local function setPrice(frame, copper)
  local input = frame.PriceInput
  if not (input and copper and copper > 0) then return end
  if call(input, "SetAmount", copper) == nil and not input.SetAmount then
    ns:Debug("Price helper: no SetAmount on the price box")
    return
  end
  -- Let the page work out the total and Post again.
  call(frame, "OnPriceChanged")
  call(frame, "UpdateTotalPrice")
  call(frame, "UpdatePostButtonState")
end

local function helperUpdate(h)
  local frame = h.frame
  local loc = call(frame, "GetItem")
  local id = loc and C_Item and C_Item.GetItemID and select(2, pcall(C_Item.GetItemID, loc))
  if ns.db.settings.priceHelper == false or type(id) ~= "number" then h.box:Hide(); return end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  local cheapest = rec and not rec.none and rec.m
  local stats = ns.PriceStats and ns:PriceStats(id, "month")
  local usual = stats and stats.points >= 3 and math.floor(stats.usual)
  if not (cheapest or usual) then h.box:Hide(); return end
  h.under = cheapest and math.max(cheapest - 1, 1)
  h.usual = usual
  local parts = {}
  if usual then parts[#parts + 1] = "Usual " .. ns.Money(usual) end
  if cheapest then parts[#parts + 1] = "cheapest now " .. ns.Money(cheapest) end
  local dumped = usual and cheapest and cheapest < usual * DUMP
  h.text:SetText(table.concat(parts, "   ") .. (dumped and "   |cffffd100well below usual: you may do better waiting|r" or ""))
  h.under_b:SetText(h.under and ("Undercut " .. ns.MoneyPlain(h.under)) or "Undercut")
  h.under_b:SetEnabled(h.under ~= nil)
  h.under_b:SetWidth(h.under_b:GetFontString():GetStringWidth() + 16)
  h.usual_b:SetText(usual and ("Usual " .. ns.MoneyPlain(usual)) or "Usual")
  h.usual_b:SetEnabled(usual ~= nil)
  h.usual_b:SetWidth(h.usual_b:GetFontString():GetStringWidth() + 16)
  h.box:Show()
end

local function helper(frame, name)
  if not frame or helpers[frame] then return end
  local input = frame.PriceInput
  local h = { frame = frame }
  helpers[frame] = h
  h.box = CreateFrame("Frame", nil, frame)
  h.box:SetSize(320, 40)
  -- Above the price box (its label sits to the left); the page has room there.
  if input then h.box:SetPoint("BOTTOMLEFT", input, "TOPLEFT", -60, 4)
  else h.box:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -60) end
  h.box:SetFrameLevel(frame:GetFrameLevel() + 10)
  h.text = T:Text(h.box, 10, T.dim)
  h.text:SetPoint("TOPLEFT", 0, 0)
  h.text:SetWidth(320)
  h.text:SetJustifyH("LEFT")
  h.text:SetWordWrap(false)
  h.under_b = T:Button(h.box, "Undercut", 90, function() setPrice(frame, h.under) end, 18)
  h.under_b:SetPoint("TOPLEFT", h.text, "BOTTOMLEFT", 0, -3)
  h.under_b:GetFontString():SetFont(T.font, 10, "")
  h.usual_b = T:Button(h.box, "Usual", 90, function() setPrice(frame, h.usual) end, 18)
  h.usual_b:SetPoint("LEFT", h.under_b, "RIGHT", 4, 0)
  h.usual_b:GetFontString():SetFont(T.font, 10, "")
  for _, b in ipairs({ h.under_b, h.usual_b }) do
    b:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self == h.under_b and "Just under the cheapest" or "Your usual price", 1, 1, 1)
      GameTooltip:AddLine(self == h.under_b and "Fills the price box with 1 copper under the cheapest listing from your last scan. You still click Post."
        or "Fills the price box with the usual price from your scans this month. You still click Post.", nil, nil, nil, true)
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end
  h.box:Hide()
  local since = 0
  frame:HookScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.5 then return end
    since = 0
    helperUpdate(h)
  end)
  ns:Debug(("Price helper on %s: PriceInput %s, SetAmount %s."):format(name, input and "yes" or "no",
    input and input.SetAmount and "yes" or "no"))
end

ns:On("AUCTION_HOUSE_SHOW", function()
  C_Timer.After(0.3, function()
    local ah = AuctionHouseFrame
    if not ah then return end
    guard(ah.ItemSellFrame, "gear")
    guard(ah.CommoditiesSellFrame, "stacks")
    helper(ah.ItemSellFrame, "gear")
    helper(ah.CommoditiesSellFrame, "stacks")
  end)
end)
