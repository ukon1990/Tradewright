# F110 — Lookup tables instead of if-chains

## Summary

Turn long if-chains that map a name to an action or a value into tables. A reader sees every case at once, and adding a case is one line.

## Context

- `Tradewright_Events.lua`: about 35 handlers are `if self.X then self:X(...) end` forwarders, and a separate hand-kept list registers the same events. One `EVENT_HANDLERS = { EVENT = "MethodName" }` can drive both (about 200 lines fewer). `safeRegisterEvent`'s return value is unused.
- `Tradewright_Data.lua`: `Export` (complexity 60) builds `scopeLabel` from a 17-way `or` chain; `HandleSettingsSlash` (27) and `HandleAuctionSlash` (23) are subcommand chains, while the debug subcommands already use a dispatch table.
- `Tradewright_Util.lua IsItemLikelyTradeableOnAuctionByStaticInfo` (complexity 27): nine bind-type checks; names `E`, `bt`.
- `Tradewright_Auction.lua FinishQueuedAuctionRefreshItem`: the source counter if/elseif.
- `Tradewright_Theme.lua applyButtonState`: state → colours.
- `GoldDashboard` and `OverviewTab:RefreshStats`: `stats[1..5]` with the meaning in comments; 44 uses of `stats[N]` across the UI.

## Scope

- Convert each of the above; rename `E` / `bt` to `bindTypes` / `bindType`
- Named keys for the stats slots (`stats.gold`, `stats.deals`, …)
- Dispatch skips a handler whose method is nil: the method may live in an optional module (Bags) or a retail-only file. Test: registration matches the table exactly, and an event whose method is missing is a no-op; the bind-type table classifies each `Enum.ItemBind` value as before; each slash subcommand reaches its handler (with a fake `pe`)

## Acceptance criteria

- [x] Events: one table drives registration and dispatch; no forwarder functions remain
- [x] The two slash handlers and the bind-type check are under complexity 10; `Export`'s scope label comes from a table and its baseline entry shrinks
- [x] No `stats[<number>]` in the UI
- [x] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game: every `/ah` subcommand from `/ah help` still works; bags, AH, mail and profession events still update the UI.

## Dependencies

- F105, F106 (both touch `HandleAuctionSlash`)

## Out of scope

- Moving the slash commands to their own file (F116)
