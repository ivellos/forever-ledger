# Changelog

Every notable change to Forever Ledger is listed here, newest first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Waylaid Crates: a Crates tab listing every crate seen in your scans or bags, with its cheapest bundle at today's prices (buying 20 counts the real cost across the cheapest listings), the crate's own price, the total, Favor it pays and gold per Favor, best first. Click a crate for every bundle and what you already have; click an item to search the auction house. Bundles are read from the crate's own tooltip. Favor per crate starts as an estimate per tier and is learned from your turn-ins. Crate tooltips show the cheapest fill. It can be turned off in Settings.

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