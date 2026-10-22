--!strict
--[[
	Theme: design tokens for all placeholder UI. Restyle the whole game from
	here, or swap UIKit builders for art-backed ones later. Soft, rounded,
	high-contrast, kid friendly.

	Sizes are in design pixels at a 1280x720 reference screen. UI/Scale turns
	them into real pixels per device, so never scale by hand.

	Art seam: every icon, panel frame and button face Peter draws plugs into
	Theme.Art below. Empty means the flat placeholder shape is drawn.
]]

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(255, 248, 235),
	Surface = Color3.fromRGB(255, 255, 255),
	SurfaceAlt = Color3.fromRGB(245, 236, 220),
	Primary = Color3.fromRGB(95, 190, 95),
	PrimaryDark = Color3.fromRGB(60, 150, 70),
	Accent = Color3.fromRGB(255, 170, 50),
	Danger = Color3.fromRGB(235, 90, 80),
	Gold = Color3.fromRGB(255, 205, 60),
	Info = Color3.fromRGB(90, 160, 235),
	Purple = Color3.fromRGB(165, 115, 225),
	Text = Color3.fromRGB(60, 45, 35),
	TextMuted = Color3.fromRGB(140, 120, 100),
	TextOnPrimary = Color3.fromRGB(255, 255, 255),
	Stroke = Color3.fromRGB(90, 65, 45),
	Disabled = Color3.fromRGB(200, 195, 185),
	DisabledText = Color3.fromRGB(150, 143, 132),
	Backdrop = Color3.fromRGB(25, 20, 15),
	Essence = Color3.fromRGB(150, 235, 120),
	EssenceGlow = Color3.fromRGB(255, 245, 160),
	CoinGlow = Color3.fromRGB(255, 240, 170),
}

-- One accent per panel so each screen is recognisable at a glance.
Theme.PanelAccent = {
	Shop = Theme.Colors.Primary,
	Market = Theme.Colors.Accent,
	Fair = Theme.Colors.Gold,
	Champion = Theme.Colors.Purple,
	Ribbons = Theme.Colors.Info,
}

Theme.Font = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.GothamMedium

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

-- Readable text color for a given background.
function Theme.textOn(color: Color3): Color3
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return if luminance > 0.72 then Theme.Colors.Text else Theme.Colors.TextOnPrimary
end

return Theme
