# Salvage yields: what the published numbers are worth

Researched 22 November 2026 for E18 (F137). Question: which disenchanting, prospecting and milling yields are solid enough to ship as starting values, for WoW Forever (classic items only, plus its own new ones) and for retail (interface 12.x).

Rule set by the user: nothing shipped is taken from another addon. Addon tables appear below only as a comparison that shows how far published numbers agree; the shipped numbers come from the reference wikis and from published counts of outcomes.

Short answer: the classic disenchant table is well supported, including by one counted data set. Classic prospecting is agreed for copper only and contradictory for thorium. For retail, almost everything comes from one addon's data files with no stated origin, and nothing usable exists for the two current expansions. No source at any tier is game data or a Blizzard statement: these loot tables live on the server.

## Evidence labels

- **Counted**: outcomes logged by players in game and published as raw data
- **Addon data**: a table in an addon's source, read as a raw file; the origin of the numbers is usually not stated
- **Emulator**: a private-server database, a community reconstruction and not Blizzard data
- **Reference wiki**: warcraft.wiki.gg and Wowpedia (one page lineage)
- **Guide**: a commercial guide or gold site, no stated data origin

Sources that copy each other are counted once. For classic disenchanting, the wiki, the Auctionator table, the legacy TradeSkillMaster port and both emulator databases match number for number and are treated as one lineage.

## Classic disenchanting (shipped for Forever)

The table shipped in `Tradewright_SalvageData.lua` is the reference wikis' table: [Warcraft Wiki, Disenchanting tables](https://warcraft.wiki.gg/wiki/Disenchanting_tables) (marked out of date by the wiki itself) and [Wowpedia](https://wowpedia.fandom.com/wiki/Disenchanting_tables). The same numbers, compared only, are in [Auctionator for TBC Classic](https://raw.githubusercontent.com/Auctionator/BCC-Auctionator/main/Source/Constants/DisenchantingProbabilities.lua) (addon data, archived 2021), [TradeSkillMaster 4.14 Vanilla table](https://raw.githubusercontent.com/seanmarthur/TradeSkillMaster/HEAD/LibTSMData/Destroy/Disenchant.lua) (addon data, third-party mirror) and the [cmangos classic database](https://github.com/cmangos/classic-db) (emulator).

The one independent check is counted: about 19,800 uncommon disenchants logged with Enchantrix on WoW Classic in 2019 and 2020 ([wow_classic_de_table](https://github.com/alex-berliner/wow_classic_de_table); its readme says some logs may come from retail players). It confirms the table within a few points in every bracket with a usable sample (for example armor of item level 41 to 45: 75.0 % dust, 20.1 % essence, 4.9 % shard over 3,461 disenchants, against 75 / 20 / 5).

Where sources disagree, and what is shipped:

| Case | Sources | Shipped |
| --- | --- | --- |
| Uncommon weapons, item level 21 to 30: which essence | Astral in the wiki, TSM, Auctionator and emulators; Greater Magic in Wowpedia and in the counted data (1,114 disenchants, no astral essence at all), with two unanswered player bug reports on Blizzard's forums | Greater Magic (the only counted evidence) |
| Uncommon weapons, item level 51 and up: shard chance | 3 % in the wikis and emulators; 5 % in the addon tables; counted 3.0 to 3.3 % | 3 %, dust 22 % (the wikis) |
| Uncommon armor, item level 51 and up: shard chance | 5 % everywhere; counted 2.8 to 3.7 % | 5 % (no written source says otherwise) |
| Epic gear, item level 56 and up | Nexus Crystal in every table; counted data from before Classic's phase 5 shows Large Brilliant Shards | Nexus Crystal |
| Nexus Crystal from rare gear, item level 56 to 65 | 0.5 % in most tables; none below 66 in the emulator; none counted (before phase 5) | 0.5 % |
| Greater Eternal Essence at item level 61 to 65 | 2 to 3 everywhere; exactly 2 in the emulator; counted mean 2.4 to 2.5 | 2 to 3 |

Not used: the emulator databases point shields and held-in-off-hand items at the weapon tables. No other source mentions it, so those items are read as armor.

Whether WoW Forever uses these tables at all is not known. Its own new items appear in no source.

## Classic prospecting (shipped for Forever)

Chances are per prospect of five ore; the data file stores them per single ore.

| Ore | Agreement | Shipped (per prospect) |
| --- | --- | --- |
| Copper | Every source: Malachite 50 %, Tigerseye 50 %, Shadowgem 10 % | the same |
| Tin, Iron, Mithril | Common gems 30 to 40 % each depending on the source, rare gems 2 to 5 % | Wowpedia: common gems 37.5 % / 30 % / 30 % each, rare gems 3.33 % / 5 % / 2.5 % each |
| Thorium | Contradictory: Star Ruby 10 to 30 %, each of the four others 15 to 31 %; Outland gems listed by some and not by others | Wowpedia: Star Ruby 30 %, the others 16 % each; its Outland gems (1.66 % each) left out, as Forever has classic items only |

Shipped from [Wowpedia, Prospecting](https://wowpedia.fandom.com/wiki/Prospecting) (reference wiki, marked as needing an update; it gives a chance per gem and no quantity, so one gem per hit is assumed). Compared only: [TradeSkillMaster 4.14 BCC table](https://raw.githubusercontent.com/seanmarthur/TradeSkillMaster/HEAD/LibTSMData/Destroy/Prospect.lua) (addon data; its non-round rates suggest counted data but it does not say), the [legacy TradeSkillMaster port](https://raw.githubusercontent.com/BanditTech/TradeSkillMaster/main/TradeSkillMaster/Data/Conversions.lua) (addon data, a private server's port), and the cmangos TBC and AzerothCore databases (emulators). No counted prospecting data was found. Prospecting is a Burning Crusade feature; whether and how Forever implements it for classic ore is not established by any source.

Everything except the copper row is a weak estimate and is expected to be replaced by counted outcomes.

## Retail (nothing shipped)

Decided by the user: retail ships no researched yields and fills from counted outcomes, since the only numbers found are other addons' tables. What follows records why.

One source carries nearly all of it: the data files of the current TradeSkillMaster (4.14.78, interface 12.1.5, read from a [GitHub mirror](https://github.com/luhao007/WoW-Addons/tree/master/AddOns/TradeSkillMaster/LibTSMData/Destroy)). It covers Classic through Dragon Isles for all three actions.

- **Origin and licence**: the files do not say where the numbers come from, and the addon is marked All Rights Reserved.
- **Errors found in it**: Cobalt and Titanium uncommon gems at 2.5 per prospect against their own 23.5 % chance; Gloom Dust chances above 1; Legion prospecting rows that contradict themselves and look far too low.
- **Cross-checks**: prospecting for Classic to Cataclysm ore roughly matches a guide site's Classic tables ([wow-professions](https://www.wow-professions.com/wotlk/prospecting-table-wotlk-classic), guide, no stated origin). Disenchanting has one independent comparison, Enchantrix ([Auctioneer fork](https://raw.githubusercontent.com/NoobyGains/Auctioneer-Forever/HEAD/Enchantrix/EnxConstants.lua), addon data from player contributions), which agrees on which material comes out but differs on amounts from Draenor on and calls its own Dragon Isles and Khaz Algar rows placeholders. Milling has no independent check.
- **Retail disenchanting is keyed differently**: by the item's expansion, then quality, weapon or armor, and an item level bracket inside that expansion. The classic item level table does not describe retail, where classic gear has been squished to low item levels.
- **Old expansions after patch 10.0**: nothing shows that the old rates still hold now that each expansion has its own prospecting and milling recipe, beyond the fact that TradeSkillMaster still ships them.
- **Dragon Isles and later**: yields depend on skill, specialization, reagent quality and resourcefulness. No source states which of those its numbers assume.
- **Khaz Algar**: no numbers for prospecting or milling at any tier; disenchanting only as a self-declared placeholder and a guess that disagree.
- **Midnight**: prospecting and milling from one community spreadsheet embedded in an addon (All Rights Reserved, assumptions unstated); disenchanting from one addon with round numbers and no origin.

One finding changes code and not data: Khaz Algar and Midnight milling destroys ten herbs per craft, not five ([Warcraft Wiki, Midnight Milling](https://warcraft.wiki.gg/wiki/Midnight_Milling)). The addon reads the quantity from the game and assumes five only when the game does not say.

## What this means for the addon

- Forever ships the classic disenchant table and the classic prospecting table, all shown as estimates
- Counted outcomes replace a researched yield from 20 casts on (`SalvageLogic.TRUSTED_CASTS`), which also settles the disputed rows above for whichever client the player is on
- A few test disenchants of green weapons of item level 21 to 30, and of epic gear, on Forever would settle the two largest doubts
- Retail ships nothing: no numbers were found outside other addons' tables, and none at all for current content
