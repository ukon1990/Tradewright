# F54 — Sell now

## Summary

A "Sell now" list in Opportunities shows items you own whose price is above usual and that sell, with what your stock is worth after the cut. It is the full-size version of the Gold view's "Sell what I own" card.

## Context

- The card is built inside `AuctionHelper_GoldDashboard.lua`: inventory × snapshot price, rows with change ≥ +10% when history exists, else the top 30 by value. The same pass sets the "Stock value" stat.
- It has no turnover check, so it can rank an item that never sells.
- E04 lists "Sell what I own opens the Sell tab" as candidate F31.

## Scope

- Move the row building into `ForeverLogic.BuildSellNowRows(ownedItems, priceFn, opts)`, pure: kept when `(price - usual) / usual >= opts.minPremium` (default 0.10) and sells a day is known; `worth = owned × price × (1 - cut)`; `daysToSell = owned / sellsPerDay`; flag "more than a day of sales" when over 1
- With no usual price for any owned item the list falls back to the current behaviour (top by value) and says so in its footer
- List columns: Item (second line: where it is, "12 bags · 40 bank"), Price, Vs usual, Owned, Worth, Sells a day. Sorted by Worth.
- Side pane: price, usual price and range, worth after the cut, what you paid on average when the ledger knows (F44), sells a day
- The Gold view card takes its top 5 from the same function
- Row clicks as elsewhere: left opens item details, right opens Market, shift links

## Acceptance criteria

- [ ] An owned item priced 20% above usual with a sells-a-day estimate is listed with the right worth
- [ ] An owned item above usual with no sells-a-day estimate is not listed
- [ ] The card and the list show the same top rows
- [ ] The "Stock value" stat is unchanged by this feature
- [ ] Offline tests of `BuildSellNowRows`: premium edge, unknown turnover, fallback without usual prices, worth after the cut

## Verification

```bash
npm test
```

In-game: own an item whose price rose → Opportunities → Sell now lists it → Overview → Gold shows the same row on the card.

## Dependencies

- F50 (tab), F40, F42, F43

## Out of scope

- Opening the auction house Sell tab on the item (F31 in E04)
- Choosing a posting price
