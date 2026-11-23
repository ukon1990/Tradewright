# F139 — Get started steps and Full scan as the main button

## Summary

A player with no prices is told in three short steps how to fill Tradewright with data, and the Full scan button stands out whenever pressing it is the useful thing to do.

Design: [Tradewright Screens](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5), section "Getting started and Full scan as the main button".

## Context

- Today a new player gets one chat line at login (`Tradewright_Events.lua`), separate hints in each empty table, and the "Getting started" topic on the Docs tab. Nothing names the first step.
- A full scan is allowed every 15 minutes (`FULL_AH_DUMP_COOLDOWN_SEC` in `Tradewright_AuctionFullScan.lua`). `GetLastFullAuctionScanAt()` says when the last one ran.
- Usual prices, deals and Opportunities need scans on 5 different days. Daily price history (`auction.history.daily`) holds one entry per item and finished day; today's scans are rolled up tomorrow.
- The Full scan button (`panel.btnDumpFull`) is drawn like every other button. F133 locks its hover highlight while stale prices wait (`refreshAuctionPanelScanButtons` in `Tradewright_AuctionPanelRefresh.lua`); that is easy to miss.
- `Tradewright_UIShell.lua` is 680 lines, close to the 700 limit: the window goes in a file of its own.

## Scope

- Pure helpers (`src/Tradewright/src/util/`):
  - New `Tradewright_StartLogic.lua`: `Progress({ hasFullScan, hasProfessionScan, scanDays })` returns the three steps in order, each with `done`, the count of done steps and the index of the next open step (nil when all are done). Step 3 is done at 5 scan days.
  - `AuctionLogic.FullScanStandsOut({ active, cooldown, lastFullScanAt, now, waiting })` is true when a full scan can start now and prices are missing, older than an hour, or waiting for a full scan (F133).
- Get started window (`Tradewright_UI`, new file `Tradewright_GetStarted.lua`), a small frame over the dashboard:
  - Three rows, one title and one short line each:
    1. "Go to an auction house and press Full scan" / "Prices every item at once. Can be run every 15 minutes." (the time comes from the cooldown constant)
    2. "Open each profession and press Scan" / "Saves your recipes, for craft profit."
    3. "Full scan again on later days" / "Deals and usual prices need 5 scan days." with the count "N of 5": the different days with saved prices, today included once a full scan ran today (`GetScanDayCount` in `Tradewright_PriceHistory.lua`).
  - Done steps show as done; the next open step is marked.
  - Opens by itself until the player has closed it once, also for a player who already has every step done: it is the introduction too. "Got it" or the close button saves the setting `general.getStartedSeen`, and it does not open by itself again.
- Dashboard header: a small "Get started N/3" button while steps remain. It opens the window. Once all three steps are done it is hidden for good (setting `general.getStartedDone`).
- Auction house panel:
  - Full scan is drawn in a solid gold style while `FullScanStandsOut` is true, and as a plain button otherwise. This replaces the locked hover highlight. The tooltip line with the count of waiting prices stays.
  - While there has never been a full scan: one line under the scan row, "No prices yet. Press Full scan." / "Keep the auction house open until it ends." It goes away when a full scan starts.
- `/tw intro` opens the window; `/tw intro reset` makes it open by itself again (for testing).
- Solid gold button style as an option of `CreateButton` (`Tradewright_Widgets.lua`), used for Full scan and "Got it".
- Login chat line: until the first full scan, "No prices yet. Open the auction house and press Full scan." in place of the usual loaded line.
- All new text as `L["..."]`, translation files updated. New file added to all four TOCs of its addon.

## Acceptance criteria

- [ ] New character data, first `/tw`: the Get started window opens over the dashboard with step 1 marked as next
- [ ] A player with every step done who has never closed the window: it opens once, with all three steps done
- [ ] After "Got it" the window does not open by itself again, also after `/reload`
- [ ] The header button shows "Get started N/3" while steps remain and opens the window; it is gone when all steps are done
- [ ] Steps tick off from saved data: a full scan exists, a profession is scanned, 5 scan days reached
- [ ] Auction house, no full scan yet: the line under the scan row shows and Full scan is solid gold
- [ ] Full scan running or on cooldown, or ready with prices under an hour old and none waiting: Full scan is plain
- [ ] Full scan ready and prices older than an hour: Full scan is solid gold
- [ ] Nothing starts a full scan except the player's click
- [x] Offline tests of `Progress` and `FullScanStandsOut`
- [x] `npm test` passes; no lint debt grows

## Verification

```bash
npm test
```

In-game on Forever (new `.lua` files: restart the client):

1. With saved data moved away, log in → the chat line names the full scan. `/tw` → the Get started window opens.
2. Press "Got it", `/reload`, `/tw` → the window stays closed; the header button reads "Get started 0/3" and opens it.
3. Open the auction house → the line under the scan row shows; Full scan is solid gold.
4. Run the full scan → the line goes away; the button is plain and counts down. The header button reads "Get started 1/3".
5. Scan a profession → "Get started 2/3".
6. More than an hour later, open the auction house → Full scan is solid gold again.

## Dependencies

- F133 (the count of prices waiting for a full scan)

## Out of scope

- Starting a full scan automatically
- A guided tour of the tabs
- Changing the empty-table hints or the Docs tab
