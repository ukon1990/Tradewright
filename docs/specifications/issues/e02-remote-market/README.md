# E02 — Remote market browser

## Summary

Browse the last AH snapshot and item hourly history from the Tradewright dashboard without standing at the auction house. Enrich full dumps with listing count and price spread (min/max unit).

## Context

- Snapshot + `history.hourly` already persist after a full dump (`classic_full` / `replicate_full`).
- Players want a Market tab inspired by the companion web app: search cached items, open detail + price history.
- Cache does **not** have region sale rate, avg sold/day, or true p25/p75 — those stay out of scope.

## Scope

- Market dashboard tab (search / filter / sort snapshot rows)
- Item detail panel with hourly history list + time-series graph
- Dump enrichment: `listingCount`, `marketHigh` (unit) alongside existing min / quantity
- Pure ForeverLogic builders + offline Lua 5.1 tests
- Retail path unchanged except shared enrichment when replicate dump runs

## Acceptance criteria

- [x] Market tab opens from `/tradewright` without AH open
- [x] Rows come only from stored snapshot (commodities + items)
- [x] Search matches item name or item ID; columns sortable
- [x] Selecting a row shows summary + hourly history from cache
- [x] Full dump stores listing count + max unit price when available
- [x] `python3 tests/run_tests.py` passes
- [x] No break to retail SetItemByLocation sell inject / Midnight-only gates

## Verification

```bash
cd Tradewright && python3 tests/run_tests.py
```

In-game: full AH dump → `/reload` or restart if TOC changed → Market tab lists items → click → history graph/list.

## Dependencies

- E01 Forever port (done)

## Out of scope

- Live remote AH queries
- Region sale rate / avg sold/day / true percentiles
- Web-app chart parity beyond last/min/max/qty from hourly buckets
