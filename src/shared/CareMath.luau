--!strict
--[[
	CareMath: the champion veggie's care needs. Pure, no requires.

	Needs are scheduled from timestamps, like growth, so they work with offline
	play: need k appears at plantedAt + k * careInterval. Handling it soon gives
	full credit, handling it late gives partial credit, and a need left alone
	for a while quietly expires. Nothing ever punishes the player; care only
	adds weight.

	Need types: before the crop is ripe they alternate "Water" and "Pests";
	once it is ripe and heavy, "Prop" (prop it up) alternates with "Water".
]]

export type Need = {
	k: number,
	kind: "Water" | "Pests" | "Prop",
	appearsAt: number,
	onTime: boolean,
}

local CareMath = {}

-- Interval chosen at planting: spreads maxCareEvents over the crop's whole growth.
function CareMath.intervalFor(crop: any, championConfig: any, totalSeconds: number): number
	local raw = totalSeconds / championConfig.maxCareEvents
	return math.clamp(raw, championConfig.minCareIntervalSeconds, championConfig.maxCareIntervalSeconds)
end

function CareMath.kindFor(k: number, ripeAtThatTime: boolean): "Water" | "Pests" | "Prop"
	if k % 2 == 1 then
		return "Water"
	end
	return if ripeAtThatTime then "Prop" else "Pests"
end

--[[
	The oldest open need at `now`, or nil.
	`done` is the plant's map of handled need indexes (string keys).
	`isRipeAt(t)` says whether the crop was ripe at time t.
]]
function CareMath.pendingNeed(
	plant: { [string]: any },
	championConfig: any,
	now: number,
	isRipeAt: (t: number) -> boolean
): Need?
	local interval = plant.careInterval
	if not interval or interval <= 0 then
		return nil
	end
	local latest = math.min(math.floor((now - plant.plantedAt) / interval), championConfig.maxCareEvents)
	if latest < 1 then
		return nil
	end
	local oldest = math.max(1, latest - championConfig.needExpiresAfterIntervals + 1)
	local done = plant.care or {}
	for k = oldest, latest do
		if not done[tostring(k)] then
			local appearsAt = plant.plantedAt + k * interval
			return {
				k = k,
				kind = CareMath.kindFor(k, isRipeAt(appearsAt)),
				appearsAt = appearsAt,
				onTime = now - appearsAt <= interval * championConfig.onTimeFraction,
			}
		end
	end
	return nil
end

-- Marks the need handled. Returns the credit given (1 on time, lateCredit after).
function CareMath.applyCare(plant: { [string]: any }, need: Need, championConfig: any): number
	local credit = if need.onTime then 1 else championConfig.lateCredit
	plant.care = plant.care or {}
	plant.care[tostring(need.k)] = credit
	plant.careScore = (plant.careScore or 0) + credit
	return credit
end

function CareMath.weightMultiplier(careScore: number, championConfig: any): number
	return 1 + careScore * championConfig.careBonusPerPoint
end

-- Attribute-friendly encoding of the done map ("1,2,5") and back.
function CareMath.encodeDone(done: { [string]: number }?): string
	local keys = {}
	for k in done or {} do
		table.insert(keys, tonumber(k) :: number)
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k))
	end
	return table.concat(parts, ",")
end

function CareMath.decodeDone(text: string?): { [string]: number }
	local done = {}
	for part in string.gmatch(text or "", "[^,]+") do
		done[part] = 1
	end
	return done
end

return CareMath
