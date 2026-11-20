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

## Status

Implemented:

- `AuctionHelper_Cooldowns.lua` (Professions): while a profession window is open, the cooldown of every recipe of that profession is read from `C_TradeSkillUI.GetRecipeCooldown` (shortly after profession events) and stored per character as `db.characters[characterKey].recipeCooldowns[recipeID] = readyAt`. It listens on its own event frame and does not touch the scan code.
- `MaterialLogic.CooldownState` and `FormatCooldown` (pure, offline-tested)
- Crafts tab: an optional `Cooldown` column ("Ready", "1 day 4 hours", or empty) for the row's best crafter; `Make` is capped at 1 when ready and 0 while waiting
- F60 leaves recipes that any character has on record as a cooldown recipe out of the craft-cost index

Differs from the scope:

- **A recipe is known to have a cooldown only after the client has reported one for it.** A cooldown recipe that has never been on cooldown while the addon was watching shows nothing. The client reports no cooldown for a ready recipe, so the addon cannot tell "ready" from "has none" until then.
- **Only the modern profession API is read** (`GetAllRecipeIDs` and `GetRecipeCooldown`). The classic `GetTradeSkillCooldown` path is not implemented; on a client without the modern calls nothing is stored.
- **Shared cooldowns** (`BestCooldownUse`) are not handled: each recipe stands alone
- **Not done:** the row's second-line text, the "Cooldowns" filter value, the footer line and the login chat line. The first three sit in `AuctionHelper_CraftsUI.lua`, which is over the file-size limit.
- The stored key is the recipe ID the client lists; a craft row is matched on its recipe ID, then its spell ID. Whether these line up on Forever needs the in-game check.

## Acceptance criteria

- [ ] Using a cooldown recipe and rescanning shows "cooldown in …" with the client's time
- [ ] The time counts down across `/reload` and a relog without a new scan
- [ ] Another character's cooldown shows from that character's last scan and flips to ready when its time passes
- [ ] A recipe without a cooldown shows nothing
- [ ] A client lacking both cooldown calls shows no cooldown text and no error
- [x] Offline tests: ready, waiting, no cooldown, time in the past, time text, Make cap
- [ ] Best use among recipes that share a cooldown (not implemented)

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
