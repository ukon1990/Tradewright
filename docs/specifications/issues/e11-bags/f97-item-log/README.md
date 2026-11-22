# F97 — Item log: what entered and left the bags, and why

## Summary

A Log view in the bag window, next to Bags and Bank: a short list of the items that entered or left a character's bags, with how (looted, mail from a character, bought, sold, moved to or from the bank, destroyed…) and when.

## Context

- The inventory module already saves what a character carries on every bag change (`Tradewright_Holdings.lua`). Comparing the counts before and after a change gives what moved; what was open or had just happened gives why.
- The income data (F81) keeps daily totals per item for crafts and loot; it has no single events and no mail, bank or vendor moves. The log is its own list and does not replace it.
- The log only watches. It hooks `DeleteCursorItem`, `TakeInboxItem`, `AutoLootMailItem` and `SendMail` with `hooksecurefunc` to know about deletes and the other character of a mail.
- Bag contents arrive in pieces after a loading screen, so nothing is logged for 5 seconds after one.

## Scope

- `Tradewright_ItemLogLogic.lua` (inventory module, pure): `Diff`, `Reason`, `Add` (merges the same item and reason within a minute), `Trim`, `Describe`, `Visible`
- `Tradewright_ItemLog.lua` (inventory module): the recorder. `TradewrightInventoryDB.itemLog[characterKey]`, at most 500 entries and `bags.logDays` days (default 14)
- Not logged: putting gear on or off, and items that left for no known reason (used up, crafting materials)
- `Tradewright_BagLog.lua` (bags module): the Log view, newest first, 100 rows at a time with "Show more" under the last row; the search box filters by item name or reason; hover shows the item and the exact time
- Log is offered on character tabs, not on All or the warband bank
- Settings → Bags: "Keep the item log for" 7, 14, 30 or 90 days

## Acceptance criteria

- [x] Looting an item adds "+N item · Looted"
- [x] Taking an item from a mail adds "Mail from <sender>"
- [x] Selling to a vendor, mailing, listing at auction, destroying and bank moves each add a line with the right reason
- [x] On retail a move to or from the warband bank is named as such
- [x] Drinking a potion or equipping an item adds nothing
- [x] The log never holds more than 500 entries or entries older than the setting
- [x] Another character's tab shows that character's log

## Verification

```bash
npm test
```

In-game (full restart): loot, open a mail, sell to a vendor, deposit in the bank, then open the bags → Log.

## Dependencies

- F92, F94

## Out of scope

- Anything from before the feature was installed
- Gold, currencies, and items that never pass through the bags
- Which mob or container an item was looted from
