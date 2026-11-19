# F22 — Send crafts back to the seller

## Summary

Remember what a crafter makes from the craft queue, and let them mail it to the auction house character with one click.

## Context

- A queued craft is ticked down when it is crafted (`OnProfessionRecipeCraftedResult` in `AuctionHelper_ProfessionCraftPanel.lua`); the crafted quantity and output item are known at that moment.
- After that the queue entry shrinks or disappears, so the mailbox has no way to tell crafted goods from anything else in the bags.
- F23 can also sweep crafted items up as surplus, but only on characters that turn "Send other sellable items" on. This feature covers the rest, and the two must not list the same items twice.

## Scope

- When a queued craft completes on a character that is not the seller, add `{ itemID, quantity }` to a saved "to seller" list for that character
- `ForeverLogic.BuildReturnToSellerPlan(toSeller, bagCounts, sellerKey)`: one destination (the seller) with each item clamped to what is in the bags; empty when there is no seller
- Mailbox panel on a crafter: a "Crafted items → <seller>" row with **Send**; **Send all** includes it
- Reuse the existing parcel queue; on a successful send, reduce the list by what was mailed
- Entries whose items are no longer in the bags are dropped when the plan is built

## Acceptance criteria

- [x] Crafting a queued recipe on a crafter adds the result to the list; crafting outside the queue does not
- [x] One click mails the listed items that are in the bags to the seller
- [x] The list shrinks by what was mailed and survives `/reload`
- [x] On the seller, or with no seller set, the row is not shown
- [x] Offline tests cover: clamp to bags, item gone, no seller, several items

## Verification

```bash
npm test
```

In-game: queue a craft for a crafter → craft it → open the mailbox → Send → the item arrives on the seller.

Still to confirm in-game: that Forever fires `TRADE_SKILL_ITEM_CRAFTED_RESULT`. The list is filled from the same handler that ticks the queue down, so if the queue counts down after a craft, this works too.

## Dependencies

- F20 (seller role)

## Out of scope

- Returning items crafted outside the queue
- Sending automatically without a click
- Posting the returned items at the auction house
