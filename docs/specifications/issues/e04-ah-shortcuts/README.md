# E04 — AH shortcuts: from Tradewright lists to the auction house

## Summary

Let the player act on what the dashboard finds without retyping item names. While the auction house is open, a row in a Tradewright list goes straight to the matching page in the auction house: a deal to its buy page, and later an owned item to its sell page.

## Context

- The Gold dashboard cards (`Tradewright_GoldDashboard.lua`) open the Market tab on every row click (`openMarket`).
- The shopping cart already has a search-and-select flow in `Tradewright_Auction.lua`: `OpenAuctionBrowseSearchForItem` switches the auction house to Buy and searches by name; `TrySelectPendingAuctionBrowseResult` runs on `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED` and opens the matching result with `AuctionHouseFrame:SelectBrowseResult`.
- Forever shows the modern `AuctionHouseFrame` (Buy / Sell / Auctions tabs, favorites); older clients may only have the classic `AuctionFrame`.
- `IsAuctionHouseFrameOpen()` and `PauseAuctionScanForManualBuy()` already exist.

## Scope

- F30: open a deal's buy page in the auction house
- F31 (candidate, not written): "Sell what I own" opens the item in the Sell tab

## Acceptance criteria

- [x] F30 done
- [x] Nothing is bought or posted without the player's own click on the auction house button
- [x] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: open the auction house → Overview → Gold → click a deal → its buy page shows.

## Dependencies

- E02 Remote market (done): deals and market movers come from its price history

## Out of scope

- Buying or posting automatically
- Quantity planning (the craft queue and shopping cart already cover that)
