local _, Tradewright = ...

-- Recipe cooldowns. Read from the client while a profession window is open and kept per character
-- in `db.characters[characterKey].recipeCooldowns[recipeID] = readyAt` (server time).
-- A recipe is only known to have a cooldown once the client has reported one for it, so nothing is
-- assumed about recipes that have never been on cooldown while the addon was watching.

local READ_DELAY = 1
local LOGIN_ANNOUNCE_DELAY = 5

local function cooldownStore(pe, characterKey)
	local character = pe.db and pe.db.characters and pe.db.characters[characterKey]
	if not character then
		return nil
	end
	character.recipeCooldowns = character.recipeCooldowns or {}
	return character.recipeCooldowns
end

-- Seconds left on a recipe's cooldown as the client reports it, or nil.
local function secondsLeft(recipeID)
	local ok, seconds = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
	seconds = ok and tonumber(seconds) or nil
	if seconds and seconds > 0 then
		return seconds
	end
	return nil
end

--- Read the cooldown of every recipe of the open profession. Returns how many are on cooldown.
function Tradewright:ReadOpenProfessionCooldowns()
	if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeCooldown) then
		return 0
	end
	local store = cooldownStore(self, self:GetCharacterKey())
	local ok, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
	if not (store and ok and type(recipeIDs) == "table") then
		return 0
	end
	local waiting = 0
	for _, recipeID in ipairs(recipeIDs) do
		local seconds = secondsLeft(recipeID)
		if seconds then
			store[recipeID] = Tradewright:Now() + seconds
			waiting = waiting + 1
		end
	end
	return waiting
end

--- Cooldown of a craft row for its best crafter: `{ state = "ready" | "waiting" | "none", secondsLeft }`.
function Tradewright:GetCraftRowCooldown(row)
	local store = row and cooldownStore(self, row.bestCharacterKey)
	local readyAt = store and (store[tonumber(row.recipeID)] or store[tonumber(row.recipeSpellID)])
	return self.MaterialLogic.CooldownState(readyAt, Tradewright:Now())
end

--- Does any character's stored cooldown mark this recipe as a cooldown recipe?
function Tradewright:IsCooldownRecipe(recipeID)
	recipeID = tonumber(recipeID)
	for _, character in pairs(self.db and self.db.characters or {}) do
		if recipeID and character.recipeCooldowns and character.recipeCooldowns[recipeID] then
			return true
		end
	end
	return false
end

--- Ready and waiting cooldowns of every character (see MaterialLogic.SummarizeCooldowns).
function Tradewright:GetCooldownSummary()
	local cooldownsByCharacter = {}
	for characterKey, character in pairs(self.db and self.db.characters or {}) do
		cooldownsByCharacter[characterKey] = character.recipeCooldowns
	end
	return self.MaterialLogic.SummarizeCooldowns(cooldownsByCharacter, Tradewright:Now())
end

-- The recipe's name as the client knows it (a recipe ID is a spell ID), or a plain stand-in.
local function recipeName(recipeID)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID)
	return name or (GetSpellInfo and GetSpellInfo(recipeID)) or "A cooldown craft"
end

-- One chat line per ready cooldown, said once after login when the setting asks for it.
local function announceReadyCooldowns(pe)
	if pe:GetSetting("crafts.announceCooldowns", true) == false then
		return
	end
	for _, ready in ipairs(pe:GetCooldownSummary().ready) do
		pe:PrintMessage(string.format("%s is off cooldown on %s.", recipeName(ready.recipeID), ready.characterKey))
	end
end

-- Profession events fire in bursts; read once shortly after the last one.
local pending = false
local function scheduleRead()
	if pending then
		return
	end
	pending = true
	C_Timer.After(READ_DELAY, function()
		pending = false
		if Tradewright.db then
			Tradewright:ReadOpenProfessionCooldowns()
		end
	end)
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "PLAYER_LOGIN" }) do
	pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		-- Saved data is merged a moment after login.
		C_Timer.After(LOGIN_ANNOUNCE_DELAY, function()
			if Tradewright.db then
				announceReadyCooldowns(Tradewright)
			end
		end)
	else
		scheduleRead()
	end
end)
