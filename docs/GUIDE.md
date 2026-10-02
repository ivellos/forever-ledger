# Forever Ledger guide

Everything the addon does, at a high level. The same text is in the game under **/fl → Help**. For what changed in each version see the [changelog](../CHANGELOG.md); for what's coming, the [roadmap](../ROADMAP.md).

> Pictures are being added. Where a picture is missing, the text still describes the feature.

## Getting started

1. Type `/fl` (or click the minimap button) to open the main window.
2. Open each profession window once on every character, so the addon learns your recipes.
3. At the auction house, click **Full scan** (allowed about every 15 minutes) to price everything.
4. Hover any item: the tooltip shows what it's worth to you.

![The Forever Ledger window, Dashboard tab](images/dashboard.png)

## Scanning the auction house

- **Full scan** reads every listing in a few seconds. **Scan materials** checks just what your recipes use.
- **Watch flips** keeps scanning while the auction house stays open and chimes when a new vendor flip turns up. An eye on the button shows it's running.
- If Auctionator or another addon runs a full scan, Forever Ledger reads it too.
- **With Auctionator or TSM installed**, Forever Ledger switches off the features they already cover, so you don't see things twice: for now, the auction and vendor price lines in tooltips (Worth to you, Buy at or below and the rest stay). A one-time message says what was turned off; **Keep them on** undoes it, and Settings can change it any time.
- Neutral auction houses (Booty Bay, Gadgetzan, Everlook) keep their own prices.

![Watch flips, Disenchant finder, Full scan and Scan materials under the auction house](images/auction-house.png)

## Tooltips

- **Worth to you**: the best of selling on the auction house, selling to a vendor, disenchanting, or crafting it into something, with the best few ways listed.
- **Buy at or below**: the most worth paying, after your safety margin. Green when it's already cheaper.
- Also: disenchant results, which of your recipes use it, and the cheapest crate fill.
- Gear with random stats ("of the Eagle"): the price of that exact version, since versions of one item can sell for very different amounts.
- **Settings → Tooltip size**: "One line, Shift for more" keeps tooltips short. Each part can be turned off.

![Tooltip for Strange Dust](images/tooltip.png)

## Shuffles and vendor flips

- **Shuffles**: buy materials, craft, disenchant or convert, and sell, ranked by profit per hour. Click a row for every step; **Work it** walks you through them with one-click buttons.
- **Vendor flips**: things on the auction house for less than a vendor pays. After a scan finds some, the tab opens by itself; click a flip to search for it. Settings, **Vendor flips** sets the least profit worth your time: a share of the vendor price (0% counts anything below it) and an amount each (say 10c). On the auction house, listings worth buying get a green bar and a **BUY** badge, and the line above the list says how many are still there (red "None left" once they've been bought).

![Vendor flips tab](images/vendor-flips.png)

## Buy queue and shopping lists

- **Buy queue**: click **Buy queue** under the auction house. A panel beside it lines up everything worth buying right now: vendor flips, greens worth disenchanting, items from your shopping lists, and (if you tick it) good deals. The addon looks up the next one by itself; **each tick of the mouse wheel down, or a click on Buy, buys it**. Stacks of materials take a second tick: the first asks the auction house for the final price, the second confirms it. `/fl queue` opens it.
- **Safe by design**: it never pays more than the limit shown (checked again against the final price) or more than you have, and every purchase is your own tick or click, as Blizzard requires. **Scroll anywhere to buy** starts off, so only the Buy button (or scrolling over it) buys; tick it to buy with the mouse wheel anywhere on screen. It turns itself off when the queue runs out, so a stray scroll later can't buy something new. Click a row to buy that one next; right-click to skip it. Gear sold in stacks is left for you to buy on the page.
- **Shopping lists**: named lists of items with the most you'd pay each and how many you want to have, for example raid consumables or twink gear to watch for. With the list open, shift-click an item from your bags or a chat link to add it, drag it in, or start typing its name and pick from the suggestions (Enter takes the top one). Suggestions include items the game hasn't loaded yet, from original Classic. Hover **Have** to see how many are in your bags, bank and on your other characters. `/fl lists` opens your lists anywhere (a window you can move), so you can plan before you go to the auction house.
- **Share and Import**: **Share** copies a list as plain text, ready to paste in the Discord (put it between ``` marks) or send to a friend. **Import** reads shared lists back, and also takes a plain list of item names, item numbers or Wowhead links, one per line. Imports never change your own lists: one with the same name is added as a new list. A shared list looks like this, and you can write one by hand:

  ```
  Forever Ledger shopping list: Raid prep
  any price
  13510 Flask of the Titans | want 2
  2772 Iron Ore | max 1g 50s | want 20
  13511 Flask of Distilled Wisdom | craft | want 3
  ```
- **Prices**: type them any way you like: `2g 50s`, `1.5g`, `25s`, `75c`, or a plain number for gold. A tip shows what it will be saved as, and Enter tidies it up. Type `any` to take any price for one item, or tick **Any price (just what I need)** for the whole list, for raid prep where you just have to eat the cost: the buy queue then buys the cheapest ones until you have the number you want (1 if you didn't set one), and never more than 3 times the usual price, so a joke listing can't slip in.
- **Buy or craft**: each item is set to **Buy** or **Craft**. Planning to make 10 Wizard Oils instead of buying them? Set it to Craft and the list shows the materials for the number you want (less what you already have), how many you need and have, and the most to pay for each: your usual price from scans unless you type your own. Materials a vendor sells are marked **vendor**.
  If none of your characters knows the recipe, the original Classic recipe is used (hover the item to see it); Forever may have changed some.
- **Search this list** checks every item and material in one click; those at or under your price turn green and join the buy queue. Items not cheap enough yet wait at the bottom of the buy queue, greyed, so you can see they're being watched.
- The panel's third tab is the **Disenchant finder** (below).

## Deals

- **Deals tab**: listings well below the price an item is usually *cheapest* at, to buy and resell. Each row shows the price now, the usual low (the middle of each day's cheapest price over the period set in Settings), how far below it is, how many are worth buying, the profit after the auction house cut (each and for all of them), and how sure the deal is: **Good**, **Fair** or **Thin**. Comparing with the usual cheapest price, not the typical one, means a deal is a real bargain, not just today's normal low.
- **Hover a deal** to see why it's a deal: the usual cheapest and typical prices, how many days they're based on, the typical range most days, how many are usually listed, and the next listing above the cheap ones. Profit assumes you resell at the usual cheapest price, or just under the next listing if that's lower, and only listings that still make the minimum profit count. **Click** a deal to search for it on the auction house.
- **How sure**: Good means a week or more of steady prices. Fair means less data, or a warning: usually only one listed (it may sell slowly, or that "usual price" was one hopeful seller), nothing else listed to compare with, or gear whose stat versions sell at different prices. Thin (a few days, or prices that jump around) is hidden unless you tick **Show thin data too**.
- Deals need at least 4 days of scans to know an item's usual price, or TSM installed. Settings, Deal alerts sets how far below, over what period, and the least profit each. After a scan, chat says how many new deals there are instead of listing them.
- The auction house only shows what's listed, not what sold. Buy what you'd be happy to hold for a while.

## Disenchanting

- **Disenchant finder** (beside the auction house: Buy queue button, Disenchant finder tab): green armor and weapons by item level, with what each is worth to disenchant. Hover a band for the odds of each material.
- The **Disenchant** button in Work it disenchants the shuffle's items one click at a time. `/fl de` shows your own results.

![Disenchant finder beside the auction house](images/disenchant-finder.png)

## Recipes and trainers

- **Recipes tab**: every recipe of your professions, who knows it, where to get it, the skill needed, and profit per craft. Types: Flip or shuffle, Crafts that sell, Enchant service, Not for sale, Not profitable. Right-click a recipe to set your own type.
- **Where from**: what you've seen in game first, otherwise original Classic data marked "(Classic)", or the auction house when the recipe item is listed there (handy for recipes new in Forever). **Pin** puts a map pin on the vendor, trainer or mob.
- **Trainers view**: trainers you've visited, Classic ones, and the spots city guards mark when you ask them for a profession trainer (marked "guard").

![Recipes tab, Cooking recipes not known yet](images/recipes.png)

![Trainers view with visited, guard-marked and Classic trainers](images/trainers.png)

## Waylaid Crates

- **Crates tab**: the cheapest way to fill each crate at today's prices, with the crate's own price and gold per Merchant's Favor. Click a crate for every bundle and what you already have in bags, bank and alts.
- **Pays back**: turning in a filled crate pays money as well as Favor (Apprentice crates about 2s 50c, green ones 5s). The tab takes that off the cost; when it pays back more than the crate and its fill cost, the net cost shows as a green profit and the crate is worth doing for gold alone. Payouts marked * are estimates until you turn one in, then learned like the Favor.
- Crates are sold at the turn-in posts too (Three Corners in Redridge for Alliance, near the Crossroads for Horde), and Merchant's Favor buys recipes, pets, tabards, titles and even a mount.

![Crates tab](images/crates.png)

## Customers and work

- **Customers window** (`/fl customers`): opens when someone in chat asks for what your character can do, with **Whisper** and **Invite** buttons.
- **Class services**: the finder also spots requests for Mage food, water and portals (portals from level 40), Warlock summons (from level 20) and Rogue lockpicking (from level 16), when you're on that class. **Settings, Customers** turns each service (and crafting requests) on or off, along with its ad button; the Customer finder switch turns the whole thing off.
- **Ad buttons** post your crafting (with profession links) to Trade, plus a button per class service: food and water (with links), portals (with the cities you know), summons, or lockpicking. Right-click a button to change its text.
- **Work done** (`/fl work`): enchants and paid trades, with today's and this week's earnings.

![Customers window, Work done view](images/work-done.png)

## Your gold

- **Dashboard**: gold over time, sales, expenses and profit, and your sessions.
- **Ledger**: every sale and purchase, resale profit, and other money like repairs and flights.



## Sharing between accounts

- **Live sync** (`/fl pair First Last`) sends prices and recipes between your two accounts while both are online. Export and import work too.

## Help and community

- **Discord:** [discord.gg/WKsCtvupeC](https://discord.gg/WKsCtvupeC) for updates, questions and WoW Forever news.
- **Found a bug?** Type **/bug** on the Discord and fill in the short form (version, what happened, how to make it happen). Add the `/fl api` output or the BugSack error if you can. It goes to our tracker and you'll get updates in your post.
- **Have an idea?** Type **/feature** on the Discord.

## Your data

- Everything Forever Ledger records stays in its saved file on your own PC. **Nothing is sent to the author or anyone else.**
- **It keeps:** auction house and vendor prices and their history; recipe, vendor and trainer locations you've seen; your characters' professions and recipes, gold over time, sales, purchases and vendor trades; bag and bank contents (this account only); requests the customer finder spotted in chat; and your work-done log.
- **It sends** only when you choose to: live sync whispers to **your own** paired character (off until you use `/fl pair`), and ad buttons post in Trade when you click them. Export copies text for you to paste; it goes nowhere by itself.
- A future option to share where vendors and trainers are with other players (on the roadmap) would share world facts only, never names, gold or bags, would ask first, and could be turned off.

## Commands

| Command | What it does |
|---|---|
| `/fl` | Open or close the window |
| `/fl scan` | Full scan if allowed, otherwise your materials |
| `/fl watch` | Start or stop the flip watch |
| `/fl queue`, `/fl lists` | The buy queue or shopping lists beside the auction house |
| `/fl customers`, `/fl work` | The Customers window, or its Work done view |
| `/fl de` | Your disenchant results |
| `/fl deals` | Open the Deals tab (`/fl deals list` lists them in chat) |
| `/fl book` | Recipe data gathered so far |
| `/fl sync` | Sync status and help |
| `/fl perf` | What takes the addon's time |
| `/fl probe` | Checks what the game supports (for testing) |
