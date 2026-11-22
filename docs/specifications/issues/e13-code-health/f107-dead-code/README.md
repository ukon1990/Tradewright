# F107 — Delete dead code

## Summary

Delete about 30 functions and fragments that are unused or redundant, several of them over the lint limits.

## Context

Found by whole-word search over `src/` (re-check each before deleting; a name may be called through a string or a table).

No callers (delete):


- `Tradewright_Auction.lua`: `GetAuctionSellFrameUnitPriceCopper` (complexity 25), `GetLastAuctionQueueScanAt`, `GetLastObservedAuctionPrice`, `GetAuctionUnitPriceForCraftCost`, `GetAuctionUnitPriceForCraftSale`, the unused parameter `_priceStateIgnored`, the legacy `"ProfessionExporterAuctionPanel"` in `KNOWN_AH_SIDE_PANELS`
- `Tradewright_Data.lua`: `CollectSpecializationTree`
- `Tradewright_Util.lua`: `EstimateJsonEscapedByteLength`, `StopStateWatcher`
- `Tradewright_CraftsEngine.lua`: `GetRetailCurrentExpansionCraftTag`, `GetCraftExpansionFilterOptions`, `FormatReagentSlotEconomicsTooltipSuffix`
- `Tradewright_SpecCatalog.lua`: `ResolveSpecCatalogForBaseProfession`
- `Tradewright_ItemAnalytics.lua`: `ResolveGraphItemIDForCraftRow` (60 lines, complexity 32), `BuildItemDetailScrollBodyLines` (55 lines, complexity 24)
- `Tradewright_InventoryTable.lua`: `GetItemSourceLabelFromRoles`, `BuildInventoryRowsForAccount`
- `Tradewright_Inventory.lua`: the inline fallback in `GetItemCountByLocation` that copies `ForeverLogic.ResolveLocationCounts` (ForeverLogic always loads first)
- `Tradewright_MailPlans.lua`: `GetMailKeepAmount`
- `Tradewright_Widgets.lua`: `CreateCard`, `CreateSectionTitle`, `CreateMutedText`, `CreateStatusBadge`
- `Tradewright_CraftsUI.lua`: `ScheduleCraftsSearchRefresh`

Redundant wrappers or no-ops (inline the callers, then delete):

- `Tradewright_Auction.lua`: `copyScanKeyFields` (copies what `NormalizeAuctionItemKeyFields` already returns fresh; 7 callers), `AuctionScanEntryKey` (a pure alias; 6 callers)
- `Tradewright_ItemAnalytics.lua`: `formatCopperFullLocal` (only calls `pe:FormatCopperFull`)
- `Tradewright_CraftingOrdersMaterials.lua`: `hideLegacyOrderInfoButtons` (complexity 18; called once, but nothing creates the buttons it hides any more — confirm in-game on retail)

## Scope

- Delete the unused items after re-checking callers (including string lookups like `pe[name]` and XML)
- Inline the callers of the wrappers, then delete them
- Remove the entries of deleted functions from the baseline with `npm run lint:baseline`

## Acceptance criteria

- [ ] Every listed item is deleted, or kept with the reason noted in the commit message
- [ ] Lint baseline shrinks; the new baseline is committed
- [ ] `npm test` passes; no Lua error on load on Forever and retail

## Verification

```bash
npm test
```

In-game: load on Forever and retail, open `/ah`, every tab, the AH panel, a profession window, the bag window — no Lua errors.

## Dependencies

- None

## Out of scope

- Merging duplicates (F109, F111)
