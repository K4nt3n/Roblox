--!strict
--[[
	FairService: the weekly Giant Veggie weigh-in.

	* A player enters one harvested crop per week. Entering a heavier crop
	  replaces the old entry and the old crop goes back to the basket.
	* Scores live in an OrderedDataStore per week (grams), shared by all servers.
	* The live top 10 is broadcast to every client on an interval.
	* When a week ends, rewards are claimed the next time the player joins:
	  rank tier -> coins + a ribbon.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local FairMath = require(Shared.FairMath)

local FairService = {}

local Services: any
local nameCache: { [number]: string } = {}
local latestBoard: { any } = {}

-- In-memory fallback: weekId -> { [userId]: score }
local memoryBoards: { [number]: { [number]: number } } = {}

local function useMemory(): boolean
	return Services.DataService:IsUsingMemoryStore()
end

local function storeFor(weekId: number): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(Config.Data.fairStorePrefix .. weekId)
end

local function displayName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.DisplayName
	if not name then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok then result else ("Gardener " .. userId)
	end
	nameCache[userId] = name :: string
	return name :: string
end

-- Keeps the higher of the stored and new score.
local function submitScore(weekId: number, userId: number, score: number)
	if useMemory() then
		local board = memoryBoards[weekId] or {}
		memoryBoards[weekId] = board
		board[userId] = math.max(board[userId] or 0, score)
		return
	end
	local ok, err = pcall(function()
		storeFor(weekId):UpdateAsync(tostring(userId), function(old)
			return math.max(old or 0, score)
		end)
	end)
	if not ok then
		warn("[FairService] submit failed: " .. tostring(err))
	end
end

-- Returns { { userId, score } } sorted descending, up to `limit`.
local function topScores(weekId: number, limit: number): { { userId: number, score: number } }
	local rows = {}
	if useMemory() then
		for userId, score in memoryBoards[weekId] or {} do
			table.insert(rows, { userId = userId, score = score })
		end
		table.sort(rows, function(a, b)
			return a.score > b.score
		end)
		while #rows > limit do
			table.remove(rows)
		end
		return rows
	end
	local ok, err = pcall(function()
		local pages = storeFor(weekId):GetSortedAsync(false, math.min(limit, 100))
		while true do
			for _, entry in pages:GetCurrentPage() do
				table.insert(rows, { userId = tonumber(entry.key) :: number, score = entry.value })
				if #rows >= limit then
					return
				end
			end
			if pages.IsFinished then
				return
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		warn("[FairService] read failed: " .. tostring(err))
	end
	return rows
end

local function rankOf(weekId: number, userId: number): number?
	-- Only the deepest finite tier matters; past that everyone is an "entrant".
	local deepest = 0
	for _, tier in Config.Fair.rewardTiers do
		if tier.topN ~= math.huge then
			deepest = math.max(deepest, tier.topN)
		end
	end
	for index, row in topScores(weekId, deepest) do
		if row.userId == userId then
			return index
		end
	end
	return nil
end

function FairService:Init(services)
	Services = services
end

function FairService:Start()
	Services.NetService:Handle(Net.Actions.EnterFair, function(player, payload)
		return self:Enter(player, payload.uid)
	end)

	Services.DataService.ProfileLoaded:Connect(function(player, data)
		task.spawn(self._claimRewards, self, player, data)
		Services.NetService:FireClient(Net.Remotes.Leaderboard, player, self:_boardPayload())
	end)

	Services.NetService:AddSnapshotBuilder(function(_player, snapshot)
		local now = os.time()
		snapshot.fairWeek = FairMath.weekId(now, Config.Fair)
		snapshot.fairEndsAt = FairMath.weekEndsAt(snapshot.fairWeek, Config.Fair)
	end)

	task.spawn(function()
		while true do
			self:_refreshBoard()
			task.wait(Config.Fair.leaderboardRefreshSeconds)
		end
	end)
end

function FairService:_boardPayload()
	local week = FairMath.weekId(os.time(), Config.Fair)
	return { weekId = week, endsAt = FairMath.weekEndsAt(week, Config.Fair), rows = latestBoard }
end

function FairService:_refreshBoard()
	local week = FairMath.weekId(os.time(), Config.Fair)
	local rows = {}
	for index, row in topScores(week, Config.Fair.leaderboardSize) do
		table.insert(rows, {
			rank = index,
			userId = row.userId,
			name = displayName(row.userId),
			weight = FairMath.scoreToWeight(row.score),
		})
	end
	latestBoard = rows
	Services.NetService:Broadcast(Net.Remotes.Leaderboard, self:_boardPayload())
end

function FairService:Enter(player: Player, uid: any): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local index, item = Services.EconomyService.FindProduce(data, uid)
	if not index then
		return false, "NotFound"
	end
	local week = FairMath.weekId(os.time(), Config.Fair)
	local key = tostring(week)
	local current = data.fair.entries[key]
	if current and current.weight >= item.weight then
		return false, "NotHeavier"
	end

	table.remove(data.produce, index)
	if current and current.item then
		-- Give the previous entry back so nothing is lost.
		table.insert(data.produce, current.item)
	end
	data.fair.entries[key] = { weight = item.weight, cropId = item.cropId, item = item }

	submitScore(week, player.UserId, FairMath.weightToScore(item.weight))
	Services.NetService:Feedback(player, Net.Feedback.FairEntered, {
		cropId = item.cropId,
		weight = item.weight,
		replaced = current ~= nil,
	})
	Services.DataService:MarkDirty(player)
	task.defer(self._refreshBoard, self)
	return true, nil
end

function FairService:_claimRewards(player: Player, data: { [string]: any })
	local currentWeek = FairMath.weekId(os.time(), Config.Fair)
	for _, week in FairMath.unclaimedWeeks(data.fair.entries, data.fair.claimed, currentWeek) do
		if not player.Parent then
			return
		end
		local key = tostring(week)
		local rank = rankOf(week, player.UserId)
		local tier = FairMath.tierForRank(rank, Config.Fair.rewardTiers)
		data.fair.claimed[key] = true
		-- The entered crop stays at the fair as a trophy; drop the copy to keep saves small.
		data.fair.entries[key].item = nil
		data.ribbons[tier.ribbon] = (data.ribbons[tier.ribbon] or 0) + 1
		Services.EconomyService:AddCoins(player, tier.coins, "Fair")
		Services.NetService:Feedback(player, Net.Feedback.FairReward, {
			weekId = week,
			rank = rank,
			tier = tier.id,
			coins = tier.coins,
			ribbon = tier.ribbon,
			weight = data.fair.entries[key].weight,
		})
	end
	-- Keep saves small: forget claimed weeks older than two months.
	for key in data.fair.claimed do
		local week = tonumber(key)
		if week and week < currentWeek - 8 then
			data.fair.claimed[key] = nil
			data.fair.entries[key] = nil
		end
	end
	Services.DataService:MarkDirty(player)
end

return FairService
