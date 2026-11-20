local _, ProfessionExporter = ...

-- Who mails what to whom: the auction house / bank character ("seller") of each realm, and the
-- plans the mailbox panel sends. The decisions are pure functions in ForeverLogic.

-- WoW Forever has no realms: the second part of its character keys is a surname, so all of its
-- characters are one group and share one auction house / bank character.
local FOREVER_GROUP = "Forever"

local function realmOf(pe, characterKey)
	if pe.IS_FOREVER then
		return FOREVER_GROUP
	end
	return tostring(characterKey or ""):match("%-(.+)$")
end

--- Characters known on the current character's realm (the current one included), sorted.
function ProfessionExporter:GetRealmCharacterKeys()
	local current = self:GetCharacterKey()
	local realm = realmOf(self, current)
	local keys = { current }
	for characterKey in pairs(self.db and self.db.characters or {}) do
		if characterKey ~= current and realmOf(self, characterKey) == realm then
			keys[#keys + 1] = characterKey
		end
	end
	table.sort(keys)
	return keys, realm
end

--- The mail To line for a character: first name and surname on Forever (MailLogic.MailRecipient).
function ProfessionExporter:GetMailRecipient(characterKey)
	return self.MailLogic.MailRecipient(characterKey, self.IS_FOREVER)
end

--- Sets each destination's To line from its character key; returns the list.
function ProfessionExporter:SetMailRecipients(destinations)
	for _, dest in ipairs(destinations) do
		dest.mailName = self:GetMailRecipient(dest.characterKey)
	end
	return destinations
end

--- The auction house / bank character of the current realm (all of Forever), or nil when none is set.
--- A Forever choice saved per surname before is carried over to the one Forever group.
function ProfessionExporter:GetSellerCharacterKey()
	local known = {}
	local keys, realm = self:GetRealmCharacterKeys()
	for _, characterKey in ipairs(keys) do
		known[characterKey] = true
	end
	local sellers = self:GetSetting("mail.sellerByRealm", {})
	if self.IS_FOREVER and sellers[realm] == nil then
		sellers[realm] = self.MailLogic.EarlierForeverSeller(sellers, known)
	end
	return self.ForeverLogic.ResolveSellerCharacter(sellers, realm, known)
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
	for bag = 0, self:GetLastBagIndex() do
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

--- Whether this character mails everything sellable, not only items with a keep amount. On unless turned off.
function ProfessionExporter:GetMailSendOthers()
	return characterStore(self, "surplusByCharacter").sendOthers ~= false
end

function ProfessionExporter:SetMailSendOthers(enabled)
	characterStore(self, "surplusByCharacter").sendOthers = enabled == true
end

--- How many of an item this character keeps; nil or 0 clears the keep amount.
function ProfessionExporter:SetMailKeepAmount(itemID, quantity)
	quantity = math.floor(tonumber(quantity) or 0)
	characterStore(self, "keepByCharacter")[tonumber(itemID)] = quantity > 0 and quantity or nil
end

-- Materials this character still needs for its own queued crafts, plus everything the other mail
-- rows already take: none of it is surplus.
local function heldQuantities(pe, plan)
	local held = {}
	local function hold(itemID, quantity)
		held[itemID] = (held[itemID] or 0) + (tonumber(quantity) or 0)
	end
	local current = pe:GetCharacterKey()
	local orders = pe.BuildCraftingOrderWorkQueueSummary and pe:BuildCraftingOrderWorkQueueSummary() or {}
	for _, lines in ipairs({ pe:BuildCraftQueueSummary().reagentLines or {}, orders.reagentLines or {} }) do
		for _, line in ipairs(lines) do
			for _, source in ipairs(line.sources or {}) do
				if source.characterKey == current then
					hold(tonumber(line.itemID), source.quantity)
				end
			end
		end
	end
	for _, dest in ipairs(plan) do
		for _, item in ipairs(dest.items) do
			hold(item.itemID, item.quantity)
		end
	end
	return held
end

-- The surplus row, shown on every character but the seller even when nothing goes: its review rows (F24) with names
-- and prices, their summary, and the items that go.
local function surplusDestination(pe, plan, bags, seller)
	local rows = pe.MailLogic.BuildReviewRows(bags, characterStore(pe, "keepByCharacter"), heldQuantities(pe, plan),
		pe:GetMailSendOthers(), pe:GetMailSkipped())
	for _, row in ipairs(rows) do
		row.name = row.name or pe:GetItemDisplayName(row.itemID)
		row.unitPrice = pe:GetMailItemUnitPrice(row.itemID)
	end
	local summary = pe.MailLogic.SummarizeReviewRows(rows)
	return { kind = "surplus", characterKey = seller, mailName = pe:GetMailRecipient(seller),
		items = pe.MailLogic.SurplusItems(rows), totalQuantity = summary.send, reviewRows = rows, summary = summary }
end

--- Everything the mailbox panel can send from this character: materials for crafters, and on any
--- character but the seller the crafted items owed to it and the surplus above keep amounts. Each
--- destination carries its `kind`.
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
	for _, dest in ipairs(self:SetMailRecipients(self.ForeverLogic.BuildReturnToSellerPlan(toSeller, bags, seller))) do
		plan[#plan + 1] = dest
	end
	plan[#plan + 1] = surplusDestination(self, plan, bags, seller)
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

--- Items skipped for this mailbox visit (review panel ticks); forgotten when the mailbox closes.
function ProfessionExporter:GetMailSkipped()
	self._mailSkipped = self._mailSkipped or {}
	return self._mailSkipped
end

function ProfessionExporter:SetMailSkipped(itemID, skipped)
	self:GetMailSkipped()[tonumber(itemID)] = skipped and true or nil
end

function ProfessionExporter:ClearMailSkipped()
	self._mailSkipped = nil
end

function ProfessionExporter:GetMailKeepAmount(itemID)
	return characterStore(self, "keepByCharacter")[tonumber(itemID)]
end

function ProfessionExporter:ClearMailKeepAmounts()
	wipe(characterStore(self, "keepByCharacter"))
end

--- Unit price for the review panel's Worth: the usual price, else the last scanned price.
function ProfessionExporter:GetMailItemUnitPrice(itemID)
	local signals = self.GetItemPriceSignals and self:GetItemPriceSignals(itemID)
	if signals and signals.usual then
		return signals.usual
	end
	return self.GetNativeAhPrice and self:GetNativeAhPrice(itemID) or nil
end

--- The surplus review rows (MailLogic.BuildReviewRows, with names and prices) and the surplus
--- destination of `panelPlan` (BuildMailPanelPlan, built when not given). No rows on the seller.
function ProfessionExporter:BuildMailReviewRows(panelPlan)
	for _, dest in ipairs(panelPlan or self:BuildMailPanelPlan()) do
		if dest.kind == "surplus" then
			return dest.reviewRows, dest
		end
	end
	return {}, nil
end

--- Keep everything the bags hold now, so nothing goes until the bags grow.
function ProfessionExporter:KeepCurrentMailBags()
	for _, row in ipairs(self:BuildMailReviewRows()) do
		if row.bags > 0 then
			self:SetMailKeepAmount(row.itemID, row.bags)
		end
	end
end
