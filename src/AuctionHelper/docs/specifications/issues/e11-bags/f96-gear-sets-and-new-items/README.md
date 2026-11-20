# F96 — Gear split by equipment set, and a mark on new items

## Summary

Gear in the bag window is split into "Gear in a set" and "Gear not in a set", so gear that is probably unused stands out. New items that are not junk get a small gold corner.

## Context

- `C_Container.GetContainerItemEquipmentSetInfo(bag, slot)` says whether a slot's item is in a saved equipment set, and names the sets. Only live slots have it, so read-only tabs keep one Gear heading.
- `C_NewItems.IsNewItem(bag, slot)` is the game's own "new item" flag. The game's item button forgets it on hover; the mark here does the same.
- Both APIs are checked for at run time; a client without them shows no split and no mark.

## Scope

- `BagLogic.CategoryOf`: gear with `inSet` true or false goes to `gearset` or `gearloose`; gear with `inSet` unknown stays `gear`
- `ScanBags` sets `inSet` (when the character has at least one saved set) and `isNew` (never on junk), and adds "set", the set names and "new" to the search keywords
- Slot look: a gold corner top left on a new item; hovering removes it
- Settings `bags.splitGearSets` and `bags.markNew`, both on by default

## Acceptance criteria

- [ ] With saved sets, bag gear shows under two headings; gear in no set is under "Gear not in a set"
- [ ] With no saved sets, or the setting off, there is one Gear heading
- [ ] A freshly looted non-junk item has the gold corner until it is hovered
- [ ] Junk is never marked
- [ ] Searching a set's name or "new" lights the matching items

## Verification

```bash
npm test
```

In-game: save an equipment set, open the bags, loot an item.

## Dependencies

- F90, F92

## Out of scope

- Set membership or new marks for other characters and the saved bank list
