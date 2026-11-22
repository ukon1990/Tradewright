# Tradewright backlog (Forever)

| ID | Title | Status |
| --- | --- | --- |
| [e01-forever-port](issues/e01-forever-port/README.md) | Adapt pack to WoW Forever 16001 | done |
| [f01-agent-harness](issues/e01-forever-port/f01-agent-harness/README.md) | AGENTS.md, skills, ForeverLogic tests | done |
| [e02-remote-market](issues/e02-remote-market/README.md) | Remote market browser + dump enrichment | done |
| [f10-market-tab](issues/e02-remote-market/f10-market-tab/README.md) | Market tab shell (search/sort snapshot) | done |
| [f11-item-history](issues/e02-remote-market/f11-item-history/README.md) | Item detail + hourly history | done |
| [f12-dump-enrichment](issues/e02-remote-market/f12-dump-enrichment/README.md) | listingCount + marketHigh on dump | done |
| [f13-market-tests](issues/e02-remote-market/f13-market-tests/README.md) | Offline market builder tests | done |
| [e03-craft-mail](issues/e03-craft-mail/README.md) | Craft mail: materials to crafters, crafts and surplus back to the seller | done |
| [f20-ah-character](issues/e03-craft-mail/f20-ah-character/README.md) | Auction house / bank character setting | done |
| [f21-auto-send-materials](issues/e03-craft-mail/f21-auto-send-materials/README.md) | Send materials when collected | done |
| [f22-return-crafts](issues/e03-craft-mail/f22-return-crafts/README.md) | Send crafts back to the seller | done |
| [f23-keep-and-send-surplus](issues/e03-craft-mail/f23-keep-and-send-surplus/README.md) | Keep amounts and mail the surplus | done |
| [f24-mail-review](issues/e03-craft-mail/f24-mail-review/README.md) | Review what the surplus mail sends | done |
| [f25-prepare-mail](issues/e03-craft-mail/f25-prepare-mail/README.md) | Prepare mails for the player to send, surplus only after review | done |
| [e04-ah-shortcuts](issues/e04-ah-shortcuts/README.md) | AH shortcuts: from Tradewright lists to the auction house | done |
| [f30-buy-in-ah](issues/e04-ah-shortcuts/f30-buy-in-ah/README.md) | Open a deal's buy page in the auction house | done |
| [e05-table-paging](issues/e05-table-paging/README.md) | Paging in the shared table | done |
| [e06-market-signals](issues/e06-market-signals/README.md) | Market signals: usual price, price steps, sells a day, real fees, fuller ledger | implemented, in-game check pending for F43 and F44; open parts listed per feature |
| [f40-usual-price](issues/e06-market-signals/f40-usual-price/README.md) | Daily price history and a robust usual price | done |
| [f41-price-steps](issues/e06-market-signals/f41-price-steps/README.md) | Cheapest price steps kept from a full scan | done for full scans; steps from a commodity search implemented, in-game check pending; the full steps list open |
| [f42-sells-a-day](issues/e06-market-signals/f42-sells-a-day/README.md) | Estimated sells per day and days of supply | done; Inventory column implemented, in-game check pending; price-steps refinement open |
| [f43-fees-from-the-game](issues/e06-market-signals/f43-fees-from-the-game/README.md) | Fees read from the game and measured from sale mail | implemented, in-game check pending; `house` on sale events and deposits per duration open |
| [f44-ledger-buys-and-misses](issues/e06-market-signals/f44-ledger-buys-and-misses/README.md) | Purchases, expired and cancelled auctions in the ledger | implemented, in-game check pending; instant `buy` on retail commodity purchases open |
| [e07-opportunities](issues/e07-opportunities/README.md) | Opportunities tab: what to buy or sell right now | done; newer parts in-game check pending, open parts listed per feature |
| [f50-opportunities-tab-flips](issues/e07-opportunities/f50-opportunities-tab-flips/README.md) | Opportunities tab and Flips | done (tab and Flips); cart button and deposit loss implemented, in-game check pending; shared Deals card open |
| [f51-sure-things](issues/e07-opportunities/f51-sure-things/README.md) | Sure things: listed under vendor price | done |
| [f52-price-gaps](issues/e07-opportunities/f52-price-gaps/README.md) | Price gaps (risky) | done |
| [f53-weekday-pattern](issues/e07-opportunities/f53-weekday-pattern/README.md) | Weekday pattern in the Market item view | done (one line of text) |
| [f54-sell-now](issues/e07-opportunities/f54-sell-now/README.md) | Sell now | done (list); Gold view card now takes its rows from the list, in-game check pending |
| [f55-smaller-profit-floor](issues/e07-opportunities/f55-smaller-profit-floor/README.md) | Smaller profit floor | done |
| [f56-little-history-warning](issues/e07-opportunities/f56-little-history-warning/README.md) | History coverage, and early rows with a warning | done |
| [f57-where-sales-come-from](issues/e07-opportunities/f57-where-sales-come-from/README.md) | Where "sells a day" comes from and how sure it is | done |
| [f58-how-this-page-works](issues/e07-opportunities/f58-how-this-page-works/README.md) | How this page works, and why a list is empty | done |
| [e08-craft-planning](issues/e08-craft-planning/README.md) | Craft planning: material sources, how many to make, cooldowns | done; newer parts in-game check pending, open parts listed per feature |
| [f60-cheapest-material-source](issues/e08-craft-planning/f60-cheapest-material-source/README.md) | Cheapest way to get each material | done (buy or craft); From column and queueing crafted materials implemented, in-game check pending; row note and "bought every material" line open |
| [f61-how-many-to-make](issues/e08-craft-planning/f61-how-many-to-make/README.md) | How many to make | done (columns); detail pane, queue default and listed stock open |
| [f62-cooldown-crafts](issues/e08-craft-planning/f62-cooldown-crafts/README.md) | Cooldown crafts | done (column and Make cap); footer, Cooldowns filter and login line implemented, in-game check pending; row text and shared cooldowns open |
| [e09-farming](issues/e09-farming/README.md) | Farming: farm window, my farms, what to farm | done; newer parts in-game check pending, open parts listed per feature |
| [f70-farm-window](issues/e09-farming/f70-farm-window/README.md) | Farm window and loot log | done (recording and window); save dialog and idle pause implemented, in-game check pending; collapsed form and tooltip line open |
| [f71-my-farms](issues/e09-farming/f71-my-farms/README.md) | My farms, re-valued at today's prices | done (tab); rename and period filter implemented, in-game check pending |
| [f72-what-to-farm](issues/e09-farming/f72-what-to-farm/README.md) | What to farm | done |
| [e10-income](issues/e10-income/README.md) | Income: where gold comes from, what earns, how fast it sells | done |
| [f80-gold-by-source](issues/e10-income/f80-gold-by-source/README.md) | Gold changes by source | done |
| [f81-sale-origin](issues/e10-income/f81-sale-origin/README.md) | Where each sold item came from | done |
| [f82-income-view](issues/e10-income/f82-income-view/README.md) | Income view | done |
| [e11-bags](issues/e11-bags/README.md) | Bags: an optional bag window grouped by category | done |
| [f90-bag-logic](issues/e11-bags/f90-bag-logic/README.md) | Bag logic: categories, grouping, layout | done |
| [f91-module-and-switch](issues/e11-bags/f91-module-and-switch/README.md) | Bags module and its on/off switch | done |
| [f92-bag-window](issues/e11-bags/f92-bag-window/README.md) | Bag window for the logged-in character | done |
| [f93-bag-row](issues/e11-bags/f93-bag-row/README.md) | Bag row: equipped bags and the reagent bag | done |
| [f94-other-characters](issues/e11-bags/f94-other-characters/README.md) | Other characters as tabs, bank, and the All tab | done |
| [f95-make-room](issues/e11-bags/f95-make-room/README.md) | Make room: delete the cheapest stack, or swap it for loot | done |
| [f96-gear-sets-and-new-items](issues/e11-bags/f96-gear-sets-and-new-items/README.md) | Gear split by equipment set, and a mark on new items | done |
| [f97-item-log](issues/e11-bags/f97-item-log/README.md) | Item log: what entered and left the bags, and why | done |
| [e12-bank-and-bulk](issues/e12-bank-and-bulk/README.md) | Bank and bulk actions in the bag window | done |
| [f100-selection-and-move-logic](issues/e12-bank-and-bulk/f100-selection-and-move-logic/README.md) | Selection and move logic | done |
| [f101-bank-in-the-bag-window](issues/e12-bank-and-bulk/f101-bank-in-the-bag-window/README.md) | Bank in the bag window | done |
| [f102-move-menu](issues/e12-bank-and-bulk/f102-move-menu/README.md) | Move menu per item | done |
| [f103-multi-select](issues/e12-bank-and-bulk/f103-multi-select/README.md) | Multi-select | done |
| [f104-bulk-actions](issues/e12-bank-and-bulk/f104-bulk-actions/README.md) | Bulk actions: move, sell, destroy | done |
| [e13-code-health](issues/e13-code-health/README.md) | Code health: maintainable by a human | done |
| [f105-conventions](issues/e13-code-health/f105-conventions/README.md) | Conventions: maintainable by a human | done |
| [f106-audit-bugs](issues/e13-code-health/f106-audit-bugs/README.md) | Bugs found by the audit | done |
| [f107-dead-code](issues/e13-code-health/f107-dead-code/README.md) | Delete dead code | done |
| [f108-comment-sweep](issues/e13-code-health/f108-comment-sweep/README.md) | Comment sweep | done |
| [f109-shared-helpers](issues/e13-code-health/f109-shared-helpers/README.md) | Shared core helpers for repeated code | done |
| [f110-lookup-tables](issues/e13-code-health/f110-lookup-tables/README.md) | Lookup tables instead of if-chains | done |
| [f111-item-key-normalizers](issues/e13-code-health/f111-item-key-normalizers/README.md) | One item key and snapshot normalizer | done |
| [f112-queue-vocabulary](issues/e13-code-health/f112-queue-vocabulary/README.md) | One name for the craft queue | done |
| [f113-tests-and-complex-functions](issues/e13-code-health/f113-tests-and-complex-functions/README.md) | Tests for core logic, then break up complex functions | done |
| [f114-split-professions-inventory](issues/e13-code-health/f114-split-professions-inventory/README.md) | Split the Professions and Inventory files | done |
| [f115-split-ui](issues/e13-code-health/f115-split-ui/README.md) | Split the UI files | done |
| [f116-split-auction](issues/e13-code-health/f116-split-auction/README.md) | Split Auction.lua | done |
| [f117-shared-ui-helpers](issues/e13-code-health/f117-shared-ui-helpers/README.md) | Shared UI helpers | done |
| [f118-split-data-util-foreverlogic](issues/e13-code-health/f118-split-data-util-foreverlogic/README.md) | Split Data.lua, Util.lua and ForeverLogic.lua | done |
| [f119-rename-namespace](issues/e13-code-health/f119-rename-namespace/README.md) | Rename ProfessionExporter to Tradewright | done |
| [e14-profession-leveling](issues/e14-profession-leveling/README.md) | Profession leveling: cheapest route in the profession side panel | done |
| [f120-skill-up-maths](issues/e14-profession-leveling/f120-skill-up-maths/README.md) | Skill-up maths | done |
| [f121-route-maths](issues/e14-profession-leveling/f121-route-maths/README.md) | Route maths | done |
| [f122-leveling-data](issues/e14-profession-leveling/f122-leveling-data/README.md) | Leveling data and craft queue integration | done |
| [f123-leveling-view](issues/e14-profession-leveling/f123-leveling-view/README.md) | Leveling view in the profession side panel | done |
| [f124-trainer-recipes](issues/e14-profession-leveling/f124-trainer-recipes/README.md) | Trainer recipes | done |
| [e15-reagent-stash](issues/e15-reagent-stash/README.md) | Stash reagents: bank deposit, take for the queue, reagent mail | done |
| [f125-deposit-reagents-in-the-bank](issues/e15-reagent-stash/f125-deposit-reagents-in-the-bank/README.md) | Deposit reagents in the bank | done |
| [f126-take-queue-materials-from-the-bank](issues/e15-reagent-stash/f126-take-queue-materials-from-the-bank/README.md) | Take the craft queue's materials from the bank | done |
| [f127-reagents-only-surplus-mail](issues/e15-reagent-stash/f127-reagents-only-surplus-mail/README.md) | "Only crafting reagents" in the surplus review | done |
| [e16-own-sources](issues/e16-own-sources/README.md) | Own source database: no price addons, sightings of vendors, trainers and drops | done |
| [f128-drop-price-addons](issues/e16-own-sources/f128-drop-price-addons/README.md) | Drop the TradeSkillMaster and Auctionator fallbacks | done |
| [f129-sightings-store](issues/e16-own-sources/f129-sightings-store/README.md) | Sightings store | done |
| [f130-collect-sightings](issues/e16-own-sources/f130-collect-sightings/README.md) | Collect vendors, trainers and loot | done |
| [f131-show-sources](issues/e16-own-sources/f131-show-sources/README.md) | Show sources in the leveling route and tooltips | done |
| [f132-shipped-source-data](issues/e16-own-sources/f132-shipped-source-data/README.md) | Shipped source data without duplicates | done |
| [e17-scan-flow](issues/e17-scan-flow/README.md) | Scan flow: the right scan at the right time | open |
| [f133-suggest-full-scan](issues/e17-scan-flow/f133-suggest-full-scan/README.md) | Suggest the full scan instead of a long item scan | open |

Suggested order: F40 → F43 → F42 → F41 → F44, then F50 and F70 (independent of each other), then the rest of E07, E08 and E09. E07 follow-ups: F55, then F56 → F57 → F58. E10: F80 first (no dependencies), then F81 and F82. E13: F105, F106, F119, then F107 and F108; F109 and F110 (after F106); F117 (after F109); F111; F112; F113; then the splits F114, F115, F116, F118. E14: F120 → F121 → F122 → F123, then F124. E15: F125 → F126, F127.

Research behind E06 to E09: [WoW gold making market strategies](../research/gold-making-market-strategies.md). Designs: [Tradewright Screens](https://claude.ai/artifact/3fV6WrMyawZwaKEAhNnSs5), section "Finding gold"; E14 in section "Profession leveling (E14)".
