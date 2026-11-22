# F12 — Dump enrichment

## Summary

At full AH dump, store listing count and max unit price alongside market low / sample quantity.

## Scope

- Extend `ForeverLogic.AggregateClassicAuctionRow` (`listingCount`, `marketHigh`)
- Persist through `PersistAuctionDumpObservation` → compact snapshot (`n`, `h`)
- Replicate dump path uses the same aggregate helper (DRY)

## Acceptance criteria

- [x] Classic + replicate aggregates expose listingCount + marketHigh
- [x] Compact snapshot keeps `n`/`h` across trim/compact
- [x] Retail sell / Midnight gates untouched

## Out of scope

- Percentiles / sale rate
