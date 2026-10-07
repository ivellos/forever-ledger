local _, ns = ...

-- Planning reserve: one failed 8-hour listing, then a successful sale. The latter's
-- deposit is refunded; this is risk allowance, not an extra fee on a successful sale.
-- API reference: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua
-- CalculateCommodityDeposit(itemID, duration, quantity) -> copper.
-- CalculateItemDeposit(itemLocation, duration, quantity) -> copper; requires owned ItemLocation.
-- Duration indices 1/2/3 = 2/8/24 hours in Forever (Classic's; owner's Sell tab, October 7:
-- "2 Hours" deposit 12c, and the API's index 2 gave 48c, four times as much). Retail's are 12/24/48.
-- Forever's amounts still need a game check. Per-unit estimates may exceed one stack
-- quote because of rounding; we use live quotes only at the matching open auction house.
ns.DEPOSIT_DURATION = 2 -- 1/2/3 = 2/8/24 hours

-- Classic's formula, which matches Forever (owner's test, October 7: Small Green Pouch,
-- vendor 2s 50c: 12c for 2 hours, 48c for 8): 5% of the vendor price per 2 hours (25% at a
-- neutral auction house), rounded down, times 1, 4 or 12 for 2, 8 or 24 hours.
local DURATION_HOURS, DURATION_TIMES = { 2, 8, 24 }, { 1, 4, 12 }
function ns:DepositEstimate(vendor, duration, quantity, neutral)
  if type(vendor) ~= "number" or vendor < 0 or vendor ~= vendor or vendor == math.huge then return end
  local times = DURATION_TIMES[duration]
  if not times or type(quantity) ~= "number" or quantity < 1 or quantity == math.huge or quantity ~= math.floor(quantity) then return end
  return math.floor(vendor * quantity * (neutral and 25 or 5) / 100) * times
end

local locations
local function bagLocation(id)
  if not locations then
    locations = {}
    local C = C_Container
    if C and C.GetContainerNumSlots and C.GetContainerItemInfo and ItemLocation and ItemLocation.CreateFromBagAndSlot then
      pcall(function()
        for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or (NUM_BAG_SLOTS or 4) + 1) do
          for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not locations[info.itemID] then
              locations[info.itemID] = ItemLocation:CreateFromBagAndSlot(bag, slot)
            end
          end
        end
      end)
    end
  end
  return locations[id]
end
local function clear()
  locations = nil
  ns.depositRevision = (ns.depositRevision or 0) + 1
  if ns.InvalidateValues then ns:InvalidateValues(true) end
end
ns:On("BAG_UPDATE_DELAYED", function()
  locations = nil
  if ns.InvalidateValues then ns:InvalidateValues() end
end)
ns:On("AUCTION_HOUSE_SHOW", clear)
ns:On("AUCTION_HOUSE_CLOSED", clear)

-- Only ask the live API about the auction house currently open. Never reuse a live
-- faction quote for Booty Bay, or guess that stackable means commodity.
function ns:AuctionDeposit(id, quantity, duration, neutral)
  quantity, duration = quantity or 1, duration or ns.DEPOSIT_DURATION
  if type(id) ~= "number" or id < 1 or type(quantity) ~= "number" or quantity < 1 or quantity == math.huge or quantity ~= math.floor(quantity) or not ({ [1] = true, [2] = true, [3] = true })[duration] then return nil, "invalid request" end
  if neutral == nil then neutral = not not ns.neutralAH end
  local AH = C_AuctionHouse
  if AH and ns.IsAHOpen and ns:IsAHOpen() and neutral == (not not ns.neutralAH) then
    local ok, info = pcall(function()
      return AH.GetItemKeyInfo and AH.GetItemKeyInfo({ itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    end)
    if ok and info and type(info.isCommodity) == "boolean" then
      local fn, arg, source
      if info.isCommodity then
        fn, arg, source = AH.CalculateCommodityDeposit, id, "commodity API"
      else
        fn, arg, source = AH.CalculateItemDeposit, bagLocation(id), "item API"
      end
      if fn and arg then
        local success, amount = pcall(fn, arg, duration, quantity)
        if success and type(amount) == "number" and amount >= 0 and amount < math.huge and amount == math.floor(amount) then
          return amount, source
        end
      end
    end
  end
  local vendor = ns:GetSellPrice(id)
  local estimate = ns:DepositEstimate(vendor or 0, duration, quantity, neutral)
  return estimate or 0, vendor and "Classic estimate" or "no vendor price: estimate 0"
end

function ns:AuctionSaleValue(id, price, neutral)
  local deposit, source = ns:AuctionDeposit(id, 1, nil, neutral)
  return ns:AfterCut(price, neutral) - deposit, deposit, source
end

function ns:DepositReport(id, quantity, duration)
  quantity, duration = quantity or 1, duration or ns.DEPOSIT_DURATION
  local amount, source = ns:AuctionDeposit(id, quantity, duration)
  if not amount then ns:Print("Use /fl deposit <item ID or shift-clicked item> [quantity] [2/8/24 hours]."); return end
  local hours = DURATION_HOURS[duration]
  local estimate = ns:DepositEstimate(ns:GetSellPrice(id) or 0, duration, quantity, ns.neutralAH)
  ns:Print(("Deposit: item %d, quantity %d, %d hours: %s (%s); Classic estimate %s. Values allow for one unsold 8-hour listing."):format(id, quantity, hours, ns.Money(amount), source, ns.Money(estimate)))
end

-- Reserve carried by one input unit of a route, including multi-output crafts and DE.
-- Already subtracted by the terminal AH option: reporting only, never subtract again.
function ns:OptionDeposit(o)
  if o.kind == "ah" then return o.deposit or 0 end
  if o.kind == "craft" then return (o.rec.oq or 1) * ns:OptionDeposit(o.next) / o.units end
  if o.kind == "convert" then return o.per * ns:OptionDeposit(o.next) end
  if o.kind == "disenchant" then
    local total = 0
    for _, m in ipairs(o.mats) do total = total + m.count * ns:OptionDeposit(m.opt) end
    return total
  end
  return 0
end
