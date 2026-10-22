--!strict
--[[
	ChampionService: the one veggie each player raises with care all week.

	* Care: needs (Water / Pests / Prop) appear on a timestamp schedule
	  (CareMath). Handling them adds weight. Care beats the Giant gene.
	* Name tag: players name their champion (text filtered for a young audience).
	* Grow together: invite up to Config.Champion.maxCoGrowers friends. Co-growers
	  can water and care for the champion, are listed on its fair card, and get
	  a share of its prizes by mail.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GrowthMath = require(Shared.GrowthMath)
local CareMath = require(Shared.CareMath)

local ChampionService = {}

local Services: any
-- invites[targetUserId][ownerUserId] = sentAt
local invites: { [number]: { [number]: number } } = {}
-- Last care need index announced per owner, so CareNeeded fires once per need.
local announced: { [Player]: number } = {}

local CHAMPION = Config.Champion

local function isRipeAt(plant: { [string]: any }, crop: any): (t: number) -> boolean
	return function(t: number)
		return GrowthMath.evaluate(plant :: any, crop, Config, t).canHarvest
	end
end

local function canTend(player: Player, owner: Player, plant: { [string]: any }): boolean
	if player == owner then
		return true
	end
	for _, userId in plant.coGrowers or {} do
		if userId == player.UserId then
			return true
		end
	end
	return false
end

function ChampionService:Init(services)
	Services = services
end

function ChampionService:Start()
	local NetService = Services.NetService

	NetService:Handle(Net.Actions.NameChampion, function(player, payload)
		return self:Name(player, payload.name)
	end)
	NetService:Handle(Net.Actions.InviteCoGrower, function(player, payload)
		return self:Invite(player, payload.userId)
	end)
	NetService:Handle(Net.Actions.RespondCoGrow, function(player, payload)
		return self:Respond(player, payload.ownerUserId, payload.accept == true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		announced[player] = nil
		invites[player.UserId] = nil
	end)

	-- Tell owners (and co-growers in the server) when a new care need appears.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, owner in Players:GetPlayers() do
				self:_checkNeeds(owner)
			end
		end
	end)
end

-- Called by GardenService when a champion is planted.
function ChampionService:SetupChampion(plant: { [string]: any }, crop: any)
	local def = GrowthMath.championDef(crop, CHAMPION)
	plant.champion = true
	plant.careInterval = if RunService:IsStudio()
		then CHAMPION.studioCareIntervalSeconds
		else CareMath.intervalFor(crop, CHAMPION, def.growSeconds + def.giantSeconds)
	plant.careScore = 0
	plant.care = {}
	plant.coGrowers = {}
	plant.paidSkips = 0
end

function ChampionService:PendingNeed(plant: { [string]: any }, now: number): CareMath.Need?
	local crop = Config.Crops[plant.cropId]
	if not plant.champion or not crop then
		return nil
	end
	return CareMath.pendingNeed(plant, CHAMPION, now, isRipeAt(plant, crop))
end

function ChampionService:_credit(carer: Player, owner: Player, plant: { [string]: any }, need: CareMath.Need): number
	local credit = CareMath.applyCare(plant, need, CHAMPION)
	Services.EconomyService:AddXp(carer, CHAMPION.xpPerCare)
	local context = {
		plotId = CHAMPION.plotId,
		ownerUserId = owner.UserId,
		kind = need.kind,
		credit = credit,
		careScore = plant.careScore,
		xp = CHAMPION.xpPerCare,
		carerName = carer.DisplayName,
		carerUserId = carer.UserId,
	}
	Services.NetService:Feedback(carer, Net.Feedback.CareDone, context)
	if carer ~= owner then
		Services.NetService:Feedback(owner, Net.Feedback.CareDone, context)
	end
	return credit
end

-- Called from GardenService:Water. Returns the care credit if a Water need was answered.
function ChampionService:OnWatered(waterer: Player, owner: Player, _plotId: string, plant: { [string]: any }): number?
	if not canTend(waterer, owner, plant) then
		return nil
	end
	local need = self:PendingNeed(plant, os.time())
	if need and need.kind == "Water" then
		return self:_credit(waterer, owner, plant, need)
	end
	return nil
end

-- F on the champion: pick off pests / prop it up (or water when that is the need).
function ChampionService:Care(player: Player, owner: Player, plotId: string): (boolean, any)
	if plotId ~= CHAMPION.plotId then
		return false, "NotChampion"
	end
	local data = Services.DataService:Get(owner)
	local plant = data and data.plots[plotId]
	if not plant or not plant.champion then
		return false, "NothingPlanted"
	end
	if not canTend(player, owner, plant) then
		return false, "NotCoGrower"
	end
	local need = self:PendingNeed(plant, os.time())
	if not need then
		return false, "NoCareNeeded"
	end
	if need.kind == "Water" then
		-- Water needs go through the normal watering rules (cooldown, boost).
		return Services.GardenService:Water(player, owner, plotId)
	end
	local credit = self:_credit(player, owner, plant, need)
	Services.PlotService:SyncPlot(owner, plotId, plant, false)
	Services.DataService:MarkDirty(owner)
	return true, { credit = credit }
end

function ChampionService:_checkNeeds(owner: Player)
	local data = Services.DataService:Get(owner)
	local plant = data and data.plots[CHAMPION.plotId]
	if not plant then
		return
	end
	local need = self:PendingNeed(plant, os.time())
	if need and announced[owner] ~= need.k then
		announced[owner] = need.k
		local context = { plotId = CHAMPION.plotId, ownerUserId = owner.UserId, kind = need.kind, cropId = plant.cropId }
		Services.NetService:Feedback(owner, Net.Feedback.CareNeeded, context)
		for _, userId in plant.coGrowers or {} do
			local coGrower = Players:GetPlayerByUserId(userId)
			if coGrower then
				Services.NetService:Feedback(coGrower, Net.Feedback.CareNeeded, context)
			end
		end
	end
end

function ChampionService:Name(player: Player, rawName: any): (boolean, any)
	local data = Services.DataService:Get(player)
	local plant = data and data.plots[CHAMPION.plotId]
	if not plant then
		return false, "NothingPlanted"
	end
	if type(rawName) ~= "string" then
		return false, "BadName"
	end
	local trimmed = rawName:gsub("^%s+", ""):gsub("%s+$", "")
	if #trimmed == 0 or utf8.len(trimmed) == nil or (utf8.len(trimmed) :: number) > CHAMPION.maxNameLength then
		return false, "BadName"
	end
	-- Everyone in the server sees the name, so filter it as broadcast text.
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(trimmed, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" or #filtered == 0 then
		return false, "FilterFailed"
	end
	plant.name = filtered
	Services.PlotService:SyncPlot(player, CHAMPION.plotId, plant, false)
	Services.NetService:Feedback(player, Net.Feedback.ChampionNamed, { name = filtered, plotId = CHAMPION.plotId })
	Services.DataService:MarkDirty(player)
	return true, { name = filtered }
end

local function friendsOk(a: Player, b: Player): boolean
	if not CHAMPION.coGrowRequiresFriendship or RunService:IsStudio() then
		return true
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	return ok and result == true
end

function ChampionService:Invite(owner: Player, targetUserId: any): (boolean, any)
	local data = Services.DataService:Get(owner)
	local plant = data and data.plots[CHAMPION.plotId]
	if not plant then
		return false, "NothingPlanted"
	end
	local target = type(targetUserId) == "number" and Players:GetPlayerByUserId(targetUserId)
	if not target or target == owner then
		return false, "PlayerNotHere"
	end
	plant.coGrowers = plant.coGrowers or {}
	if #plant.coGrowers >= CHAMPION.maxCoGrowers then
		return false, "TeamFull"
	end
	if table.find(plant.coGrowers, target.UserId) then
		return false, "AlreadyCoGrower"
	end
	if not friendsOk(owner, target) then
		return false, "NotFriends"
	end
	invites[target.UserId] = invites[target.UserId] or {}
	invites[target.UserId][owner.UserId] = os.time()
	Services.NetService:Feedback(target, Net.Feedback.CoGrowInvite, {
		ownerUserId = owner.UserId,
		ownerName = owner.DisplayName,
		cropId = plant.cropId,
		championName = plant.name,
	})
	return true, nil
end

function ChampionService:Respond(player: Player, ownerUserId: any, accept: boolean): (boolean, any)
	local pending = invites[player.UserId]
	local sentAt = pending and type(ownerUserId) == "number" and pending[ownerUserId]
	if not sentAt or os.time() - sentAt > CHAMPION.inviteExpiresSeconds then
		return false, "InviteExpired"
	end
	pending[ownerUserId] = nil
	if not accept then
		return true, nil
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local data = owner and Services.DataService:Get(owner)
	local plant = data and data.plots[CHAMPION.plotId]
	if not owner or not plant then
		return false, "InviteExpired"
	end
	plant.coGrowers = plant.coGrowers or {}
	if #plant.coGrowers >= CHAMPION.maxCoGrowers then
		return false, "TeamFull"
	end
	if not table.find(plant.coGrowers, player.UserId) then
		table.insert(plant.coGrowers, player.UserId)
	end
	Services.PlotService:SyncPlot(owner, CHAMPION.plotId, plant, false)
	local context = { ownerUserId = owner.UserId, ownerName = owner.DisplayName, coGrowerName = player.DisplayName }
	Services.NetService:Feedback(owner, Net.Feedback.CoGrowJoined, context)
	Services.NetService:Feedback(player, Net.Feedback.CoGrowJoined, context)
	Services.DataService:MarkDirty(owner)
	return true, nil
end

return ChampionService
