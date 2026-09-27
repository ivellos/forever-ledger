# Forever Ledger

A World of Warcraft: Forever addon for crafters who like to make gold. It remembers every character's professions and recipes, tracks vendor and auction house prices, and finds profitable shuffles: things you can buy, craft, disenchant or convert, and sell for more.

> **Status:** testing on the Forever beta. Expect bugs, and please report them.

## Features

- **Dashboard.** A gold graph over any range, with sales, expenses, profit and your best items, for one character or all.
- **Ledger.** Every sale and purchase, a resale view for your flips, and other money in and out, with search and filters.
- **Work it and sessions.** Open a shuffle, click items to find them on the auction house or buy them from a vendor, start the craft, and track what one session of it earned.
- **Deal alerts.** A chime after a scan when something is listed well below its usual price, or below what a vendor pays.
- **Tinted auction house.** Listings worth buying are highlighted on the auction house itself.
- **Disenchanting tools.** A finder beside the auction house lists greens by item level with their disenchant value, a one-click Disenchant button works through a shuffle's items, and a recorder checks what you actually get.
- **One click per step.** Work it has a button for each craft, split and disenchant in a shuffle.
- **What's it worth to you?** Every tooltip shows an item's best value: selling it on the auction house (after the cut), selling it to a vendor, disenchanting it, splitting or combining essences, or crafting it into something worth more, following chains up to 4 steps long.
- **Vendor floors.** When a recipe you know turns an item into something a vendor buys, that sets a guaranteed minimum value for its materials.
- **Buy at or below.** The most worth paying for a material, after a safety margin, shown in green when the auction house price is already lower.
- **Shuffle finder.** A ranked list of shuffles, split into ones that end with vendor sales (safe) and ones that end on the auction house (depend on buyers), with what to buy, the steps, profit, return and a rough profit per hour. Choose which characters' recipes count.
- **Vendor flips.** Things listed on the auction house for less than a vendor pays.
- **Character profiles that build themselves.** Level, professions, skill and every known recipe with its exact materials, saved as you play.
- **Vendor and auction house prices.** Vendor prices read from the game and from merchant windows. A full auction house scan reads every listing in seconds (Blizzard allows one about every 15 minutes), and a materials scan checks what your recipes use in between.
- **Works with Auctionator, TSM and Auctioneer.** Uses their prices when your own scan is out of date.
- **Live sync between accounts.** Pair your main with an auction house character on another account, and prices, recipes and vendor prices flow between them while both are online.
- **Export and import.** Move data between accounts by copy and paste.
- **Minimap button.** Click to open the ledger, right-click for shuffles.
- **Looks at home with EllesmereUI.** Uses its font and your accent colour when it's installed.

The addon suggests; you click. Every craft, purchase and auction still needs your own click, as Blizzard requires.

## Install

1. Download the latest `ForeverLedger-x.y.z.zip` from [Releases](../../releases).
2. Unzip it into your Forever client's `Interface\AddOns` folder, so you end up with `Interface\AddOns\ForeverLedger\ForeverLedger.toc`.
3. Start the game and make sure Forever Ledger is ticked in the AddOns list.

## Commands

| Command | What it does |
|---|---|
| `/fl` | Open or close the ledger window |
| `/fl scan` | Full scan if one is allowed, otherwise scan your materials (auction house must be open) |
| `/fl scan full` | Scan every listing (Blizzard allows this about every 15 minutes) |
| `/fl scan materials` | Scan just the materials and products of your recipes |
| `/fl stop` | Stop a scan |
| `/fl shuffles` | List the best shuffles and vendor flips in chat (`/fl shuffles all` for everything) |
| `/fl cut 5` | Auction house cut used in values, in percent |
| `/fl margin 10` | Safety margin for shuffles and "buy at or below", in percent |
| `/fl seconds 3` | Seconds per craft, used for profit per hour |
| `/fl deals` | List current deals (`/fl deals settings` for the options; they're also in the Settings tab) |
| `/fl session` | Open the Work it window for the running session |
| `/fl money` | Today's money in and out for this character |
| `/fl de` | Disenchant results so far, against what the addon expects (`/fl de reset` to start over) |
| `/fl perf` | What the addon has spent time on (for lag reports) |
| `/fl pair First Last` | Pair with your character on another account for live sync (do it on both) |
| `/fl sync` | Sync status; `/fl sync now` sends everything, `/fl sync ping First Last` checks whispers reach someone |
| `/fl minimap` | Hide or show the minimap button |
| `/fl pull` | Copy prices from Auctionator, TSM or Auctioneer |
| `/fl source auto` | Choose where prices come from: `auto`, `own`, `auctionator`, `tsm`, `auctioneer` |
| `/fl export` / `/fl import` | Move data between accounts |
| `/fl csv` | Prices as plain text |
| `/fl tooltip` | Turn tooltip lines on or off |
| `/fl api` | Show which game functions are available (useful in bug reports) |
| `/fl debug` | Turn debug messages on or off |

## Reporting a bug

Open an [issue](../../issues/new/choose) and include the output of `/fl api` and any error text from BugSack.

## Project layout

| Path | What it is |
|---|---|
| `*.lua`, `ForeverLedger.toc` | The addon itself |
| `CHANGELOG.md` | What changed in each version |
| `docs/` | Guides for testing, developing and releasing |
| `tools/flip-calculator.html` | The web version of the flip calculator |
| `.github/` | Automatic checks, release builds and the bug report form |

## License

MIT. See [LICENSE](LICENSE).
