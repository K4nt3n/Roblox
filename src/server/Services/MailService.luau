--!strict
--[[
	MailService: deliver coins and ribbons to a player who may be offline or in
	another server (used for co-grower prize shares).

	Mail is appended to a per-player DataStore key and drained into the profile
	the next time that player's profile loads. If the player is in this server
	it is applied right away.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local MailService = {}

export type Mail = { coins: number?, ribbon: string?, note: string, from: number? }

local Services: any
local store: any = nil
local memoryMail: { [string]: { Mail } } = {}

local function keyFor(userId: number): string
	return "mail_" .. userId
end

function MailService:Init(services)
	Services = services
end

function MailService:Start()
	if not Services.DataService:IsUsingMemoryStore() then
		store = DataStoreService:GetDataStore(Config.Data.mailStoreName)
	end
	Services.DataService.ProfileLoaded:Connect(function(player)
		task.spawn(self._drain, self, player)
	end)
end

function MailService:_apply(player: Player, mail: Mail)
	local data = Services.DataService:Get(player)
	if not data then
		return
	end
	if mail.coins and mail.coins > 0 then
		Services.EconomyService:AddCoins(player, mail.coins, "Mail")
	end
	if mail.ribbon then
		data.ribbons[mail.ribbon] = (data.ribbons[mail.ribbon] or 0) + 1
	end
	Services.NetService:Feedback(player, Net.Feedback.MailReceived, mail)
	Services.DataService:MarkDirty(player)
end

function MailService:Send(userId: number, mail: Mail)
	local online = Players:GetPlayerByUserId(userId)
	if online and Services.DataService:Get(online) then
		self:_apply(online, mail)
		return
	end
	local key = keyFor(userId)
	if not store then
		memoryMail[key] = memoryMail[key] or {}
		table.insert(memoryMail[key], mail)
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(list)
			list = list or {}
			table.insert(list, mail)
			while #list > Config.Data.maxMail do
				table.remove(list, 1)
			end
			return list
		end)
	end)
	if not ok then
		warn("[MailService] send failed: " .. tostring(err))
	end
end

function MailService:_drain(player: Player)
	local key = keyFor(player.UserId)
	local list: { Mail } = {}
	if not store then
		list = memoryMail[key] or {}
		memoryMail[key] = nil
	else
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(current)
				list = current or {}
				return {}
			end)
		end)
		if not ok then
			warn("[MailService] drain failed: " .. tostring(err))
			return
		end
	end
	for _, mail in list do
		self:_apply(player, mail)
	end
end

return MailService
