# F150 — Mail panel uses the rail

## Summary

The mail panel folds like the other docked panels: the chevron replaces its X, the rail replaces the "Tradewright" button at the mailbox edge.

## Context

- Design: [Tradewright Screens](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5), board "Docked panels · collapse button and rail states" (Mailbox rail).
- Today: `CreateMailPanelHeader` builds a close-style collapse button and `BindMailPanelCollapse` shows a "Tradewright" button when collapsed, both in `Tradewright_MailPanel.lua`; state in `mail.sidePanelExpanded`.

## Scope

- Chevron via `CreatePanelCollapseButton` instead of the close-style button
- Rail via `CreatePanelRail` instead of the "Tradewright" button
- Badge: characters with something to send (gold)
- Keep `mail.sidePanelExpanded` and the refresh of the review panel on unfold

## Status

Implemented; offline tests and lint pass. Not yet checked in game.

- `CreateMailPanelHeader` builds the dock: chevron instead of the close-style X; `BindMailPanelCollapse` and its "Tradewright" button are gone
- `RefreshMailPanel` and `OnMailFrameHide` show and hide through `ShowPanelDock`; the row filling moved to `fillMailRows`
- Rail badge: characters with a mail ready to attach (the same count that enables Attach all), with a tooltip
- The send queue refreshes the panel while folded too, so the rail count drops as mails go

## Acceptance criteria

- [ ] No X on the mail panel; folding and unfolding work as for the other panels
- [ ] State kept through `/reload` and reopening the mailbox
- [ ] Rail count matches the destination rows in the panel

## Verification

```bash
npm test
```

In game: open the mailbox, fold, unfold, `/reload`.

## Dependencies

- F148
