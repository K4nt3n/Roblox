local T = require("./TestKit")
local Config = require("../src/shared/Config")
local EconomyMath = require("../src/shared/EconomyMath")

T.describe("EconomyMath", function()
	T.it("prices by weight, multiplier and giant bonus", function()
		local carrot = Config.Crops.carrot
		T.eq(EconomyMath.salePrice(2, carrot, false, 1, Config.Economy), math.floor(2 * carrot.sellPricePerKg))
		T.eq(EconomyMath.salePrice(2, carrot, true, 1.5, Config.Economy), math.floor(2 * carrot.sellPricePerKg * 1.5 * Config.Economy.giantSellBonus))
		T.eq(EconomyMath.salePrice(0.0001, carrot, false, 1, Config.Economy), 1, "never sells for 0")
	end)
	T.it("upgrade cost and value tables line up", function()
		for id, def in Config.Upgrades do
			T.eq(#def.values, #def.costs + 1, id .. " needs one more value than costs")
			T.eq(EconomyMath.upgradeValue(def, 0), def.values[1])
			T.eq(EconomyMath.upgradeCost(def, #def.costs), nil, id .. " max level has no cost")
			T.eq(EconomyMath.upgradeValue(def, 99), def.values[#def.values], "clamps past max")
		end
	end)
	T.it("plot costs cover every buyable plot", function()
		local p = Config.Plots
		T.eq(#p.plotCosts, p.maxPlots - p.startingPlots)
		T.eq(EconomyMath.nextPlotCost(p.startingPlots, p), p.plotCosts[1])
		T.eq(EconomyMath.nextPlotCost(p.maxPlots, p), nil)
	end)
	T.it("levels up across multiple thresholds and carries leftover xp", function()
		local L = Config.Levels
		local need1 = EconomyMath.xpToNext(1, L)
		local need2 = EconomyMath.xpToNext(2, L)
		local level, xp, gained = EconomyMath.addXp(1, 0, need1 + need2 + 3, L)
		T.eq(level, 3)
		T.eq(xp, 3)
		T.eq(gained, 2)
	end)
	T.it("stops at max level", function()
		local level, xp = EconomyMath.addXp(Config.Levels.maxLevel, 0, 10 ^ 9, Config.Levels)
		T.eq(level, Config.Levels.maxLevel)
		T.eq(xp, 0)
	end)
end)

return nil
