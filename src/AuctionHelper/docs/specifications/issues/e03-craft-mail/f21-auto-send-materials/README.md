# F21 — Send materials when collected

## Summary

When the mailbox opens on the auction house character and all materials for a crafter's queued crafts are in the bags, mail them to that crafter without a click.

## Context

- `BuildShoppingMailSendPlan` returns, per crafter, the materials that are in the bags now; `StartMailSendQueue` mails a plan parcel by parcel.
- Materials cannot be mailed from the auction house, so "once collected" means the next time a mailbox is opened.
- A half-collected set should not leave: the crafter could not craft with it anyway.

## Scope

- `ForeverLogic.SplitMailPlanByReadiness(plan, needs)`: marks each destination complete when every material it needs is fully covered by the plan, otherwise partial with what is missing
- The plan builder exposes the full need per crafter next to what is in the bags
- On mailbox open, when the current character is the seller (F20) and the setting is on, start the send queue for the complete destinations only
- Setting `mail.autoSendMaterials` (default on) in the Settings tab: "Mail materials to crafters when the mailbox opens"
- Mailbox panel: complete sets are marked "ready", partial ones show what is missing and keep the manual **Send**
- One chat line per auto-send run: what went to whom
- **Cancel** still stops the queue; nothing auto-sends twice for the same mailbox visit

## Acceptance criteria

- [ ] Complete sets are mailed on mailbox open with no click, partial sets are not
- [ ] With the setting off, or on a non-seller character, nothing is sent automatically
- [ ] With no auction house character set, behaviour is as today (manual Send / Send all)
- [ ] A cancelled or failed run does not restart by itself until the mailbox is reopened
- [ ] Offline tests cover: complete, partial, several crafters sharing one material, empty plan

## Verification

```bash
npm test
```

In-game: queue crafts for two crafters → buy all materials for one and part for the other → open the mailbox → only the complete set leaves.

Confirm first that Forever accepts a `SendMail` not started by a click. If it does not, fall back to a single prominent "Send ready sets" button and keep the rest of the feature.

## Dependencies

- F20 (seller role)

## Out of scope

- Sending from the bank, or pulling materials out of the bank
- Splitting a set over several mailbox visits
