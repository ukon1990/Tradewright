# E12 — Bank and bulk actions in the bag window

## Summary

The bag window also becomes the bank window: at a banker the Bank view is live, and items go in and out from there. Items can be moved between bags, bank and warband bank from a menu. Several items can be selected and moved, sold or destroyed together. A setting gives the game's own bank window back.

## Context

- E11 left the bank as a saved, read-only list. The bank's containers are ordinary bag IDs (`Enum.BagIndex.Bank`, `CharacterBankTab_*`, and on retail `AccountBankTab_*`), so the live slots of E11 work for them unchanged.
- The game ends the bank session when its bank window hides. With the setting on, the game's `BankFrame` therefore stays open and is only made invisible (alpha 0, tiny scale). Nothing is replaced, so the setting works without `/reload`.
- The live slots are the game's item buttons and must keep running the game's own click code, untainted. Selecting and the menu therefore never touch those buttons: a transparent catcher frame lies over the slots while Ctrl or Alt is held, or while something is selected, and takes the clicks.
- Moving a stack is `C_Container.PickupContainerItem` on the stack and then on a free slot of the target, the same as dragging it. Selling is `C_Container.UseContainerItem` and runs only while a merchant window is open, where using an item sells it. This is the one place the module calls `UseContainerItem`.
- Deleting needs a click of the player for every stack (`DeleteCursorItem`), so bulk destroy is one click per stack.
- Forever has no warband bank; every warband entry hides when `AccountBankTab_*` is missing.

## Scope

- F100: pure selection and move logic with offline tests
- F101: the bank in the bag window, and the setting that gives the game's bank window back
- F102: move menu per item
- F103: multi-select
- F104: bulk actions: move, sell, destroy

## Acceptance criteria

- [ ] F100 to F104 done
- [ ] With "Use AuctionHelper for the bank" off, the game's bank window opens as before, without `/reload`
- [ ] Right-click, drag, split and shift-click on an item behave as in E11 when nothing is selected
- [ ] Nothing is deleted or sold without a click; nothing is used by addon code outside a merchant window
- [ ] Retail and Forever both load the module; `npm test` passes

## Verification

```bash
npm test
```

In-game (full restart, the module adds new files): open the bank → the bag window shows the Bank view, the game's bank window is not visible → right-click a bank item, it lands in the bags → Ctrl-click three junk items in the bags → the bar says "3 selected" → Destroy, then click through.

## Dependencies

- E11

## Out of scope

- Buying bank tabs or bank bag slots, "Deposit all reagents", depositing or withdrawing warband gold (use the game's bank window: turn the setting off)
- Moving items while away from a banker
- Topping up partial stacks when moving; sorting or auto-stacking
- Bags and bank side by side in two windows
