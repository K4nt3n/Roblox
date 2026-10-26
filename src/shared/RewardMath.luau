--!strict
--[[
	RewardMath: pure rules for the daily login streak, daily and weekly quests
	and the weekly star track. No requires, so it can be unit tested.

	"Day" and "week" are fair period ids (Config.Fair.periods.daily / weekly),
	so every reset lines up with a fair rollover and the HUD timers.

	A reward bundle looks like:
	    { coins = 100, xp = 20, seeds = { tomato = 3 }, supplies = { fertilizer = 1 } }
]]

local RewardMath = {}

export type Bundle = {
	coins: number?,
	xp: number?,
	seeds: { [string]: number }?,
	supplies: { [string]: number }?,
}

export type Streak = { count: number, lastDay: number }

export type Quest = { def: string, kind: string, goal: number, progress: number, claimed: boolean }

---------------------------------------------------------------------------
-- Daily login streak
---------------------------------------------------------------------------

-- True when today's streak reward has not been claimed yet.
function RewardMath.canClaimStreak(streak: Streak, today: number): boolean
	return streak.lastDay ~= today
end

--[[
	The streak day (1-based) that claiming today pays out, given `length`
	reward days. Claiming yesterday keeps the streak going; a missed day starts
	over at day 1. After the last day it loops back to day 1.
]]
function RewardMath.nextStreakDay(streak: Streak, today: number, length: number): number
	if streak.lastDay == today then
		return ((streak.count - 1) % length) + 1
	end
	local continued = streak.lastDay == today - 1
	local count = if continued then streak.count + 1 else 1
	return ((count - 1) % length) + 1
end

-- Claims today's reward. Returns the streak day that was paid out, or nil if already claimed.
function RewardMath.claimStreak(streak: Streak, today: number, length: number): number?
	if not RewardMath.canClaimStreak(streak, today) then
		return nil
	end
	local day = RewardMath.nextStreakDay(streak, today, length)
	streak.count = if streak.lastDay == today - 1 then streak.count + 1 else 1
	streak.lastDay = today
	return day
end

-- True when the streak has been broken (a day was missed). Used to say "start over" kindly.
function RewardMath.streakBroken(streak: Streak, today: number): boolean
	return streak.count > 0 and streak.lastDay < today - 1
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

-- Small deterministic generator (Park-Miller) so a player's quests for a day
-- are the same on every server and in tests.
local MOD = 2147483647
local function generator(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % (MOD - 1) + 1
	return function()
		state = (state * 48271) % MOD
		return state / MOD
	end
end

--[[
	Picks `count` quests from `pool` for a player and period. Quests above the
	player's level are skipped, and no kind is picked twice.
	pool entries: { id, kind, goal, minLevel? }
]]
function RewardMath.pickQuests(pool: { any }, count: number, userId: number, periodId: number, salt: number, level: number): { Quest }
	local candidates = {}
	for _, def in pool do
		if (def.minLevel or 1) <= level then
			table.insert(candidates, def)
		end
	end
	table.sort(candidates, function(a, b)
		return a.id < b.id
	end)
	local nextRandom = generator(userId * 31 + periodId * 7919 + salt)
	-- Fisher-Yates shuffle.
	for i = #candidates, 2, -1 do
		local j = math.floor(nextRandom() * i) + 1
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local picked: { Quest } = {}
	local usedKinds: { [string]: boolean } = {}
	for _, def in candidates do
		if #picked >= count then
			break
		end
		if not usedKinds[def.kind] then
			usedKinds[def.kind] = true
			table.insert(picked, { def = def.id, kind = def.kind, goal = def.goal, progress = 0, claimed = false })
		end
	end
	return picked
end

-- Adds progress to every unclaimed quest of `kind`. Returns the quests that just reached their goal.
function RewardMath.addProgress(quests: { Quest }, kind: string, amount: number): ({ Quest }, { Quest })
	local changed, completed = {}, {}
	if amount <= 0 then
		return changed, completed
	end
	for _, quest in quests do
		if quest.kind == kind and not quest.claimed and quest.progress < quest.goal then
			quest.progress = math.min(quest.goal, quest.progress + amount)
			table.insert(changed, quest)
			if quest.progress >= quest.goal then
				table.insert(completed, quest)
			end
		end
	end
	return changed, completed
end

function RewardMath.isComplete(quest: Quest): boolean
	return quest.progress >= quest.goal
end

function RewardMath.canClaimQuest(quest: Quest): boolean
	return not quest.claimed and quest.progress >= quest.goal
end

---------------------------------------------------------------------------
-- Star track
---------------------------------------------------------------------------

-- Indexes of chests reached but not opened. track entries: { stars, reward }
function RewardMath.claimableChests(track: { any }, stars: number, opened: { [string]: boolean }): { number }
	local list = {}
	for i, chest in track do
		if stars >= chest.stars and not opened[tostring(i)] then
			table.insert(list, i)
		end
	end
	return list
end

-- 0..1 position along the track for the progress bar.
function RewardMath.trackFill(track: { any }, stars: number): number
	local last = track[#track]
	if not last or last.stars <= 0 then
		return 0
	end
	return math.clamp(stars / last.stars, 0, 1)
end

---------------------------------------------------------------------------
-- Bundles
---------------------------------------------------------------------------

-- Merges `b` into `a` (in place) and returns `a`.
function RewardMath.mergeBundle(a: Bundle, b: Bundle): Bundle
	a.coins = (a.coins or 0) + (b.coins or 0)
	a.xp = (a.xp or 0) + (b.xp or 0)
	for key, field in { seeds = b.seeds, supplies = b.supplies } do
		if field then
			local target = (a :: any)[key] or {}
			for id, count in field do
				target[id] = (target[id] or 0) + count
			end
			(a :: any)[key] = target
		end
	end
	return a
end

function RewardMath.isEmpty(bundle: Bundle): boolean
	if (bundle.coins or 0) > 0 or (bundle.xp or 0) > 0 then
		return false
	end
	return next(bundle.seeds or {}) == nil and next(bundle.supplies or {}) == nil
end

return RewardMath
