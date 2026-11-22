# E17 — Scan flow: the right scan at the right time

## Summary

A full scan is usually much faster than looking up many items one by one. Tradewright should run the slow item scan by itself only where it is needed (the items the player is selling) and point the player to the full scan for everything else.

## Context

- Opening the auction house queues every stale price for an item-by-item scan: bag items, craft items of all characters and account inventory (`OnAuctionHouseShow` in `Tradewright_AuctionEvents.lua`).
- The full scan has a server cooldown; the Full scan button and the panel footer already show it.
- The item scan is still needed to check for undercuts and while the full scan is on cooldown.

## Scope

- F133: suggest the full scan instead of a long item scan

## Acceptance criteria

- [ ] F133 done
- [ ] A full scan never starts without the player's click
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: open the auction house with a full scan ready and many stale prices → only bag items are scanned, the Full scan button is highlighted.

## Dependencies

- None

## Out of scope

- Time estimates for either scan (they depend on the server and the day)
- Starting a full scan automatically
