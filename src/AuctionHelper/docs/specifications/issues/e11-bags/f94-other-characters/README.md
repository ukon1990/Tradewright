# F94 — Other characters as tabs, bank, and the All tab

## Summary

Each character you have logged in with is a tab. Another character's tab is a read-only list of what they carried when last seen, grouped the same way, with stacks added up per item and a Bags / Bank / Both switch. "All" adds every character together. The tooltip says who holds how many.

## Context

- Counts are kept per character in the inventory database: `AuctionHelperInventoryDB.holdings[characterKey] = { name, seenAt, money, bags = { [itemID] = count }, bank = { [itemID] = count }, bankSeenAt }`, written by `AuctionHelper_Inventory/src/modules/AuctionHelper_Holdings.lua`. `inventorySnapshot` keeps its meaning (recipe items, auctions subtracted) for the crafts engine and exports.
- The first version saved these in `AuctionHelperBagsDB`; on login the bags module copies that into the holdings once (`BagLogic.AdoptHoldings`) and clears it.
- Bags are saved on `BAG_UPDATE_DELAYED`; the bank can only be read while it is open (`BANKFRAME_OPENED`, `PLAYERBANKSLOTS_CHANGED`), over the classic bank bags and the bank tabs (`Enum.BagIndex.CharacterBankTab_*`), whichever the client has.
- Tracking starts when the inventory module first loads on a character with this version.

## Scope

- Inventory module: save the bag counts and gold on bag changes; save the bank counts while the bank is open
- Tabs: the logged-in character first, then the most recently seen, as many as fit, then "All" (setting `bags.showCharacters`)
- Own tab: Bags is the live view (F92); Bank is the saved list. Other tabs and All: Bags, Bank or Both, read-only
- Read-only slots: icon, summed count, quality outline; shift-click links the item; no drag, no use
- Tooltip on a read-only slot: the item, each character's bags and bank count, the total, the auction price when known
- Header shows "Name · read-only"; footer shows the item count and when the character was last seen
- Footer gold: the logged-in character's gold and, with more than one character, the total ("All"); hovering it lists every character's gold, richest first, and the total (`BagLogic.GoldByCharacter`)

## Acceptance criteria

- [ ] After logging in on two characters, each has a tab on the other
- [ ] An alt's tab shows the same counts that character had in its bags at logout
- [ ] Bank counts appear after that character has opened its bank once
- [ ] The All tab's count of an item equals the sum over the characters
- [ ] Nothing on a read-only tab can be dragged or used

## Verification

```bash
npm test
```

In-game on Forever: log in on character A, open the bank, log out → log in on B → A's tab lists A's bags; Bank lists A's bank; hover an item both hold → the tooltip lists both.

## Dependencies

- F90, F92

## Out of scope

- Warband bank
- Moving items between characters (the mail panel does that)
- Removing a character from the tabs
