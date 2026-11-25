# E21 — Folding the docked panels

## Summary

The auction house, profession and mailbox panels fold the same way. A chevron at the right end of the panel's header hides the panel; a 28 px rail stays at the same edge. Clicking the rail brings the panel back on the tab it had. Each panel remembers whether it was folded, for the whole account.

## Context

- Today the profession panel hides with a "Hide panel" text button on the game's profession title bar (`professions.sidePanelExpanded`). The mail panel collapses with an X and comes back with a "Tradewright" button (`mail.sidePanelExpanded`). The auction house panel cannot be folded at all.
- Design: [Tradewright Screens](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5), section "Proposed, not built yet: folding the docked side panels".
- The auction house panel lives in `Tradewright_AuctionData`, which loads before `Tradewright_UI`, so the shared rail goes in the core addon next to `StyleWindow` (`src/Tradewright/src/ui/`).
- `Tradewright_ProfessionCraftPanel.lua` is at 662 of 700 lines, so the rail is its own file, not code inside each panel.

Decisions taken with the user:

- A chevron pointing at the game window, not an X: an X reads as close
- The rail carries only icons and short numbers: WoW font strings do not rotate
- Work keeps running while a panel is folded; the rail shows its state

## Scope

- F148: shared panel rail, and folding the auction house panel
- F149: profession panel uses the rail
- F150: mail panel uses the rail

## Acceptance criteria

- [ ] F148 to F150 done
- [ ] Each panel folds and unfolds; its state is kept through `/reload` and reopening the game window
- [ ] Badges stay current while folded; a count of zero is never shown
- [ ] A full scan keeps running while the auction house panel is folded, and its bar fills
- [ ] Nothing outside `Tradewright_Bags` needs it, and nothing replaces a game global
- [ ] `npm test` passes, lint baseline does not grow

## Verification

```bash
npm test
```

In game, after a full client restart (new `.lua` file): fold and unfold each panel, `/reload`, check each keeps its state.

## Out of scope

- Dragging or resizing the docked panels
- Choosing which side a panel docks on
- The dashboard window (not docked to a game window)
