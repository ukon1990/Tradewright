# F148 — Shared panel rail, and folding the auction house panel

## Summary

A shared rail and collapse button for every docked panel, first used by the auction house panel. The chevron in the panel header folds it into a 28 px rail showing the cart count and scan progress; clicking the rail brings the panel back.

## Context

- Design: [Tradewright Screens](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5), boards "Auction house panel · collapse button, hover tooltip", "Auction house panel · collapsed to a rail" and "Docked panels · collapse button and rail states".
- The auction house panel docks at `TOPLEFT` of the auction window's `TOPRIGHT` (+8, −20) (`Tradewright_AuctionPanelBuild.lua`); its tabs are Sell, Cart and Auctions (`Tradewright_AuctionPanelLayout.lua`).
- Several functions in the auction panel files are in `scripts/lint-baseline.json`; they may not grow, so the fold wiring goes in its own functions.

## Scope

- New `src/Tradewright/src/ui/Tradewright_PanelRail.lua`, listed in all four core TOCs:
  - `CreatePanelRail(owner, anchor)`: 28 px wide, anchored like the open panel (8 right of the game window, 20 below its top, 16 above its bottom); the whole rail is one button; top down: chevron, mark, badges
  - `CreatePanelCollapseButton(header)`: icon button with a chevron pointing at the game window, tooltip "Hide panel"
  - Badge slots: gold count, green count, progress bar that fills bottom up; a count of zero hides its badge
  - Hover tooltip listing what the badges stand for and which tab the panel opens on
- Auction house panel: chevron at the right end of its header; new setting `auction.sidePanelExpanded` (default `true`)
- Rail badges: cart item count (gold); full or craft scan progress (bar, gone when done)
- Keybinding "Fold or unfold the Tradewright panel" acting on whichever docked panel is showing (`Bindings.xml` or the game's binding API; globals in `.luacheckrc`)
- All new texts as `L["..."]`; locale files updated

## Status

Implemented; offline tests and lint pass. Not yet checked in game (needs a full client restart: new `.lua` and `Bindings.xml`).

- `Tradewright_PanelRail.lua` (new, core): `CreatePanelDock`, `ShowPanelDock`, `SetPanelDockExpanded`, `IsPanelDockExpanded`, `IsPanelDockShown`, `SetPanelDockBadges`, `TogglePanelDock`
- `Tradewright:DrawGlyph` pulled out of `SkinCloseButton`; new glyphs `foldLeft` and `foldRight`
- `src/Tradewright/Bindings.xml`: binding "Fold or unfold the Tradewright panel" under the Tradewright header
- Auction house panel: chevron right of the Sell / Cart / Auctions switch (`BuildAuctionPanelDock`); `auction.sidePanelExpanded` (default `true`); rail shows the cart count and a bar for a full scan, price check or posting; bag updates refresh it while folded
- Closing the auction house hides panel and rail (`hideAuctionPanel`), which also took `OnAuctionHouseClosed` under the length limit

Differs from the design: the rail tooltip says "Click to show the panel." without naming the tab. No offline test: badge selection is only "hide at zero".

## Acceptance criteria

- [ ] Chevron folds the panel; clicking anywhere on the rail unfolds it on the same tab
- [ ] State survives `/reload` and closing and reopening the auction house
- [ ] A full scan started before folding keeps running; the rail bar follows its progress
- [ ] Cart count on the rail matches the Cart tab; no badge at zero
- [ ] Rail never overlaps the auction house window
- [ ] Offline test for badge selection if it is more than a count above zero

## Verification

```bash
npm test
```

In game after a full client restart: fold during a full scan, watch the bar, unfold, `/reload`, reopen the auction house.

## Dependencies

- None

## Out of scope

- Profession and mail panels (F149, F150)
