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
