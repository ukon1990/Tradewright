# F106 — Bugs found by the audit

## Summary

Fix the defects the audit found, each with a regression test where the logic can run offline, without growing any baselined function.

## Context

- `HandleAuctionSlash` (`Tradewright_Data.lua`, around line 2439) prints "Auction dump completed" right after starting the dump, which runs asynchronously. It also prints it when `StartAuctionDump` refuses to start (a dump is already running, or the full dump is on cooldown). The `refresh crafts` branch queues work (`QueueCraftEconomyAuctionRefresh`) but prints nothing, unlike `refresh`.
- `TryBuyAuctionCartRow` (`Tradewright_Auction.lua`, around 2372) calls `C_AuctionHouse.StartCommoditiesPurchase` / `ConfirmCommoditiesPurchase` with no `IS_RETAIL` check; only an API-presence check and a hidden button guard it. Forever may expose the same function, so the API check is not enough: `focus/auction-forever.md` forbids commodity purchase calls on Forever.
- Two item key serializers disagree: `SerializeAuctionItemKeyFields` (`Tradewright_Auction.lua`, around 327) writes `"id:"` for a plain item and `"id:0:0:0"` for all-zero fields; `ForeverLogic.SerializeItemKey` writes `"id"` for both. This is a latent inconsistency, not a live bug: Auction's keys stay in session state (search targets, dedupe, grouping), ForeverLogic's are stored. F111 unifies them.
- `now()` is `time()` in `Tradewright_Auction.lua` but `GetServerTime()` in `Tradewright_MarketInsights.lua`, so snapshot `seenAt` and the insights deal window use different clocks.

## Scope

- Move the dump branch into a new `RunAuctionDumpSlash`: "started" when the dump starts, "completed" from the dump's finish path, the refusal reason when it does not start
- `refresh crafts` prints "Queued craft refresh."
- `IS_RETAIL` guard at the top of `TryBuyAuctionCartRow`
- One shared `pe:Now()` using server time, used by both files
- Add a test that documents the two serializer formats (F111 makes it one)

## Acceptance criteria

- [ ] `/ah auction dump` prints "completed" only after the dump ends; no "started" or "completed" line when the dump refuses to start
- [ ] On Forever no commodity purchase API is called, even if the cart's buy handler is invoked directly
- [ ] One clock across AuctionData
- [ ] No baselined function grows; `HandleAuctionSlash`'s baseline entry shrinks
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: `/ah auction dump` with the AH open → "started", later "completed"; run it again at once → a refusal reason, no "completed". The cart has no buy button.

## Dependencies

- F105

## Out of scope

- Unifying the item key serializers and snapshot normalizers (F111)
