local T = require("./TestKit")
local Config = require("../src/shared/Config")
local RewardMath = require("../src/shared/RewardMath")

local R = Config.Rewards
local DAYS = #R.streak.days

T.describe("RewardMath streak", function()
	T.it("a new player claims day 1 once per day", function()
		local streak = { count = 0, lastDay = -1 }
		T.eq(RewardMath.canClaimStreak(streak, 100), true)
		T.eq(RewardMath.claimStreak(streak, 100, DAYS), 1)
		T.eq(RewardMath.canClaimStreak(streak, 100), false)
		T.eq(RewardMath.claimStreak(streak, 100, DAYS), nil)
	end)
	T.it("claiming on consecutive days climbs the streak", function()
		local streak = { count = 0, lastDay = -1 }
		for day = 1, 5 do
			T.eq(RewardMath.claimStreak(streak, 100 + day, DAYS), day)
		end
		T.eq(streak.count, 5)
	end)
	T.it("a missed day starts over at day 1", function()
		local streak = { count = 4, lastDay = 10 }
		T.eq(RewardMath.streakBroken(streak, 12), true)
		T.eq(RewardMath.nextStreakDay(streak, 12, DAYS), 1)
		T.eq(RewardMath.claimStreak(streak, 12, DAYS), 1)
		T.eq(streak.count, 1)
	end)
	T.it("loops back to day 1 after the last day", function()
		local streak = { count = DAYS, lastDay = 50 }
		T.eq(RewardMath.claimStreak(streak, 51, DAYS), 1)
		T.eq(RewardMath.claimStreak(streak, 52, DAYS), 2)
	end)
	T.it("shows the day already claimed today", function()
		local streak = { count = 3, lastDay = 20 }
		T.eq(RewardMath.nextStreakDay(streak, 20, DAYS), 3)
		T.eq(RewardMath.streakBroken(streak, 20), false)
	end)
end)

T.describe("RewardMath quests", function()
	local pool = R.quests.daily.pool
	T.it("picks the configured count with no repeated kind", function()
		local list = RewardMath.pickQuests(pool, 3, 12345, 1000, 11, 1)
		T.eq(#list, 3)
		local kinds = {}
		for _, q in list do
			T.eq(kinds[q.kind], nil, "duplicate kind")
			kinds[q.kind] = true
			T.eq(q.progress, 0)
			T.eq(q.claimed, false)
		end
	end)
	T.it("is the same for the same player and day, different on another day", function()
		local a = RewardMath.pickQuests(pool, 3, 777, 42, 11, 1)
		local b = RewardMath.pickQuests(pool, 3, 777, 42, 11, 1)
		for i = 1, 3 do
			T.eq(a[i].def, b[i].def)
		end
		local differs = false
		for day = 43, 60 do
			local c = RewardMath.pickQuests(pool, 3, 777, day, 11, 1)
			for i = 1, 3 do
				if c[i].def ~= a[i].def then
					differs = true
				end
			end
		end
		T.truthy(differs, "quests never change between days")
	end)
	T.it("skips quests above the player's level", function()
		local gated = { { id = "a", kind = "plant", goal = 1 }, { id = "b", kind = "harvest", goal = 1, minLevel = 5 } }
		local list = RewardMath.pickQuests(gated, 2, 1, 1, 0, 1)
		T.eq(#list, 1)
		T.eq(list[1].def, "a")
	end)
	T.it("progress caps at the goal and reports completion once", function()
		local quests = { { def = "x", kind = "harvest", goal = 3, progress = 0, claimed = false } }
		local changed, done = RewardMath.addProgress(quests, "harvest", 2)
		T.eq(#changed, 1)
		T.eq(#done, 0)
		changed, done = RewardMath.addProgress(quests, "harvest", 5)
		T.eq(#done, 1)
		T.eq(quests[1].progress, 3)
		changed, done = RewardMath.addProgress(quests, "harvest", 1)
		T.eq(#changed, 0)
		T.eq(#done, 0)
		T.eq(RewardMath.canClaimQuest(quests[1]), true)
		quests[1].claimed = true
		T.eq(RewardMath.canClaimQuest(quests[1]), false)
	end)
	T.it("ignores other kinds and zero amounts", function()
		local quests = { { def = "x", kind = "sell", goal = 3, progress = 0, claimed = false } }
		local changed = RewardMath.addProgress(quests, "harvest", 1)
		T.eq(#changed, 0)
		changed = RewardMath.addProgress(quests, "sell", 0)
		T.eq(#changed, 0)
	end)
	T.it("every pool entry has a reward, a goal and a known text slot", function()
		for _, period in R.quests do
			T.truthy(#period.pool >= period.count, "pool smaller than count")
			for _, def in period.pool do
				T.truthy(def.goal > 0, def.id)
				T.truthy(def.reward, def.id)
				T.truthy(string.find(def.text, "%d", 1, true), def.id)
			end
		end
	end)
end)

T.describe("RewardMath star track", function()
	local track = R.starTrack
	T.it("chests open in order as stars are reached", function()
		T.eq(#RewardMath.claimableChests(track, 0, {}), 0)
		local list = RewardMath.claimableChests(track, track[2].stars, {})
		T.eq(#list, 2)
		list = RewardMath.claimableChests(track, track[2].stars, { ["1"] = true })
		T.eq(#list, 1)
		T.eq(list[1], 2)
	end)
	T.it("thresholds climb", function()
		for i = 2, #track do
			T.truthy(track[i].stars > track[i - 1].stars)
		end
	end)
	T.it("bar fill is clamped", function()
		T.eq(RewardMath.trackFill(track, 0), 0)
		T.eq(RewardMath.trackFill(track, 10 ^ 6), 1)
	end)
end)

T.describe("RewardMath bundles", function()
	T.it("merges coins, xp, seeds and supplies", function()
		local a = RewardMath.mergeBundle({}, { coins = 10, seeds = { tomato = 2 } })
		RewardMath.mergeBundle(a, { coins = 5, xp = 3, seeds = { tomato = 1 }, supplies = { fertilizer = 2 } })
		T.eq(a.coins, 15)
		T.eq(a.xp, 3)
		T.eq((a.seeds :: any).tomato, 3)
		T.eq((a.supplies :: any).fertilizer, 2)
		T.eq(RewardMath.isEmpty(a), false)
		T.eq(RewardMath.isEmpty({}), true)
	end)
end)

return nil
