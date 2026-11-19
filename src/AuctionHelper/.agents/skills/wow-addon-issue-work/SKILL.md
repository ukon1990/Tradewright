---
name: wow-addon-issue-work
description: Implement an AuctionHelper issue from docs/specifications/issues — plan slices, implement, review against focus files, verify with tests and in-game checks.
---

# Issue work (AuctionHelper)

**Start with:** [wow-addon-issue-planning](../wow-addon-issue-planning/SKILL.md) when filing follow-ups.

## Roles

| Role | Responsibility |
| --- | --- |
| Orchestrator | Load issue, split work, confirm, integrate |
| Workers | Implement one slice |
| Reviewers | Pass/fail using focus files |

## Golden rules

1. Stay inside acceptance criteria; file follow-ups for out-of-scope finds (after confirm).
2. No surprise commits — commit only when the user asks.
3. Review against `focus/code-quality.md`, `focus/lua-wow.md`, `focus/auction-forever.md`.
4. Verify before done.

## Verify

```bash
cd AuctionHelper && python3 tests/run_tests.py
```

In-game checklist (as applicable):

- All five AuctionHelper* modules enabled; no load errors
- `/auctionhelper` opens the dashboard
- Full AH dump with house open → prices in snapshot / crafts
- Profession Scan → recipes + reagents stored
- Crafts tab shows profit from AH snapshot
- Crafting orders / commodity buy stay quiet when APIs missing
