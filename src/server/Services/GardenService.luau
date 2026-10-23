--!strict
--[[
	GardenService: the core loop. Plant -> grow (timestamps) -> water -> harvest.

	* Every action is validated here against the profile; the client only says
	  "I pressed the prompt on plot X".
	* Friends (or anyone, see Config.Watering.requireFriendship) can water your
	  crops. They get a small tip, you get the growth boost and a notification.
	* On join, a "welcome back" summary lists what ripened while you were away.
	* A light server loop watches for stage changes so it can fire feel events
	  (e.g. "your pumpkin just became a Giant!") without the client polling.
	* New arrivals claim a free garden slot (prompt or "Pick for me"); if they
	  don't choose within Config.World.autoPickSeconds, one is picked for them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GrowthMath = require(Shared.GrowthMath)
local EconomyMath = require(Shared.EconomyMath)
local FairMath = require(Shared.FairMath)

local GardenService = {}

local Services: any
local rng = Random.new()
local friendCache: { [string]: boolean } = {}
-- Last known stage per player/plot, used to detect transitions.
local lastStages: { [Player]: { [string]: string } } = {}
-- Players whose profile has loaded but who haven't claimed a garden yet (value: join info).
local pendingClaims: { [Player]: { [string]: any } } = {}

local STAGE_CHECK_SECONDS = 1

local function dayId(now: number): number
	return now // 86400
end

local function isFriend(a: Player, b: Player): boolean
	local key = math.min(a.UserId, b.UserId) .. ":" .. math.max(a.UserId, b.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	local value = ok and result == true
	friendCache[key] = value
	return value
end

function GardenService:Init(services)
	Services = services
end

function GardenService:Start()
	local DataService = Services.DataService
	local PlotService = Services.PlotService
	local NetService = Services.NetService

	DataService.ProfileLoaded:Connect(function(player, data, info)
		pendingClaims[player] = info
		task.delay(Config.World.autoPickSeconds, function()
			if pendingClaims[player] and player.Parent then
				self:ClaimGarden(player, nil)
			end
		end)
	end)

	PlotService.ClaimRequested:Connect(function(player, slot)
		local ok, reason = self:ClaimGarden(player, slot)
		if not ok and reason ~= "AlreadyClaimed" then
			NetService:Feedback(player, Net.Feedback.Denied, { action = Net.Actions.ClaimPlot, reason = reason })
		end
	end)

	NetService:Handle(Net.Actions.ClaimPlot, function(player, payload)
		local slot = payload.slot
		return self:ClaimGarden(player, if type(slot) == "number" then slot else nil)
	end)

	DataService.Dirty:Connect(function(player)
		local data = DataService:Get(player)
		if data then
			NetService:PushState(player, data)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastStages[player] = nil
		pendingClaims[player] = nil
	end)

	PlotService.PromptTriggered:Connect(function(player, ownerUserId, plotId, kind)
		local owner = Players:GetPlayerByUserId(ownerUserId)
		if not owner then
			return
		end
		local ok, reason
		if kind == "Care" then
			ok, reason = Services.ChampionService:Care(player, owner, plotId)
		elseif owner == player and kind == "Main" then
			ok, reason = self:PrimaryAction(player, plotId)
		else
			-- Watering only happens with the Watering Bucket (ToolService), never a prompt.
			ok, reason = false, "UseBucket"
		end
		-- Prompts bypass NetService, so surface failures here (Water already reports its own).
		if not ok and type(reason) == "string" and reason ~= "Cooldown" and reason ~= "Maxed" then
			NetService:Feedback(player, Net.Feedback.Denied, { reason = reason, plotId = plotId })
		end
	end)

	NetService:Handle(Net.Actions.SelectSeed, function(player, payload)
		local data = DataService:Get(player)
		local cropId = payload.cropId
		if not data or type(cropId) ~= "string" or not Config.Crops[cropId] then
			return false, "UnknownCrop"
		end
		data.selectedSeed = cropId
		DataService:MarkDirty(player)
		return true, nil
	end)

	task.spawn(function()
		while true do
			task.wait(STAGE_CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				self:_checkStages(player)
			end
		end
	end)
end

-- Builds the player's garden on `slot` (nil = any free slot), syncs it and moves them there.
function GardenService:ClaimGarden(player: Player, slot: number?): (boolean, any)
	local PlotService = Services.PlotService
	local info = pendingClaims[player]
	local data = Services.DataService:Get(player)
	if not info or not data then
		return false, if PlotService:GetGarden(player) then "AlreadyClaimed" else "NotLoaded"
	end
	if not PlotService:AssignGarden(player, slot) then
		return false, if slot then "PlotTaken" else "NoFreePlot"
	end
	pendingClaims[player] = nil
	PlotService:SyncAll(player, data)
	lastStages[player] = self:_currentStages(data)
	self:_sendWelcomeBack(player, data, info)
	self:_moveToGarden(player)
	player.CharacterAdded:Connect(function()
		task.defer(self._moveToGarden, self, player)
	end)
	return true, nil
end

function GardenService:_moveToGarden(player: Player)
	local cf = Services.PlotService:GetSpawnCFrame(player)
	local character = player.Character
	if cf and character then
		character:PivotTo(cf)
	end
end

function GardenService:_currentStages(data: { [string]: any }): { [string]: string }
	local now = os.time()
	local stages = {}
	for plotId, plant in data.plots do
		local crop = Config.Crops[plant.cropId]
		if crop then
			stages[plotId] = GrowthMath.evaluate(plant, crop, Config, now).stage
		end
	end
	return stages
end

function GardenService:_checkStages(player: Player)
	local data = Services.DataService:Get(player)
	local previous = lastStages[player]
	if not data or not previous then
		return
	end
	local current = self:_currentStages(data)
	for plotId, stage in current do
		if previous[plotId] and previous[plotId] ~= stage then
			Services.NetService:Feedback(player, Net.Feedback.StageChanged, {
				plotId = plotId,
				cropId = data.plots[plotId].cropId,
				from = previous[plotId],
				to = stage,
			})
		end
	end
	lastStages[player] = current
end

function GardenService:_sendWelcomeBack(player: Player, data: { [string]: any }, info: { [string]: any })
	if info.isNew or info.offlineSeconds < 60 then
		return
	end
	local now = os.time()
	local ready, giants = {}, 0
	for plotId, plant in data.plots do
		local crop = Config.Crops[plant.cropId]
		if crop then
			local state = GrowthMath.evaluate(plant, crop, Config, now)
			if state.canHarvest then
				table.insert(ready, { plotId = plotId, cropId = plant.cropId, weight = state.weight, stage = state.stage })
				if state.stage == "Giant" then
					giants += 1
				end
			end
		end
	end
	Services.NetService:Feedback(player, Net.Feedback.WelcomeBack, {
		offlineSeconds = info.offlineSeconds,
		ready = ready,
		giants = giants,
	})
end

-- E on your own plot: plant when empty, harvest when ripe. Watering needs the bucket.
function GardenService:PrimaryAction(player: Player, plotId: string): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local index = tonumber(plotId)
	local isChampionPlot = plotId == Config.Champion.plotId
	if not isChampionPlot and (not index or index > data.ownedPlots) then
		if index == data.ownedPlots + 1 then
			return Services.EconomyService:BuyPlot(player)
		end
		return false, "PlotLocked"
	end
	local plant = data.plots[plotId]
	if not plant then
		return self:Plant(player, plotId, data.selectedSeed)
	end
	local crop = Config.Crops[plant.cropId]
	if crop and GrowthMath.evaluate(plant, crop, Config, os.time()).canHarvest then
		return self:Harvest(player, plotId)
	end
	return false, "UseBucket"
end

function GardenService:Plant(player: Player, plotId: string, cropId: string): (boolean, any)
	local DataService = Services.DataService
	local data = DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local index = tonumber(plotId)
	local isChampionPlot = plotId == Config.Champion.plotId
	if not isChampionPlot and (not index or index < 1 or index > data.ownedPlots) then
		return false, "PlotLocked"
	end
	if data.plots[plotId] then
		return false, "PlotBusy"
	end
	local crop = Config.Crops[cropId]
	if not crop then
		return false, "UnknownCrop"
	end
	-- Free crops (seedCost 0) never run out so a new player can't get stuck.
	local owned = data.seeds[cropId] or 0
	if owned <= 0 and crop.seedCost > 0 then
		return false, "NoSeeds"
	end
	if owned > 0 then
		data.seeds[cropId] = owned - 1
	end

	local Economy = Services.EconomyService
	local plant = GrowthMath.newPlant(
		crop,
		Config.Growth,
		os.time(),
		Economy:GetUpgradeValue(player, "fertilizer"),
		Economy:GetUpgradeValue(player, "greenThumb"),
		rng:NextNumber(),
		rng:NextNumber()
	)
	if isChampionPlot then
		Services.ChampionService:SetupChampion(plant, crop)
	end
	data.plots[plotId] = plant
	lastStages[player] = lastStages[player] or {}
	lastStages[player][plotId] = "Seed"

	Services.PlotService:SyncPlot(player, plotId, plant, false)
	Services.NetService:Feedback(player, Net.Feedback.Planted, {
		plotId = plotId,
		cropId = cropId,
		gene = plant.gene,
		champion = isChampionPlot,
	})
	DataService:MarkDirty(player)
	return true, nil
end

function GardenService:Water(waterer: Player, owner: Player, plotId: string): (boolean, any)
	local DataService = Services.DataService
	local NetService = Services.NetService
	local data = DataService:Get(owner)
	local watererData = DataService:Get(waterer)
	if not data or not watererData then
		return false, "NotLoaded"
	end
	local plant = data.plots[plotId]
	if not plant then
		return false, "NothingPlanted"
	end
	local crop = Config.Crops[plant.cropId]
	if not crop then
		return false, "UnknownCrop"
	end

	local isSelf = waterer == owner
	local now = os.time()

	if not isSelf then
		if Config.Watering.requireFriendship and not isFriend(waterer, owner) then
			return false, "NotFriends"
		end
		local log = watererData.friendWaterLog
		if log.day ~= dayId(now) then
			log.day = dayId(now)
			log.targets = {}
		end
		local key = tostring(owner.UserId)
		if (log.targets[key] or 0) >= Config.Watering.friendWatersPerTargetPerDay then
			return false, "FriendLimit"
		end
	end

	local ok, reason, wait = GrowthMath.canWater(plant, crop, Config, now)
	if not ok then
		NetService:Feedback(waterer, Net.Feedback.Denied, { action = "Water", reason = reason, wait = wait, plotId = plotId })
		return false, reason
	end

	-- The waterer's can upgrade powers the boost, so good friends are worth having.
	local canMult = Services.EconomyService:GetUpgradeValue(waterer, "wateringCan")
	local boost = GrowthMath.applyWater(plant, crop, Config, now, canMult)
	-- Watering also answers a champion's "Water" care need.
	local careCredit = if plant.champion then Services.ChampionService:OnWatered(waterer, owner, plotId, plant) else nil
	Services.PlotService:SyncPlot(owner, plotId, plant, false)

	if isSelf then
		NetService:Feedback(owner, Net.Feedback.Watered, { plotId = plotId, boost = boost, cropId = plant.cropId, care = careCredit })
	else
		local key = tostring(owner.UserId)
		local log = watererData.friendWaterLog
		log.targets[key] = (log.targets[key] or 0) + 1
		watererData.stats.friendWaters += 1
		-- Helpful Neighbor division counts friend waters per fair week.
		local weekKey = tostring(FairMath.weekId(now, Config.Fair))
		watererData.fair.helper[weekKey] = (watererData.fair.helper[weekKey] or 0) + 1
		Services.FairService:MarkHelperDirty(waterer)
		Services.EconomyService:AddCoins(waterer, Config.Watering.friendRewardCoins, "FriendWater")
		Services.EconomyService:AddXp(waterer, Config.Levels.xpPerFriendWater)
		NetService:Feedback(waterer, Net.Feedback.YouWateredFriend, {
			ownerName = owner.DisplayName,
			plotId = plotId,
			coins = Config.Watering.friendRewardCoins,
			ownerUserId = owner.UserId,
			xp = Config.Levels.xpPerFriendWater,
			care = careCredit,
		})
		NetService:Feedback(owner, Net.Feedback.FriendWateredYou, {
			friendName = waterer.DisplayName,
			plotId = plotId,
			boost = boost,
			cropId = plant.cropId,
		})
		DataService:MarkDirty(waterer)
	end
	DataService:MarkDirty(owner)
	return true, { boost = boost }
end

function GardenService:Harvest(player: Player, plotId: string): (boolean, any)
	local DataService = Services.DataService
	local data = DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local plant = data.plots[plotId]
	if not plant then
		return false, "NothingPlanted"
	end
	local crop = Config.Crops[plant.cropId]
	if not crop then
		return false, "UnknownCrop"
	end
	local state = GrowthMath.evaluate(plant, crop, Config, os.time())
	if not state.canHarvest then
		return false, "NotRipe"
	end
	if #data.produce >= Config.Economy.maxProduceInventory then
		return false, "BasketFull"
	end

	local weight = math.floor(state.weight * 1000 + 0.5) / 1000
	local item = {
		uid = data.nextUid,
		cropId = plant.cropId,
		weight = weight,
		isGiant = state.stage == "Giant",
		gene = plant.gene,
		harvestedAt = os.time(),
	}
	if plant.champion then
		item.isChampion = true
		item.name = plant.name
		item.coGrowers = plant.coGrowers
		item.careScore = plant.careScore
		item.paidSkips = plant.paidSkips or 0
	end
	data.nextUid += 1
	table.insert(data.produce, item)
	data.plots[plotId] = nil
	if lastStages[player] then
		lastStages[player][plotId] = nil
	end

	local isRecord = weight > data.stats.heaviest
	data.stats.harvested += 1
	if isRecord then
		data.stats.heaviest = weight
	end

	Services.PlotService:SyncPlot(player, plotId, nil, false)
	local xp = EconomyMath.harvestXp(weight, Config.Levels)
	Services.EconomyService:AddXp(player, xp)
	Services.NetService:Feedback(player, Net.Feedback.Harvested, {
		plotId = plotId,
		cropId = item.cropId,
		weight = weight,
		isGiant = item.isGiant,
		isRecord = isRecord,
		isChampion = item.isChampion,
		uid = item.uid,
		xp = xp,
	})
	DataService:MarkDirty(player)
	return true, item
end

-- Used by MonetizationService. Returns the plot that was skipped, or nil.
function GardenService:SkipGrowth(player: Player, plotId: string?): string?
	local data = Services.DataService:Get(player)
	if not data then
		return nil
	end
	local now = os.time()
	local target, bestRemaining = nil, 0
	if plotId and data.plots[plotId] then
		target = plotId
	else
		-- No (valid) target chosen: skip the plant with the longest wait left.
		for id, plant in data.plots do
			-- Never spend a skip on the champion unless the player picked it (honest shop).
			local crop = not plant.champion and Config.Crops[plant.cropId]
			local remaining = crop and GrowthMath.skipSecondsNeeded(plant, crop, now) or 0
			if remaining > bestRemaining then
				target, bestRemaining = id, remaining
			end
		end
	end
	if not target then
		return nil
	end
	local plant = data.plots[target]
	local crop = Config.Crops[plant.cropId]
	GrowthMath.applySkip(plant, crop, now)
	plant.paidSkips = (plant.paidSkips or 0) + 1
	Services.PlotService:SyncPlot(player, target, plant, false)
	Services.DataService:MarkDirty(player)
	return target
end

return GardenService
