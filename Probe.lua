local _, ns = ...

---------------------------------------------------------------------------
-- /fl probe: reports what the game gives us for features planned after the beta
-- (crafting ads, work log, Merchant's Favor, Waylaid Crates). Read-only: it only
-- prints what it finds. After running, it also reports the next trade and the next
-- vendor window that sells something for a currency.
---------------------------------------------------------------------------
local FAVOR = 3402
local armed = { trade = false, merchant = false }

local function say(fmt, ...) print(("  " .. fmt):format(...)) end
local function exists(path)
  local cur = _G
  for part in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return false end
    cur = cur[part]
  end
  return cur ~= nil
end

local function probeFavor()
  if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then say("Favor: C_CurrencyInfo.GetCurrencyInfo is missing."); return end
  local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, FAVOR)
  if ok and type(info) == "table" then
    say("Favor (currency %d): name \"%s\", you have %s, max %s.", FAVOR, tostring(info.name), tostring(info.quantity), tostring(info.maxQuantity))
  else
    say("Favor (currency %d): nothing returned.", FAVOR)
  end
end

local function probeChat()
  -- GetChannelList came back empty in Forever; ask for each channel number instead.
  local names = {}
  for i = 1, 20 do
    local id, name = GetChannelName and GetChannelName(i)
    if id and id > 0 and name then names[#names + 1] = ("%d. %s"):format(id, name) end
  end
  say("Chat channels (GetChannelName): %s", #names > 0 and table.concat(names, ", ") or "none found")
  -- Two more ways, since Forever reported none the other ways.
  local shown = {}
  if GetNumDisplayChannels and GetChannelDisplayInfo then
    for i = 1, (GetNumDisplayChannels() or 0) do
      local name, header, _, number = GetChannelDisplayInfo(i)
      if name and not header then shown[#shown + 1] = ("%s. %s"):format(tostring(number), name) end
    end
  end
  say("Chat channels (channel list window): %s", #shown > 0 and table.concat(shown, ", ") or "none found")
  local server = {}
  if EnumerateServerChannels then
    for _, name in ipairs({ EnumerateServerChannels() }) do server[#server + 1] = tostring(name) end
  end
  say("Server channels: %s", #server > 0 and table.concat(server, ", ") or "none found")
  say("SendChatMessage: %s. C_TradeSkillUI.GetTradeSkillListLink: %s.",
    exists("SendChatMessage") and "yes" or "no", exists("C_TradeSkillUI.GetTradeSkillListLink") and "yes" or "no")
  if exists("C_TradeSkillUI.GetTradeSkillListLink") then
    local ok, link = pcall(C_TradeSkillUI.GetTradeSkillListLink)
    say("Profession link now: %s", ok and link and link:gsub("|", "||") or "none (open a profession window and probe again)")
  end
end

local function probeCrates()
  if not (C_Container and C_TooltipInfo and C_TooltipInfo.GetBagItem) then say("Crates: tooltip reading isn't available."); return end
  local found = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local name = info and info.itemID and ns.ItemName(info.itemID)
      if name and (name:find("Waylaid", 1, true) or name:find("Crate", 1, true) or name:find("Writ", 1, true)) then
        found = found + 1
        say("Bag item %d (%s), bag %d slot %d, tooltip:", info.itemID, name, bag, slot)
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        for _, line in ipairs(ok and data and data.lines or {}) do
          local l, r = line.leftText, line.rightText
          if l and l ~= "" then say("    %s%s", l, r and r ~= "" and ("  |  " .. r) or "") end
        end
      end
    end
  end
  if found == 0 then say("No Waylaid Crates or Writs in your bags. Put one in your bags and probe again.") end
end

-- Recipe book: are unlearned recipes listed, and do they say where they come from?
local function probeRecipes()
  local TS = C_TradeSkillUI
  local base = TS and TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
  local prof = type(base) == "table" and base.professionName
  if not (prof and TS.GetAllRecipeIDs) then say("Recipes: open a profession window and probe again."); return end
  -- Check every unlearned recipe; show examples that do have source text, grouped by
  -- the first word ("Vendor:", "Drop:", "Trainer:", …) so each kind is shown.
  local learned, unlearned, withText, kinds, examples = 0, 0, 0, {}, {}
  for _, id in ipairs(TS.GetAllRecipeIDs() or {}) do
    local ok, info = pcall(TS.GetRecipeInfo, id)
    if ok and info then
      if info.learned then learned = learned + 1 else
        unlearned = unlearned + 1
        local ok2, src = pcall(TS.GetRecipeSourceText or function() end, id)
        if ok2 and type(src) == "string" and src ~= "" then
          withText = withText + 1
          local clean = src:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " / "):gsub("\n", " / ")
          local kind = clean:match("^%s*([^:]+):") or "other"
          kinds[kind] = (kinds[kind] or 0) + 1
          if kinds[kind] <= 2 and #examples < 12 then examples[#examples + 1] = ("%s: %s"):format(tostring(info.name), clean) end
        end
      end
    end
  end
  say("Recipes in %s: %d learned, %d not learned, %d of those have source text. GetRecipeSourceText: %s.",
    prof, learned, unlearned, withText, TS.GetRecipeSourceText and "yes" or "no")
  local list = {}
  for k, n in pairs(kinds) do list[#list + 1] = ("%s %d"):format(k, n) end
  say("  Kinds of source: %s", #list > 0 and table.concat(list, ", ") or "none")
  for _, e in ipairs(examples) do say("  %s", e) end
  if unlearned == 0 then say("  None listed as not learned. Check whether the profession window has a filter hiding them.") end
end

-- Map pins, for "locate this vendor".
local function probeMap()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
  local x, y
  if pos and pos.GetXY then x, y = pos:GetXY() end
  local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  say("Map: %s (map %s) at %s, %s. Map pins: %s, pin tracking: %s.", tostring(info and info.name), tostring(mapID),
    x and ("%.1f"):format(x * 100) or "?", y and ("%.1f"):format(y * 100) or "?",
    exists("C_Map.SetUserWaypoint") and "yes" or "no", exists("C_SuperTrack.SetSuperTrackedUserWaypoint") and "yes" or "no")
end

---------------------------------------------------------------------------
-- Guard directions: ask a city guard for a trainer and the guard puts a flag on your
-- map. If the addon can read that flag, one conversation per city confirms where every
-- trainer stands. Always listening (cheap: only when a conversation adds a flag); each
-- flag is printed and saved in guardPOIs for checking.
---------------------------------------------------------------------------
local lastOption, lastNPC
local function probeGuards()
  say("Guard directions: map flag functions %s / %s; flag event %s. Ask a city guard for a profession trainer to test.",
    exists("C_GossipInfo.GetPoiForUiMapID") and "yes" or "no", exists("C_GossipInfo.GetPoiInfo") and "yes" or "no",
    ns.guardEventSeen and "seen" or "not seen yet")
end

-- Which option was picked ("Profession Trainer", then "Tailoring"). The options are
-- remembered when each page opens, since by the time the choice is reported the next
-- page may already have replaced them. Forever's gossip window may pick by ID or by
-- position, so both are watched. (Test 1: hooking SelectOption alone caught nothing.)
local pageOptions = {}
local function remember(match)
  for i, o in ipairs(pageOptions) do
    if match(o, i) then lastOption = o.name; return end
  end
end
if C_GossipInfo and hooksecurefunc then
  if C_GossipInfo.SelectOption then
    hooksecurefunc(C_GossipInfo, "SelectOption", function(optionID)
      remember(function(o) return o.gossipOptionID == optionID end)
    end)
  end
  if C_GossipInfo.SelectOptionByIndex then
    hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", function(index)
      remember(function(o, i) return o.orderIndex == index or i == index end)
    end)
  end
end
ns:On("GOSSIP_SHOW", function()
  local first, last = UnitName("npc")
  if first then lastNPC = (last and last ~= "") and (first .. " " .. last) or first end
  local ok, options = pcall(C_GossipInfo.GetOptions)
  pageOptions = ok and type(options) == "table" and options or {}
  -- One option on a page, e.g. the guard's follow-up: nothing to choose between.
  ns:Debug("Gossip page options:", #pageOptions)
end)

local lastFlag
local function readGuardFlag(event)
  if not (C_GossipInfo and C_GossipInfo.GetPoiForUiMapID and C_GossipInfo.GetPoiInfo and C_Map) then return end
  ns.guardEventSeen = ns.guardEventSeen or event
  -- The flag can be on the zone map or its parent (a city inside a zone).
  local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local info = mapID and C_Map.GetMapInfo(mapID)
  for _, m in ipairs({ mapID, info and info.parentMapID }) do
    local ok, poiID = pcall(C_GossipInfo.GetPoiForUiMapID, m)
    if ok and poiID then
      local ok2, poi = pcall(C_GossipInfo.GetPoiInfo, m, poiID)
      if ok2 and type(poi) == "table" then
        local x, y
        if poi.position and poi.position.GetXY then x, y = poi.position:GetXY() end
        local key = ("%s:%s:%s"):format(tostring(poi.name), tostring(x), tostring(y))
        if key ~= lastFlag then
          lastFlag = key
          local mapInfo = C_Map.GetMapInfo(m)
          ns:Print(("Guard flag (%s): \"%s\" at %s, %s on %s. You asked %s for \"%s\"."):format(event or "?",
            tostring(poi.name), x and ("%.1f"):format(x * 100) or "?", y and ("%.1f"):format(y * 100) or "?",
            mapInfo and mapInfo.name or tostring(m), lastNPC or "?", lastOption or "?"))
          local list = ns.db.guardPOIs or {}
          ns.db.guardPOIs = list
          list[#list + 1] = { name = poi.name, mapID = m, x = x, y = y, option = lastOption, npc = lastNPC, t = time() }
          while #list > 200 do table.remove(list, 1) end
        end
        return
      end
    end
  end
end
ns:On("DYNAMIC_GOSSIP_POI_UPDATED", function() readGuardFlag("DYNAMIC_GOSSIP_POI_UPDATED") end)
ns:On("GOSSIP_POI", function() readGuardFlag("GOSSIP_POI") end)   -- older name, in case
-- If neither event exists here, look right after each conversation step instead.
ns:On("GOSSIP_CLOSED", function() C_Timer.After(0.3, function() readGuardFlag("after the conversation") end) end)
ns:On("GOSSIP_SHOW", function() C_Timer.After(0.3, function() readGuardFlag("conversation page") end) end)

function ns:Probe()
  ns:Print("Probe: what the game gives us for crafting ads, trades, Merchant's Favor, crates and the recipe book.")
  probeFavor()
  probeChat()
  probeCrates()
  probeRecipes()
  probeMap()
  probeGuards()
  armed.trade, armed.merchant = true, true
  say("Waiting for your next trade and the next vendor that sells for a currency; those will be reported too.")
end

---------------------------------------------------------------------------
-- Next trade: everything both sides put in, gold, and the enchant slot (7)
---------------------------------------------------------------------------
local lastTrade
local function readTrade()
  local t = { me = {}, them = {} }
  for i = 1, 7 do
    if GetTradePlayerItemInfo then
      local name, _, qty, _, enchant = GetTradePlayerItemInfo(i)
      if name then t.me[#t.me + 1] = ("slot %d: %s x%s%s"):format(i, name, tostring(qty), enchant and (" enchant: " .. enchant) or "") end
    end
    if GetTradeTargetItemInfo then
      local name, _, qty, _, _, enchant = GetTradeTargetItemInfo(i)
      if name then t.them[#t.them + 1] = ("slot %d: %s x%s%s"):format(i, name, tostring(qty), enchant and (" enchant: " .. enchant) or "") end
    end
  end
  t.myMoney = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
  t.theirMoney = GetTargetTradeMoney and GetTargetTradeMoney() or 0
  -- Forever names are "First Last"; UnitName's second value is the last name.
  local first, last = UnitName("NPC")
  t.partner = (first and last and last ~= "" and (first .. " " .. last)) or first
    or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())
  return t
end

ns:On("TRADE_ACCEPT_UPDATE", function() if armed.trade then lastTrade = readTrade() end end)
ns:On("TRADE_PLAYER_ITEM_CHANGED", function() if armed.trade then lastTrade = readTrade() end end)
ns:On("TRADE_TARGET_ITEM_CHANGED", function() if armed.trade then lastTrade = readTrade() end end)
ns:On("TRADE_MONEY_CHANGED", function() if armed.trade then lastTrade = readTrade() end end)

ns:On("UI_INFO_MESSAGE", function(_, msg)
  if not armed.trade or not lastTrade then return end
  if msg ~= ERR_TRADE_COMPLETE and msg ~= ERR_TRADE_CANCELLED then return end
  local t = lastTrade
  lastTrade = nil
  -- Keep listening until a trade completes.
  if msg == ERR_TRADE_COMPLETE then armed.trade = false end
  ns:Print(("Probe: trade %s with %s."):format(msg == ERR_TRADE_COMPLETE and "completed" or "cancelled", tostring(t.partner)))
  say("You gave: %s; gold %s", #t.me > 0 and table.concat(t.me, "; ") or "nothing", ns.Money(t.myMoney))
  say("They gave: %s; gold %s", #t.them > 0 and table.concat(t.them, "; ") or "nothing", ns.Money(t.theirMoney))
end)

---------------------------------------------------------------------------
-- Next vendor with currency costs (the Favor vendors)
---------------------------------------------------------------------------
ns:On("MERCHANT_SHOW", function()
  if not armed.merchant then return end
  C_Timer.After(0.5, function()
    local n, shown = GetMerchantNumItems and GetMerchantNumItems() or 0, 0
    for i = 1, n do
      local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
      if info and info.hasExtendedCost and GetMerchantItemCostInfo then
        if shown == 0 then
          ns:Print(("Probe: this vendor (%s) sells for currencies:"):format(tostring(UnitName("NPC"))))
          armed.merchant = false
        end
        shown = shown + 1
        if shown <= 8 then
          local costs = {}
          for c = 1, (GetMerchantItemCostInfo(i) or 0) do
            local tex, value, link, currencyName = GetMerchantItemCostItem(i, c)
            costs[#costs + 1] = ("%s %s"):format(tostring(value), tostring(currencyName or (link and link:gsub("|", "||")) or tex))
          end
          say("%s: %s", tostring(info.name), table.concat(costs, " + "))
        end
      end
    end
    if shown > 8 then say("and %d more.", shown - 8) end
  end)
end)
