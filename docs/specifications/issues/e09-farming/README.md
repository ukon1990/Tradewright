# E09 — Farming

## Summary

Measure what a farm really earns and use it to choose the next one. A farm window logs loot and coin while you play; saved farms are re-valued at today's prices so they can be compared now; and a "What to farm" list shows the materials that move the most gold, with where you have looted them before.

## Context

- Research and sources: [WoW gold making market strategies](../../../research/gold-making-market-strategies.md), section "Farming rates are unverified; a player's own log is the only evidence".
- Every gold-per-hour figure the research found is self-reported, and the highest ones come from sites that sell gold or boosting. The game exposes vendor prices and boss loot lists but no drop rates, and node databases hold positions without yields. A player's own log is the only trustworthy source.
- Existing trackers (LootAppraiser, MoneyLooter) value loot at a listing-based price and so overstate what sells. This epic values an item at its usual price after the cut only when it shows turnover, and at vendor price otherwise.
- The addon tracks none of this today. The only general money signal is the wallet history fed by `PLAYER_MONEY`.
- Logging loot the player picks up is passive. Blizzard's rules forbid bots, input broadcasting and automation; nothing here moves the character or acts for the player.
- Design: [my farms](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldFarms), [what to farm](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldWhatToFarm), [farm window](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldFarmTracker).

## Scope

- F70: farm window and loot log
- F71: my farms, re-valued at today's prices
- F72: what to farm

## Acceptance criteria

- [ ] F70 to F72 done
- [ ] A farm's value always shows its three parts: coin, vendor items, auction estimate
- [ ] No gold-per-hour number ships with the addon; every figure comes from the player's own runs
- [ ] No drop table, node map or route ships with the addon
- [ ] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: Farming → Start farm → loot for a few minutes → Stop and save → the farm appears under My farms with a gold-an-hour figure → run a full scan → "Now" is re-valued.

## Dependencies

- E06 Market signals: F40 (usual price), F42 (sells a day), F43 (fees). Without them a farm is valued at vendor price and the latest lowest price.

## Out of scope

- Where items drop, node positions, routes on the map
- Instance lockout counters (candidate: the caps differ by client and none is sourced for Forever)
- Sharing or importing other players' farms
