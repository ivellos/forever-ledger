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
| `Locales/` | One file per language. Russian (`ruRU.lua`) is the reference for counted nouns and other grammar English doesn't need |
| `API.lua` | `ForeverLedgerAPI`: prices for other addons |

## Prices for other addons

`ForeverLedgerAPI` (in `API.lua`) lets another addon read Forever Ledger's own auction house scans for the current market. It never hands out prices copied from other addons. Every function returns nothing for an item never scanned, and a time is in seconds as `time()` gives it.

| Function | Returns |
|---|---|
| `GetPrice(itemID)` | typical price (never under the cheapest), cheapest, how many are listed, when scanned; none listed gives `nil, nil, 0, when` |
| `GetListings(itemID)` | the last scan's price levels `{ { price, count }, ... }`, cheapest first, how many are listed, when scanned |
| `GetCost(itemID, quantity)` | what buying that many costs up the levels, how many it could price (no guess past the saved levels), when scanned |
| `GetUsualPrice(itemID, window)` | the usual price over `"week"` (default), `"month"`, `"3months"`, `"6months"`, `"year"` or `"all"`, and how many days it used |
| `GetLastFullScan()` | when the last full scan finished |

`ForeverLedgerAPI.version` is 1; a change that breaks callers raises it.

## Text in other languages

Player text is written in English in the code and shown through the shared helpers (`T:Font`, `T:Button`, `ns:TooltipAddLine`, `ns:Print`), which translate it on clients with a language file in `Locales\`. Read game text by ID (item, spell, quest, map, skill line, channel), never by its English name; where the game has no ID, keep the English check as a fallback and let a language file add its own words. How to add or update a language: [TRANSLATING.md](TRANSLATING.md). `tests/test_localization.lua` loads each language file and checks its placeholders; `lua5.1 tools/locale-report.lua <code>` lists what a language still misses.
