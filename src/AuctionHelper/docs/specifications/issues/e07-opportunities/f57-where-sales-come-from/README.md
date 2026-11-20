# F57 — Say where "sells a day" comes from and how sure it is

## Summary

The sells-a-day figure is an estimate from the player's own scans, with the player's own sales as a floor. Show which source a row used, how many scan pairs it rests on and that it runs high. That way a thin estimate is visible and not taken at face value.

## Context

- `MarketSignals.EstimateSoldByDay` counts drops in listed quantity between scans no more than 26 hours apart. Cancelled and expired auctions count as sold too, so the figure runs high.
- `SellsPerDay` needs 2 scan pairs. With fewer it falls back to the player's own sales from the ledger (`ownSalesPerDay`), and with none it returns nil, so the item cannot be a flip.
- The result already has `pairs` and `confidence` ("good" at 5+ pairs, "few" at 2 to 4). Flip rows carry `fewSales`, shown as "· few sales seen" after the item line. The row does not say whether the number came from scans or from own sales.
- A player who scans every few days never gets a scan pair. Nothing tells them why.

## Scope

- `SellsPerDay` returns `source`: "scans", "own" (own sales only, under 2 pairs) or "both" (scans, raised to own sales).
- Flip, gap and sell-now rows carry `sellsSource` and `sellsPairs`.
- Side pane, "Sells a day, estimated" row: second text "from 3 scan pairs", "from your own sales" or "from 7 scan pairs and your sales".
- "What could go wrong" adds by source:
  - few pairs: "Seen over only N pairs of scans. Cancelled and expired auctions count as sold, so it may sell slower."
  - own only: "Only your own sales are known. Scan at least twice within a day to see the whole market."
- Sells a day column: a "?" after the number when confidence is "few" or the source is "own".
- Coverage card (F56) second line, when most items lack sells a day: "Scan twice within a day to see what sells".

## Acceptance criteria

- [ ] A row whose estimate comes from own sales only says so in the side pane
- [ ] A row with 2 to 4 scan pairs shows "?" and the pair count
- [ ] A row with 5+ pairs shows no "?"
- [ ] Offline tests: `SellsPerDay` source for scans only, own only, both
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: two scans a few hours apart, the next day → Flips → select a row → side pane names the pair count.

## Dependencies

- F42, F50; F56 for the coverage line

## Out of scope

- Telling cancels and expiries apart from sales (the scan cannot see it; F44 records the player's own)
- Reading sale history from other addons
