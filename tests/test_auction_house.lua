local T = ...
local ns, S = T.ns, T.S

T.test("Auction house: the buy note sits on the item box, clear of the list's column header", function()
  local savedTheme, savedAH = ns.Theme, AuctionHouseFrame
  local function widget()
    local o = S.dummy(); local index = getmetatable(o).__index
    setmetatable(o, { __index = function(self, key)
      if key:match("^[a-z]") then return nil end
      return index(self, key)
    end })
    return o
  end
  local notes = {}
  local ok, err = pcall(function()
    local theme = { accent = { 1, 1, 1 } }
    function theme:Text(parent)
      local n = widget(); n.parent, n.points = parent, {}
      n.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
      notes[#notes + 1] = n
      return n
    end
    ns.Theme = theme
    assert(loadfile("AuctionHouse.lua"))("ForeverLedger", ns)
    local page = widget()
    page.ItemList, page.ItemDisplay = widget(), widget()
    page.ItemDisplay.ItemButton = widget()
    AuctionHouseFrame = { ItemBuyFrame = page }
    ns:SetUpAuctionHighlights()
    T.eq(#notes, 1, "one note")
    T.eq(notes[1].parent, page.ItemDisplay, "on the item box")
    T.ok(#notes[1].points > 0, "placed")
    for _, p in ipairs(notes[1].points) do T.ok(p[2] ~= page.ItemList, "not against the list") end
  end)
  ns.Theme, AuctionHouseFrame = savedTheme, savedAH
  assert(ok, err)
end)

T.test("Auction house: the commodity buy note sits under the Buy button, clear of the search bar", function()
  local savedTheme, savedAH = ns.Theme, AuctionHouseFrame
  local function widget()
    local o = S.dummy(); local index = getmetatable(o).__index
    setmetatable(o, { __index = function(self, key)
      if key:match("^[a-z]") then return nil end
      return index(self, key)
    end })
    return o
  end
  local notes = {}
  local ok, err = pcall(function()
    local theme = { accent = { 1, 1, 1 } }
    function theme:Text(parent)
      local n = widget(); n.parent, n.points = parent, {}
      n.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
      notes[#notes + 1] = n
      return n
    end
    ns.Theme = theme
    assert(loadfile("AuctionHouse.lua"))("ForeverLedger", ns)
    local page = widget()
    page.ItemList, page.BuyDisplay, page.ItemDisplay = widget(), widget(), false
    AuctionHouseFrame = { CommoditiesBuyFrame = page }
    ns:SetUpAuctionHighlights()
    T.eq(#notes, 1, "one note")
    T.eq(notes[1].parent, page.BuyDisplay, "on the buy panel")
    T.eq(#notes[1].points, 2, "as wide as the panel")
    for _, p in ipairs(notes[1].points) do T.eq(p[2], page.BuyDisplay, "against the panel") end
  end)
  ns.Theme, AuctionHouseFrame = savedTheme, savedAH
  assert(ok, err)
end)
