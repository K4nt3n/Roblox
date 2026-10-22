--!strict
--[[
	ChampionPanel: your champion veggie at a glance. Name it, see its care,
	who is growing it with you, and invite friends to co-grow.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local GrowthMath = require(Shared.GrowthMath)
local CareMath = require(Shared.CareMath)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Modal = require(script.Parent.Modal)
local ArtSlot = require(script.Parent.ArtSlot)
local Counter = require(script.Parent.Counter)

local ChampionPanel = {}

local localPlayer = Players.LocalPlayer
local CHAMPION = Config.Champion

-- Last weight shown, so a re-render keeps rolling instead of restarting from zero.
local lastWeight: number? = nil

local CARE_TEXT = {
	Water = "Thirsty! Water it (R or F)",
	Pests = "Bugs on the leaves! Pick them off (F)",
	Prop = "So heavy it's leaning! Prop it up (F)",
}

local function paragraph(text: string, order: number, parent: Instance, size: number?)
	UIKit.label(text, size or Theme.TextSize.Body, {
		LayoutOrder = order,
		Font = Theme.FontBody,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}).Parent = parent
end

function ChampionPanel.openNamer(current: string?)
	Modal.show({
		title = "Name your champion",
		lines = { "Everyone at the fair will see this name." },
		build = function(holder, close)
			local box = UIKit.new("TextBox", {
				Size = UDim2.fromOffset(300, 44),
				BackgroundColor3 = Theme.Colors.Surface,
				Font = Theme.Font,
				TextSize = Theme.TextSize.Body,
				TextColor3 = Theme.Colors.Text,
				PlaceholderText = "Big Bertha",
				Text = current or "",
				ClearTextOnFocus = false,
				Parent = holder,
			}, { UIKit.corner(Theme.CornerSmall), UIKit.stroke(nil, 2) })
			UIKit.button("Save name", function()
				local text = box.Text
				if #text > 0 then
					task.spawn(NetClient.request, Net.Actions.NameChampion, { name = string.sub(text, 1, CHAMPION.maxNameLength * 4) })
				end
				close()
			end, { Size = UDim2.fromOffset(160, 40) }).Parent = holder
		end,
		buttons = { { text = "Cancel", color = Theme.Colors.Surface, textColor = Theme.Colors.Text } },
	})
end

function ChampionPanel.render(body: ScrollingFrame, data: { [string]: any })
	local plant = data.plots and data.plots[CHAMPION.plotId]
	local card = UIKit.card({ Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = body }, {
		UIKit.padding(14),
		UIKit.list(Enum.FillDirection.Vertical, 6),
	})

	if not plant then
		UIKit.label("No champion yet", Theme.TextSize.Large, { LayoutOrder = 1 }).Parent = card
		paragraph(
			"Plant any seed on the big plot in front of your garden. Your champion grows all week, and every time you care for it (water, pick off bugs, prop it up) it gets heavier. Care beats luck!",
			2,
			card
		)
		return
	end

	local crop = Config.Crops[plant.cropId]
	local now = ClientState.now()
	local state = if crop then GrowthMath.evaluate(plant, crop, Config, now) else nil
	local title = if plant.name then string.format("%s the %s", plant.name, crop and crop.displayName or "") else (crop and crop.displayName or "Champion")
	local c = crop and crop.placeholderColor
	ArtSlot.icon("ChampionPortrait", {
		size = 96,
		round = true,
		color = if c then Color3.fromRGB(c[1], c[2], c[3]) else Theme.Colors.Purple,
		glyph = if crop then string.sub(crop.displayName, 1, 1) else "?",
		layoutOrder = -2,
	}).Parent = card
	UIKit.label(title, Theme.TextSize.Large, { LayoutOrder = -1 }).Parent = card
	if state and crop then
		-- The weight keeps rolling up while the panel is open: you can watch it grow.
		local weightLabel = UIKit.label("", Theme.TextSize.Huge, { LayoutOrder = 1, TextColor3 = Theme.Colors.PrimaryDark })
		weightLabel.Parent = card
		local stageLabel = UIKit.label(state.stage, Theme.TextSize.Small, {
			LayoutOrder = 2,
			Font = Theme.FontBody,
			TextColor3 = Theme.Colors.TextMuted,
		})
		stageLabel.Parent = card
		local weight = Counter.new(weightLabel, Format.weight)
		weight:set(lastWeight or state.weight, { instant = true })
		task.spawn(function()
			while weightLabel.Parent do
				local live = GrowthMath.evaluate(plant, crop, Config, ClientState.now())
				if live.stage ~= stageLabel.Text then
					stageLabel.Text = live.stage
				end
				weight:set(live.weight, { quiet = true })
				lastWeight = live.weight
				task.wait(0.5)
			end
		end)
	end

	local careScore = plant.careScore or 0
	local bonus = math.floor((CareMath.weightMultiplier(careScore, CHAMPION) - 1) * 100 + 0.5)
	paragraph(string.format("Care: %.1f points (+%d%% weight)", careScore, bonus), 3, card)

	local need = if crop
		then CareMath.pendingNeed(plant, CHAMPION, now, function(t)
			return GrowthMath.evaluate(plant, crop, Config, t).canHarvest
		end)
		else nil
	if need then
		paragraph((CARE_TEXT[need.kind] or need.kind) .. (if need.onTime then "" else " (still counts!)"), 4, card, Theme.TextSize.Large)
	else
		paragraph("All cared for. Check back later!", 4, card)
	end

	local paidSkips = plant.paidSkips or 0
	paragraph(
		if paidSkips == 0
			then "Natural Grown: eligible (no paid skips)"
			else string.format("Natural Grown: not eligible (%d paid skip%s)", paidSkips, if paidSkips == 1 then "" else "s"),
		5,
		card
	)

	UIKit.button(if plant.name then "Rename" else "Name it", function()
		ChampionPanel.openNamer(plant.name)
	end, { LayoutOrder = 6, Size = UDim2.fromOffset(160, 40), BackgroundColor3 = Theme.Colors.Accent }).Parent = card

	-- Grow together.
	UIKit.label("Grow together", Theme.TextSize.Large, { LayoutOrder = 2 }).Parent = body
	local coGrowers = plant.coGrowers or {}
	local names = {}
	for _, userId in coGrowers do
		local p = Players:GetPlayerByUserId(userId)
		table.insert(names, if p then p.DisplayName else ("Friend " .. userId))
	end
	paragraph(
		if #names > 0
			then "Growing with " .. table.concat(names, " and ") .. ". They can water and care for it, and share its prizes."
			else string.format("Invite up to %d friends to co-grow your champion. Everyone is listed on its fair card and shares its prizes.", CHAMPION.maxCoGrowers),
		3,
		body
	)
	if #coGrowers < CHAMPION.maxCoGrowers then
		local order = 10
		for _, other in Players:GetPlayers() do
			if other ~= localPlayer and not table.find(coGrowers, other.UserId) then
				order += 1
				local invite = UIKit.button("Invite", function()
					task.spawn(NetClient.request, Net.Actions.InviteCoGrower, { userId = other.UserId })
				end, { BackgroundColor3 = Theme.Colors.Primary })
				local row = UIKit.row(other.DisplayName, nil, { invite })
				row.LayoutOrder = order
				row.Parent = body
			end
		end
	end
end

-- A friend invited you to co-grow.
function ChampionPanel.showInvite(ctx: { [string]: any })
	local crop = Config.Crops[ctx.cropId]
	local what = if ctx.championName then ctx.championName else ("their " .. (crop and crop.displayName or "champion"))
	Modal.show({
		title = ctx.ownerName .. " wants to grow together!",
		lines = { string.format("Help raise %s. You can water and care for it, and you'll share its fair prizes.", what) },
		buttons = {
			{
				text = "Let's grow!",
				onClick = function()
					task.spawn(NetClient.request, Net.Actions.RespondCoGrow, { ownerUserId = ctx.ownerUserId, accept = true })
				end,
			},
			{
				text = "No thanks",
				color = Theme.Colors.Surface,
				textColor = Theme.Colors.Text,
				onClick = function()
					task.spawn(NetClient.request, Net.Actions.RespondCoGrow, { ownerUserId = ctx.ownerUserId, accept = false })
				end,
			},
		},
	})
end

return ChampionPanel
