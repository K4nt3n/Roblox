--!strict
--[[
	GrowthMath: pure functions for crop growth, watering and skipping.

	Growth is timestamp based. A plant stores when it was planted plus any
	"bonus" seconds it earned from watering or skips, so the current state can be
	computed at any moment, including after the player was offline for days.
	Nothing ticks on the server.

	This module has no requires. Callers pass in the crop def and config tables
	so the same code runs on the server, the client (for smooth local visuals)
	and in the test runner.
]]

export type Plant = {
	cropId: string,
	plantedAt: number,
	-- Growth speed locked in at planting (from the Fertilizer upgrade).
	speed: number,
	-- Effective seconds added by watering and skips.
	bonusSeconds: number,
	waterCount: number,
	lastWateredAt: number,
	-- Size variance multiplier rolled at planting (around 1.0).
	sizeRoll: number,
	-- True when this seed rolled the Giant gene.
	gene: boolean,
	-- Champion-only fields (see CareMath and Config.Champion).
	champion: boolean?,
	careInterval: number?,
	careScore: number?,
	care: { [string]: number }?,
	name: string?,
	coGrowers: { number }?,
	-- Paid skips used on this plant (honest shop: Natural Grown needs 0).
	paidSkips: number?,
}

export type Stage = "Seed" | "Sprout" | "Growing" | "Ripe" | "Giant"

export type GrowthState = {
	stage: Stage,
	-- 0..1 progress toward Ripe.
	progress: number,
	-- 0..1 progress from Ripe toward maximum size.
	giantProgress: number,
	weight: number,
	secondsToRipe: number,
	secondsToMax: number,
	canHarvest: boolean,
	isMaxed: boolean,
}

local GrowthMath = {}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

--[[
	Builds a new plant record. rollSize and rollGene are uniform randoms in
	[0, 1) supplied by the caller so the result is deterministic in tests.
]]
function GrowthMath.newPlant(
	crop: any,
	growthConfig: any,
	now: number,
	speed: number,
	giantChanceMultiplier: number,
	rollSize: number,
	rollGene: number
): Plant
	local sizeRoll = 1 + (rollSize * 2 - 1) * crop.variance
	local geneChance = growthConfig.baseGiantGeneChance * giantChanceMultiplier
	return {
		cropId = crop.id,
		plantedAt = now,
		speed = speed,
		bonusSeconds = 0,
		waterCount = 0,
		lastWateredAt = 0,
		sizeRoll = sizeRoll,
		gene = rollGene < geneChance,
	}
end

-- Effective seconds of growth the plant has accumulated at time `now`.
function GrowthMath.effectiveElapsed(plant: Plant, now: number): number
	local real = math.max(0, now - plant.plantedAt)
	return real * plant.speed + plant.bonusSeconds
end

function GrowthMath.baseWeight(plant: Plant, crop: any, growthConfig: any): number
	local geneMult = if plant.gene then growthConfig.giantGeneMultiplier else 1
	return crop.ripeWeight * plant.sizeRoll * geneMult
end

function GrowthMath.waterWeightMultiplier(plant: Plant, waterConfig: any): number
	local count = math.min(plant.waterCount, waterConfig.maxWaterBonusCount)
	return 1 + count * waterConfig.weightBonusPerWater
end

function GrowthMath.stageFor(progress: number, giantProgress: number, growthConfig: any): Stage
	if progress >= 1 then
		if giantProgress >= growthConfig.giantStageAt then
			return "Giant"
		end
		return "Ripe"
	end
	local t = growthConfig.stageThresholds
	if progress >= t.Growing then
		return "Growing"
	elseif progress >= t.Sprout then
		return "Sprout"
	end
	return "Seed"
end

--[[
	The champion version of a crop: it keeps swelling all week and can get
	bigger than the same crop grown normally.
]]
function GrowthMath.championDef(crop: any, championConfig: any): any
	local def = table.clone(crop)
	def.giantSeconds = math.max(crop.giantSeconds, championConfig.minGiantSeconds)
	def.giantMultiplier = crop.giantMultiplier * championConfig.giantMultiplierBonus
	return def
end

function GrowthMath.evaluate(plant: Plant, crop: any, config: any, now: number): GrowthState
	local growth = config.Growth
	if plant.champion then
		crop = GrowthMath.championDef(crop, config.Champion)
	end
	local elapsed = GrowthMath.effectiveElapsed(plant, now)
	local progress = clamp01(elapsed / crop.growSeconds)
	local giantProgress = clamp01((elapsed - crop.growSeconds) / crop.giantSeconds)

	local base = GrowthMath.baseWeight(plant, crop, growth)
	local weight
	if progress < 1 then
		-- Starts at 5% of ripe weight so a sprout is never weightless.
		weight = base * (0.05 + 0.95 * progress ^ growth.ripeCurveExponent)
	else
		weight = base * (1 + (crop.giantMultiplier - 1) * easeOutQuad(giantProgress))
	end
	weight *= GrowthMath.waterWeightMultiplier(plant, config.Watering)
	if plant.champion then
		-- Care beats luck: full care adds more than the Giant gene.
		weight *= 1 + (plant.careScore or 0) * config.Champion.careBonusPerPoint
	end

	-- Convert remaining effective seconds back into real seconds.
	local speed = math.max(plant.speed, 1e-6)
	local secondsToRipe = math.max(0, crop.growSeconds - elapsed) / speed
	local secondsToMax = math.max(0, crop.growSeconds + crop.giantSeconds - elapsed) / speed

	return {
		stage = GrowthMath.stageFor(progress, giantProgress, growth),
		progress = progress,
		giantProgress = giantProgress,
		weight = weight,
		secondsToRipe = secondsToRipe,
		secondsToMax = secondsToMax,
		canHarvest = progress >= 1,
		isMaxed = giantProgress >= 1,
	}
end

-- Effective seconds one watering adds, given the Watering Can multiplier.
function GrowthMath.waterBoostSeconds(crop: any, waterConfig: any, canMultiplier: number): number
	local raw = crop.growSeconds * waterConfig.boostFraction * canMultiplier
	return math.clamp(raw, waterConfig.minBoostSeconds, waterConfig.maxBoostSeconds)
end

-- Returns ok, reason, secondsUntilAllowed.
function GrowthMath.canWater(plant: Plant, crop: any, config: any, now: number): (boolean, string?, number)
	-- lastWateredAt == 0 means "never watered".
	local wait = plant.lastWateredAt + config.Watering.plantCooldownSeconds - now
	if plant.lastWateredAt > 0 and wait > 0 then
		return false, "Cooldown", wait
	end
	if GrowthMath.evaluate(plant, crop, config, now).isMaxed then
		return false, "Maxed", 0
	end
	return true, nil, 0
end

-- Mutates the plant. Caller must call canWater first.
function GrowthMath.applyWater(plant: Plant, crop: any, config: any, now: number, canMultiplier: number): number
	local boost = GrowthMath.waterBoostSeconds(crop, config.Watering, canMultiplier)
	plant.bonusSeconds += boost
	plant.waterCount += 1
	plant.lastWateredAt = now
	return boost
end

-- Effective seconds needed to reach Ripe right now (0 if already ripe).
function GrowthMath.skipSecondsNeeded(plant: Plant, crop: any, now: number): number
	return math.max(0, crop.growSeconds - GrowthMath.effectiveElapsed(plant, now))
end

function GrowthMath.applySkip(plant: Plant, crop: any, now: number): number
	local needed = GrowthMath.skipSecondsNeeded(plant, crop, now)
	plant.bonusSeconds += needed
	return needed
end

return GrowthMath
