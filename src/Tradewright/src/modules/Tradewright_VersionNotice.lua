local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Tells the player when a newer version of the addon exists. An addon cannot reach the web, so the
-- only source is another player's client: every client shares its version with guild and group
-- through addon messages (a chat channel players do not see), and one that hears of a newer version
-- says so once in chat. The newest version heard is kept in `baseDb.meta.newestVersionSeen`, so the
-- line also shows at the next login when nobody with that version is online.
-- Anyone can send any text on the prefix, so a received version is only ever shown, never acted on.

local VersionLogic = Tradewright.VersionLogic

-- Older clients have the global functions instead of C_ChatInfo.
local chatInfo = C_ChatInfo or {}
local registerPrefix = chatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
local sendAddonMessage = chatInfo.SendAddonMessage or SendAddonMessage
if not (registerPrefix and sendAddonMessage) then
	return
end

-- The client allows at most 16 characters.
local MESSAGE_PREFIX = "Tradewright"
-- Saved data is merged a moment after login, and the line should come after the login chatter.
local LOGIN_DELAY_SEC = 8
-- Many older clients can log in at once; one answer per channel in this time tells them all.
local ANSWER_COOLDOWN_SEC = 60
-- Channels an answer can go back on as it came. A whisper would need the sender's name.
local ANSWER_CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

local noticeShown = false
local lastGroupChannel = nil
local lastAnswerAt = {}

local function shareVersion(channel)
	local message = VersionLogic.EncodeMessage(Tradewright.VERSION)
	if message then
		-- The client refuses addon messages in some situations (retail, inside instances).
		pcall(sendAddonMessage, MESSAGE_PREFIX, message, channel)
	end
end

local function groupChannel()
	-- Without the constant, IsInGroup(nil) would mean any group.
	local inInstanceGroup = LE_PARTY_CATEGORY_INSTANCE ~= nil and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	return VersionLogic.GroupChannel(inInstanceGroup, IsInRaid(), IsInGroup())
end

-- The roster event fires for every change in the group; share only when the channel is a new one.
local function shareWithNewGroup()
	local channel = groupChannel()
	if channel ~= lastGroupChannel then
		lastGroupChannel = channel
		if channel then
			shareVersion(channel)
		end
	end
end

-- One chat line per session, when a newer version is known and the setting asks for it.
local function showNotice(pe)
	local newest = pe.baseDb.meta.newestVersionSeen
	if noticeShown or not VersionLogic.IsNewer(newest, pe.VERSION) then
		return
	end
	if pe:GetSetting("general.versionNotice", true) == false then
		return
	end
	noticeShown = true
	pe:PrintMessage(string.format(L["Version %s is available. You have %s."], newest, pe.VERSION))
end

-- Tell an older client this version, on the channel it was heard on.
local function answerOlderClient(channel)
	local now = time()
	if ANSWER_CHANNELS[channel] and now - (lastAnswerAt[channel] or 0) >= ANSWER_COOLDOWN_SEC then
		lastAnswerAt[channel] = now
		shareVersion(channel)
	end
end

local function onVersionHeard(pe, version, channel)
	local meta = pe.baseDb.meta
	if VersionLogic.IsNewer(version, pe.VERSION) then
		if VersionLogic.IsNewer(version, meta.newestVersionSeen or pe.VERSION) then
			meta.newestVersionSeen = version
		end
		showNotice(pe)
	elseif VersionLogic.IsNewer(pe.VERSION, version) then
		answerOlderClient(channel)
	end
end

local function onLogin(pe)
	local meta = pe.baseDb.meta
	-- The addon has been updated since the newer version was heard of.
	if not VersionLogic.IsNewer(meta.newestVersionSeen, pe.VERSION) then
		meta.newestVersionSeen = nil
	end
	showNotice(pe)
	if IsInGuild() then
		shareVersion("GUILD")
	end
	shareWithNewGroup()
end

pcall(registerPrefix, MESSAGE_PREFIX)

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON" }) do
	pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, prefix, message, channel)
	if event == "PLAYER_LOGIN" then
		C_Timer.After(LOGIN_DELAY_SEC, function()
			if Tradewright.baseDb then
				onLogin(Tradewright)
			end
		end)
	elseif not Tradewright.baseDb then
		return
	elseif event == "GROUP_ROSTER_UPDATE" then
		shareWithNewGroup()
	elseif prefix == MESSAGE_PREFIX then
		local version = VersionLogic.DecodeMessage(message)
		if version then
			onVersionHeard(Tradewright, version, channel)
		end
	end
end)
