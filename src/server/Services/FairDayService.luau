--!strict
--[[
	FairDayService: the live weigh-in shows, run in every server when a fair
	(hourly, daily or weekly) rolls over. Timings scale per fair
	(Config.Fair.periods[*].show): the hourly show is a quick minute, the
	weekly Grand Fair is the full five-minute event.

	Phases (broadcast to all clients on the FairDay remote):
	  Announce  countdown banner during the last minutes of the week
	  Gather    camera moves to the stage, "Fair Day is starting!"
	  Weigh     each entry in this server rolls onto the scale, lightest first
	  Awards    top three in this server get ribbons and coins on the podium
	  Global    the global top three for the week
	  Empty     small-server fallback when nobody here entered
	  Idle      show over; rewards are claimed for everyone in the server

	Players who join after the show get the results as a replay card
	(FairService.ClaimRewards sends missedShow = true).
	When daily and weekly roll over together, only the weekly show runs.
	In Studio, the DebugStartFairDay action ({ fair }) previews the current period.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local FairMath = require(Shared.FairMath)

local FairDayService = {}

local Services: any
local FD = Config.FairDay
local PERIODS = Config.Fair.periods
local runningFair: string? = nil
local lastShown: { [string]: number } = {}
local currentState: { [string]: any } = { phase = "Idle" }

local function broadcast(state: { [string]: any })
	state.serverTime = os.time()
	currentState = state
	Services.NetService:Broadcast(Net.Remotes.FairDay, state)
end

function FairDayService:Init(services)
	Services = services
end

function FairDayService:Start()
	Services.NetService:Handle(Net.Actions.DebugStartFairDay, function(_player, payload)
		if not RunService:IsStudio() then
			return false, "StudioOnly"
		end
		if runningFair then
			return false, "ShowRunning"
		end
		local fairName = if type(payload.fair) == "string" and PERIODS[payload.fair] then payload.fair else "weekly"
		task.spawn(self.RunShow, self, fairName, FairMath.periodId(os.time(), PERIODS[fairName]), true)
		return true, nil
	end)

	-- Late joiners see whatever is on screen right now.
	Services.DataService.ProfileLoaded:Connect(function(player)
		Services.NetService:FireClient(Net.Remotes.FairDay, player, currentState)
	end)

	task.spawn(function()
		while true do
			self:_tick()
			task.wait(1)
		end
	end)
end

function FairDayService:IsShowRunning(): boolean
	return runningFair ~= nil
end

function FairDayService:IsShowRunningFor(fairName: string): boolean
	return runningFair == fairName
end

function FairDayService:_tick()
	if runningFair then
		return
	end
	local now = os.time()
	-- Biggest fair first, so a shared rollover runs the weekly show.
	local periods = FairMath.sortedPeriods(PERIODS)
	local announce = nil
	for i = #periods, 1, -1 do
		local period = periods[i]
		local phase, id, at = FairMath.showPhase(now, period)
		if phase == "Live" and lastShown[period.id] ~= id then
			-- Mark smaller fairs that rolled over at the same moment as shown too.
			for _, other in periods do
				local otherPhase, otherId, otherAt = FairMath.showPhase(now, other)
				if otherPhase == "Live" and otherAt == at then
					lastShown[other.id] = otherId
				end
			end
			task.spawn(self.RunShow, self, period.id, id, false)
			return
		elseif phase == "Announce" and (not announce or at < announce.startsAt) then
			announce = { phase = "Announce", fair = period.id, fairName = period.displayName, periodId = id, startsAt = at }
		end
	end
	if announce then
		if currentState.phase ~= "Announce" or currentState.fair ~= announce.fair then
			broadcast(announce)
		end
	elseif currentState.phase == "Announce" then
		broadcast({ phase = "Idle" })
	end
end

-- Entries from players in this server for one fair period.
function FairDayService:_serverEntries(fairName: string, id: number): { any }
	local key = tostring(id)
	local entries = {}
	for _, player in Players:GetPlayers() do
		local data = Services.DataService:Get(player)
		local entry = data and data.fair.entries[fairName][key]
		if entry then
			local item = entry.item or {}
			table.insert(entries, {
				userId = player.UserId,
				ownerName = player.DisplayName,
				cropId = entry.cropId,
				weight = entry.weight,
				championName = item.name,
				coGrowerNames = if item.coGrowers then Services.FairService.NamesOf(item.coGrowers) else nil,
				isChampion = item.isChampion == true,
			})
		end
	end
	return entries
end

function FairDayService:RunShow(fairName: string, id: number, preview: boolean)
	local period = PERIODS[fairName]
	local show = period.show
	runningFair = fairName
	local base = { fair = fairName, fairName = period.displayName, periodId = id, preview = preview }
	local function state(fields: { [string]: any }, seconds: number)
		local s = table.clone(base)
		for k, v in fields do
			s[k] = v
		end
		s.endsAt = os.time() + seconds
		broadcast(s)
		task.wait(seconds)
	end

	local ok, err = pcall(function()
		local entries = FairMath.stageOrder(self:_serverEntries(fairName, id), show.maxStageEntries)
		state({ phase = "Gather", count = #entries }, show.gatherSeconds)

		if #entries == 0 then
			state({ phase = "Empty" }, show.emptySeconds)
		else
			for index, entry in entries do
				state({ phase = "Weigh", index = index, total = #entries, entry = entry }, show.weighSecondsPerEntry)
			end

			-- Heaviest three in this server, biggest first.
			local podium = {}
			for i = #entries, math.max(1, #entries - 2), -1 do
				local place = #podium + 1
				local entry = table.clone(entries[i])
				local prize = FD.serverPrizes[place]
				entry.place = place
				entry.prize = { coins = math.floor(prize.coins * show.prizeScale), ribbon = prize.ribbon }
				table.insert(podium, entry)
			end
			if not preview then
				self:_awardServerPrizes(fairName, podium)
			end
			state({ phase = "Awards", podium = podium }, show.awardsSeconds)
		end

		state({ phase = "Global", rows = Services.FairService:BoardRows(fairName, id, 3) }, show.globalSeconds)
	end)
	if not ok then
		warn("[FairDayService] show failed: " .. tostring(err))
	end
	broadcast({ phase = "Idle" })
	runningFair = nil

	if not preview then
		-- Everyone here watched; their results come right after the show.
		for _, player in Players:GetPlayers() do
			local data = Services.DataService:Get(player)
			if data then
				data.fair.watched[fairName][tostring(id)] = true
				task.spawn(Services.FairService.ClaimRewards, Services.FairService, player, data)
			end
		end
	end
end

function FairDayService:_awardServerPrizes(fairName: string, podium: { any })
	for _, entry in podium do
		local player = Players:GetPlayerByUserId(entry.userId)
		local data = player and Services.DataService:Get(player)
		local prize = entry.prize
		if player and data and prize then
			local ribbon = FairMath.ribbonId(fairName, prize.ribbon, "server")
			data.ribbons[ribbon] = (data.ribbons[ribbon] or 0) + 1
			Services.EconomyService:AddCoins(player, prize.coins, "FairDay")
			Services.NetService:Feedback(player, Net.Feedback.ServerPrize, {
				fair = fairName,
				fairName = PERIODS[fairName].displayName,
				place = entry.place,
				coins = prize.coins,
				ribbon = ribbon,
			})
			Services.DataService:MarkDirty(player)
		end
	end
end

return FairDayService
