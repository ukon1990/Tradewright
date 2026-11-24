# Tradewright

Tradewright is an addon for managing auctions, professions and inventory in WoW forever and retail. It collects auction prices, and allows you to use them with your professions to show the crafting cost and potential profit.

## Features

**Auction house**
- Lets you scan the whole auction house, and collects history, so that you easily can see the change over time.
- Lets you check and search through the prices on the AH anywhere, based on the last time you did a full AH scan.
- Lets you easily find potential flips, for items below vendor price etc.
- Shopping cart, for the reagents you need for the crafts you've got queued up.
- Uses the native UI for posting, with easy click to sell via the AH side-panel. You can also check if your auctions has been undercut.

**Professions**
- Lets you see potential profit and crafting cost for your recipes.
- Selects the cheapest option to get the reagent (AH, craft or vendor)
- Lets you navigate to the vendor that sells a given trade reagent like `Fine thread` etc.
- Suggests how many to make, and tracks cooldown crafts.
- Craft queue, and a helper leveling crafting professions.
- Crafting orders (retail): queue patron orders, buy all reagents from one cart, then craft them in order.
- Reagent quality (retail): the cheapest reagents that reach the rank you want.

**Inventory and gold**
- Bags and bank across your characters, with quantity history.
- Ledger and income view: where your gold comes from and what sells.
- Farm window that logs loot and values it at current prices.
- Mail tools: send reagents to crafters, and crafts and surplus back to your bank character.

**Bag window (optional)**
- Bags and bank grouped by item category, with your other characters as tabs.
- Select several items at once to move, sell or destroy them.
- Item log of what entered and left your bags.
- Full bags: suggests the cheapest stack to destroy, or to swap for loot that does not fit. Nothing is destroyed until you confirm.
- Turn it off with `/tw bags` or in Settings.

Tradewright is split into several addons, so you can turn off the parts you don't use.

## Getting started in game

1. Enable the five core addons, and `Tradewright_Bags` if you want the bag window.
2. Type `/tw` or `/tradewright` to open the window.
3. Open the auction house and run a full scan to fill in prices.
4. Open each of your professions once; Tradewright saves the recipes.
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
