# AuctionHelper backlog (Forever)

| ID | Title | Status |
| --- | --- | --- |
| [e01-forever-port](issues/e01-forever-port/README.md) | Adapt pack to WoW Forever 16001 | done |
| [f01-agent-harness](issues/e01-forever-port/f01-agent-harness/README.md) | AGENTS.md, skills, ForeverLogic tests | done |
| [e02-remote-market](issues/e02-remote-market/README.md) | Remote market browser + dump enrichment | done |
| [f10-market-tab](issues/e02-remote-market/f10-market-tab/README.md) | Market tab shell (search/sort snapshot) | done |
| [f11-item-history](issues/e02-remote-market/f11-item-history/README.md) | Item detail + hourly history | done |
| [f12-dump-enrichment](issues/e02-remote-market/f12-dump-enrichment/README.md) | listingCount + marketHigh on dump | done |
| [f13-market-tests](issues/e02-remote-market/f13-market-tests/README.md) | Offline market builder tests | done |
| [e03-craft-mail](issues/e03-craft-mail/README.md) | Craft mail: materials to crafters, crafts and surplus back to the seller | implemented, in-game check pending |
| [f20-ah-character](issues/e03-craft-mail/f20-ah-character/README.md) | Auction house / bank character setting | done |
| [f21-auto-send-materials](issues/e03-craft-mail/f21-auto-send-materials/README.md) | Send materials when collected | done |
| [f22-return-crafts](issues/e03-craft-mail/f22-return-crafts/README.md) | Send crafts back to the seller | done |
| [f23-keep-and-send-surplus](issues/e03-craft-mail/f23-keep-and-send-surplus/README.md) | Keep amounts and mail the surplus | done |
| [e04-ah-shortcuts](issues/e04-ah-shortcuts/README.md) | AH shortcuts: from AuctionHelper lists to the auction house | in progress |
| [f30-buy-in-ah](issues/e04-ah-shortcuts/f30-buy-in-ah/README.md) | Open a deal's buy page in the auction house | in progress |
| [e05-table-paging](issues/e05-table-paging/README.md) | Paging in the shared table | implemented, in-game check pending |
| [e06-market-signals](issues/e06-market-signals/README.md) | Market signals: usual price, price steps, sells a day, real fees, fuller ledger | in progress |
| [f40-usual-price](issues/e06-market-signals/f40-usual-price/README.md) | Daily price history and a robust usual price | implemented, in-game check pending |
| [f41-price-steps](issues/e06-market-signals/f41-price-steps/README.md) | Cheapest price steps kept from a full scan | implemented for full scans, in-game check pending; single-item search and the full steps list open |
| [f42-sells-a-day](issues/e06-market-signals/f42-sells-a-day/README.md) | Estimated sells per day and days of supply | implemented, in-game check pending; Inventory column open |
| [f43-fees-from-the-game](issues/e06-market-signals/f43-fees-from-the-game/README.md) | Fees read from the game and measured from sale mail | planned |
| [f44-ledger-buys-and-misses](issues/e06-market-signals/f44-ledger-buys-and-misses/README.md) | Purchases, expired and cancelled auctions in the ledger | planned |
| [e07-opportunities](issues/e07-opportunities/README.md) | Opportunities tab: what to buy or sell right now | in progress |
| [f50-opportunities-tab-flips](issues/e07-opportunities/f50-opportunities-tab-flips/README.md) | Opportunities tab and Flips | tab and Flips implemented, in-game check pending; cart button, shared Deals card and deposit loss open |
| [f51-sure-things](issues/e07-opportunities/f51-sure-things/README.md) | Sure things: listed under vendor price | implemented, in-game check pending |
| [f52-price-gaps](issues/e07-opportunities/f52-price-gaps/README.md) | Price gaps (risky) | implemented, in-game check pending |
| [f53-weekday-pattern](issues/e07-opportunities/f53-weekday-pattern/README.md) | Weekday pattern in the Market item view | implemented as one line of text, in-game check pending |
| [f54-sell-now](issues/e07-opportunities/f54-sell-now/README.md) | Sell now | list implemented, in-game check pending; Gold view card still separate |
| [e08-craft-planning](issues/e08-craft-planning/README.md) | Craft planning: material sources, how many to make, cooldowns | in progress |
| [f60-cheapest-material-source](issues/e08-craft-planning/f60-cheapest-material-source/README.md) | Cheapest way to get each material | buy-or-craft implemented, in-game check pending; From column and queueing intermediates open |
| [f61-how-many-to-make](issues/e08-craft-planning/f61-how-many-to-make/README.md) | How many to make | columns implemented, in-game check pending; detail pane, queue default and listed stock open |
| [f62-cooldown-crafts](issues/e08-craft-planning/f62-cooldown-crafts/README.md) | Cooldown crafts | planned |
| [e09-farming](issues/e09-farming/README.md) | Farming: farm window, my farms, what to farm | planned |
| [f70-farm-window](issues/e09-farming/f70-farm-window/README.md) | Farm window and loot log | planned |
| [f71-my-farms](issues/e09-farming/f71-my-farms/README.md) | My farms, re-valued at today's prices | planned |
| [f72-what-to-farm](issues/e09-farming/f72-what-to-farm/README.md) | What to farm | planned |
| [e10-income](issues/e10-income/README.md) | Income: where gold comes from, what earns, how fast it sells | implemented, in-game check pending |
| [f80-gold-by-source](issues/e10-income/f80-gold-by-source/README.md) | Gold changes by source | implemented, in-game check pending |
| [f81-sale-origin](issues/e10-income/f81-sale-origin/README.md) | Where each sold item came from | implemented, in-game check pending |
| [f82-income-view](issues/e10-income/f82-income-view/README.md) | Income view | implemented, in-game check pending |

Suggested order: F40 → F43 → F42 → F41 → F44, then F50 and F70 (independent of each other), then the rest of E07, E08 and E09. E10: F80 first (no dependencies), then F81 and F82.

Research behind E06 to E09: [WoW gold making market strategies](../../../../../reports/WoW%20gold%20making%20market%20strategies.md). Designs: [AuctionHelper Screens](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5), section "Proposed, not built yet: finding gold".
