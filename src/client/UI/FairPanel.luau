--!strict
--[[
	FairPanel: the three fairs (hourly, daily, weekly) side by side, the fair
	picker used by the Basket, and the results / replay card.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local FairMath = require(Shared.FairMath)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Modal = require(script.Parent.Modal)
local RibbonNames = require(script.Parent.RibbonNames)

local FairPanel = {}

local localPlayer = Players.LocalPlayer
local PERIODS = FairMath.sortedPeriods(Config.Fair.periods)
local selectedFair = "weekly"

local function cropName(cropId: string?): string
	local crop = cropId and Config.Crops[cropId]
	return if crop then crop.displayName else (cropId or "")
end

local function currentEntry(data: { [string]: any }, fairName: string): any
	local info = data.fairs and data.fairs[fairName]
	local entries = data.fair and data.fair.entries and data.fair.entries[fairName]
	return info and entries and entries[tostring(info.id)]
end

function FairPanel.render(body: ScrollingFrame, data: { [string]: any }, rerender: () -> ())
	-- Fair tabs.
	local tabs = UIKit.new("Frame", {
		LayoutOrder = 0,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 44),
		Parent = body,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 8) })
	for i, period in PERIODS do
		local selected = period.id == selectedFair
		UIKit.button(period.displayName, function()
			selectedFair = period.id
			rerender()
		end, {
			LayoutOrder = i,
			Size = UDim2.fromOffset(170, 40),
			BackgroundColor3 = if selected then Theme.Colors.PrimaryDark else Theme.Colors.Surface,
			TextColor3 = if selected then Theme.Colors.TextOnPrimary else Theme.Colors.Text,
		}).Parent = tabs
	end

	local period = Config.Fair.periods[selectedFair]
	local fairInfo = data.fairs and data.fairs[selectedFair]
	local endsAt = if fairInfo then fairInfo.endsAt else 0
	local entry = currentEntry(data, selectedFair)

	local info = UIKit.card({ Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = body }, {
		UIKit.padding(12),
		UIKit.list(Enum.FillDirection.Vertical, 4),
	})
	local countdown = UIKit.label("", Theme.TextSize.Large, { LayoutOrder = 1 })
	countdown.Parent = info
	local lines = {}
	if entry then
		table.insert(lines, string.format("Your entry: %s %s", cropName(entry.cropId), Format.weight(entry.weight)))
		local item = entry.item
		if item then
			local divisions = {}
			for _, division in FairMath.divisionsForEntry(item, entry.ctx or {}, period.divisions) do
				table.insert(divisions, FairMath.divisionName(division.id, Config.Fair.divisions, Config.Crops))
			end
			table.insert(lines, "Competing in: " .. table.concat(divisions, ", "))
		end
	else
		table.insert(lines, "No entry yet. Enter a veggie from your Basket!")
	end
	local divisionNames = {}
	for _, id in period.divisions do
		local name = if id == "crop" then "Best of each veggie" else FairMath.divisionName(id, Config.Fair.divisions, Config.Crops)
		table.insert(divisionNames, name)
	end
	table.insert(lines, "Ribbons for: " .. table.concat(divisionNames, ", "))
	for i, line in lines do
		UIKit.label(line, Theme.TextSize.Body, {
			LayoutOrder = 1 + i,
			Font = Theme.FontBody,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}).Parent = info

	end

	if RunService:IsStudio() then
		UIKit.button("Preview show (Studio)", function()
			NetClient.request(Net.Actions.DebugStartFairDay, { fair = selectedFair })
		end, { LayoutOrder = 10, Size = UDim2.fromOffset(220, 36), BackgroundColor3 = Theme.Colors.Accent }).Parent = info
	end

	task.spawn(function()
		while countdown.Parent do
			countdown.Text = "Judging in " .. Format.duration(endsAt - ClientState.now())
			task.wait(1)
		end
	end)

	local board = ClientState.leaderboard
	local rows = board and board.fairs and board.fairs[selectedFair] and board.fairs[selectedFair].rows or {}
	if #rows == 0 then
		UIKit.label("No entries yet. Be the first!", Theme.TextSize.Body, { LayoutOrder = 20, Font = Theme.FontBody }).Parent = body
	end
	for i, row in rows do
		local isMe = row.userId == localPlayer.UserId
		UIKit.card({
			Size = UDim2.new(1, -8, 0, 44),
			LayoutOrder = 20 + i,
			BackgroundColor3 = if isMe then Theme.Colors.Gold else Theme.Colors.Surface,
			Parent = body,
		}, {
			UIKit.label(string.format("#%d  %s", row.rank, row.name), Theme.TextSize.Body, { Position = UDim2.fromOffset(12, 10) }),
			UIKit.label(Format.weight(row.weight), Theme.TextSize.Body, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 10),
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		})
	end
end

-- Basket "Enter Fair": pick which fair this veggie goes to.
function FairPanel.pick(item: { [string]: any })
	local data = ClientState.data
	if not data then
		return
	end
	Modal.show({
		title = "Enter " .. cropName(item.cropId) .. " · " .. Format.weight(item.weight),
		lines = { "Each veggie can go to one fair. Heavier entries replace lighter ones." },
		build = function(holder, close)
			for i, period in PERIODS do
				local entry = currentEntry(data, period.id)
				local fairInfo = data.fairs and data.fairs[period.id]
				local left = if fairInfo then Format.duration(fairInfo.endsAt - ClientState.now()) else ""
				local status = if entry
					then (if entry.weight >= item.weight then "Your entry is heavier (" .. Format.weight(entry.weight) .. ")" else "Replaces " .. Format.weight(entry.weight))
					else "No entry yet"
				local canEnter = not entry or entry.weight < item.weight
				local button = UIKit.button(period.displayName, function()
					NetClient.request(Net.Actions.EnterFair, { uid = item.uid, fair = period.id })
					close()
				end, { Size = UDim2.fromOffset(170, 40), BackgroundColor3 = Theme.Colors.Gold, TextColor3 = Theme.Colors.Text })
				UIKit.setEnabled(button, canEnter, Theme.Colors.Gold)
				local row = UIKit.row(period.displayName, string.format("Judging in %s · %s", left, status), { button })
				row.LayoutOrder = i
				row.Size = UDim2.new(1, 0, 0, 64)
				row.Parent = holder
			end
		end,
		buttons = { { text = "Not now", color = Theme.Colors.Surface, textColor = Theme.Colors.Text } },
	})
end

-- Results after a show, or a replay card for a show the player missed.
function FairPanel.showResults(ctx: { [string]: any })
	local lines = {}
	if ctx.weight then
		local who = if ctx.championName then string.format("%s the %s", ctx.championName, cropName(ctx.cropId)) else cropName(ctx.cropId)
		table.insert(lines, string.format("%s weighed %s", who, Format.weight(ctx.weight)))
	end
	if ctx.coGrowerNames and #ctx.coGrowerNames > 0 then
		table.insert(lines, "Grown together with " .. table.concat(ctx.coGrowerNames, " and "))
	end
	for _, ribbon in ctx.ribbons or {} do
		local place = if ribbon.rank then " (#" .. ribbon.rank .. ")" else ""
		table.insert(lines, RibbonNames.describe(ribbon.ribbon) .. place)
	end
	if #(ctx.ribbons or {}) == 0 then
		table.insert(lines, "No ribbon this time. Keep growing!")
	end
	if (ctx.coins or 0) > 0 then
		table.insert(lines, "+" .. Format.coins(ctx.coins) .. " Coins")
	end
	Modal.show({
		title = if ctx.missedShow then "You missed the " .. ctx.fairName .. "! Here's the replay" else ctx.fairName .. " results",
		lines = lines,
		accent = Theme.Colors.Gold,
		buttons = { { text = "Hooray!", color = Theme.Colors.Gold, textColor = Theme.Colors.Text } },
	})
end

return FairPanel
