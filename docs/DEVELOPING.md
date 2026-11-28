# Working on the addon

## Load the addon straight from this folder

Instead of copying files into the game after every change, link your repository folder into the game's AddOns folder once. Edits then show up after a `/reload`.

On Windows, open Command Prompt **as administrator** and run (change both paths to match your computer):

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ForeverLedger" "C:\Users\YOU\Documents\GitHub\forever-ledger"
```

The first path is where the game looks for addons. The second is where GitHub Desktop keeps this repository. The window title will show version `dev` for these local copies.

## Day-to-day changes

1. Change the files (or replace them with new versions from Claude).
2. Test in game with `/reload`.
3. Add a line under `## [Unreleased]` in `CHANGELOG.md` describing the change.
4. In GitHub Desktop, write a short summary like "Fix recipe capture for Enchanting" and click **Commit to main**, then **Push origin**.
5. Check the **Actions** tab on GitHub. A green tick means the code check passed.

## Files

| File | Job |
|---|---|
| `Core.lua` | Saved data, events, export/import, slash commands |
| `Prices.lua` | Vendor prices, auction house scanning, other auction addons |
| `Professions.lua` | Character profiles and recipe capture |
| `Tooltip.lua` | Extra lines on item tooltips |
| `UI.lua` | The ledger window and text windows |
| `API.lua` | `ForeverLedgerAPI`: prices for other addons |
| `CraftProfitSource.lua` | Forever Ledger in CraftProfit's list of price sources |

## Prices for other addons

`ForeverLedgerAPI` (in `API.lua`) lets another addon read Forever Ledger's own auction house scans for the current market. It never hands out prices copied from other addons. Every function returns nothing for an item never scanned, and a time is in seconds as `time()` gives it.

| Function | Returns |
|---|---|
| `GetPrice(itemID)` | typical price (never under the cheapest), cheapest, how many are listed, when scanned; none listed gives `nil, nil, 0, when` |
| `GetListings(itemID)` | the last scan's price levels `{ { price, count }, ... }`, cheapest first, how many are listed, when scanned |
| `GetCost(itemID, quantity)` | what buying that many costs up the levels, how many it could price (no guess past the saved levels), when scanned |
| `GetUsualPrice(itemID, window)` | the usual price over `"week"` (default), `"month"`, `"3months"`, `"6months"`, `"year"` or `"all"`, and how many days it used |
| `GetLastFullScan()` | when the last full scan finished |
| `GetVendorPrice(itemID)` | what a vendor pays for one, and what one costs from a vendor (`nil` where it isn't sold there or hasn't been seen at one) |
| `GetSoldPerDay(itemID)` | about how many sell a day, how many are listed, and the hours of full scans it's based on; nothing until there are enough scans |
| `GetVersionPrice(itemID, version)` or `GetVersionPrice(itemLink)` | one version of random-stat gear (the version is the bonus ID in its link) from the last full scan: cheapest, how many of it are listed, when scanned; none listed gives `nil, 0, when` |
| `RegisterForUpdate(name, fn)` | calls `fn()` after Forever Ledger saves new prices: once saving has stopped for 3 seconds, and at most every 30 seconds. `name` is your addon's name; registering it again replaces the function. `UnregisterForUpdate(name)` stops it |

`ForeverLedgerAPI.version` is 1; a change that breaks callers raises it. Functions added later keep version 1, so check that one exists before calling it (`GetVendorPrice`, `GetSoldPerDay`, `GetVersionPrice` and `RegisterForUpdate` came in after 0.30.0).

CraftProfit: Forever Ledger adds itself to CraftProfit's price sources (`CraftProfitSource.lua`, built on these functions), players can turn it off in Settings, Global settings, Prices ("Prices for CraftProfit").

## Text in other languages

Player text is written in English in the code and shown through the shared helpers (`T:Font`, `T:Button`, `ns:TooltipAddLine`, `ns:Print`), which translate it on clients with a language file in `Locales\`. Read game text by ID (item, spell, quest, map, skill line, channel), never by its English name; where the game has no ID, keep the English check as a fallback and let a language file add its own words. How to add or update a language: [TRANSLATING.md](TRANSLATING.md).
