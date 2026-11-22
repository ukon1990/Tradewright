# F24 — Review what the surplus mail sends

## Summary

Clicking the "Surplus to <seller>" row in the mailbox panel docks a review panel to its right: every item, with keep amounts edited in the row, a one-visit skip, and Send. It replaces the Keep… window from F23. Design: board `MailReview` on the "Tradewright Screens" canvas.

## Context

- F23's `ForeverLogic.BuildSurplusPlan(bagItems, keep, held, sendOthers)` and `BuildMailKeepRows` already know bags, keep and held. The Keep… window only edits keeps through a prompt and never shows what will be sent or why.
- `Tradewright_MailPanel.lua` is near its limits (`EnsureMailPanel`, `RefreshMailPanel` are baseline offenders), so the panel lives in its own file and those functions must not grow.

## Scope

- `MailLogic.BuildReviewRows(bagItems, keep, held, sendOthers, skip)` (new pure `Tradewright_MailLogic.lua`; `BuildSurplusPlan` moves there too): one row per sellable, non-trash bag item plus kept items not in the bags, each `{ itemID, name, bags, held, keep, send, reason }` with `reason` = `held` | `kept` | `skipped` | `othersOff` | nil (sends). `BuildSurplusPlan` is derived from it.
- Skip this visit: in-memory set, cleared when the mailbox closes; skipped items leave the surplus row and Send all too.
- `Tradewright_MailReviewPanel.lua`, docked right of the mail panel:
  - header "Surplus to <seller>", items and mail count
  - search box, Sending / Kept / All filter
  - table: tick, Item, Bags, Held, Keep (edit box), Send, Worth; rows grouped by item class; rows that send nothing are greyed with their reason
  - Keep box: type a number, mouse wheel = one stack, Shift-click = keep all, Ctrl-click = keep none; tooltip shows the arithmetic
  - footer: to send, skipped, total worth
  - **Clear keeps** (confirm), **Keep current bags**, **Send N items** (surplus parcel only)
- Mail panel: the Keep… button goes away; a click on the surplus row toggles the review panel and highlights the row.
- Remove `Tradewright_MailKeepWindow.lua` (all four TOCs; full client restart).

## Acceptance criteria

- [x] The panel's Send total always equals the surplus row and what is mailed
- [x] Changing Keep updates the row, surplus row and footer at once and survives `/reload`
- [x] Unticking skips an item for this send only; it is back next mailbox visit
- [x] Held items are never sent
- [x] On the seller, or with no seller set, there is no surplus row and no review panel
- [x] Offline tests cover each reason, skip, keep above/below bags, held above bags, kept-not-in-bags, and `BuildSurplusPlan` agreeing with the rows
- [x] `npm test` passes without growing lint debt

## Verification

```bash
npm test
```

In-game on a crafter: open the mailbox → click the surplus row → set Keep on one item with typing and the mouse wheel → untick another → Send N items → kept and unticked items stay in the bags; close and reopen the mailbox → the unticked item is back.

## Dependencies

- F23 (keep amounts and surplus)

## Out of scope

- Reviewing the materials and crafted-items rows
- Bank counts
- Per-item "always send" when "Send other sellable items" is off
- Stack-based keep amounts
