# F90 — Bag logic: categories, grouping, layout

## Summary

The decisions of the bag window as pure functions: which category an item belongs to, how items are sorted and grouped, where each slot is drawn, and the slot totals.

## Context

- `Tradewright_ForeverLogic.lua` is at its frozen size. This logic belongs to the bags module, so it lives there: `src/Tradewright_Bags/src/Tradewright_BagLogic.lua`, with no WoW API, loaded by an offline test.
- Item class IDs are the game's (`Enum.ItemClass`): 0 consumable (subclass 5 food and drink), 1 container, 2 weapon, 3 gem, 4 armor, 5 reagent, 7 trade goods, 8 item enhancement, 9 recipe, 12 quest, 19 profession gear.

## Scope

- `BagLogic.CATEGORIES` in display order: Gear, Consumables, Food and drink, Trade goods, Quest, Other, Junk
- `BagLogic.CategoryOf(item)`: quest items first, then poor quality as junk, then by item class; unknown classes are Other
- `BagLogic.GroupItems(items)`: non-empty groups in display order; inside a group by quality (best first), name, then count
- `BagLogic.Layout(groups, opts)`: heading and slot positions for a column count, slot size and gap, and the total height
- `BagLogic.MergeCounts(snapshot, mode)` and `BagLogic.MergeAll(characters, mode)`: per-item counts for bags, bank or both
- `TooltipLogic.Owners(characters, itemID, skipKey)` (moved to the core so the item tooltip can use it without the bags module): who holds an item, largest first, and the total
- `BagLogic.BagTotals(bags)`: slots, used and free, with the reagent bag counted apart
- `BagLogic.JunkValue(items)`, `BagLogic.Matches(item, query)`, `BagLogic.ReplacementBags(items, forReagentSlot)`, `BagLogic.TabOrder(characters, currentKey, limit)`
- `src/Tradewright/tests/test_bag_logic.lua`

## Acceptance criteria

- [ ] Weapons and armor group as Gear; food as Food and drink; other consumables as Consumables; reagents, trade goods and gems as Trade goods
- [ ] A quest item is Quest whatever its quality; any other poor quality item is Junk
- [ ] Layout wraps at the column count and returns the full height
- [ ] Reagent bag slots are not counted as free normal slots
- [ ] Offline tests cover every function above

## Verification

```bash
npm test
```

## Dependencies

- None

## Out of scope

- Anything that calls the game
