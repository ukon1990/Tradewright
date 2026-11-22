local _, AuctionHelper = ...

--- Pure helpers for profession skill-ups: which colour a recipe has at a skill level and how likely
--- one craft is to give a skill point. No WoW API.
---
--- The game reports only the skill at which a recipe turns grey, and its colour at the current skill.
--- A recipe is orange up to its yellow start, turns green halfway between the yellow start and the
--- grey level, and gives nothing from the grey level on. So the yellow start is the one unknown. It
--- begins as a guess and is narrowed by every colour the game has shown for the recipe:
--- `observation = { yellowStartMin, yellowStartMax }`, small enough to save per recipe.
local SkillUpLogic = {}
AuctionHelper.SkillUpLogic = SkillUpLogic

-- Guess for how far below the grey level a recipe turns yellow, used until the game has shown more.
-- 15 matched the colours of most learned recipes in a saved WoW Forever scan; recipes vary widely.
SkillUpLogic.DEFAULT_YELLOW_SPAN = 15

-- The game's `relativeDifficulty` values (Enum.TradeskillRelativeDifficulty).
local DIFFICULTY_NAMES = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

function SkillUpLogic.DifficultyName(relativeDifficulty)
	return DIFFICULTY_NAMES[tonumber(relativeDifficulty)]
end

-- The green start that follows from a yellow start: halfway to grey, rounded up.
local function greenStartFor(yellowStart, greyLevel)
	return math.ceil((yellowStart + greyLevel) / 2)
end

-- What seeing `difficulty` at `skill` says about the yellow start: `min, max` (either may be nil).
local function yellowStartLimits(greyLevel, skill, difficulty)
	if difficulty == "optimal" then
		return skill + 1, nil
	elseif difficulty == "medium" then
		-- Still yellow, so the green start is above this skill.
		return 2 * skill - greyLevel + 1, skill
	elseif difficulty == "easy" then
		return nil, 2 * skill - greyLevel
	end
	return nil, nil
end

-- Raises the lowest possible yellow start. A highest value that now lies below it is contradicted
-- and takes what this sighting says instead.
local function raiseYellowStartMin(observation, seenMin, seenMax)
	if not seenMin or (observation.yellowStartMin and seenMin <= observation.yellowStartMin) then
		return
	end
	observation.yellowStartMin = seenMin
	if observation.yellowStartMax and observation.yellowStartMax < seenMin then
		observation.yellowStartMax = seenMax
	end
end

local function lowerYellowStartMax(observation, seenMin, seenMax)
	if not seenMax or (observation.yellowStartMax and seenMax >= observation.yellowStartMax) then
		return
	end
	observation.yellowStartMax = seenMax
	if observation.yellowStartMin and observation.yellowStartMin > seenMax then
		observation.yellowStartMin = seenMin
	end
end

--- The observation narrowed by one more sighting of the recipe's colour. A sighting that contradicts
--- what was stored wins, because the stored one may come from before a game patch.
function SkillUpLogic.RecordObservation(observation, greyLevel, skill, difficulty)
	observation = observation or {}
	local narrowed = { yellowStartMin = observation.yellowStartMin, yellowStartMax = observation.yellowStartMax }
	local seenMin, seenMax = yellowStartLimits(greyLevel, skill, difficulty)
	raiseYellowStartMin(narrowed, seenMin, seenMax)
	lowerYellowStartMax(narrowed, seenMin, seenMax)
	return narrowed
end

-- Best single value for the yellow start, and whether it is known exactly.
local function yellowStartEstimate(greyLevel, observation)
	local lowest, highest = observation and observation.yellowStartMin, observation and observation.yellowStartMax
	local guess = greyLevel - SkillUpLogic.DEFAULT_YELLOW_SPAN
	if lowest and highest then
		return math.floor((lowest + highest) / 2), lowest == highest
	elseif lowest then
		return math.max(lowest, guess), false
	elseif highest then
		return math.min(highest, guess), false
	end
	return guess, false
end

--- Where the recipe changes colour: `{ yellowStart, greenStart, greyStart, estimated }`.
--- `estimated` is false only when the game's colours have pinned the yellow start to one value.
function SkillUpLogic.DifficultyBounds(greyLevel, observation)
	local yellowStart, exact = yellowStartEstimate(greyLevel, observation)
	yellowStart = math.min(yellowStart, greyLevel)
	return {
		yellowStart = yellowStart, greenStart = greenStartFor(yellowStart, greyLevel),
		greyStart = greyLevel, estimated = not exact,
	}
end

function SkillUpLogic.DifficultyAt(bounds, skill)
	if skill >= bounds.greyStart then
		return "trivial"
	elseif skill >= bounds.greenStart then
		return "easy"
	elseif skill >= bounds.yellowStart then
		return "medium"
	end
	return "optimal"
end

--- Chance (0 to 1) that one craft at `skill` gives a skill point: certain while orange, then falling
--- in a straight line to nothing at the grey level.
function SkillUpLogic.SkillUpChance(bounds, skill)
	if skill >= bounds.greyStart then
		return 0
	elseif skill < bounds.yellowStart then
		return 1
	end
	return (bounds.greyStart - skill) / (bounds.greyStart - bounds.yellowStart)
end
