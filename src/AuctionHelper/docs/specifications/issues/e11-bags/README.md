# E11 — Bags: an optional bag window grouped by category

## Summary

A sixth, optional addon, `AuctionHelper_Bags`, replaces the game's bag window with one in the AuctionHelper look. Items are grouped by what they are (gear, consumables, food and drink, trade goods, quest, other, junk), not by the bag they sit in. Other characters are tabs. Equipped bags, the reagent bag included, can still be swapped from a bag row. One checkbox turns it off again, at once.

Designs: [AuctionHelper Screens](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5), section "Proposed, not built yet: bags module".

## Context

- The Forever client has the modern bag code: `C_Container`, `ContainerFrameCombinedBags`, a reagent bag (`Enum.BagIndex.ReagentBag`) and bank tabs (`Enum.BagIndex.CharacterBankTab_*`).
- The inventory snapshot (`inventorySnapshot`) only counts items of scanned recipes, so it cannot fill a bag view. The inventory module therefore also saves every item each character carries and banks, and its gold, as `AuctionHelperInventoryDB.holdings` (`AuctionHelper_Holdings.lua`). The bags module only reads it, so there is one source for what the characters own, collected even when the bags module is off.
- Items must be used, dragged and split by the game's own secure button code. The window therefore builds its slots from `ContainerFrameItemButtonTemplate`; it never calls `UseContainerItem` itself.
- The game's bag frames are kept and only hidden (reparented to a hidden frame). They stay the source of truth for "are the bags open", so merchants, mail and the bag key keep working, and switching back needs no reload.
- The game's bottom bag bar is not changed. The bag row in the window mirrors the same slots.
- `AuctionHelper_Data.lua` is over the size limit and may not grow, so `/ah bags` is added by wrapping `HandleSlash` from the bags module.

## Scope

- F90: pure bag logic (categories, grouping, layout, totals) with offline tests
- F91: the module, its on/off switch and the settings group
- F92: the bag window for the logged-in character
- F93: the bag row: equipped bags and reagent bag, swap and replace
- F94: other characters as tabs, bank and the All tab

## Acceptance criteria

- [ ] F90 to F94 done
- [ ] With the module disabled in the AddOns list, or the checkbox off, the game's bags (or another bag addon) open as before
- [ ] No protected call is made by addon code; items are used through the game's item button template
- [ ] Retail and Forever both load the module; `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever (full restart, the module adds new files): enable AuctionHelper Bags → press the bag key → the AuctionHelper bag window opens with items under category headings → Settings → Inventory & mail → untick "Use AuctionHelper bags" → the bag key opens the game's bags again.

## Dependencies

- None

## Out of scope

- A live bank window (the game's bank stays; the bank shows here as a saved, read-only list)
- Changing the order of the categories (the "Category order" row of the design)
- Sorting or auto-stacking bags, selling junk with one click
- Item sets, item level or new-item markers on slots
- The slot count of a replacement bag in the picker (the game does not give it without reading tooltips)
