-- AHMove.lua (Frank, November 25): the auction house window dragged by its top edge,
-- each character's spot kept and put back after the game places its windows.
local T = ...
local ns, S = T.ns, T.S

local GAME = { "TOPLEFT", "UIParent", "TOPLEFT", 16, -116 }

-- Blizzard's window, as far as moving it goes.
local function fakeAH()
  local f = S.dummy()
  f.pts = { { unpack(GAME) } }
  f.IsShown = function() return true end
  f.GetPoint = function(self, i) local p = self.pts[i or 1]; if p then return unpack(p) end end
  f.ClearAllPoints = function(self) self.pts = {} end
  f.SetPoint = function(self, a, rel, b, x, y) self.pts[#self.pts + 1] = { a, rel == UIParent and "UIParent" or rel, b, x, y } end
  f.SetMovable = function() end
  return f
end

T.test("Auction house window: dragged, kept per character, put back", function()
  local savedAH, savedUpdate = AuctionHouseFrame, UpdateUIPanelPositions
  local f = fakeAH()
  AuctionHouseFrame = f
  UpdateUIPanelPositions = function() f.pts = { { unpack(GAME) } } end   -- the game's own spot
  ns.db.ahPos, ns.db.settings.ahMove = {}, true
  local before = #S.frames
  ns.SetUpAHMove()
  local handle
  for i = before + 1, #S.frames do if S.frames[i].scripts.OnDragStart then handle = S.frames[i] end end
  T.ok(handle and handle.scripts.OnDragStart, "a handle on the top edge")
  -- Dragged somewhere else: kept under this character.
  handle.scripts.OnDragStart(handle)
  f.pts = { { "TOPLEFT", "UIParent", "BOTTOMLEFT", 300.4, 700.6 } }
  handle.scripts.OnDragStop(handle)
  T.same(ns.db.ahPos[ns.CharKey()], { "TOPLEFT", "BOTTOMLEFT", 300, 701 })
  -- The game places its windows again (bags opened): ours goes back on.
  UpdateUIPanelPositions()
  T.same(f.pts[1], { "TOPLEFT", "UIParent", "BOTTOMLEFT", 300, 701 })
  -- Turned off: where the game puts it, the spot kept; on again: back to the spot.
  ns.db.settings.ahMove = false
  ns:ApplyAHMove()
  T.same(f.pts[1], GAME)
  T.ok(ns.db.ahPos[ns.CharKey()], "kept for later")
  ns.db.settings.ahMove = true
  ns:ApplyAHMove()
  T.eq(f.pts[1][4], 300)
  -- Another character's spot isn't this one's.
  ns.db.ahPos = { ["Some Alt-PvE"] = { "CENTER", "CENTER", 0, 0 } }
  UpdateUIPanelPositions()
  T.same(f.pts[1], GAME)
  -- Right-click the top edge: forgotten, back where the game puts it.
  ns.db.ahPos[ns.CharKey()] = { "TOPLEFT", "BOTTOMLEFT", 50, 60 }
  ns:ApplyAHPosition()
  T.eq(f.pts[1][4], 50)
  handle.scripts.OnMouseUp(handle, "RightButton")
  T.eq(ns.db.ahPos[ns.CharKey()], nil)
  T.same(f.pts[1], GAME)
  -- Codex review, November 25: the game picked a new place while the window was closed;
  -- the next opening notes it, so right-click puts it there, not at the old one.
  ns.db.ahPos[ns.CharKey()] = { "TOPLEFT", "BOTTOMLEFT", 50, 60 }
  f.pts = { { "TOPLEFT", "UIParent", "TOPLEFT", 150, -180 } }
  ns.SetUpAHMove()
  T.eq(f.pts[1][4], 50, "opened at the saved spot")
  ns.SetUpAHMove()   -- (again, already at the saved spot: that isn't the game's)
  handle.scripts.OnMouseUp(handle, "RightButton")
  T.same(f.pts[1], { "TOPLEFT", "UIParent", "TOPLEFT", 150, -180 })
  AuctionHouseFrame, UpdateUIPanelPositions = savedAH, savedUpdate
  ns.db.ahPos = {}
end)
