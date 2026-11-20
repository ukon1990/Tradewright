# F44 — Purchases, expired and cancelled auctions in the ledger

## Summary

The ledger records what you buy at the auction house and which of your auctions came back unsold, next to the sales it already records. That gives an average buy price, a real profit per item, and your own sale chance for each item.

## Context

- `db.ledger.events` (2,500 at most) has `kind, ts, characterKey, itemID, itemName, quantity, unitCopper, totalCopper, netCopper, buyer, source`. Its only writer is the sale mail, when the gold is taken.
- `LedgerAverageUnitBuyCopper` and `LedgerPurchaseStats` exist and are read by the price fallbacks and the "Low" flag, but no buy event is ever written.
- `auction.transactions.events` has `posted`, `sold`, `visible_refresh`. Cart purchases only change session cart credits.
- Mail tells the rest: a won auction arrives with a buyer invoice (`GetInboxInvoiceInfo` → `invoiceType = "buyer"`, price paid); expired and cancelled auctions return the item under the game's own subject strings.
- Your sale chance per posting, `sales / (sales + expired + cancelled)`, is what the flip maths needs to price lost deposits.

## Scope

- New ledger kinds written when the mail's item is taken: `buy` (item, quantity, unit and total price paid), `expired`, `cancelled` (item, quantity)
- Retail only: also write `buy` on a confirmed commodity purchase, so buys do not wait for the mailbox
- `ForeverLogic.SummarizePurchases(events, itemID)` → `{units, avgUnit, lastAt}`
- `ForeverLogic.OwnSaleChance(events, itemID, minPostings)` → `p`, nil below `minPostings` (5)
- `ForeverLogic.RealizedProfit(events, itemID, cut)` → average sale net minus average buy price, and units matched
- Ledger size: keep the 2,500 latest events and, per item, a running total of older ones (`units, total` per kind) so averages do not reset when events roll off
- Sales view: "Latest sales" gains a kind filter (Sold, Bought, Came back); "What sells" gains `Bought each` and `Profit each` for items with buys
- Inventory row analytics and `ResolveReagentUnitPrice` pick the buy average up without change, because they already call the ledger helpers

## Acceptance criteria

- [ ] Buying an item and taking it from the mailbox writes one `buy` event with the price paid
- [ ] Letting an auction expire and taking the item back writes one `expired` event; cancelling writes `cancelled`
- [ ] Opening a mail without taking its contents writes nothing; taking it later writes once
- [ ] `LedgerAverageUnitBuyCopper` returns the bought price for that item
- [ ] An item with 4 sales and 1 expiry shows a sale chance of 80%
- [ ] Ledgers saved before this feature load unchanged
- [ ] Offline tests: purchase summary, sale chance below and above the minimum, realized profit with no buys, running totals after events roll off

## Verification

```bash
npm test
```

In-game on Forever: buy one item, post one item at a price that will not sell for the shortest duration, cancel another → collect all mail → Overview → Sales → Latest sales shows the three events under their kinds.

## Dependencies

- F43 shares the mail-reading path (either order works)

## Out of scope

- Vendor sales, trades, quest gold (E09 covers coin and loot during a farm)
- Reading mail the player has not opened
