# F21 — Send materials when collected

## Summary

When the mailbox opens on the auction house character and all materials for a crafter's queued crafts are in the bags, mail them to that crafter without a click.

## Context

- `BuildShoppingMailSendPlan` returns, per crafter, the materials that are in the bags now; `StartMailSendQueue` mails a plan parcel by parcel.
- Materials cannot be mailed from the auction house, so "once collected" means the next time a mailbox is opened.
- A half-collected set should not leave: the crafter could not craft with it anyway.

## Scope

- `ForeverLogic.BuildMailPlan(lines, stock)`: shares the bag stock out over the crafters and marks each destination complete when everything it needs is covered, otherwise partial with what is missing
- `BuildShoppingMailSendPlan` gathers the queue's needs and the bag stock and hands them to that function
- On mailbox open, when the current character is the seller (F20) and the setting is on, start the send queue for the complete destinations only
- Setting `mail.autoSendMaterials` (default on) in the Settings tab: "Mail materials to crafters when the mailbox opens"
- Mailbox panel: complete sets are marked "ready", partial ones show what is missing and keep the manual **Send**
- One chat line per auto-send run: what went to whom
- **Cancel** still stops the queue; nothing auto-sends twice for the same mailbox visit

## Acceptance criteria

- [x] Complete sets are mailed on mailbox open with no click, partial sets are not
- [x] With the setting off, or on a non-seller character, nothing is sent automatically
- [x] With no auction house character set, behaviour is as today (manual Send / Send all)
- [x] A cancelled or failed run does not restart by itself until the mailbox is reopened
- [x] Offline tests cover: complete, partial, several crafters sharing one material, empty plan

## Verification

```bash
npm test
```

In-game: queue crafts for two crafters → buy all materials for one and part for the other → open the mailbox → only the complete set leaves.

Still to confirm in-game: that Forever accepts a `SendMail` not started by a click. If it does not, the automatic run gives up after 6 seconds, says so in chat and leaves the sets to **Send all**.

## Dependencies

- F20 (seller role)

## Out of scope

- Sending from the bank, or pulling materials out of the bank
- Splitting a set over several mailbox visits
