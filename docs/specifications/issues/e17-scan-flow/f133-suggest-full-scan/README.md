# F133 — Suggest the full scan instead of a long item scan

## Summary

When the auction house opens and a full scan is ready, Tradewright scans only the items in the player's bags by itself. The other stale prices (crafts, account inventory) wait, and the Full scan button is highlighted to show that one click updates them all. While the full scan is on cooldown, everything is scanned item by item, as today.

## Context

- `OnAuctionHouseShow` (`Tradewright_AuctionEvents.lua`) calls `BuildPrioritizedAuctionAutoScanTargets` with bags, crafts and account inventory together, and queues them all.
- `BuildPrioritizedAuctionAutoScanTargets` (`Tradewright_AuctionScanTargets.lua`) already takes `includeVisibleBags`, `includeCrafts` and `includeAccountInventory`, so the two groups can be built with two calls. It is 74 lines long and frozen in `scripts/lint-baseline.json`: it may not grow.
- Two groups of targets:
  - **selling**: the bag items the sell panel shows (`BuildAuctionVisibleItemIDs`). Few items, and the player needs their prices right away to see undercuts.
  - **bulk**: craft items and account inventory. Many items; a full scan covers them all.
- `GetFullAuctionDumpCooldownRemaining()` says whether a full scan is ready. `refreshAuctionPanelScanButtons` and `RefreshFullScanCountdown` (`Tradewright_AuctionPanelRefresh.lua`) already update the Full scan button while the cooldown runs.
- Starting a full scan already clears the item queue (`StopAuctionScanForDump`). After it, the bulk prices are inside the one-hour freshness window, so they are no longer stale.
- The panel is small: no new text in it. The detail goes in the button's tooltip.

## Scope

- Pure helper in `Tradewright_AuctionLogic.lua`: `PlanScanOnOpen({ fullScanReady, suggestFullScan, staleBulkCount })` returns `{ queueBulk, highlightFullScan }`.
  - Full scan on cooldown, or the setting off → `queueBulk = true`, no highlight.
  - Full scan ready and `staleBulkCount` at or below the limit (constant, start at 20) → `queueBulk = true`, no highlight: a short item scan is quick on any server.
  - Full scan ready and `staleBulkCount` above the limit → `queueBulk = false`, `highlightFullScan = true`.
- `OnAuctionHouseShow`: build the selling targets and the bulk targets separately, always queue the selling targets, queue the bulk targets only when the plan says so. Keep the count of waiting bulk targets in session state for the panel.
- Full scan button: highlighted (glow or accent colour from the existing button style) while bulk targets are waiting and the full scan is ready. The highlight goes away when a full scan starts, when the bulk targets are scanned another way, or when the auction house closes.
- Tooltip of the highlighted button, one added line with the count: "%d prices are older than an hour. A full scan updates them all at once." Written as `L["..."]`, with the translation files updated.
- The existing Scan button and its scan choice are unchanged: they remain the way to scan the waiting items one by one.
- Setting `auction.suggestFullScan` (default on) in `Tradewright_DataInit.lua`, with a switch beside the other auction settings: "Suggest a full scan when one is ready". Off = today's behaviour.
- If the split needs changes inside `BuildPrioritizedAuctionAutoScanTargets`, extract helpers so the function shrinks; then run `npm run lint:baseline`.

## Acceptance criteria

- [ ] Full scan ready, more than 20 stale bulk prices: only bag items are scanned on opening; the Full scan button is highlighted
- [ ] The tooltip of the highlighted button shows how many prices are waiting
- [ ] Full scan ready, 20 or fewer stale bulk prices: all are scanned item by item, no highlight
- [ ] Full scan on cooldown: all stale prices are scanned item by item, as before
- [ ] After a full scan the highlight is gone and no item scan of the bulk targets starts
- [ ] Setting off: behaviour as before this feature
- [ ] No new text in the panel itself; nothing starts a full scan except the player's click
- [x] Offline test of `PlanScanOnOpen` for the four cases above
- [x] `npm test` passes; no lint debt grows

## Verification

```bash
npm test
```

In-game on Forever:

1. With a full scan ready and prices older than an hour, open the auction house → the progress row counts only bag items; the Full scan button is highlighted.
2. Hover the button → the tooltip names the number of waiting prices.
3. Click Full scan → the highlight goes away; after the scan no item scan starts.
4. Close and reopen the auction house (full scan now on cooldown, prices fresh) → no highlight.
5. Wait until prices are stale while the cooldown still runs, reopen → everything is scanned item by item.
6. Turn the setting off, reopen with a full scan ready → everything is scanned item by item, no highlight.

## Dependencies

- None

## Out of scope

- Time estimates for either scan
- Starting a full scan automatically
- Scanning the player's own listed auctions for undercuts when the item is no longer in the bags (candidate F134)
