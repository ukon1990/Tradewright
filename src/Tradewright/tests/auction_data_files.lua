-- The Tradewright_AuctionData files tests load, in TOC order: everything before the panel refresh file.
return function(addonsRoot)
	local toc = assert(io.open(addonsRoot .. "/Tradewright_AuctionData/Tradewright_AuctionData.toc", "r"))
	local paths = {}
	for line in toc:lines() do
		local file = line:match("^src\\modules\\(.+%.lua)%s*$")
		if file == "Tradewright_AuctionPanelRefresh.lua" then
			break
		end
		if file then
			paths[#paths + 1] = "Tradewright_AuctionData/src/modules/" .. file
		end
	end
	toc:close()
	return paths
end
