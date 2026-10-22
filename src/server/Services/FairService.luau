--!strict
--[[
	FairService: the Giant Veggie weigh-ins. Three fairs run side by side:
	hourly, daily and weekly (Config.Fair.periods). Each has its own entries,
	global boards, live show (FairDayService) and prizes.

	* A player enters one harvested crop per fair per period. Entering a
	  heavier crop replaces the old entry and the old crop goes back to the
	  basket. A crop can only be in one fair.
	* Ribbons for everyone: entries compete in several divisions (overall,
	  best per veggie type, and on the weekly fair also first-timer, most
	  improved, natural grown, team grown and the Helpful Neighbor division for
	  friend waters). Each division has its own OrderedDataStore board.
	* Rewards are claimed right after a live show, or on the next join for
	  anyone who missed it (shown as a replay card). Co-growers of a team
	  champion get a share of its prizes by mail.
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
local PERIODS = Config.Fair.periods
local nameCache: { [number]: string } = {}
local latestBoards: { [string]: { any } } = {}
local helperDirty: { [Player]: boolean } = {}
local claiming: { [Player]: boolean } = {}

-- In-memory fallback: boardKey -> { [userId]: score }
local memoryBoards: { [string]: { [number]: number } } = {}

local function useMemory(): boolean
	return Services.DataService:IsUsingMemoryStore()
end

local function boardKey(periodName: string, id: number, division: string): string
	return Config.Data.fairStorePrefix .. periodName .. "_" .. id .. "_" .. division
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
FairService.DisplayName = displayName

function FairService.NamesOf(userIds: { number }): { string }
	local names = {}
	for _, userId in userIds do
		table.insert(names, displayName(userId))
	end
	return names
end

-- Keeps the higher of the stored and new score.
local function submitScore(periodName: string, id: number, division: string, userId: number, score: number)
	local key = boardKey(periodName, id, division)
	if useMemory() then
		local board = memoryBoards[key] or {}
		memoryBoards[key] = board
		board[userId] = math.max(board[userId] or 0, score)
		return
	end
	local ok, err = pcall(function()
		DataStoreService:GetOrderedDataStore(key):UpdateAsync(tostring(userId), function(old)
			return math.max(old or 0, score)
		end)
	end)
	if not ok then
		warn("[FairService] submit failed: " .. tostring(err))
	end
end

-- Returns { { userId, score } } sorted descending, up to `limit`.
local function topScores(periodName: string, id: number, division: string, limit: number): { { userId: number, score: number } }
	local rows = {}
	if limit <= 0 then
		return rows
	end
	local key = boardKey(periodName, id, division)
	if useMemory() then
		for userId, score in memoryBoards[key] or {} do
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
		local pages = DataStoreService:GetOrderedDataStore(key):GetSortedAsync(false, math.min(limit, 100))
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

local function rankOf(periodName: string, id: number, division: string, userId: number, tiers: { any }): number?
	for index, row in topScores(periodName, id, division, FairMath.deepestRank(tiers)) do
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
		return self:Enter(player, payload.uid, payload.fair)
	end)

	Services.DataService.ProfileLoaded:Connect(function(player, data)
		-- Don't hand out results mid-show; FairDayService claims for everyone when it ends.
		if not Services.FairDayService:IsShowRunning() then
			task.spawn(self.ClaimRewards, self, player, data)
		end
		Services.NetService:FireClient(Net.Remotes.Leaderboard, player, self:_boardPayload())
	end)

	Services.DataService.ProfileReleasing:Connect(function(player)
		self:_flushHelper(player)
		helperDirty[player] = nil
		claiming[player] = nil
	end)

	Services.NetService:AddSnapshotBuilder(function(_player, snapshot)
		local now = os.time()
		local fairs = {}
		for name, period in PERIODS do
			local id = FairMath.periodId(now, period)
			fairs[name] = { id = id, endsAt = FairMath.periodEndsAt(id, period) }
		end
		snapshot.fairs = fairs
	end)

	task.spawn(function()
		while true do
			self:_refreshBoards()
			task.wait(Config.Fair.leaderboardRefreshSeconds)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Fair.helperFlushSeconds)
			for player in helperDirty do
				self:_flushHelper(player)
			end
		end
	end)
end

function FairService:MarkHelperDirty(player: Player)
	helperDirty[player] = true
end

function FairService:_flushHelper(player: Player)
	if not helperDirty[player] then
		return
	end
	helperDirty[player] = nil
	local data = Services.DataService:Get(player)
	if not data then
		return
	end
	local week = FairMath.periodId(os.time(), PERIODS.weekly)
	local count = data.fair.helper[tostring(week)]
	if count and count > 0 then
		submitScore("weekly", week, "helper", player.UserId, count)
	end
end

function FairService:BoardRows(periodName: string, id: number, limit: number): { any }
	local rows = {}
	for index, row in topScores(periodName, id, "overall", limit) do
		table.insert(rows, {
			rank = index,
			userId = row.userId,
			name = displayName(row.userId),
			weight = FairMath.scoreToWeight(row.score),
		})
	end
	return rows
end

function FairService:_boardPayload()
	local now = os.time()
	local fairs = {}
	for name, period in PERIODS do
		local id = FairMath.periodId(now, period)
		fairs[name] = { id = id, endsAt = FairMath.periodEndsAt(id, period), rows = latestBoards[name] or {} }
	end
	return { fairs = fairs }
end

function FairService:_refreshBoards()
	local now = os.time()
	for name, period in PERIODS do
		latestBoards[name] = self:BoardRows(name, FairMath.periodId(now, period), Config.Fair.leaderboardSize)
	end
	Services.NetService:Broadcast(Net.Remotes.Leaderboard, self:_boardPayload())
end

-- Heaviest weekly entry from any week before `week` (for Most Improved).
local function previousBest(data: { [string]: any }, week: number): number
	local best = data.fair.bestEntryWeight or 0
	for key, entry in data.fair.entries.weekly do
		local id = tonumber(key)
		if id and id < week and entry.weight > best then
			best = entry.weight
		end
	end
	return best
end

function FairService:Enter(player: Player, uid: any, fairName: any): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local period = type(fairName) == "string" and PERIODS[fairName]
	if not period then
		return false, "UnknownFair"
	end
	if Services.FairDayService:IsShowRunningFor(fairName) then
		return false, "ShowRunning"
	end
	local index, item = Services.EconomyService.FindProduce(data, uid)
	if not index then
		return false, "NotFound"
	end
	local id = FairMath.periodId(os.time(), period)
	local key = tostring(id)
	local entries = data.fair.entries[fairName]
	local current = entries[key]
	if current and current.weight >= item.weight then
		return false, "NotHeavier"
	end

	table.remove(data.produce, index)
	if current and current.item then
		-- Give the previous entry back so nothing is lost.
		table.insert(data.produce, current.item)
	end
	local ctx = {}
	if fairName == "weekly" then
		if (data.fair.firstEntryWeek or 0) == 0 then
			data.fair.firstEntryWeek = id
		end
		ctx.isFirstTimer = data.fair.firstEntryWeek == id
		ctx.previousBest = previousBest(data, id)
	end
	entries[key] = { weight = item.weight, cropId = item.cropId, item = item, ctx = ctx }

	local divisions = FairMath.divisionsForEntry(item, ctx, period.divisions)
	local names = {}
	for _, division in divisions do
		submitScore(fairName, id, division.id, player.UserId, division.score)
		table.insert(names, FairMath.divisionName(division.id, Config.Fair.divisions, Config.Crops))
	end
	Services.NetService:Feedback(player, Net.Feedback.FairEntered, {
		fair = fairName,
		fairName = period.displayName,
		cropId = item.cropId,
		weight = item.weight,
		replaced = current ~= nil,
		divisions = names,
	})
	Services.DataService:MarkDirty(player)
	task.defer(self._refreshBoards, self)
	return true, nil
end

-- Results for one finished period: a list of { division, name, rank, tier }.
function FairService:_resultsFor(player: Player, data: { [string]: any }, fairName: string, id: number): { any }
	local period = PERIODS[fairName]
	local key = tostring(id)
	local results = {}
	local function judge(divisionId: string, tiers: { any })
		local rank = rankOf(fairName, id, divisionId, player.UserId, tiers)
		local tier = FairMath.tierForRank(rank, tiers)
		if tier then
			table.insert(results, {
				division = divisionId,
				name = FairMath.divisionName(divisionId, Config.Fair.divisions, Config.Crops),
				rank = rank,
				tier = tier,
			})
		end
	end
	local entry = data.fair.entries[fairName][key]
	if entry and entry.item then
		-- Only divisions the final entry qualifies for (a replaced entry can't win twice).
		for _, division in FairMath.divisionsForEntry(entry.item, entry.ctx or {}, period.divisions) do
			judge(division.id, if division.id == "overall" then Config.Fair.rewardTiers else Config.Fair.divisionTiers)
		end
	end
	if fairName == "weekly" and (data.fair.helper[key] or 0) > 0 then
		judge("helper", Config.Fair.divisionTiers)
	end
	return results
end

function FairService:_claimOne(player: Player, data: { [string]: any }, fairName: string, id: number)
	local period = PERIODS[fairName]
	local key = tostring(id)
	local entry = data.fair.entries[fairName][key]
	local results = self:_resultsFor(player, data, fairName, id)
	data.fair.claimed[fairName][key] = true

	local totalCoins, ribbons = 0, {}
	for _, result in results do
		local ribbon = FairMath.ribbonId(fairName, result.tier.ribbon, result.division)
		data.ribbons[ribbon] = (data.ribbons[ribbon] or 0) + 1
		totalCoins += math.floor(result.tier.coins * period.rewardScale)
		table.insert(ribbons, { ribbon = ribbon, division = result.name, rank = result.rank, tier = result.tier.id })
	end
	Services.EconomyService:AddCoins(player, totalCoins, "Fair")

	-- Team champion: every co-grower gets a share of the prizes and a team ribbon.
	local item = entry and entry.item
	if item and item.coGrowers and #item.coGrowers > 0 and totalCoins > 0 then
		for _, userId in item.coGrowers do
			Services.MailService:Send(userId, {
				coins = math.floor(totalCoins * Config.Champion.coGrowerShare),
				ribbon = FairMath.ribbonId(fairName, "Team", ribbons[1] and ribbons[1].tier or "entrant"),
				note = string.format("Your team champion with %s won at the %s!", player.DisplayName, period.displayName),
				from = player.UserId,
			})
		end
	end

	if entry then
		if fairName == "weekly" then
			data.fair.bestEntryWeight = math.max(data.fair.bestEntryWeight or 0, entry.weight)
		end
		-- The entered crop stays at the fair as a trophy; drop the copy to keep saves small.
		entry.item = nil
	end
	-- Hourly fairs with no prize don't need a card.
	if totalCoins == 0 and fairName == "hourly" then
		return
	end
	Services.NetService:Feedback(player, Net.Feedback.FairReward, {
		fair = fairName,
		fairName = period.displayName,
		periodId = id,
		coins = totalCoins,
		ribbons = ribbons,
		weight = entry and entry.weight,
		cropId = entry and entry.cropId,
		championName = item and item.name,
		coGrowerNames = if item and item.coGrowers then FairService.NamesOf(item.coGrowers) else nil,
		-- Missed the live show: the client shows this as a replay card.
		missedShow = not data.fair.watched[fairName][key],
	})
end

function FairService:ClaimRewards(player: Player, data: { [string]: any })
	if claiming[player] then
		return
	end
	claiming[player] = true
	local now = os.time()
	for _, period in FairMath.sortedPeriods(PERIODS) do
		local fairName = period.id
		local currentId = FairMath.periodId(now, period)
		local extra = if fairName == "weekly" then data.fair.helper else {}
		for _, id in FairMath.unclaimedPeriods(data.fair.entries[fairName], data.fair.claimed[fairName], currentId, extra) do
			if not player.Parent then
				break
			end
			self:_claimOne(player, data, fairName, id)
		end
		-- Keep saves small: forget claimed periods once they are old.
		local keep = if fairName == "weekly" then 8 elseif fairName == "daily" then 14 else 24
		for key in data.fair.claimed[fairName] do
			local id = tonumber(key)
			if id and id < currentId - keep then
				data.fair.claimed[fairName][key] = nil
				data.fair.entries[fairName][key] = nil
				data.fair.watched[fairName][key] = nil
				if fairName == "weekly" then
					data.fair.helper[key] = nil
				end
			end
		end
	end
	claiming[player] = nil
	Services.DataService:MarkDirty(player)
end

return FairService
