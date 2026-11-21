local _, AuctionHelper = ...

-- Gold history per character (`db.walletHistory`, hour buckets) and the overview's gold graph and summary.

local ItemHistory = AuctionHelper.ItemHistory
local RANGE_TO_SECONDS = ItemHistory.RANGE_TO_SECONDS
local trimHistoryBuckets = ItemHistory.trimHistoryBuckets

function AuctionHelper:EnsureWalletHistoryStore(characterKey)
	self:InitDB()
	characterKey = characterKey and tostring(characterKey) or ""
	if characterKey == "" then
		return nil
	end
	self.db.walletHistory = self.db.walletHistory or {}
	local walletStore = self.db.walletHistory[characterKey]
	if not walletStore then
		walletStore = { buckets = {} }
		self.db.walletHistory[characterKey] = walletStore
	end
	return walletStore
end

function AuctionHelper:RecordWalletObservation(characterKey, copper, observedAt)
	characterKey = characterKey and tostring(characterKey) or ""
	local n = tonumber(copper)
	if characterKey == "" or not n or n < 0 then
		return
	end
	local store = self:EnsureWalletHistoryStore(characterKey)
	if not store then
		return
	end
	store.buckets = store.buckets or {}
	observedAt = tonumber(observedAt) or time()
	local bucketAt = observedAt - (observedAt % 3600)
	local bucket = store.buckets[tostring(bucketAt)] or {}
	bucket.count = (bucket.count or 0) + 1
	bucket.sum = (bucket.sum or 0) + n
	bucket.last = n
	bucket.min = bucket.min and math.min(bucket.min, n) or n
	bucket.max = bucket.max and math.max(bucket.max, n) or n
	store.buckets[tostring(bucketAt)] = bucket
	-- Gold history keeps a year regardless of the item-history retention setting.
	trimHistoryBuckets(store.buckets, time() - RANGE_TO_SECONDS["1y"])
	self:NotifyWalletHistoryUpdate()
end

function AuctionHelper:NotifyWalletHistoryUpdate()
	local ui = self.ui
	if not ui or ui.activeMainTab ~= "overview" then
		return
	end
	local mf = ui.mainFrame
	if not mf or not mf:IsShown() then
		return
	end
	if self.OverviewTab and self.OverviewTab.Refresh then
		self.OverviewTab:Refresh()
	end
end

function AuctionHelper:RecordWalletObservationFromCharacterData(characterData)
	local key = characterData and characterData.meta and characterData.meta.key
	if not key or key ~= self:GetCharacterKey() then
		return
	end
	self:RecordWalletObservation(key, GetMoney(), time())
end

local function walletSortedList(bucketMap, cutoff)
	local list = {}
	for key, bucket in pairs(bucketMap or {}) do
		local at = tonumber(key)
		if at and at > 0 and (not cutoff or at >= cutoff) then
			list[#list + 1] = {
				at = at,
				last = bucket.last,
				count = bucket.count or 0,
			}
		end
	end
	table.sort(list, function(left, right)
		return left.at < right.at
	end)
	return list
end

function AuctionHelper:WalletHistoryToGraphSeries(characterKey, rangeKey)
	self:InitDB()
	local walletStore = self.db.walletHistory and self.db.walletHistory[tostring(characterKey)] or nil
	if not walletStore then
		return {}
	end
	local raw = walletSortedList(walletStore.buckets, self:GetHistoryRangeCutoff(rangeKey))
	local out = {}
	for _, point in ipairs(raw) do
		local v = tonumber(point.last)
		if v then
			out[#out + 1] = { at = point.at, value = v, meta = { count = point.count } }
		end
	end
	return out
end

function AuctionHelper:WalletBalanceSeriesToEarned(balanceSeries)
	local out = {}
	for i = 2, #(balanceSeries or {}) do
		local prev = balanceSeries[i - 1].value
		local cur = balanceSeries[i].value
		out[#out + 1] = {
			at = balanceSeries[i].at,
			value = cur - prev,
			meta = {
				previous = prev,
				current = cur,
			},
		}
	end
	return out
end

-- Account gold per hour: at each hour any character was seen, the sum of every character's last
-- known balance at or before that hour (a character not seen yet adds nothing).
function AuctionHelper:BuildAccountWalletBalanceSeries(rangeKey)
	self:InitDB()
	local cutoff = self:GetHistoryRangeCutoff(rangeKey)
	local charLists = {}
	for characterKey, walletStore in pairs(self.db.walletHistory or {}) do
		local list = walletSortedList(walletStore.buckets, cutoff)
		if #list > 0 then
			charLists[tostring(characterKey)] = list
		end
	end
	local hourSet = {}
	for _, list in pairs(charLists) do
		for _, point in ipairs(list) do
			hourSet[point.at] = true
		end
	end
	local hours = {}
	for at in pairs(hourSet) do
		hours[#hours + 1] = at
	end
	table.sort(hours)
	local indices = {}
	local result = {}
	for _, H in ipairs(hours) do
		local sum = 0
		local any = false
		for characterKey, list in pairs(charLists) do
			local idx = indices[characterKey] or 1
			while idx < #list and list[idx + 1].at <= H do
				idx = idx + 1
			end
			indices[characterKey] = idx
			local entry = list[idx]
			if entry and entry.at <= H and entry.last then
				sum = sum + (tonumber(entry.last) or 0)
				any = true
			end
		end
		if any then
			result[#result + 1] = { at = H, value = sum, meta = { account = true } }
		end
	end
	return result
end

function AuctionHelper:GetOverviewWalletGraphSeries(selectedCharacterKey, rangeKey, mode)
	local acct = self.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"
	local balance
	if selectedCharacterKey == acct then
		balance = self:BuildAccountWalletBalanceSeries(rangeKey)
	else
		balance = self:WalletHistoryToGraphSeries(selectedCharacterKey, rangeKey)
	end
	if mode == "earned" then
		return self:WalletBalanceSeriesToEarned(balance)
	end
	return balance
end

function AuctionHelper:GetCurrentGoldSummaryForOverview(selectedCharacterKey)
	local acct = self.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"
	self:InitDB()
	local currentKey = self:GetCharacterKey()

	local function lastStoredCopperForKey(characterKey)
		local walletStore = self.db.walletHistory and self.db.walletHistory[tostring(characterKey)] or nil
		if not walletStore then
			return nil
		end
		local bestAt, bestVal = nil, nil
		for hourKey, bucket in pairs(walletStore.buckets or {}) do
			local at = tonumber(hourKey)
			local v = tonumber(bucket.last)
			if at and v and (not bestAt or at > bestAt) then
				bestAt = at
				bestVal = v
			end
		end
		return bestVal
	end

	if selectedCharacterKey == acct then
		local total = 0
		for characterKey, _ in pairs(self.db.characters or {}) do
			if characterKey == currentKey then
				total = total + GetMoney()
			else
				local v = lastStoredCopperForKey(characterKey)
				if v then
					total = total + v
				end
			end
		end
		return total
	end

	local characterKey = tostring(selectedCharacterKey or "")
	if characterKey == currentKey then
		return GetMoney()
	end
	return lastStoredCopperForKey(characterKey)
end
