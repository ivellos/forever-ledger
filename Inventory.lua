local _, ns = ...

---------------------------------------------------------------------------
-- What each character on this account owns: bags (saved as they change) and bank
-- (saved when the bank is open). Sent to a sync partner only with "Share bags and bank"
-- on (Settings, Global settings, Advanced; Sync.lua); theirs arrive marked via = name.
-- inventory[charKey] = { bags = { [itemID] = count }, bank = { ... }, t, bankT, via }
---------------------------------------------------------------------------
local function scan(bagIDs)
  local counts = {}
  if not (C_Container and C_Container.GetContainerNumSlots) then return counts end
  for _, bag in ipairs(bagIDs) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1) end
    end
  end
  return counts
end

local function bagIDs()
  local ids = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do ids[#ids + 1] = bag end   -- backpack, bags, reagent bag
  return ids
end

local function bankIDs()
  local B = Enum and Enum.BagIndex
  local ids = { (B and B.Bank) or -1 }
  if B and B.Reagentbank then ids[#ids + 1] = B.Reagentbank end
  local first = (B and B.BankBag_1) or ((NUM_BAG_SLOTS or 4) + 2)
  for i = 0, (NUM_BANKBAGSLOTS or 7) - 1 do ids[#ids + 1] = first + i end
  return ids
end

-- Played here, so it's this account's: it stops being a sync partner's (Codex review,
-- October 5: a partner's character you then played kept its mark, and /fl unpair
-- deleted it).
local function mine()
  local key = ns.CharKey()
  ns.db.inventory[key] = ns.db.inventory[key] or { bags = {}, bank = {} }
  local inv = ns.db.inventory[key]
  inv.via = nil
  if ns.db.chars[key] then ns.db.chars[key].via = nil end
  return inv
end

-- With "Share bags and bank" on, a change goes to the sync partner (a few seconds later).
local function shareSoon()
  if ns.db.settings.syncBags and ns.SyncSoon then ns:SyncSoon() end
end

local function saveBags()
  if not ns.db then return end
  local inv = mine()
  inv.bags, inv.t = scan(bagIDs()), time()
  shareSoon()
end

local bankOpen = false
local function saveBank()
  if not ns.db or not bankOpen then return end
  local inv = mine()
  inv.bank, inv.bankT = scan(bankIDs()), time()
  shareSoon()
end

-- Bags change often; save a moment after the last change.
local queued = false
ns:On("BAG_UPDATE_DELAYED", function()
  if queued then return end
  queued = true
  C_Timer.After(2, function()
    queued = false
    saveBags()
    saveBank()
  end)
end)
ns:On("BANKFRAME_OPENED", function() bankOpen = true; C_Timer.After(0.5, saveBank) end)
ns:On("PLAYERBANKSLOTS_CHANGED", function() C_Timer.After(0.5, saveBank) end)
ns:On("BANKFRAME_CLOSED", function() saveBank(); bankOpen = false end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, saveBags) end)
ns:On("PLAYER_LOGOUT", saveBags)

-- Where an item is: this character's bags (live) and bank (as last seen), plus other
-- characters on this account. Returns bags, bank, alts total, and { [name] = count }.
function ns:ItemLocations(id)
  if not id or not ns.db then return 0, 0, 0, {} end
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  local me = ns.CharKey()
  local bags = count and count(id, false, false, true) or 0
  local bank = (ns.db.inventory[me] and ns.db.inventory[me].bank[id]) or 0
  local alts, byAlt = 0, {}
  -- Only characters that could hand it over: same ruleset (realm) and faction, the same
  -- auction house (Magic, October 3: characters on other rulesets counted too).
  local realm, faction = GetRealmName and GetRealmName(), UnitFactionGroup and UnitFactionGroup("player")
  for key, inv in pairs(ns.db.inventory) do
    local c = ns.db.chars[key]
    local same = not c or ((not c.realm or c.realm == realm) and (not c.faction or c.faction == faction))
    if key ~= me and same then
      local n = (inv.bags[id] or 0) + (inv.bank[id] or 0)
      if n > 0 then
        alts = alts + n
        byAlt[(c and c.name) or key] = n
      end
    end
  end
  return bags, bank, alts, byAlt
end
