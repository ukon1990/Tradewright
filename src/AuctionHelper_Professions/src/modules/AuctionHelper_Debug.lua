local _, AuctionHelper = ...

function AuctionHelper:GetDebugLogStore()
	self:InitDB()
	self.db.debug = self.db.debug or {}
	local debugDb = self.db.debug
	debugDb.lines = debugDb.lines or {}
	if debugDb.maxLines == nil then
		debugDb.maxLines = 100
	end
	return debugDb
end

function AuctionHelper:ClearDebugLog()
	local debugDb = self:GetDebugLogStore()
	debugDb.lines = {}
	debugDb.lastClearedAt = time()
end

function AuctionHelper:PersistDebugLine(category, title, line)
	if self:GetSetting("debug.persistToSavedVariables", false) ~= true then
		return
	end
	local debugDb = self:GetDebugLogStore()
	local ts = date("%Y-%m-%d %H:%M:%S")
	local entry = string.format("[%s] [%s] %s", ts, tostring(category or "?"), tostring(title or ""))
	if line and line ~= "" then
		entry = entry .. " :: " .. tostring(line)
	end
	table.insert(debugDb.lines, entry)
	local maxLines = math.max(20, math.min(100, tonumber(debugDb.maxLines) or 100))
	while #debugDb.lines > maxLines do
		table.remove(debugDb.lines, 1)
	end
	debugDb.lastWriteAt = time()
end

--- @return boolean
function AuctionHelper:IsDebugEnabled()
	self:InitDB()
	return self:GetSetting("debug.enabled", false) == true
end

function AuctionHelper:SetDebugEnabled(enabled)
	self:SetSetting("debug.enabled", enabled and true or false)
	if self:GetSetting("debug.enabled", false) then
		self:PersistDebugLine("SETTINGS", "debug logging enabled", "Persistent log storage is enabled.")
		self:DebugLog("SETTINGS", "debug logging enabled", {
			"Verbose EVENT / LIVE / SCAN / UI lines will print to this chat until you disable it.",
			self:GetSetting("debug.persistToSavedVariables", false) == true
				and "Persistent debug ring buffer is stored in SavedVariables under AuctionHelperDB.settings.debug.lines."
				or "Persistent debug storage is disabled by default; debug output is chat-only unless you enable SavedVariables persistence.",
			"Toggle: dashboard checkbox or |cffffffff/ah debug|r (on|off|toggle).",
		})
	else
		self:PrintMessage("Debug logging disabled.")
	end
end

--- Shallow table preview for chat (avoids megabytes of output).
function AuctionHelper:DebugFormatShallowTable(tbl, maxPairs)
	if type(tbl) ~= "table" then
		return tostring(tbl)
	end
	maxPairs = maxPairs or 12
	local n = 0
	local parts = {}
	for k, v in pairs(tbl) do
		n = n + 1
		if n > maxPairs then
			table.insert(parts, "...")
			break
		end
		local vt = type(v)
		if vt == "table" then
			table.insert(parts, string.format("%s=<table>", tostring(k)))
		elseif vt == "string" then
			local s = v
			if #s > 80 then
				s = s:sub(1, 80) .. "…"
			end
			table.insert(parts, string.format("%s=%q", tostring(k), s))
		else
			table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
		end
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

--- Serialize event arguments for one chat-friendly line (tables summarized).
function AuctionHelper:DebugSerializeEventArgs(...)
	local n = select("#", ...)
	if n == 0 then
		return "(no args)"
	end
	local parts = {}
	for i = 1, n do
		local v = select(i, ...)
		local t = type(v)
		if t == "nil" then
			table.insert(parts, string.format("[%d]=nil", i))
		elseif t == "table" then
			local count = 0
			for _ in pairs(v) do
				count = count + 1
			end
			table.insert(parts, string.format("[%d]=<table keys=%d %s>", i, count, self:DebugFormatShallowTable(v, 6)))
		else
			local s = tostring(v)
			if #s > 120 then
				s = s:sub(1, 120) .. "…"
			end
			table.insert(parts, string.format("[%d]=%s", i, s))
		end
	end
	return table.concat(parts, " ")
end

--- Reusable verbose logger: timestamp, category, title, then optional detail lines.
function AuctionHelper:DebugLog(category, title, detail)
	if not self:IsDebugEnabled() then
		return
	end
	local ts = date("%H:%M:%S")
	DEFAULT_CHAT_FRAME:AddMessage(string.format(
		"|cff888888[PE %s]|r |cffffcc00[%s]|r %s",
		ts,
		tostring(category or "?"),
		tostring(title or "")
	))
	self:PersistDebugLine(category, title, nil)
	if detail == nil then
		return
	end
	if type(detail) == "table" then
		for _, line in ipairs(detail) do
			DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa" .. tostring(line) .. "|r")
			self:PersistDebugLine(category, title, line)
		end
	else
		DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa" .. tostring(detail) .. "|r")
		self:PersistDebugLine(category, title, detail)
	end
end

function AuctionHelper:DebugLogEvent(event, ...)
	if not self:IsDebugEnabled() then
		return
	end
	local state = self:GetState()
	local extras = {
		"args: " .. self:DebugSerializeEventArgs(...),
		string.format(
			"state: scanInProgress=%s pendingScan=%s queueRemaining=%d currentProfession=%s",
			tostring(state.scanInProgress),
			tostring(state.pendingScan),
			state.queue and #state.queue or 0,
			state.currentProfession and tostring(state.currentProfession.professionName) or "nil"
		),
		string.format("characterKey=%s", tostring(self:GetCharacterKey())),
	}
	self:DebugLog("EVENT", tostring(event), extras)
end
