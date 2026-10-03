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

ns:On("AUCTION_HOUSE_SHOW", function()
  C_Timer.After(0.3, function()
    local ah = AuctionHouseFrame
    if not ah then return end
    guard(ah.ItemSellFrame, "gear")
    guard(ah.CommoditiesSellFrame, "stacks")
  end)
end)
