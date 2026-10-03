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
    g.anyway:Hide()
    return
  end
  g.text:SetText(("|cffff7070A vendor pays %s each;|r this would get you %s after the %d%% cut. Sell it to a vendor instead.")
    :format(ns.Money(sell), ns.Money(net), math.floor(cut * 100 + 0.5)))
  local lock = ns.db.settings.sellGuard ~= false and not unlocked[g.key]
  g.anyway:SetShown(lock)
  if lock and post and post:IsEnabled() then post:Disable() end
end

local function guard(frame, name)
  if not frame or guards[frame] then return end
  local post = frame.PostButton
  local g = { frame = frame }
  guards[frame] = g
  g.text = T:Text(frame, 11)
  g.text:SetJustifyH("LEFT")
  g.text:SetWordWrap(true)
  -- Under the Post button, where both sell pages have room (above it, it ran into Total
  -- Price, and Post anyway went off the left edge: owner's screenshots, October 3).
  if post then
    g.text:SetPoint("TOPLEFT", post, "BOTTOMLEFT", 0, -8)
    g.text:SetPoint("RIGHT", post, "RIGHT", 0, 0)
  else
    g.text:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 40)
  end
  g.anyway = T:Button(frame, "Post anyway", 100, function()
    if g.key then unlocked[g.key] = true end
    g.anyway:Hide()
    if not call(frame, "UpdatePostButtonState") and post then post:Enable() end
  end, 20)
  g.anyway:SetPoint("TOPLEFT", g.text, "BOTTOMLEFT", 0, -6)
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
