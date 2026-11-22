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

- Pure helpers in `Tradewright_MarketSignals.lua`:
  - `AddPriceStep(levels, price, qty, maxSteps)`: bounded insert into an ascending list, merging equal prices and dropping the dearest level past `maxSteps` (8)
  - `BuildPriceSteps(levels)` → flat array `{price1, qty1, price2, qty2, …}` sorted by price
  - `CostToClear(steps, upToPrice)` → `{qty, cost}`
  - `AverageFill(steps, units)` → average unit price for the cheapest `units`, nil when the steps do not cover that many
  - `FindPriceGap(steps, minGapPct)` → `{belowQty, belowCost, floorPrice, nextPrice, gapPct}` for the largest jump between neighbouring levels
- `Tradewright_PriceSteps.lua` (AuctionData):
  - `AggregateAuctionRow` folds a scan row into its item's aggregate and its price levels; rows without a buyout are skipped. Both scan paths call it, and the duplicated inline aggregation they carried as a fallback is removed.
  - `PersistDumpAggregate` saves one item's aggregate (the code moved out of `PersistFullAuctionDumpChunk`) and its steps
  - Steps are stored in their own table, `auction.priceSteps[itemID] = {t, l}`, not on the snapshot entry: full scans store one entry per item ID, and this keeps the snapshot compaction code untouched. They are not copied into history and are trimmed with the hourly retention at load.
  - `GetPriceSteps(itemID)` → `steps, seenAt`
- Item details: "Cheapest steps" (the three cheapest levels) and "Biggest price jump"
- Setting "Keep the cheapest price steps of each item from a full scan" (on by default); off removes an item's steps at the next scan
- Still open:
  - the live single-item search (`GetLiveAuctionSearchAggregate`) does not refresh steps yet
  - a full "Price steps" list (price, quantity, cost so far) in the item details window

## Acceptance criteria

- [ ] After a full scan an item with several prices has up to 8 steps, cheapest first, and the first step equals the stored lowest price
- [ ] An item listed at one price has one step holding its full quantity (offline test passes; in-game check pending)
- [ ] A scan of 18,000 items stays chunked and takes no noticeably longer than before
- [ ] Saved data from before this feature loads; items without steps show "-" where steps are needed
- [ ] Turning the setting off stops storing steps and nothing errors
- [x] Offline tests: merge of equal prices, more than 8 levels, stacks priced per unit, cost to clear, average fill beyond the kept steps, largest gap, single level

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
