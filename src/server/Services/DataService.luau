--!strict
--[[
	DataService: loads, caches and saves each player's profile.

	* UpdateAsync with a session lock so two servers never write the same profile.
	* Retries with backoff on DataStore errors.
	* Falls back to an in-memory store when DataStores are unavailable (e.g. a
	  Studio place without API access), so the game is always playable.
	* Autosaves, saves on leave and on server shutdown.

	Other services read and mutate `DataService:Get(player)` directly, then call
	`DataService:MarkDirty(player)`, which also pushes a fresh state snapshot.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local Schema = require(script.Parent.Parent.Data.Schema)

local DataService = {}

DataService.ProfileLoaded = Signal.new() -- (player, data, info: { isNew, offlineSeconds })
DataService.ProfileReleasing = Signal.new() -- (player, data)
DataService.Dirty = Signal.new() -- (player)

local profiles: { [Player]: { [string]: any } } = {}
local loading: { [Player]: boolean } = {}

-- In-memory fallback store shared by every "server" in this Studio session.
local memoryStore: { [string]: any } = {}
local store: any = nil
local useMemory = false

local function keyFor(userId: number): string
	return "player_" .. userId
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T | string)
	local lastErr
	for attempt = 1, Config.Data.maxLoadRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[DataService] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		task.wait(math.min(2 ^ attempt, 16))
	end
	return false, tostring(lastErr)
end

local function update(key: string, transform: (any) -> any): (boolean, any)
	if useMemory then
		local result = transform(Schema.deepCopy(memoryStore[key]))
		if result ~= nil then
			memoryStore[key] = Schema.deepCopy(result)
		end
		return true, result
	end
	return withRetries("UpdateAsync " .. key, function()
		return store:UpdateAsync(key, transform)
	end)
end

local function lockId(): string
	return game.JobId ~= "" and game.JobId or "studio"
end

function DataService:Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.storeName)
	end)
	if ok then
		store = result
		-- GetDataStore succeeds offline in Studio; a probe read tells us if API access works.
		local probeOk = pcall(function()
			store:GetAsync("__probe")
		end)
		useMemory = not probeOk
	else
		useMemory = true
	end
	if useMemory then
		warn("[DataService] DataStores unavailable, using in-memory store. Progress will not persist.")
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._load, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:_release(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.autosaveSeconds)
			for player in profiles do
				task.spawn(self._save, self, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				self:_save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function DataService:IsUsingMemoryStore(): boolean
	return useMemory
end

function DataService:Get(player: Player): { [string]: any }?
	return profiles[player]
end

-- Yields until the profile is loaded or the player leaves.
function DataService:WaitFor(player: Player): { [string]: any }?
	while not profiles[player] and player.Parent do
		task.wait()
	end
	return profiles[player]
end

function DataService:MarkDirty(player: Player)
	if profiles[player] then
		self.Dirty:Fire(player)
	end
end

function DataService:_load(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	local now = os.time()
	local stored: any = nil
	local ok, blocked = false, false

	-- If another server still holds the lock (player hopped servers quickly), wait for it to release.
	for _ = 1, 6 do
		blocked = false
		ok = update(keyFor(player.UserId), function(current)
			now = os.time()
			if current and current.lock and current.lock.id ~= lockId() then
				if now - (current.lock.at or 0) < Config.Data.sessionLockSeconds then
					blocked = true
					return nil
				end
			end
			stored = if current then current.data else nil
			return { data = stored, lock = { id = lockId(), at = now } }
		end)
		if not ok or not blocked or not player.Parent then
			break
		end
		task.wait(5)
	end

	loading[player] = nil
	if not ok or blocked then
		player:Kick("We couldn't load your garden. Please rejoin in a moment!")
		return
	end
	if not player.Parent then
		return
	end

	local data, isNew = Schema.prepare(stored, Config, now)
	local offlineSeconds = if data.lastSeenAt > 0 then now - data.lastSeenAt else 0
	data.lastSeenAt = now
	profiles[player] = data
	self.ProfileLoaded:Fire(player, data, { isNew = isNew, offlineSeconds = offlineSeconds })
	self:MarkDirty(player)
end

function DataService:_save(player: Player, release: boolean)
	local data = profiles[player]
	if not data then
		return
	end
	data.lastSeenAt = os.time()
	local snapshot = Schema.deepCopy(data)
	update(keyFor(player.UserId), function(current)
		if current and current.lock and current.lock.id ~= lockId() then
			-- We lost the lock (e.g. stale-lock takeover elsewhere). Don't overwrite.
			return nil
		end
		return {
			data = snapshot,
			lock = if release then nil else { id = lockId(), at = os.time() },
		}
	end)
end

function DataService:_release(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	self.ProfileReleasing:Fire(player, data)
	self:_save(player, true)
	profiles[player] = nil
end

-- Studio helper: wipe a player's data (call from the command bar).
function DataService:DebugReset(player: Player)
	if not RunService:IsStudio() then
		return
	end
	local data = Schema.default(Config)
	data.firstJoinAt = os.time()
	profiles[player] = data
	self:MarkDirty(player)
end

return DataService
