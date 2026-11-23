local _, Tradewright = ...

--- Pure helper for comparing addon versions and for the message clients share theirs with. No WoW API.
local VersionLogic = {}
Tradewright.VersionLogic = VersionLogic

-- Version text comes from other players' clients, so anything longer than a real version is refused.
local MAX_VERSION_LENGTH = 20
local PARTS = { "major", "minor", "patch" }
-- The leading letter names the kind of message, so the same prefix can carry other kinds later.
local MESSAGE_START = "V "

--- `"1.10.0"` as `{ major = 1, minor = 10, patch = 0 }`; nil for anything that is not three plain numbers.
function VersionLogic.Parse(text)
	if type(text) ~= "string" or #text > MAX_VERSION_LENGTH then
		return nil
	end
	local major, minor, patch = text:match("^(%d+)%.(%d+)%.(%d+)$")
	if not major then
		return nil
	end
	return { major = tonumber(major), minor = tonumber(minor), patch = tonumber(patch) }
end

--- Is `candidate` a later version than `current`? False when either is not a version.
function VersionLogic.IsNewer(candidate, current)
	local candidateParts, currentParts = VersionLogic.Parse(candidate), VersionLogic.Parse(current)
	if not (candidateParts and currentParts) then
		return false
	end
	for _, part in ipairs(PARTS) do
		if candidateParts[part] ~= currentParts[part] then
			return candidateParts[part] > currentParts[part]
		end
	end
	return false
end

--- The message that tells other clients this version, or nil when `version` is not a version.
function VersionLogic.EncodeMessage(version)
	return VersionLogic.Parse(version) and (MESSAGE_START .. version) or nil
end

--- The version a received message tells, or nil when the message is something else.
function VersionLogic.DecodeMessage(message)
	if type(message) ~= "string" or message:sub(1, #MESSAGE_START) ~= MESSAGE_START then
		return nil
	end
	local version = message:sub(#MESSAGE_START + 1)
	return VersionLogic.Parse(version) and version or nil
end

--- The chat channel that reaches the player's group, or nil outside a group.
--- A group made by the group finder only hears INSTANCE_CHAT.
function VersionLogic.GroupChannel(inInstanceGroup, inRaid, inGroup)
	if inInstanceGroup then
		return "INSTANCE_CHAT"
	elseif inRaid then
		return "RAID"
	elseif inGroup then
		return "PARTY"
	end
	return nil
end

return VersionLogic
