-- General helpers: SafeCall, table and API-list utilities, character and recipe keys, and the state watcher.
local _, Tradewright = ...

function Tradewright:SafeCall(func, ...)
	if type(func) ~= "function" then
		return nil
	end
	local ok, result = pcall(func, ...)
	if ok then
		return result
	end
	return nil
end

function Tradewright:ShallowArrayCopy(source)
	local result = {}
	if type(source) ~= "table" then
		return result
	end
	for index, value in ipairs(source) do
		result[index] = value
	end
	return result
end

function Tradewright:NormalizeApiList(...)
	local valueCount = select("#", ...)
	if valueCount == 0 then
		return {}
	end

	local firstValue = select(1, ...)
	if valueCount == 1 then
		if type(firstValue) == "table" then
			return self:ShallowArrayCopy(firstValue)
		end
		if firstValue == nil then
			return {}
		end
		return { firstValue }
	end

	local result = {}
	for index = 1, valueCount do
		result[index] = select(index, ...)
	end
	return result
end

function Tradewright:TableCount(tbl)
	local count = 0
	if type(tbl) ~= "table" then
		return count
	end
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

function Tradewright:SortByNameThenId(left, right)
	local leftName = tostring(left.professionName or left.name or "")
	local rightName = tostring(right.professionName or right.name or "")
	if leftName == rightName then
		return tonumber(left.skillLineID or 0) < tonumber(right.skillLineID or 0)
	end
	return leftName < rightName
end

function Tradewright:SanitizeValue(value, depth, seen)
	depth = depth or 0
	seen = seen or {}

	local valueType = type(value)
	if valueType == "nil" or valueType == "number" or valueType == "boolean" or valueType == "string" then
		if valueType == "number" and (value ~= value or value == math.huge or value == -math.huge) then
			return nil
		end
		return value
	end

	if valueType ~= "table" then
		return tostring(value)
	end

	if depth >= self.MAX_SANITIZE_DEPTH then
		return "<max-depth>"
	end

	if seen[value] then
		return "<cycle>"
	end
	seen[value] = true

	local result
	if self:IsArray(value) then
		result = {}
		for index = 1, #value do
			result[index] = self:SanitizeValue(value[index], depth + 1, seen)
		end
	else
		result = {}
		for key, nestedValue in pairs(value) do
			local keyType = type(key)
			if keyType == "string" or keyType == "number" then
				result[tostring(key)] = self:SanitizeValue(nestedValue, depth + 1, seen)
			end
		end
	end

	seen[value] = nil
	return result
end

function Tradewright:GetBuildMetadata()
	local version, build, buildDate, interfaceVersion = GetBuildInfo()
	return {
		version = version,
		build = build,
		buildDate = buildDate,
		interfaceVersion = interfaceVersion,
		project = WOW_PROJECT_ID,
	}
end

function Tradewright:GetCharacterKey()
	local name, realm = UnitFullName("player")
	realm = realm or GetRealmName() or "UnknownRealm"
	return string.format("%s-%s", tostring(name or "UnknownPlayer"), tostring(realm))
end

function Tradewright:FindProfessionByIdentifier(professions, identifier)
	if not identifier or identifier == "" then
		return nil
	end

	local numeric = tonumber(identifier)
	if numeric then
		for _, profession in ipairs(professions) do
			if tonumber(profession.skillLineID) == numeric then
				return profession
			end
		end
	end

	local lowered = string.lower(identifier)
	for _, profession in ipairs(professions) do
		if string.lower(tostring(profession.professionName or "")) == lowered then
			return profession
		end
		if string.lower(tostring(profession.currentLevelName or "")) == lowered then
			return profession
		end
	end

	return nil
end

--- Stored recipe row: schema v4 uses |info|, |slots|, |crafting|; older rows use legacy keys.
function Tradewright:RecipeDataInfo(recipeData)
	if not recipeData then
		return nil
	end
	return recipeData.info or recipeData.recipeInfo
end

--- Crafting spell ID (C_TradeSkillUI recipeSpellID / recipeInfo.recipeID).
function Tradewright:GetRecipeSpellID(recipeData)
	if not recipeData then
		return nil
	end
	if recipeData.recipeSpellID ~= nil then
		return tonumber(recipeData.recipeSpellID)
	end
	local info = self:RecipeDataInfo(recipeData)
	return info and tonumber(info.recipeID) or nil
end

--- Blizzard Game Data / SkillLineAbility recipe id (exported as recipeID).
function Tradewright:GetRecipeExportID(recipeData)
	if not recipeData then
		return nil
	end
	if recipeData.skillLineAbilityID ~= nil then
		return tonumber(recipeData.skillLineAbilityID)
	end
	local info = self:RecipeDataInfo(recipeData)
	return info and tonumber(info.skillLineAbilityID) or self:GetRecipeSpellID(recipeData)
end

function Tradewright:GetRecipeStorageKey(recipeData)
	local exportID = self:GetRecipeExportID(recipeData)
	return exportID and tostring(exportID) or nil
end

--- Resolve stored recipe by export id (skillLineAbilityID) or crafting spell id.
function Tradewright:FindStoredRecipe(professionData, recipeIDOrSpellID)
	recipeIDOrSpellID = tonumber(recipeIDOrSpellID)
	if not professionData or not recipeIDOrSpellID then
		return nil, nil
	end
	local recipes = professionData.recipes
	if type(recipes) ~= "table" then
		return nil, nil
	end
	local directKey = tostring(recipeIDOrSpellID)
	if recipes[directKey] then
		return directKey, recipes[directKey]
	end
	for storageKey, recipeData in pairs(recipes) do
		if self:GetRecipeExportID(recipeData) == recipeIDOrSpellID
			or self:GetRecipeSpellID(recipeData) == recipeIDOrSpellID then
			return storageKey, recipeData
		end
	end
	return nil, nil
end

function Tradewright:RecipeDataSlots(recipeData)
	if not recipeData then
		return nil
	end
	return recipeData.slots or recipeData.reagentSlots
end

--- Output summary: primary product item id (schema v4 |itemID|, legacy |outputItemID|).
function Tradewright:RecipeOutputsPrimaryItemId(outputs)
	if not outputs then
		return nil
	end
	return outputs.itemID or outputs.outputItemID
end

-- Generic state watcher utility (reusable across UI modules).
-- Polls snapshotFn periodically and calls onChanged(newValue, oldValue) when value changes.
function Tradewright:StartStateWatcher(key, intervalSec, snapshotFn, onChanged)
	if not key or type(snapshotFn) ~= "function" or type(onChanged) ~= "function" then
		return nil
	end
	self._stateWatchers = self._stateWatchers or {}
	local existing = self._stateWatchers[key]
	if existing and existing.ticker then
		existing.ticker:Cancel()
	end

	local watcher = {
		key = key,
		snapshotFn = snapshotFn,
		onChanged = onChanged,
		lastValue = nil,
	}
	self._stateWatchers[key] = watcher

	local function tick()
		local current = snapshotFn()
		if current ~= watcher.lastValue then
			local old = watcher.lastValue
			watcher.lastValue = current
			onChanged(current, old)
		end
	end

	watcher.ticker = C_Timer.NewTicker(math.max(0.05, tonumber(intervalSec) or 0.2), tick)
	tick()
	return watcher
end

local MEASURED_CUT = "measured"

-- The measurement from the Inventory module's ledger, or nil when that module is not loaded.
local function measuredAuctionCut(self)
	return self.LedgerMeasuredAuctionCut and self:LedgerMeasuredAuctionCut() or nil
end

--- The auction house's share of a sale, as a fraction. The setting is a fixed percent or "measured":
--- the share seen in the player's own sale mails, with DEFAULT_AUCTION_CUT until enough are collected.
function Tradewright:GetAuctionCut()
	local percent = tonumber(self:GetSetting("fees.auctionCut", MEASURED_CUT))
	if percent then
		return math.max(0, math.min(50, percent)) / 100
	end
	local measured = measuredAuctionCut(self)
	return measured and measured.cut or self.DEFAULT_AUCTION_CUT
end

--- The cut in use, for footers and notes: "5%", "4.8%, measured" or "5%, not measured yet".
function Tradewright:DescribeAuctionCut()
	local text = string.format("%.3g%%", self:GetAuctionCut() * 100)
	if tonumber(self:GetSetting("fees.auctionCut", MEASURED_CUT)) then
		return text
	end
	local measured = measuredAuctionCut(self)
	return text .. (measured and measured.cut and ", measured" or ", not measured yet")
end
