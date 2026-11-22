# F116 — Split `Tradewright_Auction.lua`

## Summary

Split the largest legacy file into files with one job each. This is the largest readability gain and the riskiest change, so it comes last and moves code only.

## Context

- `Tradewright_Auction.lua` (5669 lines, 76 over-limit functions) is the in-game hot path for AH events and scanning. Seams: item keys and bag slots; live search and the refresh queue; bulk post and sell frame; store (DB, migrations, history trim) and pricing; item rules; cart; panel layout and owned tab; full scan; AH event handlers.
- It uses 51 `state.auction*` keys that are created on first use; `GetState` declares 18. It has 35 `C_Timer.After` calls with bare delays (0.05 to 1.5 s). `ContinueAuctionDump` has the "dump finished" block twice.
- Names: `n`, `m` → `commodityResultCount`, `itemResultCount`; `u` → `unitPrice`; `g` → `variantGroup`; `f` → `keyFields`; `st` → `settings`; `agg` → `searchAggregate`. One word each for full scan (dump / replicate / classic_full) and for AH price (native / live / current).
- `Tradewright_AuctionPanelBuild.lua` (652, lint-clean): sell-tab filters can move out; `attachSimpleTooltip` / `panelButton` wrap `Auction.lua` methods used only here.

## Scope

- One new file per commit, moving code only; renames in separate commits
- Declare every `state.auction*` key in one initializer with a one-line comment each
- Named constants for the timer delays
- One copy of the "dump finished" block
- `AuctionPanelBuild.lua` under 500 lines
- All four TOCs of `Tradewright_AuctionData`; full client restart after each new file

## Acceptance criteria

- [ ] `Tradewright_Auction.lua` is gone or under 500 lines; no new file over 500
- [ ] Every `state.auction*` key is declared in one place
- [ ] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game after every commit (full client restart), on Forever and retail: AH opens with the side panel; full AH dump completes and fills prices; live search and queued refresh update a row; post an item from the sell tab; cart lists crafts' reagents.

## Dependencies

- F111, F113 (tests and normalizers in place)

## Out of scope

- Renaming `ProfessionExporter` (F119)
- `Tradewright_Data.lua` (F118)
