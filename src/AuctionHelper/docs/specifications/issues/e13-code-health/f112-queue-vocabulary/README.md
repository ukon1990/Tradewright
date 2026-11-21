# F112 — One name for the craft queue

## Summary

The craft queue is called CraftQueue, WorkQueue, WorkOrderQueue, ShoppingQueue and "shopping list". Pick one name, use it everywhere, and move the retail-only crafting-order queue code into a retail-gated file.

## Context

- About 72 uses of "CraftQueue" and 80 of "WorkQueue" / "WorkQueueEntry" / "WorkQueueStorage", plus the event `WorkOrderQueueChanged`, "ShoppingQueue", and the button `peAddWorkOrderBtn` labelled "Add to shopping". A reader cannot tell whether these are one queue or three.
- `RemoveCraftQueueByOrderID`, `CraftQueueMakeOrderKey` and `UpsertCraftQueueForCraftingOrder` (complexity 35) in `AuctionHelper_CraftQueue.lua` (around 534–641) are called only from the retail-gated `AuctionHelper_CraftingOrdersMaterials.lua` but load on Forever too. Moving them also brings `CraftQueue.lua` under 700 lines.
- `BuildCraftQueueSummary` is 130 lines, complexity 35.
- `ProfessionCraftPanel OnProfessionRecipeCraftedResult` (complexity 56) repeats the "deduct the crafted amount from the queue entry" block twice and waits a bare `20` seconds.

## Scope

- Confirm with the user which name wins ("craft queue" is the proposal; the UI label may stay "shopping list" if that is what players see)
- Rename functions, locals, the event and saved keys; saved keys only with a migration and a test
- Move those three functions to a retail-only file behind `IS_RETAIL` (all four TOCs). Keep `clearCraftingOrderWorkQueueEntry` in `CraftQueue.lua`: its shared paths call it on Forever too
- Extract `deductQueueEntry` and `PENDING_CRAFT_TIMEOUT_SEC`; split `BuildCraftQueueSummary` into named steps
- Tests: queue add / deduct / remove with a fake saved table, including a craft that finishes more than one entry

## Acceptance criteria

- [ ] One name for the queue in code; the glossary line in `focus/code-quality.md` names it
- [ ] Crafting-order queue code does not load on Forever
- [ ] `CraftQueue.lua` is under 700 lines; the touched functions meet the limits
- [ ] Existing queues in SavedVariables survive
- [ ] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game (full client restart when a new file is added), on Forever and retail: add three crafts to the queue, craft one, the queue counts down; on retail add a crafting order, it shows in the queue.

## Dependencies

- F105, F109

## Out of scope

- Splitting `CraftingOrdersMaterials.lua` (F114)
