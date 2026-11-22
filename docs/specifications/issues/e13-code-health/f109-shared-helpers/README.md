# F109 — Shared core helpers for repeated code

## Summary

Replace the small non-UI helpers that were copied from file to file with one shared version each, so a fix lands once and a reader learns each helper once.

## Context

- `colorize`: local copies in `GoldDashboard.lua`, `CraftsUI.lua`, `MailPanel.lua`, `MailReviewPanel.lua`, about 13 more inline `|cff%02x…` strings, and `UI.lua GetCharacterNameMarkup` builds its own
- `trim`: `CraftsEngine.lua`, `CraftsUI.lua`, `MarketUI.lua`, `InventoryUI.lua`
- Plural idiom `n == 1 and "x" or "xs"`: 10 places (`ExportTab`, `OverviewTab:RefreshStats`, …)
- `now()`: 6 files; F106 adds `pe:Now()`, this feature makes every file use it
- TSM price strings read with the same defaults in `CraftQueue`, `Integrations` (twice), `CraftsEngine` (twice), `CraftingOrdersMaterials`
- "Try these methods with pcall, then these fields" probe: three times in `CraftsEngine GetOpenProfessionScenario`, twice in `GetOpenProfessionRecipeID`; the sell-frame child probe twice in `Tradewright_Auction.lua` (`GetAuctionPostButton` and the function F107 deletes)
- Bag slot walks: `Inventory.lua`, `MailPlans.lua`, `Holdings.lua`, `Tradewright_Auction.lua`

## Scope

- Core: `pe:Colorize(text, color)` (accepts a theme key or a hex colour; the local copies differ in argument order), `pe:Plural(count, singular, plural)`, `pe:Trim(text)`, `pe:GetTsmPriceStrings()`, `pe:FirstValueFrom(object, methodNames, fieldNames, accept)`, `pe:ForEachBagSlot(bagIDs, fn)`
- Replace every copy and every inline `|cff%02x…` string
- Offline tests: `Plural`, `Trim`, `Colorize`, `FirstValueFrom`, `ForEachBagSlot` with a fake container API

## Acceptance criteria

- [x] No local copy of any listed helper remains (`grep` shows one definition each)
- [x] Tests cover the pure helpers' edge cases (empty string, count 0 and 1, method throws, field missing)
- [x] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game: colours, plurals and TSM prices look as before; the profession window probe still finds the open recipe; bag counts match.

## Dependencies

- F105, F106 (adds `pe:Now()`), F107 (deletes some copies first)

## Out of scope

- UI helpers: columns, cards, tab adapters, dropdowns (F117)
- Splitting the files these helpers live in (F114 to F116, F118)
