-- Gemmer og henter spillerdata (Penge, Level, XP) med DataStore.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local store = DataStoreService:GetDataStore("PlayerData_v1")

local DEFAULT = { Penge = 0, Level = 1, XP = 0 }
local AUTOSAVE_INTERVAL = 120

local loaded = {} -- [player] = true når data er hentet korrekt

local function retry(fn)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then return true, result end
		warn("DataStore fejl (forsøg " .. attempt .. "): " .. tostring(result))
		task.wait(attempt)
	end
	return false
end

local function key(player)
	return "Player_" .. player.UserId
end

local function onPlayerAdded(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local values = {}
	for name, default in pairs(DEFAULT) do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Value = default
		values[name] = v
	end
	values.Penge.Parent = leaderstats
	values.Level.Parent = leaderstats
	values.XP.Parent = player -- XP vises ikke på leaderboardet
	leaderstats.Parent = player

	local ok, data = retry(function()
		return store:GetAsync(key(player))
	end)
	if not ok then
		warn("Kunne ikke hente data for " .. player.Name .. ", gemmer ikke for at undgå at overskrive")
		return
	end
	if type(data) == "table" then
		for name, v in pairs(values) do
			if type(data[name]) == "number" then
				v.Value = data[name]
			end
		end
	end
	loaded[player] = true
end

local function save(player)
	if not loaded[player] then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local data = {
		Penge = leaderstats.Penge.Value,
		Level = leaderstats.Level.Value,
		XP = player.XP.Value,
	}
	retry(function()
		store:SetAsync(key(player), data, { player.UserId })
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	loaded[player] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() then task.wait(1) end
	local threads = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(threads, task.spawn(save, p))
	end
	task.wait(2)
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, p in ipairs(Players:GetPlayers()) do
			task.spawn(save, p)
		end
	end
end)
