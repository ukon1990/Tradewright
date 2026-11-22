# Tradewright

Tradewright is an auction, profession and inventory helper for WoW Forever and retail. It combines auction house prices with your profession recipes to show which crafts make a profit.

## Features

**Auction house**
- Full scan that stores prices, with a daily price history and a usual price per item.
- Prices on item tooltips; hold Shift for craft profit and more.
- Market tab to search the last scan and each item's price history from anywhere, not just at the auction house.
- Opportunities tab: flips, items listed under vendor price, and what to sell now.
- Shopping cart for the reagents your queued crafts need.
- Bulk posting, and undercut checks on your own auctions.

**Professions**
- Scans your recipes and reagents, and shows cost and profit per craft.
- Picks the cheapest way to get each material: buy, craft or vendor.
- Shows which reagents a vendor sells that you still need.
- Suggests how many to make, and tracks cooldown crafts.
- Craft queue, and a leveling route for raising a profession skill.
- Crafting orders (retail): queue patron orders, buy all materials from one shopping list, then craft them in order.
- Reagent quality (retail): the cheapest reagents that reach the rank you want.

**Inventory and gold**
- Bags and bank across your characters, with quantity history.
- Ledger and income view: where your gold comes from and what sells.
- Farm window that logs loot and values it at current prices.
- Mail tools: send materials to crafters, and crafts and surplus back to your seller.

**Bag window (optional)**
- Bags and bank grouped by item category, with your other characters as tabs.
- Select several items at once to move, bank or mail them.
- Item log of what entered and left your bags.
- Full bags: delete the cheapest stack, or swap it for loot that does not fit.
- Turn it off with `/ah bags` or in Settings.

Tradewright is split into several addons, so you can turn off the parts you don't use.

## Getting started in game

1. Enable the five core addons, and `Tradewright_Bags` if you want the bag window.
2. Type `/ah` or `/tradewright` to open the window.
3. Open the auction house and run a full scan to fill in prices.
4. Open a profession and press Scan to store your recipes.
5. Open the Crafts tab to see which crafts are profitable.

## Optional addons

Tradewright works on its own. With Questie installed, it can show where vendors you have not visited stand. With TomTom installed, it can use TomTom's arrow when the game's own waypoint is unavailable.

---

## For developers

The addons live under `src/`. `Tradewright` is the base every other addon needs; `Tradewright_AuctionData`, `Tradewright_Professions`, `Tradewright_Inventory` and `Tradewright_UI` make up the rest of the core, and `Tradewright_Bags` is optional.

- [Development](docs/development.md): setup, tests, lint, and copying the addons into the game.
- [Backlog and issues](docs/specifications/05-backlog.md)
- [Export package format](docs/export-format.md) and [profession data guide](docs/profession-data.md)
- [Research: gold making and market strategies](docs/research/gold-making-market-strategies.md)
- [AGENTS.md](AGENTS.md): rules for contributors and agents.

## Licence

Tradewright is released under the [MIT License](LICENSE). The Midnight profession specialization data is derived from CraftSim; see [THIRD-PARTY-NOTICES.md](src/Tradewright_Professions/THIRD-PARTY-NOTICES.md).
