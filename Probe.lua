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

function ns:Probe()
  ns:Print("Probe: what the game gives us for crafting ads, trades, Merchant's Favor and crates.")
  probeFavor()
  probeChat()
  probeCrates()
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
