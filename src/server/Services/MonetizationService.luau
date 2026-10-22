--!strict
--[[
	MonetizationService: developer products (stubbed until real ids exist).

	* PromptSkip remembers which plot the player wants to skip, then prompts the
	  purchase. ProcessReceipt applies it (or picks the longest wait if the
	  target is gone).
	* Receipts are idempotent: each PurchaseId is recorded in the profile and
	  granted only once, and we only return PurchaseGranted after the profile
	  holds the grant.
	* With productId = 0 (stub) the purchase can be simulated in Studio through
	  the DebugSimulatePurchase action so the full loop is testable today.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local MonetizationService = {}

local Services: any
local pendingSkipTarget: { [Player]: string } = {}
local productsById: { [number]: { [string]: any } } = {}

function MonetizationService:Init(services)
	Services = services
	for name, product in Config.Monetization.Products do
		if product.productId ~= 0 then
			productsById[product.productId] = table.clone(product)
			productsById[product.productId].name = name
		end
	end
end

function MonetizationService:Start()
	local NetService = Services.NetService

	NetService:Handle(Net.Actions.PromptSkip, function(player, payload)
		local data = Services.DataService:Get(player)
		local plotId = payload.plotId
		if not data or type(plotId) ~= "string" or not data.plots[plotId] then
			return false, "NothingPlanted"
		end
		pendingSkipTarget[player] = plotId
		local product = Config.Monetization.Products.SkipGrowth
		if product.productId == 0 then
			return false, "ProductNotConfigured"
		end
		MarketplaceService:PromptProductPurchase(player, product.productId)
		return true, nil
	end)

	NetService:Handle(Net.Actions.DebugSimulatePurchase, function(player, payload)
		if not RunService:IsStudio() then
			return false, "StudioOnly"
		end
		local product = Config.Monetization.Products[payload.product]
		if not product then
			return false, "UnknownProduct"
		end
		if type(payload.plotId) == "string" then
			pendingSkipTarget[player] = payload.plotId
		end
		local granted = self:_grant(player, product, "debug_" .. os.clock())
		return granted, if granted then nil else "GrantFailed"
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		return self:_processReceipt(receipt)
	end

	Players.PlayerRemoving:Connect(function(player)
		pendingSkipTarget[player] = nil
	end)
end

function MonetizationService:_grant(player: Player, product: { [string]: any }, purchaseId: string): boolean
	local data = Services.DataService:Get(player)
	if not data then
		return false
	end
	if data.purchases[purchaseId] then
		return true -- Already granted.
	end

	if product.kind == "SkipGrowth" then
		local skipped = Services.GardenService:SkipGrowth(player, pendingSkipTarget[player])
		pendingSkipTarget[player] = nil
		if not skipped then
			-- Nothing growing: refund as coins so the purchase is never wasted.
			Services.EconomyService:AddCoins(player, Config.Monetization.skipRefundCoins, "SkipRefund")
		end
		Services.NetService:Feedback(player, Net.Feedback.Purchased, { kind = "SkipGrowth", plotId = skipped })
	elseif product.kind == "Coins" then
		Services.EconomyService:AddCoins(player, product.amount, "Purchase")
		Services.NetService:Feedback(player, Net.Feedback.Purchased, { kind = "Coins", amount = product.amount })
	else
		return false
	end

	data.purchases[purchaseId] = os.time()
	self:_trimPurchases(data)
	Services.DataService:MarkDirty(player)
	return true
end

function MonetizationService:_trimPurchases(data: { [string]: any })
	local list = {}
	for id, at in data.purchases do
		table.insert(list, { id = id, at = at })
	end
	if #list <= Config.Data.maxPurchaseHistory then
		return
	end
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	for i = 1, #list - Config.Data.maxPurchaseHistory do
		data.purchases[list[i].id] = nil
	end
end

function MonetizationService:_processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = productsById[receipt.ProductId]
	if not player or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not Services.DataService:WaitFor(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(self._grant, self, player, product, receipt.PurchaseId)
	if ok and granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

return MonetizationService
