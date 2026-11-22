# F52 — Price gaps

## Summary

A "Price gaps" list shows items where a few cheap listings sit under a much higher next price. It says what clearing them costs, what they would bring at the next price, and how long they would take to sell. The list is marked risky, because it pays only if nobody lists lower first.

## Context

- This is the small version of "resetting a market". The research found it the least supported strategy: its rules come from one author, whose own documented 1.3 million gold reset lost 300,000 because volume was overestimated. Volume at the target price, not cost, is what limits it.
- Price steps (F41) make the gap and the cost exact for the moment of the scan; they are stale minutes later on busy items.
- Whether equal prices sell oldest-first or newest-first on Forever is not confirmed, so the list assumes your auctions sell after the ones already at the next price unless you list lower.
- Design: [Opportunities, price gaps](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldPriceGaps).

## Scope

- `ForeverLogic.BuildGapRows(items, opts)`, pure. For each item with price steps and sells a day:
  - `FindPriceGap(steps, opts.minGapPct)` (default 25%) → `belowQty`, `belowCost`, `nextPrice`
  - kept when `belowCost <= opts.maxCost` (default 100g), `sellsPerDay >= opts.minSellsPerDay` (default 5) and `nextPrice <= usual high` (F40), so a gap up to an absurd listing is ignored
  - `gain = belowQty × nextPrice × (1 - cut) - belowCost - deposit`
  - `daysToSell = belowQty / sellsPerDay`; flag "takes about N days to sell" above 1
- List columns: Item (second line: "Buy N · sells out in under a day"), Cheapest, Next price, To clear, Gain if it holds, Sells a day. Sorted by gain.
- One line above the table: "Risky. A few cheap listings sit under a much higher price. Buying them all pays only if nobody lists under you before yours sell."
- Side pane: the price steps with the gap marked, cost to clear, relist price, deposit, gain if all sell, sells a day, and how many already wait at the next price
- Buttons: "Open in auction house", "Add N to cart"
- Setting "Show price gaps, marked as risky" (on) with cost limit and minimum sells a day

## Status

Implemented:

- `FlipLogic.BuildGapRow` and `BuildGapRows` (pure, offline-tested) with the rules above; a gap also needs a positive gain
- `GetGapOptions` and `GetGapRows` (AuctionData), cached until the insights or thresholds change
- "Price gaps" list in the Opportunities tab: columns as above, the side pane shows the sums and the cheapest price levels marked "Buy at" or "Stays at", and how many already wait at the next price
- Settings: "Show price gaps, marked as risky" and the cost limit

Differs from the scope:

- The risk text sits in the stat row ("Risky") and the side pane, not in a line above the table; the list has no separate badge
- Minimum sells a day for gaps is fixed at 5 (no setting yet); the deposit is 0 until F43
- No "Add N to cart" button (see F50)

## Acceptance criteria

- [x] Steps 2g 80s ×3, 2g 95s ×4, 3g 10s ×2, 4g 10s ×22 give Buy 9, To clear 26g 40s, Next price 4g 10s
- [x] An item whose next price is far above its usual range is not listed
- [x] An item without a sells-a-day estimate is not listed
- [x] Gain subtracts the cut and one deposit
- [x] The risk line and the "Risky" badge are always visible on this list
- [x] Offline tests of `BuildGapRows`: the example above, cost limit, turnover floor, usual-range guard, single-level items

## Verification

```bash
npm test
```

In-game: full scan → Opportunities → Price gaps → compare one row's steps with the auction house.

## Dependencies

- F41, F42, F43, F40, F50

## Out of scope

- Full market resets across many price levels
- Watching for undercuts after the purchase
- Any advice to buy: the list shows cost, gain and risk and leaves the choice to the player
