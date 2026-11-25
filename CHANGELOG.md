# Changelog

## 1.0.4

- Destroying: A new Destroying tab in the `/tw` window lists the items on all your characters with their auction and vendor values, an estimated disenchant value, a suggested use for each, and which of your characters can disenchant it. The leveling route can now give back by disenchanting, and a "Below disenchant value" view finds gear on the auction house that is likely worth more disenchanted than its price, with a Search button at the open auction house.
- Mail to a disenchanter: Choose a disenchanter (and on retail a prospector and miller) in the settings, and the mailbox gets a "For <name> to disenchant" row with what they can destroy. Until you choose one, the character with the best skill is used. A switch per profession sends only what is likely worth more destroyed than sold.
- Side panels: The auction house, profession and mailbox panels can be folded into a thin rail at the edge with live counts. Click the rail to unfold it, or set a keybinding for it.
- Post profitable: Items are now judged by what you get after the auction house cut, compared with the estimated craft cost, what you paid and the vendor price. Gathered items are no longer left out. The Return column shows that estimated gain in gold.
- Bait prices: A price far below the estimated market price now warns you instead of being skipped. You can still sell it or skip it. Two new settings control when the warning shows.
- Sold rate: The Sold column and the "You sold" tooltip line now come from your mail (sold, expired and cancelled auctions). Before, nearly every item showed 0%.
- Price history: Fixed daily prices staying empty, so the charts, usual price and sales a day now use every day of scans.
- Tables: Number and money columns grow to fit their values, the Market table headers have tooltips that explain each column, and the sell panel filters have labels.
- Item names: Item details and the Market side panel show the item name instead of "#id" once the game has loaded the item.

## 1.0.3

- Professions: The Scan button is gone. A profession you have never stored is stored as soon as you open it, and it is updated each time you close the window. Type `/tw rescan` to scan it again by hand.
- Full scan: Fixed a case where the answer to another auction house search could end the page-by-page full scan early, so only a few items got prices.
- Price history: The 14 day and 90 day charts now show the data collected so far, instead of staying empty until that much history exists.
- Item details: The button that opens an item's details is now on the other tabs of the `/tw` window too.

## 1.0.2

- Color themes: The addon now supports color themes, so that you can make it better match your UI. It has 6 themes + custom base and highlight color selection.
- New version notice: You will now get a chat message, telling you that a new version is out. This can be turned off in the settings.
- Minimap button: LibDBIcon is no used, so that addons that group minimap buttons can group the minimap icon.

## 1.0.1

- Get started: Added a get started dialog box for new users, so that it hopefully is clearer to new users how to do the basics (updating the AH data)
- The full scan button now has a "primary" button type color, so that it stands out.

## 1.0.0

First public release, for WoW Forever and retail.

- Auction house: full scan with price history and a usual price per item, prices on tooltips, a Market tab, and an Opportunities tab (flips, items below vendor price, what to sell now).
- Selling: a panel beside the auction house to post many items one click each, check your auctions and cancel undercut ones.
- Professions: cost and profit per craft, a craft queue with a cart for the reagents to buy, how many to make, cooldown crafts and a leveling route.
- Inventory and gold: bags and bank across your characters, sales and income views, a farm window, and mail tools between your crafters and your bank character.
- Bags (optional): bag and bank window grouped by category, other characters as tabs, an item log.
- In-game Help tab, and `/tw help` for the commands.
