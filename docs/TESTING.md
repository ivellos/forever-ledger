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
10. Hover Brown Linen Pants. It should say "Disenchants to about 1.18 Strange Dust, 0.31 Lesser Magic Essence", and "Worth to you" should include "Disenchant". Hover Bolt of Linen Cloth: it should list "Craft Brown Linen Pants, disenchant".
