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
    { "Other addons", "If Auctionator or another addon runs a full scan, Forever Ledger reads it too. With Auctionator or TSM installed, features they already cover (like auction prices in tooltips) are switched off once, with a message; turn them back on in Settings." },
    { "Neutral auction houses", "Booty Bay, Gadgetzan and Everlook keep their own prices." },
  } },
  { "Tooltips", {
    { "Worth to you", "The best of selling on the auction house, selling to a vendor, disenchanting, or crafting it into something, with the best few ways listed." },
    { "Buy at or below", "The most worth paying, after your safety margin. Green when it's already cheaper." },
    { "Also", "Disenchant results, which of your recipes use it, and the cheapest crate fill." },
    { "Gear versions", "Gear with random stats (of the Eagle) also shows the price of that exact version." },
    { "Sells", "How fast an item sells: Fast, Steady, Slow, Rare (seldom listed, goes quickly) or No sales seen, judged against items of the same kind, so ore and swords aren't held to the same bar. It counts listings that vanished before they could have expired, so it builds up as you run full scans (fastest with Watch flips) and shows after 3 hours of scans compared (and, in the first day, at least 3 sales)." },
  } },
  { "Shuffles and vendor flips", {
    { "Shuffles", "Buy materials, craft, disenchant or convert, and sell, ranked by profit per hour. Click a row for every step; Work it walks you through them with one-click buttons." },
    { "Vendor flips", "Things on the auction house for less than a vendor pays. They're in the Buy queue beside the auction house (tick Vendor flips there); a full scan that finds some opens it if it's closed, and the flip watch chimes. Settings, Vendor flips sets the least profit worth your time, as a share of the vendor price and as an amount." },
    { "On the auction house", "Listings worth buying get a green bar and a badge saying why (FLIP, DE, CRAFT, USE), and the line above says how many are left." },
  } },
  { "Buy queue and shopping lists", {
    { "Buy queue", "Click Buy queue on the auction house: a panel beside it lines up vendor flips and your shopping lists. Click a section to buy from it; it finds the next one by itself, and a click on Buy (or, with Scroll to buy ticked, a tick of the mouse wheel down over its top strip) buys it. Stacks of materials take a second tick to confirm the final price. /fl queue." },
    { "Sections", "Vendor flips and Shopping lists are each a section, stacked when both are ticked (a lone section gets a big strip to scroll over). Only the section you click (bright border, \"buying from this one\") looks things up and buys; the others just show what the last scan found. A lone flips section starts by itself; shopping lists never do. Scans and the flip watch add to the sections but never switch which one you're buying from." },
    { "Safe by design", "It never pays more than the limit shown (checked again on the final price) or more than you have, and every purchase is your own tick or click, as Blizzard requires. Scroll to buy starts off. Right-click an item to skip it." },
    { "Shopping lists", "Named lists of items with the most you'd pay and how many you want to have, for example raid consumables or twink gear. Pick a list from the dropdown at the top. With the list open, shift-click an item to add it (or drag it, or type its name). Every list ticked Use in the buy queue feeds it at once. Open them anywhere, to plan before you go to the auction house: the Shopping lists button at the top of this window, Shift-click on the minimap button, or /fl lists." },
    { "Want means", "Each list chooses. Keep this many: Want is how many you want to have (bags, bank and mail count); Buy again tops you back up after you use some, for raid consumables. Buy this many: Want is how many to buy, whatever you have; the Bought column counts purchases since Buy again, and Buy again buys the whole amount again." },
    { "Done or not", "Have turns green when you have your Want (1 if no number), counting bags and bank; materials turn green when you have enough to craft. The list's name shows how many are done (3/5), and the bottom line says Complete when you have everything. Done items stay done (saved) even after you use some, so the queue doesn't refill them; click Buy again to start the list over next raid." },
    { "Share and import", "Share copies a list as plain text to paste in Discord or send a friend; Import reads it back (or a plain list of item names, item numbers or Wowhead links, one per line). Imports never change your own lists." },
    { "Prices", "Type a price any way: 2g 50s, 1.5g, 25s, 75c, or a plain number for gold; it's tidied up when you press Enter, and a tip shows what it will be. Type any for any price, or tick Any price for the whole list (raid prep): the queue then buys the cheapest until you have what you want, never more than 3 times the usual price." },
    { "Buy or craft", "Set an item to Craft and the list shows the materials for the number you want, less what you have, with the most to pay for each (your usual price unless you type one). Materials a vendor sells are marked vendor." },
    { "Search and buy", "Search list checks everything on it in one click. Items and materials at or under your price join the buy queue; the rest wait at its bottom, greyed. Typing a name suggests items (Enter takes the top one), even ones the game hasn't loaded yet. Hover Have for bags, bank and other characters." },
  } },
  { "Deals", {
    { "Deals tab", "Listings well below the price an item is usually cheapest at, to buy and resell: price now, usual low, how many are worth buying, profit after the auction house cut, and how sure it is (Good, Fair or Thin)." },
    { "Why it's a deal", "Hover a deal: the usual cheapest and typical prices and how many days of your scans they come from, how many are usually listed, and the next listing up. Profit assumes you resell at the usual cheapest price or just under the next listing, whichever is lower. Click to search the auction house." },
    { "Filter", "All, Materials, Gear or Other, and a search box for names." },
    { "How sure", "When most of what's listed is that cheap, the price has dropped and it's no bargain: rated Thin. Deals need at least 4 days of scans (or TSM). Thin data (few days, jumpy prices, usually only one listed) is hidden unless you tick Show thin data too." },
    { "Keep in mind", "The auction house can't tell what actually sold. Buy what you'd be happy to hold for a while." },
  } },
  { "Disenchanting", {
    { "Disenchant finder", "Beside the auction house (Buy queue button, Disenchant finder tab): green armor and weapons by item level, with what each is worth to disenchant. Hover a band for the odds." },
    { "Work it", "The Disenchant button disenchants the shuffle's items one click at a time. /fl de shows your own results." },
  } },
  { "Recipes and trainers", {
    { "Recipes tab", "Every recipe of your professions, who knows it, where to get it, the skill needed, and profit per craft. Right-click a recipe to set its type yourself." },
    { "Types", "Flip or shuffle, Crafts that sell, Enchant service, Not for sale, Not profitable." },
    { "Where from", "What you've seen in game first, otherwise original Classic data marked (Classic), or the auction house when its recipe item is listed there. Pin puts a map pin on the vendor, trainer or mob." },
    { "Trainers view", "Trainers you've visited, Classic ones, and spots city guards mark when you ask them for a profession trainer (marked guard)." },
  } },
  { "Waylaid Crates", {
    { "Crates tab", "The cheapest way to fill each crate at today's prices, with the crate's own price, the money the turn-in pays back, and gold per Merchant's Favor. A crate that pays back more than it costs shows its profit in green. Click a crate for every bundle and what you already have." },
    { "Shopping list for a crate", "Open a crate and click Add cheapest fill to a shopping list: its items go on a list named after the crate, set to keep that many (what's in your bags and bank counts), with prices high enough to buy them all at your last scan. Tick Use in the buy queue on that list to buy what you're short. The list is temporary: it goes when you turn that crate in, or after a week." },
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
    { "How long it's kept", "Sales and purchases one by one for 30 days, then as one line per item per month for a year. Gold and money in and out per day for a year, then per month. Prices per day for 14 days, then weekly averages for a year. Recipes, vendors, items and your characters are kept for good. Nothing is lost at a reload: only data past these ages is summed up or dropped." },
  } },
  { "Sharing between accounts", {
    { "Live sync", "/fl pair First Last sends prices and recipes between your two accounts while both are online." },
    { "Export and import", "On the Characters tab, to copy everything across by hand." },
  } },
  { "Help and community", {
    { "Discord", "discord.gg/WKsCtvupeC: updates, questions, and WoW Forever news." },
    { "Found a bug?", "Type /bug on the Discord and fill in the short form. Include /fl api output or the BugSack error if you can." },
    { "Have an idea?", "Type /feature on the Discord. You'll get updates in your post." },
  } },
  { "Your data", {
    { "Stays on your PC", "Everything Forever Ledger records is kept in its saved file on your computer. Nothing is sent to the author or anyone else." },
    { "What it keeps", "Prices and their history, vendor and trainer locations you've seen, your characters' recipes, gold, sales and purchases, bags and bank, chat requests it spotted, and your work log." },
    { "What it sends", "Only live sync to your own paired character (off until /fl pair), and ads in Trade when you click an ad button." },
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
-- Playing nice with Auctionator and TSM (owner, October 1): features they already
-- cover are switched off the first time each is found, with a one-time message
-- saying what was turned off and where to turn it back on. Every new feature that
-- overlaps one of them gets an entry here (its setting, its name in the message, and
-- which addons cover it).
---------------------------------------------------------------------------
local AUCTION_ADDONS = {
  { name = "Auctionator", global = "Auctionator" },
  { name = "TradeSkillMaster", short = "TSM", global = "TSM_API" },
}
ns.OVERLAPS = {
  { setting = "tipPrice", label = "Auction and vendor prices in tooltips", addons = { Auctionator = true, TradeSkillMaster = true } },
}

local function loaded(a)
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  return _G[a.global] ~= nil or (isLoaded and isLoaded(a.name))
end

StaticPopupDialogs["FOREVER_LEDGER_OVERLAP"] = {
  text = "%s",
  button1 = OKAY or "OK",
  button2 = "Keep them on",
  OnCancel = function(_, turnedOff)
    for _, key in ipairs(turnedOff or {}) do ns.db.settings[key] = true end
    ns:Print("Kept them on. You can change this any time in Settings.")
  end,
  timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
}

ns:On("PLAYER_ENTERING_WORLD", function()
  C_Timer.After(10, function()
    if not ns.db then return end
    local s = ns.db.settings
    s.overlapSeen = s.overlapSeen or {}
    local found, names, turnedOff = {}, {}, {}
    for _, a in ipairs(AUCTION_ADDONS) do
      if loaded(a) and not s.overlapSeen[a.name] then
        s.overlapSeen[a.name] = true
        found[a.name] = true
        names[#names + 1] = a.short or a.name
      end
    end
    if #names == 0 then return end
    -- The old tooltip question (before October 1) is covered by this one.
    s.tipAsked = true
    local lines = {}
    for _, o in ipairs(ns.OVERLAPS) do
      local covered
      for name in pairs(found) do if o.addons[name] then covered = true end end
      if covered and s[o.setting] ~= false then
        s[o.setting] = false
        turnedOff[#turnedOff + 1] = o.setting
        lines[#lines + 1] = "- " .. o.label
      end
    end
    if #turnedOff == 0 then return end
    local text = ("%s is installed. So you don't see things twice, Forever Ledger turned off:\n\n%s\n\nEverything else stays on. You can turn these back on any time in Settings."):format(
      table.concat(names, " and "), table.concat(lines, "\n"))
    local dialog = StaticPopup_Show("FOREVER_LEDGER_OVERLAP", text)
    if dialog then dialog.data = turnedOff end
  end)
end)
