local _, AuctionHelper = ...

function AuctionHelper:SafeCall(func, ...)
	if type(func) ~= "function" then
		return nil
	end
	local ok, result = pcall(func, ...)
	if ok then
		return result
	end
	return nil
end

function AuctionHelper:ShallowArrayCopy(source)
	local result = {}
	if type(source) ~= "table" then
		return result
	end
	for index, value in ipairs(source) do
		result[index] = value
	end
	return result
end

function AuctionHelper:NormalizeApiList(...)
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

function AuctionHelper:TableCount(tbl)
	local count = 0
	if type(tbl) ~= "table" then
		return count
	end
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

function AuctionHelper:SortByNameThenId(left, right)
	local leftName = tostring(left.professionName or left.name or "")
	local rightName = tostring(right.professionName or right.name or "")
	if leftName == rightName then
		return tonumber(left.skillLineID or 0) < tonumber(right.skillLineID or 0)
	end
	return leftName < rightName
end

function AuctionHelper:IsArray(tbl)
	if type(tbl) ~= "table" then
		return false
	end

	local index = 0
	for key in pairs(tbl) do
		if type(key) ~= "number" or key <= 0 or math.floor(key) ~= key then
			return false
		end
		if key > index then
			index = key
		end
	end

	for i = 1, index do
		if tbl[i] == nil then
			return false
		end
	end

	return true
end

function AuctionHelper:JsonEscape(text)
	text = tostring(text)
	text = text:gsub("\\", "\\\\")
	text = text:gsub('"', '\\"')
	text = text:gsub("\b", "\\b")
	text = text:gsub("\f", "\\f")
	text = text:gsub("\n", "\\n")
	text = text:gsub("\r", "\\r")
	text = text:gsub("\t", "\\t")
	return text
end

--- Byte length of BuildCopyBoxPagedWrapperJson(pageIndex, pageCount, payloadFragment).
function AuctionHelper:EstimateCopyBoxWrappedPagingByteLength(pageIndex, pageCount, payloadFragment)
	local head = string.format("AHPAGE:%d/%d\n", pageIndex, pageCount)
	return #head + #(payloadFragment or "")
end

local function encodeJsonCore(self, value, stepFn)
	stepFn = stepFn or function()
	end

	local valueType = type(value)

	if valueType == "nil" then
		return "null"
	elseif valueType == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		return tostring(value)
	elseif valueType == "boolean" then
		return value and "true" or "false"
	elseif valueType == "string" then
		return '"' .. self:JsonEscape(value) .. '"'
	elseif valueType ~= "table" then
		return '"' .. self:JsonEscape(tostring(value)) .. '"'
	end

	if self:IsArray(value) then
		stepFn()
		local parts = {}
		for index = 1, #value do
			stepFn()
			parts[index] = encodeJsonCore(self, value[index], stepFn)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end

	stepFn()
	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)

	local parts = {}
	for _, key in ipairs(keys) do
		stepFn()
		table.insert(parts, '"' .. self:JsonEscape(tostring(key)) .. '":' .. encodeJsonCore(self, value[key], stepFn))
	end

	return "{" .. table.concat(parts, ",") .. "}"
end

function AuctionHelper:EncodeJson(value)
	return encodeJsonCore(self, value, nil)
end

--- Same output as EncodeJson; must run inside a coroutine. Yields every JSON_ENCODE_YIELD_STEPS stepFn calls to spread work across frames.
--- progressTbl: optional { steps = 0 }; incremented on every encoding step for UI progress.
function AuctionHelper:EncodeJsonYielding(value, progressTbl)
	local every = self.JSON_ENCODE_YIELD_STEPS or 1000
	local n = 0
	progressTbl = progressTbl or { steps = 0 }
	local function stepFn()
		progressTbl.steps = progressTbl.steps + 1
		n = n + 1
		if n >= every then
			n = 0
			coroutine.yield()
		end
	end
	return encodeJsonCore(self, value, stepFn)
end

--- Runs EncodeJsonYielding across frames via C_Timer (fallback: tight synchronous coroutine loop).
--- onProgress: optional function(stepCount) called after each yield; also once with final count when encoding completes.
function AuctionHelper:RunEncodeJsonAsync(value, onComplete, onProgress)
	if type(onComplete) ~= "function" then
		return
	end

	local progress = { steps = 0 }
	local co = coroutine.create(function()
		return self:EncodeJsonYielding(value, progress)
	end)

	local function oneStep()
		local ok, first = coroutine.resume(co)
		if not ok then
			onComplete(nil, first)
			return
		end
		if coroutine.status(co) == "dead" then
			if onProgress then
				onProgress(progress.steps)
			end
			onComplete(first, nil)
			return
		end
		if onProgress then
			onProgress(progress.steps)
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(0, oneStep)
		end
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(0, oneStep)
	else
		while true do
			local ok, first = coroutine.resume(co)
			if not ok then
				onComplete(nil, first)
				return
			end
			if coroutine.status(co) == "dead" then
				if onProgress then
					onProgress(progress.steps)
				end
				onComplete(first, nil)
				return
			end
			if onProgress then
				onProgress(progress.steps)
			end
		end
	end
end

function AuctionHelper:SanitizeValue(value, depth, seen)
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

function AuctionHelper:GetBuildMetadata()
	local version, build, buildDate, interfaceVersion = GetBuildInfo()
	return {
		version = version,
		build = build,
		buildDate = buildDate,
		interfaceVersion = interfaceVersion,
		project = WOW_PROJECT_ID,
	}
end

function AuctionHelper:GetCharacterKey()
	local name, realm = UnitFullName("player")
	realm = realm or GetRealmName() or "UnknownRealm"
	return string.format("%s-%s", tostring(name or "UnknownPlayer"), tostring(realm))
end

--- Profession crafting tier (1+) embedded in item hyperlink; matches default tooltip quality diamond.
function AuctionHelper:ParseProfessionQualityTierFromItemLink(link)
	if type(link) ~= "string" or link == "" then
		return nil
	end
	local expPart, tierStr = string.match(link, "\124A:Professions%-ChatIcon%-Quality([%-%d]*)%-Tier(%d+)")
	if not tierStr then
		return nil
	end
	local tier = tonumber(tierStr)
	if not tier or tier < 1 then
		return nil
	end
	if expPart and expPart ~= "" and tonumber(expPart) then
		tier = tier + 10
	end
	if tier > 10 then
		tier = tier - 10
	end
	return tier
end

function AuctionHelper:ItemDescriptorFromID(itemID)
	if not itemID then
		return nil
	end

	local name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, icon, sellPrice,
		classID, subclassID, bindType, expansionID, setID, isCraftingReagent
	local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	if getItemInfo then
		name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, icon, sellPrice,
			classID, subclassID, bindType, expansionID, setID, isCraftingReagent = getItemInfo(itemID)
	end

	local getItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	local instantItemID, instantItemType, instantItemSubType, instantEquipLoc, instantIcon, instantClassID, instantSubClassID
	if getItemInfoInstant then
		instantItemID, instantItemType, instantItemSubType, instantEquipLoc, instantIcon, instantClassID,
			instantSubClassID = getItemInfoInstant(itemID)
	end

	return {
		itemID = itemID,
		name = name,
		link = link,
		quality = quality,
		itemLevel = itemLevel,
		minLevel = minLevel,
		itemType = itemType or instantItemType,
		itemSubType = itemSubType or instantItemSubType,
		stackCount = stackCount,
		equipLoc = equipLoc or instantEquipLoc,
		icon = icon or instantIcon,
		sellPrice = sellPrice,
		classID = classID or instantClassID,
		subclassID = subclassID or instantSubClassID,
		bindType = bindType,
		expansionID = expansionID,
		setID = setID,
		isCraftingReagent = isCraftingReagent,
		instantItemID = instantItemID,
	}
end

function AuctionHelper:ResolveItemDescriptor(itemID)
	if not itemID then
		return nil
	end
	local cache = self._itemDescCache
	if not cache then
		return self:ItemDescriptorFromID(itemID)
	end
	local existing = cache[itemID]
	if existing ~= nil then
		return existing
	end
	local desc = self:ItemDescriptorFromID(itemID)
	cache[itemID] = desc
	return desc
end

--- Uses static C_Item.GetItemInfo bind type only (not whether your stack is actually soulbound).
--- Excludes typical BoP / quest / account / bnet / warband-style bindings when the client exposes them.
function AuctionHelper:IsItemLikelyTradeableOnAuctionByStaticInfo(itemID)
	itemID = tonumber(itemID)
	if not itemID or itemID <= 0 then
		return false
	end
	local desc = self:ResolveItemDescriptor(itemID)
	if not desc or not desc.name then
		return false
	end
	local bt = desc.bindType
	if bt == nil then
		return true
	end
	bt = tonumber(bt)
	if not bt then
		return true
	end
	local E = Enum and Enum.ItemBind
	if E then
		if E.OnAcquire and bt == E.OnAcquire then
			return false
		end
		if E.Quest and bt == E.Quest then
			return false
		end
		if E.ToWoWAccount and bt == E.ToWoWAccount then
			return false
		end
		if E.ToBnetAccount and bt == E.ToBnetAccount then
			return false
		end
		if E.ToWoWAccountUntilEquipped and bt == E.ToWoWAccountUntilEquipped then
			return false
		end
		if E.ToBnetAccountUntilEquipped and bt == E.ToBnetAccountUntilEquipped then
			return false
		end
		if E.ToWarband and bt == E.ToWarband then
			return false
		end
	end
	if LE_ITEM_BIND_ON_ACQUIRE and bt == LE_ITEM_BIND_ON_ACQUIRE then
		return false
	end
	if LE_ITEM_BIND_QUEST and bt == LE_ITEM_BIND_QUEST then
		return false
	end
	return true
end

--- Map C_Item.GetItemInfo expansionID (LE_EXPANSION) to crafts/inventory filter bucket.
--- Retail: 9 DF, 10 TWW, 11 Midnight. Other values (incl. Classic client sentinel 254) → legacy.
function AuctionHelper:ExpansionLeToFilterTag(expansionID)
	local e = tonumber(expansionID)
	if not e or e ~= e then
		return nil
	end
	local midnight = LE_EXPANSION_MIDNIGHT or 11
	local tww = LE_EXPANSION_WAR_WITHIN or 10
	local df = LE_EXPANSION_DRAGONFLIGHT or 9
	if e == midnight then
		return "midnight"
	end
	if e == tww then
		return "tww"
	end
	if e == df then
		return "df"
	end
	return "legacy"
end

function AuctionHelper:GetExpansionFilterOptions()
	return {
		{ value = "all", label = "All expansions" },
		{ value = "midnight", label = "Midnight" },
		{ value = "tww", label = "The War Within" },
		{ value = "df", label = "Dragonflight" },
		{ value = "legacy", label = "Older" },
	}
end

function AuctionHelper:ResolveCurrencyDescriptor(currencyID)
	if not currencyID then
		return nil
	end
	local cache = self._currencyDescCache
	if not cache then
		return self:CurrencyDescriptorFromID(currencyID)
	end
	local existing = cache[currencyID]
	if existing ~= nil then
		return existing
	end
	local desc = self:CurrencyDescriptorFromID(currencyID)
	cache[currencyID] = desc
	return desc
end

function AuctionHelper:CurrencyDescriptorFromID(currencyID)
	if not currencyID then
		return nil
	end

	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
	return self:SanitizeValue(info)
end

function AuctionHelper:FindProfessionByIdentifier(professions, identifier)
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
function AuctionHelper:RecipeDataInfo(recipeData)
	if not recipeData then
		return nil
	end
	return recipeData.info or recipeData.recipeInfo
end

--- Crafting spell ID (C_TradeSkillUI recipeSpellID / recipeInfo.recipeID).
function AuctionHelper:GetRecipeSpellID(recipeData)
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
function AuctionHelper:GetRecipeExportID(recipeData)
	if not recipeData then
		return nil
	end
	if recipeData.skillLineAbilityID ~= nil then
		return tonumber(recipeData.skillLineAbilityID)
	end
	local info = self:RecipeDataInfo(recipeData)
	return info and tonumber(info.skillLineAbilityID) or self:GetRecipeSpellID(recipeData)
end

function AuctionHelper:GetRecipeStorageKey(recipeData)
	local exportID = self:GetRecipeExportID(recipeData)
	return exportID and tostring(exportID) or nil
end

--- Resolve stored recipe by export id (skillLineAbilityID) or crafting spell id.
function AuctionHelper:FindStoredRecipe(professionData, recipeIDOrSpellID)
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

function AuctionHelper:RecipeDataSlots(recipeData)
	if not recipeData then
		return nil
	end
	return recipeData.slots or recipeData.reagentSlots
end

--- Output summary: primary product item id (schema v4 |itemID|, legacy |outputItemID|).
function AuctionHelper:RecipeOutputsPrimaryItemId(outputs)
	if not outputs then
		return nil
	end
	return outputs.itemID or outputs.outputItemID
end

--- Copper to buy one item from a vendor (Retail C_Item); nil if not sold by vendors.
function AuctionHelper:GetItemVendorPurchaseCopper(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	if C_Item and C_Item.GetItemVendorPrice then
		local c = tonumber(C_Item.GetItemVendorPrice(itemID))
		if c and c > 0 then
			return c
		end
	end
	return nil
end

--- Vendor sell (to NPC) price per item; nil if unknown.
function AuctionHelper:GetItemVendorSellCopper(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	if C_Item and C_Item.GetItemInfo then
		local _, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemID)
		sellPrice = tonumber(sellPrice)
		if sellPrice and sellPrice > 0 then
			return sellPrice
		end
	end
	return nil
end

-- Generic state watcher utility (reusable across UI modules).
-- Polls snapshotFn periodically and calls onChanged(newValue, oldValue) when value changes.
function AuctionHelper:StartStateWatcher(key, intervalSec, snapshotFn, onChanged)
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