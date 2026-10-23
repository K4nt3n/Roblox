--!strict
--[[
	ShopPanel: seeds (+ supplies like fertilizer bags) and the garden (plots +
	honest skip-the-wait), one tab each. Opened from the Seed Shop stand in the
	middle of the map. Upgrades are their own HUD panel (ShopPanel.renderUpgrades).
	Every price comes from the server snapshot or Config.

	Buttons that can't be used yet stay visible but greyed out, and tapping
	them says why ("Reach level 3 first!") instead of doing nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local GrowthMath = require(Shared.GrowthMath)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)

local ShopPanel = {}

ShopPanel.TABS = {
	{ id = "seeds", text = "Seeds", icon = "Seeds", color = Theme.Colors.Primary },
	{ id = "supplies", text = "Supplies", icon = "Tools", color = Theme.Colors.Info },
	{ id = "garden", text = "Garden", icon = "Fence", color = Theme.Colors.Gold },
} :: { UIKit.TabItem }

local NOT_ENOUGH = "Not enough Coins yet!"

local function cropOrder(): { any }
	local list = {}
	for _, crop in Config.Crops do
		table.insert(list, crop)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

local function seedIcon(crop: any): GuiObject
	local c = crop.placeholderColor
	return ArtSlot.icon("Seed_" .. crop.id, {
		round = true,
		color = if c then Color3.fromRGB(c[1], c[2], c[3]) else nil,
		glyph = string.sub(crop.displayName, 1, 1),
	})
end

-- Small "x5" quick-buy button in the corner of an item card's icon.
local function addBuyFive(card: Frame, action: string, payload: { [string]: any }, enabled: boolean, reason: string)
	local holder = card:FindFirstChild("IconHolder") :: Frame?
	if not holder then
		return
	end
	local five = UIKit.requestButton("x5", action, payload, {
		Name = "BuyFive",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(44, 30),
		TextSize = Theme.TextSize.Small,
		BackgroundColor3 = Theme.Colors.Accent,
		ZIndex = 4,
	})
	UIKit.setEnabled(five, enabled, nil, reason)
	five.Parent = holder
end

-- Seeds as item cards: icon, name, grow time / owned, Buy button (green = buy).
local function renderSeeds(body: ScrollingFrame, data: { [string]: any })
	local grid = UIKit.grid(1, body)
	for i, crop in cropOrder() do
		local locked = data.level < crop.unlockLevel
		local owned = data.seeds[crop.id] or 0
		local free = crop.seedCost == 0
		local sub = if locked
			then "Unlocks at level " .. crop.unlockLevel
			else string.format("%s · Own %s", Format.duration(crop.growSeconds), if free then "∞" else tostring(owned))
		local lockedReason = "Reach level " .. crop.unlockLevel .. " first!"
		local buy = UIKit.requestButton(
			if free then "Free" else Format.coins(crop.seedCost),
			Net.Actions.BuySeed,
			{ cropId = crop.id, amount = 1 },
			{ BackgroundColor3 = Theme.Colors.Primary }
		)
		if not free then
			UIKit.withIcon(buy, "Coins")
		end
		UIKit.setEnabled(
			buy,
			not locked and not free and data.coins >= crop.seedCost,
			nil,
			if locked then lockedReason elseif free then "Carrots are always free!" else NOT_ENOUGH
		)
		local card = UIKit.itemCard({
			name = crop.displayName,
			icon = seedIcon(crop),
			sub = sub,
			button = buy,
			locked = locked,
			order = i,
		})
		if not free then
			addBuyFive(
				card,
				Net.Actions.BuySeed,
				{ cropId = crop.id, amount = 5 },
				not locked and data.coins >= crop.seedCost * 5,
				if locked then lockedReason else NOT_ENOUGH
			)
		end
		card.Parent = grid
	end
end

-- Supplies (Config.Supplies): consumables used with the garden tools.
local function renderSupplies(body: ScrollingFrame, data: { [string]: any })
	local supplyIds = {}
	for id in Config.Supplies do
		table.insert(supplyIds, id)
	end
	table.sort(supplyIds, function(a, b)
		return Config.Supplies[a].order < Config.Supplies[b].order
	end)
	local grid = UIKit.grid(1, body)
	for i, id in supplyIds do
		local def = Config.Supplies[id]
		local owned = if data.supplies then data.supplies[id] or 0 else 0
		local buy = UIKit.requestButton(Format.coins(def.cost), Net.Actions.BuySupply, { supplyId = id, amount = 1 })
		UIKit.withIcon(buy, "Coins")
		UIKit.setEnabled(buy, data.coins >= def.cost, nil, NOT_ENOUGH)
		local card = UIKit.itemCard({
			name = def.displayName,
			icon = ArtSlot.icon("Supply_" .. id, { color = Theme.Colors.Primary, glyph = string.sub(def.displayName, 1, 1) }),
			sub = "You have " .. owned,
			button = buy,
			count = owned,
			order = i,
		})
		addBuyFive(card, Net.Actions.BuySupply, { supplyId = id, amount = 5 }, data.coins >= def.cost * 5, NOT_ENOUGH)
		card.Parent = grid
	end
	UIKit.paragraph("Equip a garden tool from your hotbar or Backpack > Supplies, then tap a plant to use it.", {
		LayoutOrder = 2,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextMuted,
		Size = UDim2.new(1, -8, 0, 0),
	}).Parent = body
end

local function renderUpgrades(body: ScrollingFrame, data: { [string]: any })
	local upgradeIds = {}
	for id in Config.Upgrades do
		table.insert(upgradeIds, id)
	end
	table.sort(upgradeIds)
	for i, id in upgradeIds do
		local def = Config.Upgrades[id]
		local info = data.upgradeInfo and data.upgradeInfo[id]
		local level = if info then info.level else 0
		local maxLevel = if info then info.maxLevel else #def.costs
		local cost = info and info.nextCost
		local button =
			UIKit.requestButton(if cost then Format.coins(cost) else "MAX", Net.Actions.BuyUpgrade, { upgradeId = id })
		UIKit.setEnabled(
			button,
			cost ~= nil and data.coins >= cost,
			nil,
			if cost then NOT_ENOUGH else "Fully upgraded!"
		)
		local row = UIKit.row(
			string.format("%s  (Lv %d/%d)", def.displayName, level, maxLevel),
			def.description,
			{ button },
			ArtSlot.icon("Upgrade_" .. id, { color = Theme.Colors.Info, glyph = string.sub(def.displayName, 1, 1) })
		)
		row.LayoutOrder = i
		row.Parent = body
	end
end

local function renderGarden(body: ScrollingFrame, data: { [string]: any })
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local plotButton =
		UIKit.requestButton(if data.nextPlotCost then Format.coins(data.nextPlotCost) else "MAX", Net.Actions.BuyPlot)
	UIKit.setEnabled(
		plotButton,
		data.nextPlotCost ~= nil and data.coins >= data.nextPlotCost,
		nil,
		if data.nextPlotCost then NOT_ENOUGH else "Your garden is full size!"
	)
	local plotRow = UIKit.row(
		"New Plot",
		string.format("You own %d of %d", data.ownedPlots, Config.Plots.maxPlots),
		{ plotButton },
		ArtSlot.icon("Upgrade_plot", { color = Theme.Colors.Primary, glyph = "+" })
	)
	plotRow.LayoutOrder = nextOrder()
	plotRow.Parent = body

	-- Skip-the-wait (developer product) for anything still growing. The shop is
	-- honest about what a skip costs your champion.
	UIKit.section("Skip the wait", nextOrder(), body)
	UIKit.paragraph(
		string.format(
			"Champion skips left this week: %d. A skipped champion can't win Natural Grown, and care still beats skips.",
			data.championSkipsLeft or 0
		),
		{
			LayoutOrder = nextOrder(),
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextMuted,
			Size = UDim2.new(1, -8, 0, 0),
		}
	).Parent =
		body
	local now = ClientState.now()
	local plotIds = {}
	for plotId in data.plots do
		table.insert(plotIds, plotId)
	end
	table.sort(plotIds, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	local any = false
	for _, plotId in plotIds do
		local plant = data.plots[plotId]
		local crop = Config.Crops[plant.cropId]
		if crop then
			local state = GrowthMath.evaluate(plant, crop, Config, now)
			local isChampion = plant.champion == true
			if not state.canHarvest then
				any = true
				local skip = UIKit.button("Skip", function()
					task.spawn(function()
						local result = NetClient.request(Net.Actions.PromptSkip, { plotId = plotId })
						if not result.ok and result.err == "ProductNotConfigured" and RunService:IsStudio() then
							-- Stub product: simulate the purchase in Studio so the loop is testable.
							NetClient.request(
								Net.Actions.DebugSimulatePurchase,
								{ product = "SkipGrowth", plotId = plotId }
							)
						end
					end)
				end, { BackgroundColor3 = Theme.Colors.Gold })
				if isChampion then
					UIKit.setEnabled(
						skip,
						(data.championSkipsLeft or 0) > 0,
						nil,
						"Champions can only be skipped once a week. Care for it instead!"
					)
				end
				local row = UIKit.row(
					if isChampion
						then "Champion · " .. crop.displayName
						else string.format("Plot %s · %s", plotId, crop.displayName),
					"Ripe in "
						.. Format.duration(state.secondsToRipe)
						.. (
							if isChampion and (plant.paidSkips or 0) == 0 then " · skipping ends Natural Grown" else ""
						),
					{ skip },
					seedIcon(crop)
				)
				row.LayoutOrder = nextOrder()
				row.Parent = body
			end
		end
	end
	if not any then
		UIKit.paragraph("Nothing is growing right now. Plant something!", {
			LayoutOrder = nextOrder(),
			TextColor3 = Theme.Colors.TextMuted,
		}).Parent =
			body
	end
end

-- The Upgrades panel (its own HUD button, not a Shop tab).
ShopPanel.renderUpgrades = renderUpgrades

function ShopPanel.render(body: ScrollingFrame, data: { [string]: any }, tab: string?)
	if tab == "supplies" then
		renderSupplies(body, data)
	elseif tab == "garden" then
		renderGarden(body, data)
	else
		renderSeeds(body, data)
	end
end

return ShopPanel
