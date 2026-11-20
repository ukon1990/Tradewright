# Source audit: crafting_strategies.md, tools_and_algorithms.md, farming.md

Audit date: 2026-11-20. Scope: check the sources of the three notes files; no new research.

Method
- Every [peer-reviewed], [working paper], [official] and [primary data] source was re-opened independently (Crossref API, publisher/RePEc/NBER pages, full-text PDFs where open, Blizzard forum threads read through the forum's own JSON so the poster's staff flag is visible, Blizzard news and legal pages, Wowhead, CurseForge, GitHub API).
- Every [source code] file behind an algorithm claim was downloaded again from its raw GitHub URL and the constants read from the file. Nothing downloaded was executed.
- [reference wiki], [tool docs] and [community] sources were spot-checked only where an addon design fact depends on them. Wiki pages were read as raw wikitext plus rendered HTML (the game-type box is template-rendered).
- Evidence is given as exact values, identifiers and locations. Prose is paraphrased, not quoted.

Verdict key: VERIFIED (content read, supports claim), VERIFIED-ABSTRACT (abstract only), PARTLY (exists, claim overstated or a number differs), UNSUPPORTED, NOT FOUND, UNREACHABLE (exists per index, content not opened).

Headline result: no fabricated or unresolvable reference was found. All algorithm constants an addon would copy match the cited files exactly. The problems are provenance (three code sources are private-server ports, one "confirmation" is circular), a few overstated academic claims, and every WoW Forever economic rule (cut, deposit, cooldowns) resting on a wiki template listing, one third-party README and one gold-selling site.

---

## 1. Summary table

### 1a. Academic and reference sources

| # | Source | Tier claimed | Tier corrected | Verdict | Note | Verified against |
|---|---|---|---|---|---|---|
| 1 | Kosminsky, "World of Warcraft: The Viability of MMORPGs as Platforms for Modeling and Evaluating Perfect Competition", J. Virtual Worlds Research 2(4), DOI 10.4101/jvwr.v2i4.869 | peer-reviewed | peer-reviewed (journal section "Research Papers"; journal policy: two reviewers). Quality caveat: acknowledgement credits a high-school science research department; six servers, one month | PARTLY | Full PDF read. Table 3 numbers match exactly (mode 5.00 / 15.00, 0%; mean 6.02 vs 5.71 = -5.15%; 17.12 vs 18.06 = +5.49%); R2 = .993 on Figure 7; conclusion wording matches. Problems: (a) the 13 Sep to 13 Oct 2008 window is stated for the netherweave tables (data from wowecon.com); the essence table is from wow.allakhazam.com with no stated dates; (b) the price-stability test was not clean: medium-population servers were the least stable (SD 2.35 vs 1.62 low, 0.895 high), which the author explains by self-selection; (c) R2 = .993 is a quadratic fitted to about six server points; (d) the author attributes the 5% mean gap to level-70 supply of Greater essences, not to the auction cut. Issue cover is dated February 2010; the journal site labels the issue 2009 | https://jvwr-ojs-utexas.tdl.org/jvwr/article/view/869/634 ; https://api.crossref.org/works/10.4101/jvwr.v2i4.869 |
| 2 | Morrison and Fontenla (2013), "Price convergence in an online virtual world", Empirical Economics 44(3), 1053-1064, DOI 10.1007/s00181-012-0567-3 | peer-reviewed | same | VERIFIED-ABSTRACT | Bibliography exact (Crossref, RePEc). Abstract: eight structurally identical "worlds", Phillips-Sul test and own band-of-inaction test, convergence in all eight. Says nothing about crafting or conversion margins | https://api.crossref.org/works/10.1007/s00181-012-0567-3 ; https://ideas.repec.org/a/spr/empeco/v44y2013i3p1053-1064.html |
| 3 | Conlon and Mortimer, "Demand Estimation Under Incomplete Product Availability", NBER WP 14315 (Sept 2008, rev. Dec 2011); AEJ: Microeconomics 5(4), 1-30 (2013), DOI 10.1257/mic.5.4.1 | working paper; published version peer-reviewed | same | VERIFIED-ABSTRACT | Both DOIs resolve in Crossref. Abstract: 54 vending machines, availability observed every four hours, procedure for periodically observed availability. Use in the notes is by analogy only (vending machines, not auctions) | https://www.nber.org/papers/w14315 ; https://api.crossref.org/works/10.1257/mic.5.4.1 |
| 4 | Heeks (2008), Development Informatics Working Paper 32, Univ. of Manchester | working paper | same | VERIFIED | Full PDF read (44 pp). Definition, role list (Hunter, Fighter, Gatherer, Producer, Banker, Dealer, Marketer, Leveller), bots box, US$500m best guess with US$200m to >US$1bn range, 150,000 to 400,000 employed, US$145 per month all present. The paper itself warns it relies on secondary, mainly unrefereed sources | https://hummedia.manchester.ac.uk/institutes/gdi/publications/workingpapers/di/di_wp32.pdf |
| 5 | Castronova (2001), CESifo Working Paper 618 | working paper | same | VERIFIED-ABSTRACT | Abstract gives USD 3.42 per hour and USD 0.0107 per currency unit (EverQuest). Not WoW, not in-game currency per hour | https://econpapers.repec.org/RePEc:ces:ceswps:_618 |
| 6 | NIST/SEMATECH e-Handbook 1.3.5.17 Detection of Outliers | official | government statistical reference handbook (not peer-reviewed, not Blizzard) | VERIFIED | z-score formula, modified z-score with 0.6745 and MAD, 3.5 threshold (Iglewicz and Hoaglin), small-sample warning and (n-1)/sqrt(n) bound all on the page | https://www.itl.nist.gov/div898/handbook/eda/section3/eda35h.htm |
| 7 | NIST/SEMATECH e-Handbook 6.4.3.1 Single Exponential Smoothing | official | as row 6 | VERIFIED | Equation, 0 < alpha <= 1, geometric weights, choose alpha by smallest MSE all present. Nit: weights sum to one only in the limit | https://www.itl.nist.gov/div898/handbook/pmc/section4/pmc431.htm |
| 8 | Leys et al. (2013), J. Exp. Social Psychology 49(4), 764-766 (Gaps only) | (not used) | peer-reviewed | UNREACHABLE | Bibliography matches Crossref; DOI resolves to the publisher landing page; full text not read. No claim rests on it | https://api.crossref.org/works/10.1016/j.jesp.2013.03.013 |
| 9 | Huber (1964), Annals of Math. Statistics 35(1), 73-101 (Gaps only) | (not used) | peer-reviewed | UNREACHABLE | As row 8; DOI resolves to Project Euclid | https://api.crossref.org/works/10.1214/aoms/1177703732 |
| 10 | Ahmad, Keegan, Srivastava, Williams, Contractor (2009), "Mining for Gold Farmers", IEEE CSE 2009, pp. 340-345 (Gaps only) | peer-reviewed | peer-reviewed conference paper | UNREACHABLE | DOI now confirmed: 10.1109/CSE.2009.307 (the notes say unconfirmed). Content not read. No claim rests on it | https://api.crossref.org/works/10.1109/CSE.2009.307 |
| 11 | Lehdonvirta and Ernkvist (2011), "Knowledge Map of the Virtual Economy" (Gaps only) | working paper | institutional report (World Bank / infoDev) | UNREACHABLE | Exists. "27361" is the World Bank Open Knowledge handle (10986/27361), not a report number. Content not read. No claim rests on it | https://econpapers.repec.org/RePEc:wbk:wboper:27361 ; https://openknowledge.worldbank.org/handle/10986/27361 |

### 1b. Blizzard official

| # | Source | Tier claimed | Tier corrected | Verdict | Note | Verified against |
|---|---|---|---|---|---|---|
| 12 | "Dragonflight: Making It with Professions", Blizzard news 23876529 | official | same | VERIFIED | Blizzard Entertainment byline, dated 23 November (2022). Stat definitions, public/guild/personal order rules, posting fee, Artisan's Consortium cut, specialization text all present. Describes the 10.0 launch system (includes Inspiration, removed in 11.0) | https://worldofwarcraft.blizzard.com/en-us/news/23876529/dragonflight-making-it-with-professions |
| 13 | Forum: "World of Warcraft API Update - Visions of N'zoth" (thread 3461) | official | same | VERIFIED | Poster Araspir, staff flag true, user title "Blizzard Developer", 2020-02-12. Auction endpoint, 1-hour interval that may change, >10 MB all in the opening post. The Last-Modified statement is in Araspir's reply no. 15 (2020-02-16), not the opening post. The notes say the role was not labelled; it is | https://us.forums.blizzard.com/en/blizzard/t/world-of-warcraft-api-update-visions-of-nzoth/3461 |
| 14 | Forum: "Immediate change to Auction APIs for Commodities with 9.2.7" (thread 31522) | official | same | VERIFIED | Poster Korakk, staff flag true, "Blizzard Developer", 2022-08-18. Regional commodities endpoint, hourly, quota cost 25 (from 1), if-modified-since still charged: all present | https://us.forums.blizzard.com/en/blizzard/t/immediate-change-to-auction-apis-for-commodities-with-927/31522 |
| 15 | Forum: "UI Add-On Development Policy" (thread 24534) | official | same | VERIFIED | Poster Kaivax (Community Manager, staff). Thread created 2018-11-19 as a repost; policy text dates itself to 20 March 2009 with a 13 April 2009 update. All eight clauses match the notes. No clause mentions automation | https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534 |
| 16 | Forum: "New Instance Limit in WoW Classic" (thread 556616) | official | same | VERIFIED | Kaivax, 2020-06-16. 30 unique instances per day per realm, alongside 5 per hour, checked across all characters on the realm, stated purpose is exploitative and automated gameplay | https://us.forums.blizzard.com/en/wow/t/556616 |
| 17 | Forum: "New Increasing Cooldown for Changing Layers" (thread 290703) | official | same | VERIFIED | Kaivax. Created 2019-09-08 03:36 UTC (7 Sept US time). Increasing cooldown per layer change | https://us.forums.blizzard.com/en/wow/t/290703 |
| 18 | Blizzard End User License Agreement | official | same | VERIFIED | Last revised 21 March 2024. Clauses 1.C.ii (cheats, bots), 1.C.iii (gathering for sale outside the platform; services for payment), 1.C.vi (unauthorised data mining) present as cited | https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement |
| 19 | "Policy Update for Input Broadcasting Software", news 23558957, plus forum thread 707427 | official | same | VERIFIED | News page dated 3 November (no year); forum post by Kaivax created 2020-11-03 links to it. Actionable offence, warnings first, up to permanent closure | https://worldofwarcraft.blizzard.com/en-us/news/23558957/policy-update-for-input-broadcasting-software ; https://us.forums.blizzard.com/en/wow/t/policy-update-for-input-broadcasting-software/707427 |
| 20 | Forum: "Policy Update for Input Broadcasting - May 2021" (thread 956610) | official | same | VERIFIED | Kaivax, 2021-05-05. Extends to all software and hardware mirroring and to automating or streamlining multi-boxing | https://us.forums.blizzard.com/en/wow/t/policy-update-for-input-broadcasting-may-2021/956610 |

### 1c. Primary data

| # | Source | Tier claimed | Tier corrected | Verdict | Note | Verified against |
|---|---|---|---|---|---|---|
| 21 | Wowhead Classic, spell 17187 Transmute: Arcanite | primary data | database site (client data plus crowd upload) | VERIFIED | Cooldown shown as 2 days; Thorium Bar, Arcane Crystal, Philosopher's Stone. This is the Classic database, not Forever | https://www.wowhead.com/classic/spell=17187/transmute-arcanite |
| 22 | Wowhead Classic, item 13468 Black Lotus (page and XML feed) | primary data | as row 21 | VERIFIED | XML: sellprice 1000, avgbuyout 538989, source [2,17]. Page carries the Wowhead Looter text. No dropped-by table visible to a fetch | https://www.wowhead.com/classic/item=13468&xml |
| 23 | GitHub API: Auctionator organisation | primary data | direct observation | VERIFIED | `repos/Auctionator/Auctionator` returns 404; `repos/TheMouseNest/Auctionator` also 404. Addition: `Auctionator/Journalator` now redirects to `TheMouseNest/Journalator`, and `Auctionator/BCC-Auctionator` is archived | https://api.github.com/repos/Auctionator/Auctionator |
| 24 | CurseForge download totals (five pages) | primary data | direct observation | VERIFIED | TSM 64,643,659; Auctionator 215,355,759; Auctioneer 33,534,406; CraftSim 10,459,214; BagSync 5,040,517. All round to the figures in the notes | https://www.curseforge.com/wow/addons/tradeskill-master (and the four sibling pages) |
| 25 | GitHub API search: Altoholic repositories | primary data | direct observation | UNREACHABLE | GitHub API rate limit hit during the audit. Low-impact claim | https://api.github.com/search/repositories?q=Altoholic+in:name |
| 26 | nexushub.co | primary data | direct observation | VERIFIED | HTTP 307 to a GoDaddy for-sale page | https://nexushub.co/ |

### 1d. Source code (re-read from the raw files)

| # | Source | Official or third party; current or legacy | Verdict | Constants and formulas confirmed | Verified against |
|---|---|---|---|---|---|
| 27 | Keoo88/TradeSkillMaster-3.3.5-backport, `AuctionScan/Classes/Util.lua` | Third-party backport of TSM v4.14.66 to 3.3.5a. Not TSM's code path for market value: the block is headed as built from the TSM docs | VERIFIED | `MIN_PERCENTILE = 0.15`, `MAX_PERCENTILE = 0.30`, `MAX_JUMP = 1.2`; first `max(2, n*0.15)` prices protected; stop when index > n*0.30 or price >= 1.2 x previous; population standard deviation; keep window mean +/- 1.5 SD; filter skipped when fewer than 3 survivors. Because it was written from the docs article, it is not independent confirmation of row 41 | https://raw.githubusercontent.com/Keoo88/TradeSkillMaster-3.3.5-backport/HEAD/TradeSkillMaster/LibTSMService/Source/AuctionScan/Classes/Util.lua |
| 28 | Same repo, `TradeSkillMaster_AuctionDB/Core.lua` | As row 27 | PARTLY | Array `{132, 125, 100, 75, 45, 34, 33, 38, 28, 21, 15, 10, 7, 5, 4}` (15 entries, days 0..14), `MARKET_WINDOW = 15`, `HIST_WINDOW = 60` are in the file. That these are TSM's own weights is asserted only by a code comment. Consistency check: sum 672, cumulative share 38% after two days and 53% after three, which fits the docs' half-life of a little over two days. Still unverified as first-party | https://raw.githubusercontent.com/Keoo88/TradeSkillMaster-3.3.5-backport/HEAD/TradeSkillMaster_AuctionDB/Core.lua |
| 29 | BanditTech/TradeSkillMaster (7 files: Crafting, Cost, Queue, Conversions, Disenchanting, TradeSkillMaster.lua, Shopping Destroying) | Third party. Not a GitHub fork: TOC says "TradeSkillMaster: Revived", based on TSM v2.8.3, Interface 30300, modified for the Ascension private server. Legacy | VERIFIED | `defaultMatCostMethod = "min(dbmarket, crafting, vendorbuy, convert(dbmarket))"`; `defaultCraftPriceMethod = "dbminbuyout"`; `profitPercent = 0`; `ignoreCDCraftCost = true`; operation defaults `minRestock = 1`, `maxRestock = 3`, `minProfit = 1000000` copper; queue = `max(maxRestock - totalInventory, 0)`, zeroed below `minRestock`, gated by `profit >= minProfit`; cost = sum(qty x matCost) / numResult, lowest valid recipe, cooldown recipes skipped only when two or more recipes exist; profit = `buyout - buyout*profitPercent - cost`; `destroyValueSource = "DBMarket"`; prospect rate divided by 5 in the Shopping search; `pigmentPerInk` 1 (Ivory) or 2; Saronite uncommon 0.2 / rare 0.04; Titanium 0.25 / 0.04 / 0.03; Copper Malachite 0.5, Tigerseye 0.5, Shadowgem 0.1; Thorium four gems 0.3, Star Ruby 0.1; Infinite Dust ilvl 130-151 = 1.875; essence transforms 3 and 1/3, motes and crystallized 10 and 1/10 | https://raw.githubusercontent.com/BanditTech/TradeSkillMaster/main/TradeSkillMaster_Crafting/TradeSkillMaster_Crafting.lua (and siblings) |
| 30 | derfloh205/CraftSim (11 files) | Official repository of the addon author; current (pushed 2026-11-20); retail only | VERIFIED | `AUCTION_HOUSE_CUT = 0.95`; `PERCENT_DIVISION_FACTORS` identical for Dragonflight, The War Within, Midnight: `MULTICRAFT = 1100`, `RESOURCEFULNESS = 900`, `INGENUITY = 1000` (plus `CRAFTINGSPEED = 2650`); `BASE_RESOURCEFULNESS_AVERAGE_SAVE_FACTOR = 0.30`; `MULTICRAFT_CONSTANTS = {DEFAULT = 2.5, [1] = 2.1, [2] = 1.83, [5] = 1.875}`; maxExtra = constant x baseYield x (1 + bonus), expectedExtra = (1 + maxExtra) / 2; expected yield per craft = base + expectedExtra x pMC; saved cost on proc = required-reagent cost x 0.30 x (1 + bonus); concentration value = profit / (cost - cost x ingenuityChance x (0.5 + bonus)); `expectedQualityConcentration = min(expectedQuality + 1, maxQuality)`; `TSM_DEFAULT_PRICE_EXPRESSION = "first(DBRecent, DBMinbuyout)"`; deposit off by default with expression `vendorsell`; sale-rate thresholds 0.1 (send to queue) and 0 (scan); sale rate read as `dbregionsalerate*1000`; VendorBuy preferred over the price expression. One behaviour the notes do not mention: in the with-stats path the expected deposit is subtracted twice (once inside the result-value helper, once again in the per-outcome profit) | https://raw.githubusercontent.com/derfloh205/CraftSim/main/Util/Const.lua ; .../Pricing/ProfitCalculation.lua ; .../Classes/RecipeData.lua |
| 31 | TheMouseNest/CraftInfoAnywhere `Main_Classic.lua` | Official repo of that addon; current | VERIFIED | price = vendor price if present, else Auctionator auction price; total = sum(price x quantity). No cut, no profit | https://raw.githubusercontent.com/TheMouseNest/CraftInfoAnywhere/main/Main_Classic.lua |
| 32 | Auctionator/BCC-Auctionator `DisenchantingProbabilities.lua` | First-party Auctionator organisation repo; archived 2021; legacy | VERIFIED | Uncommon armor ilvl 56-60: 37.5% x1, 37.5% x2 (item 16204), 10% x1, 10% x2 (16203), 5% x1 (14344). ilvl 66-80: three 25% dust rows (x1, x2, x3). Extra discrepancy not in the notes: the file's commented reference row has Infinite Dust for ilvl 121-151 at 1-3 (mean 1.5 at 75%), while row 29 has 130-151 at 2-3 (1.875) | https://raw.githubusercontent.com/Auctionator/BCC-Auctionator/main/Source/Constants/DisenchantingProbabilities.lua |
| 33 | sirus-addons/Auctionator (TOC, Database/Mixin, API v1 README, GetAuctionPrice, LIFOPrice) | Third-party private-server port; TOC Version 9.1.3, Interface 30300; legacy. Upstream is not public, so the current API cannot be confirmed | VERIFIED | Record fields `l`, `h`, `a`, `m` with the stated meanings; `ProcessScan` takes the minimum price and sums availability; `l` stored only when below `h`; `GetPriceHistory` returns date, minSeen, maxSeen, available; API functions `GetAuctionPriceByItemID`, `GetAuctionPriceByItemLink`, `MultiSearch`; ItemID lookup returns field `m`; undercut = base x (100 - pct) / 100 or base - static amount, floor 100 copper | https://raw.githubusercontent.com/sirus-addons/Auctionator/HEAD/Auctionator/Source/Database/Mixin.lua |
| 34 | shirsig/aux-addon `core/history.lua` | Official repo; Classic 1.13 client; pushed 2026-01-19 | VERIFIED | Daily minimum unit buyout pushed at next local midnight; at most 11 points; weight `0.99 ^ days before newest point`, normalised; weighted median returns the first value where cumulative weight >= 0.5; falls back to today's minimum only when there are no points | https://raw.githubusercontent.com/shirsig/aux-addon/master/core/history.lua |
| 35 | AcidWeb/RECrystallize `RECrystallize.lua` | Official; retail; pushed 2026-04-22 | VERIFIED | Uses `C_AuctionHouse.ReplicateItems`; stores `{Price, LastSeen}` per variant; `RECrystallize_PriceCheck` returns price, lastSeen, partial; `RECrystallize_PriceCheckItemID`; 60-second warning ticker; default cleanup 432000 s | https://raw.githubusercontent.com/AcidWeb/RECrystallize/HEAD/RECrystallize.lua |
| 36 | erorus/shatari (`addon/OribosExchange.lua`, `src/constants.js`) | Official Undermine Exchange backend; current | VERIFIED | `market` = 4-day median on this AH, `region` = median across realms, `days` 0-250 with 251 and 252 special, silver precision; `MAX_HISTORY` = 14 days; products `mainline` and `forever`. `realmProcess.js` was downloaded but not re-read line by line | https://raw.githubusercontent.com/erorus/shatari/HEAD/addon/OribosExchange.lua |
| 37 | erorus/newsstand `scripts/buildaddon.php` | Official source of the defunct Undermine Journal; legacy | VERIFIED | 72-hour "recent" average and a standard deviation of hourly prices present in the SQL | https://raw.githubusercontent.com/erorus/newsstand/master/scripts/buildaddon.php |
| 38 | berickus/LootAppraiserReloaded (UI, Const, LootProcessing, Config, Session) | Official repo of the Reloaded addon; current (pushed 2026-11-14). Tagged [tool docs] in farming.md; it is source code | VERIFIED | Active function: delta = (pauseStart or now) - session start - accumulated pause; copper per second = value / delta; per hour = x 3600; returns 0 when below 1 copper per second. Default source `DBRegionMarketAvg`; quality filter "1"; alert threshold "100"; `ignoreRandomEnchants = true`; vendor fallback from item info return 11; no cut or deposit term. Config text mentions 10 instance resets per hour. An older commented-out version of the function sits above the live one | https://raw.githubusercontent.com/berickus/LootAppraiserReloaded/HEAD/Core/UI/UI.lua |
| 39 | Nevcairiel/GatherMate2 `Collector.lua` | Official; current | VERIFIED | Spell-cast based collection; LOOT_CLOSED, combat-log and CHAT_MSG_LOOT registrations are commented out | https://raw.githubusercontent.com/Nevcairiel/GatherMate2/master/Collector.lua |
| 40 | ZiiMs/OribosExchange-Forever `README.md` | Third-party fork, one star, self-described | VERIFIED | Says what the notes report: interface 16001, hourly builds, US/EU/TW/KR with 12/12/6/6 houses, four rulesets x three factions, 4-day median of daily lows, a "5% cut" in its crafting line. Single unverified source for every one of those Forever facts | https://raw.githubusercontent.com/ZiiMs/OribosExchange-Forever/HEAD/README.md |

### 1e. Tool docs (spot-checked)

| # | Source | Verdict | Note | Verified against |
|---|---|---|---|---|
| 41 | TSM support: How is AuctionDB Market Value calculated | VERIFIED | At most the lowest 30%; 20% jump rule only after the first 15%; 1.5 standard deviations; previous 14 days plus today, weights only in an image; half-life a little over 2 days; worked example gives 14.5. Article last updated 25 July 2021, so it is five years old | https://support.tradeskillmaster.com/en_US/auctiondb-market-value/how-is-auctiondb-market-value-calculated |
| 42 | TSM support: Which Price Sources can I use | VERIFIED | DBMarket 14-day weighted, recent 3 days favoured; DBMinBuyout may be 30 minutes old; DBHistorical 60 days; region sources; Crafting, matPrice, Destroy, vendorBuy, vendorSell, SmartAvgBuy; DBRegionMinBuyoutAvg retired | https://support.tradeskillmaster.com/custom-strings/which-price-sources-can-i-use-and-what-do-they-mean |
| 43 | TSM Addon: Crafting Operations | VERIFIED | Cost and profit definitions; min restock example (10 vs 3); min profit on by default at 100g; values 0 to 2000 | https://support.tradeskillmaster.com/tsm-addon-documentation/1236068-tsm-addon-crafting-operations |
| 44 | TSM: How do the #Default Operations work | VERIFIED | Shopping `dbmarket`; Crafting 10 / 20 / 100g; Vendoring 20 expires, soulbound excluded; Warehousing nothing; Auctioning and Sniper "coming soon" | https://support.tradeskillmaster.com/en_US/addon/how-do-the-default-operations-work |
| 45 | Erorus gist `method.md` | VERIFIED | Market price = per-unit cost of the cheapest 15% of quantity; mean; median; global price from US and EU medians observed 8 times in 24 hours | https://gist.github.com/erorus/09e2d19f1dd114c3588ff4141063a760 |
| 46 | Saddlebag wiki: WoW market overview | VERIFIED | Bands at +/-15% and +/-60%; current and historic market value formulas; soldPerDay from the TSM API; top 200 | https://raw.githubusercontent.com/ff14-advanced-market-search/saddlebag-with-pockets/master/app/content/blog/wiki/how-to-trade-using-our-wow-market-overview.md |
| 47 | undermine.exchange | VERIFIED | Footer names Midnight and Forever; patron options incl. Arbitrage Mode; $3.00 per month | https://undermine.exchange/ |
| 48 | wowauctions.net | VERIFIED | WoW Forever US and EU (4 realms each), Retail, MoP Classic, Classic Era, two private servers; hourly prices for 30 days; heat maps; recipes by profit. Alerts appear only as a menu link | https://www.wowauctions.net/ |
| 49 | CurseForge feature and flavor claims (TSM, Auctionator, Auctioneer, CraftSim, BagSync) | VERIFIED | Forever is listed for TSM, Auctionator and BagSync. TSM v4.15.8 on 2026-11-18. Auctioneer last updated 2024-09-29, latest retail 11.0.2. CraftSim retail only, 27.0.7 on 2026-09-28 | https://www.curseforge.com/wow/addons/tradeskill-master |

### 1f. Reference wiki (spot-checked, all on warcraft.wiki.gg)

| # | Page | Verdict | Note | Verified against |
|---|---|---|---|---|
| 50 | TOC format | VERIFIED | Interface table: Forever 16001, Standard 120105, Mists 50504, Vanilla 11509. Game suffixes: `_Standard` (Midnight), `_Forever` and `_Camelot` (Forever). Family suffix `_Mainline` covers standard, forever, camelot, plunderstorm, wowhack and has lower priority than a game suffix. Footnote that Camelot may be renamed Forever. Patch 1.60.1 entry adds the Camelot game type. `_Standard` suffix added in 12.1.5. Page warns its values are contributor-maintained | https://warcraft.wiki.gg/wiki/TOC_format |
| 51 | World of Warcraft: Forever (reached via Patch_1.60 redirect) | VERIFIED | Released 4 November 2026; announced at BlizzCon 2026; internal name Camelot; nickname Classic+; level cap 60; one mega-realm per ruleset per region. The page has no auction house rules | https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever |
| 52 | Auction House | VERIFIED | 5% cut; deposit 15 / 30 / 60% of vendor price for 12 / 24 / 48 h; 1 silver minimum; received = bid - cut + deposit; 9.2.7 region-wide commodities; 6.0.2 merge. Page carries an out-of-date banner that mentions the former neutral houses and their 15% cut. It describes retail only | https://warcraft.wiki.gg/wiki/Auction_House |
| 53 | C_AuctionHouse.ReplicateItems | VERIFIED | 15-minute account-wide throttle between successful calls; 80k-auction disconnects; 9.0.2 owner hotfix; about 2000 update events per frame; game types standard, forever, mists | https://warcraft.wiki.gg/wiki/API_C_AuctionHouse.ReplicateItems |
| 54 | C_AuctionHouse.SendBrowseQuery | VERIFIED | `noscript` restriction with the "brick the AH" note; no hardware-event tag; listed for forever | https://warcraft.wiki.gg/wiki/API_C_AuctionHouse.SendBrowseQuery |
| 55 | C_AuctionHouse.PostItem | VERIFIED | `hwevent, noscript`; durations 1/2/3 = 12/24/48 h; silent failure on non-zero copper; 9.1.5 protection; 9.2.5 return value. Tooltips carry builds 12.1.5 (69848), 1.60.1 (69913), 5.5.4 (68077) | https://warcraft.wiki.gg/wiki/API_C_AuctionHouse.PostItem |
| 56 | C_AuctionHouse.PlaceBid | PARTLY | `hwevent, noscript`, 9.1.5 protection confirmed. The page's amount note says gold only, not whole silver as the notes state (probably a wiki slip; PostItem says gold and silver) | https://warcraft.wiki.gg/wiki/API_C_AuctionHouse.PlaceBid |
| 57 | StartCommoditiesPurchase and ConfirmCommoditiesPurchase | VERIFIED | Start is `hwevent, noscript`, protected in 9.1.5; Confirm carries no restriction tag | https://warcraft.wiki.gg/wiki/API_C_AuctionHouse.StartCommoditiesPurchase |
| 58 | CancelAuction and the API index | VERIFIED | `hwevent, noscript` on CancelAuction, PlaceBid, PostCommodity, PostItem, StartCommoditiesPurchase; none on ReplicateItems or ConfirmCommoditiesPurchase | https://warcraft.wiki.gg/wiki/World_of_Warcraft_API |
| 59 | QueryAuctionItems | VERIFIED | 0.3 s normal throttle, 15 minutes for getAll, 42554-item cap in 4.0.1, 63-byte text limit; removed from retail in 8.3.0; game types mists, tbc, vanilla; forever not listed | https://warcraft.wiki.gg/wiki/API_QueryAuctionItems |
| 60 | PostAuction | VERIFIED | `hwevent, noscript`; runTime 1/2/3 = 2/8/24 h; added 1.13.2; `warningAcknowledged` in 1.15.7; forever not listed | https://warcraft.wiki.gg/wiki/API_PostAuction |
| 61 | PlaceAuctionBid | VERIFIED | Hardware event required since patch 2.0 | https://warcraft.wiki.gg/wiki/API_PlaceAuctionBid |
| 62 | C_TradeSkillUI.CraftRecipe | VERIFIED | No hardware-event tag; game types standard and forever. Nit: the page's signature line is printed under the name `CraftEnchant` | https://warcraft.wiki.gg/wiki/API_C_TradeSkillUI.CraftRecipe |
| 63 | SendMail | VERIFIED | `noscript` only; 9.1.5; repeated calls ignored until MAIL_SEND_SUCCESS or MAIL_FAILED; listed for forever | https://warcraft.wiki.gg/wiki/API_SendMail |
| 64 | Instance | VERIFIED | Ten instances per hour per account; Follower Dungeons 50 per day; 2014-04-07 hotfix 5 to 10; statement that classic and modern modes share 10 per hour "as of the Midnight era", citing Blizzard support article 10994 dated 2026-01-25; raid lock Tuesday, heroics 4:00 | https://warcraft.wiki.gg/wiki/Instance |
| 65 | C_AuctionHouse.CalculateItemDeposit | PARTLY | Function and duration codes confirmed, listed for forever. The versions on the page are "added in" versions (8.3.0, 1.60.1, 4.4.2), not "retail 12.1.5" as crafting_strategies.md writes | https://warcraft.wiki.gg/wiki/API_C_AuctionHouse.CalculateItemDeposit |
| 66 | Concentration | VERIFIED | Cap 1,000; one per six minutes; added 11.0.0 | https://warcraft.wiki.gg/wiki/Concentration |
| 67 | Legacy loot (Loot, section Legacy Loot Mode) | VERIFIED | 10 levels above content; 8.0.1 pre-patch; 12.0.1 covers through Dragonflight | https://warcraft.wiki.gg/wiki/Loot |
| 68 | C_Item.GetItemInfo | VERIFIED | Return 11 `sellPrice` in copper, 0 when unsellable | https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfo |

### 1g. Community (spot-checked)

| # | Source | Verdict | Note | Verified against |
|---|---|---|---|---|
| 69 | Timesaver.gg, "WoW Forever Cooldowns for Gold" (2026-11-12) | PARTLY | Exists; figures match (Arcanite about 47 h, Mooncloth about 95 h, Salt Shaker about 71 h; +12.61 / +9.62 / +4.05 gold per day; raids 9 December). Conflict of interest: the site sells WoW Forever gold, power leveling and profession kits. The article states it tested nothing in game and that prices are asking-price medians. Number mismatch: the notes say 40-70 units listed "per region"; the article gives 66, 43 and 39 units across 5 sampled US markets | https://timesaver.gg/blog/wow-forever-profession-cooldowns-gold |
| 70 | Gamingcy, Midnight dual gathering | VERIFIED | Declines to give a gold-per-hour figure; 40 points each for mounted gathering; dates match. Conflict of interest (sells gold and boosts), which farming.md discloses | https://gamingcy.com/blog/midnight-dual-gathering |
| 71 | NoobToBoss, Classic mage gold farming guide | PARTLY | Ranges match. The 50-80 figure is a general Zul'Farrak estimate, not graveyard-specific; the page's Dire Maul figures are internally inconsistent between table and text; no methodology, sample or date; states a five-per-hour lockout | https://noobtoboss.com/wow-classic-mage-gold-farming-guide/ |
| 72 | Blizzard forum thread "What are the rules on hyperspawn farming?" (583706) | VERIFIED | Player thread, July to October 2020; no staff post among the 20 posts loaded (of 29). Community tier is right | https://us.forums.blizzard.com/en/wow/t/what-are-the-rules-on-hypserspawn-farming/583706 |
| 73 | Engadget / WoW Insider, Berntsen, "Gold Capped: TradeSkillMaster advanced guide" (2011-03-21) | VERIFIED | Min buyout for sale price, market value for materials, optional 5% profit reduction setting, recraft below three, glyph caveat | https://www.engadget.com/2011-03-21-gold-capped-tradeskillmaster-advanced-guide.html |
| 74 | Blizzard support article 10994 (instance limits) | UNREACHABLE | Redirects to a Battle.net login. The notes did not rely on it; the wiki (row 64) cites it | https://us.support.blizzard.com/en/help/article/10994 |

Not re-checked (outside the spot-check scope, no addon design constant depends on them): Engadget 2010 Saronite column; Method.gg (three pages); WoW-Professions; Timesaver Classic Era guide; TwistedVoxel; PC Games; Warcraft Tavern; Wowhead Maraudon guide; CurseForge pages for RareScanner, HandyNotes, Routes, FarmHud, MoneyLooter, LootAppraiser, GatherMate2_Data; TSM docs for groups, ledger, auctioning, shopping, sniper, value sources, external sources; other Saddlebag wiki pages; Azeroth Auction Assassin README; wiki pages for Prospecting, Milling, Disenchanting (the tables page was confirmed to exist with its out-of-date banner; row values not re-read), Transmutation, Mooncloth, limited supply, specializations, Herb, Crafting Orders.

---

## 2. Corrections the report must apply

### Provenance and tier labels
1. crafting_strategies.md, header note and every "[tool source, legacy TSM 2.8.3 fork]" tag: relabel as "third-party private-server port (TSM Revived for Ascension, based on TSM 2.8.3)". It is not a GitHub fork and may carry porter edits. Present its defaults and rate tables as legacy third-party values, never as "TSM's" current defaults.
2. tools_and_algorithms.md section 1, Keoo88 `Util.lua` line: add that the code block states it was written from the TSM docs, so it repeats the docs article and does not independently confirm it. The first-party evidence for the market value algorithm is the 2021 support article alone.
3. tools_and_algorithms.md section 1, weights line: keep the "unverified third-party claim" label and do not present the 15-number array as TSM's weights. If the addon needs weights, describe them as "weights used by one backport, consistent with the documented half-life".
4. tools_and_algorithms.md section 2: state plainly that all Auctionator storage and API facts come from a private-server port of version 9.1.3 (about five years old) and that the vendor-price API functions are known only from their use in CraftSim.
5. tools_and_algorithms.md section 4, the two Blizzard API forum lines: delete "role not labelled". Both posters carry the forum title "Blizzard Developer" and the staff flag. Move the Last-Modified statement to "Araspir's reply of 2020-02-16 in the same thread".
6. tools_and_algorithms.md section 5: relabel the two NIST entries from [official] to "government reference handbook". They are not Blizzard sources and not peer-reviewed papers.
7. farming.md: relabel the LootAppraiser Reloaded and GatherMate2 raw-file citations from [tool docs] to [source code].
8. farming.md Gaps: Lehdonvirta and Ernkvist is an institutional report, and 27361 is its repository handle, not a report number. Ahmad et al.: DOI is 10.1109/CSE.2009.307.
9. tools_and_algorithms.md section 3: the Journalator link works only by redirect to `TheMouseNest/Journalator`; update the URL and soften "the organisation still hosts side projects".

### Claims stronger than the source
10. crafting_strategies.md section 4 takeaway ("priced by the market to within roughly the 5% auction cut, as a peer-reviewed measurement ... found"): soften. The paper shows one essence pair with modal prices at exact parity and mean prices about 5% apart, from a third-party price site, and explains the gap by supply of Greater essences. Linking the gap to the 5% cut is the notes' inference; say so.
11. crafting_strategies.md section 4, Kosminsky line: remove the 13 September to 13 October 2008 window from the essence test. That window is stated for the netherweave tables; the essence table has a different data source and no dates.
12. crafting_strategies.md section 10, Kosminsky line: add that the price-stability test gave a non-monotonic result (medium-population servers least stable) and that the study covers six servers for one month. Do not lean on it for "margins trend toward the 5% cut".
13. crafting_strategies.md section 6, Kosminsky line: add that R2 = .993 comes from a quadratic through about six points.
14. tools_and_algorithms.md section 5 inference citing Conlon and Mortimer: mark as analogy (vending machine stock-outs), abstract-only.
15. farming.md, "How experienced farmers choose" takeaway ("Blizzard's own posts confirm that instance caps and layer-change cooldowns exist specifically to limit repetitive farming"): soften. The instance post gives exploitative and automated gameplay as the reason; the layer post only says it restricts frequent layer-hopping. The "limit farming" wording is the wiki's.
16. tools_and_algorithms.md section 6 takeaway ("every money-moving action ... needs a hardware event"): restrict to the functions the wiki tags (`PostItem`, `PostCommodity`, `PlaceBid`, `StartCommoditiesPurchase`, `CancelAuction`). `ConfirmCommoditiesPurchase`, `SendMail` (noscript only) and `CraftRecipe` carry no hardware-event tag. Add that all of this is wiki documentation of retail behaviour and has not been checked in a Forever client.

### WoW Forever claims
17. crafting_strategies.md section 1 inference ("Classic/Forever (no procs): profit = yield x sellPrice x 0.95 - matCost") and every other 0.95 or 15/30/60% deposit applied to Forever: mark as unverified. Evidence for a 5% cut on Forever is a third-party README and a gold-selling blog; the wiki fee table is a retail page with an out-of-date banner that itself recalls a 15% cut on the former neutral houses, and Forever is reported to have neutral houses. The addon should read the deposit from the client and keep the cut configurable per house.
18. tools_and_algorithms.md section 6 inference ("Classic-era getAll techniques do not apply there") and section 7: soften to "the wiki lists the modern auction functions for the forever game type and does not list `QueryAuctionItems`". This is a template listing, not a client test, and it contradicts this project's own Forever notes (`.agents/skills/wow-addon-issue-work/focus/auction-forever.md`), which document a paged `QueryAuctionItems` path for Forever. Keep runtime detection of both APIs.
19. tools_and_algorithms.md section 5 (auction durations) and section 6: 12/24/48 h on Forever follows only from the same wiki listing; the 15-minute replicate throttle on Forever is likewise unverified. Say so next to each number.
20. tools_and_algorithms.md section 7 and crafting_strategies.md sections 3, 4, 8, 9: every Forever economic fact (cooldown lengths, Bind on Pickup patterns, Legacy perk, house count per region, hourly API data) has exactly one source, and that source is either a gold seller or a one-star fork. Label each "single source, unverified" and name the conflict of interest where it applies.
21. crafting_strategies.md sections 3, 9, 10 ("only 40-70 units listed per region"): fix to "39 to 66 units across the 5 US markets the article sampled".
22. crafting_strategies.md section 1 (`CalculateItemDeposit` "listed for the retail (12.1.5) ... builds"): fix to "listed for standard (added 8.3.0), forever (1.60.1), mists (4.4.2)".

### Numbers and contradictions
23. tools_and_algorithms.md section 6, `PlaceBid`: the wiki text says gold only; the notes say whole silver. Write "whole silver per PostItem; the PlaceBid page says gold only" or test in client.
24. crafting_strategies.md section 2: add the second table conflict. BCC-Auctionator's reference row gives Infinite Dust for ilvl 121-151 at 1-3 (expected 1.5 dust per item at 75%), while the TSM port and the wiki give 130-151 at 2-3 (1.875). The worked ring example uses 1.875; mark it as one of two published values.
25. crafting_strategies.md section 1, CraftSim with-stats line: add that the deposit term is subtracted twice in that code path, so an addon should not copy the expression literally.
26. farming.md, instance caps: four sources disagree (Blizzard 2020: 5 per hour plus 30 per day on Classic; wiki 2026: 10 per hour for classic and modern; LootAppraiser: 10; NoobToBoss: 5). Blizzard's current support article could not be opened by either the notes or this audit. Keep the cap configurable and state that no value for Forever is sourced.
27. farming.md, NoobToBoss list: change "Zul'Farrak graveyard: 50-80" to "Zul'Farrak (general estimate)"; note that the Dire Maul figures differ between the page's table and text.

### Gold-per-hour labelling
28. farming.md, "Concrete examples" inferences ("figures cluster between 25 and 120 gold per hour"): add "self-reported, unverified" inline; the label is currently only on the list above it.
29. crafting_strategies.md sections 3 and 4, Timesaver gold-per-day and per-use figures: these carry "unverified community claim" but not the required "self-reported, unverified" label, and not the fact that the publisher sells gold. Add both on each line.
30. farming.md, Castronova line: add that USD 3.42 per hour is an EverQuest figure from an abstract and is not a WoW gold-per-hour measurement (the Gaps say this; the finding line should too).

Project note that follows from row 50, not a new finding: the wiki treats `_Mainline.toc` as a family fallback that also matches Forever and lists Midnight at interface 120105 with a dedicated `_Standard` suffix. This project's AGENTS.md describes `_Mainline` as retail with `120000, 120001`. The game-specific `_Forever` and `_Camelot` files take priority on Forever, so nothing breaks there, but the description and the retail interface numbers are worth a check against a live client.

---

## 3. Safe to rely on

Algorithm constants, read from the cited files in this audit.

TSM market value (first-party support article, 2021; steps only, no code):
- Sort prices ascending. Consider at most the lowest 30% of auctions.
- After the first 15% of auctions, a rise of 20% or more between consecutive prices ends the set.
- Compute mean and standard deviation; drop prices more than 1.5 standard deviations from the mean; average the rest.
- Average scans within a day; final value is a recency-weighted average of the previous 14 days plus today, half-life a little over 2 days. Exact daily weights are not published in text.
- Worked example result 14.5.

CraftSim (official repository, current, retail only):
- Auction cut multiplier 0.95.
- Chance = rating / 1100 (multicraft), / 900 (resourcefulness), / 1000 (ingenuity); same for Dragonflight, The War Within and Midnight.
- Multicraft constants by base yield: 1 gives 2.1, 2 gives 1.83, 5 gives 1.875, otherwise 2.5. Max extra = constant x base yield x (1 + bonus); expected extra on a proc = (1 + max extra) / 2. Marked in the source as an approximation.
- Resourcefulness saving on a proc = required-reagent cost x 0.30 x (1 + bonus). Marked in the source as an approximation of 20-40%.
- Gold per concentration point = average profit with concentration / (cost x (1 - ingenuity chance x (0.5 + bonus))).
- Concentration raises quality by exactly one tier, capped at the maximum.
- Defaults: price expression `first(DBRecent, DBMinbuyout)`, vendor price first; deposit off; sale-rate threshold 0.1 for queueing.

Legacy TSM 2.8.3 (third-party private-server port; legacy behaviour only):
- Material cost default `min(dbmarket, crafting, vendorbuy, convert(dbmarket))`; craft value default `dbminbuyout`; profit deducts no cut unless `profitPercent` is set.
- Restock: queue = max(maxRestock - inventory, 0); zero if below minRestock; only if profit >= minProfit. Legacy defaults 1 / 3 / 100g. Current TSM docs give 10 / 20 / 100g.
- Cooldown recipes are skipped as a cost basis when another recipe exists.
- Destroy value = sum(rate x price of output), outputs priced at DBMarket; prospect rates are per 5 ore.

Other scan-only price models:
- aux (official, Classic 1.13): daily minimum unit buyout, at most 11 daily points, weight 0.99 per day of age, weighted median.
- Auctionator (9.1.3 port): per key, last seen minimum plus per-day low of lows, high of lows, max quantity; API returns the last seen minimum; undercut by percent or fixed amount, never below 1 silver.
- RECrystallize (official): lowest unit price per variant plus last-seen time.
- Oribos Exchange (official): 4-day median per house, median across the region, days-since-seen with 251 and 252 as special values.
- The Undermine Journal (author's own definition): cost per unit of the cheapest 15% of quantity.

LootAppraiser Reloaded (official, current):
- Per hour = looted value / (now or pause start - session start - paused seconds) x 3600.
- Default price source `DBRegionMarketAvg`, a listing-based regional average; vendor price fallback; no cut, deposit or sale-rate adjustment anywhere in the valuation path.

Client rules documented by the reference wiki for retail:
- Auction cut 5%; deposit 15 / 30 / 60% of vendor price for 12 / 24 / 48 h, minimum 1 silver; deposit returned on sale, lost on expiry or cancel.
- `C_AuctionHouse.ReplicateItems`: 15 minutes between successful calls, account-wide.
- Legacy `QueryAuctionItems`: about 0.3 s between page queries, 15 minutes for getAll.
- Hardware event and no-script: `PostItem`, `PostCommodity`, `PlaceBid`, `StartCommoditiesPurchase`, `CancelAuction` (protected since 9.1.5); legacy `PostAuction`; `PlaceAuctionBid` since 2.0.
- No-script only: `SendBrowseQuery`, `SendMail`. No tag: `ConfirmCommoditiesPurchase`, `CraftRecipe`, `ReplicateItems`.
- Vendor price: item info return 11, in copper.

WoW Forever facts with a solid source (reference wiki, consistent with CurseForge, Undermine Exchange and wowauctions.net listings):
- Released 4 November 2026; internal name Camelot; interface 16001.
- TOC suffixes `_Forever` and `_Camelot`; `AllowLoadGameType` values forever and camelot; `_Mainline` is a lower-priority family suffix that also matches Forever; `_Standard` is the Midnight-only suffix.
- The wiki lists the modern `C_AuctionHouse` functions and `C_TradeSkillUI.CraftRecipe` for the forever game type (build 1.60.1, 69913). Listing only; behaviour and throttles are not confirmed for Forever.

Blizzard policy (official texts read in full):
- Add-ons must be free, with visible code, no in-game ads or donation requests, no negative impact on realms; Blizzard may disable functionality.
- EULA prohibits bots, exploits, gathering for sale outside the game, and services for payment.
- Input broadcasting and any automation or streamlining of multi-boxing is actionable (November 2020, extended May 2021).
- Blizzard Game Data API: per-connected-realm auctions endpoint since February 2020, hourly; regional commodities endpoint since 9.2.7 with quota cost 25.

Academic findings that hold as stated:
- Kosminsky: modal Lesser and Greater Planar Essence prices at exact 1:3 parity, mean prices about 5% apart (one pair, 2008, small sample).
- Morrison and Fontenla: price convergence across eight WoW worlds (abstract).
- Heeks: gold farming defined as real-money trade; role taxonomy; 2008 scale estimates flagged by the author as best guesses.

---

## 4. Counts per verdict

| Verdict | Count |
|---|---|
| VERIFIED | 59 |
| VERIFIED-ABSTRACT | 3 |
| PARTLY | 6 |
| UNSUPPORTED | 0 |
| NOT FOUND | 0 |
| UNREACHABLE | 6 |
| Total sources checked | 74 |

PARTLY: Kosminsky (row 1), backport weight table (28), PlaceBid wiki page (56), CalculateItemDeposit version labels (65), Timesaver Forever article (69), NoobToBoss guide (71).
UNREACHABLE: Leys et al. (8), Huber (9), Ahmad et al. (10), Lehdonvirta and Ernkvist (11), Altoholic GitHub search (25), Blizzard support article 10994 (74). None of the six carries a claim in the notes.

Downloaded files used for this audit are in /tmp/claude-1000/-home-jonas-dev-hobby-Addons-AuctionHelper/efbcf6c8-f367-49a4-a454-426f882cd7eb/scratchpad/ under `qa_dl`, `qa_pdf`, `qa_forum` and `qa_wiki`.
