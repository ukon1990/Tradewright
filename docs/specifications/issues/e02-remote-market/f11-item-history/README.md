# F11 — Item detail + hourly history

## Summary

Clicking a Market row shows item summary and hourly history from `auction.history.hourly`.

## Scope

- Detail panel: name, min/max/last, qty, listings, source, seenAt
- History list + `CreateTimeSeriesGraph` from hourly buckets (last / min / max / qty)

## Acceptance criteria

- [x] Detail updates on row click
- [x] Empty history message when no buckets
- [x] Graph uses cached hourly data only

## Out of scope

- Sale rate / percentiles / live listings ladder
