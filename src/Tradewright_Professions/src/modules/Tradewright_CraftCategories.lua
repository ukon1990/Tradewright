local _, Tradewright = ...

-- Recipe names and category labels for craft rows, from the stored category tree or the live profession API.

local function recipeDisplayName(recipeData)
	local info = Tradewright:RecipeDataInfo(recipeData)
	return (info and info.name) and tostring(info.name) or "Recipe"
end

local function recipeCategoryId(recipeData)
	local info = Tradewright:RecipeDataInfo(recipeData)
	if not info then
		return nil
	end
	return tonumber(info.categoryID or info.recipeCategoryID)
end

local function categoryInfoName(info)
	local name = info and (info.name or info.categoryName)
	if name and tostring(name) ~= "" then
		return tostring(name)
	end
	return nil
end

local function categoryNodeName(node)
	return categoryInfoName(node and node.info or nil)
end

--- Name of entry's subcategory with categoryID (falls back to entry's own name).
local function subCategoryName(entry, categoryID)
	for _, subCategory in ipairs((entry and entry.subCategories) or {}) do
		if tonumber(subCategory and subCategory.categoryID) == tonumber(categoryID) then
			return categoryNodeName(subCategory) or categoryNodeName(entry)
		end
	end
	return nil
end

local function subCategoryIdParentName(entry, categoryID)
	for _, subCategoryID in ipairs((entry and entry.subCategoryIDs) or {}) do
		if tonumber(subCategoryID) == tonumber(categoryID) then
			return categoryNodeName(entry)
		end
	end
	return nil
end

--- Category name from the stored profession category tree; nil when unknown or nameless.
local function storedCategoryName(professionData, categoryID)
	for _, entry in ipairs((professionData and professionData.categories) or {}) do
		if tonumber(entry and entry.categoryID) == tonumber(categoryID) then
			return categoryNodeName(entry)
		end
		local name = subCategoryName(entry, categoryID) or subCategoryIdParentName(entry, categoryID)
		if name then
			return name
		end
	end
	return nil
end

local function liveCategoryName(categoryID)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetCategoryInfo) then
		return nil
	end
	return categoryInfoName(Tradewright:SafeCall(C_TradeSkillUI.GetCategoryInfo, categoryID))
end

local function recipeCategoryName(recipeData, professionData)
	local info = Tradewright:RecipeDataInfo(recipeData)
	if info then
		local directName = info.categoryName or info.recipeCategoryName or info.category
		if directName and tostring(directName) ~= "" then
			return tostring(directName)
		end
	end
	local categoryID = recipeCategoryId(recipeData)
	if not categoryID then
		return nil
	end
	return storedCategoryName(professionData, categoryID) or liveCategoryName(categoryID)
end

local function resolveCategoryLabelFromProfessionCategory(categoryEntry, categoryID)
	if not categoryEntry then
		return nil
	end
	local function joinPath(parts)
		local out = {}
		for _, part in ipairs(parts) do
			if part and part ~= "" then
				out[#out + 1] = part
			end
		end
		if #out == 0 then
			return nil
		end
		return table.concat(out, " / ")
	end

	local function walk(node, targetID, path)
		if not node then
			return nil
		end
		local nextPath = {}
		for i = 1, #path do
			nextPath[i] = path[i]
		end
		nextPath[#nextPath + 1] = categoryNodeName(node)

		if tonumber(node.categoryID) == tonumber(targetID) then
			return joinPath(nextPath)
		end
		for _, child in ipairs(node.subCategories or {}) do
			local found = walk(child, targetID, nextPath)
			if found then
				return found
			end
		end
		for _, childID in ipairs(node.subCategoryIDs or {}) do
			if tonumber(childID) == tonumber(targetID) then
				return joinPath(nextPath)
			end
		end
		return nil
	end

	return walk(categoryEntry, categoryID, {})
end

function Tradewright:ResolveCraftCategoryLabel(skillLineID, categoryID)
	self:InitDB()
	local cid = tonumber(categoryID)
	if not cid then
		return nil
	end
	for _, characterData in pairs(self.db.characters or {}) do
		for _, professionData in pairs(characterData.professions or {}) do
			if tonumber(professionData.skillLineID) == tonumber(skillLineID) then
				for _, categoryEntry in ipairs(professionData.categories or {}) do
					local label = resolveCategoryLabelFromProfessionCategory(categoryEntry, cid)
					if label and label ~= "" then
						return label
					end
				end
			end
		end
	end
	return nil
end

Tradewright.CraftCategories = {
	recipeDisplayName = recipeDisplayName,
	recipeCategoryId = recipeCategoryId,
	recipeCategoryName = recipeCategoryName,
}
