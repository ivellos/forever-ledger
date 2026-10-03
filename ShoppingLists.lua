local _, ns = ...

---------------------------------------------------------------------------
-- Shopping lists (Magic's request, October 1): named lists of items with the most
-- you'd pay and how many you want to have, for example raid consumables or their
-- materials, or twink gear to watch for. Searched in one click on the auction house
-- (BuyQueue.lua), and items at or under their price join the buy queue.
--
-- Saved in ns.db.shopping = { lists = { { name, on, kind, items = { { id, max, qty, suffix, found } } } }, current }
-- kind: "search" or "buy" (nil: a list from before kinds, a buy list).
-- max: copper, 0 = no limit (search only, never bought by the queue).
-- qty: how many you want to have (bags and bank), nil = no limit.
-- suffix: one version of a gear item ("of the Monkey"); found: the last Search all of a
-- gear item, { t, total, min, versions = { { name, min, qty } } }.
---------------------------------------------------------------------------
local function data() return ns.db.shopping end

function ns:ShoppingLists() return data().lists end

function ns:CurrentShoppingList()
  local d = data()
  if #d.lists == 0 then return nil, 0 end
  d.current = math.max(1, math.min(d.current or 1, #d.lists))
  return d.lists[d.current], d.current
end

function ns:SelectShoppingList(i)
  local d = data()
  if #d.lists > 0 then d.current = ((i - 1) % #d.lists) + 1 end
end

-- kind: "search" (an "is any of it up right now" list: Search all, no buying settings)
-- or "buy" (Want, price limits, the buy queue). New lists start as the setting says,
-- search unless changed (Magic, October 3: searching is what most lists are for).
-- Lists from before kinds existed have no kind and are buy lists.
function ns:NewShoppingList(name, kind)
  local d = data()
  kind = kind or ns.db.settings.listKind or "search"
  -- Not in the buy queue until you tick it (owner, October 2).
  d.lists[#d.lists + 1] = { name = name, on = false, items = {}, kind = kind }
  d.current = #d.lists
  return d.lists[d.current]
end

function ns:IsSearchList(list) return list ~= nil and list.kind == "search" end

function ns:DeleteShoppingList(i)
  local d = data()
  table.remove(d.lists, i)
  d.current = math.max(1, math.min(d.current or 1, #d.lists))
end

-- Adds an item, or updates it if the list has it already. Returns the entry.
-- suffix: one version of a gear item, "of the Monkey" (any level); the same item can
-- be on a list once per version.
function ns:AddToShoppingList(list, id, max, qty, suffix)
  for _, e in ipairs(list.items) do
    if e.id == id and e.suffix == suffix then
      if max then e.max = max end
      if qty then e.qty = qty end
      return e
    end
  end
  local e = { id = id, max = max or 0, qty = qty, suffix = suffix }
  list.items[#list.items + 1] = e
  return e
end

-- An entry's name, with its version if it has one.
function ns:ListEntryName(e)
  local name = ns.ItemName(e.id) or ("item " .. e.id)
  return e.suffix and (name .. " " .. e.suffix) or name
end

-- An item from what was typed or dropped: an item link, an item number, or an exact
-- name the game or this addon knows (every item a scan has seen has its name saved).
function ns:ResolveItem(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  -- An item link, a plain item number, or a Wowhead address (".../item=13510/...").
  local id = ns.ItemIDFromLink(text) or tonumber(text) or tonumber(text:match("item=(%d+)") or "")
  if id then return id end
  local name = text:gsub('^"(.*)"$', "%1")
  local _, link = ns.GetItemInfo(name)
  id = link and ns.ItemIDFromLink(link)
  if id then return id end
  local lower = name:lower()
  for itemID, n in pairs(ns.db.itemNames or {}) do
    if n:lower() == lower then return itemID end
  end
  for itemID, n in pairs(ns.CLASSIC_ITEMS or {}) do
    if n:lower() == lower then return itemID end
  end
end

-- Like ResolveItem, but also reads one version of a gear item: "Soldier's Armor of the
-- Monkey" typed, or a shift-clicked link of that version. Returns id, suffix ("of the
-- Monkey") or id, nil. Item names can have "of" in them too (Staff of Horrors), so the
-- whole text is tried first, then the part before each " of ", from the right.
local instantInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local function isGear(id)
  if not instantInfo then return false end
  local _, _, _, _, _, classID = instantInfo(id)
  return classID == 2 or classID == 4
end
function ns:ResolveItemVersion(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local linkID = ns.ItemIDFromLink(text)
  if linkID then
    -- A link's text has the version in it: [Soldier's Armor of the Monkey].
    local shown = text:match("|h%[(.-)%]|h")
    local base = ns.GetItemInfo(linkID) and (ns.GetItemInfo(linkID)) or ns.ItemName(linkID)
    if shown and base and isGear(linkID) and #shown > #base and shown:sub(1, #base) == base then
      local suffix = shown:sub(#base + 2)
      if suffix:lower():find("^of ") then return linkID, suffix end
    end
    return linkID
  end
  local id = ns:ResolveItem(text)
  if id then return id end
  local name = text:gsub('^"(.*)"$', "%1")
  local pos = #name
  while true do
    local at
    for i = pos, 1, -1 do
      if name:sub(i, i + 3):lower() == " of " then at = i; break end
    end
    if not at then return end
    local baseID = ns:ResolveItem(name:sub(1, at - 1))
    if baseID and isGear(baseID) then return baseID, name:sub(at + 1) end
    pos = at - 1
  end
end

-- Items whose name contains what was typed, for the suggestions under the add box:
-- names this addon has seen in Forever (scans, bags), and original Classic items.
-- Names starting with the text come first. Returns up to `max` { id, name }.
-- Original Classic items that can't be bought (bind when picked up, quest items).
local boundSet
function ns:IsClassicBound(id)
  if not boundSet then
    boundSet = {}
    for n in (ns.CLASSIC_BOUND or ""):gmatch("%d+") do boundSet[tonumber(n)] = true end
  end
  return boundSet[id] or false
end

-- Sorted by name, items you can buy before bound ones.
local nameIndex, nameIndexSize
local function buildNameIndex()
  local seen, list = {}, {}
  for id, n in pairs(ns.db.itemNames or {}) do
    seen[id] = true
    list[#list + 1] = { id = id, name = n, lower = n:lower(), bound = ns:IsClassicBound(id) }
  end
  for id, n in pairs(ns.CLASSIC_ITEMS or {}) do
    if not seen[id] then list[#list + 1] = { id = id, name = n, lower = n:lower(), bound = ns:IsClassicBound(id) } end
  end
  table.sort(list, function(a, b)
    if a.bound ~= b.bound then return not a.bound end
    return a.lower < b.lower
  end)
  return list
end

-- Names starting with the text first, then names containing it; bound items last.
function ns:FindItemsByName(text, max)
  text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if #text < 2 then return {} end
  local count = 0
  for _ in pairs(ns.db.itemNames or {}) do count = count + 1 end
  if not nameIndex or count ~= nameIndexSize then nameIndex, nameIndexSize = buildNameIndex(), count end
  local groups = { {}, {}, {}, {} }   -- starts, contains, bound starts, bound contains
  for _, e in ipairs(nameIndex) do
    local at = e.lower:find(text, 1, true)
    if at then
      local g = groups[(e.bound and 2 or 0) + (at == 1 and 1 or 2)]
      if #g < max then g[#g + 1] = e end
      if not e.bound and at == 1 and #g >= max then break end
    end
  end
  local out = {}
  for _, g in ipairs(groups) do
    for _, e in ipairs(g) do
      if #out >= max then return out end
      out[#out + 1] = e
    end
  end
  return out
end
ns.FindItemsByName = ns.Timed("Item name search", ns.FindItemsByName)

---------------------------------------------------------------------------
-- Sharing lists (Magic, October 2: "share shopping lists with each other via the
-- Discord"). Plain text anyone can read, edit or write by hand, one item per line:
--   Forever Ledger shopping list: Raid prep
--   any price
--   13510 Flask of the Titans | want 2
--   2772 Iron Ore | max 1g 50s | want 20
--   13511 Flask of Distilled Wisdom | craft | want 3
--   6545 Soldier's Armor | version of the Monkey
-- (and a "search list" or "buy list" line after the name).
-- Import also takes plain item names, item links and Wowhead addresses, one per line.
-- Nothing in it is run as code.
---------------------------------------------------------------------------
local HEADER = "Forever Ledger shopping list: "

function ns:ExportShoppingList(list)
  local lines = { HEADER .. list.name }
  lines[#lines + 1] = ns:IsSearchList(list) and "search list" or "buy list"
  if list.anyPrice then lines[#lines + 1] = "any price" end
  if ns:BuyMode(list) then lines[#lines + 1] = "buy this many" end
  for _, e in ipairs(list.items) do
    local parts = { e.id .. " " .. ns.ItemName(e.id) }
    if e.suffix then parts[#parts + 1] = "version " .. e.suffix end
    if e.mode == "craft" then parts[#parts + 1] = "craft" end
    if e.mode ~= "craft" and e.max == -1 then parts[#parts + 1] = "max any"
    elseif e.mode ~= "craft" and (e.max or 0) > 0 then parts[#parts + 1] = "max " .. ns.MoneyPlain(e.max) end
    if e.qty then parts[#parts + 1] = "want " .. e.qty end
    lines[#lines + 1] = table.concat(parts, " | ")
  end
  return table.concat(lines, "\n")
end

-- Reads one or more pasted lists. Returns ok, message.
function ns:ImportShoppingLists(text)
  local made, items, unknown = {}, 0, {}
  local list
  local kindSaid = {}   -- [list] = true once a "search list" / "buy list" line was read
  local function newList(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Imported list" end
    -- Don't overwrite a list you have: "Raid prep (2)".
    local taken = {}
    for _, l in ipairs(ns:ShoppingLists()) do taken[l.name] = true end
    local base, n = name, 1
    while taken[name] do n = n + 1; name = ("%s (%d)"):format(base, n) end
    list = ns:NewShoppingList(name)
    made[#made + 1] = list
  end
  for raw in (text or ""):gmatch("[^\r\n]+") do
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    local lower = line:lower()
    if line == "" or line:match("^```") then
      -- blank, or a Discord code block fence
    elseif lower:find(HEADER:lower(), 1, true) == 1 then
      newList(line:sub(#HEADER + 1))
    elseif lower == "search list" or lower == "buy list" then
      if not list then newList() end
      list.kind = lower == "search list" and "search" or "buy"
      kindSaid[list] = true
    elseif lower == "any price" then
      if not list then newList() end
      list.anyPrice = true
    elseif lower == "buy this many" or lower == "keep this many" then
      if not list then newList() end
      list.wantMode = lower == "buy this many" and "buy" or nil
    elseif line:find("|Hitem:", 1, true) then
      -- A pasted item link (it has | in it, so it's read whole).
      local id = ns.ItemIDFromLink(line)
      if id then
        if not list then newList() end
        ns:AddToShoppingList(list, id)
        items = items + 1
      end
    else
      local fields = {}
      for f in line:gmatch("[^|]+") do fields[#fields + 1] = f:gsub("^%s+", ""):gsub("%s+$", "") end
      local first = fields[1] or ""
      -- "13510 Flask of the Titans": the number is the item; otherwise the whole field.
      local id, suffix = tonumber(first:match("^(%d+)%s") or ""), nil
      if not id then id, suffix = ns:ResolveItemVersion(first) end
      if id then
        if not list then newList() end
        local max, qty, craft
        for i = 2, #fields do
          local f = fields[i]:lower()
          if f == "craft" then craft = true
          elseif f:match("^want%s") then qty = tonumber(f:match("^want%s+(%d+)"))
          elseif f:match("^version%s") then suffix = fields[i]:match("^%a+%s+(.+)$")
          elseif f:match("^max%s") then max = ns.ParseMoneyLoose(f:match("^max%s+(.+)$"), "g") end
        end
        -- Lists shared before list kinds: buying settings mean a buy list.
        if (max or qty or craft) and not kindSaid[list] then list.kind = "buy" end
        local e = ns:AddToShoppingList(list, id, max, qty, suffix)
        if craft then e.mode = "craft" end
        items = items + 1
      else
        unknown[#unknown + 1] = first
      end
    end
  end
  if #made == 0 then
    return false, "Nothing to import: paste a shared list (it starts with \"" .. HEADER .. "\"), or item names, one per line."
  end
  local names = {}
  for _, l in ipairs(made) do names[#names + 1] = l.name end
  local msg = ("Imported %d %s (%s) with %d items."):format(#made, #made == 1 and "list" or "lists", table.concat(names, ", "), items)
  if #unknown > 0 then
    msg = msg .. (" Couldn't find %d: %s."):format(#unknown, table.concat(unknown, ", "):sub(1, 200))
  end
  return true, msg
end

-- Bought on the auction house but still in the mailbox: purchases arrive by mail, so
-- bags didn't change and the list kept asking for more (owner's test, October 2:
-- Crafted Light Shot bought, Have still 0). Each purchase is noted with what bags and
-- bank held then; as they fill up (mail taken), the count goes down. Gone after 31 days
-- (mail expires after 30).
-- ns.db.onTheWay[itemID] = { n = count, base = bags and bank when noted, t = time }
local function bagsAndBank(id)
  local n = GetItemCount and GetItemCount(id, true)
  return n or 0
end

function ns:NoteBoughtToMail(id, qty)
  if not (id and qty and qty > 0 and ns.db) then return end
  ns.db.onTheWay = ns.db.onTheWay or {}
  local w = ns.db.onTheWay[id] or { n = 0 }
  local now = bagsAndBank(id)
  w.n, w.base, w.t = w.n + qty, w.base and math.min(w.base, now) or now, time()
  ns.db.onTheWay[id] = w
  ns:NoteListPurchase(id, qty)
end

function ns:InTheMail(id)
  local all = ns.db and ns.db.onTheWay
  local w = all and all[id]
  if not w then return 0 end
  if time() - (w.t or 0) > 31 * 86400 then all[id] = nil; return 0 end
  local now = bagsAndBank(id)
  if now > w.base then w.n = math.max(0, w.n - (now - w.base)) end
  w.base = now
  if w.n <= 0 then all[id] = nil; return 0 end
  return w.n
end

-- How many you have of an item on this character: bags, bank, and bought on the
-- auction house but still in the mail.
function ns:HaveCount(id)
  return bagsAndBank(id) + ns:InTheMail(id)
end

---------------------------------------------------------------------------
-- Crafting instead of buying (owner, October 2: "I want to craft 10 Wizard Oils: pull
-- the list of things I need"). An item set to Craft adds its recipe's materials, for
-- the number wanted less what you have, minus the materials you already have.
---------------------------------------------------------------------------
-- The recipe that makes an item: one a character of yours knows first, otherwise any
-- recipe the recipe book has seen. Returns { r = { { itemID, qty } }, oq, name, prof, who } or nil.
local recipeCache, recipeCacheTime = nil, 0
local function recipeIndex()
  if recipeCache and GetTime() - recipeCacheTime < 30 then return recipeCache end
  local idx = {}
  for _, c in pairs(ns.db.chars or {}) do
    for prof, p in pairs(c.profs or {}) do
      for _, rec in pairs(p.recipes or {}) do
        if rec.out and rec.r and #rec.r > 0 and not idx[rec.out] then
          idx[rec.out] = { r = rec.r, oq = rec.oq or 1, name = rec.n, prof = prof, who = c.name }
        end
      end
    end
  end
  for prof, book in pairs(ns.db.recipeBook or {}) do
    for _, rec in pairs(book) do
      if rec.out and rec.r and #rec.r > 0 and not idx[rec.out] then
        idx[rec.out] = { r = rec.r, oq = rec.oq or 1, name = rec.n, prof = prof }
      end
    end
  end
  recipeCache, recipeCacheTime = idx, GetTime()
  return idx
end

-- Falls back to the original Classic recipe (ClassicItems.lua), marked classic.
function ns:RecipeFor(id)
  local r = recipeIndex()[id]
  if r then return r end
  local c = ns.CLASSIC_CRAFTS and ns.CLASSIC_CRAFTS[id]
  if not c then return end
  local mats = {}
  for i = 1, #c[4], 2 do mats[#mats + 1] = { c[4][i], c[4][i + 1] } end
  return { r = mats, oq = c[1], prof = c[2], skill = c[3], classic = true }
end

-- "Any price" (owner, October 2: "times where you just have to eat the costs", raids):
-- buy the cheapest ones there are, but never more than 3 times the usual price when we
-- know it, so a joke listing at 999g can't be bought by a wheel tick.
local ANY_CAP = 3
function ns:AnyPriceLimit(id)
  local stats = ns.PriceStats and ns:PriceStats(id, "month")
  local usual = stats and stats.points >= 3 and stats.usual
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  local now = rec and not rec.none and (rec.a or rec.m)
  local base = usual or now
  if not base then return math.huge end
  return math.floor(math.max(base * ANY_CAP, rec and rec.m or 0))
end

-- The most to pay for a material by default: its usual (typical) price from your scans,
-- else the average of the cheapest listings. You can type your own on the list.
-- Second value: true if you typed it, "any" for any price.
function ns:MaterialLimit(list, id)
  if list.anyPrice or (list.matMax and list.matMax[id] == -1) then return ns:AnyPriceLimit(id), "any" end
  if list.matMax and list.matMax[id] then return list.matMax[id], true end
  local stats = ns.PriceStats and ns:PriceStats(id, "month")
  if stats and stats.points >= 3 and stats.usual then return math.floor(stats.usual), false end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if rec and not rec.none and (rec.a or rec.m) then return math.floor(rec.a or rec.m), false end
end

-- Materials for the list's Craft items: { { id, need, have, buy, vendor, limit, own } }
-- (vendor: a vendor sells it, so it isn't bought on the auction house), and the Craft
-- items with no recipe known.
---------------------------------------------------------------------------
-- Done (owner, October 2: "make sure things don't keep getting refilled into the buy
-- queue"). Once you have the number you want of an item (Want, or 1), it's marked done
-- and stays done, saved, even after you use some, until you click Buy again. The same
-- for a material once you have enough of it.
---------------------------------------------------------------------------
-- Two ways to read Want (owner, October 2: "the option for both, if we can make it clear"):
--   "keep" (the default): keep this many, counting bags, bank and the mail; Buy again
--     tops you up to it after you've used some (raid consumables).
--   "buy": buy this many, whatever you have; what's bought since Buy again counts (e.bought,
--     list.matBought), and Buy again buys the whole amount again.
function ns:BuyMode(list) return list and list.wantMode == "buy" end

function ns:ItemDone(e, list)
  if not e.done then
    if ns:BuyMode(list) then
      if e.mode == "craft" then
        -- Done once every material for it is bought.
        local recipe = ns:RecipeFor(e.id)
        local all = recipe and list.matDone and true
        for _, r in ipairs(recipe and recipe.r or {}) do
          if not list.matDone[r[1]] then all = false end
        end
        if all then e.done = true end
      elseif (e.bought or 0) >= (e.qty or 1) then
        e.done = true
      end
    elseif ns:HaveCount(e.id) >= (e.qty or 1) then
      e.done = true
    end
  end
  return e.done or false
end

function ns:BuyListAgain(list)
  for _, e in ipairs(list.items) do e.done, e.bought = nil, nil end
  list.matDone, list.matBought = nil, nil
end

-- An auction house purchase: lists set to "buy this many" count it, items first, then
-- materials, only up to what each still needs.
function ns:NoteListPurchase(id, qty)
  for _, list in ipairs(data().lists) do
    if ns:BuyMode(list) and qty > 0 then
      for _, e in ipairs(list.items) do
        if e.id == id and e.mode ~= "craft" and not e.done and qty > 0 then
          local add = math.min(qty, (e.qty or 1) - (e.bought or 0))
          if add > 0 then e.bought, qty = (e.bought or 0) + add, qty - add end
        end
      end
      if qty > 0 then
        for _, m in ipairs((ns:ListMaterials(list))) do
          if m.id == id and m.buy > 0 then
            local add = math.min(qty, m.buy)
            list.matBought = list.matBought or {}
            list.matBought[id] = (list.matBought[id] or 0) + add
            qty = qty - add
          end
        end
      end
    end
  end
end

function ns:ListMaterials(list)
  local buyMode = ns:BuyMode(list)
  local need, order, missing = {}, {}, {}
  for _, e in ipairs(list.items) do
    -- Buy this many: materials for the whole amount, done or not (they show as done).
    -- Keep this many: only for what you're short of.
    if e.mode == "craft" and (buyMode or not ns:ItemDone(e, list)) then
      local recipe = ns:RecipeFor(e.id)
      if not recipe then
        missing[#missing + 1] = e.id
      else
        local short = buyMode and (e.qty or 1) or math.max(0, (e.qty or 1) - ns:HaveCount(e.id))
        local crafts = math.ceil(short / math.max(recipe.oq or 1, 1))
        for _, r in ipairs(recipe.r) do
          local mat, qty = r[1], r[2] or 1
          if not need[mat] then need[mat] = 0; order[#order + 1] = mat end
          need[mat] = need[mat] + crafts * qty
        end
      end
    end
  end
  local out = {}
  for _, mat in ipairs(order) do
    if need[mat] > 0 then
      local have = ns:HaveCount(mat)
      local _, vrec = ns:GetVendorBuyPrice(mat)
      local limit, own = ns:MaterialLimit(list, mat)
      local bought = list.matBought and list.matBought[mat] or 0
      local buy = math.max(0, need[mat] - (buyMode and bought or have))
      -- Enough once is enough: crafting uses them up, but they don't go back on the list.
      list.matDone = list.matDone or {}
      if buy == 0 then list.matDone[mat] = true end
      if list.matDone[mat] then buy = 0 end
      out[#out + 1] = { id = mat, need = need[mat], have = have, bought = bought, buy = buy, done = list.matDone[mat],
        vendor = vrec and not vrec.lim and vrec.p or nil, limit = limit, own = own }
    end
  end
  return out, missing
end

-- Items the buy queue should buy: from lists that are switched on, Buy items with a
-- most-you'd-pay price and (if a number is set) fewer than you want, and the materials
-- for Craft items that you're short of (not ones a vendor sells).
-- Returns { { id, limit, want = how many more or nil, list = list name } }.
function ns:ShoppingTargets()
  local out, seen = {}, {}
  for _, list in ipairs(data().lists) do
    -- Search lists never feed the buy queue: buying from them is by hand.
    if list.on and not ns:IsSearchList(list) then
      for _, e in ipairs(list.items) do
        local max = list.anyPrice and -1 or (e.max or 0)
        if e.mode ~= "craft" and max ~= 0 and not seen[e.id] and not ns:ItemDone(e, list) then
          -- Without a Want number, just one. Buy this many: less what's been bought;
          -- keep this many: less what you have.
          local got = ns:BuyMode(list) and (e.bought or 0) or ns:HaveCount(e.id)
          local want = math.max(0, (e.qty or 1) - got)
          if want > 0 then
            seen[e.id] = true
            out[#out + 1] = { id = e.id, limit = max == -1 and ns:AnyPriceLimit(e.id) or max, any = max == -1,
              want = want, list = list.name }
          end
        end
      end
      for _, m in ipairs((ns:ListMaterials(list))) do
        if m.buy > 0 and not m.vendor and m.limit and not seen[m.id] then
          seen[m.id] = true
          out[#out + 1] = { id = m.id, limit = m.limit, any = m.own == "any", want = m.buy, list = list.name }
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Search all (Magic, October 3: "a one-click 'are any up right now' check", like
-- Auctionator's shopping lists, for rare twink gear). Gear is looked up by name with
-- every quality, so each version ("of the Monkey") shows as its own row with its
-- cheapest price; the versions are kept on the entry (e.found). Everything else is one
-- ordinary search each (prices saved like any scan). One item at a time.
---------------------------------------------------------------------------
local AH = C_AuctionHouse
local runner   -- { list, gear = { entries }, i, rest = { ids }, waiting = entry, tok }

local function qualityFilters()
  local filters = {}
  local F = Enum and Enum.AuctionHouseFilter
  if F then
    for name, value in pairs(F) do
      if type(name) == "string" and name:find("Quality$") then filters[#filters + 1] = value end
    end
  end
  return filters
end
local SORTS
local function sorts()
  if not SORTS and Enum and Enum.AuctionHouseSortOrder then
    SORTS = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  end
  return SORTS or {}
end

local nextGear

-- The versions of this item in the browse results: { { name, min, qty } }.
local function readVersions(e)
  local out, total, min, unnamed = {}, 0, nil, false
  for _, r in ipairs(AH.GetBrowseResults() or {}) do
    if r.itemKey and r.itemKey.itemID == e.id then
      local ok, info = pcall(AH.GetItemKeyInfo, r.itemKey)
      local name = ok and info and info.itemName
      if not name then unnamed = true end
      local q = r.totalQuantity or 0
      out[#out + 1] = { name = name, min = r.minPrice, qty = q }
      total = total + q
      if r.minPrice and r.minPrice > 0 then min = math.min(min or math.huge, r.minPrice) end
    end
  end
  table.sort(out, function(a, b) return (a.min or 0) < (b.min or 0) end)
  return out, total, min, unnamed
end

-- Done with one gear item: keep what was found (only its version, if it has one).
local function finishGear(e, versions, total, min)
  local found = { t = time(), versions = versions, total = total or 0, min = min }
  if e.suffix then
    local want = e.suffix:lower()
    found.total, found.min = 0, nil
    for _, v in ipairs(versions or {}) do
      if v.name and v.name:lower():find(want, 1, true) then
        found.total = found.total + (v.qty or 0)
        if v.min and v.min > 0 then found.min = math.min(found.min or math.huge, v.min) end
      end
    end
  end
  e.found = found
  if runner then runner.waiting = nil end
  C_Timer.After(0.2, function() if nextGear then nextGear() end end)
end

nextGear = function()
  local r = runner
  if not r then return end
  if not (ns.IsAHOpen and ns:IsAHOpen()) then runner = nil; ns:Print("Search all stopped: the auction house closed."); return end
  -- The auction house takes one search at a time: wait for its go-ahead, and for the
  -- buy queue's own lookups.
  if (AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady())
    or (ns.queueBusyUntil and GetTime() < ns.queueBusyUntil) then
    C_Timer.After(0.5, nextGear)
    return
  end
  r.i = r.i + 1
  local e = r.gear[r.i]
  if not e then
    runner = nil
    if #r.rest > 0 then
      ns.Scan:StartList(r.rest, r.list.name)   -- the flip watch carries on when it ends
    else
      ns:Print(("Searched %s."):format(r.list.name))
      if ns.FlipWatchNext then ns.FlipWatchNext() end
    end
    return
  end
  r.waiting, r.tok, r.retried = e, (r.tok or 0) + 1, false
  local tok = r.tok
  ns.queueSending = true
  local ok = pcall(AH.SendBrowseQuery, { searchString = ns.ItemName(e.id) or "", sorts = sorts(),
    filters = qualityFilters(), itemClassFilters = {} })
  ns.queueSending = false
  if not ok then finishGear(e, {}, 0, nil); return end
  -- Nothing listed may mean no reply at all: move on after a few seconds (rare twink
  -- gear is mostly not up, so this is the usual case and kept short).
  C_Timer.After(3, function()
    if runner == r and r.tok == tok and r.waiting == e then
      local versions, total, min = readVersions(e)
      finishGear(e, versions, total, min)
    end
  end)
end

ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  local r = runner
  local e = r and r.waiting
  if not e then return end
  local versions, total, min, unnamed = readVersions(e)
  -- The first reply can be empty or the last search's; the timeout above covers a real
  -- "none listed". Version names can take a moment to load: look once more.
  if #versions == 0 then return end
  if unnamed and e.suffix and not r.retried then
    r.retried = true
    local tok = r.tok
    C_Timer.After(1, function()
      if runner == r and r.tok == tok and r.waiting == e then finishGear(e, readVersions(e)) end
    end)
    return
  end
  finishGear(e, versions, total, min)
end)

function ns:SearchAllList(list)
  if not list or #list.items == 0 then ns:Print("That list has no items yet."); return end
  if not (ns.IsAHOpen and ns:IsAHOpen()) then ns:Print("Open the auction house first."); return end
  if runner then ns:Print("Already searching " .. runner.list.name .. "."); return end
  local scan = ns.Scan
  if scan.active then
    if scan.quiet then
      -- The flip watch's quick checks give way, and carry on afterwards.
      scan:Stop("Paused the flip watch's checks for Search all.")
    else
      ns:Print("A scan is running: Search all can start when it's done.")
      return
    end
  end
  local r = { list = list, gear = {}, rest = {}, i = 0 }
  local seen = {}
  for _, e in ipairs(list.items) do
    if isGear(e.id) then
      r.gear[#r.gear + 1] = e
    elseif not seen[e.id] then
      seen[e.id] = true
      r.rest[#r.rest + 1] = e.id
    end
  end
  ns:Print(("Searching %d %s from %s."):format(#list.items, #list.items == 1 and "item" or "items", list.name))
  runner = r
  nextGear()
end

function ns:SearchAllRunning() return runner ~= nil end
