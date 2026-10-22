--!strict
-- RibbonNames: readable names for ribbon ids ("weekly:Blue:crop_pumpkin" -> "Blue ribbon · Best Pumpkin · Weekly Grand Fair").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FairMath = require(Shared.FairMath)

local RibbonNames = {}

local TIER_NAMES = {
	Blue = "Blue ribbon",
	Red = "Red ribbon",
	Yellow = "Yellow ribbon",
	BlueRibbon = "Blue ribbon",
	RedRibbon = "Red ribbon",
	YellowRibbon = "Yellow ribbon",
	EntrantRosette = "Entrant rosette",
}

RibbonNames.Colors = {
	Blue = Color3.fromRGB(80, 140, 235),
	Red = Color3.fromRGB(230, 85, 80),
	Yellow = Color3.fromRGB(245, 200, 60),
	Team = Color3.fromRGB(160, 110, 220),
	Entrant = Color3.fromRGB(170, 170, 170),
}

function RibbonNames.colorKey(ribbonId: string): string
	local _, tier = FairMath.parseRibbonId(ribbonId)
	tier = tier or ribbonId
	for key in RibbonNames.Colors do
		if string.find(tier :: string, key, 1, true) then
			return key
		end
	end
	return "Entrant"
end

function RibbonNames.describe(ribbonId: string): string
	local fair, tier, division = FairMath.parseRibbonId(ribbonId)
	if not fair then
		return ribbonId
	end
	local period = Config.Fair.periods[fair :: string]
	local fairName = if period then period.displayName else fair
	if tier == "Team" then
		return string.format("Team %s ribbon · %s", division, fairName)
	end
	local tierName = TIER_NAMES[tier :: string] or (tier :: string)
	local divisionName = FairMath.divisionName(division :: string, Config.Fair.divisions, Config.Crops)
	return string.format("%s · %s · %s", tierName, divisionName, fairName)
end

return RibbonNames
