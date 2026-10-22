local T = require("./TestKit")
local Config = require("../src/shared/Config")
local FairMath = require("../src/shared/FairMath")

local F = Config.Fair

T.describe("FairMath", function()
	T.it("week ids roll over exactly at the anchor boundary", function()
		local start = FairMath.weekStartsAt(100, F)
		T.eq(FairMath.weekId(start, F), 100)
		T.eq(FairMath.weekId(start - 1, F), 99)
		T.eq(FairMath.weekId(FairMath.weekEndsAt(100, F) - 1, F), 100)
		T.eq(FairMath.secondsUntilRollover(start, F), F.weekSeconds)
	end)
	T.it("converts weights to integer gram scores and back", function()
		T.eq(FairMath.weightToScore(12.3456), 12345)
		T.near(FairMath.scoreToWeight(12345), 12.345)
	end)
	T.it("maps ranks to tiers", function()
		T.eq(FairMath.tierForRank(1, F.rewardTiers).id, "blue")
		T.eq(FairMath.tierForRank(10, F.rewardTiers).id, "blue")
		T.eq(FairMath.tierForRank(11, F.rewardTiers).id, "red")
		T.eq(FairMath.tierForRank(nil, F.rewardTiers).id, "entrant")
	end)
	T.it("finds finished, unclaimed weeks oldest first", function()
		local entries = { ["5"] = {}, ["3"] = {}, ["7"] = {}, ["8"] = {} }
		local claimed = { ["3"] = true }
		local weeks = FairMath.unclaimedWeeks(entries, claimed, 8)
		T.eq(#weeks, 2)
		T.eq(weeks[1], 5)
		T.eq(weeks[2], 7)
	end)
end)

return nil
