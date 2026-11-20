# F50 — Opportunities tab and Flips

## Summary

A new Opportunities tab lists flips: items listed well under their usual price that also sell. Each row says what to pay, how many to buy and the profit expected after fees; the side pane shows the sums and the price at which the flip starts losing gold.

## Context

- Main tabs are declared in `AuctionHelper_UIShell.lua` (Overview, Inventory, Market, Crafts, Export, Docs, Settings).
- `GetMarketInsights` (`AuctionHelper_MarketInsights.lua`) builds the top 50 deals from `ClassifyMarketItem`; `AuctionHelper_GoldDashboard.lua` shows them in "Deals to buy" with Price, Usual and Off.
- `OpenItemInAuctionHouse` (F30) opens an item's buy page; the shopping cart already exists.
- Expected profit of a flip with buy price `B`, sale price `S`, cut `c`, deposit `d` and sale chance `p`: `S × (1 - c) - B - d × (1 - p) / p`. It breaks even at `S = (B + d × (1 - p) / p) / (1 - c)`.
- How much to buy is bounded by turnover, not by gold: more than a share of a day's sales will not sell at the usual price.
- Design: [Opportunities, flips](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldFlips).

## Scope

- New tab "Opportunities" after Overview: `AuctionHelper_OpportunitiesTab.lua` and `AuctionHelper_OpportunitiesUI.lua` in `AuctionHelper_UI`, listed in all four TOCs
- A segmented control with one button per list and its count. This feature ships Flips; F51, F52 and F54 add theirs. A list whose feature is not present has no button.
- `ForeverLogic.BuildFlipRows(items, opts)`, pure. For each item with a usual price (F40):
  - limit price = `usual × (1 - opts.minDiscount)` (default 0.25)
  - `buyQty` = units listed at or under the limit price (F41), capped at `ceil(opts.dayShare × sellsPerDay)` (default a third); without price steps `buyQty` is nil and the row shows the lowest price only
  - `cost` = cost of the cheapest `buyQty` units; `profit` = `buyQty × usual × (1 - cut) - cost - expected deposit loss`
  - dropped when `profit < opts.minProfit` (default 5g) or `sellsPerDay < opts.minSellsPerDay` (default 1) or sells a day is unknown
  - `flags`: "sells slowly" when `buyQty` is over a day of sales, "few sales seen" from F42's confidence
- Table columns: Item (second line: "N% under usual · Q listed under P"), Buy at, Usual, Buy, Profit, Sells a day. Sorted by Profit.
- Stat row: expected profit of all rows, gold needed against gold owned, the usual-price window, price age
- Side pane for the selected row: cheapest now, usual price, sale after the cut, deposit lost if it does not sell, profit each, return; "How many to buy"; "What could go wrong" with the usual range and the break-even price
- Buttons: "Open in auction house" (F30; disabled with a hint when it is closed) and "Add to cart" with the suggested quantity
- Row clicks follow F30: left opens item details, right opens the auction house or Market, shift links
- Gold view: "Deals to buy" takes its rows from `BuildFlipRows` (top 5) so both places agree
- Settings group "Opportunities": discount, smallest profit, minimum sells a day, share of a day's sales
- Empty state: "No flips right now. Scan the auction house on a few different days to build usual prices." with a button to the auction house hint

## Status

Implemented:

- `AuctionHelper_FlipLogic.lua` (core, pure): `BuildFlipRow` and `BuildFlipRows` with the rules above
- `AuctionHelper_Opportunities.lua` (AuctionData): `GetFlipOptions`, `GetFlipRows` from the market insights, cached
- `AuctionHelper_OpportunitiesTab.lua` (UI): stat row, table, side pane with the sums and "What could go wrong", "Open in auction house"; right-click a row opens the auction house when it is open
- The tab list moved to `AuctionHelper_TabOrder.lua` (the shell file is over its size limit)
- Settings group "Opportunities"

Still open:

- The segmented control: with one list there is nothing to switch, so it arrives with F51
- "Add to cart": the cart is built from the craft queue and has no call to add a single item
- Gold view "Deals to buy" still uses its own rows
- Expected deposit loss is 0 until F43 reads deposits and F44 gives the sale chance
- Left click opens the side pane, not the item details window

## Acceptance criteria

- [ ] The tab opens from `/ah` with the auction house closed
- [ ] A cheap item with no sells-a-day estimate is not listed
- [ ] `Buy` never exceeds the units listed under the limit price nor the share of a day's sales
- [ ] Profit equals the side pane's sums for the selected row, to the copper
- [ ] Changing a setting re-filters the list without a reload
- [ ] With price steps turned off the list still works and `Buy` shows "-"
- [ ] "Open in auction house" shows the item's buy page; nothing is bought
- [x] Offline tests of `BuildFlipRows`: discount edge, profit floor, turnover cap, missing steps, missing sells a day, flags, sort order

## Verification

```bash
npm test
```

In-game on Forever (restart the client: new files): scans on 5 or more days → Opportunities → pick a flip → check the listed quantity and price against the auction house → right-click → buy page.

## Dependencies

- F40, F42, F43; F41 for quantities
- F30

## Out of scope

- Tracking a flip after the purchase (F44 gives realized profit per item)
- A per-item position limit from the player's gold
- Alerts or sounds when a flip appears
