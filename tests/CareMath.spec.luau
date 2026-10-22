local T = require("./TestKit")
local Config = require("../src/shared/Config")
local CareMath = require("../src/shared/CareMath")
local GrowthMath = require("../src/shared/GrowthMath")

local C = Config.Champion
local pumpkin = Config.Crops.pumpkin

local function champion(interval)
	local p = GrowthMath.newPlant(pumpkin, Config.Growth, 0, 1, 1, 0.5, 0.99)
	p.champion = true
	p.careInterval = interval or 100
	p.careScore = 0
	p.care = {}
	return p
end

local function never()
	return false
end

T.describe("CareMath", function()
	T.it("spreads care over the whole growth, within limits", function()
		T.eq(CareMath.intervalFor(pumpkin, C, 14 * 3600), 3600)
		T.eq(CareMath.intervalFor(pumpkin, C, 1), C.minCareIntervalSeconds)
		T.eq(CareMath.intervalFor(pumpkin, C, 10 ^ 9), C.maxCareIntervalSeconds)
	end)
	T.it("no need before the first interval", function()
		T.eq(CareMath.pendingNeed(champion(), C, 99, never), nil)
	end)
	T.it("needs alternate water and pests, then prop once ripe", function()
		T.eq(CareMath.kindFor(1, false), "Water")
		T.eq(CareMath.kindFor(2, false), "Pests")
		T.eq(CareMath.kindFor(2, true), "Prop")
		T.eq(CareMath.kindFor(3, true), "Water")
	end)
	T.it("on time gives full credit, late gives partial", function()
		local p = champion(100)
		local need = CareMath.pendingNeed(p, C, 120, never)
		T.eq(need.k, 1)
		T.eq(need.kind, "Water")
		T.eq(need.onTime, true)
		T.eq(CareMath.applyCare(p, need, C), 1)
		T.eq(CareMath.pendingNeed(p, C, 150, never), nil)
		local late = CareMath.pendingNeed(p, C, 280, never)
		T.eq(late.k, 2)
		T.eq(late.onTime, false)
		T.eq(CareMath.applyCare(p, late, C), C.lateCredit)
		T.near(p.careScore, 1 + C.lateCredit)
	end)
	T.it("old needs expire quietly instead of piling up", function()
		local p = champion(100)
		local need = CareMath.pendingNeed(p, C, 1050, never)
		-- Latest is 10; only the last needExpiresAfterIntervals are still open.
		T.eq(need.k, 10 - C.needExpiresAfterIntervals + 1)
	end)
	T.it("stops after the last care event", function()
		local p = champion(100)
		local need = CareMath.pendingNeed(p, C, 10 ^ 6, never)
		T.eq(need.k, C.maxCareEvents - C.needExpiresAfterIntervals + 1)
	end)
	T.it("done map survives the attribute round trip", function()
		local done = { ["3"] = 1, ["1"] = 0.5, ["12"] = 1 }
		local text = CareMath.encodeDone(done)
		T.eq(text, "1,3,12")
		local back = CareMath.decodeDone(text)
		T.truthy(back["1"] and back["3"] and back["12"])
		T.eq(next(CareMath.decodeDone(nil)), nil)
	end)
	T.it("full care beats the Giant gene", function()
		T.truthy(CareMath.weightMultiplier(C.maxCareEvents, C) > Config.Growth.giantGeneMultiplier)
	end)
end)

T.describe("GrowthMath champion", function()
	T.it("grows bigger and for longer than a normal crop", function()
		local def = GrowthMath.championDef(pumpkin, C)
		T.truthy(def.giantSeconds >= C.minGiantSeconds)
		T.near(def.giantMultiplier, pumpkin.giantMultiplier * C.giantMultiplierBonus)
		local normal = GrowthMath.newPlant(pumpkin, Config.Growth, 0, 1, 1, 0.5, 0.99)
		local champ = champion()
		local far = 10 ^ 9
		T.truthy(GrowthMath.evaluate(champ, pumpkin, Config, far).weight > GrowthMath.evaluate(normal, pumpkin, Config, far).weight)
	end)
	T.it("care points add weight", function()
		local a = champion()
		local b = champion()
		b.careScore = 5
		local t = pumpkin.growSeconds
		local wa = GrowthMath.evaluate(a, pumpkin, Config, t).weight
		local wb = GrowthMath.evaluate(b, pumpkin, Config, t).weight
		T.near(wb / wa, 1 + 5 * C.careBonusPerPoint)
	end)
end)

return nil
