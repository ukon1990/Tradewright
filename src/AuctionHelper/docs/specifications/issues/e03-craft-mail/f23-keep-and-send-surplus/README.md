# F23 — Keep amounts and mail the surplus

## Summary

Let each character say how many of an item it keeps, and optionally treat every other sellable, non-trash item as surplus. The mailbox panel mails the surplus to the auction house / bank character with one click.

## Context

- The auction house panel already has a "Keep…" rule (`SetAuctionItemRule`, `reserveQty`), but it is per item across the account and only holds items back when bulk posting. It says nothing about what a crafter or gatherer keeps in its own bags.
- `isAuctionSellItemValid` (`AuctionHelper_Auction.lua`) already asks the client whether a bag slot can be auctioned; soulbound and quest items fail it.
- F21 mails materials to crafters. A surplus sweep that ignored the craft queue would mail those materials straight back.
- Only bag items can be attached to mail.

## Scope

- Saved per character: `mail.keepByCharacter[characterKey][itemID] = quantity` and `mail.sendSurplusByCharacter[characterKey] = true|false` (default false)
- `ForeverLogic.BuildSurplusPlan(bagItems, keep, queuedNeeds, sendOthers)`:
  - `bagItems`: `{ itemID, quantity, quality, sellable }` per item in the bags
  - an item with a keep amount is surplus above that amount, whatever `sendOthers` says
  - an item without one is surplus in full only when `sendOthers` is on
  - never surplus: not sellable, poor quality, or still needed by this character's queued crafts (the needed quantity is held back first)
- Mailbox panel on a non-seller:
  - a "Surplus → <auction house / bank character>" row with the items and counts and **Send**; **Send all** includes it
  - a "Keep…" prompt per listed item to set or clear its keep amount, modelled on `ShowAuctionReservePrompt`
  - a "Send other sellable items" check box for this character
- Reuse the existing parcel queue (12 attachments per mail, several mails when needed)
- Items already in F22's "to seller" list are not listed twice

## Acceptance criteria

- [ ] A keep amount set on one character does not affect another character
- [ ] With the check box off and no keep amounts, the surplus row is empty
- [ ] With the check box on, soulbound, quest and poor-quality items are never listed
- [ ] Materials needed for this character's queued crafts are held back before anything is surplus
- [ ] One click mails the surplus to the auction house / bank character; keep amounts stay in the bags
- [ ] On the auction house / bank character itself, or with none set, the row and controls are not shown
- [ ] Offline tests cover: keep above and below stock, check box on and off, not sellable, poor quality, queued need larger and smaller than stock, item with both a keep amount and a queued need

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
