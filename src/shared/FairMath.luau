--!strict
--[[
	FairMath: pure helpers for the weekly weigh-in. No requires.

	A "week id" is the number of whole fair weeks since Config.Fair.weekAnchorUnix.
	Every server agrees on it because it only depends on os.time().
]]

local FairMath = {}

function FairMath.weekId(now: number, fairConfig: any): number
	return math.floor((now - fairConfig.weekAnchorUnix) / fairConfig.weekSeconds)
end

function FairMath.weekStartsAt(weekId: number, fairConfig: any): number
	return fairConfig.weekAnchorUnix + weekId * fairConfig.weekSeconds
end

function FairMath.weekEndsAt(weekId: number, fairConfig: any): number
	return FairMath.weekStartsAt(weekId + 1, fairConfig)
end

function FairMath.secondsUntilRollover(now: number, fairConfig: any): number
	return FairMath.weekEndsAt(FairMath.weekId(now, fairConfig), fairConfig) - now
end

-- OrderedDataStore only stores integers, so weights are kept in grams.
function FairMath.weightToScore(weightKg: number): number
	return math.floor(weightKg * 1000)
end

function FairMath.scoreToWeight(score: number): number
	return score / 1000
end

-- Returns the reward tier for a 1-based rank (nil rank = ranked outside the fetched pages).
function FairMath.tierForRank(rank: number?, tiers: { any }): any
	local r = rank or math.huge
	for _, tier in tiers do
		if r <= tier.topN then
			return tier
		end
	end
	return tiers[#tiers]
end

-- Weeks the player entered that have finished and not been claimed yet, oldest first.
function FairMath.unclaimedWeeks(entries: { [string]: any }, claimed: { [string]: boolean }, currentWeek: number): { number }
	local result = {}
	for key in entries do
		local id = tonumber(key)
		if id and id < currentWeek and not claimed[key] then
			table.insert(result, id)
		end
	end
	table.sort(result)
	return result
end

return FairMath
