# F149 — Profession panel uses the rail

## Summary

The profession panel folds from its own header into the shared rail. The "Hide panel" text button leaves the game's profession title bar.

## Context

- Design: [Tradewright Screens](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5), boards "Profession panel · collapse button in its own header" and "Profession panel · collapsed to a rail, rail tooltip".
- Today: `createPanelToggle` and `anchorProfessionPanelToggleButton` in `Tradewright_ProfessionCraftPanel.lua` put a "Hide panel" button left of the profession window's close button; `ApplyProfessionPanelExpanded` saves `professions.sidePanelExpanded`. The file is at 662 of 700 lines; this change should make it smaller.

## Scope

- Chevron at the right end of the panel header (after Recipe | Leveling | Queue), via `CreatePanelCollapseButton`
- Remove the title-bar toggle and the unused `collapseTab`
- Rail from `CreatePanelRail`; badges: queued recipes (gold), queued recipes ready to craft now (green)
- Keep `professions.sidePanelExpanded` and its meaning
- Selecting a recipe while folded does not unfold the panel

## Status

Implemented; offline tests and lint pass. Not yet checked in game (needs the full client restart from F148).

- Chevron right of Recipe | Leveling | Queue (`createPanelDock` in `Tradewright_ProfessionCraftPanel.lua`); the title-bar "Hide panel" button, `ApplyProfessionPanelExpanded`, `UpdateProfessionPanelToggleButton` and the unused `collapseTab` are gone (file 662 → 589 lines)
- Showing and hiding go through `ShowPanelDock`; folded, the side parts still refresh so the rail stays current
- Rail badges from `RefreshProfessionQueueCard`: queued recipes (gold), ready to craft now (green), with a tooltip
- New `SetPanelDockOffset`: the profession panel docks past Forever's profession selector tabs, so its rail follows the same offset

## Acceptance criteria

- [ ] No Tradewright button on the profession window's title bar
- [ ] Fold and unfold work and are kept through `/reload` and reopening the profession window
- [ ] Rail counts match the Queue view
- [ ] `Tradewright_ProfessionCraftPanel.lua` does not grow

## Verification

```bash
npm test
```

In game: fold, switch recipes, craft a queued recipe and watch the green count, unfold.

## Dependencies

- F148
