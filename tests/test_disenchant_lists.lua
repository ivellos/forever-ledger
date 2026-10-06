-- The finder-to-list handoff must keep the DE route, not a better vendor/craft route.
local T = ...
local ns, S = T.ns, T.S
local A, B, C, W = 89501, 89502, 89503, 89504
local DUST, ESSENCE = 10940, 10939
local function price(id, p)
  ns.db.prices[ns.MarketKey()] = ns.db.prices[ns.MarketKey()] or {}
  ns.db.prices[ns.MarketKey()][id] = { m = p, a = p, q = 50, t = S.now }
end
local function fresh()
  T.resetDB()
  S.items[A] = { name = "Green vest", quality = 2, ilvl = 18, classID = 4, equipLoc = "INVTYPE_CHEST" }
  S.items[B] = { name = "Green boots", quality = 2, ilvl = 22, classID = 4, equipLoc = "INVTYPE_FEET" }
  S.items[C] = { name = "Other band", quality = 2, ilvl = 33, classID = 4, equipLoc = "INVTYPE_HAND" }
  S.items[W] = { name = "Green sword", quality = 2, ilvl = 18, classID = 2, equipLoc = "INVTYPE_WEAPON" }
  ns.db.chars = { [ns.CharKey()] = { name = "Tester", realm = "Testrealm", faction = "Alliance", profs = { Enchanting = { rank = 300 } } } }
  ns.db.settings.deFinder = { bands = { [20] = true }, armor = true, weapon = false, profitable = true }
  ns.db.settings.margin = 10
  price(A, 10); price(B, 10); price(C, 10); price(W, 10)
  price(DUST, 100); price(ESSENCE, 200)
  ns:InvalidateValues(true)
end
local function rows() return ns:DisenchantFinderItems() end
T.test("Finder rows obey band, armor/weapon and profitability filters", function()
  fresh()
  local found = rows(); T.eq(#found, 1); T.eq(found[1].id, A)
  T.eq(found[1].max, (ns:DisenchantBuyLimit(A)))
  ns.db.settings.deFinder.armor = false; ns.db.settings.deFinder.weapon = true
  found = rows(); T.eq(#found, 1); T.eq(found[1].id, W)
  price(W, 100000); found = rows(); T.eq(#found, 0)
  ns.db.settings.deFinder.profitable = false; found = rows(); T.eq(#found, 1)
  ns.db.settings.deFinder.bands = {}; T.eq(#rows(), 0)
end)
T.test("DE limit is floored DE value minus safety margin, never vendor value", function()
  fresh(); ns.db.vendorSell[A] = 5000; ns:InvalidateValues(true)
  local cap, worth = ns:DisenchantBuyLimit(A)
  T.eq(cap, math.floor(worth * .9)); T.ok(cap < 5000)
  local list = assert(ns:DisenchantToShoppingList(rows(), nil, ns:DisenchantFinderListName()))
  T.eq(list.items[1].max, cap); T.eq(list.items[1].src, "disenchant")
  T.eq(list.items[1].disenchant.band, 20); T.eq(list.items[1].disenchant.kind, "armor")
  T.eq(list.items[1].suffix, nil, "finder buys any stat version")
  T.eq(list.items[1].qty, 1); T.eq(list.on, false)
  T.ok(list.name:find("16-20 armor", 1, true))
  T.ok(ns:ListPriceSourceText(list, list.items[1]):find("From disenchanting", 1, true))
end)
T.test("Filter names describe multiple bands; duplicate new lists get numbers", function()
  fresh(); ns.db.settings.deFinder.bands[25] = true
  local name = ns:DisenchantFinderListName(); T.ok(name:find("16-20, 21-25", 1, true))
  local a = assert(ns:DisenchantToShoppingList({ { id = A } }, nil, name))
  local b = assert(ns:DisenchantToShoppingList({ { id = A } }, nil, name))
  T.eq(b.name, a.name .. " (2)")
end)
T.test("Adding rows keeps buying, typed prices, progress and distinct suffix entries", function()
  fresh(); local list = ns:NewShoppingList("Existing"); list.on = true
  local e = ns:AddToShoppingList(list, A, 42, 3); e.bought, e.done = 3, true
  local version = ns:AddToShoppingList(list, A, 50, 2, "of the Monkey")
  assert(ns:DisenchantToShoppingList({ { id = A }, { id = A } }, list))
  T.eq(e.qty, 4, "duplicate input row counted once"); T.eq(e.bought, 3); T.eq(e.done, nil)
  T.eq(e.max, 42); T.eq(e.src, "you"); T.ok(e.disenchant)
  T.eq(list.on, true); T.eq(version.qty, 2); T.eq(version.max, 50)
end)
T.test("Buy again refreshes the DE source without the usual-price allowance", function()
  fresh(); local list = assert(ns:DisenchantToShoppingList((rows())))
  local e = list.items[1]; local old = e.max; list.allowance = 100
  price(DUST, 300); ns:BuyListAgain(list)
  T.eq(e.max, (ns:DisenchantBuyLimit(A))); T.ok(e.max > old); T.eq(e.src, "disenchant")
  ns.db.settings.margin = 25; ns:BuyListAgain(list)
  local _, worth = ns:DisenchantBuyLimit(A); T.eq(e.max, math.floor(worth * .75))
  T.eq(list.allowance, 100)
end)
T.test("Typed prices survive refresh and addition, including off/any/same", function()
  for _, value in ipairs({ 1, 999999, 0, -1 }) do
    fresh(); local list = assert(ns:DisenchantToShoppingList((rows()))); local e = list.items[1]
    ns:SetListItemPrice(e, value); price(DUST, 250); ns:BuyListAgain(list)
    assert(ns:DisenchantToShoppingList({ { id = A } }, list))
    T.eq(e.max, value); T.eq(e.src, "you")
    T.ok(ns:ListPriceSourceText(list, e):find("Automatic: disenchant", 1, true))
    local qty = e.qty; e.bought = 1
    ns:UseAutomaticListItemPrice(list, e)
    T.eq(e.src, "disenchant"); T.eq(e.max, (ns:DisenchantBuyLimit(A)))
    T.eq(e.qty, qty); T.eq(e.bought, 1); T.eq(e.offSet, nil)
  end
end)
T.test("Missing DE route turns automatic off and never falls back to usual", function()
  fresh(); local list = assert(ns:DisenchantToShoppingList((rows()))); local e = list.items[1]
  ns.db.chars = {}; ns:BuyListAgain(list)
  T.eq(e.max, 0); T.eq(e.src, "disenchant"); T.eq(ns:ItemLimit(e, list), nil)
  ns:SetListItemPrice(e, 17); ns:UseAutomaticListItemPrice(list, e)
  T.eq(e.max, 0); T.eq(e.src, "disenchant")
end)
T.test("Saved DE source survives serialization and refreshes after reload", function()
  fresh(); local list = assert(ns:DisenchantToShoppingList((rows())))
  list = ns.Deserialize(ns.Serialize(list)); ns.db.shopping.lists = { list }
  price(DUST, 125); ns:BuyListAgain(list)
  T.eq(list.items[1].max, (ns:DisenchantBuyLimit(A))); T.eq(list.items[1].src, "disenchant")
  list.items[1].disenchant.band = 25
  ns:BuyListAgain(list); T.eq(list.items[1].max, 0, "a different saved yield band is not silently substituted")
end)
T.test("DE addition validates the whole batch before changing anything", function()
  fresh(); local list = ns:NewShoppingList("Existing"); local e = ns:AddToShoppingList(list, A, 20, 3)
  local before = ns.Serialize(list)
  local got = ns:DisenchantToShoppingList({ { id = A }, { id = 999999 } }, list)
  T.eq(got, nil); T.eq(ns.Serialize(list), before)
  local n = #ns:ShoppingLists(); got = ns:DisenchantToShoppingList({ { id = 999999 } })
  T.eq(got, nil); T.eq(#ns:ShoppingLists(), n)
  e.mode = "craft"; T.eq(ns:DisenchantToShoppingList({ { id = A } }, list), nil)
  for _, key in ipairs({ "countHave", "temp", "crateID", "anyPrice" }) do
    local bad = ns:NewShoppingList(key); bad[key] = true
    T.eq(ns:DisenchantToShoppingList({ { id = A } }, bad), nil)
  end
  T.eq(ns:DisenchantToShoppingList({ { id = A } }, { items = {} }), nil)
  T.eq(ns:DisenchantToShoppingList({}), nil)
end)
T.test("Two automatic routes keep the lower cap in either addition order", function()
  fresh(); local list = assert(ns:DisenchantToShoppingList((rows()))); local e = list.items[1]
  e.shuffles = { cheap = { id = A, name = "Cheaper route", cap = 1 } }
  local value, source = ns:AutomaticListItemPrice(list, e); T.eq(value, 1); T.eq(source, "shuffle")
  e.shuffles.cheap.cap = 999999
  value, source = ns:AutomaticListItemPrice(list, e); T.eq(value, e.disenchant.cap); T.eq(source, "disenchant")
  ns:SetListItemPrice(e, 25); T.eq(e.max, 25); T.eq(e.src, "you")
end)
T.test("Schema 7 leaves existing typed and automatic entries intact", function()
  fresh(); ForeverLedgerDB = ns.Deserialize(ns.Serialize(ns.db)); ForeverLedgerDB.schema = 6
  ForeverLedgerDB.shopping.lists = { { name = "Old", on = true, items = { { id = A, src = "you", max = 15 }, { id = W, src = "usual", max = 40 } } } }
  T.fire("ADDON_LOADED", "ForeverLedger")
  T.eq(ns.db.schema, 7); T.eq(ns.db.shopping.lists[1].items[1].max, 15)
  T.eq(ns.db.shopping.lists[1].items[1].src, "you"); T.eq(ns.db.shopping.lists[1].items[2].src, "usual")
  T.eq(ns.db.shopping.lists[1].items[1].disenchant, nil)
end)

T.test("Actual shuffle and finder additions keep the lower automatic cap", function()
  fresh()
  local function shuffle(cap)
    return { id = A, key = "vendor", units = 1, single = true, maxBuy = cap,
      buys = { { id = A, qty = 1, price = 10 } }, opt = { kind = "vendor", id = A, value = 10000 } }
  end
  local list = assert(ns:DisenchantToShoppingList((rows())))
  local cap = list.items[1].max
  assert(ns:ShuffleToShoppingList(shuffle(cap + 1000), list, 1))
  T.eq(list.items[1].max, cap); T.eq(list.items[1].src, "disenchant")
  local other = assert(ns:ShuffleToShoppingList(shuffle(1), nil, 1))
  assert(ns:DisenchantToShoppingList({ { id = A } }, other))
  T.eq(other.items[1].max, 1); T.eq(other.items[1].src, "shuffle")
end)

T.test("Finder buttons use shown rows and the selected target; left click still searches", function()
  fresh()
  local savedFrame, savedTheme, savedSearch = CreateFrame, ns.Theme, ns.SearchAuctionHouse
  local function widget()
    local o = S.dummy(); local index = getmetatable(o).__index
    setmetatable(o, { __index = function(self, key)
      if key:match("^[a-z]") then return nil end
      return index(self, key)
    end })
    o.SetText = function(self, text) self.text = text end
    o.GetStringWidth = function(self) return #(self.text or "") * 5 end
    o.Show = function(self) self.shown = true end
    o.Hide = function(self) self.shown = false end
    o.IsShown = function(self) return self.shown or false end
    o.SetShown = function(self, on) self.shown = on end
    o.GetChecked = function(self) return self.checked end
    o.SetChecked = function(self, on) self.checked = on end
    return o
  end
  local ok, err = pcall(function()
    CreateFrame = function() return widget() end
    local theme = { accent = { 1, 1, 1 }, bg = {}, dim = {}, border = {} }
    function theme:Fill() return widget() end
    function theme:Border(f) f.borders = { widget() } end
    function theme:Text() return widget() end
    function theme:Check(_, fn) local c = widget(); c.label = widget(); c.scripts.OnClick = fn; return c end
    function theme:Button(_, text, _, fn) local b = widget(); b.text = text; b.scripts.OnClick = fn; return b end
    function theme:Dropdown(_, _, fn)
      local d = widget(); d.changed = fn
      d.SetOptions = function(self, options) self.options = options end
      d.SetValue = function(self, v) self.value = v end
      return d
    end
    theme.MultiDropdown = theme.Dropdown
    function theme:Scroll() local f = widget(); f.UpdateScrollBar = function() end; return f, widget() end
    ns.Theme = theme
    assert(loadfile("AuctionHouse.lua"))("ForeverLedger", ns)
    local f = ns:DisenchantFinderFrame(widget()); f:Show(); ns:RefreshDisenchantFinder()
    T.eq(#f.items, 1); T.eq(f.items[1].id, A)
    f.add.scripts.OnClick()
    local list = ns:CurrentShoppingList(); T.eq(#list.items, 1); T.eq(list.items[1].id, A)
    f.rows[1].scripts.OnClick(f.rows[1], "RightButton")
    T.eq(list.items[1].qty, 2); T.eq(#ns:ShoppingLists(), 1, "right click uses selected list")
    local searched
    ns.SearchAuctionHouse = function(_, id) searched = id end
    f.rows[1].scripts.OnClick(f.rows[1], "LeftButton"); T.eq(searched, A)
    ns.db.settings.deFinder.bands = { [25] = true }; ns:RefreshDisenchantFinder()
    T.eq(f.items[1].id, B); f.add.scripts.OnClick(); T.eq(list.items[2].id, B)
    f.pick.changed("new"); f.rows[1].scripts.OnClick(f.rows[1], "RightButton")
    T.eq(#ns:ShoppingLists(), 2); T.eq(ns:CurrentShoppingList().items[1].id, B)
  end)
  CreateFrame, ns.Theme, ns.SearchAuctionHouse = savedFrame, savedTheme, savedSearch
  assert(ok, err)
end)
