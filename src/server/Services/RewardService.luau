--!strict
--[[
	RewardService: the reasons to come back every day and every week.

	  Login streak  one claim per day; day 7 is the big one, then it loops.
	                Missing a day starts over at day 1.
	  Quests        a few daily and weekly quests per player, picked by a seed
	                so they match on every server. Progress comes from the
	                feedback events other services already send (NetService.FeedbackSent),
	                so no other service needs quest code.
	  Star track    each claim gives stars; stars open the week's chests.

	Days and weeks follow the Daily Fair and Weekly Grand Fair periods. When a
	period rolls over, anything finished but not claimed is given to the player
	automatically ("saved for you"), so nobody loses a reward for being away.
	Rules live in shared/RewardMath, amounts in Config.Rewards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local FairMath = require(Shared.FairMath)
local RewardMath = require(Shared.RewardMath)

local RewardService = {}

local Services: any
local REWARDS = Config.Rewards
local DAY = Config.Fair.periods[REWARDS.dayPeriod]
local WEEK = Config.Fair.periods[REWARDS.weekPeriod]
local PERIODS = { daily = DAY, weekly = WEEK }
-- Salt per quest period so the daily and weekly picks don't mirror each other.
local SALT = { daily = 11, weekly = 97 }

-- def id -> quest def, for both periods.
local questDefs: { [string]: any } = {}
for _, period in REWARDS.quests do
	for _, def in period.pool do
		questDefs[def.id] = def
	end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function questText(def: any): string
	return string.format(def.text, def.goal)
end

-- Gives a bundle to the player. Coins and XP go through EconomyService so
-- stats, level-ups and their feedback all still happen.
function RewardService:Grant(player: Player, bundle: RewardMath.Bundle, source: string)
	local data = Services.DataService:Get(player)
	if not data then
		return
	end
	if bundle.coins and bundle.coins > 0 then
		Services.EconomyService:AddCoins(player, bundle.coins, source)
	end
	if bundle.xp and bundle.xp > 0 then
		Services.EconomyService:AddXp(player, bundle.xp)
	end
	for cropId, count in bundle.seeds or {} do
		if Config.Crops[cropId] then
			data.seeds[cropId] = (data.seeds[cropId] or 0) + count
		end
	end
	for supplyId, count in bundle.supplies or {} do
		if Config.Supplies[supplyId] then
			data.supplies[supplyId] = (data.supplies[supplyId] or 0) + count
		end
	end
	Services.DataService:MarkDirty(player)
end

-- Adds stars and tells the player when a chest on the track just became ready.
function RewardService:_addStars(player: Player, data: { [string]: any }, amount: number)
	if amount <= 0 then
		return
	end
	local stars = data.rewards.stars
	local before = #RewardMath.claimableChests(REWARDS.starTrack, stars.count, stars.opened)
	stars.count += amount
	local after = #RewardMath.claimableChests(REWARDS.starTrack, stars.count, stars.opened)
	if after > before then
		Services.NetService:Feedback(player, Net.Feedback.QuestComplete, { kind = "chest", stars = stars.count })
	end
end

--[[
	Rolls the day and week forward when their fair period changed. Finished
	but unclaimed quests and reached but unopened chests are granted first.
	Returns true if anything changed.
]]
function RewardService:_refresh(player: Player, data: { [string]: any }): boolean
	local rewards = data.rewards
	local now = os.time()
	local day = FairMath.periodId(now, DAY)
	local week = FairMath.periodId(now, WEEK)
	local saved: RewardMath.Bundle = {}
	local changed = false

	local function collectQuests(list: { RewardMath.Quest })
		for _, quest in list do
			local def = questDefs[quest.def]
			if def and RewardMath.canClaimQuest(quest) then
				quest.claimed = true
				RewardMath.mergeBundle(saved, def.reward)
				rewards.stars.count += def.stars or 0
			end
		end
	end

	if rewards.daily.id ~= day then
		collectQuests(rewards.daily.list)
		rewards.daily = {
			id = day,
			list = RewardMath.pickQuests(REWARDS.quests.daily.pool, REWARDS.quests.daily.count, player.UserId, day, SALT.daily, data.level),
		}
		changed = true
	end
	if rewards.weekly.id ~= week then
		collectQuests(rewards.weekly.list)
		rewards.weekly = {
			id = week,
			list = RewardMath.pickQuests(REWARDS.quests.weekly.pool, REWARDS.quests.weekly.count, player.UserId, week, SALT.weekly, data.level),
		}
		changed = true
	end
	if rewards.stars.week ~= week then
		if rewards.stars.week ~= -1 then
			for _, index in RewardMath.claimableChests(REWARDS.starTrack, rewards.stars.count, rewards.stars.opened) do
				RewardMath.mergeBundle(saved, REWARDS.starTrack[index].reward)
			end
		end
		rewards.stars = { week = week, count = 0, opened = {} }
		changed = true
	end

	if not RewardMath.isEmpty(saved) then
		self:Grant(player, saved, "SavedRewards")
		Services.NetService:Feedback(player, Net.Feedback.RewardClaimed, { source = "saved", reward = saved })
	end
	if changed then
		Services.DataService:MarkDirty(player)
	end
	return changed
end

---------------------------------------------------------------------------
-- Claims
---------------------------------------------------------------------------

function RewardService:ClaimStreak(player: Player): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	self:_refresh(player, data)
	local today = FairMath.periodId(os.time(), DAY)
	local days = REWARDS.streak.days
	local day = RewardMath.claimStreak(data.rewards.streak, today, #days)
	if not day then
		return false, "AlreadyClaimed"
	end
	local reward = days[day]
	self:Grant(player, reward, "Streak")
	self:_addStars(player, data, REWARDS.streak.stars)
	Services.NetService:Feedback(player, Net.Feedback.RewardClaimed, {
		source = "streak",
		day = day,
		big = day == #days,
		reward = reward,
		stars = REWARDS.streak.stars,
	})
	Services.DataService:MarkDirty(player)
	return true, { day = day }
end

function RewardService:ClaimQuest(player: Player, period: any, index: any): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	if type(period) ~= "string" or not PERIODS[period] or type(index) ~= "number" then
		return false, "BadRequest"
	end
	self:_refresh(player, data)
	local quest = data.rewards[period].list[index]
	local def = quest and questDefs[quest.def]
	if not quest or not def then
		return false, "NotFound"
	end
	if quest.claimed then
		return false, "AlreadyClaimed"
	end
	if not RewardMath.isComplete(quest) then
		return false, "QuestNotDone"
	end
	quest.claimed = true
	self:Grant(player, def.reward, "Quest")
	self:_addStars(player, data, def.stars or 0)
	Services.NetService:Feedback(player, Net.Feedback.RewardClaimed, {
		source = "quest",
		period = period,
		index = index,
		text = questText(def),
		reward = def.reward,
		stars = def.stars or 0,
	})
	Services.DataService:MarkDirty(player)
	return true, nil
end

function RewardService:ClaimChest(player: Player, index: any): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	if type(index) ~= "number" then
		return false, "BadRequest"
	end
	self:_refresh(player, data)
	local chest = REWARDS.starTrack[index]
	if not chest then
		return false, "NotFound"
	end
	local stars = data.rewards.stars
	local key = tostring(index)
	if stars.opened[key] then
		return false, "AlreadyClaimed"
	end
	if stars.count < chest.stars then
		return false, "NeedMoreStars"
	end
	stars.opened[key] = true
	self:Grant(player, chest.reward, "StarChest")
	Services.NetService:Feedback(player, Net.Feedback.RewardClaimed, {
		source = "chest",
		index = index,
		big = chest.big == true,
		reward = chest.reward,
	})
	Services.DataService:MarkDirty(player)
	return true, nil
end

---------------------------------------------------------------------------
-- Quest progress from gameplay feedback
---------------------------------------------------------------------------

-- Feedback event -> list of (kind, amount) it counts toward, for the player it was sent to.
local function progressFor(player: Player, eventName: string, ctx: { [string]: any }): { { any } }
	if eventName == Net.Feedback.Planted then
		return { { "plant", 1 } }
	elseif eventName == Net.Feedback.Harvested then
		local list = { { "harvest", 1 } }
		if ctx.isGiant then
			table.insert(list, { "harvestGiant", 1 })
		end
		return list
	elseif eventName == Net.Feedback.Sold then
		return { { "sell", ctx.count or 1 }, { "earn", ctx.coins or 0 } }
	elseif eventName == Net.Feedback.Watered then
		-- Only sent to the owner for their own watering.
		return { { "water", 1 } }
	elseif eventName == Net.Feedback.YouWateredFriend then
		return { { "waterFriend", 1 } }
	elseif eventName == Net.Feedback.PestsRemoved then
		-- The owner also hears about a friend's help; only the remover counts it.
		if ctx.helperName == nil or player.UserId ~= ctx.ownerUserId then
			return { { "pests", 1 } }
		end
	elseif eventName == Net.Feedback.Fertilized then
		return { { "fertilize", 1 } }
	elseif eventName == Net.Feedback.CareDone then
		if ctx.carerUserId == player.UserId then
			return { { "care", 1 } }
		end
	elseif eventName == Net.Feedback.FairEntered then
		return { { "enterFair", 1 } }
	end
	return {}
end

function RewardService:_onFeedback(player: Player, eventName: string, ctx: { [string]: any })
	local list = progressFor(player, eventName, ctx)
	if #list == 0 then
		return
	end
	local data = Services.DataService:Get(player)
	if not data then
		return
	end
	self:_refresh(player, data)
	local any = false
	for _, entry in list do
		local kind, amount = entry[1], entry[2]
		for period in PERIODS do
			local quests = data.rewards[period].list
			local changed, completed = RewardMath.addProgress(quests, kind, amount)
			for _, quest in changed do
				any = true
				local def = questDefs[quest.def]
				local index = table.find(quests, quest)
				local done = table.find(completed, quest) ~= nil
				Services.NetService:Feedback(player, if done then Net.Feedback.QuestComplete else Net.Feedback.QuestProgress, {
					kind = "quest",
					period = period,
					index = index,
					text = if def then questText(def) else "",
					progress = quest.progress,
					goal = quest.goal,
				})
			end
		end
	end
	if any then
		Services.DataService:MarkDirty(player)
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function RewardService:Init(services)
	Services = services
end

function RewardService:Start()
	local NetService = Services.NetService
	local DataService = Services.DataService

	NetService:Handle(Net.Actions.ClaimStreak, function(player)
		return self:ClaimStreak(player)
	end)
	NetService:Handle(Net.Actions.ClaimQuest, function(player, payload)
		return self:ClaimQuest(player, payload.period, payload.index)
	end)
	NetService:Handle(Net.Actions.ClaimChest, function(player, payload)
		return self:ClaimChest(player, payload.index)
	end)

	NetService.FeedbackSent:Connect(function(player, eventName, ctx)
		self:_onFeedback(player, eventName, ctx)
	end)

	DataService.ProfileLoaded:Connect(function(player, data)
		self:_refresh(player, data)
	end)

	-- Periods roll over while people play; check now and then.
	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Players:GetPlayers() do
				local data = DataService:Get(player)
				if data then
					self:_refresh(player, data)
				end
			end
		end
	end)

	-- What the Quests panel and the login card show. Read-only: no changes here.
	NetService:AddSnapshotBuilder(function(player, snapshot)
		local data = DataService:Get(player)
		if not data then
			return
		end
		local rewards = data.rewards
		local now = os.time()
		local today = FairMath.periodId(now, DAY)
		local claimable = 0

		local streakReady = RewardMath.canClaimStreak(rewards.streak, today)
		if streakReady then
			claimable += 1
		end

		local function questView(period: string): { any }
			local list = {}
			for index, quest in rewards[period].list do
				local def = questDefs[quest.def]
				if def then
					local ready = RewardMath.canClaimQuest(quest)
					if ready then
						claimable += 1
					end
					table.insert(list, {
						index = index,
						text = questText(def),
						kind = quest.kind,
						progress = quest.progress,
						goal = quest.goal,
						claimed = quest.claimed,
						ready = ready,
						reward = def.reward,
						stars = def.stars or 0,
					})
				end
			end
			return list
		end

		local chests = RewardMath.claimableChests(REWARDS.starTrack, rewards.stars.count, rewards.stars.opened)
		claimable += #chests

		snapshot.rewards = {
			streak = {
				count = rewards.streak.count,
				ready = streakReady,
				-- The day a claim pays now (or the one already claimed today).
				day = RewardMath.nextStreakDay(rewards.streak, today, #REWARDS.streak.days),
				broken = RewardMath.streakBroken(rewards.streak, today),
			},
			daily = questView("daily"),
			weekly = questView("weekly"),
			stars = rewards.stars.count,
			opened = rewards.stars.opened,
			dayEndsAt = FairMath.periodEndsAt(today, DAY),
			weekEndsAt = FairMath.periodEndsAt(FairMath.periodId(now, WEEK), WEEK),
			claimable = claimable,
		}
	end)
end

return RewardService
