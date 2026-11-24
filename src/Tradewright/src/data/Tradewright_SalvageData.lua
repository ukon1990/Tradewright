local _, Tradewright = ...

-- Researched salvage yields: what disenchanting, prospecting and milling give on average, looked up
-- on the web (reference wikis and published counts of outcomes). They are estimates that stand in
-- until outcomes counted in game replace them (see SalvageLogic.Yield). Sources, their quality and
-- where they disagree: docs/research/salvage-yields.md.
--
-- Each material of a disenchant row is its chance per disenchant and the count it gives then
-- (`{ chance, min, max }`), as the reference tables state them; the average per item follows.

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

-- One material of a row: the chance one disenchant gives it, and how many it gives then.
local function drop(chance, min, max)
	return { chance = chance, min = min, max = max or min }
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
	{ [STRANGE_DUST] = drop(0.8, 1, 2), [LESSER_MAGIC] = drop(0.2, 1, 2) },
	{ [STRANGE_DUST] = drop(0.2, 1, 2), [LESSER_MAGIC] = drop(0.8, 1, 2) }))
add(uncommon(16, 20,
	{ [STRANGE_DUST] = drop(0.75, 2, 3), [GREATER_MAGIC] = drop(0.2, 1, 2), [SMALL_GLIMMERING] = drop(0.05, 1) },
	{ [STRANGE_DUST] = drop(0.2, 2, 3), [GREATER_MAGIC] = drop(0.75, 1, 2), [SMALL_GLIMMERING] = drop(0.05, 1) }))
-- Weapons of item level 21 to 30: the published tables say astral essences, but outcomes counted on
-- Classic in 2019 and 2020 gave Greater Magic Essence only. The counted behaviour is used.
add(uncommon(21, 25,
	{ [STRANGE_DUST] = drop(0.75, 4, 6), [LESSER_ASTRAL] = drop(0.15, 1, 2), [SMALL_GLIMMERING] = drop(0.1, 1) },
	{ [STRANGE_DUST] = drop(0.15, 4, 6), [GREATER_MAGIC] = drop(0.75, 1, 2), [SMALL_GLIMMERING] = drop(0.1, 1) }))
add(uncommon(26, 30,
	{ [SOUL_DUST] = drop(0.75, 1, 2), [GREATER_ASTRAL] = drop(0.2, 1, 2), [LARGE_GLIMMERING] = drop(0.05, 1) },
	{ [SOUL_DUST] = drop(0.2, 1, 2), [GREATER_MAGIC] = drop(0.75, 1, 2), [LARGE_GLIMMERING] = drop(0.05, 1) }))
add(uncommon(31, 35,
	{ [SOUL_DUST] = drop(0.75, 2, 5), [LESSER_MYSTIC] = drop(0.2, 1, 2), [SMALL_GLOWING] = drop(0.05, 1) },
	{ [SOUL_DUST] = drop(0.2, 2, 5), [LESSER_MYSTIC] = drop(0.75, 1, 2), [SMALL_GLOWING] = drop(0.05, 1) }))
add(uncommon(36, 40,
	{ [VISION_DUST] = drop(0.75, 1, 2), [GREATER_MYSTIC] = drop(0.2, 1, 2), [LARGE_GLOWING] = drop(0.05, 1) },
	{ [VISION_DUST] = drop(0.2, 1, 2), [GREATER_MYSTIC] = drop(0.75, 1, 2), [LARGE_GLOWING] = drop(0.05, 1) }))
add(uncommon(41, 45,
	{ [VISION_DUST] = drop(0.75, 2, 5), [LESSER_NETHER] = drop(0.2, 1, 2), [SMALL_RADIANT] = drop(0.05, 1) },
	{ [VISION_DUST] = drop(0.2, 2, 5), [LESSER_NETHER] = drop(0.75, 1, 2), [SMALL_RADIANT] = drop(0.05, 1) }))
add(uncommon(46, 50,
	{ [DREAM_DUST] = drop(0.75, 1, 2), [GREATER_NETHER] = drop(0.2, 1, 2), [LARGE_RADIANT] = drop(0.05, 1) },
	{ [DREAM_DUST] = drop(0.2, 1, 2), [GREATER_NETHER] = drop(0.75, 1, 2), [LARGE_RADIANT] = drop(0.05, 1) }))
add(uncommon(51, 55,
	{ [DREAM_DUST] = drop(0.75, 2, 5), [LESSER_ETERNAL] = drop(0.2, 1, 2), [SMALL_BRILLIANT] = drop(0.05, 1) },
	{ [DREAM_DUST] = drop(0.22, 2, 5), [LESSER_ETERNAL] = drop(0.75, 1, 2), [SMALL_BRILLIANT] = drop(0.03, 1) }))
add(uncommon(56, 60,
	{ [ILLUSION_DUST] = drop(0.75, 1, 2), [GREATER_ETERNAL] = drop(0.2, 1, 2), [LARGE_BRILLIANT] = drop(0.05, 1) },
	{ [ILLUSION_DUST] = drop(0.22, 1, 2), [GREATER_ETERNAL] = drop(0.75, 1, 2), [LARGE_BRILLIANT] = drop(0.03, 1) }))
add(uncommon(61, 65,
	{ [ILLUSION_DUST] = drop(0.75, 2, 5), [GREATER_ETERNAL] = drop(0.2, 2, 3), [LARGE_BRILLIANT] = drop(0.05, 1) },
	{ [ILLUSION_DUST] = drop(0.22, 2, 5), [GREATER_ETERNAL] = drop(0.75, 2, 3), [LARGE_BRILLIANT] = drop(0.03, 1) }))

add(anyGear(RARE, 1, 25, { [SMALL_GLIMMERING] = drop(1, 1) }))
add(anyGear(RARE, 26, 30, { [LARGE_GLIMMERING] = drop(1, 1) }))
add(anyGear(RARE, 31, 35, { [SMALL_GLOWING] = drop(1, 1) }))
add(anyGear(RARE, 36, 40, { [LARGE_GLOWING] = drop(1, 1) }))
add(anyGear(RARE, 41, 45, { [SMALL_RADIANT] = drop(1, 1) }))
add(anyGear(RARE, 46, 50, { [LARGE_RADIANT] = drop(1, 1) }))
add(anyGear(RARE, 51, 55, { [SMALL_BRILLIANT] = drop(1, 1) }))
add(anyGear(RARE, 56, 65, { [LARGE_BRILLIANT] = drop(0.995, 1), [NEXUS_CRYSTAL] = drop(0.005, 1) }))

add(anyGear(EPIC, 40, 45, { [SMALL_RADIANT] = drop(1, 2, 4) }))
add(anyGear(EPIC, 46, 50, { [LARGE_RADIANT] = drop(1, 2, 4) }))
add(anyGear(EPIC, 51, 55, { [SMALL_BRILLIANT] = drop(1, 2, 4) }))
add(anyGear(EPIC, 56, 60, { [NEXUS_CRYSTAL] = drop(1, 1) }))
add(anyGear(EPIC, 61, 100, { [NEXUS_CRYSTAL] = drop(1, 1, 2) }))

--- Researched yields per game client, in the shape SalvageLogic.ResearchedYield reads.
Tradewright.SALVAGE_DATA = {
	-- WoW Forever has no Jewelcrafting or Inscription, so only disenchanting.
	forever = { disenchant = classicDisenchant },
	-- Retail ships none yet; counted outcomes fill it.
	retail = {},
}
