# E06 — Market signals

## Summary

Give every list in the addon better numbers to work from: a usual price that one odd listing cannot move, the cheapest price steps of each item, an estimate of how many sell a day, the real fees, and a ledger that knows what was bought and what failed to sell. Nothing here is a new tab; E07, E08 and E09 are built on it.

## Context

- Research and sources: [WoW gold making market strategies](../../../../../../reports/WoW%20gold%20making%20market%20strategies.md), section "What an addon can compute from its own data".
- A full scan keeps one entry per item: `{t, p, s, q, n, h}` (seen, lowest unit price, source, quantity, listing count, highest unit price). The scan reads every row, but `AggregateClassicAuctionRow` (`Tradewright_ForeverLogic.lua`) keeps only these aggregates, so depth cannot be worked out afterwards.
- `history.hourly` holds min, max, last and counts per hour. Its `w / q` is the lowest price again, not an average. `history.daily` is never filled and `CompactAuctionStorageData` clears it.
- The "usual" price behind Deals and Market movers is the 7-day average of hourly lowest prices (`SummarizeHourlyHistory`, `ClassifyMarketItem`), or TSM `dbmarket` when TSM is installed.
- Sold per day, median and volatility exist nowhere in the addon. The only sale rate shown is TSM's.
- The auction cut is the literal 0.05. No official source gives the cut or deposit rule for Forever.
- The ledger records only sale mail. `LedgerAverageUnitBuyCopper` and `LedgerPurchaseStats` have nothing to read.

## Scope

- F40: daily price history and a robust usual price
- F41: cheapest price steps kept from a full scan
- F42: estimated sells per day and days of supply
- F43: fees read from the game and measured from sale mail
- F44: purchases, expired and cancelled auctions in the ledger

## Acceptance criteria

- [ ] F40 to F44 done
- [ ] Every new calculation is a pure function in `Tradewright_ForeverLogic.lua` with offline tests
- [ ] Saved data written before this epic still loads; missing fields read as "not known", never as zero
- [ ] Retail and Forever both work; nothing here depends on TSM or Auctionator
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: two full scans a day apart → Market shows a usual price and, after a few days, sells a day → sell one item and collect the mail → Settings shows the measured auction cut.

## Dependencies

- E02 Remote market (done): snapshot and hourly history
- E05 Table paging (implemented): new columns go into the shared table

## Out of scope

- Region-wide or other players' data: everything comes from this account's own scans and mail
- Copying TradeSkillMaster's market value algorithm or its weights
- Sellers, bids and time left of other players' listings
