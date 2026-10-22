--!strict
--[[
	Theme: design tokens for all placeholder UI. Restyle the whole game from
	here, or swap UIKit builders for art-backed ones later. Soft, rounded,
	high-contrast, kid friendly.
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
	Text = Color3.fromRGB(60, 45, 35),
	TextMuted = Color3.fromRGB(140, 120, 100),
	TextOnPrimary = Color3.fromRGB(255, 255, 255),
	Stroke = Color3.fromRGB(90, 65, 45),
	Disabled = Color3.fromRGB(200, 195, 185),
}

Theme.Font = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.GothamMedium

Theme.Corner = UDim.new(0, 14)
Theme.CornerSmall = UDim.new(0, 10)
Theme.StrokeThickness = 2.5
Theme.Padding = 10

Theme.TextSize = {
	Title = 30,
	Large = 24,
	Body = 18,
	Small = 14,
}

return Theme
