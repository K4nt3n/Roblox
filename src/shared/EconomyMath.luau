--!strict
--[[
	EconomyMath: pure pricing, upgrade and XP formulas. No requires.
]]

local EconomyMath = {}

function EconomyMath.salePrice(weight: number, crop: any, isGiant: boolean, sellMultiplier: number, economyConfig: any): number
	local giantBonus = if isGiant then economyConfig.giantSellBonus else 1
	return math.max(1, math.floor(weight * crop.sellPricePerKg * sellMultiplier * giantBonus))
end

-- Price to go from `level` to `level + 1`, or nil when maxed.
function EconomyMath.upgradeCost(def: any, level: number): number?
	return def.costs[level + 1]
end

function EconomyMath.upgradeValue(def: any, level: number): number
	local values = def.values
	return values[math.clamp(level + 1, 1, #values)]
end

function EconomyMath.maxUpgradeLevel(def: any): number
	return #def.costs
end

-- Price of the next plot when the player already owns `owned` plots, or nil at the cap.
function EconomyMath.nextPlotCost(owned: number, plotConfig: any): number?
	if owned >= plotConfig.maxPlots then
		return nil
	end
	return plotConfig.plotCosts[owned - plotConfig.startingPlots + 1]
end

function EconomyMath.xpToNext(level: number, levelConfig: any): number
	return math.floor(levelConfig.xpBase * level ^ levelConfig.xpExponent)
end

-- Adds xp and returns newLevel, newXp, levelsGained.
function EconomyMath.addXp(level: number, xp: number, gained: number, levelConfig: any): (number, number, number)
	local startLevel = level
	xp += gained
	while level < levelConfig.maxLevel do
		local need = EconomyMath.xpToNext(level, levelConfig)
		if xp < need then
			break
		end
		xp -= need
		level += 1
	end
	if level >= levelConfig.maxLevel then
		xp = 0
	end
	return level, xp, level - startLevel
end

function EconomyMath.harvestXp(weight: number, levelConfig: any): number
	return math.floor(levelConfig.xpPerHarvest + weight * levelConfig.xpPerKgHarvested)
end

return EconomyMath
