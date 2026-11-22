local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Mail send queue: splits mail destinations into parcels and sends them one by one through the
-- game's Send Mail window, automatically or prepared for the player to send.
-- Retail always; Forever when send-mail + bag APIs exist.
if not Tradewright.IS_RETAIL then
	if not (Tradewright.IS_FOREVER and C_Container and C_Container.GetContainerNumSlots and GetSendMailItem and ClickSendMailItemButton) then
		return
	end
end

local ATTACHMENTS_MAX = ATTACHMENTS_MAX_SEND or 12
local AUTO_SEND_TIMEOUT = 6
local MAIL_SUBJECTS = { materials = L["Tradewright reagents"], crafts = L["Tradewright crafts"], surplus = L["Tradewright surplus"] }
local MAIL_BODY = L["Sent with Tradewright."]

local function clearMailAttachments()
	for i = 1, ATTACHMENTS_MAX do
		if GetSendMailItem and GetSendMailItem(i) then
			ClickSendMailItemButton(i, true)
		end
	end
end

local function setMailField(box, text)
	if box and box.SetText then
		box:SetText(text)
	end
end

local function findBagSlotForItem(itemID)
	local foundBag, foundSlot, stack
	Tradewright:ForEachBagSlot(nil, function(bag, slot, info)
		if info and tonumber(info.itemID) == tonumber(itemID) and (tonumber(info.stackCount) or 0) > 0 then
			foundBag, foundSlot, stack = bag, slot, tonumber(info.stackCount)
			return true
		end
	end)
	return foundBag, foundSlot, stack
end

local function attachItemQuantity(itemID, quantity)
	quantity = math.max(1, math.floor(tonumber(quantity) or 0))
	local remaining = quantity
	while remaining > 0 do
		local bag, slot, stack = findBagSlotForItem(itemID)
		if not bag then
			return false, quantity - remaining
		end
		local take = math.min(remaining, stack)
		if take < stack and C_Container.SplitContainerItem then
			C_Container.SplitContainerItem(bag, slot, take)
			bag, slot = findBagSlotForItem(itemID)
			if not bag then
				return false, quantity - remaining
			end
		end
		C_Container.PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		remaining = remaining - take
	end
	return true, quantity
end

-- Largest stack of an item by ID. C_Item.GetItemMaxStackSize wants an item location, not an ID.
local function itemStackSize(itemID)
	local size = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
	if not size and GetItemInfo then
		size = select(8, GetItemInfo(itemID))
	end
	return tonumber(size)
end

function Tradewright:GetItemStackSize(itemID)
	return itemStackSize(itemID)
end

local function buildMailParcels(destinations)
	local parcels = {}
	for _, dest in ipairs(destinations or {}) do
		local parcelItems = {}
		local parcelCount = 0
		local function flush()
			if #parcelItems > 0 then
				parcels[#parcels + 1] = {
					mailName = dest.mailName,
					characterKey = dest.characterKey,
					kind = dest.kind,
					items = parcelItems,
				}
				parcelItems = {}
				parcelCount = 0
			end
		end
		for _, item in ipairs(dest.items or {}) do
			local qtyLeft = tonumber(item.quantity) or 0
			while qtyLeft > 0 do
				if parcelCount >= ATTACHMENTS_MAX then
					flush()
				end
				local attachQty = math.min(qtyLeft, itemStackSize(item.itemID) or 200)
				parcelItems[#parcelItems + 1] = {
					itemID = item.itemID,
					quantity = attachQty,
					name = item.name,
				}
				parcelCount = parcelCount + 1
				qtyLeft = qtyLeft - attachQty
			end
		end
		flush()
	end
	return parcels
end

--- How many mails the destinations take (12 attachments each, stacks split at their size).
function Tradewright:CountMailParcels(destinations)
	return #buildMailParcels(destinations)
end

-- An automatic send has no click behind it. If the client ignores it, hand back to the buttons.
local function watchAutoSend(queueState)
	local index = queueState.index
	C_Timer.After(AUTO_SEND_TIMEOUT, function()
		if queueState.running and queueState.auto and queueState.index == index then
			Tradewright:CancelMailSendQueue()
			Tradewright:PrintMessage(L["Could not mail the reagents automatically. Use Attach all in the mail panel."])
		end
	end)
end

-- Attaches a parcel and fills in To, Subject and body in the game's Send Mail window. Automatic
-- sends go out at once; the buttons leave the mail for the player to check and send.
local function fillParcel(pe, parcel, queueState)
	clearMailAttachments()
	for _, item in ipairs(parcel.items or {}) do
		if not attachItemQuantity(item.itemID, item.quantity) then
			pe:PrintMessage(string.format(L["Could not attach all of %s for %s."], tostring(item.name or item.itemID), tostring(parcel.mailName)))
		end
	end
	local subject = string.format("%s %d/%d", MAIL_SUBJECTS[parcel.kind] or MAIL_SUBJECTS.materials, queueState.index, queueState.total)
	setMailField(SendMailNameEditBox, parcel.mailName)
	setMailField(SendMailSubjectEditBox, subject)
	setMailField(SendMailBodyEditBox, MAIL_BODY)
	if queueState.auto and SendMail then
		SendMail(parcel.mailName, subject, MAIL_BODY)
		watchAutoSend(queueState)
	end
end

function Tradewright:EnsureMailSendQueueState()
	self._mailSendQueue = self._mailSendQueue or {
		parcels = {},
		index = 0,
		running = false,
		cancel = false,
		sent = 0,
		total = 0,
	}
	return self._mailSendQueue
end

--- Stops the queue at once. A send the client never answers would otherwise leave it running.
function Tradewright:CancelMailSendQueue()
	local queueState = self:EnsureMailSendQueueState()
	queueState.cancel = true
	queueState.running = false
	if MailFrame and MailFrame:IsShown() then
		clearMailAttachments()
		for _, box in ipairs({ SendMailNameEditBox, SendMailSubjectEditBox, SendMailBodyEditBox }) do
			setMailField(box, "")
		end
	end
	if self.ui and self.ui.mailPanel and self.ui.mailPanel:IsShown() then
		self:RefreshMailPanel()
	end
end

-- The last parcel went (or the queue was cancelled): back to the inbox for automatic sends,
-- report what was mailed and refresh what depends on the bags.
function Tradewright:FinishMailSendQueue(queueState)
	queueState.running = false
	if queueState.auto and MailFrameTab1 and MailFrameTab1.Click then
		MailFrameTab1:Click()
	end
	if self.RefreshMailPanel then
		self:RefreshMailPanel()
	end
	if queueState.sent and queueState.sent > 0 then
		self:PrintMessage(string.format(L["Tradewright sent %d mails."], queueState.sent))
	end
	if self.ScheduleLiveInventoryRefresh then
		self:ScheduleLiveInventoryRefresh()
	end
end

function Tradewright:CountMailParcelSent(queueState)
	queueState.sent = (queueState.sent or 0) + 1
	local parcel = queueState.parcels and queueState.parcels[queueState.index]
	if parcel and self.OnMailParcelSent then
		self:OnMailParcelSent(parcel)
	end
end

function Tradewright:AdvanceMailSendQueue(success)
	local queueState = self:EnsureMailSendQueueState()
	if not queueState.running then
		return
	end
	if success then
		self:CountMailParcelSent(queueState)
	end
	queueState.index = (queueState.index or 0) + 1
	if queueState.cancel or queueState.index > #(queueState.parcels or {}) then
		return self:FinishMailSendQueue(queueState)
	end
	C_Timer.After(0.35, function()
		Tradewright:ProcessNextMailParcel()
	end)
end

function Tradewright:ProcessNextMailParcel()
	local queueState = self:EnsureMailSendQueueState()
	if queueState.cancel or not queueState.running then
		queueState.running = false
		return
	end
	local parcel = queueState.parcels and queueState.parcels[queueState.index]
	if not parcel then
		self:AdvanceMailSendQueue(false)
		return
	end
	if self.RefreshMailPanel then
		self:RefreshMailPanel()
	end
	if not MailFrame or not MailFrame:IsShown() then
		self:PrintMessage(L["Open the mailbox to send reagents."])
		queueState.running = false
		queueState.cancel = true
		return
	end
	if MailFrameTab2 and MailFrameTab2.Click then
		MailFrameTab2:Click()
	end
	fillParcel(self, parcel, queueState)
end

function Tradewright:StartMailSendQueue(destinations, auto)
	local parcels = buildMailParcels(destinations)
	if #parcels == 0 then
		if not auto then
			self:PrintMessage(L["No reagents to mail from your bags."])
		end
		return false
	end
	local queueState = self:EnsureMailSendQueueState()
	queueState.parcels = parcels
	queueState.index = 1
	queueState.sent = 0
	queueState.total = #parcels
	queueState.running = true
	queueState.cancel = false
	queueState.auto = auto == true
	self:ProcessNextMailParcel()
	return true
end

--- On the bank character, mails every crafter whose materials are all in the bags.
--- Runs once per mailbox visit; incomplete sets wait for the Send buttons.
function Tradewright:AutoSendReadyMaterials()
	if not (self.IsSellerCharacter and self:IsSellerCharacter()) or self:GetSetting("mail.autoSendMaterials", true) == false
		or self:EnsureMailSendQueueState().running then
		return
	end
	local ready, names = {}, {}
	for _, dest in ipairs(self:BuildShoppingMailSendPlan()) do
		if dest.complete then
			ready[#ready + 1] = dest
			names[#names + 1] = string.format("%s (%s)", self:GetMailCharacterLabel(dest.characterKey), self:FormatNumberGrouped(dest.totalQuantity))
		end
	end
	if self:StartMailSendQueue(ready, true) then
		self:PrintMessage(L["Mailing reagents to "] .. table.concat(names, ", ") .. ".")
	end
end

--- Materials and crafted items; the surplus only goes from its review panel.
function Tradewright:GetReadyMailDestinations(plan)
	local ready = {}
	for _, dest in ipairs(plan) do
		if dest.kind ~= "surplus" and (tonumber(dest.totalQuantity) or 0) > 0 then
			ready[#ready + 1] = dest
		end
	end
	return ready
end

function Tradewright:StartMailSendAll()
	return self:StartMailSendQueue(self:GetReadyMailDestinations(self:BuildMailPanelPlan()))
end

local function nameOnly(name)
	return tostring(name or ""):match("^[^%-]+") or ""
end

--- A send went through. While mails are prepared, a mail the player sent to someone else is not
--- the prepared parcel: that parcel is filled in again instead of counted as sent.
function Tradewright:OnMailSendSuccess()
	local queueState = self:EnsureMailSendQueueState()
	local parcel = queueState.running and queueState.parcels and queueState.parcels[queueState.index]
	if parcel and not queueState.auto and nameOnly(self._lastMailTo):lower() ~= nameOnly(parcel.mailName):lower() then
		C_Timer.After(0.35, function() Tradewright:ProcessNextMailParcel() end)
		return
	end
	self:AdvanceMailSendQueue(true)
end

--- A failed automatic send moves on; a prepared mail stays as it is for the player to fix or cancel.
function Tradewright:OnMailSendFailed()
	self:PrintMessage(L["Mail send failed."])
	if self:EnsureMailSendQueueState().auto then
		self:AdvanceMailSendQueue(false)
	end
end
