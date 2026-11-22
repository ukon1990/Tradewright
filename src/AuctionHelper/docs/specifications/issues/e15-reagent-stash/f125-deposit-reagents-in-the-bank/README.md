# F125 — Deposit reagents in the bank

## Summary

At an open bank the bag window's header shows a "Reagents" button. Its menu holds two saved choices and a line that deposits the matching stacks from the bags.

## Context

- Rules are pure, in `AuctionHelper_ReagentStashLogic.lua` (`ProfessionReagents`, `QueueNeeds`, `IsStashed`, `StacksToDeposit`); the saved choices and the data they need are in `AuctionHelper_Inventory/.../AuctionHelper_ReagentStash.lua`; the button and menu in `AuctionHelper_Bags/src/AuctionHelper_BagStash.lua`.
- The move is `RunBagMoves(stacks, "bank")`: one stack per tick, into free general bank slots, "No room for N of the stacks" when the bank is full.
- The header's info text is anchored between the title and the leftmost button, so it truncates when the button appears.

## Scope

- Button "Reagents", shown only while the bank is open
- Menu: "Only reagents my professions use" and "Keep what my craft queue needs" (both ticked by default, saved account-wide under `reagentStash.*`), then "Deposit N stacks (M stay for the queue)"
- Ticking a box reopens the menu so the counts are right
- With the first box ticked and no profession scanned, the deposit line says so and does nothing
- Locked stacks are skipped

## Acceptance criteria

- [ ] With both boxes ticked, only reagents of scanned recipes go, and the queue's materials stay
- [ ] With the second box off everything matching goes, the reagent bag included
- [ ] With the first box off every gem, reagent and trade good goes
- [ ] The button is hidden away from a banker
- [ ] Offline test covers the selection rules

## Verification

```bash
npm test
```

In-game on Forever: open the bank → "Reagents" appears in the bag window header → the deposit line counts the stacks → click it, the stacks land in the bank → queue a craft, reopen the menu: its materials are counted as staying.

## Dependencies

- F101, F102

## Out of scope

- See E15
