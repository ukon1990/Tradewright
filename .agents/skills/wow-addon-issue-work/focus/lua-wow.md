# Lua / WoW focus (Tradewright)

- Lua 5.1-shaped: Forever/offline tests use `lua5.1` — avoid 5.2+ APIs (`goto` as control is fine on 5.1; no bit lib assumptions beyond what Forever provides)
- Never leak globals; use `local` and the shared `Tradewright` table
- `pcall` around optional `C_*` APIs (warband counts, `C_EncodingUtil`, `C_ProfSpecs`, replicate AH)
- Events over polling; classic AH dump waits on `AUCTION_ITEM_LIST_UPDATE` + `CanSendAuctionQuery`
- New TOC entries need a **full restart**
- `BackdropTemplate` / `Settings.Register*` — guard if missing
