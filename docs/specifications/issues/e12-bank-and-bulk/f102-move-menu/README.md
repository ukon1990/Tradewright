# F102 — Move menu per item

## Summary

A menu on an item: move it to the bank, the warband bank or the bags, whichever makes sense for where it is.

## Context

- Plain right-click on a slot uses or equips the item and must stay with the game's button. The menu opens with Alt-right-click, or with right-click while something is selected (F103); both are caught by the catcher frame of E12.
- A move puts the stack in the first free slot of a normal container of the target.

## Scope

- `Tradewright_BagActions.lua`: `FindFreeBagSlots(target)`, `RunBagMoves(items, target)` (one stack per tick, skipping stacks that changed), the menu
- Menu entries from `BagLogic.MoveTargets`; with a selection the menu acts on the selection, else on the item under the mouse
- Chat line when stacks did not fit

## Acceptance criteria

- [x] Alt-right-click on a bag item at a banker offers "Move to bank" (and "Move to warband bank" on retail)
- [x] On a bank item it offers "Move to bags" (and the other bank on retail)
- [x] Away from a banker the menu says there is nowhere to move to
- [x] A full target moves what fits and says how many stacks stayed

## Verification

```bash
npm test
```

In-game: at a banker, Alt-right-click items in each view.

## Dependencies

- F100, F101

## Out of scope

- Topping up partial stacks
