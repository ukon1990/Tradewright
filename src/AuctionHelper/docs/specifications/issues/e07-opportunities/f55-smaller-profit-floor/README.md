# F55 — Smaller profit floor

## Summary

Let a low-level character see small flips. The "Smallest profit worth showing" setting gets options under 1g, and its default drops from 5g to 1g.

## Context

- `GetFlipOptions` (`AuctionHelper_Opportunities.lua`) reads `opportunities.minProfitGold` (default 5) and multiplies it by 10,000. The setting is in whole gold, so it cannot hold 50s.
- Settings → Opportunities offers 1g, 5g, 10g, 25g and 50g (`AuctionHelper_SettingsTab.lua`, `opportunitiesSection`).
- On Forever, a level-35 character's whole wealth can be around 10g, so a 5g floor hides everything. `FlipLogic` already takes `minProfit` in copper (default 50000 in `DEFAULTS`).

## Scope

- New setting `opportunities.minProfitCopper` (copper, default 10000 = 1g). Options: 10s, 25s, 50s, 1g, 5g, 10g, 25g, 50g, shown with `FormatCopperShort`.
- Migration: when `opportunities.minProfitGold` is set and the new key is not, use `minProfitGold × 10000` once. Leave the old key in place.
- `FlipLogic` `DEFAULTS.minProfit` becomes 10000, matching the setting.
- Stats/footer text that mentions the floor uses the same copper value.

## Status

Implemented:

- Setting `opportunities.minProfitCopper` (default 1g) with options 10s, 25s, 50s, 1g, 5g, 10g, 25g, 50g; plain labels from `moneyChoices` in `AuctionHelper_SettingsTab.lua`
- `GetFlipOptions` reads the copper key; `FlipLogic` default is 10000
- `migrateMinProfit` in `AuctionHelper_DataInit.lua` copies an old `minProfitGold` choice once at load

No stats or footer text names the floor yet, so nothing else changed.

## Acceptance criteria

- [ ] With 25s selected, a flip worth 30s shows and one worth 20s does not
- [ ] A player who had picked 10g keeps 10g after the update
- [ ] A fresh install starts at 1g
- [ ] Changing the setting re-filters the list without a reload
- [x] Offline test: the profit floor at a copper value under 1g
- [x] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: Settings → Opportunities → 25s → Opportunities → Flips shows small rows; `/reload` keeps the choice.

## Dependencies

- F50

## Out of scope

- A floor scaled automatically from the character's gold or level (candidate)
- Changing the price-gap cost cap or the sure-things minimum gain
