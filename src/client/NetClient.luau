--!strict
--[[
	NetClient: thin wrapper over the server's Request remote.
	Returns the server's { ok, err, data } table, never throws.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local NetClient = {}

local folder = ReplicatedStorage:WaitForChild(Net.FolderName)
local request = folder:WaitForChild(Net.Remotes.Request) :: RemoteFunction

NetClient.Actions = Net.Actions

function NetClient.request(action: string, payload: { [string]: any }?): { ok: boolean, err: string?, data: any }
	local ok, result = pcall(function()
		return request:InvokeServer(action, payload)
	end)
	if not ok or type(result) ~= "table" then
		return { ok = false, err = "NetworkError", data = nil }
	end
	return result
end

function NetClient.remote(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return NetClient
