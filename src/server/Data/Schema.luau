--!strict
--[[
	Schema: the shape of a player's saved data, plus defaults, reconcile and
	migrations. Pure (Config is passed in) so it can be unit tested.

	DataStores serialize to JSON, so every map uses string keys (plots are
	"1", "2", ...) and arrays are kept dense.
]]

local Schema = {}

Schema.Version = 1

function Schema.default(config: any): { [string]: any }
	local seeds = {}
	for cropId, count in config.Economy.startingSeeds do
		seeds[cropId] = count
	end
	local supplies = {}
	for supplyId, count in config.Economy.startingSupplies or {} do
		supplies[supplyId] = count
	end
	local upgrades = {}
	for id in config.Upgrades do
		upgrades[id] = 0
	end
	-- Every garden tool starts on the hotbar; Backpack > Supplies takes them off.
	local hotbar = {}
	for id in config.Tools.items do
		hotbar[id] = true
	end
	return {
		version = Schema.Version,
		coins = config.Economy.startingCoins,
		level = 1,
		xp = 0,
		ownedPlots = config.Plots.startingPlots,
		-- plotId (string) -> GrowthMath.Plant
		plots = {},
		-- cropId -> count
		seeds = seeds,
		-- "" = nothing in hand. Cleared on every join, like a normal hotbar.
		selectedSeed = "",
		-- toolId -> whether it sits on the hotbar
		hotbar = hotbar,
		-- supplyId -> count (consumables like fertilizer bags)
		supplies = supplies,
		-- array of { uid, cropId, weight, isGiant, harvestedAt }
		produce = {},
		nextUid = 1,
		upgrades = upgrades,
		fair = {
			-- fair period ("hourly" | "daily" | "weekly") -> period id (string) ->
			--   { weight, cropId, item, ctx = { isFirstTimer, previousBest } }
			entries = { hourly = {}, daily = {}, weekly = {} },
			-- period -> id -> true once rewards were handed out
			claimed = { hourly = {}, daily = {}, weekly = {} },
			-- period -> id -> true when the player watched that fair's live show
			watched = { hourly = {}, daily = {}, weekly = {} },
			-- weekly id (string) -> friend waters given that week (Helpful Neighbor division)
			helper = {},
			-- First week this player ever entered the weekly fair (First-Timer Class). 0 = never.
			firstEntryWeek = 0,
			-- Heaviest weekly entry from finished weeks (Most Improved).
			bestEntryWeight = 0,
		},
		-- weekId (string) -> paid skips used on champions that week (honest shop cap)
		championSkips = {},
		-- ribbon id -> count
		ribbons = {},
		stats = {
			harvested = 0,
			heaviest = 0,
			friendWaters = 0,
			coinsEarned = 0,
		},
		-- Limits on social watering: { day = number, targets = { [userId string] = count } }
		friendWaterLog = { day = 0, targets = {} },
		-- receiptId -> unix time, for idempotent ProcessReceipt.
		purchases = {},
		lastSeenAt = 0,
		firstJoinAt = 0,
	}
end

-- Fills any key missing from `data` with a deep copy of the default. Never removes keys.
function Schema.reconcile(data: { [string]: any }, defaults: { [string]: any }): { [string]: any }
	for key, value in defaults do
		if data[key] == nil then
			data[key] = if type(value) == "table" then Schema.deepCopy(value) else value
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			-- Only recurse into "record" defaults, not empty maps like plots.
			Schema.reconcile(data[key], value)
		end
	end
	return data
end

function Schema.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = Schema.deepCopy(v)
	end
	return out :: any
end

--[[
	Migrations run in order on load. Migrations[n] upgrades data from version
	n - 1 to n. Add a new entry and bump Schema.Version whenever the shape changes.
]]
Schema.Migrations = {
	-- [2] = function(data) data.newField = data.oldField; data.oldField = nil end,
} :: { [number]: (data: { [string]: any }) -> () }

function Schema.migrate(data: { [string]: any }): { [string]: any }
	local version = data.version or 0
	while version < Schema.Version do
		version += 1
		local step = Schema.Migrations[version]
		if step then
			step(data)
		end
		data.version = version
	end
	return data
end

-- Full load pipeline: nil (new player) or stored table -> ready-to-use data.
function Schema.prepare(stored: { [string]: any }?, config: any, now: number): ({ [string]: any }, boolean)
	local isNew = stored == nil
	local data = if stored then Schema.migrate(stored) else Schema.default(config)
	Schema.reconcile(data, Schema.default(config))
	if isNew then
		data.firstJoinAt = now
	end
	return data, isNew
end

return Schema
