# F70 — Farm window and loot log

## Summary

A small farm window records what you loot and the coin you pick up while a farm runs, and shows gold an hour at today's prices. Stopping it saves the run under a name.

## Context

- Nothing in the pack listens for loot. `Tradewright_Events.lua` feeds `PLAYER_MONEY` into the wallet history; mail, auction and vendor money also arrive through it, so a money delta alone is not farm income.
- The reference computation (LootAppraiser Reloaded): `per hour = value ÷ (now - start - paused seconds) × 3600`.
- Value rule for this addon: an item counts at `max(vendor price, usual price × (1 - cut))` when it has a sells-a-day estimate at or above a threshold, and at vendor price otherwise. The three parts (coin, vendor items, auction estimate) stay separate.
- UI rules from the design system: the header is the drag handle, position is saved per character, the window is clamped to the screen, Escape does not close a running farm.
- Design: [farm window, summary and tooltip](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldFarmTracker).

## Scope

- New module `Tradewright_Farm.lua` in `Tradewright_Inventory` and `Tradewright_FarmWindow.lua` in `Tradewright_UI`, listed in all four TOCs of each addon
- A run: `{name, zone, startedAt, pausedSeconds, coin, vendorSold, items = {[itemID] = qty}}`, kept in `TradewrightInventoryDB.farm.current` so it survives `/reload`
- While a farm runs:
  - loot messages for the player add to `items` (item ID from the link, quantity from the message)
  - looted-coin messages add to `coin`
  - gold received from a vendor between opening and closing a merchant adds to `vendorSold`, and items sold there leave `items`
  - mail, auction house and trade money is ignored
- Start, Pause, Stop: from the Farming tab, the window, and `/ah farm start|pause|stop`
- Automatic pause after standing still for N minutes (setting, default 5); the paused time is not counted
- `ForeverLogic.SummarizeFarmRun(run, priceFn, now)`, pure → `{coin, vendorValue, auctionValue, total, activeSeconds, perHour, byItem}` using the value rule above
- Farm window (250 wide): farm name and zone, elapsed time, gold an hour, looted so far, coin, vendor items, the three latest pickups, Pause and "Stop and save"; a one-line collapsed form showing time and gold an hour
- "Farm finished" dialog: name field (pre-filled with the zone or the farm it was started from), time, looted value, coin and vendor items, gold an hour, Save farm, Discard
- Item tooltip: "Vendor pays" and "You looted it in <farm>" lines
- Settings group "Farming": show the window while a farm runs, count rarely sold items at vendor price, pause when idle, start a farm on entering an instance (off)

## Status

Implemented:

- `Tradewright_FarmLogic.lua` (core, pure, offline-tested): `ActiveSeconds`, `ItemValue` (the value rule), `SummarizeRun`, `RemoveItems`
- `Tradewright_Farm.lua` (Inventory): the run in progress lives in `ledger.farm.current` and survives a reload. While a run is active and not paused:
  - the player's own loot messages add to the run's items
  - gold gained within a second of a looted-coin message counts as coin
  - gold gained with a merchant open counts as a vendor sale, and an item sold there leaves the run's items
  - all other gold (mail, auction house, trade, quests) is ignored
- `StartFarmRun(name)`, `ToggleFarmPause()`, `StopFarmRun()` (saves the run under its name into `ledger.farm.farms`), `SummarizeFarmRun(run)`
- `Tradewright_FarmWindow.lua` (UI): a 250 px movable window with the farm name, clock, gold an hour, the three value parts, the three latest pickups, Pause and "Stop and save"; its position is saved
- Slash command `/ahfarm` (toggle the window), `/ahfarm start [name]`, `/ahfarm pause`, `/ahfarm stop`
- Setting "Show the farm window when a farm starts"

Differs from the scope:

- **Its own slash command, `/ahfarm`,** instead of `/ah farm …`: the `/ah` command table sits in a file that is over the size limit
- **No "Farm finished" dialog.** Stop saves under the name the run was started with (default: the zone) and prints a chat line; Discard does not exist yet
- **No automatic pause when idle** and no start on entering an instance
- **No collapsed one-line form** of the window
- **Tooltip lines:** "Vendor pays" is on the item tooltip (with Shift; always, in orange, when a vendor pays more than the auction house after the cut). "You looted it in …" is not added
- **Vendor sales:** only items sold by using them from the bags with a merchant open are taken out of the run; items sold another way stay counted while their gold is also counted
- **Storage:** in the ledger table, not a new saved-variables key

## Acceptance criteria

- [ ] Looting 2 of an item during a run adds 2 to that item; the same loot with no run adds nothing
- [ ] Collecting auction mail or trading during a run does not change the run's coin
- [ ] Selling loot to a vendor moves its value from the auction estimate to vendor items, not counted twice
- [ ] Pause stops the clock; gold an hour does not fall while paused
- [ ] A `/reload` mid-run keeps the run and its clock
- [ ] An item with no sells-a-day estimate counts at vendor price
- [ ] The window position is saved per character and stays on screen
- [ ] Nothing moves, targets, loots or sells for the player
- [x] Offline tests of `SummarizeFarmRun`: value rule per item, paused time, zero active time, vendor sales, empty run

## Verification

```bash
npm test
```

In-game on Forever (restart the client: new files): `/ah farm start` → kill and loot for 5 minutes → window shows items and gold an hour → sell some loot to a vendor → Stop and save → the dialog's numbers match the window.

## Dependencies

- F40, F42, F43 for the value rule (falls back to vendor price and the lowest price without them)
- F80: read coin and vendor gold from its money listener instead of a second one; F81 shares the loot-message parsing

## Out of scope

- Group loot shares and loot rolled by others
- Skinning, gathering and fishing counted separately from other loot (all arrive as loot)
- Experience or reputation per hour
