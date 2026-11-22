# F100 — Selection and move logic

## Summary

The rules behind selecting and bulk actions as pure functions in `BagLogic`, tested offline.

## Context

- `Tradewright_BagLogic.lua` has no WoW API and is loaded by `tests/test_bag_logic.lua`.
- A selected stack is remembered as bag, slot and item ID, so a stack that moved or changed is noticed and dropped.

## Scope

- `SlotKey(bag, slot)`, `ToggleSelected(selection, item)`, `SelectedItems(selection, items)` (which also drops stacks that are gone)
- `MoveTargets(place, state)`: where a stack in `place` ("bags", "bank", "warband") can go, given `state` (`bankOpen`, `hasWarband`)
- `PlanMoves(items, freeSlots)`: one free slot per stack, and how many stacks did not fit
- `SellQueue(items)`: the stacks a vendor buys and their total
- `DestroyQueue(items, auctionPriceOf)`: the stacks that may be destroyed, their value, and how many are refused (locked, quest, bag, rare or better)

## Acceptance criteria

- [ ] Toggling a stack twice leaves the selection empty
- [ ] A selected stack whose slot now holds another item is pruned
- [ ] No move target without an open bank; no warband target without warband tabs
- [ ] More stacks than free slots: the rest is reported, not planned
- [ ] Quest items, bags and rare or better items never enter the destroy queue

## Verification

```bash
npm test
```

## Dependencies

- F90

## Out of scope

- Any WoW API call
