--!strict
--[[
	EconomyService: coins, XP/levels, the seed shop, upgrades, plot purchases
	and selling produce. All prices come from Config via EconomyMath.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local EconomyMath = require(Shared.EconomyMath)

local EconomyService = {}

local Services: any

function EconomyService:Init(services)
	Services = services
end

function EconomyService:Start()
	local NetService = Services.NetService

	NetService:Handle(Net.Actions.BuySeed, function(player, payload)
		return self:BuySeed(player, payload.cropId, payload.amount)
	end)
	NetService:Handle(Net.Actions.BuyUpgrade, function(player, payload)
		return self:BuyUpgrade(player, payload.upgradeId)
	end)
	NetService:Handle(Net.Actions.BuyPlot, function(player)
		return self:BuyPlot(player)
	end)
	NetService:Handle(Net.Actions.SellProduce, function(player, payload)
		return self:SellProduce(player, payload.uid)
	end)
	NetService:Handle(Net.Actions.SellAll, function(player)
		return self:SellAll(player)
	end)

	-- Computed values the UI needs, so the client never duplicates pricing rules.
	NetService:AddSnapshotBuilder(function(player, snapshot)
		local data = Services.DataService:Get(player)
		if not data then
			return
		end
		local upgradeInfo = {}
		for id, def in Config.Upgrades do
			local level = data.upgrades[id] or 0
			upgradeInfo[id] = {
				level = level,
				maxLevel = EconomyMath.maxUpgradeLevel(def),
				nextCost = EconomyMath.upgradeCost(def, level),
				value = EconomyMath.upgradeValue(def, level),
			}
		end
		snapshot.upgradeInfo = upgradeInfo
		snapshot.nextPlotCost = EconomyMath.nextPlotCost(data.ownedPlots, Config.Plots)
		snapshot.xpToNext = EconomyMath.xpToNext(data.level, Config.Levels)
		local sellMult = self:GetUpgradeValue(player, "marketStall")
		local prices = {}
		for _, item in data.produce do
			local crop = Config.Crops[item.cropId]
			if crop then
				-- String keys: sparse number keys don't survive RemoteEvent serialization.
				prices[tostring(item.uid)] = EconomyMath.salePrice(item.weight, crop, item.isGiant, sellMult, Config.Economy)
			end
		end
		snapshot.producePrices = prices
	end)
end

function EconomyService:GetUpgradeValue(player: Player, upgradeId: string): number
	local data = Services.DataService:Get(player)
	local def = Config.Upgrades[upgradeId]
	if not data or not def then
		return 1
	end
	return EconomyMath.upgradeValue(def, data.upgrades[upgradeId] or 0)
end

function EconomyService:AddCoins(player: Player, amount: number, source: string?)
	local data = Services.DataService:Get(player)
	if not data or amount == 0 then
		return
	end
	data.coins = math.max(0, data.coins + math.floor(amount))
	if amount > 0 then
		data.stats.coinsEarned += math.floor(amount)
	end
	Services.DataService:MarkDirty(player)
end

function EconomyService:TrySpend(player: Player, amount: number): boolean
	local data = Services.DataService:Get(player)
	if not data or amount < 0 or data.coins < amount then
		return false
	end
	data.coins -= amount
	Services.DataService:MarkDirty(player)
	return true
end

function EconomyService:AddXp(player: Player, amount: number)
	local data = Services.DataService:Get(player)
	if not data or amount <= 0 then
		return
	end
	local level, xp, gained = EconomyMath.addXp(data.level, data.xp, amount, Config.Levels)
	data.level, data.xp = level, xp
	if gained > 0 then
		Services.NetService:Feedback(player, Net.Feedback.LevelUp, { level = level })
	end
	Services.DataService:MarkDirty(player)
end

function EconomyService:BuySeed(player: Player, cropId: any, amount: any): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local crop = type(cropId) == "string" and Config.Crops[cropId]
	if not crop then
		return false, "UnknownCrop"
	end
	local count = if type(amount) == "number" then math.clamp(math.floor(amount), 1, 99) else 1
	if data.level < crop.unlockLevel then
		return false, "LevelLocked"
	end
	local cost = crop.seedCost * count
	if not self:TrySpend(player, cost) then
		return false, "NotEnoughCoins"
	end
	data.seeds[cropId] = (data.seeds[cropId] or 0) + count
	Services.NetService:Feedback(player, Net.Feedback.Purchased, { kind = "Seed", cropId = cropId, amount = count })
	Services.DataService:MarkDirty(player)
	return true, nil
end

function EconomyService:BuyUpgrade(player: Player, upgradeId: any): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local def = type(upgradeId) == "string" and Config.Upgrades[upgradeId]
	if not def then
		return false, "UnknownUpgrade"
	end
	local level = data.upgrades[upgradeId] or 0
	local cost = EconomyMath.upgradeCost(def, level)
	if not cost then
		return false, "Maxed"
	end
	if not self:TrySpend(player, cost) then
		return false, "NotEnoughCoins"
	end
	data.upgrades[upgradeId] = level + 1
	Services.NetService:Feedback(player, Net.Feedback.Purchased, { kind = "Upgrade", upgradeId = upgradeId, level = level + 1 })
	Services.DataService:MarkDirty(player)
	return true, nil
end

function EconomyService:BuyPlot(player: Player): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local cost = EconomyMath.nextPlotCost(data.ownedPlots, Config.Plots)
	if not cost then
		return false, "Maxed"
	end
	if not self:TrySpend(player, cost) then
		return false, "NotEnoughCoins"
	end
	data.ownedPlots += 1
	Services.PlotService:SyncAll(player, data)
	Services.NetService:Feedback(player, Net.Feedback.Purchased, { kind = "Plot", plotId = tostring(data.ownedPlots) })
	Services.DataService:MarkDirty(player)
	return true, nil
end

local function findProduce(data: { [string]: any }, uid: any): (number?, any)
	if type(uid) ~= "number" then
		return nil, nil
	end
	for index, item in data.produce do
		if item.uid == uid then
			return index, item
		end
	end
	return nil, nil
end
EconomyService.FindProduce = findProduce

function EconomyService:PriceFor(player: Player, item: { [string]: any }): number
	local crop = Config.Crops[item.cropId]
	if not crop then
		return 0
	end
	return EconomyMath.salePrice(item.weight, crop, item.isGiant, self:GetUpgradeValue(player, "marketStall"), Config.Economy)
end

function EconomyService:SellProduce(player: Player, uid: any): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	local index, item = findProduce(data, uid)
	if not index then
		return false, "NotFound"
	end
	local price = self:PriceFor(player, item)
	table.remove(data.produce, index)
	self:AddCoins(player, price, "Sell")
	Services.NetService:Feedback(player, Net.Feedback.Sold, { coins = price, count = 1, cropId = item.cropId })
	return true, { coins = price }
end

function EconomyService:SellAll(player: Player): (boolean, any)
	local data = Services.DataService:Get(player)
	if not data then
		return false, "NotLoaded"
	end
	if #data.produce == 0 then
		return false, "NothingToSell"
	end
	local total, count = 0, 0
	for _, item in data.produce do
		total += self:PriceFor(player, item)
		count += 1
	end
	table.clear(data.produce)
	self:AddCoins(player, total, "SellAll")
	Services.NetService:Feedback(player, Net.Feedback.Sold, { coins = total, count = count })
	return true, { coins = total }
end

return EconomyService
