# F105 — Conventions: maintainable by a human

## Summary

Write down the rule every other E13 feature follows: code must be maintainable by a human. Add clear rules for names and comments, and a review check that asks whether a developer new to the file could change it safely.

## Context

- Today `AGENTS.md` and the skills imply this only through KISS and the lint limits. Lint can pass while the code is still hard to follow: one-letter context tables (`c` in `CraftsEngine`), five names for one queue, `stats[1..5]` with the meaning in a comment.
- Feature and epic ids in comments (`-- ... (F55)`) tell a reader nothing about the code; the commit message and the issue file already carry them.
- `ProfessionExporter` is the addon object's historical name. A newcomer looks for an exporter that does not exist. Renaming it is out of scope for E13; explaining it is not.

## Scope

- `AGENTS.md`: first hard rule "Code must be maintainable by a human: a developer new to the file can read, understand and safely change it. Lint limits, names and comments serve this; passing lint is not enough." Plus one line each for names and comments, and a line explaining `ProfessionExporter`
- `focus/code-quality.md`:
  - opens with the same rule
  - new section **Naming**: descriptive names; single letters only for short loop indices and the established `pe` / `f` / `FL`; no abbreviations a reader must decode (`st`, `ev`, `ck`, `expSel`); one word per concept (item key, craft queue, full scan, AH price); named constants for magic numbers and timer delays
  - new section **Comments**: a comment explains why, a WoW API quirk, a Forever-vs-retail reason or a non-obvious invariant. No comments that restate the code, no feature or epic ids, no changelog notes ("like before the split"), no commented-out code. A label for a block inside a long function means the block wants to be a named function
  - new section **Tests**: meaningful tests only — behaviour that could break (math, selection, saved formats, Forever-vs-retail branches); no tests for getters or layout
- `wow-addon-issue-work/SKILL.md`: reviewers fail a change that a developer new to the file could not follow

## Acceptance criteria

- [ ] The rule opens both `AGENTS.md` hard rules and `focus/code-quality.md`
- [ ] Naming, Comments and Tests sections exist with concrete good and bad examples from this repo
- [ ] The reviewer role in `wow-addon-issue-work` checks human readability
- [ ] No change to `scripts/lint-baseline.json`
- [ ] `npm test` passes

## Verification

```bash
npm test
```

Read the new sections as someone new to the repo: each rule has a good and a bad example taken from this codebase.

## Dependencies

- None

## Out of scope

- Fixing existing names and comments (F108 and the split features do that)
- The lint check against feature ids in comments (F108 adds it after the sweep, so nothing is baselined)
- Renaming `ProfessionExporter` (F119)
