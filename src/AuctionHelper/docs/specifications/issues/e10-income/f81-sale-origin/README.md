# F81 — Where each sold item came from

## Summary

Each auction sale is labelled crafted, resold, farmed or unknown, from what the account did with that item before the sale. Crafts are written to the ledger so the label has something to match.

## Context

- No craft is recorded anywhere. Retail fires `TRADE_SKILL_ITEM_CRAFTED_RESULT` (already routed to `OnProfessionRecipeCraftedResult`); on Forever the craft has to be seen from the craft cast succeeding (`UNIT_SPELLCAST_SUCCEEDED` for the player with a known recipe spell) and the made item arriving in the bags.
- Buys come from F44 (`kind = "buy"`). Looted items come from the loot messages F70 parses; this feature needs only "the account looted this item", not a farm run.
- Sales already recorded have item, quantity and time, enough to label them after the fact.

## Scope

- Ledger event `kind = "craft"`: item, quantity, recipe, time; on retail from the craft result, on Forever from the cast plus the item arriving
- Ledger event `kind = "loot"`: item and quantity from the player's own loot messages, with daily per-item totals instead of one event per pickup, so the ledger is not flooded
- `IncomeLogic.LabelSaleOrigins(events)` → for each sale, units by origin `{crafted, resold, farmed, unknown}`. Units are matched oldest first, per item, against crafts, buys and loot that came before the sale, so 10 crafted and 5 bought split the right way
- Labels are worked out when needed, never stored, so older sales get labels too
- Ledger size: craft and loot entries count towards the existing cap

## Acceptance criteria

- [ ] Crafting 5 of an item writes one `craft` event with quantity 5, on retail and on Forever
- [ ] Selling 5 of an item crafted earlier labels the sale crafted
- [ ] An item bought then sold is labelled resold (with F44); without F44, unknown
- [ ] An item looted then sold is labelled farmed
- [ ] A sale of 10 where 6 were crafted and 4 looted splits 6 / 4
- [ ] A sale with nothing before it is unknown
- [ ] Offline tests: oldest-first matching, split sales, items sold more often than they were made, no events

## Verification

```bash
npm test
```

In-game on Forever: craft 2 of an item, loot 2 of another, post and sell both → after taking the mail, `/dump` the labelled origins or check F82's split.

## Dependencies

- F44 for resold
- Shares loot-message parsing with F70 (either order works)

## Out of scope

- Items received by mail from alts count as unknown
- Profit per origin after material cost
