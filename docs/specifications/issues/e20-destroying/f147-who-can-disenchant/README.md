# F147 — Who can disenchant an owned item

## Summary

The Owned view's side pane says which of the player's characters can disenchant the item: those with Enchanting, with their skill. A soulbound item can only be disenchanted by the character holding it.

## Context

- Characters' professions and skill levels are saved by the profession scan (`db.characters[key].professions[skillLineID].skillLevel`).
- Design: "Tradewright Screens" canvas, Owned view.

## Scope

- `Tradewright:GetEnchanters()`: `{ { characterKey, name, skillLevel } }`, highest skill first
- Side pane line "Who can disenchant it": the enchanters, or for soulbound items whether the holder can

## Status

Implemented; offline tests and lint pass. Not yet checked in game.

- `Tradewright:GetEnchanters()` in `Tradewright_SalvageHoldings.lua`
- Owned side pane, "Who can disenchant it": a soulbound stack names its holder's Enchanting skill or says they lack it; any other stack lists every enchanter with skill

## Acceptance criteria

- [ ] Soulbound item held by a character without Enchanting says so
- [ ] Tradeable item lists every enchanter with skill
- [ ] Offline test for the enchanter list

## Verification

```bash
npm test
```

## Dependencies

- F143

## Out of scope

- The skill an item needs (not researched yet); mailing items to the enchanter
