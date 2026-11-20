# F58 — How this page works, and why a list is empty

## Summary

Explain the Opportunities tab where the player is looking. With no row selected, the side pane says what the current list is, where its numbers come from and what the player has to do. An empty list shows which rule removed the items, step by step, and which setting to loosen.

## Context

- With no row selected, the side pane only says "Select a row" (`AuctionHelper_OpportunitiesTab.lua`, `buildDetail`). That space is unused.
- Each view in `AuctionHelper_OpportunityViews.lua` has one fixed `emptyTitle` / `emptyHint`. Flips says "Scan the auction house on a few different days to build usual prices." even when the history is complete and only the profit floor removed everything.
- `flipCandidates` and `FlipLogic.BuildFlipRow` apply the rules in a fixed order: has a usual price → has sells a day → discount → sells often enough → quantity → profit floor. The counts of each step are not kept.
- `OpportunityViews.lua` is 413 lines; new help text may need its own file to keep under 700.

## Scope

- `FlipLogic.BuildFlipRows` also returns a funnel: `{ scanned, withUsual, withSells, underUsual, sellEnough, worthIt }`. The existing rows come out unchanged. Same for gaps (`scanned, withSteps, gap, sellEnough, affordable, worthIt`), sure things (`scanned, vendorKnown, underVendor`) and sell now (`owned, withUsual, aboveUsual`).
- Empty state of each list: the funnel as lines, for example
  "7,071 items in the last scan / 312 have a usual price / 40 are 25%+ under it / 3 sell 1+ a day / 0 make 1g or more". The first step that drops to 0 is highlighted, with a hint naming the fix ("Lower 'Smallest profit worth showing' in Settings" or "Scan on more days").
- Side pane with no row selected: "How this list works" for the active view.
  - What the list is (one sentence)
  - Where the numbers come from: usual price = middle price of daily scans over the window, 5 days needed; sells a day = drops in listed quantity between scans; profit after the cut
  - What to do: scan with the auction house open, on different days, and twice within a day for sales; today counts from tomorrow
  - The settings that change the list, with a "Settings" button that opens the Opportunities group
- Help text for each view lives with the view definition (`help = { … }`) in a new `AuctionHelper_OpportunityHelp.lua` (all four UI TOCs).
- Docs tab: an Opportunities page with the same text, longer, linked from the side pane.

## Status

Implemented:

- `FlipLogic.BuildFlipRow` returns the reason it drops an item ("discount", "sells", "profit"); `BuildFlipRows(items, opts, drops)` counts them; `FlipLogic.FlipFunnel` and `FlipLogic.FirstEmptyStep`
- Every list's `getRows` returns `rows, insights, funnel`. Flips: scanned, usual price, sales estimate, under usual, sells enough, profit. Sure things: scanned, vendor price known, under it, gain 10s+. Price gaps: scanned, price steps, usual price and sales, gap that fits. Sell now: owned, in the last scan, usual price and sales, 10%+ above usual. A list turned off in Settings says so.
- `AuctionHelper_OpportunityHelp.lua` (new, all four UI TOCs): step labels, fixes and "How … work" text per list; `GetOpportunityEmptyText`, `GetOpportunityHelp`, `WarningText`
- Empty list: steps down to the first that kept nothing (warning colour), then its fix, naming the setting
- Side pane with no row selected: "How … work" for the active list
- Docs tab: "Opportunities" page

Not done: a "Settings" button in the side pane; the text names "Settings, Opportunities" instead.

## Acceptance criteria

- [ ] Flips empty because of the profit floor names the profit step and the setting, not "scan on more days"
- [ ] Flips empty because no item has 5 days says how many days the best item has
- [ ] Each of the four lists shows its own "How this list works" with no row selected
- [ ] The funnel numbers add up: each step is at most the one before it
- [x] Offline tests: flip drop reasons, flip funnel, first empty step (the other lists' counts are plain loops in the WoW-side code)
- [x] `npm test` passes; no file over 700 lines

## Verification

```bash
npm test
```

In-game on Forever (restart the client: new file): Opportunities → each list with no row selected shows its help → set the profit floor to 50g → Flips empty state points at that setting.

## Dependencies

- F50 to F54; F55 for the setting names; F56 for the day counts

## Out of scope

- An interactive tutorial or first-run walkthrough
- Help text for other tabs
