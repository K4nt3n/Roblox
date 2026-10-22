--!strict
--[[
	ClientState: the latest server snapshot plus change signals.
	Read-only for UI. Never mutate `ClientState.data` locally.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local NetClient = require(script.Parent.NetClient)

local ClientState = {}

ClientState.data = nil :: { [string]: any }?
ClientState.leaderboard = nil :: { [string]: any }?
ClientState.Changed = Signal.new() -- (data, previous)
ClientState.LeaderboardChanged = Signal.new() -- (board)
ClientState.Feedback = Signal.new() -- (eventName, context)

-- Server-synced clock. Use this (not os.time) for any growth math on the client.
function ClientState.now(): number
	return workspace:GetServerTimeNow()
end

function ClientState.start()
	NetClient.remote(Net.Remotes.State).OnClientEvent:Connect(function(snapshot)
		local previous = ClientState.data
		ClientState.data = snapshot
		ClientState.Changed:Fire(snapshot, previous)
	end)
	NetClient.remote(Net.Remotes.Leaderboard).OnClientEvent:Connect(function(board)
		ClientState.leaderboard = board
		ClientState.LeaderboardChanged:Fire(board)
	end)
	NetClient.remote(Net.Remotes.Feedback).OnClientEvent:Connect(function(eventName, context)
		ClientState.Feedback:Fire(eventName, context)
	end)
end

return ClientState
