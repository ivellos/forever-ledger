# Forever Ledger

A gold-making addon built specifically for **WoW Forever**. It scans the auction house and shows what every item is actually worth to *you*: sell it, vendor it, disenchant it, or craft it into something better. Then it points you at the best buys.

> **Status:** pre-release, tested in the Forever beta and updated often. Expect the odd rough edge, and please report it.

## Features

- **Tooltips that answer "what's this worth?"** The best way to turn an item into gold, the most it's worth paying, what it disenchants into, and which of your recipes use it. One line with Shift for more, if you prefer.
- **Deals.** Listings well below their usual price, with why each one is a deal: the usual price and how many days of scans it's based on, the price now, the next listing up, and the resale profit after the auction house cut. Each deal is rated Good, Fair or Thin.
- **Vendor flips.** Things on the auction house for less than a vendor pays. Watch flips keeps scanning while the auction house is open and chimes when one shows up.
- **Shuffles.** Buy materials, craft, disenchant or convert, and sell, ranked by gold per hour. Work it walks you through each step with one-click buttons.
- **On the auction house.** Listings worth buying get a green bar and a badge saying why (FLIP, DE, CRAFT, USE).
- **Disenchant finder.** Green armor and weapons by item level, with what each is worth to disenchant and the odds of each material.
- **Recipes and trainers.** Every recipe for your professions: who knows it, where to get it, the skill needed and profit per craft.
- **Waylaid Crates.** The cheapest way to fill each crate at today's prices, and gold per Merchant's Favor.
- **Customer finder and ads.** Spots people in chat asking for what your character can do (enchanting, crafted items, Mage water and portals, Warlock summons, lockpicking), with Whisper and Invite buttons and one-click ads for Trade.
- **Dashboard and Ledger.** Gold over time, every sale and purchase, resale profit, and where the rest of your money goes.
- **Gear versions.** "Of the Eagle" and "of the Whale" are priced separately.
- **Two accounts?** Live sync shares prices and recipes between them while both are online.
- **Works with Auctionator, TSM and Auctioneer** prices and full scans, and looks at home with EllesmereUI.

The addon suggests; you click. Every craft, purchase and auction still needs your own click, as Blizzard requires.

## Your data

Forever Ledger keeps everything in its saved file on your own PC (`WTF\Account\...\SavedVariables\ForeverLedger.lua`). Nothing is sent to the author or anyone else.

- **What it keeps:** auction house and vendor prices and their history; recipe, vendor and trainer locations you've seen; your characters' professions and recipes, gold over time, sales, purchases and vendor trades; bag and bank contents (this account only); requests the customer finder spotted in chat; and your work-done log.
- **What it sends:** only two things, and only when you choose to. Live sync whispers prices and recipes to **your own** paired character (off until you use `/fl pair`), and the ad buttons post your ad in Trade chat when you click them.
- **Export** copies your data as text for you to paste on your other account; it goes nowhere by itself.

If a feature ever shares anything with other players (an idea on the roadmap: sharing where vendors and trainers are, so everyone's data fills in faster), it will be world facts only, never names, gold or bags, it will ask first, and you can turn it off.

## Install

The easiest way is an addon manager: **Forever Ledger** is on [CurseForge](https://www.curseforge.com/wow/addons/forever-ledger) and [Wago](https://addons.wago.io/addons/forever-ledger), so the CurseForge app, Wago app or WowUp install it and keep it updated.

By hand:

1. Download the latest `ForeverLedger-x.y.z.zip` from [Releases](https://github.com/ivellos/forever-ledger/releases), the file under "Assets", not "Source code".
2. Open the zip and drag the **ForeverLedger** folder inside it into your Forever client's `Interface\AddOns` folder, so you end up with `Interface\AddOns\ForeverLedger\ForeverLedger.toc`. The folder must be named exactly `ForeverLedger`, with no version number and no extra folder in between, or the game won't see it.
3. Start the game and make sure Forever Ledger is ticked in the AddOns list, then type `/fl`.

## How to use it

The [guide](https://github.com/ivellos/forever-ledger/blob/main/docs/GUIDE.md) explains every feature, with pictures. The same text is in the game under `/fl` → Help.

## What's next

See the [roadmap](https://github.com/ivellos/forever-ledger/blob/main/ROADMAP.md) for planned features. Ideas are welcome in [Issues](https://github.com/ivellos/forever-ledger/issues).

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
| `/fl watch` | Watch flips: keep scanning while the auction house is open, chime on a new vendor flip |
| `/fl deals` | Open the Deals tab (`/fl deals list` in chat, `/fl deals settings` for the options; they're also in the Settings tab) |
| `/fl customers` / `/fl work` | The Customers window: requests from chat, ads, and work done |
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

Open an [issue](https://github.com/ivellos/forever-ledger/issues/new/choose) and include the output of `/fl api` and any error text from BugSack.

## Project layout

| Path | What it is |
|---|---|
| `*.lua`, `ForeverLedger.toc` | The addon itself |
| `CHANGELOG.md` | What changed in each version |
| `docs/` | Guides for testing, developing and releasing |
| `tools/flip-calculator.html` | The web version of the flip calculator |
| `.github/` | Automatic checks, release builds and the bug report form |

## License

MIT. See [LICENSE](https://github.com/ivellos/forever-ledger/blob/main/LICENSE).

Classic recipe sources in `ClassicRecipes.lua` are generated by `tools/build-classic-data.ps1` from [wow-classic-items](https://github.com/nexus-devs/wow-classic-items) by nexus-devs and [pfQuest](https://github.com/shagu/pfQuest) by shagu (both MIT licence).
