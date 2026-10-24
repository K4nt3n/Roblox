--!strict
--[[
	ShopPanel: seeds and supplies (like fertilizer bags), one tab each, as lists.
	Opened from the Seed Shop stand in the middle of the map. New plots are bought
	at the plot itself. Upgrades are their own HUD panel (ShopPanel.renderUpgrades).
	Every price comes from the server snapshot or Config.

	Buttons that can't be used yet stay visible but greyed out, and tapping
	them says why ("Reach level 3 first!") instead of doing nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)

local ShopPanel = {}

ShopPanel.TABS = {
	{ id = "seeds", text = "Seeds", icon = "Seeds", color = Theme.Colors.Primary },
	{ id = "supplies", text = "Supplies", icon = "Tools", color = Theme.Colors.Info },
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

-- One shop line: icon, name, info, then "x5" and the single Buy button.
local function shopRow(
	name: string,
	sub: string,
	icon: GuiObject,
	action: string,
	payload: { [string]: any },
	price: string,
	canOne: boolean,
	canFive: boolean,
	reason: string,
	order: number
)
	local five = UIKit.requestButton("x5", action, table.clone(payload), { BackgroundColor3 = Theme.Colors.Accent })
	UIKit.setEnabled(five, canFive, nil, reason)
	local onePayload = table.clone(payload)
	onePayload.amount = 1
	local buy = UIKit.requestButton(price, action, onePayload, { BackgroundColor3 = Theme.Colors.Primary })
	UIKit.withIcon(buy, "Coins")
	UIKit.setEnabled(buy, canOne, nil, reason)
	local row = UIKit.row(name, sub, { five, buy }, icon)
	row.LayoutOrder = order
	return row
end

-- Seeds, one line each: icon, name, grow time and how many you own, buy 5 / buy 1.
local function renderSeeds(body: ScrollingFrame, data: { [string]: any })
	for i, crop in cropOrder() do
		local locked = data.level < crop.unlockLevel
		local owned = data.seeds[crop.id] or 0
		local free = crop.seedCost == 0
		local sub = if locked
			then "Unlocks at level " .. crop.unlockLevel
			else string.format(
				"%s · Own %s",
				Format.duration(crop.growSeconds),
				if free then "∞" else tostring(owned)
			)
		if free then
			-- Free seeds never run out, so there is nothing to buy.
			local row = UIKit.row(crop.displayName, sub .. " · Always free", {}, seedIcon(crop))
			row.LayoutOrder = i
			row.Parent = body
			continue
		end
		shopRow(
			crop.displayName,
			sub,
			seedIcon(crop),
			Net.Actions.BuySeed,
			{ cropId = crop.id, amount = 5 },
			Format.coins(crop.seedCost),
			not locked and data.coins >= crop.seedCost,
			not locked and data.coins >= crop.seedCost * 5,
			if locked then "Reach level " .. crop.unlockLevel .. " first!" else NOT_ENOUGH,
			i
		).Parent =
			body
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
	for i, id in supplyIds do
		local def = Config.Supplies[id]
		local owned = if data.supplies then data.supplies[id] or 0 else 0
		shopRow(
			def.displayName,
			"You have " .. owned,
			ArtSlot.icon("Supply_" .. id, { color = Theme.Colors.Primary, glyph = string.sub(def.displayName, 1, 1) }),
			Net.Actions.BuySupply,
			{ supplyId = id, amount = 5 },
			Format.coins(def.cost),
			data.coins >= def.cost,
			data.coins >= def.cost * 5,
			NOT_ENOUGH,
			i
		).Parent =
			body
	end
	UIKit.paragraph("Equip a garden tool from your hotbar or Backpack > Supplies, then tap a plant to use it.", {
		LayoutOrder = #supplyIds + 1,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextMuted,
		Size = UDim2.new(1, -8, 0, 0),
	}).Parent =
		body
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

-- The Upgrades panel (its own HUD button, not a Shop tab).
ShopPanel.renderUpgrades = renderUpgrades

function ShopPanel.render(body: ScrollingFrame, data: { [string]: any }, tab: string?)
	if tab == "supplies" then
		renderSupplies(body, data)
	else
		renderSeeds(body, data)
	end
end

return ShopPanel
