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
    { "Search", "Settings and Help each have a search box above their list: type two letters or more to see everything that mentions it, from every section at once." },
    { "Settings per character", "Tick Just for this character under the Settings sections and that character gets its own settings (a copy to start): say no tooltips on one, no customer finder on another. Price and deal rules stay the same everywhere and say (all characters)." },
    { "Welcome", "The first time you open the window, a short welcome lists the five things to start with. Show it again with the button under the list of topics, or /fl welcome." },
    { "What's new", "After an update, chat lists what's new in that version, once. /fl new shows it again." },
  } },
  { "Auction house scans", {
    { "Full scan", "Reads every listing in a few seconds." },
    { "Scan materials", "Checks just what your recipes use." },
    { "Watch flips", "On the auction house: keeps scanning while it stays open and chimes when a new vendor flip turns up. It can only scan with the auction house open: it pauses when you close it and picks up again when you come back (Settings, Auction house: Resume the flip watch)." },
    { "Other addons", "If Auctionator or another addon runs a full scan, Forever Ledger reads it too. With Auctionator, TSM or ForeverForge installed, features they already cover (like auction prices in tooltips, or a sound when an auction sells) are switched off once, with a message; turn them back on in Settings." },
    { "Your auctions", "The Auctions tab beside the auction house: All, Up, Undercut and Sold, like the Ledger. Each auction shows how many, your price each, the cheapest now, and undercut (red) or cheapest (green); sold ones show what you get after the cut and when the gold reaches your mailbox. The bottom line says what gold is on the way and what's waiting in your mailbox. Check prices looks them all up; scans and the flip watch check them too, and an undercut gets a chat line and a sound (Settings, Auction house). Cancel next undercut asks once, then each click cancels the next one (each loses its deposit). Opening the auction house says in chat what sold while you were away and the gold it brings (Settings, Auction house)." },
    { "Sale sound", "A coin sound when one of your auctions sells. Settings, Auction house: Sound when an auction sells." },
    { "Neutral auction houses", "Booty Bay, Gadgetzan and Everlook keep their own prices." },
    { "Price helper", "On the Sell tab, under the Create Auction button: your usual price and the cheapest now, with Undercut (1 copper under the cheapest) and Usual buttons that fill in the price. When the cheapest is well below usual it says so, so you can wait. You still click Post (Settings, Auction house)." },
    { "Sell protection", "On the Sell tab, if a vendor pays more than your listing would bring after the auction house cut, a red line under Post says so and Post is greyed out until you click Post anyway. Settings, Auction house: untick Stop posts below vendor price to keep just the warning." },
  } },
  { "Tooltips", {
    { "Auction price", "Auction, cheapest: the lowest price listed at your last scan, how many were listed, and (in grey) how long ago. Under it, when different: the average of the 20 cheapest, about what you'd pay buying a few. Values in Forever Ledger use that average, so one odd cheap listing doesn't sway them. With your own prices over 12 hours old, Auctionator's or TSM's price is used if you have them, and named." },
    { "Worth to you", "The best of selling on the auction house, selling to a vendor, disenchanting, or crafting it into something, with the best few ways listed." },
    { "Buy at or below", "The most worth paying, after your safety margin. Green when it's already cheaper." },
    { "Also", "Disenchant results, which of your recipes use it, and the cheapest crate fill." },
    { "Gear versions", "Gear with random stats (of the Eagle) also shows the price of that exact version." },
    { "Price history", "Hold Ctrl over an item: the cheapest price over the last 14 days, whether it's rising or falling, the usual price this month, how many are usually listed and the lowest price ever seen. It builds up with each scan." },
    { "Quests", "Items quests ask for (Bronze Tube, Spider Ichor, Flask of Oil...) list the quest, its level and how many, for your faction. In yellow with keep it when this character hasn't reached that level yet, so you don't vendor it. Quests this character has done, ones grey for its level and other classes' quests are left out (Settings, Tooltips: Only quests this character still needs; off shows them all, marked). Leveling players buy these once per character, so they sell; the Deals tab's hover says when a deal is one. From original Classic quests: Forever may have changed some." },
    { "Sells", "How fast an item sells: Fast, Steady, Slow, Rare (seldom listed, goes quickly) or No sales seen, judged against items of the same kind, so ore and swords aren't held to the same bar. It counts listings that vanished before they could have expired, so it builds up as you run full scans (fastest with Watch flips) and shows after 3 hours of scans compared (and, in the first day, at least 3 sales)." },
  } },
  { "Shuffles and vendor flips", {
    { "Shuffles", "Buy materials, craft, disenchant or convert, and sell, ranked by profit per hour. Click a row for every step." },
    { "Vendor flips", "Things on the auction house for less than a vendor pays. They're in the Buy queue beside the auction house (its Vendor flips view); a full scan that finds some opens it if it's closed, and the flip watch chimes. Settings, Vendor flips sets the least profit worth your time, as a share of the vendor price and as an amount." },
    { "On the auction house", "Listings worth buying get a green bar and a badge saying why (FLIP, DE, CRAFT, USE), and the line above says how many are left." },
  } },
  { "Buy queue and lists", {
    { "Buy queue", "Click Buy queue on the auction house: a panel beside it lines up vendor flips and your shopping lists. Click a section to buy from it; it finds the next one by itself, and a click on Buy (or, with Scroll to buy ticked, a tick of the mouse wheel down over its top strip) buys it. Stacks of materials take a second tick to confirm the final price. /fl queue." },
    { "Scanning from the panel", "The panel's bottom row has Watch flips, Full scan and Scan materials (Stop watching and Stop scan while they run), with the scan's progress just above. While the panel is open beside the auction house, the same buttons under the auction house window are hidden. With nothing to buy, the big button starts the flip watch." },
    { "Two views", "Vendor flips or Shopping lists, switched at the top of the panel, one at a time; the one you're on is the one that buys, so a list never buys a flip by accident. Each has its own buttons at the bottom. With Scroll to buy ticked, the strip to scroll over glows (teal for Vendor flips, purple for Shopping lists) and shows a mouse wheel. Scans and the flip watch add to the lists but never switch the view; new flips found while you're on Shopping lists show a teal count on the Vendor flips button (and on the Buy queue tab)." },
    { "Safe by design", "It never pays more than the limit shown (checked again on the final price) or more than you have, and every purchase is your own tick or click, as Blizzard requires. Scroll to buy starts off. Right-click an item to skip it. Items you can't afford yet stay at the bottom of the list, greyed and marked can't afford, and are skipped until you have the gold; scroll past the last one you can buy and you get the error sound and a red message, once." },
    { "Spend at most", "The box near the bottom of the Buy queue caps what it spends this auction house visit (type 50 for 50g; it starts again each time you open the auction house). No limit until you type one; what's left shows beside it. Items over it are marked over limit and skipped. To always keep some gold back for repairs or a mount: Settings, Auction house, Buy queue: always keep." },
    { "Shopping lists", "Named lists of items, for example twink gear to watch for or raid consumables to buy. Pick a list from the dropdown at the top; New, Rename and Delete are beside it. With the list open, shift-click an item to add it (or drag it, or type its name: names are suggested as you type, Enter takes the top one). Open them anywhere, to plan before you go to the auction house: the Shopping lists button at the top of this window, Shift-click on the minimap button, or /fl lists." },
    { "Search all", "Checks the auction house for everything on the list at once. Each item shows when it was checked (checking... and in line while it runs), how many are listed and the cheapest. Click an item to look at it on the auction house." },
    { "Have", "What you own of each item: this character's bags, bank and auction house purchases still in the mail, and your characters on this ruleset and faction. On a list you buy from it reads 3 (20): 3 bought for the list, 20 owned. Hover the number to see where. It's there to know, it doesn't change what's bought." },
    { "Buying from a list", "Tick Buy from this list in the Buy queue: the list adds Want (how many to buy) and Up to (the most you'll pay for one: filled in with your usual price when you tick it or add an item, change it any time; off means don't buy it), and the Buy queue's Shopping lists view buys them. Want is how many to buy, whatever you already have; Have shows how many are bought so far. It never buys more than Want. An item is done once its Want is bought, and stays done; Buy again (bottom right) starts the list over. The bottom line says about what buying the rest would cost." },
    { "Prices", "Type a price any way: 2g 50s 25c, 2 50 25 or 2.50.25 (gold silver copper), 2 50 (gold silver), 25s, 75c, or a plain number for gold; it's tidied up when you press Enter, and a tip shows what it will be. Type any for any price, or tick Any price (bottom of the list) for the whole list (raid prep): the queue then buys the cheapest until it has bought what you want, never more than 3 times the usual price." },
    { "Buy or craft", "Items one of your recipes makes have a Buy/Craft button: set Craft and the list shows the materials for the number you want, with Up to for each (your usual price unless you type one) and how many are bought. Materials a vendor sells are marked vendor. Hover an item one of your recipes makes: what buying it would cost against buying the materials to craft it, and which is cheaper." },
    { "One version", "Type \"Soldier's Armor of the Monkey\", or shift-click a link of that version, to keep just that version on a list. Search all looks up every version of gear; hover an item for each version's price, yours first." },
    { "Share and import", "Share / import (top right of the list) opens a window with two tabs. Share copies a list as plain text to paste in Discord or send a friend; Import reads it back (or a plain list of item names, item numbers or Wowhead links, one per line). Imports never change your own lists, and never buy by themselves: tick Buy from this list to buy from one." },
  } },
  { "Deals", {
    { "Deals tab", "Listings well below the price an item is usually cheapest at, to buy and resell: price now, usual low, how many are worth buying, profit after the auction house cut, and how sure it is (Good, Fair or Thin)." },
    { "Why it's a deal", "Hover a deal: the usual cheapest and typical prices and how many days of your scans they come from, how many are usually listed, and the next listing up. Profit assumes you resell at the usual cheapest price or just under the next listing, whichever is lower. Click to search the auction house." },
    { "Filter", "All, Materials, Gear or Other, and a search box for names." },
    { "How sure", "When most of what's listed is that cheap, the price has dropped and it's no bargain: rated Thin. Deals need at least 4 days of scans (or TSM). Thin data (few days, jumpy prices, usually only one listed) is hidden unless you tick Show thin data too." },
    { "Keep in mind", "The auction house can't tell what actually sold. Buy what you'd be happy to hold for a while." },
  } },
  { "Disenchanting", {
    { "Disenchant finder", "Beside the auction house (Buy queue button, Disenchant finder tab): green armor and weapons by item level, with what each is worth to disenchant, on average. Hover a band for the odds and what a bad and a good roll would bring (Settings, Auction house can hide the rolls)." },
  } },
  { "Recipes and trainers", {
    { "Recipes tab", "Every recipe of your professions, who knows it, where to get it, the skill needed, and profit per craft. Right-click a recipe to set its type yourself. Click a column heading to sort." },
    { "Types", "Flip or shuffle, Crafts that sell, Enchant service, Not for sale, Not profitable." },
    { "Where from", "What you've seen in game first, otherwise original Classic data marked (Classic), or the auction house when its recipe item is listed there. Pin puts a map pin on the vendor, trainer or mob." },
    { "Trainers view", "Trainers you've visited, Classic ones, and spots city guards mark when you ask them for a profession trainer (marked guard)." },
  } },
  { "Waylaid Crates", {
    { "Crates tab", "The cheapest way to fill each crate at today's prices, with the crate's own price and gold per Merchant's Favor. After your first turn-in (a one-time quest), every crate pays 5s and 10 Favor; Net cost takes the 5s off, and shows green if a crate somehow pays for itself. Click a crate for every bundle and what you already have." },
    { "Shopping list for a crate", "Open a crate and click Add cheapest fill to a shopping list: the crate and its items go on a list named after the crate, with prices high enough to buy them all at your last scan. What you already have counts towards a crate list's Want (only crate lists do this). Tick Buy from this list in the Buy queue on it to buy what you're short. Set the crate's Want to fill several at once: every item's Want follows it. The list is temporary: each crate you fill takes one off, and the list goes with the last one (or after a week)." },
  } },
  { "Customers and work", {
    { "Customers window", "Opens when someone in chat asks for what your character can do, with Whisper and Invite buttons. /fl customers opens it any time." },
    { "Silence", "The Silence button (bottom right of the Customers window) quiets the alerts: until you're next in a capital city, until you reload, until you log out, or always (that turns the finder off; Turn alerts back on, or /fl customers on, brings it back). While quiet, requests are still listed in the window, with no pop-up, sound or chat line." },
    { "Class services", "The finder also spots requests for Mage food, water and portals (portals from level 40), Warlock summons (from 20) and Rogue lockpicking (from 16), on those classes. Settings, Customers turns each one (and crafting) on or off." },
    { "Ads", "Post your crafting (with profession links) to Trade, and on those classes your food and water, portals, summons or lockpicking. Right-click a button to change the text." },
    { "Work done", "Enchants and paid trades, with today's and this week's earnings. /fl work." },
  } },
  { "Your gold", {
    { "Dashboard", "Gold over time, sales, expenses and profit, and your sessions." },
    { "Characters", "Your characters on this realm and faction down the left with their gold (the dropdown above them picks another realm or faction, both factions, or all realms). Pick one for its professions and what's in its bags and bank, each item with what it's worth to you (Each: the best of auction house, vendor, disenchanting or crafting) and the best way to get it; All characters adds everyone up. Hover an item for who has it, a character for gold and bags and bank worth, the bottom line for what it's made of. Bags as of each character's last login, bank as of the last bank visit." },
    { "Ledger", "All: every transaction in one list (auction and vendor sales and purchases, repairs, mail, loot, quests...), money in green and out in red. Sales, Purchases, Resale (profit on items bought and sold) and Other show one kind each. Filter by time, character or a word; click a heading to sort; hover a row for the details." },
    { "Totals of rows", "Select rows to see what they add up to: click one, Shift-click another for everything between, Ctrl-click to add or take one, or press and drag across rows. The bottom line shows the money in, out and net of the selection. Right-click a row or Clear selection to start again." },
    { "Sessions", "Start one (Start a session at the top of the Dashboard, Ctrl-click on the minimap button, or /fl session start) and a small tracker you can drag counts what your time is worth: gold an hour, gold in and out, and what you loot (at the better of auction and vendor price; Settings can make it vendor only). Right-click the tracker to fold it to one line. Stop it to get a summary in chat; it joins the Dashboard's sessions. A session carries on through a logout on the same character." },
    { "Dungeon runs", "Counted as you go, session or not: each dungeon's runs, time, coin and what dropped for you (going back in within 5 minutes is the same run). /fl runs lists them; item tooltips say \"Dropped for you: Deadmines, 2 in 14 runs\"." },
    { "How long it's kept", "Sales and purchases one by one for 30 days, then as one line per item per month for a year. Gold and money in and out per day for a year, then per month. Prices per day for 14 days, then weekly averages for a year. Recipes, vendors, items and your characters are kept for good. Nothing is lost at a reload: only data past these ages is summed up or dropped." },
  } },
  { "Two accounts", {
    { "Live sync", "/fl pair First Last sends prices and recipes between your two accounts while both are online." },
    { "Export and import", "Export / import on the Characters tab, to copy everything across by hand (and Prices as text)." },
  } },
  { "Help and community", {
    { "New versions", "When a guildmate or group member has a newer Forever Ledger, chat says so once a session, with where to update. Only the version number is shared (Settings, Other)." },
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
    { "/fl customers, /fl work", "The Customers window. /fl customers on or off turns the customer finder on or off." },
    { "/fl de", "Your disenchant results." },
    { "/fl book", "Recipe data gathered." },
    { "/fl sync", "Sync status." },
    { "/fl perf, /fl probe", "What takes time; game checks." },
  } },
}

---------------------------------------------------------------------------
-- Questions players asked, per Help section (owner, October 3: one page was getting
-- long, so Help is split into topics, each with its questions). Add new ones as players
-- ask them; keep the answers short. { question, answer }.
---------------------------------------------------------------------------
ns.HELP_FAQ = {
  ["Getting started"] = {
    { "Does it buy or sell anything by itself?", "No. Every purchase and auction is your own click (or wheel tick), as Blizzard requires. Forever Ledger finds, suggests and queues." },
    { "Why are some things empty on the first day?", "Prices and flips work from your first full scan. Deals and how fast things sell need a few days of scans to know what's usual." },
  },
  ["Auction house scans"] = {
    { "Why can't I run a full scan?", "The game allows one about every 15 minutes. The Full scan button counts down to the next." },
    { "Does Watch flips work with the auction house closed?", "No: the game only lets addons search with the auction house open. The watch pauses when you close it and picks up when you come back." },
    { "What are the 120 items the watch re-checks?", "Between full scans, the items whose price was closest to what a vendor pays: the likeliest to turn into flips when someone lists one cheap." },
  },
  ["Tooltips"] = {
    { "Why does it say none listed?", "Your last scan found none of that item on the auction house." },
  },
  ["Buy queue and lists"] = {
    { "Do I click the big button or a row?", "Either. The big button (or the wheel over its strip, with Scroll to buy ticked) buys the next one. Clicking a row buys that one next." },
    { "Why did items disappear from the queue?", "Someone else bought them first, or their price is too old: finds over 15 minutes old are left out until a scan finds them again. Items you can't afford stay at the bottom, marked." },
  },
  ["Deals"] = {
    { "Why are there no deals?", "A deal needs an item's usual price, so at least 4 days of your scans (or TSM). Keep scanning; they fill in." },
  },
}

---------------------------------------------------------------------------
-- The Help tab: a list of topics on the left, the chosen topic on the right (its
-- entries, then its questions). Opens on the first topic each time (owner, October 3:
-- no need to remember the last one; ns.helpTopic, set back by UI.lua's setView).
---------------------------------------------------------------------------
local TOPIC_W = 170
local NAV_W = 170
local hv

local function topicIndex()
  local want = ns.helpTopic
  for i, s in ipairs(ns.HELP) do if s[1] == want then return i end end
  return 1
end

function ns:BuildHelp(parent)
  local T = ns.Theme
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  hv = { frame = f, parts = {}, navButtons = {} }

  -- Search, from 2 letters: every entry and question with it, from all topics at once
  -- (owner's test, October 3). Clicking a topic clears it.
  local search = T:EditBox(f, NAV_W - 16, "LEFT")
  search:SetPoint("TOPLEFT", 0, 0)
  local hint = T:Text(search, 11, T.section)
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Search help")
  search:SetScript("OnTextChanged", function(self)
    hint:SetShown(self:GetText() == "" and not self:HasFocus())
    local q = self:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "")
    local new = #q >= 2 and q or nil
    if new ~= ns.helpQuery then
      ns.helpQuery = new
      ns:RefreshHelp()
      hv.sf:SetVerticalScroll(0)
    end
  end)
  search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  search:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  hv.search = search
  f.search = search   -- (UI.lua clears it when the tab is opened)

  -- Topics on the left (scrolls if the window is short).
  local navSf, nav = T:Scroll(f)
  navSf:SetPoint("TOPLEFT", 0, -30)
  navSf:SetPoint("BOTTOMLEFT", 0, 30)
  navSf:SetWidth(NAV_W)
  hv.navSf, hv.nav = navSf, nav
  for i, section in ipairs(ns.HELP) do
    local b = T:Button(nav, section[1], NAV_W - 16, function()
      ns.helpTopic = section[1]
      hv.search:SetText("")
      hv.search:ClearFocus()
      ns:RefreshHelp()
      hv.sf:SetVerticalScroll(0)
    end, 21)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 23)
    b:GetFontString():SetFont(T.font, 11, "")
    -- Never wider than the button, whatever the font (Magic, October 3: names ran out).
    b:GetFontString():SetWidth(NAV_W - 24)
    b:GetFontString():SetWordWrap(false)
    hv.navButtons[i] = b
  end
  nav:SetHeight(#ns.HELP * 23)
  -- The first-run welcome again (Welcome.lua).
  hv.welcome = T:Button(f, "Show the welcome again", NAV_W - 16, function()
    if ns.ShowWelcome then ns:ShowWelcome() end
  end, 22)
  hv.welcome:SetPoint("BOTTOMLEFT", 0, 2)

  -- The chosen topic.
  local sf, content = T:Scroll(f)
  sf:SetPoint("TOPLEFT", NAV_W + 4, 0)
  sf:SetPoint("BOTTOMRIGHT")
  hv.sf, hv.content = sf, content
  return f
end

-- Text pieces are reused between topics: get the i-th of a kind.
local function piece(kind, i, make)
  hv.pool = hv.pool or {}
  local list = hv.pool[kind] or {}
  hv.pool[kind] = list
  if not list[i] then list[i] = make() end
  return list[i]
end

-- Draws the chosen topic for the current width (text heights depend on it).
function ns:RefreshHelp()
  if not hv then return end
  local T = ns.Theme
  local cur = topicIndex()
  local q = ns.helpQuery
  for i, b in ipairs(hv.navButtons) do b:SetSelected(not q and i == cur) end
  hv.navSf.UpdateScrollBar()

  local section = ns.HELP[cur]
  local width = math.max(hv.sf:GetWidth() - 12, 280)
  hv.content:SetWidth(width)
  for _, list in pairs(hv.pool or {}) do for _, p in ipairs(list) do p:Hide() end end

  local y, nBand, nTopic, nText, nLine = 0, 0, 0, 0, 0
  local function band(title)
    nBand = nBand + 1
    local b = piece("band", nBand, function()
      local fr = CreateFrame("Frame", nil, hv.content)
      T:Fill(fr, { 1, 1, 1, 0.05 })
      fr.text = T:Text(fr, 13, T.accent)
      fr.text:SetPoint("LEFT", 8, 0)
      return fr
    end)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -y)
    b:SetPoint("RIGHT", hv.content, "RIGHT", -4, 0)
    b:SetHeight(24)
    b.text:SetText(title)
    b:Show()
    y = y + 30
  end
  local function entry(left, right, leftColor)
    nTopic, nText, nLine = nTopic + 1, nText + 1, nLine + 1
    local topic = piece("topic", nTopic, function()
      local fs = T:Text(hv.content, 12)
      fs:SetJustifyH("LEFT")
      return fs
    end)
    local text = piece("text", nText, function()
      local fs = T:Text(hv.content, 12, T.dim)
      fs:SetJustifyH("LEFT")
      return fs
    end)
    local line = piece("line", nLine, function()
      local tx = hv.content:CreateTexture(nil, "BACKGROUND")
      tx:SetColorTexture(1, 1, 1, 0.04)
      tx:SetHeight(1)
      return tx
    end)
    topic:SetText(left)
    local c = leftColor or { 1, 1, 1, 1 }
    topic:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    text:SetText(right)
    topic:ClearAllPoints()
    topic:SetPoint("TOPLEFT", 12, -y)
    topic:SetWidth(TOPIC_W - 16)
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", TOPIC_W, -y)
    text:SetWidth(width - TOPIC_W - 12)
    topic:Show()
    text:Show()
    y = y + math.max(topic:GetStringHeight(), text:GetStringHeight()) + 10
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 8, -(y - 5))
    line:SetPoint("RIGHT", hv.content, "RIGHT", -8, 0)
    line:Show()
  end

  if q then
    -- Searching: the matching entries and questions of every topic, under its name.
    local function hit(a, b) return (a or ""):lower():find(q, 1, true) or (b or ""):lower():find(q, 1, true) end
    local any = false
    for _, s in ipairs(ns.HELP) do
      local list = {}
      for _, e in ipairs(s[2]) do if hit(e[1], e[2]) then list[#list + 1] = { e[1], e[2] } end end
      for _, fq in ipairs(ns.HELP_FAQ[s[1]] or {}) do
        if hit(fq[1], fq[2]) then list[#list + 1] = { fq[1], fq[2], true } end
      end
      if #list > 0 then
        if any then y = y + 6 end
        any = true
        band(s[1])
        for _, e in ipairs(list) do entry(e[1], e[2], e[3] and T.accent or nil) end
      end
    end
    if not any then
      band("Nothing found")
      entry("Try another word", "Like price, flip, list, scan or sound. Or pick a topic on the left.")
    end
  else
    band(section[1])
    for _, e in ipairs(section[2]) do entry(e[1], e[2]) end
    local faq = ns.HELP_FAQ[section[1]]
    if faq and #faq > 0 then
      y = y + 6
      band("Questions")
      for _, fq in ipairs(faq) do entry(fq[1], fq[2], T.accent) end
    end
    if cur == 1 then
      y = y + 6
      band("More")
      entry("Full guide", "docs/GUIDE.md on the addon's GitHub page, with pictures.")
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
-- ForeverForge (owner, October 3): its Auction module shows prices in tooltips and its
-- core plays a sound when an auction sells. Its folder name isn't known for sure, so a
-- few likely ones are tried (alt).
local AUCTION_ADDONS = {
  { name = "Auctionator", global = "Auctionator" },
  { name = "TradeSkillMaster", short = "TSM", global = "TSM_API" },
  { name = "ForeverForge_Auction", short = "ForeverForge Auction", alt = { "ForeverForgeAuction", "ForeverForge-Auction" } },
  { name = "ForeverForge", alt = { "ForeverForge_Core" } },
}
ns.OVERLAPS = {
  { setting = "tipPrice", label = "Auction and vendor prices in tooltips",
    addons = { Auctionator = true, TradeSkillMaster = true, ForeverForge_Auction = true } },
  { setting = "saleSound", label = "A sound when an auction sells", addons = { ForeverForge = true } },
  { setting = "undercutAlerts", label = "Undercut alerts", addons = { Auctionator = true, TradeSkillMaster = true } },
  { setting = "priceHelper", label = "Price helper on the Sell tab", addons = { Auctionator = true, TradeSkillMaster = true } },
  { setting = "soldSummary", label = "What sold while you were away", addons = { TradeSkillMaster = true } },
}

local function loaded(a)
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if a.global and _G[a.global] ~= nil then return true end
  if not isLoaded then return false end
  if isLoaded(a.name) then return true end
  for _, n in ipairs(a.alt or {}) do if isLoaded(n) then return true end end
  return false
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
