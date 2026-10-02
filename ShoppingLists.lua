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
end

-- How many you have of an item on this character, bags and bank.
function ns:HaveCount(id)
  local n = GetItemCount and GetItemCount(id, true)
  return n or 0
end

-- Items the buy queue should buy: from lists that are switched on, those with a most-
-- you'd-pay price and (if a number is set) fewer than you want.
-- Returns { { id, limit, want = how many more or nil, list = list name } }.
function ns:ShoppingTargets()
  local out, seen = {}, {}
  for _, list in ipairs(data().lists) do
    if list.on then
      for _, e in ipairs(list.items) do
        if (e.max or 0) > 0 and not seen[e.id] then
          local want = e.qty and math.max(0, e.qty - ns:HaveCount(e.id)) or nil
          if want ~= 0 then
            seen[e.id] = true
            out[#out + 1] = { id = e.id, limit = e.max, want = want, list = list.name }
          end
        end
      end
    end
  end
  return out
end
