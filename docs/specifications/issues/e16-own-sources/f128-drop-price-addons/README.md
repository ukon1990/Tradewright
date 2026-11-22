# F128 — Drop the price addons

## Summary

Prices come from the pack's own auction scans only. The TradeSkillMaster and Auctionator fallbacks, their settings and their mentions are removed.

## Context

- `Tradewright_Integrations.lua` holds both adapters; `GetMarketEstimateCopper` tries own scan, then TSM, then Auctionator. `Tradewright_MaterialCost.lua` has the same chain for materials and reads TSM's sale rate.
- `Tradewright_MarketInsights.lua` can use TSM's `dbmarket` as the Deals reference.
- Settings offer TSM price strings and an Auctionator switch; help text names both.

## Scope

- Delete the adapters and every read of `TSM_API` and `Auctionator`
- Market and material price: own scan or snapshot only
- Sale-rate column, tooltip line and setting: removed until F42
- Deals reference: own usual price or 7-day average
- Remove the settings, defaults and help text; saved keys of old settings are ignored
- Remove `TradeSkillMaster, Auctionator` from `OptionalDeps` in all TOCs, the globals from `.luacheckrc`, and update `AGENTS.md`

## Status

Implemented, in-game check pending.

## Acceptance criteria

- [ ] `grep -r "TSM\|Auctionator" src --include=*.lua --include=*.toc` finds nothing
- [ ] An unscanned item shows no price and no error
- [ ] Settings show no price-source options
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In-game: Crafts tab and craft queue show prices after a full scan; Settings has no TSM or Auctionator rows.

## Dependencies

- None

## Out of scope

- An own sale rate (F42)
