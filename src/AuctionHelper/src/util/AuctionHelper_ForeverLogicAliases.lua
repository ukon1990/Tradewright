-- Old ForeverLogic names for helpers that moved to their own modules; other addons still call them
-- through ForeverLogic. Each forwards at call time, so load order does not matter. Remove a name once
-- nothing calls ForeverLogic.<name> any more.
local _, AuctionHelper = ...

local ForeverLogic = AuctionHelper.ForeverLogic
local MOVED = {
	AuctionLogic = {
		"AggregateClassicAuctionRow",
		"ShouldUseClassicSellInject",
		"SummarizeOwnedAuctions",
		"LiveSearchDiffers",
	},
	FilterLogic = {
		"PageBounds",
	},
	IncomeLogic = {
		"SummarizeSales",
	},
	MailLogic = {
		"ResolveSellerCharacter",
		"BuildMailPlan",
		"BuildReturnToSellerPlan",
	},
	MarketLogic = {
		"NormalizeMarketSnapshotFields",
		"BuildMarketHistorySeries",
		"SummarizeHourlyHistory",
		"ClassifyMarketItem",
		"TopN",
		"BuildMarketBrowserRows",
		"FilterMarketRows",
		"ResolveDealRowClick",
	},
	MaterialLogic = {
		"ResolveLocationCounts",
	},
}

for moduleName, names in pairs(MOVED) do
	for _, name in ipairs(names) do
		ForeverLogic[name] = function(...)
			return AuctionHelper[moduleName][name](...)
		end
	end
end
