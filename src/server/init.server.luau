--!strict
--[[
	Server entry point. Loads every service, calls Init on all of them (no
	cross-service calls allowed yet), then Start on all of them.

	Order matters only for Init: NetService must create remotes before clients
	look for them, DataService must pick its store before anything loads.
]]

local Services = script:WaitForChild("Services")

local ORDER = {
	"NetService",
	"DataService",
	"MapService", -- studs on the island in Init, before anything is built on it
	"PlotService",
	"EconomyService",
	"GardenService",
	"ChampionService",
	"ToolService",
	"MailService",
	"RewardService",
	"FairService",
	"FairDayService",
	"MonetizationService",
}

local registry: { [string]: any } = {}
for _, name in ORDER do
	registry[name] = require(Services:WaitForChild(name)) :: any
end

for _, name in ORDER do
	local service = registry[name]
	if service.Init then
		service:Init(registry)
	end
end

-- DataService starts last so every ProfileLoaded listener is connected before
-- the first profile (possibly from the synchronous in-memory store) loads.
for _, name in ORDER do
	local service = registry[name]
	if service.Start and name ~= "DataService" then
		task.spawn(service.Start, service)
	end
end
registry.DataService:Start()

print("[GiantVeggieFair] server started")
