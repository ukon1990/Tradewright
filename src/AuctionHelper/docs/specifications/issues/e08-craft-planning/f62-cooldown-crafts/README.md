# F62 — Cooldown crafts

## Summary

Recipes with a cooldown show whether they are ready or how long is left, per character, and what one use is worth. The Crafts footer and an optional login line say when a cooldown craft is ready.

## Context

- The research's clearest finding on crafting: margins last where capacity is capped, and in a Classic-style game that means cooldown crafts (transmutes, Mooncloth and the like).
- Published cooldown lengths conflict between sources and nothing official exists for Forever, so lengths are read from the client and never assumed.
- No cooldown call exists in the pack. The profession scan (`AuctionHelper_Scan.lua`, `LiveUpdate.lua`) stores recipes per character under `db.characters[char].professions[...].recipes`.
- The game reports the time left on a recipe's cooldown while the profession window is open (`C_TradeSkillUI.GetRecipeCooldown`; the classic `GetTradeSkillCooldown` where that is absent). The addon can only know another character's cooldown from that character's last scan.
- Design: row text and footer in [Crafts](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5#artboard-GoldCrafts).

## Scope

- Profession scan and live update: for each learned recipe, ask the client for its cooldown; when it reports one, store `cooldownReadyAt` (server time) and `hasCooldown = true` on the recipe, capability-checked for both APIs
- `ForeverLogic.CooldownState(recipe, now)`, pure → `{state = "ready" | "waiting" | "none", secondsLeft}`
- `ForeverLogic.BestCooldownUse(recipes, profitFn)`: among recipes of one character that the client reports as sharing a cooldown, the most profitable one; when sharing cannot be told, each recipe stands alone
- Crafts row second line: "cooldown ready" or "cooldown in 1 day 4 hours"; `Make` is capped at 1 for a ready cooldown and 0 while waiting
- Crafts filter value "Cooldowns" in the profit-state filter
- Footer: "1 cooldown ready · next in 1 day 4 hours" across all characters
- Setting "Tell me when a cooldown craft is ready" (on): one chat line at login naming the recipe and character
- F60 reads `hasCooldown` to keep these recipes out of the craft branch

## Acceptance criteria

- [ ] Using a cooldown recipe and rescanning shows "cooldown in …" with the client's time
- [ ] The time counts down across `/reload` and a relog without a new scan
- [ ] Another character's cooldown shows from that character's last scan and flips to ready when its time passes
- [ ] A recipe without a cooldown shows nothing
- [ ] A client lacking both cooldown calls shows no cooldown text and no error
- [ ] Offline tests: ready, waiting, no cooldown, time in the past, best use among several

## Verification

```bash
npm test
```

In-game on Forever: open the profession window on an alchemist with a transmute → scan → Crafts shows the state → use the transmute → reopen the window → the row shows the time left.

## Dependencies

- None (F61 uses the cap; F60 uses the flag)

## Out of scope

- Assumed cooldown lengths for recipes not yet used
- Reminders while playing another character beyond the login line
- Gold per day across alts as a ranking
