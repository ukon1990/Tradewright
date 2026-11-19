# F01 — Agent harness (AGENTS + tests)

## Summary

Add QuestPlanner-style `AGENTS.md`, `.agents` / `.claude` skills, Forever pure helpers, and offline Lua 5.1 tests so Forever work can be reviewed and verified without the client.

## Acceptance criteria

- [x] `AuctionHelper/AGENTS.md` documents product, modules, flags, verify
- [x] Skills: `wow-addon-dev`, `wow-addon-issue-planning`, `wow-addon-issue-work` + focus files
- [x] `AuctionHelper_ForeverLogic.lua` + TOC entry
- [x] `python3 tests/run_tests.py` green

## Verification

```bash
cd AuctionHelper && python3 tests/run_tests.py
```
