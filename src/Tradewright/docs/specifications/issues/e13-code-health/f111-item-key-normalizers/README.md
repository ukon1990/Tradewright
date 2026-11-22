# F111 — One item key and snapshot normalizer

## Summary

Make `Tradewright_ForeverLogic.lua` the only place that turns an item key or an auction snapshot into its stored form, with tests that pin the stored formats before anything changes.

## Context

- Item keys are serialized in `Tradewright_Auction.lua SerializeAuctionItemKeyFields` (`"id:"` for a plain item, `"id:0:0:0"` for all-zero fields; session state only) and `ForeverLogic.SerializeItemKey` (`"id"`; stored). F106 documents the mismatch with a test.
- Snapshot fields are normalized in `ForeverLogic.NormalizeMarketSnapshotFields`, again in `auctionSnapshot*` helpers and the fallback of `NormalizeAuctionSnapshotEntry` in `Tradewright_Auction.lua`, and the "`p` or `marketLow` or `minBuyout` or `price`" pick is repeated in `BuildCompactAuctionSnapshotEntry`.
- The price freshness window is computed inline in `GetItemEconomySummary` and `ItemTooltip.lua` although `GetAuctionPriceFreshnessWindowSeconds` exists.
- Stored keys live in SavedVariables. Changing their format without a migration loses the player's price history.

## Scope

- Characterization tests first: current output of both serializers and all normalizers for plain items, items with bonus ids, battle pets, commodities, old long-key and new short-key snapshots
- One serializer and one normalizer in ForeverLogic; `Tradewright_Auction.lua` calls them
- Stored keys already use the ForeverLogic format; no migration is expected unless the characterization tests show otherwise. If one is needed, it goes in `RepairAuctionStorageKeys` with its own test (old saved table in → new saved table out, nothing lost)
- Use `GetAuctionPriceFreshnessWindowSeconds` everywhere

## Acceptance criteria

- [ ] One item-key serializer and one snapshot normalizer in the codebase
- [ ] Tests pin the stored formats; an existing SavedVariables file still loads its prices
- [ ] Lint baseline shrinks; `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever with an existing SavedVariables file: Market tab and tooltips show the same prices as before the change; a full AH dump adds to the history instead of starting a new one.

## Dependencies

- F106

## Out of scope

- Splitting `Tradewright_Auction.lua` (F116)
