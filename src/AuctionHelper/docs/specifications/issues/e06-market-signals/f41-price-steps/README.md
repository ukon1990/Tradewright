# F41 — Cheapest price steps kept from a full scan

## Summary

A full scan keeps, for each item, its cheapest price levels and how many are listed at each. With that the addon can say what it costs to buy N units, how many sit near the lowest price, and where the price jumps.

## Context

- The classic paged dump and the replicate dump both read every row (unit count, buyout, bid, seller). `AggregateClassicAuctionRow` reduces them to `marketLow, marketHigh, minBuyout, sampleSize, listingCount, weightedQty, weightedSum`, and only those are persisted.
- `GetLiveAuctionSearchAggregate` (single-item search) reduces its results the same way.
- Depth, cost to clear and gaps cannot be rebuilt from a lowest price and a total quantity; they must be derived while the rows are in hand.
- A full scan sees about 18,000 items, so the per-item cost must stay small and bounded.
- Design: [Opportunities, price gaps](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldPriceGaps).

## Scope

- While aggregating a dump, keep per item a bounded list of its cheapest unit prices: insert each row's `(unitPrice, quantity)`, merge equal prices, drop the dearest level when the list exceeds `maxSteps` (8). Rows without a buyout are skipped.
- `ForeverLogic.BuildPriceSteps(levels, maxSteps)` → flat array `{price1, qty1, price2, qty2, …}` sorted by price
- Store it on the snapshot entry as `l`. It is not copied into hourly or daily history.
- The live single-item search fills `l` the same way, so opening an item's buy page refreshes its steps (F30 already saves price and quantity from that page)
- Pure helpers:
  - `ForeverLogic.CostToClear(steps, upToPrice)` → `{qty, cost}`
  - `ForeverLogic.AverageFill(steps, units)` → average unit price for the cheapest `units`, nil when the steps do not cover that many
  - `ForeverLogic.FindPriceGap(steps, minGapPct)` → `{belowQty, belowCost, floorPrice, nextPrice}` for the largest jump between neighbouring levels
- Item details window: a "Price steps" list (price, quantity, cost so far)
- Setting "Keep the cheapest price steps of each item from a full scan" (on by default); off removes `l` at the next scan

## Acceptance criteria

- [ ] After a full scan an item with several prices has up to 8 steps, cheapest first, and the first step equals the stored lowest price
- [ ] An item listed at one price has one step holding its full quantity
- [ ] A scan of 18,000 items stays chunked and takes no noticeably longer than before
- [ ] Saved data from before this feature loads; items without steps show "-" where steps are needed
- [ ] Turning the setting off stops storing steps and nothing errors
- [ ] Offline tests: merge of equal prices, more than 8 levels, stacks priced per unit, cost to clear, average fill beyond the kept steps, largest gap, single level

## Verification

```bash
npm test
```

In-game: note the SavedVariables file size, run a full scan, `/reload`, compare the size → open an item with many listings → Price steps match the auction house's cheapest listings.

## Dependencies

- None

## Out of scope

- Sellers, time left and bids
- Steps in price history (only the latest scan keeps them)
- Deciding what to buy (F50, F52)
