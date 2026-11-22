# F104 — Bulk actions: move, sell, destroy

## Summary

Act on the selection: move it to the bank, warband bank or bags, sell it to a vendor, or destroy it.

## Context

- Moves reuse `RunBagMoves` (F102).
- Selling uses the item at an open merchant window, one stack per tick, and stops the moment the window closes, so nothing is ever used by mistake.
- Destroying is one stack per click (see E12). The first click only announces the count and value.

## Scope

- Move: one entry per target of `BagLogic.MoveTargets`
- Sell: only in the Bags view with a merchant open; stacks without a vendor price are skipped; chat line with the count and the gold
- Destroy: in every live view (bags, bank, warband bank), on retail and Forever. First click arms it and prints "Destroying N stacks worth X"; the button then reads "Destroy next (N left)" and each click deletes one stack. Quest items, bags and rare or better items are refused and said so
- Changing the selection disarms Destroy

## Acceptance criteria

- [x] Selecting stacks at a banker and choosing a target moves them all, one after another
- [x] Sell is offered only at a merchant and sells every selected stack that has a vendor price
- [x] Destroy never deletes on the first click, and one stack per later click
- [x] A refused stack stays in the bags and in the selection
- [x] Closing the merchant mid-run stops the selling

## Verification

```bash
npm test
```

In-game on Forever and retail: move ten stacks to the bank, sell five at a vendor, destroy three junk stacks.

## Dependencies

- F100, F102, F103

## Out of scope

- More than one deletion per click; deleting rare or better items
