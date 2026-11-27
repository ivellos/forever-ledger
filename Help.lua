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
    { sub = "First steps" },
    { "Open this window", "Type /fl, or click the minimap button." },
    { "Learn your recipes", "Open each profession window once on every character." },
    { "Price everything", "At the auction house, click Full scan (allowed about every 15 minutes)." },
    { "Tooltips", "Hover any item to see what it's worth to you. Settings can make it short (today's cheapest price and what it's worth to you), with Shift for more. With 20 or more listed, selling on the auction house is valued from today's prices; with fewer, from this month's usual price if that's lower, so a few hopeful listings don't fool it, and a gray line says so. What a disenchant or craft gives is valued at no more than its usual price this week, so a buyout that spikes a material's price doesn't make a disenchant look profitable." },
    { "Bags", "A bag's tooltip shows what one slot costs at today's cheapest price (auction house or vendor), and which bag is the cheapest per slot right now, so you buy the cheapest space first." },
    { sub = "Settings and look" },
    { "Search", "Settings and Help each have a search box above their list: type two letters or more to see everything that mentions it, from every section at once." },
    { "Settings", "A sidebar like EllesmereUI's: Global settings first (the same for every character: the auction house cut, safety margin, price source and what counts as a flip or a deal), then Profiles, then a page per part of the addon, with tabs across the top for its parts." },
    { "Themes", "Settings, Appearance: FL Clean (flat and quiet), FL Bronze (a bronze edge, gold titles, sections as cards, switches) or FL Gilded (a bronze frame, gold serif titles), and an accent color: Auto uses EllesmereUI's when it's installed, or pick one, or Custom. A new look shows after a reload; it offers one. Size makes the windows smaller or bigger, 75% to 150%: drag, then let go. Show money as: the game's coins, or colored letters (12g 50s 3c, each letter in its coin's color) if the coins look busy." },
    { "Languages", "Forever Ledger shows its text in your game's language where a translation exists: Simplified Chinese and Russian so far, English for the rest. It follows the game's own language, so there is nothing to pick. Professions, quests and zones work in every language. To help translate, see TRANSLATING.md on the addon's GitHub page." },
    { "Profiles", "Settings, Profiles: a profile is a set of settings characters can share, say no tooltips on one character, no customer finder on another. Each character uses one (Default to start). New profile copies your settings now; Rename, Reset to defaults and Delete profile (click twice) work on the one this character uses. Export / import opens one window: Export copies a profile as text with the parts you tick; Import makes a new profile from someone's text. Global settings are never in a profile." },
    { sub = "Updates" },
    { "Welcome", "The first time you open the window, a short welcome lists the five things to start with. Show it again with the button at the bottom left of this tab, or /fl welcome." },
    { "What's new", "After an update, chat lists what's new in that version, once. The What's new button (bottom right of Help and the Dashboard) or /fl new shows it as a card." },
  } },
  { "Auction house scans", {
    { sub = "Scanning" },
    { "Full scan", "Reads every listing in a few seconds." },
    { "Pause", "Holds Live watch and the Buy queue's own lookups, so your searches and the page you're on stay as you leave them; Buy, Go now and clicking a row still work. Resume carries on, and closing the auction house ends it too. To check just what your recipes use, type /fl scan materials." },
    { "Live watch", "On the auction house: keeps scanning while it stays open and chimes when a new vendor flip turns up. Between full scans (about every 15 minutes) it reads the auction house's whole list about every 20 seconds, as a search with no name on the Buy page does, and looks closely at anything that just got cheap enough. The list comes cheapest first, in parts: a new flip chimes and goes to the Buy queue as soon as its part arrives, without waiting for the rest. While it reads, the Buy page's list shows every item, cheapest first; after your own search it waits half a minute before replacing your results. It can only scan with the auction house open: it pauses when you close it and picks up again when you come back (Settings, Auction house: Resume Live watch). It also waits while you're on one item's buy or sell page, so it doesn't change what the page shows; the status line says so, and it carries on when you go back to the list." },
    { "Quiet mode", "Doing something else while you wait for a chime? /fl quiet turns the game's sound off and plays Forever Ledger's chimes at full volume, even with the game in the background, plus a chime when you win an auction. It stays on for that character, through reloads and logins, until you type /fl quiet again. Quiet mode while Live watch runs (Settings, Auction house, Alerts) does it by itself, and /fl pair offers to turn that on. Your sound settings come back afterward." },
    { "Other addons", "If Auctionator or another addon runs a full scan, Forever Ledger reads it too. With Auctionator, TSM, AHledger or ForeverForge installed, features they already cover (like auction prices in tooltips, or a sound when an auction sells) are switched off once, with a message; turn them back on in Settings." },
    { "Neutral auction houses", "Booty Bay, Gadgetzan and Everlook keep their own prices and take a 15% cut (your faction's takes 5%), which values, sell protection and the Auctions tab count while you're there. The Auctions tab lists what you have up there apart from your faction's." },
    { sub = "Selling" },
    { "Your auctions", "The Auctions tab beside the auction house: All, Up, Undercut and Sold, like the Ledger. Each auction shows how many, your price each, the cheapest now, and undercut (red) or cheapest (green); sold ones show what you get after the cut and when the gold reaches your mailbox. The bottom line says what gold is on the way and what's waiting in your mailbox. Check prices looks them all up; scans and Live watch check them too, and an undercut gets a chat line and a sound (Settings, Auction house). Cancel next undercut asks once, then each click cancels the next one (each loses its deposit). Opening the auction house says in chat what sold while you were away and the gold it brings (Settings, Auction house). Scroll to cancel (off each visit, Esc turns it off): each mouse wheel tick over the list cancels the next undercut one. Also cancel ones I could ask more for: adds your auctions that are the cheapest but at least 10% under the usual price (marked could ask more), to repost higher. Middle-click a row to skip it this visit." },
    { "Sale sound", "A coin sound when one of your auctions sells. Settings, Auction house: Sound when an auction sells." },
    { "Price helper", "On the Sell tab, under the Create Auction button: your usual price and the cheapest now, with Undercut (1 copper under the cheapest) and Usual buttons that fill in the price. When the cheapest is well below usual it says so, so you can wait. You still click Post (Settings, Auction house). With Always undercut by set (Settings, Selling), it fills the price box by itself with that much under the cheapest listing, or your own price when the cheapest is yours, and Undercut uses the same amount." },
    { "Sell protection", "On the Sell tab, if a vendor pays more than your listing would bring after the auction house cut, a red line under Post says so and Post is grayed out until you click Post anyway. Settings, Auction house: untick Stop posts below vendor price to keep just the warning." },
  } },
  { "Tooltips", {
    { sub = "Prices" },
    { "Auction price", "Auction, cheapest: the lowest price listed at your last scan, how many were listed, and (in gray) how long ago. Under it, when different: the average of the 20 cheapest, about what you'd pay buying a few. Values in Forever Ledger use that average, so one odd cheap listing doesn't sway them. With your own prices over 12 hours old, another addon's price is used if you have one, and named: AHledger first (its prices come from every player's scans, refreshed every half hour by its sync app; shown with Prices from AHledger, ahledger.com), then Auctionator, TSM or Auctioneer. Where your own scans can't yet say how fast an item sells, AHledger's sold a day is used, marked AHledger." },
    { "Worth to you", "The best of selling on the auction house, selling to a vendor, disenchanting, or crafting it into something, with the best few ways listed. Disenchanting counts what the materials sell for, as an average: each disenchant gives one result, and the tooltip shows the chance of each. Hover damaged gear and the vendor way counts what a vendor pays for it as it is. Settings, Tooltips chooses which ways it counts (turn off crafting to leave out what your alts could make); shuffles and the Buy queue still count every way." },
    { "Sell suggestion", "On items in your bags, the first Forever Ledger line says what to do with it. Keep, when a quest still needs it, a recipe of one of your characters uses it, you watch it, or it's on one of your lists. Otherwise Sell: Vendor, Sell: Auction house (it brings clearly more after the cut and a deposit: a quarter more, or twice as much when it sells slowly), or Sell: Close call when the two are near, with the reason in gray. Soulbound items say Vendor; gear this character can wear says what to do if you won't wear it (If you won't wear it: sell to a vendor, or disenchant when that's clearly worth more). When disenchanting brings more, that shows too, with your enchanter's name; when it brings a quarter more or better, Disenchant is the first line and selling the other way under it. Only a suggestion: nothing is sold. Off in Settings, Tooltips." },
    { "Auction house deposits", "Selling an item on the auction house (its Worth to you line), resale deals and the Booty Bay view allow for one 8-hour listing that doesn't sell (its deposit is lost). The deposit comes back when a listing sells. Materials further down a chain (dust from disenchanting, a craft's output) don't count it, so the Disenchant finder, shuffles, vendor flips and shopping-list limits are unchanged. If this makes selling to a vendor better, the option says Vendor it instead. Deposits use the auction house's quote when available, otherwise Classic's formula, which matches Forever: 5% of the vendor price per 2 hours (25% at Booty Bay), so 20% for 8 hours. Without a known vendor price, it's zero." },
    { "Buy at or below", "The most worth paying, after your safety margin. Green when it's already cheaper." },
    { "Gear versions", "Gear with random stats (of the Eagle) also shows the price of that exact version." },
    { "Price history", "Hold Ctrl over an item: the cheapest price over the last 14 days, whether it's rising or falling, the usual price this month, how many are usually listed and the lowest price ever seen. It builds up with each scan." },
    { "Price window", "Alt-click an item in your bags, a link in chat or a listing on the auction house (search results, a gear listing, or the item's picture on its buy page; gear with random stats opens on the version you clicked) for its own window. To look up any item, even one you don't have: Price lookup at the top of this window, or /fl price, then type part of its name in the box at the top right. The window shows the usual price, which way it's heading, the cheapest now and how many are listed, how many you have and have posted; a graph of the cheapest and typical price (pick the time in the dropdown above it: Today, Past 24 hours, This week or Past 7 days show each hour, with a mark every hour, or every midnight and noon; Month, 3 months, 6 months or Year show each day. Each scan saves an hour and a day, and with sync on your other account's scans count too, with days you missed while offline, up to 14, sent over when the two connect; hours are kept a week, days 90 days, then weekly averages for a year), with how many were listed as bars and dashed lines for the vendor price or disenchant value and the cost to craft; hover it for each hour or day. Gear with random stats can show one version (of the Eagle), by day only. Beside it: your last 7 days with the item and what it's worth to you. If a recipe makes it: the materials at today's prices, what crafting one costs against what it sells for after the cut and one unsold listing (as Worth to you counts it), and the profit; click a material for its own graph. Choose how many crafts and a list to add the materials to a shopping list. Search on the auction house shows it there while the auction house is open. Settings, Tooltips, General turns the click off or changes it to Ctrl-click or Ctrl+Alt-click (if another addon, such as a disenchanting one, uses Alt-click). Ctrl-click then no longer opens the dressing room; with Ctrl+Alt-click, Ctrl-click still does." },
    { sub = "Uses and quests" },
    { "Also", "Disenchant results, which of your recipes use it, and the cheapest crate fill." },
    { "Quests and crafts", "Items quests ask for (Bronze Tube, Spider Ichor, Flask of Oil...) say Quests (3) in orange, and items crafts use say Used in crafts (12) with the professions (every recipe we know, yours or not). Hold Shift for the lists: each quest, its level and how many, for your faction, and the crafts by profession, with which of your characters use it. Quests turn yellow with keep it when this character hasn't reached that level yet, so you don't vendor it. Quests this character has done, ones gray for its level and other classes' quests are left out (Settings, Tooltips: Only quests this character still needs; off shows them all, marked). Leveling players buy these once per character, so they sell; the Deals tab's hover says when a deal is one. From original Classic quests: Forever may have changed some." },
    { "Darkmoon Faire", "Items the Darkmoon Faire takes for Prize Tickets get a coral red line: how many a turn-in takes, the tickets it gives and who takes them (Small Furry Paw: 5 for 1 ticket, Yebb Neblegear). Animal parts, and Blacksmithing, Engineering and Leatherworking crafts. Classic's list: Forever may have changed it. Settings, Tooltips." },
    { "Sells", "How fast an item sells: Fast, Steady, Slow, Rare (seldom listed, goes quickly) or No sales seen, judged against items of the same kind, so ore and swords aren't held to the same bar. It counts listings that vanished before they could have expired, so it builds up as you run full scans (fastest with Live watch) and shows after 3 hours of scans compared (and, in the first day, at least 3 sales)." },
  } },
  { "The Gold making tab", {
    { "Gold making tab", "Every way to make gold Forever Ledger finds, in one list: crafts that sell to a vendor or on the auction house, conversions, vendor flips, deals well below the usual price, disenchanting, and Booty Bay against your own auction house. Each row: what it costs, what it brings, the profit each time and how many times you could do it with what's listed cheaply enough now. Click a column name to sort; it starts with profit times how many. It's worked out when you open the tab (Refresh to do it again). It replaces the Shuffles and Deals tabs: /fl deals still opens the old Deals tab for now." },
    { "Kinds and filters", "The buttons across the top pick a kind, with how many of each; Everything leaves Booty Bay out (it needs a trip there, and only prices from the last 3 days count). Least profit hides small ones, and the profession box shows one profession's crafts (disenchanting counts as Enchanting). Untick Only my recipes to add every profession's crafts that sell to a vendor for more than they cost, from recipes nobody of yours knows yet (marked learn). Search narrows it by name." },
    { "Saved filters", "Pick filters, then Save these filters: they become a quick button (up to 5). Click one to use it, right-click to delete it." },
    { "How it adds up", "Click a craft: the panel on the right works out the cheapest way to get its materials for that many crafts (it starts at what's listed cheaply enough, and for an auction house craft no more than about a day's sales; change it with Crafts). Each material is filled one at a time from the cheapest place next: your bags (at what they'd sell for, or free with Count my bags as paid for), the next listing on the auction house, a vendor, or making it from its own materials. So a few cheap Bolts of Runecloth are bought and the rest made from cloth, and nothing is counted twice. Add materials to a shopping list puts what's bought on a new list, each up to the highest price the plan paid." },
    { "Other kinds", "Click a deal, flip, disenchant or Booty Bay row for its numbers and why. Right-click any row (or Price window) for the item's price window." },
  } },
  { "Shuffles and vendor flips", {
    { "Shuffles", "Buy materials, craft, disenchant or convert, and sell, ranked by profit per hour. Click a row for every step. Blizzard nerfed most vendor shuffles, so Sells to a vendor may often be empty. Tick All professions there to see every profession's crafts that sell to a vendor for more than their materials, whoever knows them. Recipes from your profession windows come first. Ones your windows haven't shown come from the game's own data, marked (Forever), and for an item that has none, Classic's, marked (Classic). Some may not be learnable in game yet." },
    { "Add to shopping list", "Open a shuffle or vendor flip, pick a regular list or New list, choose how many crafts (or items), then Add to shopping list. Its purchases and price limits are added; an existing item keeps its bought count and any price you typed. A disenchant group uses its cheapest item. Crate lists and lists with Any price are left out. New lists start with buying off: check Want and Up to and tick Buy from this list when ready." },
    { "Vendor flips", "Things on the auction house for less than a vendor pays. They're in the Buy queue beside the auction house (its Vendor flips view); a full scan that finds some opens it if it's closed, and Live watch chimes. Settings, Global settings, Flips and deals sets the least profit worth your time, as a share of the vendor price and as an amount." },
    { "On the auction house", "Listings worth buying get a green bar and a badge saying why (FLIP, DE, CRAFT, USE), and the line above says how many are left." },
  } },
  { "Buy queue and lists", {
    { sub = "Buy queue" },
    { "Profit %", "On Vendor flips, click the Profit % heading to put the best return on what you spend first (50% means you get 1.5 times what you pay), or Profit for the most gold you can make now. Both count only the listings your gold covers. Until you click one, the usual order stays; watched items always come first." },
    { "Buy queue", "Click the Buy tab along the bottom of the auction house window, after Blizzard's Buy, Sell and Auctions (My auctions beside it shows your auctions; with Forever Ledger's tabs in the auction house off in Settings, click Buy queue under the window for a panel beside it). It lines up vendor flips and your shopping lists. Each row says Up to (the most it pays for one), Buy (how many it would buy now: what's listed at or under that, no more than the list wants or your gold covers) and Total (what those cost). It finds the next one by itself, and a click on Buy (or, with Scroll to buy picked in the dropdown at the top right, a tick of the mouse wheel, up or down, anywhere over Vendor flips or over a shopping list's top strip) buys it. A stack of materials is confirmed in the same tick once its final price comes back within your limit (to confirm it yourself, tick Confirm stacks with a second click in Settings, Auction house). Bottom right: what you bought this visit, what it cost and the profit if you vendored it (hover for the numbers). /fl queue. Each row has a star: click it to watch the item (gold while watched; Live watch then looks for it every time it reads the auction house), and a short reason, FLIP or WATCH (or the shopping list's name)." },
    { "Scan once", "The Buy tab's Scan once view is for looking things over instead of sniping. Scan reads the whole auction house list once (with Live watch on, its prices are fresh already), and the list stays as scanned until you scan again. Tick groups on the left (All items, All groups, Materials, Cloth...; a group counts the ones under it, ticked groups add together, + opens a group) and search names at the top right. Each item shows its cheapest price, its usual price, how far under or over that it is (green under 90%, red over 110%), how many are listed, and FLIP, WATCH or DEAL when Live watch would buy it. Best deals first. Click a row for its price window; click the star to watch it." },
    { "Post", "The Post tab in the auction house window: your bags, grouped (Cloth, Herbs, Gear...), each with a price ready and a mark from the sell suggestion (Post, Keep, Vendor, Disenchant; Show: Everything lists all you could post). The price comes from the item's post rule: the same as the cheapest (listings at one price sell in the order they went up; a rule can undercut instead, or Settings, Selling: Always undercut by for every item without a rule of its own; when the cheapest is yours, yours is matched, never undercut), never below 70% of the usual price or what a vendor pays after the cut; under that it isn't posted. Picking an item looks it up on the auction house, as the Sell page does, and the price comes from the listings now (Post waits for that); the table below lists them, price each, how many and the seller, yours marked, with a line where yours would go; click a listing to price yours the same as it, Refresh looks again. Change how many, the price or how long (2h, 8h, 24h) and see the deposit, the total price and what you get after the cut; the line under says where the price came from and which rule. Post posts it and moves to the next; Skip and Previous move along; middle-click a row to skip it this visit. Scroll to post (off each visit, Esc turns it off): each mouse wheel tick over the list posts the highlighted one. One click or tick per post, as the game requires; when the game asks to confirm, the next click or tick confirms." },
    { "Groups", "The Groups tab sorts items into groups and gives each group rules. Built-in groups (Materials, Cloth, Herbs, Consumables, Recipes, Gear...) sort themselves by the game's item type, gear by kind and then by required level (Level 1-15 up to 56-60); profession groups (Tailoring materials, Tailoring crafts) come from the recipes; Watched and Gray items; and your own groups (New group). Pick a group: Items lists what's in it (add an item by name, ID or Shift-click; Remove from group; Restore items puts a built-in group back), Rules has four cards, Post, Buy, Vendor and Craft, each Same as the group above, Forever Ledger's default, Off, Changed here (edit a field) or one of your saved rules. Rules on the left lists the defaults (copy one to make your own) and your saved rules, which several groups can share. When an item is in several groups, your own group wins, then a profession group, then a built-in one. The Post tab uses the post rules today; Restore built-in and deletes ask first." },
    { "Scanning from the panel", "The panel's bottom row has Live watch, Full scan and Pause (Stop watching and Resume while they're on), with the scan's progress just above. While the panel is open beside the auction house, the same buttons under the auction house window are hidden." },
    { "Moving the auction house window", "Drag the auction house window by its top edge to put it where you like; each character keeps its own spot, and the panel beside it moves with it. Right-click the top edge to put it back. Settings, Auction house: Let me move the auction house window (it turns off by itself when BlizzMove or MoveAny is installed, since they move windows too)." },
    { "Watched items", "Items you always want checked, each with the most you'd pay (Silk Cloth up to 2s for bandages, say). Live watch looks for them every time it reads the auction house (about every 20 seconds), and anything at or under your price joins Vendor flips, first in the list, and chimes. Leave the price at vendor to buy one only when a vendor pays more. Add one with Watch in its price window, or with the Watched button at the top of Vendor flips (shift-click, drag or type it); change Up to or remove it there. For gear, any stat version at or under your price is bought." },
    { "Two views", "Vendor flips or Shopping lists, switched at the top of the panel, one at a time; the one you're on is the one that buys, so a list never buys a flip by accident. Each has its own buttons at the bottom. When there is something to buy, the strip at the top glows (gold for Vendor flips, purple for Shopping lists); with Scroll to buy picked it also shows a mouse wheel: scroll anywhere over Vendor flips (drag the bar on the right to scroll its list), or over a shopping list's top strip. A new flip that chimes switches the panel to Vendor flips, unless you're using a shopping list (something on it being looked up or bought, or a click or scroll there in the last 30 seconds); then a gold count on the Vendor flips button (and on the Buy queue tab) says it's there." },
    { "Safe by design", "It never pays more than the limit shown (checked again on the final price) or more than you have, and every purchase starts with your own tick or click, as Blizzard requires. Scroll to buy only works with the mouse over Vendor flips or a shopping list's top strip (Scroll anywhere, for Vendor flips: wherever the pointer is, but only while there is something to buy); pick Click to buy in the dropdown to buy by clicking only. Right-click an item to skip it. Items you can't afford yet stay at the bottom of the list, grayed and marked can't afford, and are skipped until you have the gold; scroll past the last one you can buy and you get the error sound and a red message, once." },
    { "Spend at most", "The box near the bottom of the Buy queue caps what it spends this auction house visit (type 50 for 50g; it starts again each time you open the auction house). No limit until you type one; what's left shows beside it. Items over it are marked over limit and skipped. To always keep some gold back for repairs or a mount: Settings, Auction house, Buy queue: always keep." },
    { sub = "Shopping lists" },
    { "Shopping lists", "Named lists of items, for example twink gear to watch for or raid consumables to buy. Pick a list from the dropdown at the top; New, Rename and Delete are beside it. With the list open, shift-click an item to add it (or drag it, or type its name: names are suggested as you type, Enter takes the top one). Open them anywhere, to plan before you go to the auction house: the Shopping lists button at the top of this window, Shift-click on the minimap button, or /fl lists." },
    { "Search all", "Checks the auction house for everything on the list at once. Each item shows when it was checked (checking... and in line while it runs), how many are listed and the cheapest. Click an item to look at it on the auction house." },
    { "Have", "What you own of each item: this character's bags, bank and auction house purchases still in the mail, and your characters on this ruleset and faction. On a list you buy from it reads 3 (20): 3 bought for the list, 20 owned. Hover the number to see where. It's there to know, it doesn't change what's bought." },
    { "Buying from a list", "Tick Buy from this list in the Buy queue: the list adds Want (how many to buy) and Up to (the most you'll pay for one: filled in from its source; hover to see where it came from; off means don't buy it), and the Buy queue's Shopping lists view buys them. Want is how many to buy, whatever you already have; Have shows how many are bought so far. It never buys more than Want. Type any in Want to keep buying it whenever it's at or under Up to, with no limit (not with Up to any, which would buy every listing: then it buys one). An item is done once its Want is bought, and stays done; Buy again (bottom right) starts the list over. The bottom line says about what buying the rest would cost." },
    { "Where Up to comes from", "Hover Up to for its source. From a shuffle: its buying cap, not today's price; if two shuffles use an item, the lower cap wins. Add the shuffle again or use Buy again to refresh it. Added by hand: usual price plus this list's allowance (Pay up to X% over the usual price, starting at 10%); change the percentage on each list, then switch buying on or use Buy again to fill it. Type any price yourself, including off: it always wins and is never changed automatically. Existing limits are treated as yours. A shuffle route that can no longer be valued turns off until refreshed with known prices." },
    { "Prices", "Type a price any way: 2g 50s 25c, 2 50 25 or 2.50.25 (gold silver copper), 2 50 (gold silver), 25s, 75c, or a plain number for gold; it's tidied up when you press Enter, and a tip shows what it will be. Type any for any price, or tick Any price (bottom of the list) for the whole list (raid prep): the queue then buys the cheapest until it has bought what you want, never more than 3 times the usual price." },
    { "Vendor supplies", "Unlimited-stock vendor items show vendor under Up to on lists and stay out of the auction house queue, including hand-added items. Settings > Auction house > Buying: Buy vendor items on the auction house too (off by default) permits buying at the vendor price; a lower price or off that you typed is still respected. Your stored price is kept. Right-click an item's Up to box to use its automatic price again; the hover shows the underlying shuffle cap or usual price plus the list allowance while a typed price is in force. Limited-stock vendor items remain ordinary auction house items." },
    { "Buy or craft", "Items one of your recipes makes have a Buy/Craft button: set Craft and the list shows the materials for the number you want, with Up to for each (usual price plus this list's allowance unless you type one) and how many are bought. Materials a vendor sells are marked vendor. Hover an item one of your recipes makes: what buying it would cost against buying the materials to craft it, and which is cheaper." },
    { "One version", "Type \"Soldier's Armor of the Monkey\", or shift-click a link of that version, to keep just that version on a list. Search all looks up every version of gear; hover an item for each version's price, yours first." },
    { "Share and import", "Share / import (top right of the list) opens a window with two tabs. Share copies a list as plain text to paste in Discord or send a friend; Import reads it back (or a plain list of item names, item numbers or Wowhead links, one per line). Imports never change your own lists, and never buy by themselves: tick Buy from this list to buy from one." },
  } },
  { "Deals", {
    { "Deals tab", "Listings well below the price an item is usually cheapest at, to buy and resell: price now, usual low, how many are worth buying, profit after the cut and one unsold listing, and how sure it is (Good, Fair or Thin)." },
    { "Booty Bay", "Deals tab, Booty Bay (top right): the neutral auction house against yours, each after its own cut (15% there, 5% here) and one unsold listing. Sells for more there: items worth at least 10% more sold at Booty Bay. Cheaper there: buy at Booty Bay, sell here. Its prices come from scanning there and are kept apart from yours; a tooltip line for big differences is in Settings, Tooltips." },
    { "Why it's a deal", "Hover a deal: the usual cheapest and typical prices and how many days of your scans they come from, how many are usually listed, and the next listing up. Profit assumes you resell at the usual cheapest price or just under the next listing, whichever is lower. Click to search the auction house." },
    { "Filter", "All, Materials, Gear or Other, and a search box for names." },
    { "How sure", "When most of what's listed is that cheap, the price has dropped and it's no bargain: rated Thin. Deals need at least 4 days of scans (or TSM). Thin data (few days, jumpy prices, usually only one listed) is hidden unless you tick Show doubtful deals too." },
    { "Keep in mind", "The auction house can't tell what actually sold. Buy what you'd be happy to hold for a while." },
  } },
  { "Disenchanting", {
    { "Quick disenchant", "Hold Ctrl+Alt and click a green, blue or purple weapon or armor in your bags: it is disenchanted, one click each (the slot lights up while the key is held). Or open the Disenchant window (Disenchant at the top of the main window, or /fl disenchant): tick what to disenchant (Tick suggested ticks what the sell suggestion says to disenchant), then click the Disenchant button at the bottom once per item. Only ticked items. Settings, Disenchanting changes the key. Not in combat." },
    { "Disenchant estimates", "Any Enchanting skill can disenchant anything. What an item gives, and how often, are estimates from public data, so the game can differ. Greens, blues from item level 21 and purples from 40 are covered; blues below 21 aren't, as ours gave essences where the estimate says shards. Crafted wands and items the game says can't be disenchanted are left out. The rare extra crystal from high-level blues and the Arcane Salvager's bonus aren't counted." },
    { "Disenchant finder", "Beside the auction house (Buy queue button, Disenchant finder tab): eligible armor and weapons in the item levels you pick (the Item levels dropdown, with Select all and Deselect all), with what each is worth to disenchant, on average, if you sell the materials. Hover a row to see each material's price and how that adds up. Hover a level in that list for the odds and what a bad and a good roll would bring (Settings, Auction house can hide the rolls). Pick a regular shopping list or New list, then Add to shopping list for one of every shown row your Enchanting can disenchant; right-click a row to add only it. Up to uses the disenchant value less the safety margin, refreshed when added again, on Buy again or by right-clicking Up to. Type a lower price for a bigger margin; typed prices stay yours. New lists start with buying off. Any stat version of each item will do." },
  } },
  { "Recipes and trainers", {
    { "Professions tab", "Your professions as tabs (the rest in the Other professions dropdown), then Trainers and Crates. Each profession lists every recipe: the ones your profession windows recorded and the rest from the game's own data, with who knows it, where to get it, the skill needed and profit per craft. Right-click a recipe to set its type yourself. Click a column heading to sort." },
    { "Recipe filters", "All, Not known or Known; Type; Where from (Trainer, Vendor, Drop, Quest, On the AH, or Not seen yet: a recipe item nobody has spotted); Skill (Learnable now: one of your characters on this realm and faction has the skill; Need more skill); Group, by what the recipe makes (the Groups tab's groups); Least profit a craft; and a search. When nothing matches, the list says which choices hide it." },
    { "Types", "Flip or shuffle, Crafts that sell, Enchant service, Not for sale, Not profitable." },
    { "Where from", "What you've seen in game first, otherwise original Classic data marked (Classic), or the auction house when its recipe item is listed there. Pin puts a map pin on the vendor, trainer or mob." },
    { "Trainers view", "Trainers you've visited, Classic ones, and spots city guards mark when you ask them for a profession trainer (marked guard)." },
  } },
  { "Waylaid Crates", {
    { "Crates", "Professions, Crates: the cheapest way to fill each crate at today's prices, with the crate's own price, gold per Merchant's Favor and how many you have (bags, bank and other characters; hover for where). Filter by level (Apprentice to Artisan), by kind (Herbs, Ore, Ingots, Parts...) and Only ones I have. A turn-in gives 5 Favor a level (Apprentice 5 to Artisan 20) for gathered goods, twice that for crafted goods (Fabrics, Ingots, Parts), checked at your turn-ins (the Favor column); the money varies, so it isn't counted: Total is what the crate takes, Per Favor that divided by its Favor. It knows every crate's items by item number, so it works in any language. Click a crate for every bundle and what you already have." },
    { "Writs", "Professions, Writs: every Craftsman's Writ order (an item to deliver to a customer for reputation and a coin pouch, each once a day, no profession needed) with its customer and zone, the cheapest way to get the item at your last scan's prices, the cost per point of reputation (the coin pouch's money varies, so it isn't counted; hover for what yours paid), and the writ's own auction price. Writs in your bags come first. Yours shows only the writs you have. List, or Add yours to a shopping list, puts what to buy on the Writs shopping list (the item, or its materials when making it is cheaper; what you have is used first). Filter by tier, profession and the zone the customer is in. Hover for the cheapest way step by step; click to search the auction house for the item, right-click for the writ itself (List also puts the writ on the list when you have none). The amounts, customers and reputation start from player guides; taking or handing in an order checks them in game." },
    { "Shopping list for a crate", "Open a crate and click Add cheapest fill to a shopping list: the crate and its items go on a list named after the crate, with prices high enough to buy them all at your last scan. What you already have counts towards a crate list's Want (only crate lists do this). Tick Buy from this list in the Buy queue on it to buy what you're short. Set the crate's Want to fill several at once: every item's Want follows it. The list is temporary: each crate you fill takes one off, and the list goes with the last one (or after a week)." },
  } },
  { "Customers and work", {
    { "Customers window", "Opens when someone in chat asks for what your character can do, with Whisper and Invite buttons. x hides one request; Clear all (bottom right) hides them all. /fl customers opens it any time." },
    { "Silence", "The Silence button (bottom right of the Customers window) quiets the alerts: until you're next in a capital city, until you reload, until you log out, or always (that turns the finder off; Turn alerts back on, or /fl customers on, brings it back). While quiet, requests are still listed in the window, with no pop-up, sound or chat line." },
    { "Class services", "The finder also spots requests for Mage food, water and portals (portals from level 40), Warlock summons (from 20) and Rogue lockpicking (from 16), on those classes. Settings, Customers turns each one (and crafting) on or off." },
    { "Ads", "Post your crafting (with profession links) to Trade, and on those classes your food and water, portals, summons or lockpicking. Right-click a button to change the text." },
    { "Work done", "Enchants and paid trades, with today's and this week's earnings. /fl work." },
  } },
  { "Your gold", {
    { sub = "Overview" },
    { "Dashboard", "Your gold now and how it changed; trading profit (auction house and vendors: hover it for loot, quests, training and the rest of your money, which together match the change in gold), sales and expenses for the range you pick (Day to All time); the gold graph (hover it for any moment), the most profitable item and the biggest sale and purchase, and how much you trade a day." },
    { "Riding fund","A strip on the Dashboard until this character knows riding (then epic riding): what it costs (from the riding trainer once you've seen one, else about 100g and 1,000g), your gold toward it and about how many days at your pace. Off everywhere in Settings, Global settings, Modules; Hide here on one character, /fl fund to show it again." },
    { "Characters", "Your characters on this realm and faction down the left with their gold (the dropdown above them picks another realm or faction, both factions, or all realms). Pick one for its professions and what's in its bags and bank, each item with what it's worth to you (Each: the best of auction house, vendor, disenchanting or crafting) and the best way to get it; All characters adds everyone up. Hover an item for who has it, a character for gold and bags and bank worth, the bottom line for what it's made of. Bags as of each character's last login, bank as of the last bank visit." },
    { sub = "Ledger" },
    { "Ledger", "All: every transaction in one list (auction and vendor sales and purchases, repairs, mail, loot, quests...), money in green and out in red. Sales, Purchases and Other show one kind each. Filter by time, character or a word; click a heading to sort; hover a row for the details." },
    { "Ledger by item", "By item gives each item you bought or sold one line: how many bought and sold, the average prices (auction sales after the cut), profit each, and profit on the ones resold. Hover for totals and where; double-click for every trade of that item. Sales, Purchases and By item also filter by group (from the Groups tab) and rarity. A search in quotes matches that one item exactly." },
    { "Totals of rows", "Select rows to see what they add up to: click one, Shift-click another for everything between, Ctrl-click to add or take one, or press and drag across rows. The bottom line shows the money in, out and net of the selection. Right-click a row or Clear selection to start again." },
    { sub = "Sessions" },
    { "Sessions", "Start one (Ctrl-click on the minimap button, or /fl session start) and a small tracker you can drag counts what your time is worth: gold an hour, gold in and out, and what you loot (at the better of auction and vendor price; Settings, Sessions can make it vendor only). Right-click the tracker to fold it to one line. The small icons: the arrow (More) opens the session window, live: tiles for gold an hour, gold, loot and your usual pace (after 3 sessions of 10 minutes or more; ahead or behind it), a graph of gold and loot over the session against your usual pace, every item looted with how many, worth each and in all (click a heading to sort; gray items for the vendor apart; the best drop on top; hover one for its tooltip; new loot lit for a few seconds), gold by where it came from, and your past sessions (the best gold an hour lit). Drag it anywhere; Close or the arrow closes it. Pause (two bars) stops the clock and the counting until Carry on (the play arrow; or /fl session pause and resume). Reset (the circle arrow; or /fl session reset) clears what the session has counted and starts its clock again from zero, after asking; it isn't kept. Loot counts only while you still have it: sell it during the session and it counts once, as the gold it brought; disenchant, use or destroy it and it drops out. Gold an hour shows after 5 minutes. Stop it (the square) to get a summary in chat (with your best yet, or your usual); it joins the Ledger's Sessions sub-tab, with when, length, gold, what you looted, gold an hour and the character (hover one for where its gold came from and the best loot). A session carries on through a logout on the same character. Settings, Sessions can start one each time you log in. Without one, each login and each day are recorded on their own (gold in and out and loot, the same way): in the Ledger's Sessions sub-tab, choose Each login or Each day in the dropdown beside Characters (Started by you lists yours). The one counting now is on top, so far. A /reload carries on the same login; a day runs from your first login to midnight or your last logout. Logins are kept 30 days, days a year; ones with nothing in them aren't kept." },
    { sub = "Keeping data" },
    { "How long it's kept", "Sales and purchases one by one for 30 days, then as one line per item per month for a year. Gold and money in and out per day for a year, then per month. Prices per day for 90 days, then weekly for a year. Recipes, vendors, items and your characters are kept for good. Nothing is lost at a reload: only data past these ages is summed up or dropped." },
  } },
  { "Two accounts", {
    { "Live sync", "Link your other account in Settings, Characters (or /fl pair First Last, on both characters): prices and recipes go between your two accounts while both are online: your characters first, then the prices (those can take several minutes), then the days of price history the other missed while offline (up to 14, about a minute a day). Pairing asks whether it's your own account: say yes and your gold and sales go too, so both Dashboards and Ledgers match. They include your buyers' names, so say no for a friend. Every new link starts with sharing off and asks again. Change that with \"Share gold and sales\", and share bags and bank with \"Share bags and bank\" (both in Global settings, Advanced). /fl unpair stops it and removes the other side's characters, gold and sales; the prices stay." },
    { "Removing a character", "Settings, Characters lists every character Forever Ledger knows, when each was last seen and where it came from. Addons can't see a character being deleted, so remove old ones there: click Remove twice. It forgets the level, professions, recipes, bags and bank; prices and gold history stay. Not the one you're on." },
    { "Export and import", "Export / import on the Characters tab, to copy everything across by hand (and Prices as text)." },
  } },
  { "Help and community", {
    { "New versions", "When a guildmate or group member has a newer Forever Ledger, chat says so once a session, with where to update. Only the version number is shared (Settings, Minimap and updates)." },
    { "Discord", "discord.gg/WKsCtvupeC: updates, questions, and WoW Forever news." },
    { "Found a bug?", "Type /bug on the Discord and fill in the short form. Include /fl api output or the BugSack error if you can." },
    { "Have an idea?", "Type /idea on the Discord. You'll get updates in your post." },
  } },
  { "Your data", {
    { "Stays on your PC", "Everything Forever Ledger records is kept in its saved file on your computer. Nothing is sent to the author or anyone else." },
    { "What it keeps", "Prices and their history, vendor and trainer locations you've seen, your characters' recipes, gold, sales and purchases, bags and bank, chat requests it spotted, and your work log." },
    { "What it sends", "Only live sync to your own paired character (off until /fl pair), ads in Trade when you click an ad button, and your Forever Ledger version number to your guild and group, which can be turned off (Settings, Minimap and updates)." },
  } },
  { "Commands", {
    { "/fl", "Open or close the window." },
    { "/fl scan", "Full scan or materials." },
    { "/fl watch", "Live watch." },
    { "/fl quiet", "Quiet mode on this character, until you type it again: game sound off, chimes at full volume." },
    { "/fl price", "The Price window: look up any item's price history." },
    { "/fl queue, /fl lists", "The Buy queue or shopping lists." },
    { "/fl deals", "The old Deals tab (/fl deals list in chat). Deals are on Gold making now." },
    { "/fl session", "Sessions: /fl session start, pause, resume, reset or stop (or Ctrl-click the minimap button)." },
    { "/fl customers, /fl work", "The Customers window. /fl customers on or off turns the customer finder on or off." },
    { "/fl de", "Your disenchant results." },
    { "/fl disenchant", "The Disenchant window: tick items, then one click each." },
    { "/fl book", "Recipe data gathered." },
    { "/fl pair, /fl unpair", "Link or unlink your other account." },
    { "/fl sync", "Sync status." },
    { "/fl welcome, /fl new", "The welcome card; what's new in this version." },
    { "/fl perf, /fl probe", "What takes time, and any freezes (a frame of a quarter second or more): how long, how much of it was Forever Ledger and which part, the item a tooltip showed, and which other addons the game names. /fl perf reset starts over; /fl perf detail adds time by kind of work, for this session. /fl probe: game checks." },
  } },
}

---------------------------------------------------------------------------
-- Questions players asked, per Help section (owner, October 3: one page was getting
-- long, so Help is split into topics, each with its questions). Add new ones as players
-- ask them; keep the answers short. { question, answer }.
---------------------------------------------------------------------------
ns.HELP_FAQ = {
  ["Getting started"] = {
    { "Does it buy or sell anything by itself?", "No. Every purchase and auction starts with your own click (or wheel tick), as Blizzard requires; a stack's confirm can follow in the same tick. Forever Ledger finds, suggests and queues." },
    { "Why are some things empty on the first day?", "Prices and flips work from your first full scan. Deals and how fast things sell need a few days of scans to know what's usual." },
  },
  ["Buy queue and lists"] = {
    { "Do I click the big button or a row?", "Either. The big button (or the wheel, with Scroll to buy picked) buys the next one. Clicking a row buys that one next." },
    { "Why did items disappear from the queue?", "Someone else bought them first, or their price is too old: finds over 15 minutes old are left out until a scan finds them again." },
  },
}

---------------------------------------------------------------------------
-- The Help tab, laid out like Settings (owner's test, October 4): a sidebar with search
-- and the topics, the chosen topic on the right under its title, each entry as a name
-- with its explanation under it, the topic and its questions each in a card with the
-- heading inside (Default and Gilded). Opens on the first topic each time (ns.helpTopic,
-- set back by UI.lua's setView).
---------------------------------------------------------------------------
local NAV_W = 190
local hv

-- Settings' Search Help button: the Help tab, searching for the same words.
function ns:SearchHelp(text)
  ns:ShowTab("help")   -- (opening the tab clears its search)
  if hv and hv.search then hv.search:SetText(text or "") end
end

-- The sidebar's groups, like Settings'; Getting started stands on its own.
local HELP_GROUPS = {
  ["The Gold making tab"] = "Gold making", ["Auction house scans"] = "Gold making", ["Tooltips"] = "Gold making", ["Shuffles and vendor flips"] = "Gold making",
  ["Buy queue and lists"] = "Gold making", ["Deals"] = "Gold making", ["Disenchanting"] = "Gold making",
  ["Recipes and trainers"] = "Professions", ["Waylaid Crates"] = "Professions", ["Customers and work"] = "Professions",
  ["Your gold"] = "Your gold",
  ["Two accounts"] = "Other", ["Help and community"] = "Other", ["Your data"] = "Other", ["Commands"] = "Other",
}

local function topicIndex()
  local want = ns.helpTopic
  for i, s in ipairs(ns.HELP) do if s[1] == want then return i end end
  return 1
end

function ns:BuildHelp(parent)
  local T = ns.Theme
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  hv = { frame = f, navButtons = {} }

  -- The sidebar, like Settings': search and the topics.
  local nav = CreateFrame("Frame", nil, f)
  nav:SetPoint("TOPLEFT")
  nav:SetPoint("BOTTOMLEFT")
  nav:SetWidth(NAV_W)
  local fr = T.theme.frame
  T:Fill(nav, fr and { 0.91, 0.76, 0.48, 0.04 } or { 1, 1, 1, 0.02 })
  local edge = nav:CreateTexture(nil, "BORDER")
  if fr then edge:SetColorTexture(fr[1], fr[2], fr[3], 0.5) else edge:SetColorTexture(1, 1, 1, 0.06) end
  edge:SetPoint("TOPRIGHT")
  edge:SetPoint("BOTTOMRIGHT")
  edge:SetWidth(1)

  -- Search, from 2 letters: every entry and question with it, from all topics at once
  -- (owner's test, October 3). Clicking a topic clears it.
  local search = T:EditBox(nav, NAV_W - 16, "LEFT")
  search:SetPoint("TOPLEFT", 8, -6)
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

  -- Topics (scroll if the window is short): a name, with a bar and a tint on the chosen one.
  local navSf, list = T:Scroll(nav)
  navSf:SetPoint("TOPLEFT", 0, -38)
  navSf:SetPoint("BOTTOMRIGHT", -1, 4)
  hv.navSf, hv.list = navSf, list
  local y, lastGroup = 0, nil
  for i, section in ipairs(ns.HELP) do
    local group = HELP_GROUPS[section[1]]
    if group and group ~= lastGroup then
      local h = T:Text(list, 10)
      T:StyleHeading(h, group)
      h:SetPoint("TOPLEFT", 10, -(y + 8))
      y = y + 26
    end
    lastGroup = group
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(24)
    b:SetPoint("TOPLEFT", 0, -y)
    y = y + 26
    b:SetPoint("RIGHT", list, "RIGHT", 0, 0)
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
    b.text = T:Text(b, 12)
    b.text:SetPoint("LEFT", group and 24 or 14, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)   -- (Magic, October 3: names ran out)
    b.text:SetText(section[1])
    b:SetScript("OnClick", function()
      ns.helpTopic = section[1]
      hv.search:SetText("")
      hv.search:ClearFocus()
      ns:RefreshHelp()
      hv.sf:SetVerticalScroll(0)
    end)
    hv.navButtons[i] = b
  end
  list:SetHeight(y)
  -- (Show the welcome again is in the window's bottom bar, UI.lua: owner, October 5.)

  -- The chosen topic: its title, a line about it, then the entries.
  hv.title = T:Text(f, 16)
  T:StyleTitle(hv.title, 16)
  hv.title:SetPoint("TOPLEFT", NAV_W + 14, -4)
  hv.desc = T:Text(f, 11, T.dim)
  hv.desc:SetPoint("TOPLEFT", NAV_W + 14, -26)
  hv.desc:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  hv.desc:SetJustifyH("LEFT")
  hv.desc:SetWordWrap(false)
  local sf, content = T:Scroll(f)
  sf:SetPoint("TOPLEFT", NAV_W + 4, -50)
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
  for i, b in ipairs(hv.navButtons) do
    local on = not q and i == cur
    b.sel:SetShown(on)
    b.bar:SetShown(on)
  end
  hv.navSf.UpdateScrollBar()

  local section = ns.HELP[cur]
  if q then
    hv.title:SetText("Search")
    hv.desc:SetText(("Help that mentions \"%s\", from every topic."):format(q))
  else
    hv.title:SetText(section[1])
    local faq = ns.HELP_FAQ[section[1]]
    local count = 0
    for _, e in ipairs(section[2]) do if not e.sub then count = count + 1 end end
    hv.desc:SetText(("%d things to know%s. Search finds anything in Help."):format(count,
      (faq and #faq > 0) and (", and common questions") or ""))
  end
  local width = math.max(hv.sf:GetWidth() - 12, 280)
  hv.content:SetWidth(width)
  for _, list in pairs(hv.pool or {}) do for _, p in ipairs(list) do p:Hide() end end

  local y, cards, groupTop = 0, 0, nil
  local nHead, nName, nText, nLine = 0, 0, 0, 0
  -- A group: its heading inside the top of a card; close() ends the card.
  local function close()
    if groupTop then
      cards = cards + 1
      T:PlaceCard(hv.content, cards, groupTop, y + 2, width)
      y = y + 12
      groupTop = nil
    end
  end
  local function heading(title)
    close()
    groupTop = y
    nHead = nHead + 1
    local h = piece("head", nHead, function()
      local fs = T:Text(hv.content, 11)
      fs:SetJustifyH("LEFT")
      return fs
    end)
    T:StyleHeading(h, title)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", 14, -(y + 8))
    h:Show()
    y = y + 30
  end
  local function entry(name, text, question)
    nName, nText, nLine = nName + 1, nText + 1, nLine + 1
    local n = piece("name", nName, function()
      local fs = T:Text(hv.content, 12 + (T.theme.labelAdd or 0))
      fs:SetJustifyH("LEFT")
      return fs
    end)
    local d = piece("text", nText, function()
      local fs = T:Text(hv.content, 11, T.dim)
      fs:SetJustifyH("LEFT")
      fs:SetSpacing(2)
      return fs
    end)
    local line = piece("line", nLine, function()
      local tx = hv.content:CreateTexture(nil, "BACKGROUND")
      tx:SetColorTexture(1, 1, 1, 0.04)
      tx:SetHeight(1)
      return tx
    end)
    n:SetText(name)
    local c = question and T.accent or T.text
    n:SetTextColor(c[1], c[2], c[3], 1)
    n:ClearAllPoints()
    n:SetPoint("TOPLEFT", 14, -(y + 4))
    n:SetWidth(width - 28)
    d:SetText(text)
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", n, "BOTTOMLEFT", 0, -3)
    d:SetWidth(width - 28)
    n:Show()
    d:Show()
    y = y + 4 + n:GetStringHeight() + 3 + d:GetStringHeight() + 10
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 8, -(y - 4))
    line:SetPoint("RIGHT", hv.content, "RIGHT", -8, 0)
    line:Show()
  end

  if q then
    -- Searching: the matching entries and questions of every topic, under its name.
    local function hit(a, b) return (a or ""):lower():find(q, 1, true) or (b or ""):lower():find(q, 1, true) or ns.LocalizeText(a or ""):lower():find(q, 1, true) or ns.LocalizeText(b or ""):lower():find(q, 1, true) end
    local any = false
    for _, s in ipairs(ns.HELP) do
      local list = {}
      for _, e in ipairs(s[2]) do if not e.sub and hit(e[1], e[2]) then list[#list + 1] = { e[1], e[2] } end end
      for _, fq in ipairs(ns.HELP_FAQ[s[1]] or {}) do
        if hit(fq[1], fq[2]) then list[#list + 1] = { fq[1], fq[2], true } end
      end
      if #list > 0 then
        any = true
        heading(s[1])
        for _, e in ipairs(list) do entry(e[1], e[2], e[3]) end
      end
    end
    if not any then
      heading("Nothing found")
      entry("Try another word", "Like price, flip, list, scan or sound. Or pick a topic on the left.")
    end
  else
    -- A topic's named groups each get a card; entries before the first are under the
    -- topic's own name.
    local started = false
    for _, e in ipairs(section[2]) do
      if e.sub then
        heading(e.sub)
      else
        if not started and not groupTop then heading(section[1]) end
        entry(e[1], e[2])
      end
      started = true
    end
    local faq = ns.HELP_FAQ[section[1]]
    if faq and #faq > 0 then
      heading("Questions")
      for _, fq in ipairs(faq) do entry(fq[1], fq[2], true) end
    end
    if cur == 1 then
      heading("More")
      entry("Full guide", "docs/GUIDE.md on the addon's GitHub page, with pictures.")
    end
  end
  close()
  T:HideCards(hv.content, cards + 1)
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
  -- Prices from every player's scans in tooltips (ahledger.com, Frank, November 16).
  { name = "AHledger", global = "AHledgerAPI" },
  { name = "ForeverForge_Auction", short = "ForeverForge Auction", alt = { "ForeverForgeAuction", "ForeverForge-Auction" } },
  { name = "ForeverForge", alt = { "ForeverForge_Core" } },
  -- Lists the crafts an item is used for (Frank has it, November 14).
  { name = "ProfTooltip-Forever", short = "ProfTooltip", alt = { "ProfTooltip" } },
  -- Window movers (Frank, November 25: moving the auction house window).
  { name = "BlizzMove" },
  { name = "MoveAny" },
  { name = "MoveAnything" },
}
ns.OVERLAPS = {
  { setting = "tipPrice", label = "Auction and vendor prices in tooltips",
    addons = { Auctionator = true, TradeSkillMaster = true, ForeverForge_Auction = true, AHledger = true } },
  { setting = "saleSound", label = "A sound when an auction sells", addons = { ForeverForge = true } },
  { setting = "undercutAlerts", label = "Undercut alerts", addons = { Auctionator = true, TradeSkillMaster = true } },
  { setting = "priceHelper", label = "Price helper on the Sell tab", addons = { Auctionator = true, TradeSkillMaster = true } },
  { setting = "soldSummary", label = "What sold while you were away", addons = { TradeSkillMaster = true } },
  { setting = "tipUsedBy", label = "Crafts that use an item, in tooltips", addons = { ["ProfTooltip-Forever"] = true } },
  { setting = "ahMove", label = "Moving the auction house window", addons = { BlizzMove = true, MoveAny = true, MoveAnything = true } },
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
    local dialog = ns:ShowPopup("FOREVER_LEDGER_OVERLAP", text)
    if dialog then dialog.data = turnedOff end
  end)
end)
