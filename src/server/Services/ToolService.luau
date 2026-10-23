--!strict
--[[
	ToolService: the garden tools (Watering Bucket, Pest Remover, Fertilizer)
	and the bugs the Pest Remover deals with.

	* Tools live in StarterPack (Tool with a "GardenTool" attribute = Config.Tools
	  item id). The client says "I used <tool> on plot X"; the server checks the tool
	  is equipped, the plot is close enough and the per-player cooldown, then reuses
	  the existing rules: the bucket goes through GardenService:Water, champion
	  bugs through ChampionService:Care.
	* Bugs (Config.Pests) appear on growing regular crops while the owner is in
	  the server and pause growth (GrowthMath.pestPause) until removed.
	* Every successful use is broadcast as Feedback.ToolUsed so all clients can
	  play the tool animation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GrowthMath = require(Shared.GrowthMath)

local ToolService = {}

local Services: any
local rng = Random.new()
local lastUse: { [Player]: number } = {}

local TOOLS = Config.Tools
local PESTS = Config.Pests

function ToolService:Init(services)
	Services = services
end

function ToolService:Start()
	Services.NetService:Handle(Net.Actions.UseTool, function(player, payload)
		return self:Use(player, payload.toolId, payload.ownerUserId, payload.plotId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(PESTS.checkSeconds)
			for _, player in Players:GetPlayers() do
				self:_spawnPests(player)
			end
		end
	end)
end

function ToolService:_spawnPests(player: Player)
	local data = Services.DataService:Get(player)
	if not data or not Services.PlotService:GetGarden(player) then
		return
	end
	local now = os.time()
	for plotId, plant in data.plots do
		local crop = Config.Crops[plant.cropId]
		if crop and not plant.champion and not plant.pestSince and rng:NextNumber() < PESTS.chance then
			if not GrowthMath.evaluate(plant, crop, Config, now).canHarvest then
				GrowthMath.addPests(plant, now, PESTS.maxPauseSeconds)
				Services.PlotService:SyncPlot(player, plotId, plant, false)
				Services.NetService:Feedback(player, Net.Feedback.PestsAppeared, { plotId = plotId, cropId = plant.cropId })
				Services.DataService:MarkDirty(player)
			end
		end
	end
end

-- The equipped tool (in the character, not the backpack) with this GardenTool id.
local function equippedTool(player: Player, toolId: string): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("GardenTool") == toolId then
			return child
		end
	end
	return nil
end

function ToolService:Use(player: Player, toolId: any, ownerUserId: any, plotId: any): (boolean, any)
	if type(toolId) ~= "string" or not TOOLS.items[toolId] then
		return false, "UnknownTool"
	end
	if type(ownerUserId) ~= "number" or type(plotId) ~= "string" then
		return false, "NoPlot"
	end
	if not equippedTool(player, toolId) then
		return false, "ToolNotEquipped"
	end
	local now = os.clock()
	if lastUse[player] and now - lastUse[player] < TOOLS.cooldownSeconds then
		return false, "TooFast"
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local part = owner and Services.PlotService:GetPlotPart(owner, plotId)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not owner or not part or not root then
		return false, "NoPlot"
	end
	if (root.Position - part.Position).Magnitude > TOOLS.useDistance then
		return false, "TooFar"
	end
	lastUse[player] = now

	local ok, result
	if toolId == "WateringBucket" then
		-- Check first so a refusal gives one message (Water reports its own otherwise).
		local data = Services.DataService:Get(owner)
		local plant = data and data.plots[plotId]
		local crop = plant and Config.Crops[plant.cropId]
		if not plant or not crop then
			return false, "NothingPlanted"
		end
		local canWater, reason = GrowthMath.canWater(plant, crop, Config, os.time())
		if not canWater then
			return false, reason
		end
		ok, result = Services.GardenService:Water(player, owner, plotId)
	elseif toolId == "PestRemover" then
		ok, result = self:RemovePests(player, owner, plotId)
	else
		ok, result = self:Fertilize(player, owner, plotId)
	end
	if ok then
		Services.NetService:Broadcast(Net.Remotes.Feedback, Net.Feedback.ToolUsed, {
			userId = player.UserId,
			toolId = toolId,
			ownerUserId = owner.UserId,
			plotId = plotId,
			position = part.Position,
		})
	end
	return ok, result
end

function ToolService:RemovePests(player: Player, owner: Player, plotId: string): (boolean, any)
	local data = Services.DataService:Get(owner)
	local plant = data and data.plots[plotId]
	if not plant then
		return false, "NothingPlanted"
	end
	if plant.champion then
		-- The champion's bugs are one of its care needs.
		local need = Services.ChampionService:PendingNeed(plant, os.time())
		if not need or need.kind ~= "Pests" then
			return false, "NoPests"
		end
		return Services.ChampionService:Care(player, owner, plotId)
	end
	if not plant.pestSince then
		return false, "NoPests"
	end
	GrowthMath.removePests(plant, os.time())
	Services.PlotService:SyncPlot(owner, plotId, plant, false)
	Services.EconomyService:AddXp(player, PESTS.xpPerRemove)
	local context = { plotId = plotId, ownerUserId = owner.UserId, cropId = plant.cropId, xp = PESTS.xpPerRemove }
	if player ~= owner then
		Services.EconomyService:AddCoins(player, PESTS.friendRewardCoins, "FriendPests")
		context.coins = PESTS.friendRewardCoins
		context.helperName = player.DisplayName
		Services.NetService:Feedback(owner, Net.Feedback.PestsRemoved, context)
	end
	Services.NetService:Feedback(player, Net.Feedback.PestsRemoved, context)
	Services.DataService:MarkDirty(owner)
	return true, nil
end

function ToolService:Fertilize(player: Player, owner: Player, plotId: string): (boolean, any)
	if player ~= owner then
		return false, "NotYourPlot"
	end
	local data = Services.DataService:Get(player)
	local plant = data and data.plots[plotId]
	local crop = plant and Config.Crops[plant.cropId]
	if not plant or not crop then
		return false, "NothingPlanted"
	end
	if plant.fertilized then
		return false, "AlreadyFertilized"
	end
	local now = os.time()
	if GrowthMath.evaluate(plant, crop, Config, now).isMaxed then
		return false, "Maxed"
	end
	local supplyId = TOOLS.items.Fertilizer.supply
	local bags = data.supplies[supplyId] or 0
	if bags <= 0 then
		return false, "NoFertilizer"
	end
	data.supplies[supplyId] = bags - 1
	local boost = GrowthMath.fertilizerBoostSeconds(crop, TOOLS)
	plant.bonusSeconds += boost
	plant.fertilized = true
	Services.PlotService:SyncPlot(player, plotId, plant, false)
	Services.EconomyService:AddXp(player, TOOLS.xpPerFertilize)
	Services.NetService:Feedback(player, Net.Feedback.Fertilized, {
		plotId = plotId,
		cropId = plant.cropId,
		boost = boost,
		bagsLeft = data.supplies[supplyId],
		xp = TOOLS.xpPerFertilize,
	})
	Services.DataService:MarkDirty(player)
	return true, { boost = boost }
end

return ToolService
