local _, ns = ...

---------------------------------------------------------------------------
-- The cheapest way to get a number of items, buying or making each one (redesign,
-- Frank's comment on the Gold making mockup, November 15: a Felblood Soul Bag needs 4
-- Bolts of Runecloth: buy the few cheap bolts listed, make the rest from Runecloth, and
-- never count both the bolts and the cloth). Pure, for the tests; Gold making and
-- shopping lists will call it.
--
-- Each unit is filled from whichever is cheapest next:
--   made already  a unit left over from a batch made earlier in the plan (paid for)
--   your bags     at what they'd sell for (opts.ownedFree: at no cost)
--   the AH        the next listing on its price ladder (cheapest first; each used once)
--   a vendor      its price, as many as wanted
--   a craft       one more batch, tried out first on a copy of the plan so far: its
--                 materials come from the same listings, bags and leftovers the rest of
--                 the plan uses (never the same cheap listing twice), and the whole batch
--                 is paid for, shared over the units still needed (Codex review, November
--                 15: one needed, 20c on the AH, a batch of 10 for 100c must buy)
-- so a thin cheap end on the auction house is used, then making takes over when that
-- gets dearer. Every unit is counted once, bought or made, never both.
-- When buying the next unit is cheaper than a batch but a batch could be made, the rest of
-- what's needed is worked out both ways (buy this one, or make a batch now) and the cheaper
-- whole is kept (Codex review, November 15: a 49c bolt then 10s ones, against a batch of 2
-- for 1s). Inside that look ahead the plan is filled unit by unit, so it stays quick.
--
-- sourceOf(id) returns { ladder = { { price, count }, ... } (cheapest first) or nil,
--   vendor = copper each or nil, recipe = { makes = n, mats = { { id, qty }, ... } } or
--   nil, owned = count in your bags or nil, ownedValue = copper each or nil }.
-- need = { [id] = units }. Returns total copper (nil if something can't be had) and the
-- plan: { [id] = { owned = n, bought = n, boughtCost = c, vendor = n, vendorCost = c,
--   made = n, top = highest AH price paid } }.
---------------------------------------------------------------------------
local MAX_DEPTH = 4
local EMPTY = {}

function ns.CraftPlan(need, sourceOf, opts)
  opts = opts or {}
  local cache = {}
  local function src(id)
    local s = cache[id]
    if s == nil then
      s = sourceOf(id) or {}
      cache[id] = s
    end
    return s
  end

  -- The plan so far, in one set of tables: where each item's ladder is up to (level, used),
  -- bags left, units made and not yet used, and the plan's counts. A try (a craft tried
  -- out, or the rest worked out both ways) runs on the same tables and is put back
  -- afterwards from a log of what it changed (Frank's seventeenth /fl perf, November 22:
  -- copying the plan for every try left about 1.3 MB per writ order, 187 MB a Writs run).
  -- Inside a try the plan's counts aren't kept: only the copper matters there.
  local level, used, owned, left, plan = {}, {}, {}, {}, {}
  local logT, logK, logV, logN = {}, {}, {}, 0
  local trying = 0
  local function set(t, k, v)
    if trying > 0 then
      logN = logN + 1
      logT[logN], logK[logN], logV[logN] = t, k, t[k]
    end
    t[k] = v
  end
  local function try() trying = trying + 1; return logN end
  local function putBack(mark)
    for i = logN, mark + 1, -1 do logT[i][logK[i]] = logV[i] end
    logN, trying = mark, trying - 1
  end
  local function ownedOf(id)
    -- (Not logged: a try that fills it in fills in what anyone would.)
    if owned[id] == nil then owned[id] = src(id).owned or 0 end
    return owned[id]
  end
  local function entry(id)
    plan[id] = plan[id] or { owned = 0, bought = 0, boughtCost = 0, vendor = 0, vendorCost = 0, made = 0 }
    return plan[id]
  end
  -- The next AH listing's price (its place on the ladder moves past used-up levels).
  local function nextListing(id)
    local ladder = src(id).ladder
    if not ladder then return nil end
    local lv, u = level[id] or 1, used[id] or 0
    while ladder[lv] and u >= ladder[lv][2] do lv, u = lv + 1, 0 end
    if lv ~= (level[id] or 1) then set(level, id, lv); set(used, id, u) end
    return ladder[lv] and ladder[lv][1] or nil
  end

  local take
  -- One batch of id: its materials taken. The copper, or nil if they can't be had.
  local function makeBatch(id, depth, simple)
    local total = 0
    for _, m in ipairs(src(id).recipe.mats or EMPTY) do
      local c = take(m[1], m[2], depth + 1, simple)
      if not c then return nil end
      total = total + c
    end
    return total
  end
  -- What one batch of id would cost now, tried out and put back.
  local function tryBatch(id, depth)
    local mark = try()
    local c = makeBatch(id, depth, true)
    putBack(mark)
    return c
  end

  -- One unit of id the chosen way (how: "ah", "vendor" or "craft"). The copper.
  local function takeOne(id, how, depth, simple)
    local s = src(id)
    local e = trying == 0 and entry(id) or nil
    if how == "ah" then
      local listing = nextListing(id)
      set(used, id, (used[id] or 0) + 1)
      if e then
        e.bought, e.boughtCost = e.bought + 1, e.boughtCost + listing
        e.top = math.max(e.top or 0, listing)
      end
      return listing
    elseif how == "vendor" then
      if e then e.vendor, e.vendorCost = e.vendor + 1, e.vendorCost + s.vendor end
      return s.vendor
    end
    local makes = math.max(s.recipe.makes or 1, 1)
    local batch = makeBatch(id, depth, simple)
    if not batch then return nil end
    if e then e.made = e.made + makes end
    set(left, id, (left[id] or 0) + makes - 1)   -- this unit is one of them
    return batch
  end

  -- Takes n units of id, cheapest first. The copper, or nil if they can't be had.
  -- simple: no looking ahead (used inside a look ahead, so it stays quick).
  take = function(id, n, depth, simple)
    local s = src(id)
    local e = trying == 0 and entry(id) or nil
    local total = 0
    for i = 1, n do
      -- opts.yield: a sliced run's caller (the Writs view's costs) gets frames back between
      -- units (Frank's sixteenth /fl perf, November 21: one order, 128 ms). Only when asked:
      -- a caller inside pcall (a tier's average) can't give a frame back in Lua 5.1.
      if opts.yield and ns.MaybeYield then ns.MaybeYield() end
      if (left[id] or 0) > 0 then
        set(left, id, left[id] - 1)   -- made earlier in the plan, paid for then
      elseif ownedOf(id) > 0 then
        set(owned, id, owned[id] - 1)
        if e then e.owned = e.owned + 1 end
        total = total + (opts.ownedFree and 0 or (s.ownedValue or 0))
      else
        local listing = nextListing(id)
        local best, how = listing, "ah"
        if s.vendor and (not best or s.vendor < best) then best, how = s.vendor, "vendor" end
        local makes = s.recipe and math.max(s.recipe.makes or 1, 1)
        local canMake = false
        if s.recipe and depth < MAX_DEPTH then
          local batch = tryBatch(id, depth)
          if batch then
            canMake = true
            -- The whole batch, over the units still needed here (a leftover may be wasted).
            local each = batch / math.min(makes, n - i + 1)
            if not best or each < best then best, how = each, "craft" end
          end
        end
        if not best then return nil end
        -- Buying this one looks cheaper, but a batch now may fill the rest for less (Codex
        -- review, November 15: need 2, one listed at 49c then 10s, a batch of 2 for 1s:
        -- buying the 49c one, then making a whole batch for the other, came to 1s 49c).
        -- So the rest of what's needed is worked out both ways and the cheaper kept.
        if not simple and canMake and how ~= "craft" and n - i >= 1 then
          local ahead = math.min(n - i, math.max(2 * makes, 10))
          local mark = try()
          local ca = takeOne(id, how, depth, true)
          local ra = ca and take(id, ahead, depth, true)
          putBack(mark)
          mark = try()
          local cb = takeOne(id, "craft", depth, true)
          local rb = cb and take(id, ahead, depth, true)
          putBack(mark)
          if cb and rb and not (ca and ra and ca + ra <= cb + rb) then how = "craft" end
        end
        local c = takeOne(id, how, depth, simple)
        if not c then return nil end
        total = total + c
      end
    end
    return total
  end

  local total = 0
  for id, n in pairs(need) do
    local c = take(id, n, 0)
    if not c then return nil, plan end
    total = total + c
  end
  return math.floor(total + 0.5), plan
end
