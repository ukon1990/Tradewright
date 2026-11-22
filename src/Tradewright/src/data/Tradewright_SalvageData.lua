local _, Tradewright = ...

-- Researched salvage yields: what disenchanting, prospecting and milling give on average, looked up
-- on the web (reference wikis and published counts of outcomes; no table is taken from another
-- addon). They are estimates that stand in until outcomes counted in game replace them (see
-- SalvageLogic.Yield). Sources, their quality and where they disagree: docs/research/salvage-yields.md.
--
-- Every number is the quantity received per destroyed item: per piece of gear, per single ore, per
-- single herb (the sources give ore and herbs per cast of five; those are divided by five here).

local CLASSIC = 0

local STRANGE_DUST, SOUL_DUST, VISION_DUST, DREAM_DUST, ILLUSION_DUST = 10940, 11083, 11137, 11176, 16204
local LESSER_MAGIC, GREATER_MAGIC, LESSER_ASTRAL, GREATER_ASTRAL = 10938, 10939, 10998, 11082
local LESSER_MYSTIC, GREATER_MYSTIC, LESSER_NETHER, GREATER_NETHER = 11134, 11135, 11174, 11175
local LESSER_ETERNAL, GREATER_ETERNAL = 16202, 16203
local SMALL_GLIMMERING, LARGE_GLIMMERING, SMALL_GLOWING, LARGE_GLOWING = 10978, 11084, 11138, 11139
local SMALL_RADIANT, LARGE_RADIANT, SMALL_BRILLIANT, LARGE_BRILLIANT = 11177, 11178, 14343, 14344
local NEXUS_CRYSTAL = 20725

local UNCOMMON, RARE, EPIC = 2, 3, 4

local function gear(quality, isWeapon, fromLevel, toLevel, yield)
	return { expansionID = CLASSIC, quality = quality, isWeapon = isWeapon, fromLevel = fromLevel, toLevel = toLevel, yield = yield }
end

-- Uncommon gear gives dust, an essence or a shard: armor mostly dust, weapons mostly the essence.
local function uncommon(fromLevel, toLevel, armorYield, weaponYield)
	return gear(UNCOMMON, false, fromLevel, toLevel, armorYield), gear(UNCOMMON, true, fromLevel, toLevel, weaponYield)
end

-- Rare and epic gear gives the same whether weapon or armor.
local function anyGear(quality, fromLevel, toLevel, yield)
	return gear(quality, nil, fromLevel, toLevel, yield)
end

local classicDisenchant = {}
local function add(...)
	for _, row in ipairs({ ... }) do
		classicDisenchant[#classicDisenchant + 1] = row
	end
end

add(uncommon(5, 15,
	{ [STRANGE_DUST] = 1.2, [LESSER_MAGIC] = 0.3 },
	{ [STRANGE_DUST] = 0.3, [LESSER_MAGIC] = 1.2 }))
add(uncommon(16, 20,
	{ [STRANGE_DUST] = 1.875, [GREATER_MAGIC] = 0.3, [SMALL_GLIMMERING] = 0.05 },
	{ [STRANGE_DUST] = 0.5, [GREATER_MAGIC] = 1.125, [SMALL_GLIMMERING] = 0.05 }))
-- Weapons of item level 21 to 30: the published tables say astral essences, but outcomes counted on
-- Classic in 2019 and 2020 gave Greater Magic Essence only. The counted behaviour is used.
add(uncommon(21, 25,
	{ [STRANGE_DUST] = 3.75, [LESSER_ASTRAL] = 0.225, [SMALL_GLIMMERING] = 0.1 },
	{ [STRANGE_DUST] = 0.75, [GREATER_MAGIC] = 1.125, [SMALL_GLIMMERING] = 0.1 }))
add(uncommon(26, 30,
	{ [SOUL_DUST] = 1.125, [GREATER_ASTRAL] = 0.3, [LARGE_GLIMMERING] = 0.05 },
	{ [SOUL_DUST] = 0.3, [GREATER_MAGIC] = 1.125, [LARGE_GLIMMERING] = 0.05 }))
add(uncommon(31, 35,
	{ [SOUL_DUST] = 2.625, [LESSER_MYSTIC] = 0.3, [SMALL_GLOWING] = 0.05 },
	{ [SOUL_DUST] = 0.7, [LESSER_MYSTIC] = 1.125, [SMALL_GLOWING] = 0.05 }))
add(uncommon(36, 40,
	{ [VISION_DUST] = 1.125, [GREATER_MYSTIC] = 0.3, [LARGE_GLOWING] = 0.05 },
	{ [VISION_DUST] = 0.3, [GREATER_MYSTIC] = 1.125, [LARGE_GLOWING] = 0.05 }))
add(uncommon(41, 45,
	{ [VISION_DUST] = 2.625, [LESSER_NETHER] = 0.3, [SMALL_RADIANT] = 0.05 },
	{ [VISION_DUST] = 0.7, [LESSER_NETHER] = 1.125, [SMALL_RADIANT] = 0.05 }))
add(uncommon(46, 50,
	{ [DREAM_DUST] = 1.125, [GREATER_NETHER] = 0.3, [LARGE_RADIANT] = 0.05 },
	{ [DREAM_DUST] = 0.3, [GREATER_NETHER] = 1.125, [LARGE_RADIANT] = 0.05 }))
add(uncommon(51, 55,
	{ [DREAM_DUST] = 2.625, [LESSER_ETERNAL] = 0.3, [SMALL_BRILLIANT] = 0.05 },
	{ [DREAM_DUST] = 0.77, [LESSER_ETERNAL] = 1.125, [SMALL_BRILLIANT] = 0.03 }))
add(uncommon(56, 60,
	{ [ILLUSION_DUST] = 1.125, [GREATER_ETERNAL] = 0.3, [LARGE_BRILLIANT] = 0.05 },
	{ [ILLUSION_DUST] = 0.33, [GREATER_ETERNAL] = 1.125, [LARGE_BRILLIANT] = 0.03 }))
add(uncommon(61, 65,
	{ [ILLUSION_DUST] = 2.625, [GREATER_ETERNAL] = 0.5, [LARGE_BRILLIANT] = 0.05 },
	{ [ILLUSION_DUST] = 0.77, [GREATER_ETERNAL] = 1.875, [LARGE_BRILLIANT] = 0.03 }))

add(anyGear(RARE, 1, 25, { [SMALL_GLIMMERING] = 1 }))
add(anyGear(RARE, 26, 30, { [LARGE_GLIMMERING] = 1 }))
add(anyGear(RARE, 31, 35, { [SMALL_GLOWING] = 1 }))
add(anyGear(RARE, 36, 40, { [LARGE_GLOWING] = 1 }))
add(anyGear(RARE, 41, 45, { [SMALL_RADIANT] = 1 }))
add(anyGear(RARE, 46, 50, { [LARGE_RADIANT] = 1 }))
add(anyGear(RARE, 51, 55, { [SMALL_BRILLIANT] = 1 }))
add(anyGear(RARE, 56, 65, { [LARGE_BRILLIANT] = 0.995, [NEXUS_CRYSTAL] = 0.005 }))

add(anyGear(EPIC, 40, 45, { [SMALL_RADIANT] = 3 }))
add(anyGear(EPIC, 46, 50, { [LARGE_RADIANT] = 3 }))
add(anyGear(EPIC, 51, 55, { [SMALL_BRILLIANT] = 3 }))
add(anyGear(EPIC, 56, 60, { [NEXUS_CRYSTAL] = 1 }))
add(anyGear(EPIC, 61, 100, { [NEXUS_CRYSTAL] = 1.5 }))

local COPPER_ORE, TIN_ORE, IRON_ORE, MITHRIL_ORE, THORIUM_ORE = 2770, 2771, 2772, 3858, 10620
local MALACHITE, TIGERSEYE, SHADOWGEM, MOSS_AGATE, LESSER_MOONSTONE = 774, 818, 1210, 1206, 1705
local JADE, CITRINE, AQUAMARINE, STAR_RUBY = 1529, 3864, 7909, 7910
local BLUE_SAPPHIRE, LARGE_OPAL, AZEROTHIAN_DIAMOND, HUGE_EMERALD = 12361, 12799, 12800, 12364

-- From the reference wiki's table, which gives a chance per gem and no quantity; one gem is assumed.
-- Only the copper numbers are agreed on by every source found. For tin, iron and mithril others differ
-- by up to ten points per gem, and for thorium they contradict each other outright.
local COMMON_TIN, RARE_TIN = 0.375 / 5, 0.0333 / 5
local COMMON_IRON, RARE_IRON = 0.30 / 5, 0.05 / 5
local COMMON_MITHRIL, RARE_MITHRIL = 0.30 / 5, 0.025 / 5
local classicProspect = {
	[COPPER_ORE] = { [MALACHITE] = 0.5 / 5, [TIGERSEYE] = 0.5 / 5, [SHADOWGEM] = 0.1 / 5 },
	[TIN_ORE] = {
		[SHADOWGEM] = COMMON_TIN, [MOSS_AGATE] = COMMON_TIN, [LESSER_MOONSTONE] = COMMON_TIN,
		[JADE] = RARE_TIN, [CITRINE] = RARE_TIN, [AQUAMARINE] = RARE_TIN,
	},
	[IRON_ORE] = {
		[CITRINE] = COMMON_IRON, [LESSER_MOONSTONE] = COMMON_IRON, [JADE] = COMMON_IRON,
		[AQUAMARINE] = RARE_IRON, [STAR_RUBY] = RARE_IRON,
	},
	[MITHRIL_ORE] = {
		[CITRINE] = COMMON_MITHRIL, [STAR_RUBY] = COMMON_MITHRIL, [AQUAMARINE] = COMMON_MITHRIL,
		[BLUE_SAPPHIRE] = RARE_MITHRIL, [LARGE_OPAL] = RARE_MITHRIL, [AZEROTHIAN_DIAMOND] = RARE_MITHRIL, [HUGE_EMERALD] = RARE_MITHRIL,
	},
	-- The wiki also lists Outland gems at under 2 % each; WoW Forever has classic items only.
	[THORIUM_ORE] = {
		[STAR_RUBY] = 0.30 / 5, [BLUE_SAPPHIRE] = 0.16 / 5, [LARGE_OPAL] = 0.16 / 5, [AZEROTHIAN_DIAMOND] = 0.16 / 5, [HUGE_EMERALD] = 0.16 / 5,
	},
}

--- Researched yields per game client, in the shape SalvageLogic.ResearchedYield reads.
Tradewright.SALVAGE_DATA = {
	forever = { disenchant = classicDisenchant, prospect = classicProspect },
	-- Retail ships none: no yields were found outside other addons' tables. Counted outcomes fill it.
	retail = {},
}
