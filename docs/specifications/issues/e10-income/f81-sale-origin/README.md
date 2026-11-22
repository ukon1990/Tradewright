# F81 — Where each sold item came from

## Summary

Each auction sale is labelled crafted, resold, farmed or unknown, from what the account did with that item before the sale. Crafts are written to the ledger so the label has something to match.

## Context

- No craft is recorded anywhere. Retail fires `TRADE_SKILL_ITEM_CRAFTED_RESULT` (already routed to `OnProfessionRecipeCraftedResult`); on Forever the craft has to be seen from the craft cast succeeding (`UNIT_SPELLCAST_SUCCEEDED` for the player with a known recipe spell) and the made item arriving in the bags.
- Buys come from F44 (`kind = "buy"`). Looted items come from the loot messages F70 parses; this feature needs only "the account looted this item", not a farm run.
- Sales already recorded have item, quantity and time, enough to label them after the fact.

## Scope

- Crafts and loot are read from the player's own item chat lines (`CHAT_MSG_LOOT` with `LOOT_ITEM_CREATED_SELF[_MULTIPLE]` and `LOOT_ITEM_SELF[_MULTIPLE]`, turned into patterns with `IncomeLogic.FormatToPattern`, so every client language works). This works the same on retail and Forever; the recipe is not known from the line and is not stored
- Stored apart from the ledger events, so loot never crowds sales out of the 2,500-event cap: `ledger.acquired[itemID][day] = { craft = n, loot = n }`, account-wide (items move between characters by mail before they are sold), days older than 400 dropped at login
- `IncomeLogic.LabelSaleOrigins(events, acquired)` → for each sale, units by origin `{crafted, resold, farmed, unknown}`. Units are matched oldest first, per item, against crafts, loot and buys (F44 `kind = "buy"` events) from the sale's day or earlier, so 10 crafted and 5 bought split the right way
- Labels are worked out when needed, never stored, so older sales get labels too (as unknown, since nothing before this feature was logged)
- Sales view: the "What sells" tooltip gains "Came from: 6 crafted, 4 farmed"

## Acceptance criteria

- [x] Crafting 5 of an item adds 5 crafted to that item and day, on retail and on Forever
- [x] Selling 5 of an item crafted earlier labels the sale crafted
- [x] An item bought then sold is labelled resold (with F44); without F44, unknown
- [x] An item looted then sold is labelled farmed
- [x] A sale of 10 where 6 were crafted and 4 looted splits 6 / 4
- [x] A sale with nothing before it is unknown
- [x] Offline tests: oldest-first matching, split sales, items sold more often than they were made, no events

## Verification

```bash
npm test
```

In-game on Forever: craft 2 of an item, loot 2 of another, post and sell both → after taking the mail, Overview → Sales → hover each in "What sells": "Came from" shows 2 crafted and 2 farmed.

## Dependencies

- F44 for resold
- Shares loot-message parsing with F70 (either order works)

## Out of scope

- Items received by mail from alts count as unknown
- Profit per origin after material cost
