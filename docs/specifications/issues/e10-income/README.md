# E10 — Income: where your gold comes from

## Summary

Show where gold comes from and where it goes. Every change to the character's gold is filed under a source (vendor, quests, loot, auction house, mail, trade, other); each auction sale is labelled crafted, resold or farmed; and an Income view ranks the sources, the item types that earn, and how fast they sell.

## Context

- The ledger (`db.ledger.events`) records auction sales only, written when the sale gold is taken from the mailbox (`Tradewright_Ledger.lua`). Nothing records crafts, vendor sales, quest gold or loot.
- `PLAYER_MONEY` feeds `RecordWalletObservation` (`Tradewright_ItemAnalytics.lua`), which keeps the balance per hour. It never asks why the balance changed.
- `auction.transactions.events` has `posted` events (item, quantity, time), which can be matched to sales for time to sell.
- F44 plans to add `buy`, `expired` and `cancelled` ledger events; F70 plans to count coin and vendor sales during a farm run only.
- `Tradewright_ForeverLogic.lua` is at its frozen size in `scripts/lint-baseline.json` and may not grow. The pure logic of this epic goes in a new `src/Tradewright/src/util/Tradewright_IncomeLogic.lua`, listed in all four core TOCs and loaded by the offline tests.
- Tracking starts when this ships. Auction sales already in the ledger are the only history it can show from before.

## Scope

- F80: gold changes by source
- F81: where each sold item came from
- F82: Income view

## Acceptance criteria

- [x] F80 to F82 done
- [x] Every new calculation is a pure function in `Tradewright_IncomeLogic.lua` with offline tests
- [x] Gold whose source cannot be told apart is counted under Other, never dropped and never counted twice
- [x] Saved data written before this epic still loads
- [x] Retail and Forever both work
- [x] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: sell an item to a vendor, turn in a quest that pays gold, loot coin, collect an auction sale → Overview → Income lists each under its source with the right amount.

## Dependencies

- F44 for the resold label and the sell rate (both show "-" without it)

## Out of scope

- Gold earned before this ships, other than auction sales already recorded
- Profit per sale after material costs (F44, E08)
- Telling warband or alt transfers apart from other mail
