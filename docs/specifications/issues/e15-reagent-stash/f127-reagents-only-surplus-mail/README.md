# F127 — "Only crafting reagents" in the surplus review

## Summary

The mailbox's surplus review gets a tick box "Only crafting reagents". While ticked, the surplus mail to the bank character carries only reagents; everything else stays this visit.

## Context

- The surplus row already mails everything above keep amounts and the queue's needs to the bank character, reagents included. A second mail row would compete for the same items, so this narrows the existing one.
- `MailLogic.SendOnly` marks the other rows as not sent with the reason "Not a reagent"; rows skipped by hand keep their reason.
- Which items count as reagents is F125's rule and its saved choice, shown next to the tick as "only ones my professions use".

## Scope

- Tick box in the review panel under "Send everything sellable…", off by default and forgotten when the mailbox closes
- Second tick box, shown only while the first is ticked, bound to the shared `reagentStash.onlyOwnProfessions`
- No change on the bank character itself (it has no surplus row)

## Acceptance criteria

- [x] Ticked: the Prepare button counts only reagents; other rows read "Not a reagent"
- [x] Unticked or after reopening the mailbox: the surplus is as before
- [x] Queue needs and keep amounts still hold reagents back

## Verification

```bash
npm test
```

In-game on Forever, on a character that is not the bank character: open the mailbox → Review… → tick "Only crafting reagents" → only reagents are listed as sending → Prepare.

## Dependencies

- F125; E03 surplus review

## Out of scope

- A reagent mail from the bank character back to crafters (the materials rows already do that)
