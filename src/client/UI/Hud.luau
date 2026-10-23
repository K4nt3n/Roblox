--!strict
--[[
	Hud: the always-on screen. Built once, then updated in place (no
	rebuilds, so nothing jumps or loses its hover state).

	  Bottom left  stacked: gem pill (premium currency, "Soon" for now) on top,
	               coin pill (rolls up, coins fly into it on a sale), then the player
	               card (avatar, name, level badge + XP bar filled by essence via LevelBar)
	  Left         2x2 icon grid with badges: Backpack (seeds, supplies + tools, ribbons;
	               badge = new ribbons), Upgrades, Fairs (fair waiting for an entry),
	               Champion (needs care)
	  Top right    Settings icon
	  Top center   travel buttons: My Garden (your plot) and Shops (Seed Shop, Sell, Fair)
	Seeds and supplies are bought and veggies sold at the stands in the middle, not from the HUD.
	  Bottom       seed hotbar (selected seed lifts up)
	  Top center   toasts, under the travel buttons (own ScreenGui above panels and modals)

	Fly-to targets for effects (harvest -> basket in G4, coins, essence):
	    Hud.target("Coins" | "Level" | "Backpack" | "Upgrades" | "Fair" | "Champion" | "Settings" | "Seeds")

	Art slots: CoinIcon, LevelIcon, Menu<Panel>, Seed_<cropId> (see Theme.Art).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)
local Scale = require(script.Parent.Scale)
local Counter = require(script.Parent.Counter)
local Toasts = require(script.Parent.Toasts)
local LevelBar = require(script.Parent.LevelBar)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local EssenceFX = require(script.Parent.Parent.Feel.EssenceFX)

local Icons = require(script.Parent.Icons)
local ToolBar = require(script.Parent.ToolBar)
local Teleport = require(script.Parent.Parent.Controllers.Teleport)

local Hud = {}

export type NavEntry = { id: string, panel: string, tab: string?, icon: string, color: Color3 }

-- Left icon grid, filled row by row (2 per row). `tab` opens that tab of the panel.
Hud.NAV = {
	{ id = "Backpack", panel = "Backpack", icon = "Backpack", color = Theme.Colors.Slate },
	{ id = "Upgrades", panel = "Upgrades", icon = "Upgrades", color = Theme.Colors.Purple },
	{ id = "Fair", panel = "Fair", icon = "Trophy", color = Theme.Colors.Gold },
	{ id = "Champion", panel = "Champion", icon = "Crown", color = Theme.Colors.Danger },
} :: { NavEntry }

-- Top right icon.
Hud.SETTINGS = { id = "Settings", panel = "Settings", icon = "Settings", color = Theme.Colors.Gold } :: NavEntry

-- Top travel buttons.
Hud.TRAVEL = {
	{ id = "Garden", text = "My Garden", icon = "Home", color = Theme.Colors.Primary, go = Teleport.toGarden },
	{ id = "Shops", text = "Shops", icon = "Shop", color = Theme.Colors.Danger, go = Teleport.toShops },
}

local root: Frame
local coinPill: Frame
local coinCounter: Counter.Counter
local levelPill: Frame
local gemPill: Frame
local nav: Frame
local travel: Frame
local navButtons: { [string]: TextButton } = {}
local settingsHolder: Frame
local seedScroller: ScrollingFrame
local seedDock: Frame
local menuBadges: { [string]: Frame } = {}
local seedSlots: { [string]: { holder: Frame, button: TextButton, count: TextLabel, edge: UIStroke, shadow: Frame?, selected: boolean } } =
	{}

local coinPending: number? = nil
-- True while a garden tool is in hand: the seed highlight dims so only one thing is active.
local toolActive = false
local lastData: { [string]: any }? = nil
local dockHidden = false

local NAV_GAP = 8
local STATS_WIDTH = Theme.Size.PillWidth + 20
local STATS_HEIGHT = 172

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

local function rgb(values: { number }?): Color3
	if not values then
		return Theme.Colors.SurfaceAlt
	end
	return Color3.fromRGB(values[1], values[2], values[3])
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function buildStats()
	local stats = UIKit.new("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -14),
		Size = UDim2.fromOffset(STATS_WIDTH, STATS_HEIGHT),
		Parent = root,
	})

	-- Coins: a pill with the icon slot hanging off its left edge.
	coinPill = UIKit.new("Frame", {
		Name = "Coins",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 52),
		Size = UDim2.fromOffset(Theme.Size.PillWidth - 18, 44),
		ZIndex = 2,
		Parent = stats,
	}, { UIKit.corner(Theme.CornerRound) })
	UIKit.paint(coinPill, Theme.Colors.Primary)
	UIKit.outline(coinPill)
	UIKit.gloss(coinPill)
	UIKit.shadow(coinPill)
	ArtSlot.icon("CoinIcon", {
		size = 54,
		round = true,
		color = Theme.Colors.Primary,
		glyph = "C",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0, 0, 0.5, 0),
		zIndex = 3,
	}).Parent =
		coinPill
	local coinsLabel = UIKit.label("0", Theme.TextSize.Large + 4, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 36, 0.5, 0),
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 3,
		Parent = coinPill,
	})
	UIKit.outlineText(coinsLabel, Theme.Style.TitleOutline)
	coinCounter = Counter.new(coinsLabel, function(n)
		return Format.coins(math.floor(n + 0.5))
	end, {
		popTarget = coinPill,
		floatParent = coinPill,
		gainColor = Theme.Colors.Gold,
		tick = "CoinTick",
	})
	-- Gems: premium currency. Not in the game yet, so the pill says "Soon" and has no + button.
	gemPill = UIKit.new("Frame", {
		Name = "Gems",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 4),
		Size = UDim2.fromOffset(Theme.Size.PillWidth - 60, 38),
		ZIndex = 2,
		Parent = stats,
	}, { UIKit.corner(Theme.CornerRound) })
	UIKit.paint(gemPill, Theme.Colors.Purple)
	UIKit.outline(gemPill)
	UIKit.shadow(gemPill)
	gemPill:SetAttribute("NotConnected", "Gems are not in the game yet")
	ArtSlot.icon("GemIcon", {
		size = 44,
		round = true,
		color = Theme.Colors.Purple,
		glyph = "G",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0, 0, 0.5, 0),
		zIndex = 3,
	}).Parent =
		gemPill
	local soon = UIKit.label("Soon", Theme.TextSize.Body, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 32, 0.5, 0),
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 3,
		Parent = gemPill,
	})
	UIKit.outlineText(soon, 2)
	gemPill.BackgroundTransparency = 0.25

	-- Player card: avatar, name, level badge and the XP bar.
	levelPill = UIKit.new("Frame", {
		Name = "Level",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 106),
		Size = UDim2.fromOffset(Theme.Size.PillWidth + 12, 60),
		ZIndex = 2,
		Parent = stats,
	}, { UIKit.corner(UDim.new(0, 16)) })
	UIKit.paint(levelPill, Theme.Colors.Chip)
	UIKit.outline(levelPill)
	UIKit.shadow(levelPill)
	local avatar = UIKit.new("ImageLabel", {
		Name = "Avatar",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = Theme.lighten(Theme.Colors.Chip, 0.25),
		Image = "",
		ZIndex = 3,
		Parent = levelPill,
	}, { UIKit.corner(Theme.CornerRound), UIKit.stroke(Theme.Colors.TextOnPrimary, 2) })
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				Players.LocalPlayer.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if ok then
			avatar.Image = image
		end
	end)
	local nameLabel = UIKit.label(Players.LocalPlayer.DisplayName, Theme.TextSize.Body, {
		Name = "PlayerName",
		Position = UDim2.fromOffset(62, 5),
		Size = UDim2.new(1, -110, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 3,
		Parent = levelPill,
	})
	UIKit.outlineText(nameLabel, 2)
	-- Level number in a gold star badge on the right.
	local badge = ArtSlot.icon("LevelIcon", {
		size = 42,
		round = true,
		color = Theme.Colors.Gold,
		glyph = "",
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -6, 0.5, 0),
		zIndex = 3,
	})
	badge.Parent = levelPill
	local levelNumber = UIKit.label("1", Theme.TextSize.Large, {
		Name = "LevelNumber",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 4,
		Parent = badge,
	})
	UIKit.outlineText(levelNumber, Theme.Style.TitleOutline)
	local track = UIKit.new("Frame", {
		Name = "Track",
		BackgroundColor3 = Theme.darken(Theme.Style.Outline, 0.3),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(62, 30),
		Size = UDim2.new(1, -116, 0, 22),
		ClipsDescendants = true,
		Parent = levelPill,
	}, { UIKit.corner(Theme.CornerRound) })
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}, { UIKit.corner(Theme.CornerRound) })
	UIKit.paint(fill, Theme.Colors.Primary)
	UIKit.gloss(fill)
	local xpLabel = UIKit.label("", Theme.TextSize.Small, {
		Name = "Xp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 4,
		Parent = track,
	})
	UIKit.outlineText(xpLabel, 2)
	LevelBar.mount(levelPill, fill, xpLabel, levelNumber)
end

-- Reference-style rectangle buttons: colour + icon square + bold outlined text.
local travelHolders: { Frame } = {}
-- Square icon-only buttons (left grid and settings).
local iconHolders: { Frame } = {}

-- The action button look with only the icon, centred.
local function iconButton(entry: NavEntry, onMenu: (panel: string, tab: string?) -> ()): (Frame, TextButton)
	local size = Theme.Size.IconButton
	local holder, button = UIKit.actionButton("", entry.icon, entry.color, function()
		onMenu(entry.panel, entry.tab)
	end, Vector2.new(size, size))
	holder.Name = entry.id
	local tile = button:FindFirstChild("IconTile") :: Frame?
	if tile then
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Position = UDim2.fromScale(0.5, 0.5)
		tile.BackgroundTransparency = 1
	end
	navButtons[entry.id] = button
	menuBadges[entry.panel] = UIKit.badge(button)
	table.insert(iconHolders, holder)
	return holder, button
end

-- Left side: Backpack, Upgrades, Fairs, Champion as a 2x2 grid of icons.
local function buildNav(onMenu: (panel: string, tab: string?) -> ())
	local size = Theme.Size.IconButton
	nav = UIKit.new("Frame", {
		Name = "Nav",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, -40),
		Size = UDim2.fromOffset(size * 2 + NAV_GAP, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	}, {
		UIKit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(size, size + 5),
			CellPadding = UDim2.fromOffset(NAV_GAP, NAV_GAP),
			FillDirectionMaxCells = 2,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, entry in Hud.NAV do
		local holder = iconButton(entry, onMenu)
		holder.LayoutOrder = i
		holder.Parent = nav
	end
end

-- Top right: the Settings icon.
local function buildSettings(onMenu: (panel: string, tab: string?) -> ())
	settingsHolder = iconButton(Hud.SETTINGS, onMenu)
	settingsHolder.AnchorPoint = Vector2.new(1, 0)
	settingsHolder.Position = UDim2.new(1, -16, 0, 14)
	settingsHolder.Parent = root
end

-- Top center: teleport to your own garden, or to the stands in the middle.
local function buildTravel()
	travel = UIKit.new("Frame", {
		Name = "Travel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = root,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	for i, entry in Hud.TRAVEL do
		local holder, button = UIKit.actionButton(entry.text, entry.icon, entry.color, entry.go)
		holder.Name = entry.id
		holder.LayoutOrder = i
		holder.Parent = travel
		navButtons[entry.id] = button
		table.insert(travelHolders, holder)
	end
end

local function buildSeedDock()
	seedDock = UIKit.new("Frame", {
		Name = "SeedDock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(600, 96),
		Parent = root,
	})
	seedScroller = UIKit.new("ScrollingFrame", {
		Name = "Seeds",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ElasticBehavior = Enum.ElasticBehavior.Always,
		Selectable = false,
		Parent = seedDock,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	local layout = seedScroller:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
end

local function layoutForDevice()
	local phone = Scale.isPhone()
	local buttonSize = if phone then Theme.Size.ActionButtonPhone else Theme.Size.ActionButton
	local textSize = if phone then Theme.TextSize.Body - 2 else Theme.TextSize.Large - 2
	for _, holder in travelHolders do
		UIKit.setActionSize(holder, buttonSize, textSize)
	end
	local icon = if phone then Theme.Size.IconButtonPhone else Theme.Size.IconButton
	for _, holder in iconHolders do
		UIKit.setActionSize(holder, Vector2.new(icon, icon))
	end
	nav.Size = UDim2.fromOffset(icon * 2 + NAV_GAP, 0)
	local grid = nav:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(icon, icon + 5)
	end
	local slotSize = if phone then Theme.Size.SeedSlotPhone else Theme.Size.SeedSlot
	ToolBar.resize(slotSize)
	for _, slot in seedSlots do
		slot.holder.Size = UDim2.fromOffset(slotSize, slotSize + 12)
		slot.button.Size = UDim2.fromOffset(slotSize, slotSize)
		if slot.shadow then
			slot.shadow.Size = slot.button.Size
		end
	end
	-- Keep the hotbar clear of the stats in the corner and, on touch screens, the thumbstick and jump button.
	local rootWidth = root.AbsoluteSize.X / math.max(Scale.value, 0.01)
	local margin = if phone then 170 else (STATS_WIDTH + 32) * 2
	seedDock.Size = UDim2.fromOffset(math.max(240, rootWidth - margin), slotSize + 20)
end

---------------------------------------------------------------------------
-- Seed hotbar (keyed, updated in place)
---------------------------------------------------------------------------

local function setSlotSelected(cropId: string, selected: boolean)
	local slot = seedSlots[cropId]
	if not slot or slot.selected == selected then
		return
	end
	slot.selected = selected
	Tweens.play(slot.button, Tweens.Ease.PanelIn, {
		Position = UDim2.new(0.5, 0, 1, if selected then -16 else -6),
	})
	Tweens.play(slot.edge, Tweens.Ease.Hover, {
		Color = if selected then Theme.Colors.Gold else Theme.Style.Outline,
		Thickness = if selected then 5 else Theme.Style.OutlineThickness,
	})
	UIKit.paint(slot.button, if selected then Theme.darken(Theme.Colors.Gold, 0.15) else Theme.Colors.Surface)
	if selected then
		Tweens.pop(slot.button, 0.12)
		Tweens.flash(slot.button, Theme.Style.Flash, 0.3)
	end
end

local function makeSeedSlot(crop: any, order: number, onSelect: (cropId: string) -> ())
	local size = if Scale.isPhone() then Theme.Size.SeedSlotPhone else Theme.Size.SeedSlot
	local holder = UIKit.new("Frame", {
		Name = crop.id,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size, size + 12),
		Visible = false,
		Parent = seedScroller,
	})
	local button = UIKit.button("", function()
		onSelect(crop.id)
	end, {
		Name = "Slot",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.Surface,
		Parent = holder,
	})
	local edge = button:FindFirstChild("Edge") :: UIStroke
	local shadow = UIKit.shadow(button)
	ArtSlot.icon("Seed_" .. crop.id, {
		size = 40,
		round = true,
		color = rgb(crop.placeholderColor),
		glyph = string.sub(crop.displayName, 1, 1),
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 8),
		zIndex = 3,
	}).Parent =
		button
	UIKit.label(crop.displayName, 13, {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = button,
	})
	local countBadge = UIKit.badge(button, Theme.Colors.PrimaryDark)
	seedSlots[crop.id] = {
		holder = holder,
		button = button,
		count = countBadge:FindFirstChild("Count") :: TextLabel,
		edge = edge,
		shadow = shadow,
		selected = false,
	}
end

local function renderSeeds(data: { [string]: any })
	for _, crop in cropOrder() do
		local slot = seedSlots[crop.id]
		if not slot then
			continue
		end
		local count = data.seeds[crop.id] or 0
		local visible = data.level >= crop.unlockLevel and (count > 0 or crop.seedCost == 0)
		if visible and not slot.holder.Visible then
			slot.holder.Visible = true
			Tweens.pop(slot.button, 0.3)
		elseif not visible and slot.holder.Visible then
			slot.holder.Visible = false
		end
		local badge = slot.count.Parent :: Frame
		if crop.seedCost == 0 then
			UIKit.setBadge(badge, false)
		else
			UIKit.setBadge(badge, count)
		end
		setSlotSelected(crop.id, data.selectedSeed == crop.id and not toolActive)
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function Hud.build(playerGui: Instance, onMenu: (panel: string, tab: string?) -> (), onSeed: (cropId: string) -> ())
	local gui = UIKit.new("ScreenGui", {
		Name = "GVF_UI",
		ResetOnSpawn = false,
		DisplayOrder = Theme.Layer.Hud,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	root = Scale.root(gui, "Hud")

	local toastGui = UIKit.new("ScreenGui", {
		Name = "GVF_Toasts",
		ResetOnSpawn = false,
		DisplayOrder = Theme.Layer.Toasts,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	Toasts.mount(Scale.root(toastGui, "Toasts"))

	buildStats()
	buildNav(onMenu)
	buildSettings(onMenu)
	buildTravel()
	buildSeedDock()
	-- Picking a seed puts any garden tool away.
	local function selectSeed(cropId: string)
		ToolBar.unequip()
		onSeed(cropId)
	end
	for i, crop in cropOrder() do
		makeSeedSlot(crop, i, selectSeed)
	end
	ToolBar.mount(seedScroller)
	ToolBar.Changed:Connect(function(toolId)
		toolActive = toolId ~= nil
		if lastData then
			renderSeeds(lastData)
		end
	end)
	layoutForDevice()
	Scale.Changed:Connect(layoutForDevice)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutForDevice)
end

function Hud.render(data: { [string]: any })
	lastData = data
	ToolBar.render(data)
	Hud.setCoins(data.coins)
	LevelBar.setTarget(data.level, data.xp, data.xpToNext or 1)
	renderSeeds(data)
end

-- Coins from the server. Held back while coins are still flying in.
function Hud.setCoins(value: number)
	if EssenceFX.active("coins") > 0 then
		coinPending = value
	else
		coinCounter:set(value)
	end
end

--[[
	Coins fly from `from` (screen point, world point or nil) into the coin
	pill; the counter ticks up as each one lands.
]]
function Hud.coinBurst(amount: number, from: Vector3 | Vector2 | nil)
	if amount <= 0 then
		return
	end
	local count = math.clamp(math.floor(math.log10(amount + 1) * 3) + 3, 4, 14)
	local base = coinCounter.value
	coinCounter:float(amount)
	EssenceFX.burst(from, coinPill, count, function(index, total)
		Tweens.pop(coinPill, 0.05)
		Tweens.flash(coinPill, Theme.Style.Flash, 0.6, 0.18)
		coinCounter:step(base + amount * index / total)
	end, function()
		if EssenceFX.active("coins") == 0 then
			Tweens.pop(coinPill, 0.14)
			Tweens.flash(coinPill, Theme.Style.Flash, Theme.Style.FlashStrength)
			local truth = coinPending
			coinPending = nil
			if truth then
				coinCounter:step(truth)
			end
		end
	end, { tag = "coins", color = Theme.Colors.Gold, glow = Theme.Colors.CoinGlow })
end

-- Reward moment on a HUD element: a bouncy pop and a bright flash.
function Hud.celebrate(name: string, color: Color3?, strength: number?)
	local target = Hud.target(name)
	if target then
		Tweens.pop(target, strength or 0.18)
		Tweens.flash(target, color or Theme.Style.Flash, Theme.Style.FlashStrength)
	end
end

function Hud.setBadge(panel: string, value: number | boolean | nil)
	local badge = menuBadges[panel]
	if badge then
		UIKit.setBadge(badge, value)
	end
end

function Hud.target(name: string): GuiObject?
	if name == "Coins" then
		return coinPill
	elseif name == "Level" then
		return levelPill
	elseif name == "Seeds" then
		return seedDock
	elseif name == "Gems" then
		return gemPill
	end
	return navButtons[name]
end

-- Slides the seed hotbar away while a panel is open, so the panel has the stage.
function Hud.setDockHidden(hidden: boolean)
	if dockHidden == hidden then
		return
	end
	dockHidden = hidden
	Tweens.play(seedDock, if hidden then Tweens.Ease.PanelOut else Tweens.Ease.PanelIn, {
		Position = UDim2.new(0.5, 0, 1, if hidden then 140 else -10),
	})
end

function Hud.menuButton(panel: string): TextButton?
	return navButtons[panel]
end

return Hud
