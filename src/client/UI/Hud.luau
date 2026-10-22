--!strict
--[[
	Hud: the always-on screen. Built once, then updated in place (no
	rebuilds, so nothing jumps or loses its hover state).

	  Top left     coin pill (rolls up, coins fly into it on a sale)
	               level pill (badge + XP bar, filled by essence via LevelBar)
	  Right        menu buttons with badges (basket count, champion needs care,
	               fair waiting for an entry, new ribbons)
	  Bottom       seed hotbar (selected seed lifts up)
	  Top center   toasts (own ScreenGui above panels and modals)

	Fly-to targets for effects (harvest -> basket in G4, coins, essence):
	    Hud.target("Coins" | "Level" | "Market" | "Shop" | "Fair" | "Champion" | "Ribbons" | "Seeds")

	Art slots: CoinIcon, LevelIcon, Menu<Panel>, Seed_<cropId> (see Theme.Art).
]]

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

local Hud = {}

export type MenuEntry = { panel: string, text: string, glyph: string }

Hud.MENU = {
	{ panel = "Shop", text = "Shop", glyph = "S" },
	{ panel = "Market", text = "Basket", glyph = "B" },
	{ panel = "Fair", text = "Fairs", glyph = "F" },
	{ panel = "Champion", text = "Champion", glyph = "C" },
	{ panel = "Ribbons", text = "Ribbons", glyph = "R" },
} :: { MenuEntry }

local root: Frame
local coinPill: Frame
local coinCounter: Counter.Counter
local levelPill: Frame
local menu: Frame
local seedScroller: ScrollingFrame
local seedDock: Frame
local menuButtons: { [string]: TextButton } = {}
local menuBadges: { [string]: Frame } = {}
local seedSlots: { [string]: { holder: Frame, button: TextButton, count: TextLabel, edge: UIStroke, shadow: Frame?, selected: boolean } } =
	{}

local coinPending: number? = nil
local dockHidden = false

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
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.fromOffset(Theme.Size.PillWidth + 20, 110),
		Parent = root,
	})

	-- Coins: a pill with the icon slot hanging off its left edge.
	coinPill = UIKit.new("Frame", {
		Name = "Coins",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 4),
		Size = UDim2.fromOffset(Theme.Size.PillWidth - 18, 44),
		ZIndex = 2,
		Parent = stats,
	}, { UIKit.corner(Theme.CornerRound) })
	UIKit.paint(coinPill, Theme.Colors.Gold)
	UIKit.outline(coinPill)
	UIKit.gloss(coinPill)
	UIKit.shadow(coinPill)
	ArtSlot.icon("CoinIcon", {
		size = 54,
		round = true,
		color = Theme.Colors.Gold,
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

	-- Level: a badge with the number, and the XP bar.
	levelPill = UIKit.new("Frame", {
		Name = "Level",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 60),
		Size = UDim2.fromOffset(Theme.Size.PillWidth - 18, 36),
		ZIndex = 2,
		Parent = stats,
	}, { UIKit.corner(Theme.CornerRound) })
	UIKit.paint(levelPill, Theme.lighten(Theme.Style.Outline, 0.18))
	UIKit.outline(levelPill)
	UIKit.shadow(levelPill)
	local badge = ArtSlot.icon("LevelIcon", {
		size = 46,
		round = true,
		color = Theme.Colors.Primary,
		glyph = "",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0, 0, 0.5, 0),
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
		Position = UDim2.fromOffset(30, 6),
		Size = UDim2.new(1, -37, 1, -12),
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

local function buildMenu(onMenu: (panel: string) -> ())
	menu = UIKit.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(Theme.Size.MenuButton, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	}, { UIKit.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right) })
	for i, entry in Hud.MENU do
		local accent = Theme.PanelAccent[entry.panel] or Theme.Colors.Primary
		local button = UIKit.button("", function()
			onMenu(entry.panel)
		end, {
			Name = entry.panel,
			LayoutOrder = i,
			Size = UDim2.fromOffset(Theme.Size.MenuButton, Theme.Size.MenuButton),
			BackgroundColor3 = accent,
		})
		local corner = button:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, 18)
		end
		ArtSlot.icon("Menu" .. entry.panel, {
			size = 38,
			color = Theme.lighten(accent, 0.35),
			glyph = entry.glyph,
			anchor = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, 6),
			zIndex = 3,
		}).Parent =
			button
		local caption = UIKit.label(entry.text, 14, {
			Name = "Caption",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.Colors.TextOnPrimary,
			ZIndex = 3,
			Parent = button,
		})
		UIKit.outlineText(caption, 2)
		button.Parent = menu
		menuButtons[entry.panel] = button
		menuBadges[entry.panel] = UIKit.badge(button)
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
	local menuSize = if phone then Theme.Size.MenuButtonPhone else Theme.Size.MenuButton
	menu.Size = UDim2.fromOffset(menuSize, 0)
	for _, button in menuButtons do
		button.Size = UDim2.fromOffset(menuSize, menuSize)
		local caption = button:FindFirstChild("Caption") :: TextLabel?
		if caption then
			caption.TextSize = if phone then 12 else 14
		end
	end
	local slotSize = if phone then Theme.Size.SeedSlotPhone else Theme.Size.SeedSlot
	for _, slot in seedSlots do
		slot.holder.Size = UDim2.fromOffset(slotSize, slotSize + 12)
		slot.button.Size = UDim2.fromOffset(slotSize, slotSize)
		if slot.shadow then
			slot.shadow.Size = slot.button.Size
		end
	end
	-- Keep the hotbar clear of the menu and, on touch screens, the thumbstick and jump button.
	local rootWidth = root.AbsoluteSize.X / math.max(Scale.value, 0.01)
	local margin = if phone then 170 else (menuSize + 48) * 2
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
	UIKit.paint(slot.button, if selected then Theme.lighten(Theme.Colors.Gold, 0.65) else Theme.Colors.Surface)
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
		setSlotSelected(crop.id, data.selectedSeed == crop.id)
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function Hud.build(playerGui: Instance, onMenu: (panel: string) -> (), onSeed: (cropId: string) -> ())
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
	buildMenu(onMenu)
	buildSeedDock()
	for i, crop in cropOrder() do
		makeSeedSlot(crop, i, onSeed)
	end
	layoutForDevice()
	Scale.Changed:Connect(layoutForDevice)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutForDevice)
end

function Hud.render(data: { [string]: any })
	Hud.setCoins(data.coins)
	LevelBar.setTarget(data.level, data.xp, data.xpToNext or 1)
	renderSeeds(data)
	UIKit.setBadge(menuBadges.Market, #(data.produce or {}))
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
	end
	return menuButtons[name]
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
	return menuButtons[panel]
end

return Hud
