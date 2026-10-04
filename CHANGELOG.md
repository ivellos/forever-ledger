# Changelog

Every notable change to Forever Ledger is listed here, newest first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Your auctions: an Auctions tab beside the auction house lists what you have up, your price each, the cheapest now, and undercut, cheapest or sold. Check prices looks them all up; scans and the flip watch check them too. Undercut alerts in chat with a sound (Settings, Auction house; off by themselves with Auctionator or TSM). All, Up, Undercut and Sold views; sold ones show what you get and when the gold reaches the mailbox, and the bottom line the gold on the way and in your mailbox. Cancel next undercut asks once, then cancels one undercut auction per click. Gear is checked version by version, like Search all.

### Changed
- Your characters on another ruleset or faction no longer count where they couldn't help you: crafting values and shuffles, Used by in tooltips, craft or buy, the Recipes tab's who knows it, the Enchanting skill for disenchanting, and which materials Scan materials looks up (as Have already did). On the Dashboard and Ledger, All characters means this realm and faction; characters elsewhere are listed after them, with their realm, to look at on their own.

## [0.11.0] - 2026-10-04

### Highlights
- **Shopping lists, simpler**: one kind of list with Search all and what you own; tick one box to buy from it
- **Buy queue, clearer**: Vendor flips and Shopping lists views, a glow and mouse sign where to scroll, profit you can afford
- **Spend at most**: cap what the Buy queue spends each auction house visit, or always keep some gold back
- **Ledger, All in one**: every transaction in one list; select rows to see their total
- **Sessions and dungeon runs**: a small tracker for gold an hour, and your runs and drops counted as you go
- **Price history on Ctrl**: hold Ctrl over an item for its recent range, trend and lowest price
- **Search Settings and Help**: type a word to find any setting or help entry

### Added
- Shopping lists, simpler: every list has Search all, which looks for every item at once ("checking..." and "in line" while it runs), and shows when each was checked, how many are listed, the cheapest and what you own (Have: this character and your characters on the same ruleset and faction; hover for where). Click an item to look at it on the auction house.
- Shopping lists: tick Buy from this list in the Buy queue to buy from a list. It adds Buy/Craft (a button only on items one of your recipes makes), Up to (the most you'll pay for one, filled with your usual price; off means don't buy) and Want (how many to buy, up to 9999); Have then reads 3 (20): bought for the list, then owned. Share / import is one button with two tabs; Buy again sits bottom right. The bottom line says about what buying the rest would cost.
- Shopping lists: one version of a piece of gear ("Soldier's Armor of the Monkey", typed or shift-clicked) can go on a list; Search all looks up every version, and hovering an item lists each version's price, yours first.
- Shopping lists: craft or buy. Hovering an item one of your recipes makes compares buying it with buying the materials to craft it, and says which is cheaper.
- Buy queue: Spend at most, a box at the bottom of the panel that caps what the queue spends each auction house visit, with what's left beside it. Settings, Auction house: Buy queue: always keep, to never spend below a set amount of gold.
- Ledger: an All view (opens first) with every transaction in one list: auction and vendor sales and purchases and other money (repairs, mail, loot, quests...), money in green and out in red. In every view, select rows (click, Shift-click, Ctrl-click or drag) to see their money in, out and net; hover a row for its details.
- Sessions: Start a session (top of the Dashboard, Ctrl-click on the minimap button, or /fl session start) shows a small tracker: gold an hour, gold in and out, and what you loot. Right-click folds it to one line; hover or the end summary lists gold by where it came from. Sessions show on the Dashboard.
- Dungeon runs: counted as you go (runs, time, coin and what dropped for you, per dungeon). /fl runs lists them, and item tooltips say how often something dropped for you.
- Tooltips: hold Ctrl over an item for its price history: the range of its typical price over the last 14 days, whether it's rising or falling, the usual price this month, how many are usually listed and the lowest price ever seen.
- Search boxes for Settings and Help: type two letters or more to see everything that mentions it.
- Customers window: a Silence button quiets customer alerts until you're next in a capital city, until you reload, until you log out, or always. Requests are still listed while it's quiet. /fl customers on and off.
- A coin sound when one of your auctions sells (Settings, Auction house).
- Disenchant finder: the bad and the good roll beside the average when you hover a band ("Worth per item, on average").
- ForeverForge counts as an overlapping addon: with it installed, the auction price lines in tooltips and the sale sound are switched off once, with a message.

### Changed
- Buy queue: Vendor flips and Shopping lists are two views you switch between at the top; the one you're on is the one that buys, and each has its own buttons at the bottom (Watch flips, Full scan and Scan materials; or Search my lists and Full scan). With Scroll to buy ticked, the area to scroll glows (teal for flips, purple for lists) with a mouse sign. From Magic's suggestions.
- Buy queue: a flip's profit is what you can make with your gold and limit right now, and flips are re-sorted best first each time it picks the next one. New flips you can't afford don't chime. New flips found while you look elsewhere show a count on the Buy queue tab and the Vendor flips button.
- Buy queue: the panel is a little wider, and clicking it brings it (with the auction house) in front of other windows.
- Settings: sections on the left, like Help; tick boxes left of their name, small headings in long sections, a line on every tooltip part, and defaults shown. Settings, Help and the Ledger open on their first view each time.
- Welcome: shades the whole window until you pick a button, and every button closes it.
- Tooltips: "Sell on the auction house, after 5% cut" (was "Auction house, after 5% cut"), and "avg of all 7" when 20 or fewer are listed.
- Prices can be typed as 2 50 25 or 2.50.25 (gold silver copper) and 2 50 (gold silver) as well as 2g 50s 25c; a lone number is gold in every price box. Big prices show short in narrow boxes and in full when you click in or hover.
- The import and export window: the text in a framed box under the instructions, with a "Paste here" hint.
- Dungeon runs: walking in and straight back out isn't counted as a run.

### Fixed
- Buy queue: it could buy far more of a shopping list item than you meant (601 Strange Dust for what looked like a Want of 2): the Want box was too narrow to show more than one digit. It shows all four now, and before every purchase from a list the queue checks how many the list still wants and never buys more.
- Shopping lists: Have could count purchases as still in the mail long after you'd used them. The count is per character, follows your bags, and opening the mailbox sets it to what's really there.
- Shopping lists: the list menu and name suggestions drew under other buttons; the lists panel could open behind the main window.
- Shopping lists: a typed version ("of the boar") is saved as the game writes it ("of the Boar"); adding an item already on a list with the price box empty no longer clears its price.
- Buy queue: a new flip of an item the queue had just finished with could take up to two minutes to show up.
- Price history's lowest ever seen could be above the current cheapest (it skipped today).

## [0.10.0] - 2026-10-03

### Highlights
- **Welcome and Help**: a short guide the first time you open the window, and Help by topic with common questions
- **Sell protection**: a warning, and Post held back, when a vendor would pay more than the auction house
- **Quest items**: tooltips list the quests that need an item, and say "keep it" when you'll need it
- **Buy queue**: scan buttons in the panel, the flip watch picks up when you come back, and what you can't afford stays listed
- **Crates to shopping lists**: send a crate's cheapest fill to a list, for one crate or several
- **Clearer screens**: "Auction, cheapest" in tooltips, characters from a dropdown, a Dashboard graph that fills the window
- **Saved data stays small**: old sales and prices are summed up by month and week

### Fixed
- Buy queue: flips you can't afford were looked up and dropped as "none left", so with little gold every find seemed to vanish a second after it showed up. They now stay at the bottom of the list, greyed and marked can't afford (hover for the details), and are skipped until you have the gold. Scrolling past the last thing you can afford plays the error sound once with a red "That's everything you can buy" message.
- Buy queue: the strip says plainly what's happening and what to do: "Nothing to buy yet" and why (instead of a Check button), why it's waiting for the auction house, and how to buy (click Buy, or scroll over the strip with Scroll to buy). The button reads Watch flips, Wait, Buy, Confirm or Go now. The list's Up to and Cheap headings no longer run together.
- Clearer wording: the full scan countdown reads "Full scan in 1:06"; an empty Deals tab says when your filter or search is what's hiding the deals; an empty Ledger says when sales get recorded (when you take the money from the mailbox).
- Buy queue: items you'd just bought out no longer come back when you reopen the auction house (stacks bought are taken off the saved listings, as gear already was).
- Shopping lists: the Now column shows prices short (54s, 1g 20s) so they no longer run into the Have number.
- Shopping lists: the list menu is drawn above the panel, so its buttons and tick boxes no longer show through it.

### Added
- Dashboard and Ledger: characters are picked from a dropdown (All, the character you're on, then the rest by name) instead of a button each. The Dashboard's gold graph grows with the window instead of leaving empty space, and more past sessions show when there's room.
- Help tab: a list of topics on the left and the chosen one on the right, with a Questions part for common questions players have asked. The guide has them too, under Common questions.
- Flip watch: if it was on when you closed the auction house, it starts again when you come back (it can only scan with the auction house open). Settings, Auction house: Resume the flip watch.
- Sell protection: on the auction house Sell tab, when a vendor pays more than the listing would bring after the cut, a warning says so and Post is greyed out until you click Post anyway (Settings, Auction house can make it warning only).
- Buy queue: flips found a while ago (say, before you left the auction house) show "seen 12m ago" until they're checked again, since they may be gone; after 15 minutes (when the next full scan is allowed) they're left out until a scan finds them again.
- Buy queue: Watch flips, Full scan and Scan materials are now at the bottom of the panel, always there (they become Stop watching and Stop scan while running), and the scan status shows above them. While the panel is open beside the auction house, the same buttons under the auction house window are hidden. With nothing to buy, the big button is Watch flips; scrolling never starts a scan. The Buy queue button under the auction house reads Close buy queue, lit, while the panel is open.
- Quest items: tooltips list the quests that ask for an item (about 75 Classic quests with items you can buy, for your faction), with the level and how many; in yellow with "keep it" when this character hasn't reached that level yet. The Deals tab's hover says when a deal is a quest item, since leveling players buy them. Settings, Tooltips can turn it off. Quests a character has done, ones grey for its level and other classes' quests are left out (a setting shows them all, marked).
- A welcome the first time you open the window: the five things to start with (learn your recipes, full scan, the Buy queue, Deals, Shopping lists), with buttons for the ones you can open from there. Show it again from the Help tab or with /fl welcome.
- What's new: after an update, chat lists the new version's highlights once (/fl new shows them again).
- Settings, Deal alerts: Big message on screen, to turn off the large text new finds show at the top of the screen (it can land on your windows); the chime and chat lines stay.
- Shopping lists away from the auction house: a Shopping lists button at the top of the main window, and Shift-click on the minimap button (as well as /fl lists).
- Crates tab: open a crate and click Add cheapest fill to a shopping list. The crate and its items go on a list named after the crate, counting what you already have, with prices high enough to buy them all; the Buy queue can then buy what you're short. The crate's items show indented under it. Set the crate's Want to fill several at once: every item's Want follows it. The list is temporary: each crate you fill takes one off, and the list goes with the last one (or after a week).

### Changed
- Tooltips: "Ledger price" is now "Auction, cheapest" (the lowest price listed, how many, how long ago), with "avg of cheapest 20" under it when different, so it's clear which is which.
- Crates: after the first turn-in (a one-time quest), every crate pays 5s and 10 Merchant's Favor, whatever its tier or quality, since they all become a Sealed Apprentice Crate. The tab uses that for every crate; the Pays back and Favor columns are gone, and Net cost shows green only if a crate somehow pays for itself.
- Saved data no longer grows forever. Sales and purchases are kept one by one for 30 days, then as one line per item per month for a year (the Ledger tab and Dashboard show those lines for longer ranges). Gold and money in and out are kept per day for a year, then per month. Prices are kept per day for 14 days, then as weekly averages for a year (was 30 days and 2 years). Recipes, vendors, items and characters are kept for good. The Help tab and guide list it all.
- Selling many of the same item to a vendor within a minute is saved as one entry.

## [0.9.0] - 2026-10-03

### Highlights
- **Sell speed**: tooltips and the Deals tab say how fast an item sells, judged against similar items
- **Deals filter**: show only materials, gear or other items, and search by name
- **Smarter deals**: a price that has dropped across the board is no longer called a bargain
- **Faster Buy queue**: one scroll per item, with no wait for a new search after each buy
- **Smoother window**: no more stutter on the Deals tab while scanning or crafting
- **Full character names**: two characters with the same first name no longer share saved data

### Added
- Deals tab: filter by kind (All, Materials, Gear, Other) and search by name.
- Sell speed: tooltips and the Deals tab say how fast an item sells (Fast, Steady, Slow, Rare, or No sales seen), judged against items of the same kind. It counts listings that vanished between full scans before they could have expired, using each listing's time left, and leaves out ones reposted cheaper. It shows once there are 3 hours of scans compared (and, in the first day, at least 3 sales); Watch flips gets there fastest. Deals that don't sell are rated less sure. Settings, Tooltips can turn the line off.

### Changed
- Buy queue buys faster: after buying one piece of gear it goes straight to the next cheap listing on the page it already has, instead of searching again each time. After buying every stack under the limit it moves on without a second look. Finding vendor flips no longer reads the tooltip of every listed item, which caused a short hitch after each scan. The window redraws at most once a second while scans and crafting send updates, and sell speeds are worked out once per scan, so the Deals tab no longer stutters. Crafting with the profession window open no longer re-reads every recipe and redraws the window after each craft. Deals are judged once per price change instead of on every redraw.

### Fixed
- Deals: when half or more of what's listed is that cheap, the price has dropped rather than being a bargain (Greater Magic Essence at 1s 30c "usually" 20s 90c, with 2,381 that cheap, from when essences were scarce early in the beta). Those are now rated Thin, hidden unless you tick Show thin data too, and say why.
- Characters are filed under their full name ("Iveilos Veren"), not just the first name, so two characters with the same first name no longer share one record (gold, recipes, bags and the rest). Each character's saved data moves over by itself the first time it logs in.

### Removed
- The first try at sell speed (counts of listings that went down between scans, mostly noise) is removed from saved data. Nothing used it any more, and it took about 170 KB.

## [0.8.0] - 2026-10-02

### Highlights
- **Buy queue**: vendor flips and shopping list items lined up beside the auction house; click Buy, or scroll over it, to buy the next one
- **Shopping lists**: named lists with the most you'd pay and how many you want, saved, shareable, and searched in one click
- **Craft from a list**: set an item to Craft and the list shows the materials you need, less what you have
- **Every Classic item**: type any item name and pick it, even ones above the beta's level cap
- **Vendor flip settings**: choose the least profit worth your time, as a share of the vendor price or an amount
- **Better deals and shuffles**: deals judged against an item's usual cheapest price, and no more absurd shuffle returns
- **Discord**: report bugs and ideas with /bug and /feature, and get told in your thread when a fix is live

### Added
- Buy queue: the Buy queue button under the auction house opens a panel beside it with vendor flips and your shopping list items, each in its own section. Click a section to buy from it (it gets a bright border); it looks up the next item by itself, and a click on Buy buys it. Stacks of materials take a second click to confirm the final price. It never pays more than the limit, checked again on the final price, or more than you have. Only the section you clicked looks anything up or buys, and scans never switch it, so a shopping list and the flip watch don't get in each other's way. /fl queue.
- Scroll to buy: with it ticked, each tick of the mouse wheel down over your section's top strip buys, and it keeps working while the section is empty, so new flips can be bought the moment they show up. A section on its own gets a big strip to scroll over. It starts off.
- The flip watch adds new flips to the queue within a second of finding them, and a full scan that finds some opens the queue if it's closed. Scans pause for a moment after each of the queue's lookups and buys, and the queue pauses while you search the auction house yourself, so neither replaces the page the other is using.
- Shopping lists: named lists of items with the most you'd pay each and how many you want. Add items by shift-clicking them, dragging them in, typing an item number or Wowhead link, or typing a name and picking from the suggestions. Pick a list from the dropdown; tick "Use in the buy queue" for the queue to buy from it. Search list checks everything on it in one click. /fl lists opens them anywhere, not just at the auction house.
- Want means: per list, Keep this many (bags, bank and auction house purchases still in the mail count; Buy again tops you up after you use some) or Buy this many (Bought counts purchases since Buy again; Buy again buys it all again). Items stay done once you have enough, so the queue doesn't refill them, and the list shows how far along it is (3/5, Complete).
- Craft: set a list item to Craft and the list shows the materials for the number you want, less what you have, with the most to pay for each (your usual price unless you type one). Materials vendors sell are marked. When none of your characters knows the recipe, the original Classic one is used.
- Prices can be typed any way (2g 50s, 1.5g, 25s, or a plain number for gold), with a tip showing what they'll be. "any", or Any price for a whole list, buys the cheapest until you have enough, never more than 3 times the usual price.
- Share and Import shopping lists as plain text, for Discord or a friend. Import also takes a plain list of item names or Wowhead links.
- Every original Classic item's name and recipe is built in, so you can find and plan items the game hasn't loaded yet; ones that can't be bought are marked.
- Hover Have on a shopping list to see how many are in your bags, bank, the mail and on your other characters.
- Vendor flips have their own settings: the least profit worth your time, as a share of the vendor price (0% counts anything below it) and as an amount each.
- Crates: the money a turn-in pays back is taken off the cost ("Pays back" and "Net cost" columns), and crates that pay back more than they cost show a green profit.
- Prices seen at a merchant note your standing with them: "Vendor sells it for 4c at Honored".
- Discord: the Help tab and guide link the Forever Ledger Discord, where /bug and /feature report bugs and ideas. Your report becomes a GitHub issue; your replies are copied to it, and your thread is told when the fix is live.
- "Your data" in the Help tab, the guide and the README: everything stays on your PC.
- /fl perf also shows memory use, how long the addon took to load, and the biggest parts of the saved data.

### Changed
- The Vendor flips tab is gone: vendor flips are bought from the Buy queue. The Disenchant finder is now a tab of the same panel, next to Shopping lists.
- Deals are measured against the price an item is usually cheapest at, not its typical price, so there are far fewer and far more believable deals.
- Plays nice with Auctionator and TSM: the first time either is found, Forever Ledger turns off what they already cover (for now the price lines in tooltips) and says so once, with a button to keep them on.

### Fixed
- Shuffles that end on the auction house showed absurd returns (Simple Linen Pants 10,564%); what selling brings now uses the item's usual cheapest price.
- What a vendor pays follows the game's current item data, and price history from before a vendor price changed is ignored (crafted wands now sell for 1 copper, and the Greater Magic Wand stopped showing as a deal).
- Items vendors won't buy (essences, dust, shards) showed "Sell to vendor 1c"; they show no vendor price now.
- Gear flips dropped off as soon as their cheap listings were gone or bought, not at the next full scan, and gear purchases are logged under the right item.
- Flip alerts follow the flips exactly and fire as soon as a flip is found.
- The flips list no longer works out every shuffle each time a price is saved, which caused a small hitch every few seconds.

## [0.7.0] - 2026-09-30

### Highlights
- **Deals tab**: listings well below their usual price, with why each one is a deal and your profit after the auction house cut
- **Buy badges**: listings worth buying on the auction house now say why: FLIP, DE, CRAFT or USE
- **Gear versions**: "of the Eagle" and "of the Whale" are priced separately
- **Customer finder**: also spots requests for Mage portals, Warlock summons and Rogue lockpicking, each with its own ad button and a switch in Settings
- **Help tab**: every feature explained in game, plus a tidier Settings page
- **One-line tooltips**: an option to show just what an item is worth to you, with Shift for the rest

### Fixed
- Gear with random stats: versions are now told apart. Forever's item links hold the version ("of the Whale") as a bonus ID, not where Classic kept it, so full scans found no versions. On the auction house's list, where one row covers every version ("Items in this group may vary"), the tooltip lists the cheapest versions on sale by name instead of a wrong "this version: none listed". Version prices from a full scan are kept when a later search saves the item's price.
- Shuffles: two groups of disenchant shuffles took turns disappearing on every refresh. The game only keeps so many item details in memory, and working out every shuffle pushed half of them out each time; items it had forgotten got no disenchant value. The addon now remembers item details itself for the session.
- Flip watch: your own searches are saved even while a watch check is running (Shadowgem and Linen Bandage stayed on Vendor flips after buying), the watch waits 20 seconds after you search so it doesn't talk over you, and it no longer re-checks gear: each check came back with a different stat version's listings, so disenchant shuffles kept appearing and disappearing. Gear prices come from full scans.
- Materials a vendor also sells now cost whichever is cheaper, the vendor or the auction house. A limited vendor's Strange Dust at 8s was used instead of 2s 35c on the auction house, which hid the Minor Wizard Oil shuffle. Same fix for recipe profits and crate fills.
- Shuffles: some disenchant shuffles came and went on every refresh. When the best use of a material led back to the item being valued, the material counted as worthless instead of using its next-best use, and which items were hit depended on the order they were worked out.
- Vendor flips: opening an item on the auction house now saves the prices it shows, so Refresh drops a flip whose cheap listings were just bought (it stayed until the next scan). Gear with random stats is left to the scans.
- Trainers view: a trainer named by a city guard (Lucan Cordell, Shaina Fuller, Arnold Leland) is no longer listed twice; a Classic entry takes the guard's position instead (Shaina Fuller has moved in Forever).
- Flip watch: between checks the status corner counts down ("Watching flips: next check in 25s, full scan in 12 min"), so a quiet spell doesn't look like it stopped.
- One-line tooltips: pressing Shift adds the full details to the tooltip that's showing (they stay until you hover something else); holding Shift before hovering shows them too.
- Flip watch: the Vendor flips tab, when open, is worked out again after each pass, so its list and time stay current.
- Shuffles and Vendor flips: the line at the bottom is shorter and stops before the scan status, so it fits the smallest window.
- Customers: the empty Work done message wraps instead of running off the window.
- Customers: someone asking again moves their request to the top with the newest message instead of adding a second row.
- Dashboard: the gold graph's scale shows silver under 100g (it read "11g" on every line when gold only moved by a few silver).

### Changed
- Help tab: laid out like Settings, with a header per section and each topic's name beside its text.
- Settings are grouped more clearly (Values and shuffles, Deal alerts, Tooltips, Auction house, Customers, Other), each with its name and description together and the control beside it.
- Auction house: listings worth buying stand out, with a green tint, a green bar on the left and (on gear) a badge saying why: FLIP (sell to a vendor), DE (disenchant), CRAFT or USE. The line above says it too ("Disenchant: 573 available at 16s 92c or less"). The line above the list reads "BUY: N available at X or less" in green, or turns red with "None left" once someone else has bought them.
- Dashboard gold graph: the scale always starts at 0g, and each step is coloured by its own direction (green up, red down) instead of the whole graph taking one colour.

### Added
- Customers: class services. On a Mage the finder spots requests for portals (from level 40) as well as food and water; on a Warlock, summons (from level 20); on a Rogue, lockpicking and lockboxes (from level 16). Each has its own ad button ("Sell portals" lists the cities you can portal to). The window is a little wider to fit them. Settings, Customers has a switch for each service and for crafting requests, which also hides its ad button.
- Deals tab: listings well below their usual price, with the price now, the usual price, how many are cheap, profit after the auction house cut, and how sure the deal is (Good, Fair, Thin). Hover a deal for why it's one, in short labelled sections (right now, usually, if you resell, how sure): days of scans behind the usual price, the range most days, how many are usually listed and the next listing up. Thin data (a few days, jumpy prices) is hidden unless you ask for it, and a new setting sets the least resale profit (10s to start). After a scan, chat gives one line instead of a long list; `/fl deals` opens the tab. Scans now also note how many of each item are listed each day.
- Gear with random stats ("of the Eagle"): full scans now note each version's price, and the tooltip shows "this version (of the Eagle): 18s, 6 listed" under the item's price, since versions of one item can sell for very different amounts.
- Recipes tab: a recipe with no known source whose recipe item is on the auction house (many new Forever recipes, like Savory Whimsyfin Delight) shows "On the auction house: 6g (12 listed)" instead of "trainer, or new in Forever".
- Help tab: every feature explained in short, and the commands. The same guide is on GitHub (docs/GUIDE.md), with pictures to come.
- If you run TSM or Auctionator, a one-time question at login offers the one-line tooltip (Shift for more), since those addons already show prices in tooltips.
- Tooltip settings (tester feedback: tooltips were getting long): "Tooltip size" can be "One line, Shift for more", which shows only what an item is worth to you until you hold Shift; each part of the tooltip (prices, Worth to you, Buy at or below, Disenchants to, Used by, crate fill) can be turned off; and "Worth to you" lists the best 3 ways by default (1 to 10, with "and N more ways").
- Trainers view: ask a city guard for a profession trainer and the spot the guard marks (for example "Duncan's Textiles" for Tailoring in Stormwind) is added with a Pin, marked "(guard)". These are Forever's own positions, so they're more reliable than the Classic ones.
- Work log: the Customers window has a "Work done" view (also `/fl work`). Every completed trade that looks like a job, where you enchanted something in the "will not be traded" slot, got paid, or traded with someone who asked in chat, is logged with who, what (the enchant, or the items you gave) and the gold. A matching request is marked done. The footer shows today's and the last 7 days' earnings and jobs.
- Customer finder: when someone in chat asks for something your current character can do ("LF enchanter to enchant wrists", "anyone tailoring?", "WTB" an item you can craft, or water and portals for Mages), a small Customers window opens listing the request with Whisper, Invite and dismiss buttons (hover for the full message), with a soft sound. `/fl customers` opens it any time; requests stay for an hour. Chat lines are optional in Settings.
- Ads in the Customers window: "Advertise my crafting" posts one line to Trade (or Trade (Services) if you're not in Trade), with links to your professions (saved when you open each profession window), and on a Mage "Sell food and water" posts "WTS Mage water and food [water] [food]" with links to the best water and food your Mage can conjure. Hover a button to see the text; right-click to change it. Each ad can be posted once a minute (the two ads wait separately). Crafters' own ads ("LFW", "WTS") are skipped, and each player alerts at most every 3 minutes. Settings has on/off switches for it and its sound. `/fl customer <message>` shows whether a message would alert.
- Guard directions test: when a city guard marks a trainer on your map, the addon prints the flag's name and position and saves it, to see whether guards can confirm trainer locations. `/fl probe` shows whether the game supports it.
- Disenchant finder: hover an item level band for what one item gives, for armor and/or weapons (whichever are ticked): the chance of each material and how many, what that's worth per item at today's prices, your own disenchant results for that band, whether it's tested in Forever or Classic's table, and the Enchanting skill needed.
- Flip watch: a "Watch flips" button on the auction house (or `/fl watch`). While the auction house stays open it runs a full scan whenever one is allowed (about every 15 minutes) and quietly re-checks the items closest to their vendor price in between. A new flip chimes and opens the Vendor flips tab. It only looks; buying is always your click. It stops when the auction house closes, with `/fl watch` again, or by clicking "Stop watching". While it runs, an animated eye (like the group finder's) shows on the button.

### Changed
- Vendor flips are quicker to buy: click a flip and the auction house searches for it straight away (right-click, or shift-click, for the details and Work it). When a scan finds items below vendor price, the Vendor flips tab opens instead of a list in chat (can be turned off in Settings: "Open Vendor flips after a scan").

### Fixed
- The auction house's "Worth buying up to" for items a vendor buys now uses the same safety margin as Vendor flips, so both show the same price (it said 49c where the flip said 45c).

## [0.6.1] - 2026-09-28

Fixes from the first testers.

### Fixed
- Vendor flips and "below vendor price" deal alerts now agree. Flips count only the listings cheap enough to profit, at their own prices (they used the average of the cheapest 20, which hid flips like a few cheap Dirty Blunderbusses), and deal alerts say how many are listed at the deal price instead of everything listed (it said 935 Okra when only 23 were cheap enough).
- With Auctionator installed, the Disenchant finder, Full scan and Scan materials buttons covered Auctionator's tabs at the bottom of the auction house. They now sit one row lower.

### Added
- Arcane Salvager: disenchants done while one is up are logged separately, so `/fl de` shows what it adds next to the same items without it.

## [0.6.0] - 2026-09-28

A Recipes tab with where to get every recipe, a Waylaid Crates tab, and better auction house handling. Recipe sources from original Classic are marked "(Classic)" until you see them in game.

### Added
- Recipes tab: a sub-tab for each profession your characters have, plus Cooking, First Aid and Fishing (anyone can learn those). Every recipe with the skill needed (green when one of your characters has it), who knows it, where it comes from, a type and profit per craft at today's prices, even for recipes nobody knows yet. Types: Flip or shuffle, Crafts that sell, Enchant service, Not for sale, Not profitable. Filter by known or not, by type, or by name. The list starts on Known, grouped by type, best first.
- Your own types: right-click a recipe to set its type, shift-right-click to put it back to automatic, "Clear my types" (asks first) to clear them all, and "Use my types" to switch between yours and the automatic ones.
- Where recipes come from: vendors, trainers and drops you see in game are recorded (with position), and original Classic data fills in the rest for Tailoring, Enchanting, Cooking, First Aid and Fishing: every vendor that sold it, the mobs it drops from with zones and drop chances, and quests. Hover a recipe for all of them. Trainer recipes say which tier teaches them ("Any Journeyman+ Tailoring trainer"). Recipes only the other faction can get are marked "Horde only: neutral AH". Drop recipes show their auction house price.
- Map pins: a Pin button on every vendor, trainer or mob with a position, including Classic ones you haven't visited yet.
- Trainers view: every trainer you've visited, plus Classic trainers for these professions (Alliance and neutral), with profession, tier, notes and a pin.
- Waylaid Crates tab: every crate seen in your scans or bags, its cheapest bundle at today's prices (buying 20 counts the real cost across the cheapest listings), the crate's own price, the total, Favor it pays and gold per Favor, best first. Click a crate for every bundle and what you already have. Bundles are read from the crate's tooltip. Favor is estimated per tier (green crates double) and learned from your turn-ins. Crate tooltips show the cheapest fill. Can be turned off in Settings.
- The addon remembers what each character on this account has in their bags and bank. The Crates tab shows "you have N (bags, bank, alts)"; hover for which alt has what.
- When another addon (Auctionator, TSM and others) runs a full auction house scan, Forever Ledger reads it too.
- Prices seen at a neutral auction house (Booty Bay, Gadgetzan, Everlook, and the Waylaid Crate trade posts if theirs are neutral) are kept separate from your faction's.
- `/fl book` shows how much recipe data has been gathered.

### Fixed
- A full scan stopped with "integer overflow" when something was listed at the maximum price. Price history now handles any amount, and a problem saving history can no longer stop a scan.
- Trainers keep their title, profession and tier from an earlier visit, and the profession is taken from the title ("Journeyman Enchanter") when the trainer list doesn't say.

## [0.5.0] - 2026-09-28

Disenchanting tools and one-click steps for working a shuffle. The item level 16-20 disenchant table was confirmed in the beta (22 items: 2.05 Strange Dust and 0.36 Greater Magic Essence each).

### Added
- Work it has a "Do it" button for every step of a shuffle, in order: each craft (the first makes your Runs number, later ones as many as your bags allow; if its profession window is closed, the first click opens it and the second crafts), splitting or combining essences, and disenchanting.
- Disenchant button: "Disenchant: <item> (N left)" disenchants the next of that shuffle's items in your bags with one click. It only ever picks the shuffle's own items.
- Disenchant finder: a panel beside the auction house listing green armor and weapons from your last scan by item level band, armor or weapons, and "only worth disenchanting", with price, disenchant value and profit. Click an item to search for it.
- Disenchant recorder: every disenchant is logged. `/fl de` shows the totals per group next to what the addon expects; `/fl de reset` starts a fresh count.
- `/fl perf` shows which parts of the addon take the most time.
- `/fl probe` reports what the game gives for planned features (Merchant's Favor, chat channels, profession links, crate tooltips, trades, currency vendors). It only reads and prints.

### Changed
- The disenchant table covers green items up to item level 65 (Classic's figures above level 25, assumed until tested). Disenchanting only counts when one of your characters has the Enchanting skill the item level needs.
- Less work in the background: item values are rebuilt less often, item names are remembered (lists no longer flicker between "item 727" and the name), and the addon only listens to your own spell casts.

## [0.4.0] - 2026-09-27

Live sync between two accounts, so an auction house character's scans reach your main. The whisper route was checked in the beta; syncing two of your own accounts can only be tried at launch.

### Added
- Live sync: `/fl pair First Last` on each character (Forever names have a first and last name). While both are online, auction house prices from the last 48 hours, characters and recipes, and vendor prices are sent automatically a few seconds after they change. Newer data wins, as with Import; gold, the ledger and sessions stay on their own account. Pairing is remembered, and each login only sends what changed; anything cut off is sent again next time.
- `/fl sync` shows the status (also on the Characters tab), `/fl sync now` sends everything, `/fl sync ping First Last` checks that a hidden whisper reaches someone online and saves the name form that works, `/fl sync whoami` shows how the game names your character.

### Fixed
- The Dashboard gold graph no longer dips to 0c: 0-gold readings the game gives around login and logout are skipped, and ones already saved are removed.

## [0.3.0] - 2026-09-27

A new look, a dashboard and a ledger, deal alerts, and tools for working a shuffle from start to finish. Tested on the Forever beta.

### Added
- Dashboard: a gold graph for all characters or one, over a day, week, month, 3 months, year or all time (green when gold went up, red when it went down; hover for the amount at any point). Below it: highest and lowest gold, auction house sales and purchases per day, the biggest single auction house sale and purchase, and Sales, Expenses and Profit with totals, per day and top items. Recent sessions at the bottom.
- Ledger tab: every sale and purchase (auction house and vendor) with time, item, quantity, price each, total, where, buyer and character; Resale, for items both bought and sold, with average buy and sell prices and profit; and Other money (fees, repairs, mail, trade, loot, quests, training, flights) by day. Filter by time, character and item name, sort by any column. Identical trades within a minute are one row.
- Work it: a small window for doing one shuffle, opened from any shuffle or vendor flip. Click an item to search the auction house for it or buy it from the open vendor (one click, one purchase). A Craft button starts the first craft; if that profession's window is closed, the first click opens it and the second crafts. One Runs number sets what to buy, how many to craft and the session goal.
- Sessions: count what you spend on a shuffle's materials, earn from its products, and runs done, with profit and profit per hour, until you stop. A chime and "Goal reached" when you hit your goal. `/fl session` opens it.
- Deal alerts after each scan (chime, on-screen message, chat list): listings well below their usual price (percent and period of your choice, from this addon's price history or TradeSkillMaster's when installed), or below what a vendor pays. `/fl deals` lists them.
- On the auction house: listings worth buying are tinted on an item's buy page, with "Worth buying up to â€¦: N available" above; search results are tinted too.
- History, recorded from now on: each character's gold, money in and out by source, auction house sales (with quantity and buyer) and purchases, vendor trades per item (12 months), and price history per item (daily for 30 days, weekly for 2 years, all-time lowest and average). `/fl money` shows today's money.
- Settings tab with controls for every setting.
- The ledger window can be resized, and remembers its size.

### Changed
- New look: dark and flat with an accent colour, matching EllesmereUI (its font and your accent colour are used when it's installed). Tabs: Dashboard, Shuffles, Vendor flips, Ledger, Characters, Settings.
- Shuffles are a table with sub-tabs (Sells to a vendor, Sells on the auction house, Limited supply) and sortable columns: an icon per step, name, steps, profit, return, profit per hour, and runs (how many times you could do it profitably with what's listed now). Click a row for what to buy and every step. Vendor flips use the same table.
- "One-off deals" are now called "Limited supply".
- Scans save how many are listed at each of the cheapest 20 prices, so runs and vendor flips count only listings cheap enough to profit.
- The scan buttons on the auction house sit just below its window.

## [0.2.0] - 2026-09-26

Value engine, shuffle finder and vendor flips. Tested on the Forever beta. The item level 16-20 disenchant table is still the Classic one and hasn't been checked in Forever yet.

### Added
- "Worth to you" on item tooltips: the best of selling on the auction house (after the cut), selling to a vendor, or crafting it with a known recipe and selling the result. Every option is listed, best first.
- Vendor floors: the guaranteed value of a material when a known recipe turns it into something a vendor buys.
- Disenchant values for green armor and weapons up to item level 20: a "Disenchant" option in "Worth to you", a "Craft X, disenchant" option for materials, and a "Disenchants to about" tooltip line. Only shown when one of your characters has Enchanting. Crafted wands and other Enchanting products are skipped, since Forever doesn't allow disenchanting them.
- Essence conversions in "Worth to you": splitting a greater essence into 3 lesser, and combining 3 lesser into a greater, for every essence type. Disenchant values use them too.
- "Worth to you" follows chains up to 4 steps long, for example Linen Cloth â†’ Bolt of Linen Cloth â†’ Heavy Linen Gloves â†’ disenchant â†’ Greater Magic Wand â†’ vendor. Only the three best recipes are listed.
- Inside a chain, auction house prices with fewer than 5 listings are ignored, so one overpriced listing can't inflate values.
- Shuffle finder: `/fl shuffles` lists the best shuffles in two groups, ones that end with vendor sales (safe) and ones that end on the auction house (depend on buyers). Each shows what to buy, profit per craft, return and a rough profit per hour. `/fl shuffles all` lists everything, including one-off deals with fewer than 5 listed.
- Shuffles tab in the ledger window: the same two groups as `/fl shuffles`, one row each with profit, return and profit per hour. Click a row to see what to buy and each step. Refresh recalculates. Items that disenchant the same way are grouped into one row, for example "Item level 16-20 green armor (27 items)".
- Vendor flips tab: things you can buy on the auction house and sell straight to a vendor for more, ranked by total profit on offer. They're no longer mixed in with shuffles.
- "Use recipes from" checkboxes on the Shuffles tab: choose which characters' recipes count, for shuffles and tooltip values alike.
- "Buy at or below" on tooltips for anything you can craft with, disenchant or convert: the most worth paying, after the safety margin. Green when the current price is already below it.
- `/fl margin` sets the safety margin for shuffles (default 10%), and `/fl seconds` sets the seconds per craft used for profit per hour (default 3).
- `/fl cut` shows or changes the auction house cut used in values (default 5%).
- Minimap button: click to open or close the ledger, right-click for shuffles, drag to move it. `/fl minimap` hides or shows it.

### Changed
- Two scan buttons, in the ledger window and on the auction house: "Full scan" (reads everything in seconds) shows "Ready" or a countdown to when Blizzard allows the next one (about every 15 minutes), and "Scan materials" scans what your recipes use.
- `/fl scan` does a full scan when one is allowed and scans your materials otherwise. `/fl scan materials` forces the materials scan. If the auction house doesn't send a full scan within 30 seconds, the materials scan runs instead.
- The materials scan waits 3 seconds instead of 6 for items with no reply, and tries those items once more at the end.
- The "scan finished" and "full scan done" messages say how long the scan took.

### Fixed
- Auction house scans read prices for items sold one at a time (bags, oils, rods) far too low, for example Linen Reagent Bags at 19c instead of 13s. Forever already reports these per item. Full scans weren't affected.
- The "Scanning" line in the ledger window now clears after a full scan finishes.

## [0.1.0] - 2026-09-26

First test version for the Forever beta.

### Added
- Character profiles: level, faction, professions and skill, saved on login.
- Recipe capture: every learned recipe and its materials, saved when a profession window opens.
- Vendor prices: vendor sell prices from the game, vendor buy prices from merchant windows, with defaults for common thread, dye and Simple Wood.
- Auction house scanning of every material your characters use, plus an optional full scan.
- Prices from Auctionator, TSM and Auctioneer when your own scan is older than 12 hours.
- Tooltip lines for price, vendor cost and which characters use an item.
- Export and import between accounts, and a plain-text price list.
- `/fl api` report for testing on the beta.
