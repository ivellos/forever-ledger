local _, ns = ...

---------------------------------------------------------------------------
-- Help: every feature at a high level, shown in the Help tab. The same text is in
-- docs/GUIDE.md on GitHub (with pictures); keep the two in step when features change.
-- Also: a one-time question for players who run TSM or Auctionator, whose tooltips
-- already show prices, offering the one-line tooltip.
---------------------------------------------------------------------------
ns.HELP = {
  { "Getting started", {
    "Type /fl (or click the minimap button) to open this window.",
    "Open each profession window once on every character, so the addon learns your recipes.",
    "At the auction house, click Full scan (allowed about every 15 minutes) to price everything.",
    "Hover any item: the tooltip shows what it's worth to you. Settings can make it one line, with Shift for more.",
  } },
  { "Scanning the auction house", {
    "Full scan reads every listing in a few seconds. Scan materials checks just what your recipes use.",
    "Watch flips (on the auction house) keeps scanning while the auction house stays open and chimes when a new vendor flip turns up. An eye on the button shows it's running.",
    "If Auctionator or another addon runs a full scan, Forever Ledger reads it too.",
    "Neutral auction houses (Booty Bay, Gadgetzan, Everlook) keep their own prices.",
  } },
  { "Tooltips", {
    "Worth to you: the best of selling on the auction house, selling to a vendor, disenchanting, or crafting it into something, with the best few ways listed.",
    "Buy at or below: the most worth paying, after your safety margin. Green when it's already cheaper.",
    "Also: disenchant results, which of your recipes use it, and the cheapest crate fill. Gear with random stats (of the Eagle) also shows the price of that exact version.",
  } },
  { "Shuffles and vendor flips", {
    "Shuffles: buy materials, craft, disenchant or convert, and sell, ranked by profit per hour. Click a row for every step; Work it walks you through them with one-click buttons.",
    "Vendor flips: things on the auction house for less than a vendor pays. After a scan finds some, the tab opens by itself; click a flip to search for it. On the auction house, listings worth buying get a green bar and a BUY badge, and the line above says how many are left.",
  } },
  { "Disenchanting", {
    "Disenchant finder (beside the auction house): green armor and weapons by item level, with what each is worth to disenchant. Hover a band for the odds.",
    "The Disenchant button in Work it disenchants the shuffle's items one click at a time. /fl de shows your own results.",
  } },
  { "Recipes and trainers", {
    "Recipes tab: every recipe of your professions, who knows it, where to get it, the skill needed, and profit per craft. Types: Flip or shuffle, Crafts that sell, Enchant service, Not for sale, Not profitable. Right-click to set your own.",
    "Where from: what you've seen in game first, otherwise original Classic data marked (Classic), or the auction house when its recipe item is listed there. Pin puts a map pin on the vendor, trainer or mob.",
    "Trainers view: trainers you've visited, Classic ones, and spots city guards mark when you ask them for a profession trainer (marked guard).",
  } },
  { "Waylaid Crates", {
    "Crates tab: the cheapest way to fill each crate at today's prices, with the crate's own price and gold per Merchant's Favor. Click a crate for every bundle and what you already have.",
  } },
  { "Customers and work", {
    "Customers window (/fl customers): opens when someone in chat asks for what your character can do, with Whisper and Invite buttons.",
    "Ad buttons post your crafting (with profession links) or, on a Mage, food and water (with links) to Trade. Right-click to change the text.",
    "Work done (/fl work): enchants and paid trades, with today's and this week's earnings.",
  } },
  { "Your gold", {
    "Dashboard: gold over time, sales, expenses and profit, and your sessions.",
    "Ledger: every sale and purchase, resale profit, and other money like repairs and flights.",
  } },
  { "Sharing between accounts", {
    "Live sync (/fl pair First Last) sends prices and recipes between your two accounts while both are online. Export and import work too.",
  } },
  { "Commands", {
    "/fl  open or close the window.   /fl scan  full scan or materials.   /fl watch  flip watch.",
    "/fl customers, /fl work  the Customers window.   /fl de  disenchant results.   /fl deals  current deals.",
    "/fl book  recipe data gathered.   /fl sync  sync status.   /fl perf  what takes time.   /fl probe  game checks.",
  } },
}

-- The Help tab's text (UI.lua shows it like the Characters tab).
function ns.HelpText(add, heading, dim)
  add(dim("Everything Forever Ledger does, in short. The full guide with pictures is docs/GUIDE.md on the addon's GitHub page."))
  for _, section in ipairs(ns.HELP) do
    add("")
    add(heading(section[1]))
    for _, line in ipairs(section[2]) do add("  " .. line) end
  end
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
