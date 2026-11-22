# F108 — Comment sweep

## Summary

Remove comments that add nothing, fix the ones that are wrong, and add the few that are missing — following the Comments rules of F105.

## Context

- About 50 comments cite feature or epic ids, mostly in file headers (`-- Farm window (E09 F70): ...`). Most are in `Tradewright_IncomeLogic.lua` (5), `Tradewright_OpportunityViews.lua` (3), and one or two in each Bags file and many UI files.
- Changelog notes: "like before the split" (`CraftsEngine`, around 1195), "Legacy … pre side-panel" (`CraftingOrdersMaterials`, around 815), "Belt-and-suspenders" (`CraftsEngine`, around 2454), `@param` lines that restate a signature.
- Stale: `Tradewright_Docs.lua` describes the export as `AHCBOR1` and never mentions `AHLUA1:`, which Forever uses. `Tradewright_MailPlans.lua` says its rules are in ForeverLogic; most are in `MailLogic`. `Tradewright_DataInit.lua` around 269 mixes a valid migration reason with "(F55)": keep the reason.
- Missing: the short SavedVariable keys in `Tradewright_ItemAnalytics.lua` (`c, s, l, n, x, o`, `b, k, w`) have no legend; `n` = min and `x` = max cannot be guessed. `Tradewright_ItemAnalytics.lua` has only 6 comments in 1331 lines.
- Indentation: `CraftsEngine` lines around 1105–1375 and `isPlaceholderItemLabel` in `CraftsUI` use spaces; the rest uses tabs.

## Scope

- Strip feature and epic ids from every Lua comment; keep the sentence when it says something
- Delete changelog and restating comments; fix the stale ones
- Add a key legend next to the SavedVariable compaction code; add a comment wherever a reader of `ItemAnalytics` would otherwise have to reverse-engineer a rule
- Retab the space-indented blocks
- After the sweep, `scripts/lint.py` fails on a Lua comment that cites a feature or epic id (`F\d+`, `E\d+` as a word), with a fixture that proves it

## Acceptance criteria

- [ ] No Lua comment cites a feature or epic id, and a new one fails `npm run lint`; the baseline gets no new entries
- [ ] `Docs.lua` describes the export format the addon actually writes
- [ ] The SavedVariable short keys are explained in one place
- [ ] No mixed indentation in the touched files
- [ ] `npm test` passes

## Verification

```bash
npm test
grep -rnE --include='*.lua' -- '--.*\b[FE][0-9]{2,3}\b' src
```

The grep prints nothing (except generated data).

## Dependencies

- F105

## Out of scope

- Section labels inside long functions: they go when the split features turn the blocks into named functions
