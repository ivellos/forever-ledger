local _, ns = ...

---------------------------------------------------------------------------
-- Vendor or auction house? Step 1 (owner, November 11, 2026; design in the private notes,
-- planning/VENDOR_OR_AH_DESIGN.md): one line in the tooltip of an item you have, saying
-- what to do with it, with the reason. Keep it (a quest needs it, a recipe of yours uses
-- it, you watch it, it's on your list), or sell it to a vendor, at the auction house, or,
-- when the two are close, either (the middle verdict). Disenchanting shows as a suggestion
-- when it's worth more. Only a suggestion: nothing is sold or posted (owner: "I mostly
-- want to flag the items in the tooltip with a suggestion").
---------------------------------------------------------------------------

-- The middle verdict's name (Frank, November 12: "For now Close Call works").
ns.SELL_MIDDLE = "Close call"

-- The auction house "clearly" pays more: at least this many times what a vendor pays,
-- after the cut and one unsold deposit (as Worth to you counts it); twice, for an item
-- that sells slowly or hasn't been seen to sell.
local CLEAR, SLOW_CLEAR = 1.25, 2
local SLOW = { slow = true, rare = true, none = true }

-- The verdict from the facts (pure, for the tests). f:
--   keep    why to keep it (text), or nil
--   bound   soulbound or a quest item (can't go on the auction house)
--   usable  this character can use or wear it (no red requirement lines)
--   gear    weapon or armor; quality: 0 gray, 1 white, 2 green...
--   vendor  what a vendor pays for one (nil: vendors don't buy it)
--   ah      what one brings on the auction house after the cut and a deposit (nil: no
--           recent price)
--   speed   sell speed key: fast, steady, slow, rare, none, or nil (not known yet)
--   de      what disenchanting one brings (nil: none of your characters can)
--   deWho   who would disenchant it
-- Returns nil (nothing to say) or { kind = "keep" | "vendor" | "middle" | "ah" | "de",
-- value = copper, reason = text or nil, de = copper or nil, deWho = name or nil }.
function ns.SellVerdict(f)
  if f.keep then return { kind = "keep", reason = f.keep } end
  local vendor = (f.vendor and f.vendor > 0) and f.vendor or nil
  local v
  if f.bound then
    -- Gear you can wear may be what you'll wear next, so its suggestion says "If you won't
    -- wear it" (Frank, November 14: dungeon and quest drops had no suggestion at all).
    local wearable = f.gear and f.usable and (f.quality or 0) >= 2
    if vendor then v = { kind = "vendor", value = vendor, reason = "can't be sold on the auction house", ifUnused = wearable or nil } end
    if wearable and not v and f.de then v = { kind = "de", ifUnused = true } end
  elseif not vendor then
    if f.ah then v = { kind = "ah", value = f.ah, reason = "vendors don't buy it" } end
  elseif not f.ah then
    -- With no recent auction price only gray items are judged (nothing else is called
    -- vendor trash on a guess).
    if (f.quality or 1) == 0 then v = { kind = "vendor", value = vendor } end
  elseif f.ah <= vendor then
    v = { kind = "vendor", value = vendor, reason = "a vendor pays as much or more" }
  else
    local ratio = f.ah / vendor
    local more = ("auction house %d%% more"):format(math.floor((ratio - 1) * 100 + 0.5))
    if SLOW[f.speed or ""] then
      if ratio >= SLOW_CLEAR then
        v = { kind = "ah", value = f.ah, reason = "sells slowly, but it's worth the wait" }
      elseif ratio >= CLEAR then
        v = { kind = "middle", value = f.ah, reason = more .. ", but it sells slowly" }
      else
        v = { kind = "vendor", value = vendor, reason = more .. ", and it sells slowly" }
      end
    elseif ratio >= CLEAR then
      v = { kind = "ah", value = f.ah, reason = "after the cut and the deposit" }
    else
      v = { kind = "middle", value = f.ah, reason = more }
    end
  end
  -- Disenchanting, offered beside the verdict when it brings more; when it brings clearly
  -- more (the same 25% as the auction house over a vendor), it's the suggestion and selling
  -- the other way (Frank, November 13: "making disenchant the main line when its way better").
  if f.de and f.de > ((v and v.value) or 0) then
    v = v or { kind = "de" }
    v.de, v.deWho = f.de, f.deWho
    if v.kind ~= "de" and v.value and f.de >= v.value * CLEAR then v.deFirst = true end
  end
  return v
end

-- Why to keep it, or nil.
function ns:SellKeepReason(id)
  if ns.QuestNeeds then
    for _, q in ipairs(ns:QuestNeeds(id) or {}) do
      if q.keep then return ("a quest needs it (%s)"):format(q.quest) end
    end
  end
  if ns.IsWatched and ns:IsWatched(id) then return "you watch it" end
  for _, l in ipairs(ns.db.shopping and ns.db.shopping.lists or {}) do
    for _, e in ipairs(l.items or {}) do
      if e.id == id and not e.done then return ns.LocalizeText("it's on your list %s"):format(l.name or "") end
    end
  end
  local users = ns.usage and ns.usage[id]
  if users then
    local first
    for k in pairs(users) do
      if not first or k < first then first = k end
    end
    local who, prof = (first or ""):match("^(.-)|(.*)$")
    if who then return ns.LocalizeText("%s's %s uses it"):format(who, prof) end
  end
end

-- Who'd disenchant it, or nil if nobody who can get it can. A bound copy (soulbound,
-- account-bound or a quest item) stays with this character, so only this character's
-- Enchanting counts; anything else can be mailed, so the best enchanter of yours that the
-- disenchant value counts (Values.lua ns:BestEnchanter). Codex review of 3bb2be7: a
-- soulbound green was offered to an alt who couldn't receive it.
local function enchanter(id, bound)
  local yield = ns:DisenchantYield(id)
  local need = yield and yield.skill or 1
  if bound then
    local me = ns.db.chars and ns.db.chars[ns.CharKey()]
    local p = me and me.profs and me.profs.Enchanting
    if p and (p.rank or 1) >= need then return me.name end
    return nil
  end
  local name, skill = ns:BestEnchanter()
  if name and (skill or 0) >= need then return name end
end

-- An auction price recent enough to advise on: your own scan within the price age in
-- Settings (12 hours), or another addon's current price (Auctionator, TSM). Worth to you
-- may still use an older price; a suggestion to post shouldn't (Codex review of 3bb2be7).
local function recentPrice(id)
  local price, _, t = ns:GetPrice(id)
  if not price then return false end
  if t == nil then return true end
  return time() - t <= (ns.db.settings.maxAgeHours or 12) * 3600
end

-- From the tooltip's own lines: bound (soulbound, account-bound or a quest item), and
-- whether a requirement line is red (this character can't use it). Read before
-- Forever Ledger adds its lines.
function ns.SellTooltipFlags(tt)
  local bound, usable = false, true
  local name = tt and tt.GetName and tt:GetName()
  if not (name and tt.NumLines) then return bound, usable end
  local boundTexts = {}
  for _, key in ipairs({ "ITEM_SOULBOUND", "ITEM_BIND_QUEST", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND" }) do
    if type(_G[key]) == "string" then boundTexts[_G[key]] = true end
  end
  local function red(fs)
    if not (fs and fs.GetTextColor and fs.GetText and ns.Readable(fs:GetText())) then return false end
    local r, g, b = fs:GetTextColor()
    return r and r > 0.9 and g < 0.25 and b < 0.25
  end
  for i = 2, tt:NumLines() do
    local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
    local text = left and left.GetText and ns.Readable(left:GetText())
    if text and boundTexts[text] then bound = true end
    if red(left) or (right and right.IsShown and right:IsShown() and red(right)) then usable = false end
  end
  return bound, usable
end

-- The facts for one item (bound and usable from SellTooltipFlags; copyPrice: what a
-- vendor pays for this copy, when the game said).
function ns:SellFacts(id, bound, usable, copyPrice)
  local f = { keep = ns:SellKeepReason(id), bound = bound, usable = usable ~= false }
  f.gear = ns.IsGearItem and ns:IsGearItem(id) or false
  f.quality = select(3, ns.GetItemInfo(id))
  -- The game's Sell Price is for the whole stack, and everything else here is for one, so
  -- the copy's price only counts when it's less than one's (damaged gear), as in Worth to
  -- you (ns:WorthOfCopy). Owner's screenshots, November 18: a stack of 5 Superior Healing
  -- Potions said Sell: Vendor 12s 50c against 7s 11c on the auction house for one.
  local one = ns:GetSellPrice(id)
  f.vendor = (copyPrice and (not one or copyPrice < one)) and copyPrice or one
  local fresh = recentPrice(id)
  for _, o in ipairs(ns:Options(id) or {}) do
    if o.kind == "ah" and not f.ah and fresh then f.ah = o.value end
    if o.kind == "disenchant" and not f.de then f.de = o.value end
  end
  if f.de then
    f.deWho = enchanter(id, bound)
    if not f.deWho then f.de = nil end
  end
  if ns.SellSpeed then
    local ok, sp = pcall(ns.SellSpeed, ns, id)
    f.speed = ok and sp and sp.key or nil
  end
  return f
end

-- Colours: keep blue, vendor gold, the middle orange, auction house green, disenchant purple.
local COLOR = {
  keep = { 0.53, 0.75, 1 }, vendor = { 1, 0.82, 0 }, middle = { 1, 0.62, 0.3 },
  ah = { 0.5, 0.83, 0.61 }, de = { 0.75, 0.62, 1 },
}
local LABEL = { vendor = "Vendor", ah = "Auction house" }
-- Selling as the other way, under a Disenchant suggestion.
local ALT = { vendor = "or sell to a vendor", ah = "or sell on the auction house", middle = "or sell (close call)" }
-- After "If you won't wear it: ".
local UNUSED = { vendor = "sell to a vendor", ah = "sell on the auction house", middle = "sell (close call)" }

-- The tooltip lines (Tooltip.lua): only for an item you have in your bags.
function ns:AddSellLines(tt, id, bound, usable, copyPrice)
  if not (id and ns.ItemCount(id) > 0) then return end
  local v = ns.SellVerdict(ns:SellFacts(id, bound, usable, copyPrice))
  if not v then return end
  local c = COLOR[v.kind]
  if v.kind == "keep" then
    ns:AddTooltipLine(tt, ns.LocalizeText("Keep: ") .. ns.LocalizeText(v.reason), c[1], c[2], c[3], true)
    return
  end
  local reason = v.reason and (" |cff999999(" .. ns.LocalizeText(v.reason) .. ")|r") or ""
  -- Gear this character can wear: the suggestion is for if it won't wear it.
  local lead = v.ifUnused and ns.LocalizeText("If you won't wear it: ") or ""
  if v.ifUnused then reason = "" end
  local function deLine(text)
    local d = COLOR.de
    ns:AddTooltipDoubleLine(tt, text .. (v.deWho and (" |cff999999(" .. v.deWho .. ")|r") or ""),
      ns.LocalizeText("about ") .. ns.Money(v.de), d[1], d[2], d[3], 1, 1, 1)
  end
  if v.deFirst then
    deLine(lead .. ns.LocalizeText(v.ifUnused and "disenchant" or "Disenchant"))
    ns:AddTooltipDoubleLine(tt, "  " .. ns.LocalizeText(ALT[v.kind] or "or sell") .. reason, ns.Money(v.value), c[1], c[2], c[3], 1, 1, 1)
    return
  end
  if v.kind ~= "de" then
    local what = v.ifUnused and ns.LocalizeText(UNUSED[v.kind] or "sell it") or (ns.LocalizeText("Sell: ") .. ns.LocalizeText(LABEL[v.kind] or ns.SELL_MIDDLE))
    ns:AddTooltipDoubleLine(tt, lead .. what .. reason, ns.Money(v.value), c[1], c[2], c[3], 1, 1, 1)
  end
  if v.de then deLine(v.kind == "de" and (lead .. ns.LocalizeText(v.ifUnused and "disenchant" or "Disenchant")) or "  or disenchant") end
end
