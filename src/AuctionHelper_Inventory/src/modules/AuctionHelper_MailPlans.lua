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
