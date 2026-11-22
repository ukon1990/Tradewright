# F95 — Make room: delete the cheapest stack, or swap it for loot

## Summary

Two ways out of full bags. A "Make room" button in the bag window deletes the stack worth least, one stack per click. And when loot does not fit, a prompt offers to delete that stack and take the loot instead, when the loot is worth more.

## Context

- Deleting is `C_Container.PickupContainerItem` followed by `DeleteCursorItem`, the same calls as dragging an item out of the bags and confirming. It cannot be undone, so it only ever runs from a click of the player; nothing is deleted on an event.
- The game says "Inventory is full" through `UI_ERROR_MESSAGE` with `ERR_INV_FULL`. Loot that stacks onto what is carried still fits, so the prompt waits for that message rather than guessing from the free slots.
- A deleted stack leaves the bags on the next `BAG_UPDATE_DELAYED`; only then can `LootSlot` take the item.

## Scope

- `BagLogic.CheapestToDrop(items, auctionPriceOf)`: the junk stack a vendor pays least for; with no junk, the cheapest other stack valued at the higher of vendor and auction price. Never offered: locked stacks, quest items, bags, rare or better, items without a vendor price (keys, hearthstone), and the last profession tool of each kind (skinning knife, mining pick, fishing pole, …; a spare copy may go)
- `BagLogic.BestLootSwap(loot, drop)`: the most valuable loot that is worth more than the stack to delete
- `Tradewright_BagDrop.lua`: the Make room button, shown in the footer when no normal slot is free. The tooltip names the stack and its value. Junk is deleted on the first click; any other stack needs a second click on the same stack within 5 seconds
- `Tradewright_BagLootSwap.lua`: after "Inventory is full" while the loot window is open, a small prompt under the loot window: "Delete X (value) to loot Y (value)?" with Swap. Swap deletes the stack, then loots the item once the slot is free. Works whether or not the bag window is the one in use
- Setting `bags.lootSwap` (default on) in the Bags settings group
- The stack is chosen again at the moment of each click, never from an earlier redraw

## Acceptance criteria

- [x] With a free slot there is no Make room button
- [x] With full bags and junk, one click deletes the cheapest junk stack and says so in chat
- [x] With full bags and no junk, the first click only announces the stack; the second deletes it
- [x] Quest items, bags, rare or better items items without a vendor price and the last profession tool of each kind are never offered
- [x] Looting an item worth more than the cheapest stack with full bags shows the prompt; Swap deletes the stack and the item is looted
- [x] Loot worth less than the cheapest stack shows no prompt
- [x] Nothing is deleted without a click

## Verification

```bash
npm test
```

In-game on Forever: fill the bags → the footer shows "Make room" → hover it, click it → loot a mob with full bags → the prompt names both items → Swap.

## Dependencies

- F90, F92

## Out of scope

- Deleting without a click, or more than one stack per click
- Quest loot (it has no value to compare) and coin or currency
- Selling junk at a vendor
