# F126 — Take the craft queue's materials from the bank

## Summary

The "Reagents" menu has a line "Take N stacks for the craft queue": it moves from the bank what this character's queued crafts need and the bags do not hold yet.

## Context

- `ReagentStashLogic.StacksToWithdraw` picks whole stacks per item: the largest that does not overshoot, else the smallest, until the need is covered.
- The need is the same as F125's hold: this character's queued crafts and crafting orders (`GetOwnQueueNeeds`).
- The move is `RunBagMoves(stacks, "bags")`, which fills general bag slots, not the reagent bag.

## Scope

- Menu line with the stack count; "Nothing in the bank the craft queue needs" when there is none
- Items the bags already cover are left in the bank

## Acceptance criteria

- [ ] After depositing everything, one click brings back the stacks the queue needs
- [ ] A 200 stack is not taken when smaller stacks cover the need
- [ ] Offline test covers the stack choice and what the bank cannot cover

## Verification

```bash
npm test
```

In-game on Forever: queue a craft, deposit with "Keep what my craft queue needs" off, then "Take … for the craft queue" → the materials are back and the craft can run.

## Dependencies

- F125

## Out of scope

- Exact amounts (stack splitting); a list of what the bank is short of
