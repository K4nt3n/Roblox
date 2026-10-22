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

--[[
	Generic versions for any fair period (hourly / daily / weekly), where
	period = { anchorUnix, seconds } from Config.Fair.periods.
]]
function FairMath.periodId(now: number, period: any): number
	return math.floor((now - period.anchorUnix) / period.seconds)
end

function FairMath.periodStartsAt(id: number, period: any): number
	return period.anchorUnix + id * period.seconds
end

function FairMath.periodEndsAt(id: number, period: any): number
	return FairMath.periodStartsAt(id + 1, period)
end

-- Periods sorted by `order` (hourly, daily, weekly).
function FairMath.sortedPeriods(periods: { [string]: any }): { any }
	local list = {}
	for _, period in periods do
		table.insert(list, period)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- OrderedDataStore only stores integers, so weights are kept in grams.
function FairMath.weightToScore(weightKg: number): number
	return math.floor(weightKg * 1000)
end

function FairMath.scoreToWeight(score: number): number
	return score / 1000
end

-- Returns the reward tier for a 1-based rank (nil rank = ranked outside the fetched pages),
-- or nil when the rank earns nothing in this tier list.
function FairMath.tierForRank(rank: number?, tiers: { any }): any?
	local r = rank or math.huge
	for _, tier in tiers do
		if r <= tier.topN then
			return tier
		end
	end
	return nil
end

-- Deepest finite rank a tier list rewards (how far down a board must be read).
function FairMath.deepestRank(tiers: { any }): number
	local deepest = 0
	for _, tier in tiers do
		if tier.topN ~= math.huge then
			deepest = math.max(deepest, tier.topN)
		end
	end
	return deepest
end

--[[
	Every division a fair entry competes in, with its integer score.
	ctx = { isFirstTimer: boolean, previousBest: number (kg, 0 if none) }
	The helper division is not entry based; see FairService.
]]
function FairMath.divisionsForEntry(
	item: { [string]: any },
	ctx: { [string]: any },
	allowed: { string }?
): { { id: string, score: number } }
	local all = FairMath._allDivisionsForEntry(item, ctx)
	if not allowed then
		return all
	end
	local list = {}
	for _, division in all do
		local family = if string.sub(division.id, 1, 5) == "crop_" then "crop" else division.id
		if table.find(allowed, family) then
			table.insert(list, division)
		end
	end
	return list
end

function FairMath._allDivisionsForEntry(item: { [string]: any }, ctx: { [string]: any }): { { id: string, score: number } }
	local grams = FairMath.weightToScore(item.weight)
	local list = {
		{ id = "overall", score = grams },
		{ id = "crop_" .. item.cropId, score = grams },
	}
	if ctx.isFirstTimer then
		table.insert(list, { id = "firstTimer", score = grams })
	end
	if (ctx.previousBest or 0) > 0 and item.weight > ctx.previousBest then
		-- Score is the improvement ratio in thousandths (1500 = 50% heavier than last best).
		table.insert(list, { id = "improved", score = math.floor(1000 * item.weight / ctx.previousBest) })
	end
	if item.isChampion and (item.paidSkips or 0) == 0 then
		table.insert(list, { id = "natural", score = grams })
	end
	if item.isChampion and item.coGrowers and #item.coGrowers > 0 then
		table.insert(list, { id = "team", score = grams })
	end
	return list
end

function FairMath.divisionName(divisionId: string, divisions: any, crops: any): string
	local cropId = string.match(divisionId, "^crop_(.+)$")
	if cropId then
		local crop = crops[cropId]
		return string.format(divisions.crop.displayName, if crop then crop.displayName else cropId)
	end
	local def = divisions[divisionId]
	return if def then def.displayName else divisionId
end

--[[
	Where a fair's live show stands at `now`.
	  "Announce": counting down to the rollover; id = the period being judged.
	  "Live": inside the show window right after a rollover; id = the period just ended.
	  "Idle": otherwise.
	`at` is the rollover time in every case.
]]
function FairMath.showPhase(now: number, period: any): (string, number, number)
	local id = FairMath.periodId(now, period)
	local startedAt = FairMath.periodStartsAt(id, period)
	if now - startedAt < period.show.liveWindowSeconds then
		return "Live", id - 1, startedAt
	end
	local endsAt = FairMath.periodEndsAt(id, period)
	if endsAt - now <= period.show.announceSeconds then
		return "Announce", id, endsAt
	end
	return "Idle", id, endsAt
end

-- Ribbon ids: "<fair>:<tier ribbon>:<division>", e.g. "weekly:Blue:crop_pumpkin".
function FairMath.ribbonId(periodId: string, tierRibbon: string, division: string): string
	return periodId .. ":" .. tierRibbon .. ":" .. division
end

function FairMath.parseRibbonId(ribbon: string): (string?, string?, string?)
	return string.match(ribbon, "^([^:]+):([^:]+):(.+)$")
end

-- Stage order for the show: lightest first so the heaviest comes last; keeps the heaviest `max`.
function FairMath.stageOrder(entries: { any }, max: number): { any }
	local sorted = table.clone(entries)
	table.sort(sorted, function(a, b)
		return a.weight < b.weight
	end)
	while #sorted > max do
		table.remove(sorted, 1)
	end
	return sorted
end

-- Finished, unclaimed period ids found in any of the given id-keyed maps, oldest first.
function FairMath.unclaimedPeriods(entries: { [string]: any }, claimed: { [string]: boolean }, currentId: number, ...: { [string]: any }): { number }
	local seen, result = {}, {}
	for _, map in { entries, ... } do
		for key in map do
			local id = tonumber(key)
			if id and id < currentId and not claimed[key] and not seen[key] then
				seen[key] = true
				table.insert(result, id)
			end
		end
	end
	table.sort(result)
	return result
end

return FairMath
