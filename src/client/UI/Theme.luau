--!strict
--[[
	Theme: design tokens for all placeholder UI. Restyle the whole game from
	here, or swap UIKit builders for art-backed ones later. Soft, rounded,
	high-contrast, kid friendly.

	Sizes are in design pixels at a 1280x720 reference screen. UI/Scale turns
	them into real pixels per device, so never scale by hand.

	Art seam: every icon, panel frame and button face Peter draws plugs into
	Theme.Art below. Empty means the flat placeholder shape is drawn.

	Look: bright candy colors, top-to-bottom gradients, thick dark outlines,
	white text with a dark outline, a glossy strip on buttons and a shine
	that sweeps across the important ones. All of it is tuned in Theme.Style.
]]

local Theme = {}

-- Candy palette: saturated, bright, and readable under a dark outline.
-- Panels, cards and HUD tiles are dark navy with a light border (reference UI kit).
Theme.Colors = {
	Background = Color3.fromRGB(28, 36, 60),
	Surface = Color3.fromRGB(42, 54, 86),
	SurfaceAlt = Color3.fromRGB(32, 42, 70),
	Primary = Color3.fromRGB(70, 220, 85),
	PrimaryDark = Color3.fromRGB(30, 165, 70),
	Accent = Color3.fromRGB(255, 140, 25),
	Danger = Color3.fromRGB(255, 70, 95),
	Gold = Color3.fromRGB(255, 205, 25),
	Info = Color3.fromRGB(40, 170, 255),
	Purple = Color3.fromRGB(170, 90, 255),
	Pink = Color3.fromRGB(255, 95, 190),
	-- Dark chips: round nav buttons (reference UI kit).
	Chip = Color3.fromRGB(40, 52, 84),
	-- Slate grey-blue (reference Home / Back buttons).
	Slate = Color3.fromRGB(120, 140, 178),
	Text = Color3.fromRGB(246, 248, 255),
	TextMuted = Color3.fromRGB(170, 182, 210),
	TextOnPrimary = Color3.fromRGB(255, 255, 255),
	Stroke = Color3.fromRGB(32, 24, 52),
	Disabled = Color3.fromRGB(96, 106, 132),
	DisabledText = Color3.fromRGB(200, 205, 220),
	Backdrop = Color3.fromRGB(20, 12, 40),
	Essence = Color3.fromRGB(150, 235, 120),
	EssenceGlow = Color3.fromRGB(255, 245, 160),
	CoinGlow = Color3.fromRGB(255, 240, 170),
}

-- One accent per panel so each screen is recognisable at a glance.
Theme.PanelAccent = {
	Shop = Theme.Colors.Danger,
	Market = Theme.Colors.Accent,
	Fair = Theme.Colors.Gold,
	Champion = Theme.Colors.Purple,
	Ribbons = Theme.Colors.Info,
	Backpack = Theme.Colors.Info,
	Tools = Theme.Colors.Info,
	Upgrades = Theme.Colors.Purple,
	Settings = Theme.Colors.Gold,
}

--[[
	Style: the "big Roblox game" finish. Everything visual that is code (not
	art) is tuned here: outlines, gradients, gloss, shadows, shine sweeps.
]]
Theme.Style = {
	-- Thick dark outline around buttons, pills and panels.
	Outline = Color3.fromRGB(32, 24, 52),
	OutlineThickness = 3,
	PanelOutlineThickness = 4,
	-- Cards and tiles on the dark panels get a thin light border.
	CardOutline = Color3.fromRGB(88, 106, 150),
	CardOutlineTransparency = 0,
	-- Ring around the round nav buttons.
	NavRing = Color3.fromRGB(110, 130, 175),
	-- White text with a dark outline on anything colored.
	TextOutline = 2.5,
	TitleOutline = 3.5,
	-- Gradient: how much lighter the top and darker the bottom edge are.
	GradientLight = 0.38,
	GradientDark = 0.22,
	-- Glossy strip across the top half of buttons.
	Gloss = true,
	GlossTransparency = 0.5,
	-- Drop shadow under HUD pills, slots and toasts.
	ShadowColor = Color3.fromRGB(20, 10, 45),
	ShadowTransparency = 0.6,
	ShadowOffset = 5,
	-- Shine sweep on key buttons: seconds between sweeps, and sweep time.
	ShineEvery = { 2.2, 4.2 },
	ShineTime = 0.65,
	ShineTransparency = 0.35,
	-- Reward flash: overlay color and how strong it starts.
	Flash = Color3.fromRGB(255, 255, 255),
	FlashStrength = 0.15,
}

-- Two fonts: a chunky display font for titles, buttons and numbers, and a soft
-- rounded font for longer body text (drawn bold, see UIKit.weigh).
Theme.Font = Enum.Font.LuckiestGuy
Theme.FontBody = Enum.Font.Nunito
Theme.FontBodyWeight = Enum.FontWeight.Bold

Theme.Corner = UDim.new(0, 14)
Theme.CornerSmall = UDim.new(0, 10)
Theme.CornerRound = UDim.new(1, 0)
Theme.StrokeThickness = 2.5
Theme.Padding = 10

Theme.Space = {
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
}

Theme.TextSize = {
	Huge = 40,
	Title = 30,
	Large = 24,
	Body = 18,
	Small = 14,
}

-- Fixed design sizes. 44 is the smallest comfortable touch target after scaling.
Theme.Size = {
	Touch = 44,
	RowHeight = 68,
	RowButton = Vector2.new(112, 44),
	MenuButton = 72,
	MenuButtonPhone = 60,
	NavButton = 58,
	NavButtonPhone = 46,
	ItemCard = Vector2.new(148, 186),
	-- Reference-style rectangle buttons (HUD nav and menu).
	ActionButton = Vector2.new(158, 50),
	ActionButtonPhone = Vector2.new(124, 40),
	-- Square icon-only HUD buttons (left grid, settings).
	IconButton = 64,
	IconButtonPhone = 50,
	-- Wide left-side HUD buttons (Backpack, Upgrades, Fairs, Champion).
	SideButton = Vector2.new(190, 54),
	SideButtonPhone = Vector2.new(140, 42),
	-- Hotbar slots (seeds and garden tools).
	SeedSlot = 62,
	SeedSlotPhone = 52,
	-- Room above a hotbar slot for its badge and the lift when selected, so nothing is clipped.
	SlotHeadroom = 22,
	SlotLift = 8,
	PillWidth = 220,
	PanelMax = Vector2.new(700, 540),
	ModalWidth = 440,
	ToastWidth = 520,
}

-- ScreenGui DisplayOrder per layer, lowest first.
Theme.Layer = {
	Hud = 0,
	FairDay = 10,
	Panels = 15,
	Modal = 20,
	Toasts = 30,
	Essence = 50,
}

--[[
	Art slots. Put an asset id ("rbxassetid://123") next to a slot name and
	every place that slot is drawn shows the image instead of the placeholder.
	Seed icons use "Seed_<cropId>", ribbons "Ribbon_<Blue|Red|Yellow|Team|Entrant>".
	Slots not listed here still work: ArtSlot falls back to the placeholder.
]]
Theme.Art = {
	-- HUD
	CoinIcon = "",
	LevelIcon = "",
	MenuShop = "",
	MenuMarket = "",
	MenuFair = "",
	MenuChampion = "",
	MenuRibbons = "",
	-- Panel headers (icon left of the title).
	PanelIcon_Shop = "",
	PanelIcon_Market = "",
	PanelIcon_Fair = "",
	PanelIcon_Champion = "",
	PanelIcon_Ribbons = "",
	ChampionPortrait = "",
	-- 9-slice frames. Set ArtSlice for the matching slot too.
	PanelFrame = "",
	ButtonFace = "",
} :: { [string]: string }

-- SliceCenter for 9-slice art slots (pixels inside the source image).
Theme.ArtSlice = {
	PanelFrame = Rect.new(32, 32, 96, 96),
	ButtonFace = Rect.new(16, 16, 48, 48),
} :: { [string]: Rect }

function Theme.darken(color: Color3, amount: number?): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount or 0.2)
end

function Theme.lighten(color: Color3, amount: number?): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount or 0.2)
end

function Theme.luminance(color: Color3): number
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
end

-- Text color for a background: white (with an outline) on anything colored, dark on near-white.
function Theme.textOn(color: Color3): Color3
	return if Theme.luminance(color) > 0.86 then Theme.Colors.Text else Theme.Colors.TextOnPrimary
end

-- True when text in this color should get the dark outline.
function Theme.wantsOutline(textColor: Color3): boolean
	return Theme.luminance(textColor) > 0.6
end

--[[
	The candy gradient for a color: light top, the color itself through the
	middle, and a darker band at the very bottom that reads as a 3D edge.
	Used on a white BackgroundColor3 (UIGradient multiplies).
]]
function Theme.gradient(color: Color3): ColorSequence
	local style = Theme.Style
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.lighten(color, style.GradientLight)),
		ColorSequenceKeypoint.new(0.45, color),
		ColorSequenceKeypoint.new(0.82, Theme.darken(color, style.GradientDark * 0.4)),
		ColorSequenceKeypoint.new(1, Theme.darken(color, style.GradientDark)),
	})
end

return Theme
