--!strict
--[[
	QuestsPanel: the Quests menu and the daily login card.

	  Daily tab   the 7-day login streak strip, then today's quests
	  Weekly tab  the star track (chests along a bar), then this week's quests
	  Login card  QuestsPanel.showStreak(data): pops up on join when today's
	              reward is waiting; the Claim button sends ClaimStreak

	Everything shown comes from snapshot.rewards (RewardService). Amounts and
	streak days are read from Config.Rewards so the strip can show future days.
	Art slots: Quest_<kind> (quest icons), Chest / ChestBig, Star.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Icons = require(script.Parent.Icons)
local Modal = require(script.Parent.Modal)

local QuestsPanel = {}

QuestsPanel.TABS = {
	{ id = "daily", text = "Daily", icon = "Sun" },
	{ id = "weekly", text = "Weekly", icon = "Star" },
} :: { UIKit.TabItem }

local REWARDS = Config.Rewards

-- Quest kind -> Icons name (placeholder emoji until Peter's art lands).
local KIND_ICON: { [string]: string } = {
	plant = "Seedling",
	harvest = "Basket",
	harvestGiant = "Pumpkin",
	sell = "Market",
	earn = "Coins",
	water = "Water",
	waterFriend = "Friends",
	pests = "Bugs",
	fertilize = "Fertilizer",
	care = "Crown",
	enterFair = "Trophy",
}

local function plural(count: number, word: string): string
	return if count == 1 then word else word .. "s"
end

-- "+150 Coins · 40 XP · 3 Tomato Seeds"
function QuestsPanel.describe(bundle: { [string]: any }?): string
	if not bundle then
		return ""
	end
	local parts = {}
	if (bundle.coins or 0) > 0 then
		table.insert(parts, Format.coins(bundle.coins) .. " Coins")
	end
	if (bundle.xp or 0) > 0 then
		table.insert(parts, bundle.xp .. " XP")
	end
	for cropId, count in bundle.seeds or {} do
		local crop = Config.Crops[cropId]
		table.insert(parts, string.format("%d %s %s", count, if crop then crop.displayName else cropId, plural(count, "Seed")))
	end
	for supplyId, count in bundle.supplies or {} do
		local def = Config.Supplies[supplyId]
		table.insert(parts, string.format("%d %s", count, if def then plural(count, def.displayName) else supplyId))
	end
	return table.concat(parts, " · ")
end

-- Main icon for a reward bundle: coins unless it is mostly something else.
local function bundleIcon(bundle: { [string]: any }): string
	if (bundle.coins or 0) > 0 then
		return "Coins"
	elseif next(bundle.supplies or {}) then
		return "Fertilizer"
	elseif next(bundle.seeds or {}) then
		return "Seeds"
	end
	return "Star"
end

local function claim(action: string, payload: { [string]: any }?, button: TextButton)
	UIKit.setBusy(button, true)
	task.spawn(function()
		local result = NetClient.request(action, payload)
		if button.Parent then
			UIKit.setBusy(button, false)
			if not result.ok then
				Tweens.shake(button)
			end
		end
	end)
end

-- A progress bar inside `parent`. fill 0..1.
local function bar(parent: GuiObject, fill: number, color: Color3, props: { [string]: any }): Frame
	local track = UIKit.new("Frame", {
		Name = "Bar",
		BackgroundColor3 = Theme.darken(Theme.Style.Outline, 0.3),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = parent,
	}, { UIKit.corner(Theme.CornerRound) })
	for key, value in props do
		(track :: any)[key] = value
	end
	local fillFrame = UIKit.new("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(math.clamp(fill, 0, 1), 1),
		Parent = track,
	}, { UIKit.corner(Theme.CornerRound) })
	UIKit.paint(fillFrame, color)
	UIKit.gloss(fillFrame)
	return track
end

local function countdown(endsAt: number?): string
	if not endsAt then
		return ""
	end
	return "New in " .. Format.duration(endsAt - ClientState.now())
end

---------------------------------------------------------------------------
-- Streak strip (panel and login card)
---------------------------------------------------------------------------

--[[
	Seven day tiles. Days before `day` are done, `day` is today (glowing while
	it can be claimed), later days are still to come.
]]
local function streakStrip(parent: Instance, streak: { [string]: any }, order: number, tileSize: number?): Frame
	local size = tileSize or 74
	local days = REWARDS.streak.days
	local strip = UIKit.new("Frame", {
		Name = "Streak",
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, size + 26),
		Parent = parent,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
	local today = streak.day or 1
	for i, reward in days do
		local done = i < today or (i == today and not streak.ready)
		local isToday = i == today and streak.ready
		local big = i == #days
		local color = if isToday then Theme.Colors.Gold elseif done then Theme.Colors.PrimaryDark else Theme.Colors.SurfaceAlt
		local tile = UIKit.card({
			Name = "Day" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(if big then size + 18 else size, size + 22),
			BackgroundColor3 = color,
			Parent = strip,
		})
		if isToday then
			UIKit.outline(tile, 4).Color = Theme.Colors.Gold
			UIKit.sweep(tile)
		end
		local dayLabel = UIKit.label("Day " .. i, Theme.TextSize.Small, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.Colors.TextOnPrimary,
			Parent = tile,
		})
		UIKit.outlineText(dayLabel, 2)
		local icon = Icons.make(if big then "Gift" else bundleIcon(reward), math.floor(size * (if big then 0.55 else 0.43)))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, 2)
		icon.Parent = tile
		local amount = UIKit.label(if (reward.coins or 0) > 0 then Format.coins(reward.coins) else "", Theme.TextSize.Small, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.Colors.TextOnPrimary,
			Parent = tile,
		})
		UIKit.outlineText(amount, 2)
		if done then
			local check = Icons.make("Success", 24)
			check.AnchorPoint = Vector2.new(1, 0)
			check.Position = UDim2.new(1, 2, 0, -6)
			check.ZIndex = 5
			check.Parent = tile
		end
	end
	return strip
end

---------------------------------------------------------------------------
-- Quest rows
---------------------------------------------------------------------------

local function questRow(quest: { [string]: any }, period: string, order: number, parent: Instance)
	local row = UIKit.card({
		Name = "Quest" .. quest.index,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 84),
		BackgroundColor3 = if quest.ready then Theme.Colors.Surface else Theme.Colors.SurfaceAlt,
		Parent = parent,
	})
	if quest.ready then
		UIKit.outline(row, 3).Color = Theme.Colors.Gold
	end
	local icon = Icons.make(KIND_ICON[quest.kind] or "Quest", 48)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Parent = row
	UIKit.label(quest.text, Theme.TextSize.Body, {
		Position = UDim2.fromOffset(72, 10),
		Size = UDim2.new(1, -230, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local reward = QuestsPanel.describe(quest.reward)
	if (quest.stars or 0) > 0 then
		reward ..= string.format(" · %d %s", quest.stars, plural(quest.stars, "Star"))
	end
	UIKit.label(reward, Theme.TextSize.Small, {
		Position = UDim2.fromOffset(72, 34),
		Size = UDim2.new(1, -230, 0, 18),
		AutomaticSize = Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Theme.FontBody,
		TextColor3 = Theme.Colors.TextMuted,
		Parent = row,
	})
	local track = bar(row, quest.progress / math.max(quest.goal, 1), if quest.ready or quest.claimed then Theme.Colors.Gold else Theme.Colors.Primary, {
		Position = UDim2.fromOffset(72, 58),
		Size = UDim2.new(1, -230, 0, 16),
	})
	local count = UIKit.label(string.format("%s / %s", Format.coins(quest.progress), Format.coins(quest.goal)), Theme.TextSize.Small, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 4,
		Parent = track,
	})
	UIKit.outlineText(count, 2)

	local button: TextButton
	if quest.claimed then
		button = UIKit.button("Done!", function() end, { BackgroundColor3 = Theme.Colors.PrimaryDark })
		UIKit.setEnabled(button, false, Theme.Colors.PrimaryDark, "Already claimed. New quests soon!")
	elseif quest.ready then
		button = UIKit.keyButton("Claim!", function()
			claim(Net.Actions.ClaimQuest, { period = period, index = quest.index }, button)
		end, { BackgroundColor3 = Theme.Colors.Gold })
	else
		button = UIKit.button("Claim", function() end, { BackgroundColor3 = Theme.Colors.Gold })
		UIKit.setEnabled(button, false, Theme.Colors.Gold, "Finish the quest first!")
	end
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.fromOffset(130, 48)
	button.Parent = row
end

---------------------------------------------------------------------------
-- Star track
---------------------------------------------------------------------------

local function starTrack(parent: Instance, rewards: { [string]: any }, order: number)
	local track = REWARDS.starTrack
	local last = track[#track].stars
	local card = UIKit.card({
		Name = "StarTrack",
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 170),
		BackgroundColor3 = Theme.Colors.SurfaceAlt,
		Parent = parent,
	})
	local title = UIKit.label(string.format("Stars this week: %d", rewards.stars or 0), Theme.TextSize.Large, {
		Position = UDim2.fromOffset(16, 10),
		TextColor3 = Theme.Colors.Gold,
		Parent = card,
	})
	UIKit.outlineText(title, 2)
	local starIcon = Icons.make("Star", 30)
	starIcon.AnchorPoint = Vector2.new(1, 0)
	starIcon.Position = UDim2.new(1, -14, 0, 8)
	starIcon.Parent = card
	UIKit.label(countdown(rewards.weekEndsAt), Theme.TextSize.Small, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -50, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.TextMuted,
		Font = Theme.FontBody,
		Parent = card,
	})

	-- The bar runs under the chests; each chest sits at its star count.
	local lane = UIKit.new("Frame", {
		Name = "Lane",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 40, 0, 52),
		Size = UDim2.new(1, -80, 0, 108),
		Parent = card,
	})
	bar(lane, (rewards.stars or 0) / last, Theme.Colors.Gold, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 18),
	})
	for i, chest in track do
		local x = chest.stars / last
		local opened = rewards.opened and rewards.opened[tostring(i)]
		local ready = not opened and (rewards.stars or 0) >= chest.stars
		local holder = UIKit.new("Frame", {
			Name = "Chest" .. i,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.fromOffset(if chest.big then 84 else 70, 108),
			Parent = lane,
		})
		local button: TextButton
		button = UIKit.button("", function()
			if ready then
				claim(Net.Actions.ClaimChest, { index = i }, button)
			end
		end, {
			Name = "Open",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(if chest.big then 76 else 62, if chest.big then 76 else 62),
			BackgroundColor3 = if ready then Theme.Colors.Gold elseif opened then Theme.Colors.PrimaryDark else Theme.Colors.Surface,
			Parent = holder,
		})
		if not ready then
			UIKit.setEnabled(
				button,
				false,
				if opened then Theme.Colors.PrimaryDark else Theme.Colors.Surface,
				if opened then "Already opened!" else string.format("Get %d stars to open this chest!", chest.stars)
			)
		else
			UIKit.sweep(button)
		end
		local icon = Icons.make(if opened then "Success" elseif chest.big then "Gift" else "Box", if chest.big then 48 else 38)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 4
		icon.Parent = button
		local need = UIKit.label(tostring(chest.stars) .. " Stars", Theme.TextSize.Small, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, if chest.big then 80 else 66),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if ready then Theme.Colors.Gold else Theme.Colors.TextOnPrimary,
			Parent = holder,
		})
		UIKit.outlineText(need, 2)
	end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

function QuestsPanel.render(body: ScrollingFrame, data: { [string]: any }, tab: string?)
	local rewards = data.rewards
	if not rewards then
		UIKit.label("Loading quests...", Theme.TextSize.Body, { LayoutOrder = 1, Font = Theme.FontBody }).Parent = body
		return
	end
	if tab == "weekly" then
		starTrack(body, rewards, 1)
		UIKit.section("Weekly Quests", 2, body)
		for i, quest in rewards.weekly or {} do
			questRow(quest, "weekly", 2 + i, body)
		end
		UIKit.label(countdown(rewards.weekEndsAt), Theme.TextSize.Small, {
			LayoutOrder = 20,
			Font = Theme.FontBody,
			TextColor3 = Theme.Colors.TextMuted,
		}).Parent = body
		return
	end

	local streak = rewards.streak or {}
	local heading = if streak.ready
		then (if streak.broken then "Daily Reward: a fresh start!" else "Daily Reward: claim Day " .. tostring(streak.day))
		else "Daily Reward: come back tomorrow for Day " .. tostring((streak.day % #REWARDS.streak.days) + 1)
	UIKit.section(heading, 1, body)
	streakStrip(body, streak, 2)
	if streak.ready then
		local claimButton: TextButton
		claimButton = UIKit.keyButton("Claim Day " .. tostring(streak.day) .. "!", function()
			claim(Net.Actions.ClaimStreak, nil, claimButton)
		end, { LayoutOrder = 3, Size = UDim2.fromOffset(240, 52), BackgroundColor3 = Theme.Colors.Gold })
		claimButton.Parent = body
	end
	UIKit.section("Daily Quests", 4, body)
	for i, quest in rewards.daily or {} do
		questRow(quest, "daily", 4 + i, body)
	end
	UIKit.label(countdown(rewards.dayEndsAt), Theme.TextSize.Small, {
		LayoutOrder = 20,
		Font = Theme.FontBody,
		TextColor3 = Theme.Colors.TextMuted,
	}).Parent = body
end

---------------------------------------------------------------------------
-- Login card
---------------------------------------------------------------------------

-- The card that greets you when today's reward is waiting.
function QuestsPanel.showStreak(data: { [string]: any })
	local streak = data.rewards and data.rewards.streak
	if not streak or not streak.ready then
		return
	end
	local days = REWARDS.streak.days
	local reward = days[streak.day] or days[1]
	local lines = {
		if streak.broken
			then "Welcome back! Your streak starts again today."
			elseif streak.day == #days then "Day " .. streak.day .. " in a row. The BIG reward is here!"
			else "Day " .. streak.day .. " in a row. Come back tomorrow for even more!",
		"Today: " .. QuestsPanel.describe(reward),
	}
	Modal.show({
		title = "Daily Reward!",
		accent = Theme.Colors.Gold,
		lines = lines,
		build = function(holder)
			holder.Size = UDim2.new(1, 0, 0, 0)
			-- Seven tiles must fit the modal card (Theme.Size.ModalWidth).
			streakStrip(holder, streak, 1, 46)
		end,
		buttons = {
			{
				text = "Claim!",
				color = Theme.Colors.Gold,
				onClick = function()
					task.spawn(NetClient.request, Net.Actions.ClaimStreak)
				end,
			},
		},
	})
end

return QuestsPanel
