local T = require("./TestKit")
local Config = require("../src/shared/Config")
local Schema = require("../src/server/Data/Schema")

T.describe("Schema", function()
	T.it("new players get defaults and a join time", function()
		local data, isNew = Schema.prepare(nil, Config, 1234)
		T.eq(isNew, true)
		T.eq(data.coins, Config.Economy.startingCoins)
		T.eq(data.ownedPlots, Config.Plots.startingPlots)
		T.eq(data.firstJoinAt, 1234)
		T.eq(data.upgrades.fertilizer, 0)
		T.eq(data.rewards.streak.lastDay, -1)
		T.eq(#data.rewards.daily.list, 0)
	end)
	T.it("old saves get the rewards record", function()
		local data = Schema.prepare({ version = 1, coins = 5 }, Config, 0)
		T.eq(data.rewards.streak.count, 0)
		T.eq(data.rewards.stars.count, 0)
		T.truthy(data.rewards.weekly.list)
	end)
	T.it("reconcile fills missing fields without overwriting saved ones", function()
		local stored = { version = 1, coins = 999, stats = { harvested = 4 } }
		local data = Schema.prepare(stored, Config, 0)
		T.eq(data.coins, 999)
		T.eq(data.stats.harvested, 4)
		T.eq(data.stats.heaviest, 0)
		T.truthy(data.fair and data.fair.entries)
	end)
	T.it("does not inject defaults into user maps like plots", function()
		local stored = { version = 1, plots = { ["2"] = { cropId = "carrot" } }, seeds = {} }
		local data = Schema.prepare(stored, Config, 0)
		T.eq(data.plots["1"], nil)
		T.eq(data.plots["2"].cropId, "carrot")
	end)
	T.it("defaults are deep copies", function()
		local a = Schema.prepare(nil, Config, 0)
		local b = Schema.prepare(nil, Config, 0)
		a.stats.harvested = 50
		T.eq(b.stats.harvested, 0)
	end)
	T.it("migrations run in order and set the version", function()
		local old = Schema.Version
		Schema.Version = old + 1
		Schema.Migrations[old + 1] = function(d)
			d.migrated = true
		end
		local data = Schema.migrate({ version = old })
		T.eq(data.version, old + 1)
		T.eq(data.migrated, true)
		Schema.Migrations[old + 1] = nil
		Schema.Version = old
	end)
end)

return nil
