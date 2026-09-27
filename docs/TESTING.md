# Beta test checklist

Run through this after installing a new version. Send the results, plus any errors from BugSack.

1. Type `/fl api` and save the output.
2. Type `/fl`. Your character should be listed with its professions. The window title shows the version.
3. Open your Tailoring window, then your Enchanting window. Chat should say "Saved N ... recipes".
4. Visit a Trade Supplies vendor. Hover Coarse Thread or Simple Wood: the tooltip should show "Vendor sells it for".
5. Open the auction house and click "Ledger scan". When it finishes, hover Strange Dust and compare the ledger price with the auction house.
6. Try `/fl scan full` once. Note whether it finishes and how long it takes.
7. Hover Linen Cloth. It should say which of your characters use it.
8. Type `/fl csv` and check the price list looks sensible.
9. Hover Lesser Magic Essence. "Worth to you" should list the auction house, the vendor and "Craft Greater Magic Wand, sell to vendor" at about 7s 49c.
10. Hover Brown Linen Pants. It should say "Disenchants to about 1.18 Strange Dust, 0.31 Lesser Magic Essence", and "Worth to you" should include "Disenchant". Crafted wands should have no disenchant line.
11. Hover Greater Magic Essence. "Worth to you" should include "Split into Lesser Magic Essence, 1 more step" at 3 times the Lesser essence's value.
12. Hover Linen Cloth and Wool Cloth. "Worth to you" should include "Craft Bolt of …, N more steps", following the chain to a vendor or auction house sale.
13. Type `/fl shuffles`. It should show two groups, "Sells to a vendor" and "Sells on the auction house", with each recipe listed once and item names (not "item 1234").
14. Hover Strange Dust. "Buy at or below" should be 90% of its "Worth to you", and green if the ledger price is lower.
