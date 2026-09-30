# Changelog

Every notable change to Forever Ledger is listed here, newest first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Gear with random stats: versions are now told apart. Forever's item links hold the version ("of the Whale") as a bonus ID, not where Classic kept it, so full scans found no versions. The tooltip also matches a version when its link carries extra bonus IDs, and takes the version's name from the link.
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
- On the auction house: listings worth buying are tinted on an item's buy page, with "Worth buying up to …: N available" above; search results are tinted too.
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
- "Worth to you" follows chains up to 4 steps long, for example Linen Cloth → Bolt of Linen Cloth → Heavy Linen Gloves → disenchant → Greater Magic Wand → vendor. Only the three best recipes are listed.
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
