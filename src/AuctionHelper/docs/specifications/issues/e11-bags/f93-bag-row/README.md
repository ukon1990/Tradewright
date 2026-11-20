# F93 — Bag row: equipped bags and the reagent bag

## Summary

A "Bag row" button opens a row with the backpack, the four bags and the reagent bag. Hovering a bag lights the items in it, dropping a bag on a slot swaps it in, dragging it off unequips it, and a right-click lists the bags you carry to replace it with.

## Context

- A bag slot is an inventory slot: `C_Container.ContainerIDToInventoryID(bag)`, then `PutItemInBag(slot)` and `PickupBagFromSlot(slot)`. These are the calls the game's bag bar makes; the game applies its own rules (a bag must be empty to come off).
- The game's bottom bag bar stays as it is and keeps working.

## Scope

- `AuctionHelper_BagRow.lua`: one cell per bag with icon, name and "used / size"; the reagent bag set apart by a divider
- Hover: slots of other bags dim, the bag's tooltip shows with a hint line
- Left-click or drop with a bag on the cursor: swap it in. Drag off: pick the bag up
- Right-click: a menu of the bags in your bags that fit the slot (reagent bags only for the reagent slot), and "Take this bag off"
- Setting `bags.showBagRow` (the header button and the Settings checkbox both set it)

## Acceptance criteria

- [ ] The row shows the backpack, four bag slots and the reagent bag slot, empty slots included
- [ ] Hovering a bag dims every slot that is not in it
- [ ] Dropping a larger bag on a slot swaps it in, as on the game's bag bar
- [ ] Choosing a bag from the right-click menu equips it in that slot
- [ ] The row stays open or closed across sessions

## Verification

```bash
npm test
```

In-game on Forever: open the bag row → hover each bag → drag a spare bag onto a slot → right-click a slot and pick another bag → take an empty bag off.

## Dependencies

- F92

## Out of scope

- Bank bag slots and bank tabs
- Showing how many slots a replacement bag has
