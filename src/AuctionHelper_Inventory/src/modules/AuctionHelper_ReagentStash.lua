local _, AuctionHelper = ...

-- Stashing crafting reagents away from the bags: the two choices the player makes (which reagents,
-- and whether the craft queue's materials stay), and the facts the rules need from saved data.
-- The rules themselves are in AuctionHelper_ReagentStashLogic.lua; the bag window and the mailbox's
-- surplus review act on them.

local StashLogic = AuctionHelper.ReagentStashLogic

--- Whether only reagents of this character's scanned professions are stashed (else every crafting
--- material). On unless turned off.
function AuctionHelper:GetStashOnlyOwnProfessions()
	return self:GetSetting("reagentStash.onlyOwnProfessions", true) == true
end

function AuctionHelper:SetStashOnlyOwnProfessions(enabled)
	self:SetSetting("reagentStash.onlyOwnProfessions", enabled == true)
end

--- Whether the materials of this character's queued crafts stay in the bags. On unless turned off.
function AuctionHelper:GetStashKeepsQueueNeeds()
	return self:GetSetting("reagentStash.keepQueueNeeds", true) == true
end

function AuctionHelper:SetStashKeepsQueueNeeds(enabled)
	self:SetSetting("reagentStash.keepQueueNeeds", enabled == true)
end

--- Every item a scanned recipe of this character uses (reagents[itemID] = true), and how many of
--- its professions have been scanned.
function AuctionHelper:GetOwnProfessionReagents()
	local characters = self.db and self.db.characters or {}
	local character = characters[self:GetCharacterKey()] or {}
	return StashLogic.ProfessionReagents(character.professions)
end

--- What this character's queued crafts and crafting orders need, as need[itemID] = quantity.
function AuctionHelper:GetOwnQueueNeeds()
	local current = self:GetCharacterKey()
	local need = StashLogic.QueueNeeds(self:BuildCraftQueueSummary().reagentLines, current)
	local orders = self.BuildCraftingOrderQueueSummary and self:BuildCraftingOrderQueueSummary() or {}
	return StashLogic.QueueNeeds(orders.reagentLines, current, need)
end

--- Whether the surplus mail is narrowed to crafting reagents for this mailbox visit.
function AuctionHelper:GetMailReagentsOnly()
	return self._mailReagentsOnly == true
end

function AuctionHelper:SetMailReagentsOnly(enabled)
	self._mailReagentsOnly = enabled == true
end

--- With "reagents only" on, marks every surplus row that is no stashed reagent as not sent.
function AuctionHelper:NarrowSurplusToReagents(rows)
	if not self:GetMailReagentsOnly() then
		return rows
	end
	local professionReagents = self:GetStashOnlyOwnProfessions() and self:GetOwnProfessionReagents() or nil
	return self.MailLogic.SendOnly(rows, function(itemID)
		local classID = select(6, C_Item.GetItemInfoInstant(itemID))
		return StashLogic.IsStashed(itemID, classID, professionReagents)
	end, "notReagent")
end
