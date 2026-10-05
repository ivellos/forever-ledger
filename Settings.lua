local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- Settings tab (October 4 redesign, after EllesmereUI's options window; owner): a
-- sidebar with Global settings (the same for every character), Profiles, then the
-- feature groups, gold making first. A page can have tabs across the top for its parts.
-- Changes apply straight away. Search finds a setting on any page.
-- Global settings decide what prices, flips and deals are, so they're account-wide and
-- never in a profile; every other setting is in the character's profile (Core.lua:
-- ApplyCharSettings, ns.PER_CHAR_SETTINGS).
---------------------------------------------------------------------------
local function recalc() ns:InvalidateValues(true) end
local function ads() ns:UpdateCustomerAds() end

-- A setting: key, label, kind (check, number, money, choice), help; numbers have min,
-- max and suffix, money a plainUnit, choices their options; after runs after a change.
-- A label starting with spaces is a sub-option of the one above it. { sub = "..." } is
-- a small heading.
local PAGES = {
  { key = "global", title = "Global settings", icon = "Interface\\AddOns\\ForeverLedger\\media\\icons\\global",
    desc = "The same for every character and profile: they decide what items are worth and what counts as a flip or a deal.",
    tabs = {
      { name = "Prices", rows = {
        { sub = "How items are valued" },
        { key = "ahCut", label = "Auction house cut", kind = "number", suffix = "%", min = 0, max = 99, after = recalc,
          help = "Taken off every auction house sale in values and shuffles, at your faction's auction house. Neutral ones (Booty Bay, Gadgetzan, Everlook) take 15%, counted by themselves." },
        { key = "margin", label = "Safety margin", kind = "number", suffix = "%", min = 0, max = 99,
          help = "Shuffles and \"buy at or below\" keep this much below an item's worth." },
        { key = "actionSeconds", label = "Seconds per craft", kind = "number", suffix = "seconds", min = 1, max = 60,
          help = "Used for the rough profit per hour." },
        { key = "source", label = "Auction house prices from", kind = "choice", after = recalc, options = {
            { "auto", "Auto" }, { "own", "My scans" }, { "Auctionator", "Auctionator" }, { "TSM", "TSM" }, { "Auctioneer", "Auctioneer" } },
          help = "Auto uses your own scans while they're fresh, then other auction addons." },
      } },
      { name = "Flips and deals", rules = true, rows = {
        { sub = "Vendor flips" },
        { key = "dealVendorPct", label = "Least profit, share of price", kind = "number", suffix = "% of vendor price", min = 0, max = 99, after = recalc,
          help = "Selling to a vendor has no risk, only the effort of buying. 0 counts any listing below vendor price." },
        { key = "dealVendorMin", label = "Least profit each", kind = "money", after = recalc,
          help = "For example 10c or 1s. \"off\" for no minimum. A flip needs both this and the share above." },
        { sub = "Deals" },
        { key = "dealUsualPct", label = "Below usual price by", kind = "number", suffix = "% or more", min = 1, max = 99 },
        { key = "dealWindow", label = "Usual price over", kind = "choice", options = {
            { "week", "Week" }, { "month", "Month" }, { "3months", "3 months" }, { "6months", "6 months" },
            { "year", "Year" }, { "all", "All time" } } },
        { key = "dealHistory", label = "Usual prices from", kind = "choice", options = {
            { "auto", "Auto" }, { "local", "My scans" }, { "tsm", "TSM" } },
          help = "Auto uses TSM's history where it has a price, otherwise your own scans." },
        { key = "dealUsualMin", label = "Least resale profit each", kind = "money",
          help = "Deals tab: profit after the auction house cut, reselling at the usual price or under the next listing. \"off\" for no minimum." },
      } },
      { name = "Advanced", rows = {
        { sub = "Sync with your other account" },
        { key = "syncBags", label = "Share bags and bank with your sync partner", kind = "check",
          after = function() if ns.SyncSend then ns:SyncSend(true) end end,
          help = "Sends what your characters carry and keep in the bank to the character you paired with (/fl pair), so it counts in Have, shopping lists and the Characters tab there. Only for your own second account: off by default. /fl unpair removes what you got from them." },
        { sub = "Testing" },
        { key = "debug", label = "Debug messages", kind = "check", help = "Extra chat lines for testing." },
      } },
    } },

  { key = "profiles", title = "Profiles", icon = "Interface\\AddOns\\ForeverLedger\\media\\icons\\profiles", custom = true,
    desc = "Sets of settings your characters can share, switch between, export and import." },

  { key = "appearance", title = "Appearance", icon = "Interface\\AddOns\\ForeverLedger\\media\\icons\\appearance",
    desc = "How Forever Ledger's windows look. A change shows after a reload.",
    rows = {
      { sub = "Theme and colour" },
      { key = "theme", label = "Theme", kind = "choice", after = function() ns:OfferReload() end, options = {
          { "clean", "FL Clean" }, { "default", "FL Default" }, { "gilded", "FL Gilded" } },
        help = "FL Clean: flat and quiet. FL Default: a bronze edge, gold titles, sections as cards, switches. FL Gilded: a bronze frame and gold serif titles. Looks based on WoW Forever's and Blizzard's own windows are coming." },
      { key = "uiScale", label = "Size", kind = "slider", min = 75, max = 150, step = 5, suffix = "%",
        after = function() if ns.ApplyScale then ns:ApplyScale() end end,
        help = "How big Forever Ledger's windows are, from 75% to 150%. Drag, then let go." },
      { key = "accent", label = "Accent colour", kind = "accent", after = function() ns:OfferReload() end,
        help = "The colour of what's active: the chosen tab, switches that are on, highlights. Auto uses EllesmereUI's colour when it's installed." },
    } },

  { group = "Gold making" },
  { key = "ah", title = "Auction house", icon = "Interface\\Icons\\INV_Misc_Coin_02",
    desc = "Buying, selling and alerts at the auction house.",
    tabs = {
      { name = "Buying", rows = {
        { sub = "Auction house window" },
        { key = "ahHighlight", label = "Mark good buys", kind = "check",
          help = "Listings at or below an item's buy limit get a green tint, bar and BUY badge." },
        { sub = "Buy queue" },
        { key = "openFlips", label = "Open the Buy queue after a full scan", kind = "check",
          help = "When a full scan finds vendor flips and the Buy queue beside the auction house is closed, open it. The flip watch's quick checks only chime." },
        { key = "watchResume", label = "Resume the flip watch", kind = "check",
          help = "If the flip watch was on when you closed the auction house, start it again when you come back. It can only scan while the auction house is open." },
        { key = "keepGold", label = "Buy queue: always keep", kind = "money", plainUnit = "g",
          help = "The Buy queue never takes your gold below this, so there's always enough for repairs, training or a mount. Type 100 for 100g. \"off\": it may spend all of it. (The most to spend each visit is on the Buy queue itself.)" },
      } },
      { name = "Selling", rows = {
        { sub = "Sell tab" },
        { key = "priceHelper", label = "Price helper on the Sell tab", kind = "check",
          help = "Under the Create Auction button: the usual price and the cheapest now, and buttons to fill in 1 copper under the cheapest or the usual price. Says when the cheapest is well below usual." },
        { key = "sellGuard", label = "Stop posts below vendor price", kind = "check",
          help = "On the Sell tab, when a vendor would pay more than the auction house after its cut, Post is greyed out until you click Post anyway. Off: just the warning." },
        { sub = "Your auctions" },
        { key = "undercutAlerts", label = "Undercut alerts", kind = "check",
          help = "When a scan finds one of your auctions undercut: a line in chat, once per price. The Auctions tab beside the auction house lists them all." },
        { key = "undercutSound", label = "  Sound with undercut alerts", kind = "check",
          help = "A short alarm sound with each undercut alert." },
        { key = "saleSound", label = "Sound when an auction sells", kind = "check",
          help = "A coin sound when the game says a buyer was found for one of your auctions." },
        { key = "soldSummary", label = "What sold while you were away", kind = "check",
          help = "Opening the auction house: one line in chat with what sold since you were last there, and the gold it brings." },
      } },
      { name = "Alerts", rows = {
        { sub = "New flips and deals" },
        { key = "dealSound", label = "Chime for new flips and deals", kind = "check", help = "Plays the raid warning sound when a scan finds new vendor flips or deals." },
        { key = "dealScreen", label = "Big message on screen", kind = "check", help = "Shows new flips and deals in large text at the top of the screen, where raid warnings go. Turn it off if it covers your windows; chat still lists them." },
      } },
      { name = "Disenchant finder", rows = {
        { sub = "Rolls" },
        { key = "deRolls", label = "Show a bad and a good roll", kind = "check",
          help = "Besides the average, what a band's greens are worth on a bad roll and a good one (the least and the most a disenchant can give)." },
      } },
    } },
  { key = "tooltips", title = "Tooltips", icon = "Interface\\Icons\\INV_Misc_Note_01",
    desc = "What Forever Ledger adds to item tooltips.",
    tabs = {
      { name = "General", rows = {
        { sub = "Size and detail" },
        { key = "tooltip", label = "Tooltip lines", kind = "check", help = "Forever Ledger's lines on item tooltips." },
        { key = "tipMode", label = "Tooltip size", kind = "choice", options = {
            { "full", "Everything" }, { "compact", "One line, Shift for more" } },
          help = "One line shows just what an item is worth to you; press Shift for the rest." },
        { key = "tipOptions", label = "Ways under Worth to you", kind = "number", suffix = "ways", min = 1, max = 10,
          help = "How many ways to use an item to list, best first." },
      } },
      { name = "What they show", rows = {
        { sub = "Prices and worth" },
        { key = "tipPrice", label = "Auction and vendor prices", kind = "check",
          help = "The cheapest on the auction house (how many listed, how long ago), the average of the cheapest 20, and what a vendor sells it for." },
        { key = "tipHistory", label = "Price history while Ctrl is held", kind = "check",
          help = "Hold Ctrl over an item for the cheapest price over the last 14 days, which way it's heading, the usual price this month, how many are usually listed and the lowest price ever seen." },
        { key = "tipSpeed", label = "How fast it sells", kind = "check",
          help = "Fast, Steady, Slow, Rare or No sales seen, once there are 3 hours of scans to judge by (and, in the first day, at least 3 sales)." },
        { key = "tipWorth", label = "Worth to you", kind = "check",
          help = "The best way to use the item (auction house, vendor, disenchanting or crafting it into something) and the next best few." },
        { key = "tipBuy", label = "Buy at or below", kind = "check",
          help = "The most worth paying for it, after your safety margin. Green when it's already cheaper." },
        { sub = "Uses and quests" },
        { key = "tipQuest", label = "Quests that need it", kind = "check",
          help = "Quests that ask for the item (original Classic quests; Forever may have changed some), and \"keep it\" when this character will want it later." },
        { key = "tipQuestMine", label = "  Only quests this character still needs", kind = "check",
          help = "Leaves out quests this character has done, ones grey for its level, and other classes' quests. Off: all of them, marked (done), (too low) or (other class), handy when selling to others." },
        { key = "tipDrops", label = "Dungeon drops you've had", kind = "check",
          help = "\"Dropped for you: Deadmines, 2 in 14 runs\", from the dungeon runs Forever Ledger counts (/fl runs)." },
        { key = "tipDisenchant", label = "Disenchants to", kind = "check",
          help = "What a green disenchants into, on average." },
        { key = "tipUsedBy", label = "Used by (your recipes)", kind = "check",
          help = "Which of your characters' recipes use it, and how many." },
        { key = "tipCrate", label = "Crate cheapest fill", kind = "check",
          help = "On a Waylaid Crate: the cheapest way to fill it at today's prices." },
        { key = "tipBagSlot", label = "Bag price per slot", kind = "check",
          help = "On a bag: what one slot costs at today's cheapest price (auction house or vendor), and the cheapest bag per slot right now." },
      } },
    } },

  { group = "Professions" },
  { key = "customers", title = "Customers", icon = "Interface\\Icons\\INV_Letter_15",
    desc = "Spotting people in chat who want what this character can do.",
    tabs = {
      { name = "General", rows = {
        { sub = "Customer finder" },
        { key = "customers", label = "Customer finder", kind = "check",
          help = "Spot people in chat asking for what this character can do (LF enchanter, WTB an item you craft, Mage water)." },
        { key = "customerWindow", label = "Open the Customers window", kind = "check",
          help = "Opens on a new request. /fl customers opens it any time." },
        { key = "customerSound", label = "Sound", kind = "check", help = "The whisper sound with each new request." },
        { key = "customerChat", label = "Requests in chat too", kind = "check", help = "Also print each request in chat." },
      } },
      { name = "What to look for", rows = {
        { sub = "Services" },
        { key = "svcCrafting", label = "Crafting", kind = "check", after = ads,
          help = "Requests for your professions and for items you craft, and the Advertise crafting button." },
        { key = "svcFood", label = "Mage food and water", kind = "check", after = ads,
          help = "On a Mage: requests for water and food, and the Sell food and water button." },
        { key = "svcPortal", label = "Mage portals", kind = "check", after = ads,
          help = "On a Mage from level 40: portal requests, and the Sell portals button." },
        { key = "svcSummon", label = "Warlock summons", kind = "check", after = ads,
          help = "On a Warlock from level 20: summon requests, and the Offer summons button." },
        { key = "svcLockpick", label = "Rogue lockpicking", kind = "check", after = ads,
          help = "On a Rogue from level 16: lockbox requests, and the Offer lockpicking button." },
      } },
    } },
  { key = "crates", title = "Waylaid Crates", icon = "Interface\\Icons\\INV_Crate_01",
    desc = "The Crates tab and the cheapest way to fill each crate.",
    rows = {
      { sub = "Crates" },
      { key = "crates", label = "Waylaid Crates", kind = "check", after = function() ns:LayoutTabs() end,
        help = "The Crates tab and the \"cheapest fill\" tooltip line." },
    } },

  { group = "Your gold" },
  { key = "sessions", title = "Sessions", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    desc = "Counting what your play time earns.",
    rows = {
      { sub = "Loot" },
      { key = "sessionValue", label = "Count loot at", kind = "choice", options = {
          { "best", "Best of auction and vendor" }, { "vendor", "Vendor only" } },
        help = "What a session counts each looted item as worth. Auction house prices are after the cut; items that bind when picked up always count at vendor price. Start a session with /fl session start or on the Dashboard." },
    } },

  { group = "Other" },
  { key = "other", title = "Minimap and updates", icon = "Interface\\Icons\\INV_Misc_Map_01",
    desc = "The minimap button and new version notices.",
    rows = {
      { sub = "Minimap" },
      { key = "minimap", label = "Minimap button", kind = "check", after = function() ns:UpdateMinimapButton() end,
        help = "The Forever Ledger button on the minimap. /fl opens the window either way." },
      { sub = "New versions" },
      { key = "updateNotice", label = "Tell me when a new version is out", kind = "check",
        help = "Forever Ledger hears it from guildmates and group members who have a newer version, and says so in chat once a session. It only shares the version number." },
    } },
  -- Every saved character, with Remove (owner, October 5: addons can't see a character
  -- being deleted, and a sync partner's stayed; rare and permanent, so here, not on the
  -- Characters tab).
  { key = "characters", title = "Characters", custom = true,
    desc = "Every character Forever Ledger knows about, and removing ones you no longer have." },
}

-- Every page gets a tab list (one unnamed tab when it has none), and every setting is
-- found by key. Settings on any page but Global are in profiles.
local DEFS, PAGE_BY_KEY = {}, {}
ns.PER_CHAR_SETTINGS = {}
for _, p in ipairs(PAGES) do
  if p.key then
    PAGE_BY_KEY[p.key] = p
    if p.rows then p.tabs = { { rows = p.rows } } end
    for _, tab in ipairs(p.tabs or {}) do
      for _, d in ipairs(tab.rows) do
        if d.key then
          DEFS[d.key] = d
          d.page = p.key
          if p.key ~= "global" then ns.PER_CHAR_SETTINGS[d.key] = true end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Appearance: a new look shows after a reload (every frame is drawn in the theme when
-- it's made), so a change offers one. Accept is a click, which ReloadUI needs.
---------------------------------------------------------------------------
if StaticPopupDialogs then
  StaticPopupDialogs.FLEDGER_RELOAD = {
    text = "Forever Ledger: reload now to see the new look?",
    button1 = "Reload", button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end
function ns:OfferReload()
  local T = ns.Theme
  if T and T.NeedsReload and T:NeedsReload() and StaticPopup_Show then StaticPopup_Show("FLEDGER_RELOAD") end
end

-- The accent colours on offer ("" = auto: EllesmereUI's, else the theme's teal).
local ACCENTS = { "0cd29d", "e8c27a", "f08a24", "e5484d", "9b7bff", "3e9bff" }

-- WoW's colour picker, old and new forms. done(r, g, b) as the colour changes.
local function pickColour(start, done)
  local CP = ColorPickerFrame
  if not CP then return end
  local r, g, b = start[1], start[2], start[3]
  local function changed() local nr, ng, nb = CP:GetColorRGB(); done(nr, ng, nb) end
  if CP.SetupColorPickerAndShow then
    CP:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = changed, cancelFunc = function() done(r, g, b) end })
  else
    CP.func, CP.cancelFunc, CP.hasOpacity = changed, function() done(r, g, b) end, false
    CP:SetColorRGB(r, g, b)
    CP:Hide(); CP:Show()
  end
end

-- The accent control: Auto, a row of colour squares, and Custom (the colour picker).
local function accentControl(parent, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f.items = {}
  local x = 0
  local function add(b, value)
    b:SetPoint("LEFT", x, 0)
    x = x + b:GetWidth() + 4
    b.value = value
    f.items[#f.items + 1] = b
  end
  add(T:Button(f, "Auto", 44, function() f:SetValue(""); onChange("") end, 20), "")
  for _, hex in ipairs(ACCENTS) do
    local c = T:FromHex(hex)
    local b = T:Button(f, "", 20, function() f:SetValue(hex); onChange(hex) end, 20)
    b.bg:SetColorTexture(c[1], c[2], c[3], 1)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(c[1], c[2], c[3], 1); for _, e in ipairs(self.borders) do e:SetColorTexture(1, 1, 1, self.selected and 1 or 0.15) end end)
    b:SetScript("OnEnter", function(self) for _, e in ipairs(self.borders) do e:SetColorTexture(1, 1, 1, 0.8) end end)
    function b:SetSelected(on) self.selected = on; self:GetScript("OnLeave")(self) end
    add(b, hex)
  end
  add(T:Button(f, "Custom", 60, function()
    pickColour(T:FromHex(f.value) or T.accent, function(r, g, b)
      local hex = T:ToHex({ r, g, b })
      f:SetValue(hex)
      onChange(hex)
    end)
  end, 20), "custom")
  f:SetSize(x, 20)
  function f:SetValue(v)
    self.value = v or ""
    local preset = self.value == ""
    for _, hex in ipairs(ACCENTS) do if hex == self.value then preset = true end end
    for _, b in ipairs(self.items) do
      b:SetSelected(b.value == self.value or (b.value == "custom" and not preset))
    end
  end
  return f
end

---------------------------------------------------------------------------
-- Profiles: switching, new, rename, delete, reset, export, import
---------------------------------------------------------------------------
local function profileNames()
  local names = {}
  for n in pairs(ns.db.profiles) do names[#names + 1] = n end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  table.insert(names, 1, ns.DEFAULT_PROFILE)
  return names
end

local function usersOf(name)
  local out = {}
  for key, c in pairs(ns.db.chars) do
    if ns:ProfileOf(key) == name then out[#out + 1] = c.name or key end
  end
  table.sort(out)
  return out
end

-- After the profile changes: everything that reads a setting once is told.
local function afterSwitch()
  ns:ApplyCharSettings()
  ns:OfferReload()   -- (the profile may have another theme or accent)
  if ns.UpdateMinimapButton then pcall(ns.UpdateMinimapButton, ns) end
  if ns.LayoutTabs then pcall(ns.LayoutTabs, ns) end
  if ns.UpdateCustomerAds then pcall(ns.UpdateCustomerAds, ns) end
  if ns.ApplyScale then ns:ApplyScale() end
  ns:RefreshSettings()
end

local function useProfile(name)
  ns.db.charProfile[ns.CharKey()] = (name ~= ns.DEFAULT_PROFILE) and name or nil
  afterSwitch()
end

-- This character's per-character settings as they are now, as a new table.
local function snapshot()
  local v = {}
  for k in pairs(ns.PER_CHAR_SETTINGS) do
    local x = ns.db.settings[k]
    if type(x) ~= "table" then v[k] = x end
  end
  return v
end

local function cleanName(s)
  s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil, "Type a name in the box first." end
  if #s > 30 then return nil, "That name is too long (30 letters at most)." end
  if s:lower() == ns.DEFAULT_PROFILE:lower() then return nil, "That name is taken by the Default profile." end
  for n in pairs(ns.db.profiles) do
    if n:lower() == s:lower() then return nil, ("There's already a profile called %s."):format(n) end
  end
  return s
end

local function uniqueName(base)
  base = (type(base) == "string" and base:gsub("^%s+", ""):gsub("%s+$", "") ~= "" and base:sub(1, 26)) or "Imported"   -- (room for " 2")
  local name, n = base, 2
  while not cleanName(name) do name = base .. " " .. n; n = n + 1 end
  return name
end

local function newProfile(text)
  local name, err = cleanName(text)
  if not name then return ns:Print(err) end
  ns.db.profiles[name] = snapshot()
  useProfile(name)
  ns:Print(("New profile %s, a copy of the settings you had. This character uses it now."):format(name))
end

local function renameProfile(text)
  local cur = ns:ProfileOf()
  if cur == ns.DEFAULT_PROFILE then return ns:Print("The Default profile keeps its name. Make a new profile to name your own.") end
  local name, err = cleanName(text)
  if not name then return ns:Print(err) end
  ns.db.profiles[name], ns.db.profiles[cur] = ns.db.profiles[cur], nil
  for key, n in pairs(ns.db.charProfile) do if n == cur then ns.db.charProfile[key] = name end end
  afterSwitch()
  ns:Print(("Renamed %s to %s."):format(cur, name))
end

local function deleteProfile()
  local cur = ns:ProfileOf()
  if cur == ns.DEFAULT_PROFILE then return end
  ns.db.profiles[cur] = nil
  for key, n in pairs(ns.db.charProfile) do if n == cur then ns.db.charProfile[key] = nil end end
  afterSwitch()
  ns:Print(("Deleted the profile %s. Characters that used it are on Default now."):format(cur))
end

local function resetProfile()
  for k in pairs(ns.PER_CHAR_SETTINGS) do
    local d = ns.DEFAULT_SETTINGS[k]
    if type(d) ~= "table" then ns.db.settings[k] = d end
  end
  afterSwitch()
  ns:Print(("The %s profile is back to Forever Ledger's defaults. Global settings weren't touched."):format(ns:ProfileOf()))
end

-- A value a setting could really have (imports are checked, never trusted).
local function validValue(d, v)
  if d.kind == "check" then return type(v) == "boolean" end
  if d.kind == "number" or d.kind == "slider" then return type(v) == "number" and v >= (d.min or -math.huge) and v <= (d.max or math.huge) end
  if d.kind == "money" then return type(v) == "number" and v >= 0 and v < 1e10 end
  if d.kind == "choice" then
    for _, o in ipairs(d.options) do if o[1] == v then return true end end
  end
  if d.kind == "accent" then return v == "" or (type(v) == "string" and v:match("^%x%x%x%x%x%x$") ~= nil) end
  return false
end

local function exportProfile(parts)
  local values = {}
  for key, d in pairs(DEFS) do
    if parts[d.page] and ns.PER_CHAR_SETTINGS[key] then
      local v = ns.db.settings[key]
      if type(v) ~= "table" then values[key] = v end
    end
  end
  return ns.Serialize({ kind = "profile", v = 1, name = ns:ProfileOf(), values = values })
end

local function importProfile(text)
  local data, err = ns.Deserialize(text)
  if not data then return false, err end
  if type(data) ~= "table" or data.kind ~= "profile" or type(data.values) ~= "table" then
    return false, "That isn't a settings profile. (Data from Export / import on the Characters tab goes in there.)"
  end
  local values, n = {}, 0
  for k, v in pairs(data.values) do
    local d = DEFS[k]
    if d and ns.PER_CHAR_SETTINGS[k] and validValue(d, v) then values[k] = v; n = n + 1 end
  end
  if n == 0 then return false, "That profile has no settings this version of Forever Ledger knows." end
  -- Parts left out of the export start as this character's settings are now.
  local full = snapshot()
  for k, v in pairs(values) do full[k] = v end
  local name = uniqueName(data.name ~= ns.DEFAULT_PROFILE and data.name or "Imported")
  ns.db.profiles[name] = full
  useProfile(name)
  return true, ("Imported %d settings as the profile %s; this character uses it now. Switch back any time in Settings, Profiles."):format(n, name)
end

---------------------------------------------------------------------------
-- Building the tab
---------------------------------------------------------------------------
local NAV_W = 190
local f
local state = { page = "global", tab = {}, query = nil }

-- "Default: Auto." under each setting (owner's test, October 3).
local function defaultText(d)
  local v = ns.DEFAULT_SETTINGS and ns.DEFAULT_SETTINGS[d.key]
  if v == nil then return end
  if d.kind == "choice" then
    for _, o in ipairs(d.options) do if o[1] == v then return "Default: " .. o[2] .. "." end end
  elseif d.kind == "number" then
    local s = d.suffix or ""
    return ("Default: %g%s."):format(v, s == "" and "" or ((s:sub(1, 1) == "%" and "" or " ") .. s))
  elseif d.kind == "money" then
    return "Default: " .. ((v > 0) and ns.MoneyPlain(v) or "off") .. "."
  elseif d.kind == "accent" then
    return "Default: Auto."
  elseif d.kind == "slider" then
    return ("Default: %d%s."):format(v, d.suffix or "")
  end
end

-- One setting's row: name, description and its control.
local function makeRow(box, d)
  local r = { def = d }
  r.label = T:Text(box, 12 + (T.theme.labelAdd or 0))   -- (names stand out from the grey text)
  r.label:SetJustifyH("LEFT")
  r.label:SetText((d.label:gsub("^%s+", "")))
  r.indent = d.label:find("^%s") and 18 or 0   -- a sub-option of the one above
  local dflt = defaultText(d)
  local helpText = d.help and dflt and (d.help .. " " .. dflt) or d.help or dflt
  if helpText then
    r.help = T:Text(box, 11, T.dim)
    r.help:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
    r.help:SetJustifyH("LEFT")
    r.help:SetSpacing(2)
    r.help:SetText(helpText)
  end
  local function changed(v)
    ns.db.settings[d.key] = v
    if d.after then d.after() end
    if f.rules then f.rules:SetText("Deals are listings " .. ns:DealRules() .. ".") end
  end
  if d.kind == "number" then
    r.control = T:Number(box, d, changed)
  elseif d.kind == "money" then
    r.control = T:MoneyBox(box, changed, d.plainUnit or "g")   -- a lone number is gold (owner, October 3)
  elseif d.kind == "choice" then
    local opts = {}
    for _, o in ipairs(d.options) do opts[#opts + 1] = { value = o[1], label = o[2] } end
    if #opts > 3 then   -- many options would run off the page: a dropdown instead
      r.control = T:Dropdown(box, 190, changed)
      r.control.default = ns.DEFAULT_SETTINGS and ns.DEFAULT_SETTINGS[d.key]
      r.control:SetOptions(opts)
    else
      r.control = T:Choice(box, opts, changed)
    end
  elseif d.kind == "accent" then
    r.control = accentControl(box, changed)
  elseif d.kind == "slider" then
    r.control = T:Slider(box, d, changed)
  elseif d.kind == "check" then
    r.control = T:Check(box, function(self) changed(self:GetChecked()) end, "switch")
  end
  r.line = box:CreateTexture(nil, "BACKGROUND")
  r.line:SetColorTexture(1, 1, 1, 0.04)
  r.line:SetHeight(1)
  f.controls[#f.controls + 1] = r
  return r
end

-- A small heading inside a tab, on a faint accent band (owner's test, October 3).
local function makeSub(box, text)
  local r = { head = true }
  r.text = T:Text(box, 11)
  T:StyleHeading(r.text, text)
  -- Plain, like the mockup (no band behind it); on Gilded a gold rule under it. The
  -- band is an invisible frame to lay it out by.
  r.band = box:CreateTexture(nil, "BACKGROUND")
  r.band:SetColorTexture(0, 0, 0, 0)
  r.band:SetHeight(20)
  if T.theme.serif then
    local c = T.theme.heading or T.accent
    r.rule = box:CreateTexture(nil, "BORDER")
    r.rule:SetColorTexture(c[1], c[2], c[3], 0.45)
    r.rule:SetHeight(1)
    r.rule:SetPoint("BOTTOMLEFT", r.band, "BOTTOMLEFT", 8, -2)
    r.rule:SetPoint("BOTTOMRIGHT", r.band, "BOTTOMRIGHT", -8, -2)
  end
  return r
end

local function showRow(r, on)
  if r.head then r.text:SetShown(on); r.band:SetShown(on); if r.rule then r.rule:SetShown(on) end; return end
  r.label:SetShown(on); r.control:SetShown(on); r.line:SetShown(on)
  if r.help then r.help:SetShown(on) end
end

local function rowMatches(r, q)
  local d = r.def
  return d and ((d.label or ""):lower():find(q, 1, true) or (d.help or ""):lower():find(q, 1, true)) and true or false
end

-- (Cards: T:PlaceCard / T:HideCards in Theme.lua, shared with Help.)

-- Lay out one tab's rows from y; returns where it ended. Tick boxes sit left of their
-- name so the text has the width; other controls line up on the right. withCards: a
-- card for each group (from a heading to the next).
local function layoutRows(box, rows, width, y, withCards)
  local used, groupTop, any = 0, nil, false
  local function close()
    if withCards and groupTop and any then
      used = used + 1
      T:PlaceCard(box, used, groupTop, y + 2, width)
      y = y + 12
    end
    groupTop, any = nil, false
  end
  for _, r in ipairs(rows) do
    if r.head then close(); groupTop = y elseif not groupTop then groupTop = y end
    if not r.head then any = true end
    if r.head then
      r.band:ClearAllPoints()
      r.band:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -(y + 4))
      r.band:SetWidth(width - 8)
      r.text:ClearAllPoints()
      r.text:SetPoint("LEFT", r.band, "LEFT", 8, 0)
      y = y + 30
    else
      local check = r.def.kind == "check"
      local cw = check and 0 or r.control:GetWidth()
      local textX = (check and (20 + r.control:GetWidth()) or 12) + (r.indent or 0)   -- (a switch is wider than a tick box)
      -- (Right-hand controls end 12 pixels inside the edge; they ran past the card's edge:
      -- owner's screenshots, October 4.)
      local textW = math.max(120, check and (width - textX - 12) or (width - cw - 48 - (r.indent or 0)))
      r.label:ClearAllPoints()
      r.label:SetPoint("TOPLEFT", box, "TOPLEFT", textX, -(y + 5))
      r.label:SetWidth(textW)
      local h = 20
      if r.help then
        r.help:SetWidth(textW)
        h = h + r.help:GetStringHeight() + 4
      end
      r.control:ClearAllPoints()
      if check then
        r.control:SetPoint("TOPLEFT", box, "TOPLEFT", 12 + (r.indent or 0), -(y + 6))
        r.control:SetHitRectInsets(0, -(math.min(r.label:GetStringWidth(), textW) + 22), -4, -4)   -- the name ticks it too
      else
        r.control:SetPoint("TOPLEFT", box, "TOPLEFT", math.max(textX + textW + 24, width - 12 - cw), -(y + 1))
      end
      y = y + math.max(h, 26) + 8
      r.line:ClearAllPoints()
      r.line:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -(y - 4))
      r.line:SetWidth(width - 16)
    end
  end
  close()
  T:HideCards(box, used + 1)
  return y
end

-- The sidebar: a page's button (its name, a bar and a tint on the chosen one).
local function navButton(p, indent)
  local b = CreateFrame("Button", nil, f.nav)
  b:SetHeight(24)
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetPoint("TOPLEFT")
  b.bar:SetPoint("BOTTOMLEFT")
  b.bar:SetWidth(2)
  b.bar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.05)
  -- No icons (owner, October 4: the game's icons looked busy, and there will be many
  -- pages); the bar and the tint show the chosen one.
  -- Global settings, Profiles and Appearance (above the groups) get a small outline icon
  -- so they stand out, like the mockup (owner, October 4): our own drawings (media/icons,
  -- white, 64 px TGA), tinted in the heading colour.
  if p.icon and (indent or 14) < 20 then
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(15, 15)
    b.icon:SetPoint("LEFT", 12, 0)
    b.icon:SetTexture(p.icon)
    local c = T.theme.heading or T.accent
    b.icon:SetVertexColor(c[1], c[2], c[3], 0.9)
    indent = 32
  end
  b.text = T:Text(b, 12)
  b.text:SetPoint("LEFT", indent or 14, 0)
  b.text:SetJustifyH("LEFT")
  b.text:SetText(p.title)
  b.extra = T:Text(b, 10, T.dim)
  b.extra:SetPoint("RIGHT", -8, 0)
  b.extra:SetJustifyH("RIGHT")
  b.extra:SetWordWrap(false)
  b.text:SetPoint("RIGHT", b.extra, "LEFT", -4, 0)
  b.text:SetWordWrap(false)
  b:SetScript("OnClick", function()
    state.page = p.key
    f.search:SetText("")   -- (clears the search, which redraws)
    f.search:ClearFocus()
    ns:RefreshSettings()
    f.sf:SetVerticalScroll(0)
  end)
  return b
end

---------------------------------------------------------------------------
-- The Profiles page
---------------------------------------------------------------------------
local armed = {}   -- [button] = GetTime() of the first click ("Sure?")
local function confirmButton(parent, label, width, fn)
  local b
  b = T:Button(parent, label, width, function()
    if armed[b] and GetTime() - armed[b] < 4 then
      armed[b] = nil
      b:SetText(label)
      fn()
    else
      armed[b] = GetTime()
      b:SetText("Sure? Click again")
      C_Timer.After(4, function() if armed[b] and GetTime() - armed[b] >= 4 then armed[b] = nil; b:SetText(label) end end)
    end
  end, 24)
  return b
end

local function buildProfiles(box)
  local P = CreateFrame("Frame", nil, box)
  P.intro = T:Text(P, 12, T.dim)
  P.intro:SetJustifyH("LEFT")
  P.intro:SetText("A profile is a set of settings your characters can share: say no tooltips on one character, no customer finder on another. Each character uses one profile. Global settings aren't in profiles: they're the same for everyone.")

  P.head1 = makeSub(P, "This character")
  P.pick = T:Dropdown(P, 220, function(v) useProfile(v) end)
  P.pickLabel = T:Text(P, 12)
  P.pickLabel:SetText("Profile")
  P.users = T:Text(P, 11, T.dim)
  P.users:SetJustifyH("LEFT")

  P.head2 = makeSub(P, "Manage")
  P.name = T:EditBox(P, 200, "LEFT")
  local hint = T:Text(P.name, 11, T.section)
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Name for a new profile")
  P.name:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "" and not self:HasFocus()) end)
  P.name:SetScript("OnEditFocusGained", function() hint:Hide() end)
  P.name:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
  P.name:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  P.new = T:Button(P, "New profile", 110, function()
    newProfile(P.name:GetText())
    if ns:ProfileOf() ~= ns.DEFAULT_PROFILE then P.name:SetText(""); P.name:ClearFocus() end
  end, 24)
  P.rename = T:Button(P, "Rename", 80, function() renameProfile(P.name:GetText()); P.name:SetText(""); P.name:ClearFocus() end, 24)
  P.manageHelp = T:Text(P, 11, T.dim)
  P.manageHelp:SetJustifyH("LEFT")
  P.manageHelp:SetText("A new profile starts as a copy of the settings this character has now, and this character switches to it. Rename renames the profile this character uses.")
  P.reset = confirmButton(P, "Reset to defaults", 140, resetProfile)
  P.delete = confirmButton(P, "Delete profile", 120, deleteProfile)
  for _, b in ipairs({ P.reset, P.delete }) do
    b:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self == P.reset and "Reset to defaults" or "Delete profile", 1, 1, 1)
      GameTooltip:AddLine(self == P.reset and "Puts every setting in this profile back to Forever Ledger's default. Global settings aren't touched. Click twice."
        or "Deletes the profile this character uses; characters on it go back to Default. Default can't be deleted. Click twice.", nil, nil, nil, true)
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end

  P.head3 = makeSub(P, "Share")
  P.shareHelp = T:Text(P, 11, T.dim)
  P.shareHelp:SetJustifyH("LEFT")
  P.shareHelp:SetText("Export copies this character's profile as text, with only the parts you tick. Import makes a new profile from someone's text. Only settings travel: never Global settings, gold or any of your data.")
  P.parts, P.partChecks = {}, {}
  for _, p in ipairs(PAGES) do
    if p.key and p.tabs and p.key ~= "global" then   -- (pages with settings: not Profiles or Characters)
      P.parts[p.key] = true
      local c = T:Check(P, function(self) P.parts[p.key] = self:GetChecked() end)
      c:SetChecked(true)
      c.label:SetText(p.title)
      c:SetHitRectInsets(0, -(c.label:GetStringWidth() + 8), -4, -4)
      P.partChecks[#P.partChecks + 1] = c
    end
  end
  -- One button and one window with Export and Import tabs, like Export / import on the
  -- Characters tab (owner's test, October 5).
  local showExport, showImport
  local function tabs(current)
    return { current = current, { "Export", function() showExport() end }, { "Import", function() showImport() end } }
  end
  showExport = function()
    local any = false
    for _, on in pairs(P.parts) do any = any or on end
    if not any then
      ns:ShowTextWindow("Export / import profile",
        "Tick at least one part under Share in Settings, Profiles, to export it.", "", nil, nil, tabs(1))
      return
    end
    ns:ShowTextWindow("Export / import profile",
      ("Profile %s. Press Ctrl+A, then Ctrl+C to copy. Whoever gets it pastes it into Settings, Profiles, Export / import, Import."):format(ns:ProfileOf()),
      exportProfile(P.parts), nil, nil, tabs(1))
  end
  showImport = function()
    ns:ShowTextWindow("Export / import profile",
      "Paste a profile with Ctrl+V, then click Import. It becomes a new profile and this character switches to it; your other profiles stay as they are.",
      "", "Import", importProfile, tabs(2))
  end
  P.export = T:Button(P, "Export / import", 130, function() showExport() end, 24)
  return P
end

local function layoutProfiles(P, width)
  local y = 4
  P.intro:ClearAllPoints()
  P.intro:SetPoint("TOPLEFT", 12, -y)
  P.intro:SetWidth(width - 24)
  y = y + P.intro:GetStringHeight() + 12
  y = layoutRows(P, { P.head1 }, width, y)
  P.pickLabel:ClearAllPoints()
  P.pickLabel:SetPoint("TOPLEFT", 12, -(y + 4))
  P.pick:ClearAllPoints()
  P.pick:SetPoint("TOPLEFT", 80, -y)
  P.users:ClearAllPoints()
  P.users:SetPoint("TOPLEFT", 80, -(y + 28))
  P.users:SetWidth(width - 92)
  y = y + 32 + P.users:GetStringHeight() + 14
  y = layoutRows(P, { P.head2 }, width, y)
  P.name:ClearAllPoints()
  P.name:SetPoint("TOPLEFT", 12, -(y + 1))
  P.new:ClearAllPoints()
  P.new:SetPoint("LEFT", P.name, "RIGHT", 6, 0)
  P.rename:ClearAllPoints()
  P.rename:SetPoint("LEFT", P.new, "RIGHT", 4, 0)
  y = y + 30
  P.manageHelp:ClearAllPoints()
  P.manageHelp:SetPoint("TOPLEFT", 12, -y)
  P.manageHelp:SetWidth(width - 24)
  y = y + P.manageHelp:GetStringHeight() + 10
  P.reset:ClearAllPoints()
  P.reset:SetPoint("TOPLEFT", 12, -y)
  P.delete:ClearAllPoints()
  P.delete:SetPoint("LEFT", P.reset, "RIGHT", 6, 0)
  y = y + 38
  y = layoutRows(P, { P.head3 }, width, y)
  P.shareHelp:ClearAllPoints()
  P.shareHelp:SetPoint("TOPLEFT", 12, -y)
  P.shareHelp:SetWidth(width - 24)
  y = y + P.shareHelp:GetStringHeight() + 10
  local colW = math.max(150, math.floor((width - 24) / 3))
  for i, c in ipairs(P.partChecks) do
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", 12 + ((i - 1) % 3) * colW, -(y + math.floor((i - 1) / 3) * 22))
  end
  y = y + math.ceil(#P.partChecks / 3) * 22 + 6
  P.export:ClearAllPoints()
  P.export:SetPoint("TOPLEFT", 12, -y)
  return y + 40
end

local function refreshProfiles(P)
  local cur = ns:ProfileOf()
  local opts = {}
  for _, n in ipairs(profileNames()) do opts[#opts + 1] = { value = n, label = n } end
  P.pick:SetOptions(opts)
  P.pick:SetValue(cur)
  local users = usersOf(cur)
  P.users:SetText(#users > 0 and ("Used by: " .. table.concat(users, ", ")) or "")
  P.rename:SetEnabled(cur ~= ns.DEFAULT_PROFILE)
  P.delete:SetEnabled(cur ~= ns.DEFAULT_PROFILE)
end

---------------------------------------------------------------------------
-- The Characters page: every saved character, when it was last seen, where it came
-- from, and Remove (ns:RemoveCharacter, Core.lua). Never the one you're on.
---------------------------------------------------------------------------
local function lastSeen(key)
  if key == ns.CharKey() then return time() end
  local c, inv = ns.db.chars[key] or {}, ns.db.inventory[key] or {}
  local t = math.max(c.updated or 0, inv.t or 0, inv.bankT or 0)
  return t > 0 and t or nil
end

local function buildChars(box)
  local C = CreateFrame("Frame", nil, box)
  C.intro = T:Text(C, 12, T.dim)
  C.intro:SetJustifyH("LEFT")
  C.intro:SetText("Addons can't see a character being deleted or renamed, so it stays here (and on the Characters tab, in Have and in recipes) until you remove it. Remove forgets its level, professions, recipes, bags and bank; prices and gold history stay. One of yours comes back when you log in on it.")
  -- A heading between the explanation and the list (owner's screenshot, October 5: the
  -- top ran straight into the rows), as on the Profiles page.
  C.head = makeSub(C, "Saved characters")
  C.rows = {}
  return C
end

local function charRow(C, i)
  if C.rows[i] then return C.rows[i] end
  local r = CreateFrame("Frame", nil, C)
  r:SetHeight(40)
  r.stripe = T:Fill(r, { 1, 1, 1, 0.025 })
  r.remove = confirmButton(r, "Remove", 130, function()
    local key = r.key
    local name = (ns.db.chars[key] and ns.db.chars[key].name) or key
    if ns:RemoveCharacter(key) then
      if ns.BuildUsageIndex then ns:BuildUsageIndex() end
      if ns.InvalidateValues then ns:InvalidateValues() end
      ns:Print(("Removed %s from Forever Ledger. Prices and gold history are kept."):format(name))
      ns:RefreshUI()
      ns:RefreshSettings()
    end
  end)
  r.remove:SetPoint("RIGHT", -8, 0)
  r.you = T:Text(r, 11, T.dim)
  r.you:SetPoint("RIGHT", -14, 0)
  r.you:SetText("you're on this one")
  r.name = T:Text(r, 12)
  r.name:SetPoint("TOPLEFT", 10, -5)
  r.name:SetPoint("RIGHT", r.remove, "LEFT", -10, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.info = T:Text(r, 11, T.dim)
  r.info:SetPoint("TOPLEFT", 10, -22)
  r.info:SetPoint("RIGHT", r.remove, "LEFT", -10, 0)
  r.info:SetJustifyH("LEFT")
  r.info:SetWordWrap(false)
  C.rows[i] = r
  return r
end

local function layoutChars(C, width)
  local y = 4
  C.intro:ClearAllPoints()
  C.intro:SetPoint("TOPLEFT", 12, -y)
  C.intro:SetWidth(width - 24)
  y = y + C.intro:GetStringHeight() + 12
  y = layoutRows(C, { C.head }, width, y) + 2
  -- The one you're on first, then the most recently seen.
  local keys = {}
  for key in pairs(ns.db.chars) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if (a == ns.CharKey()) ~= (b == ns.CharKey()) then return a == ns.CharKey() end
    return (lastSeen(a) or 0) > (lastSeen(b) or 0)
  end)
  for i, key in ipairs(keys) do
    local c, r = ns.db.chars[key], charRow(C, i)
    local me = key == ns.CharKey()
    r.key = key
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 4, -y)
    r:SetWidth(width - 8)
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class or ""]
    local cls = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class or ""]) or c.class or ""
    r.name:SetText(("%s  |cff888888level %s %s|r"):format(
      cc and ("|c" .. (cc.colorStr or "ffffffff") .. (c.name or key) .. "|r") or (c.name or key), c.level or "?", cls))
    local from = (c.via and ("from your sync partner " .. c.via))
      or (ns:IsOwnChar(key) and "this account") or "from an import or an earlier sync"
    local seen = lastSeen(key)
    r.info:SetText(("%s %s, %s, %s"):format(c.realm or "?", c.faction or "", from,
      me and "playing now" or (seen and ("last seen " .. ns.Age(seen)) or "never seen here")))
    r.remove:SetShown(not me)
    r.you:SetShown(me)
    r:Show()
    y = y + 44
  end
  for i = #keys + 1, #C.rows do C.rows[i]:Hide() end
  return y + 10
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function ns:BuildSettings(parent)
  f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f.controls, f.boxes, f.navButtons = {}, {}, {}

  -- The sidebar: search, then the pages under their group headings.
  f.nav = CreateFrame("Frame", nil, f)
  f.nav:SetPoint("TOPLEFT")
  f.nav:SetPoint("BOTTOMLEFT")
  f.nav:SetWidth(NAV_W)
  -- Gilded: a warm gold tint and a bronze edge, like the mockup.
  local fr = T.theme.frame
  T:Fill(f.nav, fr and { 0.91, 0.76, 0.48, 0.04 } or { 1, 1, 1, 0.02 })
  local edge = f.nav:CreateTexture(nil, "BORDER")
  if fr then edge:SetColorTexture(fr[1], fr[2], fr[3], 0.5) else edge:SetColorTexture(1, 1, 1, 0.06) end
  edge:SetPoint("TOPRIGHT")
  edge:SetPoint("BOTTOMRIGHT")
  edge:SetWidth(1)

  local search = T:EditBox(f.nav, NAV_W - 16, "LEFT")
  search:SetPoint("TOPLEFT", 8, -6)
  local hint = T:Text(search, 11, T.section)
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Search settings")
  search:SetScript("OnTextChanged", function(self)
    hint:SetShown(self:GetText() == "" and not self:HasFocus())
    local q = self:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "")
    local new = #q >= 2 and q or nil
    if new ~= state.query then
      state.query = new
      f.sf:SetVerticalScroll(0)
      ns:RefreshSettings()
    end
  end)
  search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  search:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  f.search = search

  local y = 38
  local grouped = false   -- pages under a group heading sit further in (owner, October 4)
  for _, p in ipairs(PAGES) do
    if p.group then
      grouped = true
      local h = T:Text(f.nav, 10)
      T:StyleHeading(h, p.group)
      h:SetPoint("TOPLEFT", 10, -(y + 8))
      y = y + 26
    else
      local b = navButton(p, grouped and 24 or 14)
      b:SetPoint("TOPLEFT", 0, -y)
      b:SetPoint("RIGHT", f.nav, "RIGHT", -1, 0)
      f.navButtons[p.key] = b
      y = y + 26
    end
  end

  -- The page: title, a line about it, tabs, then its settings.
  f.title = T:Text(f, 16)
  T:StyleTitle(f.title, 16)
  f.title:SetPoint("TOPLEFT", NAV_W + 14, -4)
  f.desc = T:Text(f, 11, T.dim)
  f.desc:SetPoint("TOPLEFT", NAV_W + 14, -26)
  f.desc:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  f.desc:SetJustifyH("LEFT")
  f.desc:SetWordWrap(false)
  f.tabLine = f:CreateTexture(nil, "BORDER")
  f.tabLine:SetColorTexture(1, 1, 1, 0.06)
  f.tabLine:SetHeight(1)
  f.tabLine:SetPoint("TOPLEFT", NAV_W + 8, -73)
  f.tabLine:SetPoint("TOPRIGHT", 0, -73)

  local sf, content = T:Scroll(f)
  sf:SetPoint("BOTTOMRIGHT")
  f.sf, f.content = sf, content
  sf:HookScript("OnSizeChanged", function() if f:IsVisible() then ns:RefreshSettings() end end)
  f.noMatch = T:Text(content, 12, T.dim)
  f.noMatch:SetPoint("TOPLEFT", 12, -12)
  f.noMatch:SetText("No setting matches that. Try another word, like price, sound or tooltip.")

  -- Each page's tabs, and a box of rows for each tab.
  for _, p in ipairs(PAGES) do
    if p.key and p.tabs then
      p.tabButtons = {}
      local x = NAV_W + 8
      for i, tab in ipairs(p.tabs) do
        if tab.name then
          local b = T:Tab(f, tab.name, function()
            state.tab[p.key] = i
            ns:RefreshSettings()
            f.sf:SetVerticalScroll(0)
          end)
          b:SetPoint("TOPLEFT", x, -44)
          x = x + b:GetWidth()
          b:Hide()
          p.tabButtons[i] = b
        end
        local box = CreateFrame("Frame", nil, content)
        box:Hide()
        box.page, box.tabIndex, box.rows = p, i, {}
        box.headBand = box:CreateTexture(nil, "BACKGROUND")
        box.headBand:SetColorTexture(1, 1, 1, 0.05)
        box.headBand:SetHeight(24)
        box.headText = T:Text(box, 13, T.accent)
        box.headText:SetText(p.title .. (tab.name and ("  |cff888888>|r  " .. tab.name) or ""))
        if tab.rules then
          box.rules = T:Text(box, 11, T.dim)
          box.rules:SetJustifyH("LEFT")
          f.rules = box.rules
        end
        for _, d in ipairs(tab.rows) do
          box.rows[#box.rows + 1] = d.sub and makeSub(box, d.sub) or makeRow(box, d)
        end
        f.boxes[#f.boxes + 1] = box
      end
    end
  end
  f.profiles = buildProfiles(content)
  f.profiles:Hide()
  f.chars = buildChars(content)
  f.chars:Hide()
  return f
end

-- Back to Global settings and no search (the tab was clicked again).
function ns:ResetSettingsView()
  state.page, state.query, state.tab = "global", nil, {}
  if f and f.search then f.search:SetText("") end
end

function ns:RefreshSettings()
  if not (f and f:IsShown()) then return end
  local q = state.query
  local page = PAGE_BY_KEY[state.page] or PAGE_BY_KEY.global
  local tabIndex = state.tab[page.key] or 1

  -- Sidebar
  for key, b in pairs(f.navButtons) do
    local on = not q and key == page.key
    b.sel:SetShown(on)
    b.bar:SetShown(on)
    local nChars = 0
    if key == "characters" then for _ in pairs(ns.db.chars) do nChars = nChars + 1 end end
    b.extra:SetText((key == "profiles" and ns:ProfileOf()) or (key == "characters" and tostring(nChars)) or "")
  end

  -- Header and tabs
  local hasTabs = not q and page.tabButtons and #page.tabButtons > 0
  if q then
    f.title:SetText("Search")
    f.desc:SetText(("Settings that mention \"%s\", from every page."):format(q))
  else
    f.title:SetText(page.title)
    f.desc:SetText(page.desc or "")
  end
  for _, p in ipairs(PAGES) do
    for i, b in pairs(p.tabButtons or {}) do
      b:SetShown(hasTabs and p == page)
      b:SetSelected(i == tabIndex)
    end
  end
  f.tabLine:SetShown(hasTabs)
  local top = hasTabs and 78 or 50
  f.sf:ClearAllPoints()
  f.sf:SetPoint("TOPLEFT", NAV_W + 4, -top)
  f.sf:SetPoint("BOTTOMRIGHT")

  -- Rows: this page's tab, or every match when searching.
  f.content:SetWidth(math.max(f.sf:GetWidth() - 12, 300))
  local width = f.content:GetWidth()
  local y = 0
  for _, box in ipairs(f.boxes) do
    local rows = {}
    for _, r in ipairs(box.rows) do
      local on = (not q) or (not r.head and rowMatches(r, q))
      showRow(r, on)
      if on then rows[#rows + 1] = r end
    end
    local show = (q and #rows > 0) or (not q and box.page == page and box.tabIndex == tabIndex)
    box:SetShown(show and true or false)
    if show then
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", 0, -y)
      box:SetWidth(width)
      local by = 0
      box.headBand:SetShown(q ~= nil)
      box.headText:SetShown(q ~= nil)
      if q then
        box.headBand:ClearAllPoints()
        box.headBand:SetPoint("TOPLEFT", 4, -4)
        box.headBand:SetWidth(width - 8)
        box.headText:ClearAllPoints()
        box.headText:SetPoint("LEFT", box.headBand, "LEFT", 8, 0)
        by = 32
      end
      if box.rules then
        box.rules:SetShown(not q)
        if not q then
          box.rules:ClearAllPoints()
          box.rules:SetPoint("TOPLEFT", 12, -(by + 4))
          box.rules:SetWidth(width - 24)
          box.rules:SetText("Deals are listings " .. ns:DealRules() .. ".")
          by = by + box.rules:GetStringHeight() + 14
        end
      end
      by = layoutRows(box, rows, width, by, T.theme.cards) + 10
      box:SetHeight(by)
      y = y + by
    end
  end

  -- The Profiles page
  local prof = not q and page.key == "profiles"
  f.profiles:SetShown(prof)
  if prof then
    f.profiles:ClearAllPoints()
    f.profiles:SetPoint("TOPLEFT", 0, 0)
    f.profiles:SetWidth(width)
    refreshProfiles(f.profiles)
    local h = layoutProfiles(f.profiles, width)
    f.profiles:SetHeight(h)
    y = h
  end
  -- The Characters page
  local chars = not q and page.key == "characters"
  f.chars:SetShown(chars)
  if chars then
    f.chars:ClearAllPoints()
    f.chars:SetPoint("TOPLEFT", 0, 0)
    f.chars:SetWidth(width)
    local h = layoutChars(f.chars, width)
    f.chars:SetHeight(h)
    y = h
  end

  f.noMatch:SetShown(q ~= nil and y == 0)
  f.content:SetHeight(math.max(y, 100))
  for _, r in ipairs(f.controls) do
    if r.control:IsShown() then
      local v = ns.db.settings[r.def.key]
      if r.def.kind == "check" then r.control:SetChecked(v) else r.control:SetValue(v) end
    end
  end
  f.sf.UpdateScrollBar()
end

-- For the tests (tests/test_profiles.lua): the profile functions above are local, and
-- the tests call them the way the Profiles page's buttons do.
ns._test = { DEFS = DEFS, newProfile = newProfile, renameProfile = renameProfile, deleteProfile = deleteProfile,
  resetProfile = resetProfile, exportProfile = exportProfile, importProfile = importProfile, useProfile = useProfile }
