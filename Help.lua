local _, ns = ...

---------------------------------------------------------------------------
-- Help: every feature at a high level, shown in the Help tab. The same text is in
-- docs/GUIDE.md on GitHub (with pictures); keep the two in step when features change.
-- Also: a one-time question for players who run TSM or Auctionator, whose tooltips
-- already show prices, offering the one-line tooltip.
---------------------------------------------------------------------------
-- Each section: { title, { { topic, text }, ... } }.
ns.HELP = {
  { "Getting started", {
    { "Open this window", "Type /fl, or click the minimap button." },
    { "Learn your recipes", "Open each profession window once on every character." },
    { "Price everything", "At the auction house, click Full scan (allowed about every 15 minutes)." },
    { "Tooltips", "Hover any item to see what it's worth to you. Settings can make it one line, with Shift for more." },
  } },
  { "Scanning the auction house", {
    { "Full scan", "Reads every listing in a few seconds." },
    { "Scan materials", "Checks just what your recipes use." },
    { "Watch flips", "On the auction house: keeps scanning while it stays open and chimes when a new vendor flip turns up. An eye on the button shows it's running." },
    { "Other addons", "If Auctionator or another addon runs a full scan, Forever Ledger reads it too." },
    { "Neutral auction houses", "Booty Bay, Gadgetzan and Everlook keep their own prices." },
  } },
  { "Tooltips", {
    { "Worth to you", "The best of selling on the auction house, selling to a vendor, disenchanting, or crafting it into something, with the best few ways listed." },
    { "Buy at or below", "The most worth paying, after your safety margin. Green when it's already cheaper." },
    { "Also", "Disenchant results, which of your recipes use it, and the cheapest crate fill." },
    { "Gear versions", "Gear with random stats (of the Eagle) also shows the price of that exact version." },
  } },
  { "Shuffles and vendor flips", {
    { "Shuffles", "Buy materials, craft, disenchant or convert, and sell, ranked by profit per hour. Click a row for every step; Work it walks you through them with one-click buttons." },
    { "Vendor flips", "Things on the auction house for less than a vendor pays. After a scan finds some, the tab opens by itself; click a flip to search for it." },
    { "On the auction house", "Listings worth buying get a green bar and a badge saying why (FLIP, DE, CRAFT, USE), and the line above says how many are left." },
  } },
  { "Deals", {
    { "Deals tab", "Listings well below their usual price, to buy and resell: price now, usual price, how many are cheap, profit after the auction house cut, and how sure it is (Good, Fair or Thin)." },
    { "Why it's a deal", "Hover a deal: the usual price and how many days of your scans it comes from, the range most days, how many are usually listed, and the next listing up (reselling today means pricing under it). Click to search the auction house." },
    { "Gone per day", "How many reasonably priced listings disappeared between full scans (mostly bought, some expired): a rough sell speed. Keep the flip watch running to collect it; deals where nothing moved in 6 hours are marked less sure." },
    { "How sure", "Deals need at least 4 days of scans (or TSM). Thin data (few days, jumpy prices, usually only one listed) is hidden unless you tick Show thin data too." },
    { "Keep in mind", "The auction house can't tell what actually sold. Buy what you'd be happy to hold for a while." },
  } },
  { "Disenchanting", {
    { "Disenchant finder", "Beside the auction house: green armor and weapons by item level, with what each is worth to disenchant. Hover a band for the odds." },
    { "Work it", "The Disenchant button disenchants the shuffle's items one click at a time. /fl de shows your own results." },
  } },
  { "Recipes and trainers", {
    { "Recipes tab", "Every recipe of your professions, who knows it, where to get it, the skill needed, and profit per craft. Right-click a recipe to set its type yourself." },
    { "Types", "Flip or shuffle, Crafts that sell, Enchant service, Not for sale, Not profitable." },
    { "Where from", "What you've seen in game first, otherwise original Classic data marked (Classic), or the auction house when its recipe item is listed there. Pin puts a map pin on the vendor, trainer or mob." },
    { "Trainers view", "Trainers you've visited, Classic ones, and spots city guards mark when you ask them for a profession trainer (marked guard)." },
  } },
  { "Waylaid Crates", {
    { "Crates tab", "The cheapest way to fill each crate at today's prices, with the crate's own price and gold per Merchant's Favor. Click a crate for every bundle and what you already have." },
  } },
  { "Customers and work", {
    { "Customers window", "Opens when someone in chat asks for what your character can do, with Whisper and Invite buttons. /fl customers opens it any time." },
    { "Class services", "The finder also spots requests for Mage food, water and portals (portals from level 40), Warlock summons (from 20) and Rogue lockpicking (from 16), on those classes. Settings, Customers turns each one (and crafting) on or off." },
    { "Ads", "Post your crafting (with profession links) to Trade, and on those classes your food and water, portals, summons or lockpicking. Right-click a button to change the text." },
    { "Work done", "Enchants and paid trades, with today's and this week's earnings. /fl work." },
  } },
  { "Your gold", {
    { "Dashboard", "Gold over time, sales, expenses and profit, and your sessions." },
    { "Ledger", "Every sale and purchase, resale profit, and other money like repairs and flights." },
  } },
  { "Sharing between accounts", {
    { "Live sync", "/fl pair First Last sends prices and recipes between your two accounts while both are online." },
    { "Export and import", "On the Characters tab, to copy everything across by hand." },
  } },
  { "Commands", {
    { "/fl", "Open or close the window." },
    { "/fl scan", "Full scan or materials." },
    { "/fl watch", "Flip watch." },
    { "/fl deals", "The Deals tab (/fl deals list in chat)." },
    { "/fl customers, /fl work", "The Customers window." },
    { "/fl de", "Your disenchant results." },
    { "/fl book", "Recipe data gathered." },
    { "/fl sync", "Sync status." },
    { "/fl perf, /fl probe", "What takes time; game checks." },
  } },
}

---------------------------------------------------------------------------
-- The Help tab, laid out like Settings: a header band per section, each topic on
-- the left with its text beside it, and a faint line between topics.
---------------------------------------------------------------------------
local TOPIC_W = 170
local hv

function ns:BuildHelp(parent)
  local T = ns.Theme
  local sf, content = T:Scroll(parent)
  sf:SetAllPoints()
  hv = { sf = sf, content = content, parts = {} }
  local function add(kind, obj) hv.parts[#hv.parts + 1] = { kind = kind, obj = obj } end

  local intro = T:Text(content, 11, T.dim)
  intro:SetJustifyH("LEFT")
  intro:SetText("Everything Forever Ledger does, in short. The full guide with pictures is docs/GUIDE.md on the addon's GitHub page.")
  add("intro", intro)
  for _, section in ipairs(ns.HELP) do
    local band = content:CreateTexture(nil, "BACKGROUND")
    band:SetColorTexture(1, 1, 1, 0.05)
    local h = T:Text(content, 13, T.accent)
    h:SetText(section[1])
    add("band", { band = band, text = h })
    for _, entry in ipairs(section[2]) do
      local topic = T:Text(content, 12)
      topic:SetJustifyH("LEFT")
      topic:SetText(entry[1])
      local text = T:Text(content, 12, T.dim)
      text:SetJustifyH("LEFT")
      text:SetText(entry[2])
      local line = content:CreateTexture(nil, "BACKGROUND")
      line:SetColorTexture(1, 1, 1, 0.04)
      line:SetHeight(1)
      add("entry", { topic = topic, text = text, line = line })
    end
  end
  return sf
end

-- Positions everything for the current width (text heights depend on it).
function ns:RefreshHelp()
  if not hv then return end
  local width = math.max(hv.sf:GetWidth() - 12, 300)
  hv.content:SetWidth(width)
  local y = 0
  for _, p in ipairs(hv.parts) do
    local o = p.obj
    if p.kind == "intro" then
      o:ClearAllPoints()
      o:SetPoint("TOPLEFT", 4, -2)
      o:SetWidth(width - 8)
      y = o:GetStringHeight() + 12
    elseif p.kind == "band" then
      y = y + 8
      o.band:ClearAllPoints()
      o.band:SetPoint("TOPLEFT", 0, -y)
      o.band:SetPoint("RIGHT", hv.content, "RIGHT", -4, 0)
      o.band:SetHeight(24)
      o.text:ClearAllPoints()
      o.text:SetPoint("LEFT", o.band, "LEFT", 8, 0)
      y = y + 30
    else
      o.topic:ClearAllPoints()
      o.topic:SetPoint("TOPLEFT", 12, -y)
      o.topic:SetWidth(TOPIC_W - 16)
      o.text:ClearAllPoints()
      o.text:SetPoint("TOPLEFT", TOPIC_W, -y)
      o.text:SetWidth(width - TOPIC_W - 12)
      y = y + math.max(o.topic:GetStringHeight(), o.text:GetStringHeight()) + 10
      o.line:ClearAllPoints()
      o.line:SetPoint("TOPLEFT", 8, -(y - 5))
      o.line:SetPoint("RIGHT", hv.content, "RIGHT", -8, 0)
    end
  end
  hv.content:SetHeight(y + 10)
  hv.sf.UpdateScrollBar()
end

---------------------------------------------------------------------------
-- One-time tooltip question for TSM / Auctionator users
---------------------------------------------------------------------------
local function otherAuctionAddon()
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if Auctionator or (isLoaded and isLoaded("Auctionator")) then return "Auctionator" end
  if TSM_API or (isLoaded and isLoaded("TradeSkillMaster")) then return "TradeSkillMaster" end
end

StaticPopupDialogs["FOREVER_LEDGER_TOOLTIP_SIZE"] = {
  text = "Forever Ledger adds lines to item tooltips: what an item is worth to you (sell, disenchant or craft), the most worth paying, and which of your recipes use it.\n\n%s already shows prices there too. Keep everything, or show one line and hold Shift for the rest?\n\n(You can change this any time in Settings.)",
  button1 = "One line, Shift for more",
  button2 = "Keep everything",
  OnAccept = function() ns.db.settings.tipMode = "compact"; ns.db.settings.tipAsked = true end,
  OnCancel = function() ns.db.settings.tipAsked = true end,
  timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
}

ns:On("PLAYER_ENTERING_WORLD", function()
  C_Timer.After(10, function()
    if not ns.db or ns.db.settings.tipAsked then return end
    local other = otherAuctionAddon()
    if other then StaticPopup_Show("FOREVER_LEDGER_TOOLTIP_SIZE", other) end
  end)
end)
