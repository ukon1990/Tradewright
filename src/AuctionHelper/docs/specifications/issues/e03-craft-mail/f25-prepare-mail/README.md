# F25 — Prepare mails for the player to send, surplus only after review

## Summary

The mailbox panel's buttons no longer send in the background. They fill the game's Send Mail window (To, Subject, attachments) and the player presses the game's Send; the next mail is filled in when that one goes through. The surplus is only mailed from the review panel (F24), so nothing leaves the bags unseen.

## Context

- In-game on Forever (2026-11-20): Send attached the items and called `SendMail` behind the Send Mail window. To and Subject stayed empty, the send never went through ("Sending 0 of 3"), and the player could not see or confirm what was going.
- The surplus row had three ways to send (row Send, Send all, the review panel) and only the review panel showed the items. Opening the review was a hidden row click.

## Scope

- Manual sends prepare each parcel: switch to the Send Mail tab, attach, fill `SendMailNameEditBox`, `SendMailSubjectEditBox` (kind and "n/m"), body. The progress line says "Mail n of m ready: press Send in the mailbox". `MAIL_SEND_SUCCESS` prepares the next one; `MAIL_FAILED` keeps the mail as it is. Cancel clears the attachments.
- F21's automatic send to crafters keeps sending by itself.
- Surplus row: a **Review…** button in place of Send; its second line says "214 to send · 8 kept · 4 skipped". The row is shown on a crafter even when nothing would go, so the review can always be opened.
- **Send all** → **Prepare all**: materials and crafted items only. The footer points to Review… for the surplus.
- "Send other sellable items" moves from the mailbox panel into the review panel as "Also send items with no keep amount".
- The review panel's button reads "Prepare 214 items · 3 mails".
- The review panel reopens with the mailbox when it was open last time (saved setting).

## Acceptance criteria

- [x] No manual button sends without the player pressing the game's Send; To and Subject are filled
- [x] The next parcel is prepared after each successful send; a failed send leaves the mail in place
- [x] The surplus can only be mailed from the review panel; Prepare all leaves it out
- [x] The surplus row and Review… show on a crafter even with nothing to send
- [x] The review panel's open state survives closing the mailbox and `/reload`
- [x] `npm test` passes without growing lint debt

## Verification

```bash
npm test
```

In-game: open the mailbox on a crafter → Review… → Prepare → To, Subject and items are filled → press Send → the next mail is filled → after the last one the panel says how many went.

## Dependencies

- F24 (review panel)

## Out of scope

- Changing F21's automatic send
- Mailing to someone other than the auction house / bank character from the surplus
