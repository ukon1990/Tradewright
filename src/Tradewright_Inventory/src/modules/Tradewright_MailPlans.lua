local _, Tradewright = ...

-- Who mails what to whom: the bank character ("seller") of each realm, the characters that
-- disenchant, prospect and mill, and the plans the mailbox panel sends. The decisions are pure functions, mostly in MailLogic (the seller
-- choice and the return-to-seller plan are in ForeverLogic).

-- WoW Forever has no realms: the second part of its character keys is a surname, so all of its
-- characters are one group and share one bank character.
local FOREVER_GROUP = "Forever"

local function realmOf(pe, characterKey)
	if pe.IS_FOREVER then
		return FOREVER_GROUP
	end
	return tostring(characterKey or ""):match("%-(.+)$")
end

--- Characters known on the current character's realm (the current one included), sorted.
function Tradewright:GetRealmCharacterKeys()
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
function Tradewright:GetMailRecipient(characterKey)
	return self.MailLogic.MailRecipient(characterKey, self.IS_FOREVER)
end

--- Sets each destination's To line from its character key; returns the list.
function Tradewright:SetMailRecipients(destinations)
	for _, dest in ipairs(destinations) do
		dest.mailName = self:GetMailRecipient(dest.characterKey)
	end
	return destinations
end

--- The bank character of the current realm (all of Forever), or nil when none is set.
--- A Forever choice saved per surname before is carried over to the one Forever group.
function Tradewright:GetSellerCharacterKey()
	local known = {}
	local keys, realm = self:GetRealmCharacterKeys()
	for _, characterKey in ipairs(keys) do
		known[characterKey] = true
	end
	local sellers = self:GetSetting("mail.sellerByRealm", {})
	if self.IS_FOREVER and sellers[realm] == nil then
		sellers[realm] = self.MailLogic.EarlierForeverSeller(sellers, known)
	end
	return self.MailLogic.ResolveSellerCharacter(sellers, realm, known)
end

function Tradewright:IsSellerCharacter()
	return self:GetSellerCharacterKey() == self:GetCharacterKey()
end

--- Where the character chosen to destroy for `action` ("disenchant", "prospect", "mill") on this
--- realm (all of Forever) is saved.
function Tradewright:GetDestroyerSettingPath(action)
	local _, realm = self:GetRealmCharacterKeys()
	return "mail.destroyerByRealm." .. realm .. "." .. action
end

-- This realm's characters with the profession `action` takes, the highest skill first, and every
-- character known here (known[characterKey] = true).
local function destroyerCandidates(pe, action)
	local known, candidates = {}, {}
	for _, characterKey in ipairs((pe:GetRealmCharacterKeys())) do
		known[characterKey] = true
	end
	for _, character in ipairs(pe:GetSalvageCharacters(action)) do
		if known[character.characterKey] then
			candidates[#candidates + 1] = character.characterKey
		end
	end
	return candidates, known
end

--- The character on this realm with the best skill in the profession `action` takes, or nil.
function Tradewright:GetDefaultDestroyerKey(action)
	return (destroyerCandidates(self, action))[1]
end

--- Whether only items worth more destroyed than sold go to the character that destroys with
--- `action`; else everything it can destroy goes. Off unless turned on.
function Tradewright:GetDestroyProfitableOnly(action)
	return self:GetSetting("mail.destroyProfitableOnly." .. action, false) == true
end

function Tradewright:SetDestroyProfitableOnly(action, enabled)
	self:SetSetting("mail.destroyProfitableOnly." .. action, enabled == true)
end

--- The character items to destroy with `action` are mailed to: the one chosen in settings, else the
--- best one with the profession. nil when "None" is chosen or nobody has it.
function Tradewright:GetDestroyerCharacterKey(action)
	local candidates, known = destroyerCandidates(self, action)
	return self.MailLogic.ResolveDestroyerCharacter(self:GetSetting(self:GetDestroyerSettingPath(action)), candidates, known)
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
function Tradewright:GetBagItems()
	local questClass = Enum and Enum.ItemClass and Enum.ItemClass.Questitem
	local items = {}
	self:ForEachBagSlot(nil, function(_, _, info)
		local itemID = info and tonumber(info.itemID)
		if not itemID then
			return
		end
		local entry = items[itemID]
		if not entry then
			local classID = select(6, C_Item.GetItemInfoInstant(itemID))
			entry = { itemID = itemID, name = self:GetItemDisplayName(itemID), quantity = 0,
				quality = tonumber(info.quality) or 0, sellable = classID ~= questClass }
			items[itemID] = entry
		end
		entry.quantity = entry.quantity + (tonumber(info.stackCount) or 1)
		entry.sellable = entry.sellable and not info.isBound
	end)
	return items
end

--- A queued craft finished on this character: remember the result so it can be mailed to the seller.
function Tradewright:NoteCraftForSeller(itemID, quantity)
	itemID, quantity = tonumber(itemID), tonumber(quantity) or 0
	local seller = self:GetSellerCharacterKey()
	if not itemID or quantity <= 0 or not seller or seller == self:GetCharacterKey() then
		return
	end
	local toSeller = characterStore(self, "toSellerByCharacter")
	toSeller[itemID] = (toSeller[itemID] or 0) + quantity
end

--- Whether this character mails everything sellable, not only items with a keep amount. On unless turned off.
function Tradewright:GetMailSendOthers()
	return characterStore(self, "surplusByCharacter").sendOthers ~= false
end

function Tradewright:SetMailSendOthers(enabled)
	characterStore(self, "surplusByCharacter").sendOthers = enabled == true
end

--- How many of an item this character keeps; nil or 0 clears the keep amount.
function Tradewright:SetMailKeepAmount(itemID, quantity)
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
	for itemID, quantity in pairs(pe:GetOwnQueueNeeds()) do
		hold(itemID, quantity)
	end
	for _, dest in ipairs(plan) do
		for _, item in ipairs(dest.items) do
			hold(item.itemID, item.quantity)
		end
	end
	return held
end

-- Names and prices on review rows, their summary, and the items that go: what a destination with a
-- review panel shows. `dest` = { kind, reviewKey, characterKey, action? }.
local function reviewDestination(pe, rows, dest)
	for _, row in ipairs(rows) do
		row.name = row.name or pe:GetItemDisplayName(row.itemID)
		row.unitPrice = pe:GetMailItemUnitPrice(row.itemID)
	end
	local summary = pe.MailLogic.SummarizeReviewRows(rows)
	dest.mailName = pe:GetMailRecipient(dest.characterKey)
	dest.items, dest.totalQuantity = pe.MailLogic.SurplusItems(rows), summary.send
	dest.reviewRows, dest.summary = rows, summary
	return dest
end

-- The surplus row, shown on every character but the seller even when nothing goes.
local function surplusDestination(pe, plan, bags, seller)
	local rows = pe.MailLogic.BuildReviewRows(bags, characterStore(pe, "keepByCharacter"), heldQuantities(pe, plan),
		pe:GetMailSendOthers(), pe:GetMailSkipped())
	pe:NarrowSurplusToReagents(rows)
	return reviewDestination(pe, rows, { kind = "surplus", reviewKey = "surplus", characterKey = seller })
end

-- The items in the bags `action` can destroy, for `destroyer`; with "only worth more destroyed" on,
-- the ones known to sell for more stay (reason "notProfitable"). nil when the bags hold none.
local function destroyDestination(pe, plan, bags, action, destroyer)
	local rows = pe.MailLogic.BuildDestroyRows(bags, function(itemID) return pe:CanDestroy(action, itemID) end,
		characterStore(pe, "keepByCharacter"), heldQuantities(pe, plan), pe:GetMailSkipped())
	if #rows == 0 then
		return nil
	end
	if pe:GetDestroyProfitableOnly(action) then
		pe.MailLogic.SendOnly(rows, function(itemID) return pe:IsBestDestroyed(action, itemID) end, "notProfitable")
	end
	return reviewDestination(pe, rows, { kind = "destroy", reviewKey = action, action = action, characterKey = destroyer })
end

-- A row per destroying action with a destroyer other than this character, added to `plan`. Returns
-- the rows added.
local function addDestroyDestinations(pe, plan, bags)
	local added, current = {}, pe:GetCharacterKey()
	for _, action in ipairs(pe:GetClientSalvageActions()) do
		local destroyer = pe:GetDestroyerCharacterKey(action)
		local dest = destroyer and destroyer ~= current and destroyDestination(pe, plan, bags, action, destroyer)
		if dest then
			plan[#plan + 1] = dest
			added[#added + 1] = dest
		end
	end
	return added
end

-- Crafted items owed to the seller. Ones that left the bags some other way are no longer owed.
local function addCraftsDestination(pe, plan, bags, seller)
	local toSeller = characterStore(pe, "toSellerByCharacter")
	for itemID, owed in pairs(toSeller) do
		local held = bags[itemID] and bags[itemID].quantity or 0
		toSeller[itemID] = held > 0 and math.min(owed, held) or nil
	end
	for _, dest in ipairs(pe:SetMailRecipients(pe.MailLogic.BuildReturnToSellerPlan(toSeller, bags, seller))) do
		plan[#plan + 1] = dest
	end
end

--- Everything the mailbox panel can send from this character: materials for crafters; items to
--- destroy to the disenchanter, prospector and miller; and on any character but the seller the
--- crafted items owed to it and the surplus above keep amounts. Each destination carries its `kind`;
--- the ones with a review panel (surplus, destroy) also a `reviewKey`. Rows take items in this order,
--- what one sends being held back from the rows after; the rows to destroy are listed first.
function Tradewright:BuildMailPanelPlan()
	local plan = self:BuildShoppingMailSendPlan()
	for _, dest in ipairs(plan) do
		dest.kind = "materials"
	end
	local bags = self:GetBagItems()
	local seller = self:GetSellerCharacterKey()
	local toSeller = seller ~= nil and seller ~= self:GetCharacterKey()
	if toSeller then
		addCraftsDestination(self, plan, bags, seller)
	end
	local listed = addDestroyDestinations(self, plan, bags)
	for _, dest in ipairs(plan) do
		if dest.kind ~= "destroy" then
			listed[#listed + 1] = dest
		end
	end
	if toSeller then
		listed[#listed + 1] = surplusDestination(self, listed, bags, seller)
	end
	return listed
end

--- A parcel reached the mail server: crafted items in it are no longer owed to the seller.
function Tradewright:OnMailParcelSent(parcel)
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
function Tradewright:GetMailSkipped()
	self._mailSkipped = self._mailSkipped or {}
	return self._mailSkipped
end

function Tradewright:SetMailSkipped(itemID, skipped)
	self:GetMailSkipped()[tonumber(itemID)] = skipped and true or nil
end

function Tradewright:ClearMailSkipped()
	self._mailSkipped = nil
end

function Tradewright:ClearMailKeepAmounts()
	wipe(characterStore(self, "keepByCharacter"))
end

--- Unit price for the review panel's Worth: the usual price, else the last scanned price.
function Tradewright:GetMailItemUnitPrice(itemID)
	local signals = self.GetItemPriceSignals and self:GetItemPriceSignals(itemID)
	if signals and signals.usual then
		return signals.usual
	end
	return self.GetNativeAhPrice and self:GetNativeAhPrice(itemID) or nil
end

--- The review rows and the destination of `panelPlan` (BuildMailPanelPlan, built when not given)
--- whose review panel is `reviewKey` ("surplus", or a destroying action); the first destination with
--- a review panel when `reviewKey` is nil. No rows when the plan has no such destination.
function Tradewright:BuildMailReviewRows(panelPlan, reviewKey)
	for _, dest in ipairs(panelPlan or self:BuildMailPanelPlan()) do
		if dest.reviewKey and (reviewKey == nil or dest.reviewKey == reviewKey) then
			return dest.reviewRows, dest
		end
	end
	return {}, nil
end

--- Keep everything of one review panel's rows the bags hold now, so nothing goes until the bags grow.
function Tradewright:KeepCurrentMailBags(reviewKey)
	for _, row in ipairs((self:BuildMailReviewRows(nil, reviewKey))) do
		if row.bags > 0 then
			self:SetMailKeepAmount(row.itemID, row.bags)
		end
	end
end
