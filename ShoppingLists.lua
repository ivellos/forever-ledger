local _, ns = ...

---------------------------------------------------------------------------
-- Shopping lists (Magic's request, October 1): named lists of items with the most
-- you'd pay and how many you want to have, for example raid consumables or their
-- materials, or twink gear to watch for. Searched in one click on the auction house
-- (BuyQueue.lua), and items at or under their price join the buy queue.
--
-- Saved in ns.db.shopping = { lists = { { name, on, items = { { id, max, qty } } } }, current }
-- max: copper, 0 = no limit (search only, never bought by the queue).
-- qty: how many you want to have (bags and bank), nil = no limit.
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

function ns:NewShoppingList(name)
  local d = data()
  -- Not in the buy queue until you tick it (owner, October 2).
  d.lists[#d.lists + 1] = { name = name, on = false, items = {} }
  d.current = #d.lists
  return d.lists[d.current]
end

function ns:DeleteShoppingList(i)
  local d = data()
  table.remove(d.lists, i)
  d.current = math.max(1, math.min(d.current or 1, #d.lists))
end

-- Adds an item, or updates it if the list has it already. Returns the entry.
function ns:AddToShoppingList(list, id, max, qty)
  for _, e in ipairs(list.items) do
    if e.id == id then
      if max then e.max = max end
      if qty then e.qty = qty end
      return e
    end
  end
  local e = { id = id, max = max or 0, qty = qty }
  list.items[#list.items + 1] = e
  return e
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
-- Import also takes plain item names, item links and Wowhead addresses, one per line.
-- Nothing in it is run as code.
---------------------------------------------------------------------------
local HEADER = "Forever Ledger shopping list: "

function ns:ExportShoppingList(list)
  local lines = { HEADER .. list.name }
  if list.anyPrice then lines[#lines + 1] = "any price" end
  for _, e in ipairs(list.items) do
    local parts = { e.id .. " " .. ns.ItemName(e.id) }
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
    elseif lower == "any price" then
      if not list then newList() end
      list.anyPrice = true
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
      local id = tonumber(first:match("^(%d+)%s") or "") or ns:ResolveItem(first)
      if id then
        if not list then newList() end
        local max, qty, craft
        for i = 2, #fields do
          local f = fields[i]:lower()
          if f == "craft" then craft = true
          elseif f:match("^want%s") then qty = tonumber(f:match("^want%s+(%d+)"))
          elseif f:match("^max%s") then max = ns.ParseMoneyLoose(f:match("^max%s+(.+)$"), "g") end
        end
        local e = ns:AddToShoppingList(list, id, max, qty)
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
function ns:ItemDone(e)
  if not e.done and ns:HaveCount(e.id) >= (e.qty or 1) then e.done = true end
  return e.done or false
end

function ns:BuyListAgain(list)
  for _, e in ipairs(list.items) do e.done = nil end
  list.matDone = nil
end

function ns:ListMaterials(list)
  local need, order, missing = {}, {}, {}
  for _, e in ipairs(list.items) do
    if e.mode == "craft" and not ns:ItemDone(e) then
      local recipe = ns:RecipeFor(e.id)
      if not recipe then
        missing[#missing + 1] = e.id
      else
        local short = math.max(0, (e.qty or 1) - ns:HaveCount(e.id))
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
      local buy = math.max(0, need[mat] - have)
      -- Enough once is enough: crafting uses them up, but they don't go back on the list.
      list.matDone = list.matDone or {}
      if buy == 0 then list.matDone[mat] = true end
      if list.matDone[mat] then buy = 0 end
      out[#out + 1] = { id = mat, need = need[mat], have = have, buy = buy, done = list.matDone[mat],
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
    if list.on then
      for _, e in ipairs(list.items) do
        local max = list.anyPrice and -1 or (e.max or 0)
        if e.mode ~= "craft" and max ~= 0 and not seen[e.id] and not ns:ItemDone(e) then
          -- Without a Want number, just one.
          local want = math.max(0, (e.qty or 1) - ns:HaveCount(e.id))
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
