# E03 — Craft mail: materials to crafters, crafts and surplus back to the seller

## Summary

Close the loop between the auction house character and the crafters. Materials bought for queued crafts are mailed to the right crafter as soon as they are all collected, and the finished crafts are mailed back to the seller with one click. Each character can also say how much of an item it keeps and mail the rest. A setting says which character is the auction house / bank character.

## Context

- The mailbox panel (`AuctionHelper_MailPanel.lua`) already lists queued-craft materials per crafter with **Send** per character and **Send all**; `BuildShoppingMailSendPlan` (`AuctionHelper_CraftQueue.lua`) builds that plan from the craft queue and the bags.
- Mails are sent as a queue: the next parcel goes out on `MAIL_SEND_SUCCESS`. Only the first parcel has needed a click so far.
- The craft queue knows the crafter of each craft. A queued craft is ticked down on `TRADE_SKILL_ITEM_CRAFTED_RESULT` (`OnProfessionRecipeCraftedResult`), after which nothing remembers the crafted items.
- There is no notion of an auction house character: the plan treats "whoever is at the mailbox" as the sender.
- The mail panel loads on retail always, and on Forever only when the send-mail and bag APIs exist.

## Scope

- F20: auction house / bank character setting, one per realm
- F21: send a crafter's materials automatically when the full set is in the bags
- F22: remember queued crafts made on a crafter and mail them to the seller
- F23: per-character keep amounts, and mailing surplus sellable items to the seller
- F24: review panel for the surplus mail: inline keep amounts, skip this visit
- F25: prepare each mail in the Send Mail window for the player to send; surplus only from the review
- Pure helpers in `AuctionHelper_ForeverLogic.lua` with offline Lua 5.1 tests in each feature

## Acceptance criteria

- [x] An auction house character can be chosen per realm and is used by the mail plan
- [ ] Opening the mailbox on the auction house character mails every complete material set without a click
- [x] Queued crafts made on a crafter can be mailed to the seller with one click
- [x] A character's surplus above its keep amounts can be mailed to the seller with one click, without touching materials it still needs
- [ ] Retail and Forever both work, or the feature is cleanly hidden where the mail APIs are missing
- [x] `npm test` passes

## Verification

```bash
npm test
```

In-game on Forever: set the auction house character → queue a craft for another character → buy the materials → open the mailbox (materials leave without a click) → log the crafter, craft → open the mailbox → Send to seller.

Two client behaviours to confirm early, because F21 and F22 depend on them:

- Forever accepts a `SendMail` that was not started by a click.
- Forever fires `TRADE_SKILL_ITEM_CRAFTED_RESULT` for crafts.

## Dependencies

- E01 Forever port (done)

## Out of scope

- Cross-realm or cross-faction mail
- Mailing gold
- Buying the materials automatically
