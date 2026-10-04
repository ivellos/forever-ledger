# Bug review: Auctions, Shopping lists, Buy queue, Ledger, Sessions, Customers

Reviewed on 2026-10-04 against `main` at commit 876681e. Files: `Auctions.lua`, `ShoppingLists.lua`,
`BuyQueue.lua`, `Ledger.lua`, `Sessions.lua`, `Customers.lua`. Related code in `Core.lua`,
`Prices.lua`, `History.lua` and `Theme.lua` was read where these files depend on it.

This was a read-through only. Nothing was run in game. Findings are ranked most serious first.
"Unconfirmed" means the code reads as described but the game behaviour it depends on isn't
certain; the reason is given.

No Lua 5.1 problems were found: no `goto`, `//`, `table.unpack`, bit operators or `utf8`,
and every `string.format` checked has matching arguments.

## Summary

| # | Severity | File | Problem |
|---|----------|------|---------|
| 1 | High | ShoppingLists.lua:553 | "Any price" cap is raised to the cheapest listing, so a joke listing defeats it |
| 2 | High | ShoppingLists.lua:552, BuyQueue.lua:109 | "Any price" with no saved price has no cap at all, and the item is looked up by itself |
| 3 | High | Auctions.lua:535 | Cancel next undercut cancels a different auction from the one the "Next:" line names |
| 4 | Medium | BuyQueue.lua:726 | Spend at most can be exceeded: purchases whose reply arrives late are never counted |
| 5 | Medium | ShoppingLists.lua:638 | Lua error (nil `matDone`) when opening the list menu for a Craft item |
| 6 | Medium | Sessions.lua:55 | A session carried over a logout counts the time offline, so gold an hour is wrong |
| 7 | Medium (unconfirmed) | ShoppingLists.lua:70 | One-time list migration reads bag counts at ADDON_LOADED, maybe before bags load |
| 8 | Medium (unconfirmed) | Auctions.lua:85 | Per item or per stack price guessed; a wrong guess marks a fair auction undercut |
| 9 | Low | BuyQueue.lua:1875 | Shopping lists view redoes all its work every second |
| 10 | Low | Ledger.lua:348 | Every key typed in Search rebuilds every record, with an item lookup per sale |
| 11 | Low | Auctions.lua:294 | A cancel the server ignores stays "cancelling..." until the auction house closes |
| 12 | Low | Customers.lua:536 | Long request headings can run under the Whisper, Invite and x buttons |
| 13 | Low | Sessions.lua:245 | A session left running on another character blocks starting one on this character |

---

## 1. High: "Any price" cap is raised to the cheapest listing

**Where:** `ShoppingLists.lua:546-554` (`ns:AnyPriceLimit`), line 553.

**What's wrong:** The limit is `math.max(base * 3, rec.m)`, where `rec.m` is the cheapest
listing at the last scan. The tooltip (`BuyQueue.lua:1680`) and the comment above the function
promise "never more than 3 times the usual price, so a joke listing at 999g can't be bought".
But when a joke listing is the cheapest one up, `rec.m` is that joke price, and the cap rises
to meet it.

**Scenario:** A raid list has "Any price" ticked and wants 1 Flask of the Titans. Its usual
price from the month's scans is 20g, so the cap should be 60g. The last scan saw only one
flask, listed at 500g. The limit becomes `max(60g, 500g) = 500g`. The queue picks the flask by
itself, and the next scroll tick buys it for 500g.

**Suggested fix:** Drop `rec.m` from the `math.max`, so the limit is `base * ANY_CAP`. If a
higher limit is wanted when prices have really gone up, use a recent typical price (`rec.a`),
never the single cheapest listing.

## 2. High: "Any price" with no saved price has no cap

**Where:** `ShoppingLists.lua:552` (`return math.huge`), together with `BuyQueue.lua:109-111`
and `Prices.lua:361`.

**What's wrong:** With no month history and no saved price on this market, `AnyPriceLimit`
returns `math.huge`. `ns:CheapListings` then returns `nil` (not `0`) for an item with no
record, so `buildQueue` doesn't mark the entry as waiting. `prepare()` picks it by itself,
because `cantAfford` finds no price either. `planItem` and `planCommodity` accept every
listing, and the commodity check `total <= limit * qty` (`BuyQueue.lua:677`) is always true.
Only your gold and Spend at most limit what gets spent.

**Scenario:** A player takes their raid list to a neutral auction house, which has its own
market key (`Core.lua:221`) and so no saved prices there. Every "Any price" item on the list
has no cap. The queue looks each one up by itself, and with Scroll to buy on, each tick buys
the cheapest listing whatever it costs. The same happens for an item that has never been
scanned.

**Suggested fix:** When there's no price to base a cap on, don't buy: return `nil`, or mark
the entry as waiting until a search has priced it. At the least, require a click on Buy for
these items and never let the wheel buy them.

## 3. High: Cancel next undercut cancels a different auction from the one named

**Where:** `Auctions.lua:533-546` (the button's click), compared with `Auctions.lua:453` and
`Auctions.lua:470-473` (the "Next:" line).

**What's wrong:** The "Next: X, yours ..., cheapest ..." line is built from
`undercutList(order)`, which follows the sorted order on screen (undercut first, then by
item name). The button's click uses `undercutList(m.list)`, which follows the game's
owned-auctions order (sorted by price, `Auctions.lua:44`) with sold auctions added at the end.
With two or more undercut auctions, the two lists usually start with different auctions.

**Scenario:** Two auctions are undercut: Wizard Oil at 20s and Iron Ore at 30s. On screen
they're sorted by name, so the line says "Next: Iron Ore". The game's list is sorted by price,
so Wizard Oil comes first there, and the click cancels Wizard Oil. The player loses a deposit
on an auction they didn't choose, and may have wanted to keep it.

**Suggested fix:** Build the click's list in the same order as the screen: sort it the way
`refresh()` does, or keep the `todo` list `refresh()` computed (for example on `frame.todo`)
and cancel `frame.todo[1]`.

## 4. Medium: Spend at most can be exceeded

**Where:** `BuyQueue.lua:217-223` (`bought`), `710-714` (`itemBought`), `694-702`
(`COMMODITY_PURCHASE_SUCCEEDED`), `726-731` (`failed`), and the timeouts at `569`, `574` and
`582`.

**What's wrong:** `Q.spent` only goes up in `bought()`, and that only runs when the success
reply arrives while `Q.state == "buying"`. The state leaves "buying" early in two ways:
- **Any error message:** `UI_ERROR_MESSAGE` calls `failed()` for any red error, not just an
  auction house one (an ability pressed out of range, "Item is not ready yet").
- **A slow reply:** the timeouts (6 seconds for an item, 10 for a stack) give up. Gear also
  relies on `AUCTION_HOUSE_PURCHASE_COMPLETED` or the "You won an auction" chat line arriving
  in time.

When the reply for a purchase that did go through arrives later, it's ignored. The gold was
spent, but Spend at most never counts it.

**Scenario:** Spend at most is 50g. During a commodity confirm, the player presses a keybind
that shows "Not enough energy". `failed()` runs, the queue searches again and plans another
purchase. The first purchase then succeeds with nothing counting it, so the queue can spend up
to another 50g on top.

**Suggested fix:**
- Only treat auction house errors as a failed purchase (compare against the `ERR_AUCTION_*`
  and `ERR_ITEM_*` messages, or use `AUCTION_HOUSE_SHOW_ERROR` alone).
- Count spending from the money change itself: History.lua already sees every `ahBuy` gold
  drop (`History.lua:262-276`), so add it to `Q.spent` there while the auction house is open.

## 5. Medium: Lua error in the list menu for a Craft item (nil `matDone`)

**Where:** `ShoppingLists.lua:631-641` (`ns:ItemDone`), lines 637-640; the menu calls it at
`BuyQueue.lua:1588`.

**What's wrong:** For a Craft item on a list you buy from, `ItemDone` sets
`all = recipe and list.matDone and true`. It then loops over the recipe's materials and
indexes `list.matDone[r[1]]` without checking that `list.matDone` exists. `list.matDone` is
only created inside `ns:ListMaterials`, and only for a material that is actually needed.

**Scenario:** List A is ticked "Buy from this list" and has one Craft item whose recipe isn't
known yet. `ListMaterials` finds no recipe, so `matDone` is never created. Later the recipe
becomes known: a profession window is opened on the crafter, or the recipe book records it.
While another list is on screen, the player opens the list dropdown. `fillMenu` calls
`ItemDone` for list A and gets "attempt to index field 'matDone' (a nil value)". The menu
doesn't open, and the error repeats until something runs `ListMaterials` on list A.

**Suggested fix:** Guard the lookup: `if not (list.matDone and list.matDone[r[1]]) then all = false end`.

## 6. Medium: A carried-over session counts the time offline

**Where:** `Sessions.lua:55` (`secs = time() - s.t`) and `Sessions.lua:290-294`.

**What's wrong:** A session left running at logout "carries on at login" by design, but its
length is measured from the clock time it started. The hours logged out count as session
time, so gold an hour, and the length shown in chat and on the Dashboard, are wrong.

**Scenario:** A player farms for 1 hour and makes 50g, then logs out with the session still
running. They log back in 10 hours later and stop it. The summary says 11 hours and about 4g
50s an hour, instead of 50g an hour.

**Suggested fix:** Keep the session's active seconds on the session itself: at logout
(`PLAYER_LOGOUT`) add the seconds since it last resumed, and at login set a new resume time.
Work out the rate from the active seconds. Alternatively, ask at login whether to carry on or
stop it.

## 7. Medium (unconfirmed): One-time list migration may read empty bags

**Where:** `ShoppingLists.lua:56-76`, line 70.

**What's wrong:** The comment says the migration "needs bag counts, so it can't run with the
other saved-data changes in Core.lua". But `ns:OnReady` callbacks run inside `ADDON_LOADED`
(`Core.lua:356-394`), which is the same point Core.lua's changes run. If `GetItemCount`
reports 0 then, `e.bought = math.min(ns:HaveCount(e.id), e.qty)` sets 0 for every item. "Keep
this many" lists would then buy their full Want again, though what you had was supposed to
count as bought.

**Why unconfirmed:** Whether bag contents are known at `ADDON_LOADED` during login isn't
certain in this client. This only affects players upgrading from a version before schema 4.

**Suggested fix:** Run the migration on `PLAYER_LOGIN`, or on the first `BAG_UPDATE_DELAYED`
after login, with `d.oneKind` still guarding it.

## 8. Medium (unconfirmed): Per item or per stack price is guessed

**Where:** `Auctions.lua:85-103` (`eachPrice`) and `Auctions.lua:152-156` (`undercutBy`).

**What's wrong:** For a stack, whether `buyoutAmount` is per item or for the whole stack is
guessed by which is closer to the saved market price. If that saved price is stale or missing,
the guess can be wrong. A stack of 20 priced at 1s each then reads as 20s each, shows as
undercut, and goes into Cancel next undercut.

**Scenario:** A stack of 20 Linen Cloth is listed at 1s each, but the saved market price is
20s, left over from an old joke-listing scan. The 20s stack total sits closer to 20s than the
1s per item does, so the guess takes 20s as each. The auction shows as undercut, and Cancel
next undercut can cancel it, losing the deposit.

**Why unconfirmed:** The comment says the API's meaning isn't settled. In the retail API,
`OwnedAuctionInfo.buyoutAmount` is per unit for commodities, which would make the guess
unnecessary.

**Suggested fix:**
- Settle it in the beta with the `/fl debug` line already written. If it's per unit, use it
  directly.
- Until then, leave stacks whose guess was close to a coin flip out of Cancel next undercut.

## 9. Low: The Shopping lists view redoes all its work every second

**Where:** `BuyQueue.lua:1873-1878` (an `OnUpdate` that calls `refreshLists()` every second),
`BuyQueue.lua:2218-2502`.

**What's wrong:** Each redraw runs:
- `ns:ListMaterials` and `estimateText`, which calls `ns:CostToBuy` for every item;
- `ns:OwnedCount`, which goes through every saved character, for every row;
- `ns:RecipeFor` for every item, which rebuilds its index from every character's recipes at
  most every 30 seconds.

This repeats while the tab is open, even when nothing has changed.

**Scenario:** A 40-item raid list with several Craft items is left open beside the auction
house. Each second does all of the above for every row. On a slow machine, `/fl perf` would
show "Shopping lists view" running constantly.

**Suggested fix:** Redraw on events (bag changes, prices saved, Search all progress, list
edits) instead of on a timer, or redraw every 5 seconds and only while the auction house is
open.

## 10. Low: Every key typed in the Ledger search rebuilds every record

**Where:** `Ledger.lua:348` (`OnTextChanged` calls `RefreshLedger`), `Ledger.lua:141-240`
(`records`), and `Ledger.lua:149` (`iconOf(e.n)`).

**What's wrong:** Every key press rebuilds every sale, purchase, vendor trade and monthly
total before filtering. That includes a `pcall(GetItemInfo, name)` per auction sale, looked up
by name, and a sort whose comparison lowercases strings each time. `MAX_ROWS` only limits what
is drawn, not what is built.

**Scenario:** With the Year or All range and a few thousand logged trades, typing "flask"
does the whole rebuild five times. That's a short hitch per key.

**Suggested fix:** Build the records once per filter change (tab, range, character), filter
those for the search text, and wait about 0.2 seconds after the last key before redrawing.

## 11. Low: An ignored cancel stays "cancelling..."

**Where:** `Auctions.lua:292-297` (`cancelOne`) and `Auctions.lua:482-486`.

**What's wrong:** `pending[e.a]` is only cleared when the auction leaves the owned list, or
when the auction house closes. If the server doesn't cancel it and only shows an error (the
`pcall` doesn't fail), the row says "cancelling..." and has no Cancel button. Cancel next
undercut also skips it until the auction house is closed and opened again.

**Scenario:** A cancel is refused by the server. The auction stays up and undercut, but can't
be cancelled from the tab until the player leaves the auction house.

**Suggested fix:** Clear `pending` for that auction after a few seconds without a change, or
on `OWNED_AUCTIONS_UPDATED` if it's still listed.

## 12. Low: Long request headings run under the buttons

**Where:** `Customers.lua:536-538` and `570` (Requests rows); `Customers.lua:469-474`
(Work done rows).

**What's wrong:** `r.head` is anchored only on its left and has no width or right edge. The
Whisper, Invite and x buttons take about the last 150 pixels of each row, so a long heading
draws underneath them. The same happens with `r.money` on Work done rows.

**Scenario:** A heading like "Firstname Lastname  Tailoring: Robe of the Archmage  Trade, 12m"
runs under the Whisper button in the 620-pixel window.

**Suggested fix:** Give `r.head` a right edge that stops before `r.whisper` and set
`SetWordWrap(false)`, as `r.msg` already does.

## 13. Low: A session on another character blocks starting one

**Where:** `Sessions.lua:245` and `Sessions.lua:290-294`.

**What's wrong:** `liveSession` is stored once for the whole account. If a session is left
running on character A, logging into character B hides the tracker, and "Start" on B says "A
session is already running". The message doesn't say it belongs to A. Stopping it from B
counts all the time since it started on A.

**Scenario:** A player forgets a session on their main and logs into an alt to farm. Starting
a session there fails with a message that doesn't explain why.

**Suggested fix:** Name the character in the message ("A session is running on A: /fl session
stop ends it"). Optionally, offer to stop it and start a new one on this character.
