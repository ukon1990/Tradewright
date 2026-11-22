local _, Tradewright = ...

-- Leveling route steps in the craft queue. A queue line remembers how many of its crafts came from
-- the route (`levelingQuantity`). Only that part is ever lowered when the route needs fewer crafts,
-- so crafts the player queued for the same recipe stay.

local LevelingRouteLogic = Tradewright.LevelingRouteLogic

-- Crafts on this line that came from the route. Crafting lowers the line's quantity without touching
-- `levelingQuantity`, hence the cap.
local function levelingCrafts(entry)
	return math.min(tonumber(entry.levelingQuantity) or 0, tonumber(entry.quantity) or 0)
end

-- A line of this route. On retail a route levels one expansion of the profession, and the line
-- remembers which (`levelingExpansionSkillLineID`): another expansion's route must not lower it.
local function isRouteLine(entry, route)
	return type(entry) == "table" and entry.levelingQuantity
		and entry.characterKey == route.characterKey and tonumber(entry.skillLineID) == tonumber(route.skillLineID)
		and entry.levelingExpansionSkillLineID == route.expansionSkillLineID
end

--- Whether any craft in the craft queue came from a leveling route.
function Tradewright:HasLevelingCraftQueueLines()
	for _, entry in pairs(self:GetCraftQueueStorage()) do
		if type(entry) == "table" and entry.levelingQuantity then
			return true
		end
	end
	return false
end

--- Crafts of `recipeID` in the craft queue that came from this route.
function Tradewright:GetLevelingQueuedQuantity(route, recipeID)
	local queued = 0
	for _, entry in pairs(self:GetCraftQueueStorage()) do
		if isRouteLine(entry, route) and entry.recipeID == recipeID then
			queued = queued + levelingCrafts(entry)
		end
	end
	return queued
end

-- Brings the route's crafts of the step's recipe in the craft queue up to `wanted`. Returns the
-- number added. A line for a recipe not learned yet remembers that (`levelingLearn`), so the Queue
-- view can say it has to be learned first.
local function queueRouteCrafts(pe, route, step, wanted)
	local alreadyQueued = pe:GetLevelingQueuedQuantity(route, step.recipeID)
	local toAdd = wanted - alreadyQueued
	if toAdd <= 0 then
		return 0
	end
	local queueKey = pe:AddCraftToQueue({
		recipeID = step.recipeID, characterKey = route.characterKey, scenario = "default",
		eval = step.candidate.evaluation, dataSource = "leveling_route",
	}, toAdd)
	local entry = queueKey and pe:GetCraftQueueStorage()[queueKey]
	if not entry then
		return 0
	end
	entry.levelingQuantity = alreadyQueued + toAdd
	entry.levelingExpansionSkillLineID = route.expansionSkillLineID
	if not step.learned then
		entry.levelingLearn = { skill = step.candidate.source == "trainer" and step.candidate.learnSkill or nil }
	end
	return toAdd
end

--- Puts a step's crafts in the craft queue, counting what the route already queued for that recipe.
--- Only for a recipe the character knows. Returns the number of crafts added.
function Tradewright:QueueLevelingStep(route, step)
	local wanted = LevelingRouteLogic.QueueEntry(step)
	return wanted and queueRouteCrafts(self, route, step, wanted.quantity) or 0
end

--- Queues the route's crafts from the current skill up to `toSkill`, in route order, including
--- recipes that still have to be learned. Returns the number of crafts added.
function Tradewright:QueueLevelingRange(route, toSkill)
	local added = 0
	for _, wanted in ipairs(LevelingRouteLogic.QueueEntriesUpTo(route.steps, toSkill)) do
		added = added + queueRouteCrafts(self, route, wanted.step, wanted.quantity)
	end
	return added
end

--- After the route changed: lowers queued route crafts the route no longer needs (skill came early,
--- or another recipe took over the step). Never adds; the step's Queue button does that.
function Tradewright:TrimLevelingCraftQueue(route)
	local trims = {}
	for queueKey, entry in pairs(self:GetCraftQueueStorage()) do
		if isRouteLine(entry, route) then
			local surplus = -LevelingRouteLogic.QueueAdjustment(levelingCrafts(entry), entry.recipeID, route.steps)
			if surplus > 0 then
				trims[#trims + 1] = { queueKey = queueKey, entry = entry, surplus = surplus }
			end
		end
	end
	-- Applied after the scan: lowering a line to nothing removes it from the storage being walked.
	for _, trim in ipairs(trims) do
		local remaining = levelingCrafts(trim.entry) - trim.surplus
		trim.entry.levelingQuantity = remaining > 0 and remaining or nil
		self:UpdateCraftQueueQuantity(trim.queueKey, (tonumber(trim.entry.quantity) or 0) - trim.surplus)
	end
end
