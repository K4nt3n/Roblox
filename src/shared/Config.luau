--!strict
--[[
	Config: every gameplay tunable lives here.

	Rules:
	  * Pure data only. No requires, no Roblox services, so tests can load it.
	  * Times are in seconds, weights in kilograms, prices in Coins.
	  * Changing a crop id or upgrade id breaks saved data; add new ones instead.
]]

local MINUTE = 60
local HOUR = 60 * MINUTE

export type CropDef = {
	id: string,
	displayName: string,
	seedCost: number,
	-- Seconds from planting until the crop is Ripe and can be harvested.
	growSeconds: number,
	-- Extra seconds after Ripe during which it keeps swelling toward Giant size.
	giantSeconds: number,
	-- Weight when Ripe (before variance, water and upgrades).
	ripeWeight: number,
	-- Weight multiplier reached at the end of giantSeconds (1.0 = no extra growth).
	giantMultiplier: number,
	-- +/- fraction of random size variance rolled once at planting.
	variance: number,
	sellPricePerKg: number,
	unlockLevel: number,
	-- Placeholder look used until real art is dropped into ReplicatedStorage.Assets.Crops.
	placeholderColor: { number },
	order: number,
}

export type UpgradeDef = {
	id: string,
	displayName: string,
	description: string,
	-- costs[n] is the price to buy level n. Max level is #costs.
	costs: { number },
	-- values[n + 1] is the effect at level n (values[1] is level 0).
	values: { number },
}

local Config = {}

Config.Version = 1

Config.Crops = {
	carrot = {
		id = "carrot",
		displayName = "Carrot",
		seedCost = 0,
		growSeconds = 2 * MINUTE,
		giantSeconds = 10 * MINUTE,
		ripeWeight = 0.4,
		giantMultiplier = 3,
		variance = 0.15,
		sellPricePerKg = 25,
		unlockLevel = 1,
		placeholderColor = { 255, 145, 60 },
		order = 1,
	},
	tomato = {
		id = "tomato",
		displayName = "Tomato",
		seedCost = 25,
		growSeconds = 10 * MINUTE,
		giantSeconds = 1 * HOUR,
		ripeWeight = 0.8,
		giantMultiplier = 3.5,
		variance = 0.2,
		sellPricePerKg = 40,
		unlockLevel = 1,
		placeholderColor = { 235, 70, 60 },
		order = 2,
	},
	cabbage = {
		id = "cabbage",
		displayName = "Cabbage",
		seedCost = 120,
		growSeconds = 45 * MINUTE,
		giantSeconds = 4 * HOUR,
		ripeWeight = 3,
		giantMultiplier = 4,
		variance = 0.2,
		sellPricePerKg = 30,
		unlockLevel = 3,
		placeholderColor = { 140, 210, 110 },
		order = 3,
	},
	pumpkin = {
		id = "pumpkin",
		displayName = "Pumpkin",
		seedCost = 500,
		growSeconds = 3 * HOUR,
		giantSeconds = 12 * HOUR,
		ripeWeight = 9,
		giantMultiplier = 6,
		variance = 0.25,
		sellPricePerKg = 22,
		unlockLevel = 5,
		placeholderColor = { 255, 165, 40 },
		order = 4,
	},
	watermelon = {
		id = "watermelon",
		displayName = "Watermelon",
		seedCost = 2000,
		growSeconds = 8 * HOUR,
		giantSeconds = 24 * HOUR,
		ripeWeight = 14,
		giantMultiplier = 7,
		variance = 0.3,
		sellPricePerKg = 25,
		unlockLevel = 8,
		placeholderColor = { 70, 170, 90 },
		order = 5,
	},
} :: { [string]: CropDef }

Config.Growth = {
	-- Fraction of growSeconds where each visual stage begins. Ripe is always 1.0.
	stageThresholds = {
		Seed = 0,
		Sprout = 0.15,
		Growing = 0.45,
		Ripe = 1,
	},
	-- Chance that a planted seed is a "Giant gene" seed, and the extra multiplier it gets.
	baseGiantGeneChance = 0.05,
	giantGeneMultiplier = 1.6,
	-- Weight curve exponent while growing to Ripe (higher = slow start, fast finish).
	ripeCurveExponent = 1.6,
	-- Fraction of giantSeconds after Ripe where the crop counts as a Giant.
	giantStageAt = 0.5,
}

Config.Watering = {
	-- Seconds a single plant must wait between waterings (any waterer).
	plantCooldownSeconds = 5 * MINUTE,
	-- A watering skips this fraction of the crop's growSeconds...
	boostFraction = 0.06,
	-- ...but never less/more than these.
	minBoostSeconds = 10,
	maxBoostSeconds = 30 * MINUTE,
	-- Each watering also adds permanent weight; capped per plant.
	weightBonusPerWater = 0.02,
	maxWaterBonusCount = 10,
	-- Social watering.
	friendRewardCoins = 5,
	friendWatersPerTargetPerDay = 10,
	-- Only Roblox friends can water each other when true. False = anyone in the server.
	requireFriendship = false,
}

Config.Plots = {
	startingPlots = 3,
	maxPlots = 12,
	-- Cost of plot number n (index n - startingPlots).
	plotCosts = { 150, 400, 900, 2000, 4000, 8000, 15000, 25000, 40000 },
}

Config.Economy = {
	startingCoins = 50,
	startingSeeds = { carrot = 3 },
	maxProduceInventory = 60,
	-- Bonus multiplier on sale price for crops that reached Giant stage.
	giantSellBonus = 1.25,
}

Config.Upgrades = {
	wateringCan = {
		id = "wateringCan",
		displayName = "Watering Can",
		description = "Each watering speeds growth more.",
		costs = { 200, 800, 3000, 10000 },
		values = { 1, 1.25, 1.5, 1.8, 2.2 },
	},
	fertilizer = {
		id = "fertilizer",
		displayName = "Fertilizer",
		description = "All crops grow faster.",
		costs = { 300, 1200, 5000, 18000 },
		values = { 1, 1.1, 1.2, 1.35, 1.5 },
	},
	greenThumb = {
		id = "greenThumb",
		displayName = "Green Thumb",
		description = "Higher chance of Giant gene seeds.",
		costs = { 500, 2500, 9000 },
		values = { 1, 1.5, 2, 3 },
	},
	marketStall = {
		id = "marketStall",
		displayName = "Market Stall",
		description = "Sell produce for more Coins.",
		costs = { 400, 1600, 6000, 20000 },
		values = { 1, 1.15, 1.3, 1.5, 1.75 },
	},
} :: { [string]: UpgradeDef }

Config.Levels = {
	-- XP needed to reach level n + 1 from level n is xpBase * n ^ xpExponent.
	xpBase = 50,
	xpExponent = 1.4,
	xpPerKgHarvested = 10,
	xpPerHarvest = 5,
	xpPerFriendWater = 3,
	maxLevel = 50,
}

local FAIR_ANCHOR = 1704560400 -- Saturday 6 Jan 2024, 17:00 UTC

Config.Fair = {
	-- The weekly fair rolls over at this Unix time offset (Saturday 17:00 UTC).
	weekAnchorUnix = FAIR_ANCHOR,
	weekSeconds = 7 * 24 * HOUR,

	--[[
		Three fairs run side by side. Each has its own entries, global boards,
		live show and prizes. A crop can only be entered in one of them.
		  divisions:  which divisions this fair judges (see `divisions` below)
		  rewardScale: multiplier on coin prizes
		  show:       timings for the live show (FairDayService)
		The hourly fair rolls over at half past so it never collides with the
		daily/weekly rollover. When daily and weekly roll over together
		(Saturdays), the weekly show runs and daily results arrive as a card.
	]]
	periods = {
		hourly = {
			id = "hourly",
			displayName = "Hourly Fair",
			order = 1,
			seconds = HOUR,
			anchorUnix = FAIR_ANCHOR + 30 * MINUTE,
			divisions = { "overall" },
			rewardScale = 0.1,
			show = {
				announceSeconds = 60,
				liveWindowSeconds = 2 * MINUTE,
				gatherSeconds = 5,
				weighSecondsPerEntry = 3,
				maxStageEntries = 5,
				awardsSeconds = 8,
				globalSeconds = 5,
				emptySeconds = 4,
				prizeScale = 0.15,
			},
		},
		daily = {
			id = "daily",
			displayName = "Daily Fair",
			order = 2,
			seconds = 24 * HOUR,
			anchorUnix = FAIR_ANCHOR,
			divisions = { "overall", "crop" },
			rewardScale = 0.35,
			show = {
				announceSeconds = 3 * MINUTE,
				liveWindowSeconds = 4 * MINUTE,
				gatherSeconds = 8,
				weighSecondsPerEntry = 4,
				maxStageEntries = 8,
				awardsSeconds = 12,
				globalSeconds = 8,
				emptySeconds = 5,
				prizeScale = 0.4,
			},
		},
		weekly = {
			id = "weekly",
			displayName = "Weekly Grand Fair",
			order = 3,
			seconds = 7 * 24 * HOUR,
			anchorUnix = FAIR_ANCHOR,
			divisions = { "overall", "crop", "firstTimer", "improved", "natural", "team", "helper" },
			rewardScale = 1,
			show = {
				announceSeconds = 5 * MINUTE,
				liveWindowSeconds = 5 * MINUTE,
				gatherSeconds = 12,
				weighSecondsPerEntry = 6,
				maxStageEntries = 12,
				awardsSeconds = 16,
				globalSeconds = 12,
				emptySeconds = 6,
				prizeScale = 1,
			},
		},
	},
	-- Tier rewards claimed the next time the player joins after the week ends.
	-- Ranks come from the global OrderedDataStore; topN is inclusive.
	rewardTiers = {
		{ id = "blue", topN = 10, coins = 25000, ribbon = "BlueRibbon" },
		{ id = "red", topN = 100, coins = 8000, ribbon = "RedRibbon" },
		{ id = "yellow", topN = 1000, coins = 2500, ribbon = "YellowRibbon" },
		{ id = "entrant", topN = math.huge, coins = 500, ribbon = "EntrantRosette" },
	},
	leaderboardSize = 10,
	leaderboardRefreshSeconds = 60,

	-- "Ribbons for everyone": extra divisions so lots of kids win something each week.
	-- Each division has its own global OrderedDataStore board. "overall" uses rewardTiers above.
	divisionTiers = {
		{ id = "blue", topN = 1, coins = 3000, ribbon = "Blue" },
		{ id = "red", topN = 3, coins = 1500, ribbon = "Red" },
		{ id = "yellow", topN = 10, coins = 800, ribbon = "Yellow" },
	},
	divisions = {
		overall = { displayName = "Heaviest Overall" },
		crop = { displayName = "Best %s" }, -- one board per crop type, e.g. crop_pumpkin
		firstTimer = { displayName = "First-Timer Class" },
		improved = { displayName = "Most Improved" },
		natural = { displayName = "Natural Grown" }, -- champions with zero paid skips
		team = { displayName = "Team Grown" }, -- champions grown with co-growers
		helper = { displayName = "Helpful Neighbor" }, -- most friend waters this week, no entry needed
		server = { displayName = "Live Show Podium" }, -- top three in your server at the live show
	},
	-- Helper scores are flushed to the board at most this often per player.
	helperFlushSeconds = 60,
}

Config.FairDay = {
	-- Shared settings for the live shows. Per-fair timings live in Config.Fair.periods[*].show.
	-- Prizes for the top three entries in this server, scaled by each fair's show.prizeScale.
	serverPrizes = {
		{ coins = 1500, ribbon = "Blue" },
		{ coins = 800, ribbon = "Red" },
		{ coins = 400, ribbon = "Yellow" },
	},
	stagePosition = { 0, 0, -75 },
}

Config.Champion = {
	-- One special plot per player for the veggie they raise all week.
	plotId = "C",
	-- The champion keeps swelling for at least this long after it ripens...
	minGiantSeconds = 5 * 24 * HOUR,
	-- ...and can get this much bigger than a normal crop of the same type.
	giantMultiplierBonus = 1.5,
	-- Care needs (water, pests, propping up) appear every interval. Handling one adds weight.
	maxCareEvents = 14,
	minCareIntervalSeconds = 60,
	maxCareIntervalSeconds = 8 * HOUR,
	-- Shorter interval in Studio so care can be tested quickly.
	studioCareIntervalSeconds = 45,
	-- Handled within this fraction of the interval = full credit; later = lateCredit.
	onTimeFraction = 0.5,
	lateCredit = 0.5,
	-- A need left unhandled for this many intervals expires (no penalty, just no bonus).
	needExpiresAfterIntervals = 2,
	-- Weight bonus per care point. Full care (14 points) beats the Giant gene on purpose.
	careBonusPerPoint = 0.08,
	xpPerCare = 8,
	maxNameLength = 20,
	-- Grow together: friends who co-grow your champion.
	maxCoGrowers = 2,
	coGrowRequiresFriendship = true,
	inviteExpiresSeconds = 120,
	-- Share of the owner's fair prize each co-grower gets by mail.
	coGrowerShare = 0.5,
}

Config.Monetization = {
	-- Coins given instead if a Skip is bought while nothing is growing.
	skipRefundCoins = 500,
	-- Honest shop: paid skips on the champion are capped per fair week, and any paid skip
	-- makes that champion ineligible for the Natural Grown division.
	championSkipsPerWeek = 1,
	-- Game passes (convenience, never power in the fair). 0 = not created yet.
	Passes = {
		ExtraPlotRow = { passId = 0 },
		SeasonFairPass = { passId = 0 },
	},
	-- Set real ids from the Creator Dashboard. 0 = stub (simulated purchases allowed in Studio only).
	Products = {
		SkipGrowth = { productId = 0, kind = "SkipGrowth" },
		CoinsSmall = { productId = 0, kind = "Coins", amount = 1000 },
	},
}

Config.Data = {
	storeName = "GVF_PlayerData_v1",
	fairStorePrefix = "GVF_Fair_v2_",
	mailStoreName = "GVF_Mail_v1",
	maxMail = 50,
	autosaveSeconds = 120,
	sessionLockSeconds = 30 * MINUTE,
	maxLoadRetries = 5,
	maxPurchaseHistory = 50,
}

Config.World = {
	-- Placeholder layout used when the map has no Workspace.GardenSlots folder.
	-- Peter's map can provide GardenSlots/<n> parts (any size) to position gardens instead.
	gardenSlots = 8,
	gardenSpacing = 64,
	plotsPerRow = 4,
	plotSize = 8,
	plotGap = 3,
	promptDistance = 10,
	-- Placeholder palette (soft, saturated, kid friendly). Art replaces these later.
	colors = {
		soil = { 120, 85, 60 },
		soilWet = { 85, 60, 45 },
		lockedPlot = { 200, 200, 200 },
		garden = { 125, 200, 105 },
		stand = { 255, 220, 120 },
	},
	-- Interaction stands. `panel` is the client UI panel the prompt opens.
	stands = {
		{ name = "SeedShop", panel = "Shop", label = "Seed Shop", position = { -30, 0, -30 } },
		{ name = "Market", panel = "Market", label = "Market", position = { 0, 0, -30 } },
		{ name = "FairStand", panel = "Fair", label = "Weigh-In Fair", position = { 30, 0, -30 } },
	},
}

Config.Net = {
	-- Max requests per action per player inside the window.
	rateLimit = { window = 2, maxCalls = 8 },
}

return Config
