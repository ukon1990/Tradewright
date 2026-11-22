# F137 — Researched starting yields

## Summary

Yields looked up on the web ship with the addon, so disenchanting, prospecting and milling have a value before the player has records of their own.

## Context

- Published yield tables conflict with each other, and none is known for Forever's own content.
- Research in this repo follows the source standards: primary data first, sources audited, every claim tiered.
- Retail yields depend on skill and profession talents, so shipped retail numbers are rough by nature.

## Scope

- Research note in `docs/research/`: classic-era disenchant tables and the prospecting ores that exist on Forever; retail disenchant, prospecting and milling yields per expansion. Conflicts between sources are written down, and each table gets a tier
- New `src/Tradewright/src/data/Tradewright_SalvageData.lua` in the shape of F135, with the tier kept per table so the UI can mark weak numbers
- Confirm with the user which expansions' ores and gear exist on Forever before the tables are cut down to it

## Status

Done. Research note: [salvage yields](../../../../research/salvage-yields.md).

- Rule from the user: nothing is taken from another addon; reference wikis and published counts of outcomes are fine
- Shipped for Forever in `Tradewright_SalvageData.lua`: the reference wikis' classic disenchant table (confirmed by one counted data set) and Wowpedia's classic prospecting table (agreed with other sources for copper only; thorium is contradictory)
- Read through `Tradewright:GetSalvageYield(action, input)`
- Retail ships nothing (decided by the user): the only numbers found are other addons' tables. Retail values come from counted outcomes (F136)

Differs from the scope:

- No tier per table in the data file: every researched yield is shown as an estimate, and the note carries the tiers
- Forever has classic items only (confirmed by the user), so no tables beyond classic

## Acceptance criteria

- [x] Every shipped table names its source and tier in the research note
- [x] With no own records, a classic green item and a classic ore have a researched yield on Forever (offline test; the value shows with F138)
- [x] Own records with enough casts replace the shipped numbers (F135's order of trust)
- [x] New file in all four TOCs
- Dropped: researched yields for retail

## Verification

```bash
npm test
```

## Dependencies

- F135

## Out of scope

- Copying a table whole from another addon
- Yields per talent build
