local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Watched items (owner, November 10: Silk Cloth turns into bandages, so buy it up to 2s,
-- "but I want it actively watched"). Items you pick, each with the most you'd pay. The
-- flip watch looks for them in every reading of the auction house list (Sweep.lua), and
-- the Buy queue buys them with the vendor flips, first in the list. Added with the
-- price window's Watch box, or on the Watched items list (Buy queue, Vendor flips).
--
-- ns.db.watchItems[itemID] = { max = copper, or nil for "vendor price", t = time added }
-- The most it pays is your price or a vendor flip's limit (what a vendor pays, less your
-- vendor flip margin), whichever is higher. With no price of yours, it's bought only as a
-- vendor flip, just checked far more often.
---------------------------------------------------------------------------
local function data()
  ns.db.watchItems = ns.db.watchItems or {}
  return ns.db.watchItems
end

function ns:IsWatched(id) return id ~= nil and data()[id] ~= nil end
function ns:WatchPrice(id)
  local w = id and data()[id]
  return w and w.max or nil
end

-- Everything that shows or uses the list catches up: the Buy queue (a changed price can
-- bring back an item it had set aside), the alerts (one already under your price chimes
-- now), the list and the price window. Only a recent price chimes: the queue leaves out
-- finds older than a full scan's wait, and the flip watch checks this item on its next
-- pass anyway (Codex review, November 10: an hour-old price was announced as in the queue).
local function changed(id)
  if ns.UnparkBuyQueue then ns:UnparkBuyQueue({ id }) end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if ns.CheckFlip and rec and rec.t and time() - rec.t <= (ns.FLIP_DROP_SECONDS or 900) then
    pcall(ns.CheckFlip, ns, id)
  end
  if ns.RebuildBuyQueue then ns:RebuildBuyQueue() end
  if ns.RefreshWatchedView then ns:RefreshWatchedView() end
  if ns.RefreshPriceWindow then ns:RefreshPriceWindow() end
end

-- Watch an item, or change its price. max: copper; nil or 0 for the vendor price.
function ns:WatchItem(id, max)
  if not id then return end
  local w = data()[id] or { t = time() }
  w.max = (max and max > 0) and math.floor(max) or nil
  data()[id] = w
  changed(id)
  return w
end

function ns:UnwatchItem(id)
  if not (id and data()[id]) then return end
  data()[id] = nil
  changed(id)
end

-- The most to pay for a watched item, how it was set ("you": your price; "vendor": a
-- vendor flip's limit) and what a vendor pays. nil when it has neither: no price of
-- yours, and no vendor buys it (or a vendor sells it, which flips leave out too).
function ns:WatchLimit(id)
  local w = id and data()[id]
  if not w then return end
  local sell = ns:GetSellPrice(id)
  local flip
  if sell and sell > 0 and not ns:GetVendorBuyPrice(id) then
    local limit = ns:VendorFlipLimit(sell)
    if limit > 0 then flip = limit end
  end
  if w.max and w.max > 0 and w.max >= (flip or 0) then return w.max, "you", sell end
  if flip then return flip, "vendor", sell end
  return nil, nil, sell
end

-- The most the Buy queue's Vendor flips may pay for an item now, whatever is listed: a
-- watched item's limit, else a vendor flip's; nil when it's neither. BuyQueue.lua checks
-- it again right before each purchase is sent, so a price lowered or removed while a
-- purchase waits at Confirm applies to it too (Codex review, November 10).
function ns:FlipLimitNow(id)
  if ns:IsWatched(id) then
    local limit = ns:WatchLimit(id)
    return limit and math.floor(limit) or nil
  end
  local sell = ns:GetSellPrice(id)
  if not (sell and sell > 0) or ns:GetVendorBuyPrice(id) then return end
  local limit = ns:VendorFlipLimit(sell)
  return limit > 0 and limit or nil
end

-- A watched item cheap enough to buy now, or nil. Shaped like a vendor flip (Shuffles.lua),
-- so the alerts and the Buy queue take it the same way; f.watched says how: "you" (at or
-- under your price) or "vendor" (a plain vendor flip).
function ns:WatchedFind(id)
  if not (id and data()[id]) then return end
  local limit, how, sell = ns:WatchLimit(id)
  if not limit then return end
  if how == "vendor" then
    local f = ns:VendorFlip(id)
    if f then f.watched = "vendor" end
    return f
  end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if not (rec and rec.m and not rec.none) or rec.m > limit then return end
  local n, avg = ns:CheapListings(id, limit)
  if not (n and n > 0 and avg) then return end
  local value = (sell and sell > 0) and sell or 0
  return {
    id = id, key = "item:" .. id .. ":watch", single = true, units = 1, watched = "you",
    opt = { kind = "watch", value = value, id = id }, share = 0,
    buys = { { id = id, qty = 1, price = avg, listed = n } },
    cost = avg, profit = value - avg, maxBuy = limit, perHour = 0, t = rec.t,
  }
end

function ns:WatchedCount()
  local n = 0
  for _ in pairs(data()) do n = n + 1 end
  return n
end

-- The list in name order, for the Watched items view.
local function sorted()
  local out = {}
  for id, w in pairs(data()) do out[#out + 1] = { id = id, w = w, name = ns.ItemName(id) or ("item " .. id) } end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- An item from the add box: a link, a number or an exact name, else the closest name.
local function resolve(text)
  local id = ns:ResolveItem(text)
  if id then return id end
  local found = ns.FindItemsByName and ns:FindItemsByName(text or "", 1) or {}
  return found[1] and found[1].id or nil
end

---------------------------------------------------------------------------
-- The Watched items view: over the Buy queue, opened with the Watched button on Vendor
-- flips (BuyQueue.lua). Add an item, set or change Up to, remove one.
---------------------------------------------------------------------------
local view
local ROW_H = 24
-- Columns, from a row's left: name, Up to box, Now (right edge), Vendor pays (right edge), remove.
-- (Up to further left than at first: a price over 1g under Now ran into its box; owner,
-- UI pass checks, November 11. Long names are cut and shown whole on hover.)
local C = { name = 22, max = 178, now = 340, vendor = 410, x = 416 }

local function tip(frame, title, text, anchor)
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, anchor or "ANCHOR_TOP")
    GameTooltip:AddLine(title, 1, 1, 1)
    GameTooltip:AddLine(text, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A text box with a grey hint inside while it's empty (as on Shopping lists).
local function hinted(parent, width, hint, justify)
  local eb = T:EditBox(parent, width, justify)
  local fs = T:Text(eb, 11, T.section)
  if justify == "LEFT" then fs:SetPoint("LEFT", 6, 0) else fs:SetPoint("CENTER") end
  fs:SetText(hint)
  local function update(self) fs:SetShown(self:GetText() == "" and not self:HasFocus()) end
  eb:SetScript("OnTextChanged", update)
  eb:SetScript("OnEditFocusGained", function() fs:Hide() end)
  eb:SetScript("OnEditFocusLost", update)
  return eb
end

local function addFromBox(v)
  local text = v.add:GetText()
  local id = v.pendingID or resolve(text)
  if not id then
    ns:Print("Couldn't find that item. Shift-click it from your bags or a chat link, drag it here, or type its name.")
    return
  end
  local maxText = v.max:GetText():gsub("^%s+", ""):gsub("%s+$", "")
  local max = maxText ~= "" and ns.ParseMoneyLoose(maxText, "g") or 0
  if not max or max < 0 then
    ns:Print("Couldn't read that price. Try 2s, 1g 50s, 75c or a plain number for gold; leave it empty for the vendor price.")
    v.max:SetFocus()
    return
  end
  ns:WatchItem(id, max)
  ns:Print(("Watching %s, %s. Watch flips looks for it every time it reads the auction house."):format(ns.ItemName(id) or "it",
    max > 0 and ("up to " .. ns.Money(max)) or "at the vendor price"))
  v.add:SetText(""); v.max:SetText("")
  v.pendingID = nil
  v.add:ClearFocus(); v.max:ClearFocus()
end

local function row(v, i)
  local r = v.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, v.content)
  r:SetHeight(ROW_H)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.hit = CreateFrame("Button", nil, r)
  r.hit:SetPoint("LEFT", 0, 0)
  r.hit:SetSize(C.max - 6, ROW_H)
  r.icon = r.hit:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = T:Text(r.hit, 11)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.name:SetWidth(C.max - C.name - 10)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.hit:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(r.id)
    local limit, how, sell = ns:WatchLimit(r.id)
    GameTooltip:AddLine(" ")
    if how == "you" then
      GameTooltip:AddLine(("Bought at %s or less, your price."):format(ns.Money(limit)), T.accent[1], T.accent[2], T.accent[3], true)
    elseif how == "vendor" then
      GameTooltip:AddLine(("Bought at %s or less: a vendor pays %s, less your vendor flip margin."):format(ns.Money(limit), ns.Money(sell)),
        T.accent[1], T.accent[2], T.accent[3], true)
    else
      GameTooltip:AddLine("Not bought yet: vendors don't buy it, so type the most you'd pay in Up to.", 1, 0.82, 0, true)
    end
    if ns.IsGearItem and ns:IsGearItem(r.id) then
      GameTooltip:AddLine("Gear: any stat version at or under the price.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine("Click to search for it on the auction house.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  r.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.hit:SetScript("OnClick", function()
    if not ns:SearchAuctionHouse(r.id) then ns:Print("Open the auction house, then click an item to search for it.") end
  end)
  r.max = T:MoneyBox(r, function(value) ns:WatchItem(r.id, value) end, "g", false, "vendor")
  r.max:SetWidth(76)
  r.max:SetPoint("LEFT", C.max, 0)
  r.max.compact = true
  r.max:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Up to", 1, 1, 1)
    GameTooltip:AddLine("The most the Buy queue pays for it. \"vendor\": only when a vendor pays more (a vendor flip). A price of yours that's lower than that still buys vendor flips.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  r.max:HookScript("OnLeave", function() GameTooltip:Hide() end)
  r.now = T:Text(r, 11)
  r.now:SetPoint("RIGHT", r, "LEFT", C.now, 0)
  r.now:SetJustifyH("RIGHT")
  r.vendor = T:Text(r, 11, T.dim)
  r.vendor:SetPoint("RIGHT", r, "LEFT", C.vendor, 0)
  r.vendor:SetJustifyH("RIGHT")
  r.remove = T:Button(r, "x", 20, function() ns:UnwatchItem(r.id) end, 20)
  r.remove:SetPoint("LEFT", C.x, 0)
  tip(r.remove, "Stop watching", "Takes it off the list. Nothing you've bought is affected.")
  v.rows[i] = r
  return r
end

local function refresh()
  local v = view
  if not (v and v:IsVisible()) then return end
  local list = sorted()
  local market = ns.db.prices[ns.MarketKey()] or {}
  local width = v.sf:GetWidth() - 12
  v.content:SetWidth(width)
  for i, e in ipairs(list) do
    local r = row(v, i)
    r.id = e.id
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    r.icon:SetTexture(ns:ItemIcon(e.id))
    local limit = ns:WatchLimit(e.id)
    local rec = market[e.id]
    local cheapest = rec and not rec.none and rec.m
    local cheap = cheapest and limit and cheapest <= limit
    r.name:SetText(cheap and ("|cff7fd39c" .. e.name .. "|r") or e.name)
    if not r.max:HasFocus() then r.max:SetValue(e.w.max or 0) end
    r.now:SetText((rec and rec.none and "|cff888888none|r") or (cheapest and (cheap and ("|cff7fd39c" .. ns.MoneyPlain(cheapest) .. "|r") or ns.MoneyPlain(cheapest)))
      or "|cff888888?|r")
    local sell = ns:GetSellPrice(e.id)
    r.vendor:SetText(sell and sell > 0 and ns.MoneyPlain(sell) or "-")
    r:Show()
  end
  for i = #list + 1, #v.rows do v.rows[i]:Hide() end
  v.content:SetHeight(math.max(#list * ROW_H, ROW_H))
  v.sf.UpdateScrollBar()
  v.empty:SetShown(#list == 0)
  v.count:SetText(#list == 0 and "" or ("%d watched. Green: at or under Up to right now."):format(#list))
end

function ns:RefreshWatchedView() refresh() end

local function build(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints(parent)
  v:SetFrameLevel(parent:GetFrameLevel() + 30)
  v:EnableMouse(true)
  T:Fill(v, T.bg)

  local bar = CreateFrame("Frame", nil, v)
  bar:SetPoint("TOPLEFT", 1, 0)
  bar:SetPoint("TOPRIGHT", -1, 0)
  bar:SetHeight(30)
  T:Fill(bar, { 1, 1, 1, 0.035 })
  local line = bar:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)
  line:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
  local title = T:Text(bar, 13)
  title:SetPoint("LEFT", 10, 0)
  title:SetText("Watched items")
  local back = T:Button(bar, "Back to the queue", 130, function() v:Hide() end, 22)
  back:SetPoint("RIGHT", -6, 0)

  local info = T:Text(v, 11, T.dim)
  info:SetPoint("TOPLEFT", 12, -38)
  info:SetPoint("RIGHT", v, "RIGHT", -12, 0)
  info:SetJustifyH("LEFT")
  info:SetWordWrap(true)
  info:SetText("Watch flips looks for these every time it reads the auction house, about every 20 seconds. Anything at or under Up to joins Vendor flips, first in the list, and chimes. Up to \"vendor\": only when a vendor pays more.")

  -- Add: shift-click, drag or type an item; the most you'd pay (empty: vendor price).
  v.add = hinted(v, 214, "Shift-click, drag or type an item", "LEFT")
  v.add:SetPoint("TOPLEFT", 10, -84)
  v.add:HookScript("OnTextChanged", function(self, userInput) if userInput then v.pendingID = ns.ItemIDFromLink(self:GetText()) end end)
  v.add:SetScript("OnEnterPressed", function() addFromBox(v) end)
  v.add:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local function drop()
    local kind, id, link = GetCursorInfo()
    if kind == "item" and id then
      ClearCursor()
      v.add:SetText(link or ns.ItemName(id) or "")
      v.pendingID = id
      v.max:SetFocus()
    end
  end
  v.add:SetScript("OnReceiveDrag", drop)
  v.add:SetScript("OnMouseDown", function() if GetCursorInfo() then drop() end end)
  v:SetScript("OnReceiveDrag", drop)
  v.max = hinted(v, 90, "up to: vendor")
  T:MoneyPreview(v.max, "g")
  v.max:SetPoint("LEFT", v.add, "RIGHT", 4, 0)
  v.max:SetScript("OnEnterPressed", function() addFromBox(v) end)
  local addB = T:Button(v, "Watch", 70, function() addFromBox(v) end, 22)
  addB:SetPoint("LEFT", v.max, "RIGHT", 4, 0)
  tip(addB, "Watch", "Adds the item. Leave the price empty to buy it only as a vendor flip, or type the most you'd pay: 2s, 1g 50s, or a plain number for gold.")

  local header = CreateFrame("Frame", nil, v)
  header:SetPoint("TOPLEFT", 6, -114)
  header:SetPoint("TOPRIGHT", -6, -114)
  header:SetHeight(20)
  T:Fill(header, { 1, 1, 1, 0.05 })
  local function head(text, point, x)
    local fs = T:Text(header, 11, T.dim)
    fs:SetText(text)
    fs:SetPoint(point, header, "LEFT", x, 0)
    return fs
  end
  head("Item", "LEFT", 8)
  head("Up to", "LEFT", C.max + 2)
  head("Now", "RIGHT", C.now)
  head("Vendor", "RIGHT", C.vendor)   -- (what a vendor pays; "Vendor pays" ran into Now)

  v.sf, v.content = T:Scroll(v)
  v.sf:SetPoint("TOPLEFT", 6, -136)
  v.sf:SetPoint("BOTTOMRIGHT", -6, 34)
  v.rows = {}
  v.empty = T:Text(v, 12, T.dim)
  v.empty:SetPoint("TOP", v.sf, "TOP", 0, -30)
  v.empty:SetWidth(380)
  v.empty:SetWordWrap(true)
  v.empty:SetText("Nothing watched yet. Add an item above, or tick Watch in an item's price window.")
  v.count = T:Text(v, 11, T.dim)
  v.count:SetPoint("BOTTOMLEFT", 12, 12)

  -- Keep Now current while it's open (the flip watch sees these in every reading).
  local elapsed = 0
  v:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 2 then elapsed = 0; refresh() end
  end)
  v:SetScript("OnShow", refresh)
  v:SetScript("OnHide", function()
    if ns.UpdatePanelScanButtons then ns:UpdatePanelScanButtons() end
  end)
  v:Hide()
  return v
end

-- Opens the list over the Buy queue (parent: the queue view), or closes it.
function ns:ToggleWatchedView(parent, show)
  if not view then
    if not parent then return end
    view = build(parent)
  end
  if show == nil then show = not view:IsShown() end
  view:SetShown(show)
end
function ns:WatchedViewShown() return view ~= nil and view:IsVisible() end
ns:On("AUCTION_HOUSE_CLOSED", function() if view then view:Hide() end end)

-- Shift-click an item while the list is open: into the add box if you're typing there,
-- else straight onto the list at the vendor price.
local function onModifiedClick(link)
  local v = view
  if not (v and v:IsVisible() and type(link) == "string") then return end
  if IsModifiedClick and not IsModifiedClick("CHATLINK") then return end
  local id = ns.ItemIDFromLink(link)
  if not id then return end
  if v.add:HasFocus() or v.max:HasFocus() then
    v.add:SetText(link)
    v.pendingID = id
    return
  end
  if not ns:IsWatched(id) then
    ns:WatchItem(id, nil)
    ns:Print(("Watching %s at the vendor price. Type a price in Up to to buy it for more."):format(link))
  end
end
if HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", onModifiedClick) end
