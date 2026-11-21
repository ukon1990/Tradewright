# F20 — Auction house / bank character setting

## Summary

Let the player say which character is the auction house / bank character on each realm: the one that buys, sells and receives what the others send. Every other character on that realm counts as a crafter.

## Context

- Characters are known by key `Name-Realm` in `db.characters`.
- Mail only reaches characters on the same realm, so the choice is per realm.
- The Settings tab already has `select` items (`AuctionHelper_SettingsTab.lua`).

## Scope

- Setting `mail.sellerByRealm[realm] = characterKey`; unset means "no auction house character"
- Settings tab: "Auction house / bank character" select listing the known characters on the current realm, plus "None"
- `ForeverLogic.ResolveSellerCharacter(sellerByRealm, realm, knownCharacters)`: returns the chosen key, or nil when unset or when the character is no longer known
- `AuctionHelper:GetSellerCharacterKey()` and `IsSellerCharacter()` for the current realm
- The mailbox panel shows the role of the current character in its header (seller or crafter)

## Acceptance criteria

- [x] The select lists only characters on the current realm and saves per realm
- [x] A removed or unknown character resolves to "None" instead of erroring
- [x] The current character's role is visible in the mailbox panel
- [x] Offline tests cover: chosen, unset, unknown character, other realm

## Verification

```bash
npm test
```

In-game: choose the character in Settings → `/reload` → the choice is kept; log a second realm → its own choice.

## Dependencies

- None

## Out of scope

- Several auction house characters on one realm
- Restricting the auction house panel to the seller
