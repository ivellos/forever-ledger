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
  d.lists[#d.lists + 1] = { name = name, on = true, items = {} }
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
  local id = ns.ItemIDFromLink(text) or tonumber(text)
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
local nameIndex, nameIndexSize
local function buildNameIndex()
  local seen, list = {}, {}
  for id, n in pairs(ns.db.itemNames or {}) do
    seen[id] = true
    list[#list + 1] = { id = id, name = n, lower = n:lower() }
  end
  for id, n in pairs(ns.CLASSIC_ITEMS or {}) do
    if not seen[id] then list[#list + 1] = { id = id, name = n, lower = n:lower() } end
  end
  table.sort(list, function(a, b) return a.lower < b.lower end)
  return list
end

function ns:FindItemsByName(text, max)
  text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if #text < 2 then return {} end
  local count = 0
  for _ in pairs(ns.db.itemNames or {}) do count = count + 1 end
  if not nameIndex or count ~= nameIndexSize then nameIndex, nameIndexSize = buildNameIndex(), count end
  local starts, contains = {}, {}
  for _, e in ipairs(nameIndex) do
    local at = e.lower:find(text, 1, true)
    if at == 1 then
      starts[#starts + 1] = e
      if #starts >= max then break end
    elseif at and #contains < max then
      contains[#contains + 1] = e
    end
  end
  for _, e in ipairs(contains) do
    if #starts >= max then break end
    starts[#starts + 1] = e
  end
  return starts
end

-- How many you have of an item on this character, bags and bank.
function ns:HaveCount(id)
  local n = GetItemCount and GetItemCount(id, true)
  return n or 0
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

-- The most to pay for a material by default: its usual (typical) price from your scans,
-- else the average of the cheapest listings. You can type your own on the list.
function ns:MaterialLimit(list, id)
  if list.matMax and list.matMax[id] then return list.matMax[id], true end
  local stats = ns.PriceStats and ns:PriceStats(id, "month")
  if stats and stats.points >= 3 and stats.usual then return math.floor(stats.usual), false end
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  if rec and not rec.none and (rec.a or rec.m) then return math.floor(rec.a or rec.m), false end
end

-- Materials for the list's Craft items: { { id, need, have, buy, vendor, limit, own } }
-- (vendor: a vendor sells it, so it isn't bought on the auction house), and the Craft
-- items with no recipe known.
function ns:ListMaterials(list)
  local need, order, missing = {}, {}, {}
  for _, e in ipairs(list.items) do
    if e.mode == "craft" then
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
      out[#out + 1] = { id = mat, need = need[mat], have = have, buy = math.max(0, need[mat] - have),
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
        if e.mode ~= "craft" and (e.max or 0) > 0 and not seen[e.id] then
          local want = e.qty and math.max(0, e.qty - ns:HaveCount(e.id)) or nil
          if want ~= 0 then
            seen[e.id] = true
            out[#out + 1] = { id = e.id, limit = e.max, want = want, list = list.name }
          end
        end
      end
      for _, m in ipairs((ns:ListMaterials(list))) do
        if m.buy > 0 and not m.vendor and m.limit and not seen[m.id] then
          seen[m.id] = true
          out[#out + 1] = { id = m.id, limit = m.limit, want = m.buy, list = list.name }
        end
      end
    end
  end
  return out
end
