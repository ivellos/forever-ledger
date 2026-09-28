local _, ns = ...

---------------------------------------------------------------------------
-- Disenchant recorder: logs what each disenchant gives, so the yield table in
-- Values.lua can be checked against Forever. The disenchanted item is found by
-- comparing bags from the start of the cast with bags when the loot appears.
---------------------------------------------------------------------------
local DISENCHANT = 13262
local LOG_SIZE = 1000
local WAIT = 6            -- seconds after the cast for the loot to appear

local pending             -- { bags = snapshot, t = time the cast finished }

local function isDisenchant(spellID)
  if spellID == DISENCHANT then return true end
  local name = ns.SpellName and ns.SpellName(spellID)
  return name ~= nil and name == ns.SpellName(DISENCHANT)
end

-- itemID -> total count in the backpack and bags.
local function bagCounts()
  local counts = {}
  if not (C_Container and C_Container.GetContainerNumSlots) then return counts end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1) end
    end
  end
  return counts
end

---------------------------------------------------------------------------
-- Arcane Salvager (Forever camping object, Enchanting 140): "more efficient
-- disenchanting" for 15 minutes, no numbers published. Disenchants done while one is
-- up are logged apart, so /fl de can show what it really adds.
---------------------------------------------------------------------------
local SALVAGER_TIME = 15 * 60
local salvagerPlaced = 0

-- Names of the player's buffs.
local function buffNames()
  local names = {}
  for i = 1, 40 do
    local name
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      name = ok and aura and aura.name
    elseif UnitBuff then
      name = UnitBuff("player", i)
    end
    if not name then break end
    names[#names + 1] = name
  end
  return names
end

-- "buff" if a Salvager buff is on you, "placed" if you placed one in the last 15
-- minutes (you may have walked away), nil otherwise.
local function salvagerState()
  for _, name in ipairs(buffNames()) do
    if name:find("Salvager", 1, true) then return "buff" end
  end
  if GetTime() - salvagerPlaced < SALVAGER_TIME then return "placed" end
end

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  local name = unit == "player" and ns.SpellName and ns.SpellName(spellID)
  if name and name:find("Arcane Salvager", 1, true) then
    salvagerPlaced = GetTime()
    -- Which buff it gives isn't known yet: show them once, for checking (/fl debug).
    C_Timer.After(2, function() ns:Debug("Arcane Salvager placed. Your buffs now:", table.concat(buffNames(), ", ")) end)
  end
end)

ns:On("UNIT_SPELLCAST_START", function(unit, _, spellID)
  if unit == "player" and isDisenchant(spellID) then
    local item = pending and pending.item   -- may already be known from the lock below
    pending = { bags = bagCounts(), start = GetTime(), item = item, salv = salvagerState() }
  end
end)

-- Picking an item for Disenchant locks it (it greys out). That names the item for
-- certain; the bag comparison is a backup. (Comparing bags alone found nothing in Forever.)
local lockSeen
ns:On("ITEM_LOCK_CHANGED", function(bag, slot)
  if not slot or not (C_Container and C_Container.GetContainerItemInfo) then return end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if info and info.isLocked and info.itemID then
    lockSeen = { id = info.itemID, t = GetTime() }
    if pending and not pending.t then pending.item = info.itemID end
  end
end)

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit == "player" and pending and isDisenchant(spellID) then pending.t = GetTime() end
end)

ns:On("UNIT_SPELLCAST_INTERRUPTED", function(unit, _, spellID)
  if unit == "player" and isDisenchant(spellID) then pending = nil end
end)

-- The item that left the bags: a green or better weapon or armor whose count dropped.
local function disenchantedItem(before)
  local after = bagCounts()
  for id, n in pairs(before) do
    if (after[id] or 0) < n then
      local _, _, quality, _, _, _, _, _, _, _, _, classID = ns.GetItemInfo(id)
      if (classID == 2 or classID == 4) and quality and quality >= 2 then return id end
    end
  end
end

local function onLoot()
  local p = pending
  -- The loot can show a moment before the cast counts as finished, so allow either.
  if not (p and GetTime() - (p.t or p.start) <= WAIT + (p.t and 0 or 5)) then return end
  pending = nil
  local mats, any = {}, false
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local _, _, qty = GetLootSlotInfo(i)
    local id = ns.ItemIDFromLink(GetLootSlotLink and GetLootSlotLink(i))
    if id then mats[id] = (mats[id] or 0) + (qty or 1); any = true end
  end
  if not any then return end
  -- The locked item if seen, otherwise compare bags a moment later.
  if not p.item and lockSeen and GetTime() - lockSeen.t < 15 then p.item = lockSeen.id end
  C_Timer.After(1.5, function()
    local id = p.item or disenchantedItem(p.bags)
    local quality, ilvl, classID
    if id then
      local _
      _, _, quality, ilvl, _, _, _, _, _, _, _, classID = ns.GetItemInfo(id)
    end
    local log = ns.db.disenchants
    log[#log + 1] = { t = time(), id = id, ilvl = ilvl, q = quality, cls = classID, mats = mats, salv = p.salv }
    while #log > LOG_SIZE do table.remove(log, 1) end
    local parts = {}
    for m, n in pairs(mats) do parts[#parts + 1] = n .. " " .. ns:DisenchantMaterialName(m) end
    ns:Debug("Disenchanted", id and ((ns.GetItemInfo(id)) or id) or "unknown item", "item level", ilvl or "?",
      "->", table.concat(parts, ", "))
  end)
end
ns:On("LOOT_READY", onLoot)
ns:On("LOOT_OPENED", onLoot)

---------------------------------------------------------------------------
-- /fl de: totals per group, next to what the table expects
---------------------------------------------------------------------------
local function groupFor(e)
  -- With an Arcane Salvager up, a group of its own, next to the same items without.
  local salv = e.salv == "buff" and " |cff66bbffwith Arcane Salvager|r"
    or e.salv == "placed" and " |cff66bbffwith Arcane Salvager (placed nearby, no buff seen)|r" or ""
  local yield = e.id and ns:DisenchantYield(e.id)
  if yield then return yield.label .. salv, yield end
  local kind = e.cls == 2 and "weapons" or "armor"
  local quality = e.q == 3 and "blue" or (e.q == 4 and "purple" or "green")
  return ("Item level %s %s %s (not in the table)"):format(e.ilvl or "?", quality, kind) .. salv, nil
end

function ns:PrintDisenchants(reset)
  local log = ns.db.disenchants
  if reset then
    wipe(log)
    ns:Print("Disenchant log cleared. Disenchant as usual, then /fl de to see the totals.")
    return
  end
  if #log == 0 then
    ns:Print("No disenchants recorded yet. Disenchant some items, then /fl de. (/fl de reset starts a fresh count.)")
    return
  end
  local groups, order = {}, {}
  for _, e in ipairs(log) do
    local label, yield = groupFor(e)
    local g = groups[label]
    if not g then g = { n = 0, mats = {}, yield = yield }; groups[label] = g; order[#order + 1] = label end
    g.n = g.n + 1
    for m, c in pairs(e.mats) do g.mats[m] = (g.mats[m] or 0) + c end
  end
  table.sort(order)
  ns:Print(("Disenchant log: %d items since %s."):format(#log, date("%b %d %H:%M", log[1].t)))
  for _, label in ipairs(order) do
    local g = groups[label]
    print(("  |cffffffff%s|r: %d items"):format(label, g.n))
    local expected = {}
    for _, y in ipairs(g.yield or {}) do expected[y[1]] = y[2] end
    local seen = {}
    local function line(m)
      local got = g.mats[m] or 0
      local exp = expected[m]
      print(("      %s: %d (%.2f each%s)"):format(ns:DisenchantMaterialName(m), got, got / g.n,
        exp and (", table says %.2f"):format(exp) or ""))
      seen[m] = true
    end
    for _, y in ipairs(g.yield or {}) do line(y[1]) end
    for m in pairs(g.mats) do if not seen[m] then line(m) end end
  end
end
