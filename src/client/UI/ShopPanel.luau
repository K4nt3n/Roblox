--!strict
--[[
	ShopPanel: seeds, upgrades and the garden (plots + honest skip-the-wait),
	one tab each. Every price comes from the server snapshot.

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
	{ id = "seeds", text = "Seeds" },
	{ id = "upgrades", text = "Upgrades" },
	{ id = "garden", text = "Garden" },
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

local function renderSeeds(body: ScrollingFrame, data: { [string]: any })
	for i, crop in cropOrder() do
		local locked = data.level < crop.unlockLevel
		local owned = data.seeds[crop.id] or 0
		local free = crop.seedCost == 0
		local sub = if locked
			then "Unlocks at level " .. crop.unlockLevel
			else string.format(
				"Ripe in %s · You have %s",
				Format.duration(crop.growSeconds),
				if free then "∞" else tostring(owned)
			)
		local lockedReason = "Reach level " .. crop.unlockLevel .. " first!"
		local buy = UIKit.requestButton(
			if free then "Free" else Format.coins(crop.seedCost),
			Net.Actions.BuySeed,
			{ cropId = crop.id, amount = 1 }
		)
		local buyFive = UIKit.requestButton("x5", Net.Actions.BuySeed, { cropId = crop.id, amount = 5 }, {
			BackgroundColor3 = Theme.Colors.Accent,
		})
		UIKit.setEnabled(
			buy,
			not locked and not free and data.coins >= crop.seedCost,
			nil,
			if locked then lockedReason elseif free then "Carrots are always free!" else NOT_ENOUGH
		)
		UIKit.setEnabled(
			buyFive,
			not locked and not free and data.coins >= crop.seedCost * 5,
			nil,
			if locked then lockedReason elseif free then "Carrots are always free!" else NOT_ENOUGH
		)
		local row = UIKit.row(crop.displayName, sub, { buyFive, buy }, seedIcon(crop))
		row.LayoutOrder = i
		if locked then
			row.BackgroundColor3 = Theme.Colors.SurfaceAlt
		end
		row.Parent = body
	end
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

function ShopPanel.render(body: ScrollingFrame, data: { [string]: any }, tab: string?)
	if tab == "upgrades" then
		renderUpgrades(body, data)
	elseif tab == "garden" then
		renderGarden(body, data)
	else
		renderSeeds(body, data)
	end
end

return ShopPanel
