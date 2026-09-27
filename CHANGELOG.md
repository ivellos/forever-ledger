# Changelog

Every notable change to Forever Ledger is listed here, newest first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Dashboard: a gold graph (hover for the amount at any point) and Sales, Expenses and Profit boxes with totals, per day and top items, for all characters or one, over a day, week, month, 3 months, year or all time. The graph is green when gold went up over the range and red when it went down. A row above the boxes shows the highest and lowest gold, auction house sales and purchases per day, and the biggest single auction house sale and purchase. Recent sessions below.
- Auction house sales also record how many were sold and to whom, for the coming Ledger.
- New look for the ledger window: dark and flat with an accent colour, matching EllesmereUI (and using its font and your accent colour when it's installed). Tabs across the top: Dashboard, Shuffles, Vendor flips, Characters (the old overview) and Settings. Dashboard and Settings show a summary for now; their full versions come next.
- "One-off deals" in the Shuffles tab are now called "Limited supply".
- The Shuffles tab is a table: sub-tabs for "Sells to a vendor", "Sells on the auction house" and "Limited supply" (with counts), and columns for steps, shuffle, profit, return, profit per hour and runs (how many times you could do it with what's listed, limited by the scarcest auction house purchase). Hover a column heading for what it means. Click a column heading to sort. Each row shows an icon per step (profession, disenchant, split, vendor or auction house) and the item's icon; hover for the steps. Click a row to open what to buy, with item icons, next to the numbered steps. Vendor flips use the same table, with "Listed" and "If all bought" columns.
- Shuffle rows are simpler: the name is just the item or recipe, a Steps column gives the count, and hovering a step icon names that step. Runs, and "Listed" on vendor flips, count only listings cheap enough to make a profit (scans now save how many are listed at each of the cheapest 20 prices).
- The ledger window can be resized from its bottom-right corner, and remembers its size.
- "Work it" on each opened shuffle or vendor flip: a small window with the shopping list and steps. Click an item to search the auction house for it, or to buy it from the open vendor (choose how many runs to buy for). Each click is one search or one purchase.
- A "Craft" button in Work it starts the shuffle's first craft as many times as the Runs number says. If that profession's window isn't open, the first click opens it (switching to the right profession if needed) and the second crafts.
- Work it has one Runs number for what to buy, how many to craft and the session goal.
- The ledger and Work it windows come fully to the front when clicked, instead of mixing where they overlap.
- On the auction house, an item's buy page tints the listings worth buying (at or below its "buy at or below" price, or below what a vendor pays), with a line above saying how many are available at that price. The search results list is tinted too, each row by its own item's limit. Can be turned off in Settings.
- Sessions with a goal play the chime and show "Goal reached" when the runs reach it.
- The scan buttons on the auction house window moved to its bottom-right corner, where they're no longer hidden.
- Sessions: start one from the Work it window, optionally with a goal. It counts what you spend on the shuffle's materials, what you earn selling its products, runs done (crafts, counted from "You create" messages; disenchants; or items sold), profit and profit per hour, until you stop. The Dashboard lists the running session and the last five. `/fl session` opens it.
- The Settings tab has controls for every setting: number boxes with - and +, rows of choices, a money box and checkboxes. Changes apply straight away. The slash commands still work.

### Added
- History for the coming dashboard: each character's gold over time, money in and out each day by source (auction house sales, purchases and fees, vendors, repairs, mail, trade, loot, quests, training, flights), and a log of auction house sales and purchases.
- A log of vendor purchases and sales per item (which item, how many, how much), for the coming session tracker. Quick sales that arrive as one gold change are split back into the items sold.
- Price history per item: daily for 30 days, weekly for 2 years, and all-time lowest and average.
- `/fl money` shows today's money in and out for the character you're on.
- Deal alerts after each scan (chime, on-screen message, chat list), two kinds:
  - Below usual price: at least 20% below the item's usual price over all time, or over the last week, month, 3 months, 6 months or year. Starts once there are 3 days of price history.
  - Below vendor price: listed at least 10% below what a vendor pays, optionally with a least profit per item.
- Usual prices can come from TradeSkillMaster's historical prices when TSM is installed: `/fl deals history auto` (TSM where it has a price, otherwise this addon's own scans; the default), `local` or `tsm`. For a week or a month TSM's market value is used, for longer periods its historical price.
- `/fl deals` lists current deals. `/fl deals usual 20`, `/fl deals period month`, `/fl deals history auto`, `/fl deals vendor 10%`, `/fl deals vendor 1s` and `/fl deals sound` change the settings. `/fl deals` lists current deals, `/fl deals 40` changes the threshold, `/fl deals sound` turns the chime on or off.

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
