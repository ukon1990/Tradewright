# F92 — Bag window for the logged-in character

## Summary

The window: title bar, search, category headings with item slots, one tile for the free slots, and a footer with free slots and gold. Items are used, dragged, split and linked exactly as in the game's bags.

## Context

- Slots are `ContainerFrameItemButtonTemplate` buttons under one parent frame per bag (the parent's ID is the bag, the button's ID the slot), so the game's own click, drag and tooltip code runs.
- A slot keeps its bag and slot for its whole life; only its position changes when items regroup.
- Look: `StyleWindow`, 34px header, `CreateHeading`, 36px slots with a 1px outline in the item's quality colour, 4px gaps, 12px padding.

## Scope

- `Tradewright_BagData.lua`: read the bags (`C_Container`), describe each item (name from its link, class from `C_Item.GetItemInfoInstant`, sell price when cached), free slots per bag
- `Tradewright_BagButtons.lua`: the live slot buttons (icon, count, quality outline, lock, cooldown) and plain read-only ones
- `Tradewright_BagWindow.lua`: the frame and its refresh
  - header: "Bags", "46 / 98 slots", Bag row button, close; drag to move, position saved
  - search box: items that do not match are dimmed
  - a heading per category with its item count; Junk also shows its sell value (setting)
  - free normal slots collapse into one tile showing the count; dropping an item on it puts it in the first free slot
  - content taller than the screen scrolls with the mouse wheel
  - footer: free slots, free reagent bag slots, gold
- Redraw on `BAG_UPDATE_DELAYED`, `ITEM_LOCK_CHANGED`, `BAG_UPDATE_COOLDOWN`, `PLAYER_MONEY`, `GET_ITEM_INFO_RECEIVED`, only while shown, at most once per frame
- Settings `bags.columns` (8, 10, 12, 14), `bags.slotSize` (30, 36, 42), `bags.showJunkValue`

## Acceptance criteria

- [x] Every item in the backpack, bags and reagent bag shows once, under the right heading
- [x] Right-click uses or equips, drag moves, shift-click splits or links, as in the game's bags
- [x] Looting, selling or moving an item regroups the window without reopening it
- [x] Typing in the search box dims everything that does not match
- [x] The window never leaves the screen; long content scrolls

## Verification

```bash
npm test
```

In-game on Forever: open the bags → compare with the game's bags (switch off) → every stack is there; use a potion, equip gear, split a stack, drag an item onto the free tile, sell junk at a merchant.

## Dependencies

- F90, F91

## Out of scope

- Using items in ways the game's item button does not (no automation)
