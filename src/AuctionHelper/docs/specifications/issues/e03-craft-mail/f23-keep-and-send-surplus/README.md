# F23 — Keep amounts and mail the surplus

## Summary

Let each character say how many of an item it keeps, and optionally treat every other sellable, non-trash item as surplus. The mailbox panel mails the surplus to the auction house / bank character with one click.

## Context

- The auction house panel already has a "Keep…" rule (`SetAuctionItemRule`, `reserveQty`), but it is per item across the account and only holds items back when bulk posting. It says nothing about what a crafter or gatherer keeps in its own bags.
- `isAuctionSellItemValid` (`AuctionHelper_Auction.lua`) already asks the client whether a bag slot can be auctioned; soulbound and quest items fail it.
- F21 mails materials to crafters. A surplus sweep that ignored the craft queue would mail those materials straight back.
- Only bag items can be attached to mail.

## Scope

- Saved per character: `mail.keepByCharacter[characterKey][itemID] = quantity` and `mail.surplusByCharacter[characterKey].sendOthers` (default off)
- `ForeverLogic.BuildSurplusPlan(bagItems, keep, held, sendOthers)`:
  - `bagItems`: `{ quantity, quality, sellable, name }` per item in the bags
  - `held`: what is already spoken for — this character's queued crafts and the other mail rows
  - an item with a keep amount is surplus above keep + held, whatever `sendOthers` says
  - an item without one is surplus above held only when `sendOthers` is on
  - never surplus: not sellable (bound or a quest item) or poor quality
- Mailbox panel on a non-seller:
  - a "Surplus to <auction house / bank character>" row with the items and counts and **Send**; **Send all** includes it
  - a **Keep…** button opening a window that lists the sellable bag items and the items with a keep amount; clicking one opens the keep prompt (`ShowKeepPrompt`, shared with the auction house panel's "Keep…")
  - a "Send other sellable items" check box for this character
- Reuse the existing parcel queue (12 attachments per mail, several mails when needed)
- Items already in F22's "to seller" list are not listed twice

## Acceptance criteria

- [x] A keep amount set on one character does not affect another character
- [x] With the check box off and no keep amounts, the surplus row is empty
- [x] With the check box on, soulbound, quest and poor-quality items are never listed
- [x] Materials needed for this character's queued crafts are held back before anything is surplus
- [x] One click mails the surplus to the auction house / bank character; keep amounts stay in the bags
- [x] On the auction house / bank character itself, or with none set, the row and controls are not shown
- [x] Offline tests cover: keep above and below stock, check box on and off, not sellable, poor quality, queued need larger and smaller than stock, item with both a keep amount and a queued need

## Verification

```bash
npm test
```

In-game: on a crafter, set keep 20 on one material and turn the check box on → open the mailbox → the row lists everything sellable except 20 of that material and anything queued → Send → the items arrive on the auction house / bank character.

## Dependencies

- F20 (auction house / bank character)
- F21 for the queued-needs figure (shared with the materials plan)

## Out of scope

- Counting bank stock towards a keep amount, or pulling items from the bank
- Sending surplus automatically without a click
- Merging with the auction house panel's "Keep…" rule
- Keep amounts by item category or quality instead of per item
