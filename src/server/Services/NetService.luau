--!strict
--[[
	NetService: creates the remotes, routes Request actions to handlers, rate
	limits every player, and pushes state snapshots and feedback events.

	Handlers are registered by other services:
	    NetService:Handle(Net.Actions.BuySeed, function(player, payload) ... end)
	A handler returns (ok, errOrData). Errors become a gentle "Denied" toast on
	the client, never a stack trace.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local NetService = {}

type Handler = (player: Player, payload: { [string]: any }) -> (boolean, any)

local handlers: { [string]: Handler } = {}
local callLog: { [Player]: { [string]: { number } } } = {}
local pendingPush: { [Player]: boolean } = {}
local snapshotBuilders: { (player: Player, snapshot: { [string]: any }) -> () } = {}

local folder: Folder
local remotes: { [string]: Instance } = {}

local function makeRemote(className: string, name: string): Instance
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	remotes[name] = remote
	return remote
end

local function rateLimited(player: Player, action: string): boolean
	local now = os.clock()
	local perPlayer = callLog[player]
	if not perPlayer then
		perPlayer = {}
		callLog[player] = perPlayer
	end
	local calls = perPlayer[action] or {}
	local window = Config.Net.rateLimit.window
	local kept = {}
	for _, t in calls do
		if now - t < window then
			table.insert(kept, t)
		end
	end
	if #kept >= Config.Net.rateLimit.maxCalls then
		perPlayer[action] = kept
		return true
	end
	table.insert(kept, now)
	perPlayer[action] = kept
	return false
end

function NetService:Init()
	folder = Instance.new("Folder")
	folder.Name = Net.FolderName
	makeRemote("RemoteFunction", Net.Remotes.Request)
	makeRemote("RemoteEvent", Net.Remotes.State)
	makeRemote("RemoteEvent", Net.Remotes.Feedback)
	makeRemote("RemoteEvent", Net.Remotes.Leaderboard)
	folder.Parent = ReplicatedStorage
end

function NetService:Start()
	local request = remotes[Net.Remotes.Request] :: RemoteFunction
	request.OnServerInvoke = function(player: Player, action: any, payload: any)
		if type(action) ~= "string" then
			return { ok = false, err = "BadRequest" }
		end
		local handler = handlers[action]
		if not handler then
			return { ok = false, err = "UnknownAction" }
		end
		if payload ~= nil and type(payload) ~= "table" then
			return { ok = false, err = "BadRequest" }
		end
		if rateLimited(player, action) then
			return { ok = false, err = "TooFast" }
		end
		local ok, okOrErr, result = pcall(handler, player, payload or {})
		if not ok then
			warn(string.format("[NetService] %s errored for %s: %s", action, player.Name, tostring(okOrErr)))
			return { ok = false, err = "ServerError" }
		end
		if okOrErr then
			return { ok = true, data = result }
		end
		self:Feedback(player, Net.Feedback.Denied, { action = action, reason = result })
		return { ok = false, err = result }
	end

	Players.PlayerRemoving:Connect(function(player)
		callLog[player] = nil
		pendingPush[player] = nil
	end)
end

function NetService:Handle(action: string, handler: Handler)
	assert(handlers[action] == nil, "Duplicate handler for " .. action)
	handlers[action] = handler
end

-- Services contribute fields to the client snapshot (e.g. computed shop prices).
function NetService:AddSnapshotBuilder(builder: (player: Player, snapshot: { [string]: any }) -> ())
	table.insert(snapshotBuilders, builder)
end

-- Coalesces many changes in one frame into a single snapshot push.
function NetService:PushState(player: Player, data: { [string]: any })
	if pendingPush[player] then
		return
	end
	pendingPush[player] = true
	task.defer(function()
		pendingPush[player] = nil
		if not player.Parent then
			return
		end
		local snapshot = {
			serverTime = os.time(),
			coins = data.coins,
			level = data.level,
			xp = data.xp,
			ownedPlots = data.ownedPlots,
			plots = data.plots,
			seeds = data.seeds,
			selectedSeed = data.selectedSeed,
			produce = data.produce,
			upgrades = data.upgrades,
			fair = data.fair,
			ribbons = data.ribbons,
			stats = data.stats,
		}
		for _, builder in snapshotBuilders do
			builder(player, snapshot)
		end
		(remotes[Net.Remotes.State] :: RemoteEvent):FireClient(player, snapshot)
	end)
end

function NetService:Feedback(player: Player, eventName: string, context: { [string]: any }?)
	(remotes[Net.Remotes.Feedback] :: RemoteEvent):FireClient(player, eventName, context or {})
end

function NetService:Broadcast(remoteName: string, ...: any)
	(remotes[remoteName] :: RemoteEvent):FireAllClients(...)
end

function NetService:FireClient(remoteName: string, player: Player, ...: any)
	(remotes[remoteName] :: RemoteEvent):FireClient(player, ...)
end

return NetService
