local _, ns = ...

---------------------------------------------------------------------------
-- Moving the auction house window (Frank, November 25: friends asked). Drag Blizzard's
-- window by its top edge; each character keeps its own spot (ns.db.ahPos[charKey] =
-- { point, relativePoint, x, y }, schema 13), put back each time the game places its
-- windows (opening the auction house, and again when bags or the character window open:
-- UpdateUIPanelPositions). Right-click the top edge: back where the game puts it. Our tabs
-- and the panel beside the window are attached to it, so they move with it.
-- Settings, Auction house, "Let me move the auction house window" (ahMove). A window
-- mover (BlizzMove, MoveAny) does this instead: it's turned off once when one is found
-- (Help.lua ns.OVERLAPS).
---------------------------------------------------------------------------

local handle
local gamePoint   -- where the game last put the window, for putting it back

local function on() return ns.db and ns.db.settings.ahMove ~= false end
local function saved() return ns.db and ns.db.ahPos and ns.db.ahPos[ns.CharKey()] end
local function busy() return InCombatLockdown and InCombatLockdown() end

-- Where the game has just put the window (it places it as it opens, and again as other
-- windows open), before the saved spot goes over it. Noted every time, shown or not, unless
-- the window is still at the saved spot (the game didn't move it): Codex review, November
-- 25: a new place the game chose while it was closed was missed, so right-click put it back
-- at the old one.
local function noteGamePoint()
  local f = AuctionHouseFrame
  local p = f and { f:GetPoint(1) }
  if not (p and p[1]) then return end
  local s = saved()
  if s and p[1] == s[1] and p[3] == s[2] and math.floor((p[4] or 0) + 0.5) == s[3]
    and math.floor((p[5] or 0) + 0.5) == s[4] then return end
  gamePoint = p
end

-- The saved spot, if there is one and moving is on.
local function apply()
  local f = AuctionHouseFrame
  if not (f and f:IsShown()) or busy() then return end
  local s = on() and saved()
  if not s then return end
  f:ClearAllPoints()
  f:SetPoint(s[1], UIParent, s[2], s[3], s[4])
end
ns.ApplyAHPosition = apply   -- (tests)

-- Where the game puts it (the saved spot stays unless forget).
local function gameSpot(forget)
  local f = AuctionHouseFrame
  if forget and ns.db.ahPos then ns.db.ahPos[ns.CharKey()] = nil end
  if f and gamePoint and not busy() then
    f:ClearAllPoints()
    f:SetPoint(unpack(gamePoint))
  elseif forget then
    ns:Print("The auction house window goes back to its usual place the next time it opens.")
  end
end

local function make()
  local f = AuctionHouseFrame
  if handle or not (f and f.SetMovable) then return end
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  -- The top edge, between the portrait and the close button.
  handle = CreateFrame("Frame", nil, f)
  handle:SetPoint("TOPLEFT", f, "TOPLEFT", 60, 0)
  handle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, 0)
  handle:SetHeight(22)
  handle:SetFrameLevel(f:GetFrameLevel() + 20)
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  handle:SetScript("OnDragStart", function()
    if not on() or busy() then return end
    if not saved() then noteGamePoint() end
    f:StartMoving()
  end)
  handle:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    -- (Kept by us, per character, not in the game's own layout file.)
    if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
    local point, _, relativePoint, x, y = f:GetPoint(1)
    if not point then return end
    ns.db.ahPos = ns.db.ahPos or {}
    ns.db.ahPos[ns.CharKey()] = { point, relativePoint, math.floor(x + 0.5), math.floor(y + 0.5) }
  end)
  handle:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and on() and saved() then gameSpot(true) end
  end)
  handle:SetScript("OnEnter", function(self)
    if not on() then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ns:TooltipAddLine("Drag to move the auction house window", 1, 1, 1)
    if saved() then ns:TooltipAddLine("Right-click: put it back", 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:HookScript("OnShow", function() C_Timer.After(0, apply) end)
  -- After the game places its windows (opening one goes through the public
  -- UpdateUIPanelPositions too, Codex review, November 25): the game's own spot noted,
  -- then ours.
  local function placed()
    noteGamePoint()
    apply()
  end
  if UpdateUIPanelPositions then hooksecurefunc("UpdateUIPanelPositions", placed) end
end

-- A frame later: Blizzard loads its auction house window the first time it opens, maybe
-- after this event reaches us. Then the window is still where the game put it.
local function setUp()
  make()
  if not handle then return end
  handle:SetShown(on())
  noteGamePoint()
  apply()
end
ns.SetUpAHMove = setUp   -- (tests)
ns:On("AUCTION_HOUSE_SHOW", function() C_Timer.After(0, setUp) end)

-- Settings: turned on or off while the window is open (off: where the game puts it; the
-- saved spot is kept for turning it on again).
function ns:ApplyAHMove()
  if handle then handle:SetShown(on()) end
  if on() then apply() elseif saved() then gameSpot(false) end
end
