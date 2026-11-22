# E07 — Opportunities tab

## Summary

One tab that answers "what should I buy or sell right now": flips priced after fees and capped to what the market can absorb, listings under vendor price, price gaps worth clearing, and owned items priced above usual. Each row shows the reasoning and goes to the auction house with one click.

## Context

- Research and sources: [WoW gold making market strategies](../../../research/gold-making-market-strategies.md), sections "Auction-house trading" and "What an addon can compute from its own data".
- Today the Gold view has four small cards (Deals to buy, Best crafts now, Sell what I own, Market movers), each a top-N list with no quantity, no fees on the buy side beyond the fixed cut, and no check that the item sells.
- The research finds the buy thresholds in circulation ("under 80% of market value") are conventions with no data behind them, that a low price without turnover is the usual way to lose gold, and that resets are the least supported strategy. The tab therefore shows turnover and risk next to every profit figure and keeps the thresholds as settings.
- Buying, bidding, posting and cancelling need the player's own click in the game client. The tab opens the right auction house page (E04) and never buys.
- Design: [flips](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldFlips), [price gaps](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldPriceGaps), [Market item](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldMarketItem).

## Scope

- F50: Opportunities tab and Flips
- F51: Sure things (listed under vendor price)
- F52: Price gaps
- F53: Weekday pattern in the Market item view
- F54: Sell now
- F55: Smaller profit floor
- F56: Show how much history there is, and allow rows with little of it
- F57: Say where "sells a day" comes from and how sure it is
- F58: How this page works, and why a list is empty

## Acceptance criteria

- [x] F50 to F58 done
- [x] Every profit shown is after the auction cut in use (F43) and names the quantity it assumes
- [x] An item with no sells-a-day estimate is never ranked as if it sold
- [x] Nothing is bought, bid on, posted or cancelled without the player's click on the game's own button
- [x] The Gold view cards and the tab show the same rows for the same list
- [x] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: full scan on several days → `/ah` → Opportunities → each list fills or shows its empty state → right-click a flip with the auction house open → its buy page shows.

## Dependencies

- E06 Market signals: F40 (usual price), F41 (price steps), F42 (sells a day), F43 (fees)
- E04 AH shortcuts: F30 (open a deal in the auction house)

## Out of scope

- Buying or posting automatically, sniping loops, cancel scans
- Cross-realm or cross-faction arbitrage
- Bids on auctions about to end (candidate; whether Forever has bids is not confirmed)
- Disenchant, prospecting and milling value (now [E18](../e18-salvage-value/README.md))
