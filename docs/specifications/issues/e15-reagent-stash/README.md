# E15 — Stash reagents

## Summary

Crafting reagents can be put away to free bag space and fetched again when they are needed: into the character's own bank from the bag window, back out for the craft queue, and to the bank character by mail. Every move follows a click of the player.

## Context

- The bag window already moves stacks between bags and bank (`RunBagMoves`, E12); E12 left "Deposit all reagents" out of scope.
- The profession scan saves every recipe's reagents per character (`db.characters[characterKey].professions[*].recipes[*].slots[*].reagents[*].itemID`), so "a reagent one of my professions uses" needs no item database. A profession that was never scanned adds nothing.
- The craft queue summary lists what each character's queued crafts need (`BuildCraftQueueSummary().reagentLines[*].sources`). The mail feature already holds those back from the surplus.
- The craft queue counts the character's bank: what a character has is bags plus bank (`GetCharacterItemTotal` → `GetItemCountByLocation`), so the shopping list never asks to buy what is banked. Nothing changes there.
- Stacks are never split. Keeping or fetching "what the queue needs" is done in whole stacks, so a little more than needed can stay or come out.

Decisions taken with the user:

- Both the own bank and the bank character by mail
- By default only reagents of the character's own professions; a tick box widens it to every crafting material (item classes gem, reagent, trade goods)
- The player chooses whether the craft queue's materials stay; with it off everything goes
- The reagent bag is emptied too; when something stays for the queue, stacks in the reagent bag stay first
- The bank actions live in the bag window only (`Tradewright_Bags`)
- Reagents the queue needs can be fetched from the bank in one click

## Scope

- F125: deposit reagents in the bank, with the pure selection rules and their offline test
- F126: take the craft queue's materials from the bank
- F127: "Only crafting reagents" in the mailbox's surplus review

## Acceptance criteria

- [x] F125 to F127 done
- [x] Nothing moves or is mailed without a click
- [x] The pack loads and works without `Tradewright_Bags`; only the bank actions are missing
- [x] Retail and Forever both load; `npm test` passes

## Verification

```bash
npm test
```

In-game (full restart, three new files): see F125 to F127.

## Dependencies

- E12 (bag window bank and stack moves), E03 (surplus mail), E08 (craft queue)

## Out of scope

- Splitting stacks to keep or fetch exact amounts; topping up partial stacks in the bank
- The warband bank
- A deposit button on the game's own bank window, or without `Tradewright_Bags`
- Moving anything while away from a banker or mailbox
