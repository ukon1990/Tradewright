-- The AuctionHelper_AuctionData files tests load, in TOC order: everything before the panel refresh file.
return function(addonsRoot)
	local toc = assert(io.open(addonsRoot .. "/AuctionHelper_AuctionData/AuctionHelper_AuctionData.toc", "r"))
	local paths = {}
	for line in toc:lines() do
		local file = line:match("^src\\modules\\(.+%.lua)%s*$")
		if file == "AuctionHelper_AuctionPanelRefresh.lua" then
			break
		end
		if file then
			paths[#paths + 1] = "AuctionHelper_AuctionData/src/modules/" .. file
		end
	end
	toc:close()
	return paths
end
