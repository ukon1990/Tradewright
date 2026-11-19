local addonName, ProfessionExporter = ...

-- Who mails what to whom: the auction house / bank character ("seller") of each realm, and the
-- plans the mailbox panel sends. The decisions are pure functions in ForeverLogic.

local function realmOf(characterKey)
	return tostring(characterKey or ""):match("%-(.+)$")
end

--- Characters known on the current character's realm (the current one included), sorted.
function ProfessionExporter:GetRealmCharacterKeys()
	local current = self:GetCharacterKey()
	local realm = realmOf(current)
	local keys = { current }
	for characterKey in pairs(self.db and self.db.characters or {}) do
		if characterKey ~= current and realmOf(characterKey) == realm then
			keys[#keys + 1] = characterKey
		end
	end
	table.sort(keys)
	return keys, realm
end

--- The auction house / bank character of the current realm, or nil when none is set.
function ProfessionExporter:GetSellerCharacterKey()
	local known = {}
	local keys, realm = self:GetRealmCharacterKeys()
	for _, characterKey in ipairs(keys) do
		known[characterKey] = true
	end
	return self.ForeverLogic.ResolveSellerCharacter(self:GetSetting("mail.sellerByRealm", {}), realm, known)
end

function ProfessionExporter:IsSellerCharacter()
	return self:GetSellerCharacterKey() == self:GetCharacterKey()
end

-- Saved per character under settings.mail[name][characterKey].
local function characterStore(pe, name)
	local path = "mail." .. name
	local all = pe:GetSetting(path)
	if type(all) ~= "table" then
		all = {}
		pe:SetSetting(path, all)
	end
	local key = pe:GetCharacterKey()
	all[key] = all[key] or {}
	return all[key]
end

--- What the bags hold, per item: { itemID, name, quantity, quality, sellable }. Sellable means it
--- can change hands: not bound and not a quest item.
function ProfessionExporter:GetBagItems()
	local questClass = Enum and Enum.ItemClass and Enum.ItemClass.Questitem
	local items = {}
	for bag = 0, 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local itemID = info and tonumber(info.itemID)
			if itemID then
				local entry = items[itemID]
				if not entry then
					local classID = select(6, C_Item.GetItemInfoInstant(itemID))
					entry = { itemID = itemID, name = self:GetItemDisplayName(itemID), quantity = 0,
						quality = tonumber(info.quality) or 0, sellable = classID ~= questClass }
					items[itemID] = entry
				end
				entry.quantity = entry.quantity + (tonumber(info.stackCount) or 1)
				entry.sellable = entry.sellable and not info.isBound
			end
		end
	end
	return items
end

--- A queued craft finished on this character: remember the result so it can be mailed to the seller.
function ProfessionExporter:NoteCraftForSeller(itemID, quantity)
	itemID, quantity = tonumber(itemID), tonumber(quantity) or 0
	local seller = self:GetSellerCharacterKey()
	if not itemID or quantity <= 0 or not seller or seller == self:GetCharacterKey() then
		return
	end
	local toSeller = characterStore(self, "toSellerByCharacter")
	toSeller[itemID] = (toSeller[itemID] or 0) + quantity
end

--- Everything the mailbox panel can send from this character: materials for crafters, and on a
--- crafter the crafted items owed to the seller. Each destination carries its `kind`.
function ProfessionExporter:BuildMailPanelPlan()
	local plan = self:BuildShoppingMailSendPlan()
	for _, dest in ipairs(plan) do
		dest.kind = "materials"
	end
	local seller = self:GetSellerCharacterKey()
	if not seller or seller == self:GetCharacterKey() then
		return plan
	end
	local bags = self:GetBagItems()
	-- Crafted items that left the bags some other way are no longer owed.
	local toSeller = characterStore(self, "toSellerByCharacter")
	for itemID, owed in pairs(toSeller) do
		local held = bags[itemID] and bags[itemID].quantity or 0
		toSeller[itemID] = held > 0 and math.min(owed, held) or nil
	end
	for _, dest in ipairs(self.ForeverLogic.BuildReturnToSellerPlan(toSeller, bags, seller)) do
		plan[#plan + 1] = dest
	end
	return plan
end

--- A parcel reached the mail server: crafted items in it are no longer owed to the seller.
function ProfessionExporter:OnMailParcelSent(parcel)
	if parcel.kind ~= "crafts" then
		return
	end
	local toSeller = characterStore(self, "toSellerByCharacter")
	for _, item in ipairs(parcel.items) do
		local left = (toSeller[item.itemID] or 0) - item.quantity
		toSeller[item.itemID] = left > 0 and left or nil
	end
end
