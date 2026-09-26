# Forever Ledger

A World of Warcraft: Forever addon for crafters who like to make gold. It remembers every character's professions and recipes, tracks vendor and auction house prices, and (from version 0.2) finds profitable flips and shuffles across your characters.

> **Status:** early testing on the Forever beta. Expect bugs, and please report them.

## Features

- **Character profiles that build themselves.** Level, professions, skill and every known recipe with its exact materials, saved as you play.
- **Vendor prices.** What vendors pay you, read from the game, and what they charge you, captured whenever you open a vendor.
- **Auction house scanning.** Scan the materials your characters use, or every listing at once.
- **Works with Auctionator, TSM and Auctioneer.** Uses their prices when your own scan is out of date.
- **Tooltips.** See an item's price, what a vendor charges for it, and which of your characters use it.
- **Export and import.** Move data between accounts, for example to an auction house character on a second account.

## Install

1. Download the latest `ForeverLedger-x.y.z.zip` from [Releases](../../releases).
2. Unzip it into your Forever client's `Interface\AddOns` folder, so you end up with `Interface\AddOns\ForeverLedger\ForeverLedger.toc`.
3. Start the game and make sure Forever Ledger is ticked in the AddOns list.

## Commands

| Command | What it does |
|---|---|
| `/fl` | Open or close the ledger window |
| `/fl scan` | Scan prices for every material your characters use (auction house must be open) |
| `/fl scan full` | Scan every listing (Blizzard allows this about every 15 minutes) |
| `/fl stop` | Stop a scan |
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
