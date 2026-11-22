# Tradewright

Tradewright is an auction, profession and inventory helper for World of Warcraft: **WoW Forever** (`Interface 16001`) and retail. It combines auction house prices with your profession recipes to show which crafts make a profit.

## Features

**Auction house**
- Full scan that stores prices, with a daily price history and a usual price per item.
- Market tab to search and sort the last scan, with a price chart per item.
- Opportunities tab: flips, items listed under vendor price, price gaps and what to sell now.
- Shopping cart for the reagents your queued crafts need.

**Professions**
- Scans your recipes and reagents, and shows cost and profit per craft.
- Picks the cheapest way to get each material: buy, craft or vendor.
- Suggests how many to make, and tracks cooldown crafts.
- Craft queue, and a leveling route for raising a profession skill.

**Inventory and gold**
- Bags and bank across your characters, with quantity history.
- Ledger and income view: where your gold comes from and what sells.
- Farm window that logs loot and values it at current prices.
- Mail tools: send materials to crafters, and crafts and surplus back to your seller.

**Bag window (optional)**
- Bags and bank grouped by item category, with your other characters as tabs.
- Select several items at once to move, bank or mail them.
- Item log of what entered and left your bags.

Good to know:

- Crafting orders, concentration and commodity auto-buy are retail only.
- Tradewright uses only public game functions and does not automate protected actions.
- The [backlog](docs/specifications/05-backlog.md) shows what is done, what is still open and what is planned.

## Modules

The pack is split into addons under `src/`, so you can enable only the parts you want.

| Addon | What it does |
| --- | --- |
| `Tradewright` | The base that every other module needs. Holds settings and saved data. |
| `Tradewright_AuctionData` | Scans the auction house and remembers the prices. |
| `Tradewright_Professions` | Scans your recipes and reagents, and works out craft cost and profit. |
| `Tradewright_Inventory` | Keeps track of your bags and bank, and keeps a ledger. |
| `Tradewright_UI` | The main window: dashboard, craft panel and mail tools. |
| `Tradewright_Bags` (optional) | A bag and bank window grouped by item category, with your other characters as tabs. Turn it off in Settings → Inventory & mail, with `/ah bags`, or by disabling the addon. |

## Getting started in game

1. Enable the five core addons, and `Tradewright_Bags` if you want the bag window.
2. Type `/ah` or `/tradewright` to open the window.
3. Open the auction house and run a full scan to fill in prices.
4. Open a profession and press Scan to store your recipes.
5. Open the Crafts tab to see which crafts are profitable.

## Optional addons

Tradewright works on its own. With Questie installed, it can show where vendors you have not visited stand. With TomTom installed, it can use TomTom's arrow when the game's own waypoint is unavailable.

## Documentation

- [Development](docs/development.md): setup, tests, lint, and copying the addons into the game.
- [Backlog and issues](docs/specifications/05-backlog.md)
- [Export package format](docs/export-format.md) and [profession data guide](docs/profession-data.md)
- [Research: gold making and market strategies](docs/research/gold-making-market-strategies.md)
- [AGENTS.md](AGENTS.md): rules for contributors and agents.

## Licence

Tradewright is released under the [MIT License](LICENSE). The Midnight profession specialization data is derived from CraftSim; see [THIRD-PARTY-NOTICES.md](src/Tradewright_Professions/THIRD-PARTY-NOTICES.md).
