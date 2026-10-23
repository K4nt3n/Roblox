--!strict
--[[
	Theme: design tokens for all placeholder UI. Restyle the whole game from
	here, or swap UIKit builders for art-backed ones later. Soft, rounded,
	high-contrast, kid friendly.

	Sizes are in design pixels at a 1280x720 reference screen. UI/Scale turns
	them into real pixels per device, so never scale by hand.

	Art seam: every icon, panel frame and button face Peter draws plugs into
	Theme.Art below. Empty means the flat placeholder shape is drawn.

	Look (Peter's two references, 2026-10-23): clean white panels with black
	edges and a colored title bar, and "studded" colored buttons: flat
	saturated faces with a subtle square-stud texture, a darker lip along the
	bottom, a thick dark outline and white text with a heavy dark stroke.
	All of it is tuned in Theme.Style.
]]

local Theme = {}

-- Saturated button colors on clean white surfaces.
Theme.Colors = {
	Background = Color3.fromRGB(255, 255, 255),
	Surface = Color3.fromRGB(255, 255, 255),
	SurfaceAlt = Color3.fromRGB(238, 240, 246),
	Primary = Color3.fromRGB(60, 200, 70),
	PrimaryDark = Color3.fromRGB(30, 150, 50),
	Accent = Color3.fromRGB(255, 140, 25),
	Danger = Color3.fromRGB(240, 60, 70),
	Gold = Color3.fromRGB(255, 200, 30),
	Info = Color3.fromRGB(40, 150, 250),
	Purple = Color3.fromRGB(160, 80, 245),
	Pink = Color3.fromRGB(255, 95, 190),
	Text = Color3.fromRGB(30, 30, 40),
	TextMuted = Color3.fromRGB(125, 128, 142),
	TextOnPrimary = Color3.fromRGB(255, 255, 255),
	Stroke = Color3.fromRGB(22, 22, 30),
	Disabled = Color3.fromRGB(180, 183, 194),
	DisabledText = Color3.fromRGB(245, 245, 250),
	Backdrop = Color3.fromRGB(20, 12, 40),
	Essence = Color3.fromRGB(150, 235, 120),
	EssenceGlow = Color3.fromRGB(255, 245, 160),
	CoinGlow = Color3.fromRGB(255, 240, 170),
}

-- Placeholder color per fair (HUD timers), until Timer_<fairId> art arrives.
Theme.FairColor = {
	hourly = Color3.fromRGB(40, 150, 250),
	daily = Color3.fromRGB(255, 140, 25),
	weekly = Color3.fromRGB(255, 200, 30),
} :: { [string]: Color3 }

-- One accent per panel so each screen is recognisable at a glance.
Theme.PanelAccent = {
	Shop = Theme.Colors.Primary,
	Market = Theme.Colors.Accent,
	Fair = Theme.Colors.Gold,
	Champion = Theme.Colors.Purple,
	Ribbons = Theme.Colors.Info,
}

--[[
	Style: the "big Roblox game" finish. Everything visual that is code (not
	art) is tuned here: outlines, gradients, gloss, shadows, shine sweeps.
]]
Theme.Style = {
	-- Thick near-black outline around buttons, pills and panels.
	Outline = Color3.fromRGB(22, 22, 30),
	OutlineThickness = 3,
	PanelOutlineThickness = 3.5,
	-- Cards inside panels get a softer (grey) outline so panels don't get busy.
	CardOutlineTransparency = 0.7,
	-- White text with a heavy dark outline on anything colored.
	TextOutline = 3,
	TitleOutline = 4,
	-- Face shading: a slightly lighter top, then flat color.
	GradientLight = 0.14,
	GradientDark = 0.08,
	-- The darker lip along the bottom of buttons and pills (share of the height,
	-- and how much darker it is). Lip = 0 turns it off.
	Lip = 0.2,
	LipDarken = 0.24,
	-- Square-stud texture on colored faces. Theme.Art.StudTile (a seamless
	-- tile, one stud) replaces the texture made in code.
	Studs = true,
	StudSize = 14,
	StudTransparency = 0.55,
	-- Glossy strip across the top half of buttons (off for the flat studded look).
	Gloss = false,
	GlossTransparency = 0.5,
	-- Drop shadow under HUD pills, slots and toasts.
	ShadowColor = Color3.fromRGB(15, 15, 25),
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

Theme.Font = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.GothamMedium

Theme.Corner = UDim.new(0, 12)
Theme.CornerSmall = UDim.new(0, 8)
Theme.CornerPanel = UDim.new(0, 16)
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
	SeedSlot = 76,
	SeedSlotPhone = 64,
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
	Seed icons use "Seed_<cropId>", upgrades "Upgrade_<upgradeId>", ribbons
	"Ribbon_<Blue|Red|Yellow|Team|Entrant>", fair places "Medal_<1|2|3>".
	PanelIcon_<Panel> left empty reuses Menu<Panel>, so one upload covers both.
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
	-- Panel headers (icon left of the title). Empty uses the Menu<Panel> art.
	PanelIcon_Shop = "",
	PanelIcon_Market = "",
	PanelIcon_Fair = "",
	PanelIcon_Champion = "",
	PanelIcon_Ribbons = "",
	ChampionPortrait = "",
	-- Seeds (hotbar, shop, basket).
	Seed_carrot = "",
	Seed_tomato = "",
	Seed_cabbage = "",
	Seed_pumpkin = "",
	Seed_watermelon = "",
	-- Shop upgrades.
	Upgrade_wateringCan = "",
	Upgrade_fertilizer = "",
	Upgrade_greenThumb = "",
	Upgrade_marketStall = "",
	Upgrade_plot = "",
	-- HUD fair timers (Timer_<fairId>).
	Timer_hourly = "",
	Timer_daily = "",
	Timer_weekly = "",
	-- One stud of the button texture, tiled (see Theme.Style.Studs).
	StudTile = "",
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
	The face gradient for a color: a slightly lighter top, the color itself,
	and a hard step into a darker lip along the bottom that reads as a 3D
	edge (`lip` false for flat bars like panel headers).
	Used on a white BackgroundColor3 (UIGradient multiplies).
]]
function Theme.gradient(color: Color3, lip: boolean?): ColorSequence
	local style = Theme.Style
	local top = Theme.lighten(color, style.GradientLight)
	local bottom = Theme.darken(color, style.GradientDark)
	if lip == false or style.Lip <= 0 then
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, bottom),
		})
	end
	local step = 1 - style.Lip
	local edge = Theme.darken(color, style.LipDarken)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(step * 0.5, color),
		ColorSequenceKeypoint.new(step - 0.001, bottom),
		ColorSequenceKeypoint.new(step, edge),
		ColorSequenceKeypoint.new(1, Theme.darken(edge, 0.08)),
	})
end

return Theme
