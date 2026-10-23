--!strict
--[[
	Icons: every icon in the game, by name.

	    Icons.make("Carrot", 40)           -- an icon GuiObject, 40x40 design px
	    Icons.forSlot("Seed_carrot")       -- the icon name an ArtSlot slot uses

	Each icon has an `image` (an uploaded transparent PNG, "rbxassetid://...")
	and an `emoji` fallback. Until an image is filled in the emoji is drawn,
	so to swap in real art: upload the PNG, paste its id into `image`, done.

	`color` is the icon's theme colour (used for chips and placeholder tints).
]]

local Icons = {}

export type Def = { image: string, emoji: string, color: Color3 }

local function def(emoji: string, r: number, g: number, b: number, image: string?): Def
	return { image = image or "", emoji = emoji, color = Color3.fromRGB(r, g, b) }
end

Icons.List = {
	-- Seeds / crops
	Carrot = def("🥕", 255, 145, 60),
	Tomato = def("🍅", 235, 70, 60),
	Corn = def("🌽", 255, 205, 60),
	Strawberry = def("🍓", 235, 70, 90),
	Blueberry = def("🍇", 90, 110, 220),
	Watermelon = def("🍉", 70, 170, 90),
	Pumpkin = def("🎃", 255, 165, 40),
	Cabbage = def("🥬", 140, 210, 110),
	Sunflower = def("🌻", 255, 205, 60),
	Seedling = def("🌱", 95, 190, 95),
	-- Farming tools
	Shovel = def("⛏️", 140, 140, 150),
	WateringCan = def("🚿", 90, 160, 235),
	Bucket = def("💦", 90, 160, 235),
	PestRemover = def("🧴", 95, 190, 95),
	Wheelbarrow = def("🛒", 235, 90, 80),
	Fertilizer = def("🌱", 176, 140, 92),
	Tools = def("🧰", 90, 160, 235),
	-- Environment
	Tree = def("🌳", 86, 176, 74),
	Fence = def("🚧", 163, 112, 68),
	Rock = def("🗿", 156, 152, 148),
	Crate = def("📦", 163, 112, 68),
	Bugs = def("🐛", 110, 160, 60),
	-- Currency
	Cash = def("💵", 95, 190, 95),
	Gems = def("💎", 165, 115, 225),
	Coins = def("💰", 255, 205, 60),
	Leaves = def("🍃", 95, 190, 95),
	-- Navigation
	Shop = def("🛒", 95, 190, 95),
	Seeds = def("🌱", 95, 190, 95),
	Settings = def("⚙️", 255, 190, 60),
	Home = def("🏠", 140, 160, 190),
	Backpack = def("🎒", 90, 160, 235),
	Basket = def("🧺", 255, 170, 50),
	Pets = def("🐾", 255, 190, 60),
	Upgrades = def("⏫", 165, 115, 225),
	Rewards = def("🎁", 235, 90, 80),
	Profile = def("👤", 90, 160, 235),
	Trophy = def("🏆", 255, 205, 60),
	Crown = def("👑", 255, 205, 60),
	Ribbon = def("🎀", 90, 160, 235),
	Market = def("🏪", 255, 170, 50),
	Plot = def("➕", 95, 190, 95),
	-- Notifications
	Success = def("✅", 95, 190, 95),
	Info = def("ℹ️", 90, 160, 235),
	Warning = def("⚠️", 255, 190, 60),
	Error = def("❗", 235, 90, 80),
	Reward = def("🎉", 255, 205, 60),
	-- Other
	Water = def("💧", 90, 160, 235),
	Energy = def("⚡", 255, 205, 60),
	Level = def("⭐", 255, 205, 60),
	Star = def("⭐", 255, 205, 60),
	Heart = def("❤️", 235, 70, 80),
	Sparkle = def("✨", 255, 220, 120),
	Lock = def("🔒", 150, 143, 132),
	Clock = def("⏱️", 140, 160, 190),
	Hand = def("👆", 255, 205, 160),
	-- Ribbons
	Ribbon_Blue = def("🥇", 90, 160, 235),
	Ribbon_Red = def("🥈", 235, 90, 80),
	Ribbon_Yellow = def("🥉", 255, 205, 60),
	Ribbon_Team = def("🤝", 165, 115, 225),
	Ribbon_Entrant = def("🏵️", 255, 170, 50),
	-- More from the UI reference sheet
	CoinsStack = def("💰", 255, 205, 60),
	Box = def("📦", 163, 112, 68),
	ArrowUp = def("⬆️", 90, 160, 235),
	Close = def("✖️", 235, 90, 80),
	Back = def("↩️", 140, 160, 190),
	Menu = def("☰", 140, 160, 190),
	Chat = def("💬", 140, 160, 190),
	Map = def("🗺️", 95, 190, 95),
	Quest = def("📜", 222, 190, 140),
	Gift = def("🎁", 235, 90, 80),
	Friends = def("👥", 140, 160, 190),
	KeyE = def("E", 240, 240, 245),
	Cursor = def("↖️", 240, 240, 245),
	Wifi = def("📶", 90, 160, 235),
	Sun = def("☀️", 255, 205, 60),
} :: { [string]: Def }

--[[
	Uploaded art: transparent PNGs cut from the UI reference sheet (source files
	in D:\roblox\icons, cut by D:\roblox\tools\cut_icons.ps1). Icons not listed
	here draw their emoji.
]]
local IMAGES: { [string]: string } = {
	Carrot = "rbxassetid://135067738540280", -- Peter's art
	Tomato = "rbxassetid://75507724510899", -- Peter's art
	Corn = "rbxassetid://91307205658871",
	Strawberry = "rbxassetid://78162361077584",
	Blueberry = "rbxassetid://136831717832722",
	Watermelon = "rbxassetid://70751184684141", -- Peter's art
	Pumpkin = "rbxassetid://101621559771007", -- Peter's art
	Cabbage = "rbxassetid://113377002122844", -- Peter's art
	Sunflower = "rbxassetid://82534278241710",
	Seedling = "rbxassetid://111591482395541",
	Shovel = "rbxassetid://108163588000757",
	WateringCan = "rbxassetid://87222493958048",
	Bucket = "rbxassetid://87222493958048",
	Wheelbarrow = "rbxassetid://130260915284197",
	Fertilizer = "rbxassetid://123019696376670",
	Tools = "rbxassetid://140045367350212",
	Tree = "rbxassetid://131186982864867",
	Fence = "rbxassetid://84750479901602",
	Rock = "rbxassetid://88036331511561",
	Crate = "rbxassetid://71398394030588",
	Cash = "rbxassetid://135059430542618",
	Gems = "rbxassetid://121449516132218", -- Peter's art
	Coins = "rbxassetid://127516979601580", -- Peter's art
	Leaves = "rbxassetid://108052201030190",
	Shop = "rbxassetid://119819984937638",
	Seeds = "rbxassetid://111591482395541",
	Settings = "rbxassetid://106320831987822",
	Home = "rbxassetid://92432938057083",
	Backpack = "rbxassetid://95947609675186", -- Peter's art
	Basket = "rbxassetid://119662165172518",
	Upgrades = "rbxassetid://105474617673297", -- Peter's art
	Rewards = "rbxassetid://100782637837673",
	Profile = "rbxassetid://77420709122744",
	Trophy = "rbxassetid://130038282233028", -- Peter's art
	Crown = "rbxassetid://109345674374193", -- Peter's art
	Success = "rbxassetid://109300110129433",
	Info = "rbxassetid://127303904167870",
	Error = "rbxassetid://90461792057933",
	Reward = "rbxassetid://77007589231068",
	Water = "rbxassetid://76585110115923",
	Energy = "rbxassetid://93148120119489",
	Sun = "rbxassetid://93148120119489",
	Level = "rbxassetid://119845549049763",
	Star = "rbxassetid://72875467828151", -- Peter's art
	Heart = "rbxassetid://101734815415752",
	Hand = "rbxassetid://103275385118466",
	CoinsStack = "rbxassetid://124458271247406",
	Box = "rbxassetid://109348590634413",
	ArrowUp = "rbxassetid://129440706577088",
	Close = "rbxassetid://84618024082369",
	Back = "rbxassetid://116693670854845",
	Menu = "rbxassetid://120544074535864",
	Chat = "rbxassetid://72576833391019",
	Map = "rbxassetid://125574306059034",
	Quest = "rbxassetid://74489156535348",
	Gift = "rbxassetid://100782637837673",
	Friends = "rbxassetid://77420709122744",
	KeyE = "rbxassetid://91817284138255",
	Cursor = "rbxassetid://127887931168201",
	Wifi = "rbxassetid://120690464457480",
}
for name, id in IMAGES do
	local icon = Icons.List[name]
	if icon then
		icon.image = id
	end
end

-- ArtSlot slot name -> icon name. Seeds, upgrades and supplies map by id below.
Icons.Slots = {
	CoinIcon = "Coins",
	LevelIcon = "Star",
	GemIcon = "Gems",
	MenuShop = "Shop",
	MenuMarket = "Basket",
	MenuFair = "Trophy",
	MenuChampion = "Crown",
	MenuRibbons = "Ribbon",
	PanelIcon_Shop = "Shop",
	PanelIcon_Market = "Basket",
	PanelIcon_Fair = "Trophy",
	PanelIcon_Champion = "Crown",
	PanelIcon_Ribbons = "Ribbon",
	PanelIcon_Backpack = "Backpack",
	PanelIcon_Tools = "Tools",
	PanelIcon_Upgrades = "Upgrades",
	PanelIcon_Settings = "Settings",
	ChampionPortrait = "Crown",
	Upgrade_wateringCan = "WateringCan",
	Upgrade_fertilizer = "Fertilizer",
	Upgrade_greenThumb = "Leaves",
	Upgrade_marketStall = "Market",
	Upgrade_plot = "Plot",
	Supply_fertilizer = "Fertilizer",
	Tool_WateringBucket = "Bucket",
	Tool_PestRemover = "PestRemover",
	Tool_Fertilizer = "Fertilizer",
} :: { [string]: string }

-- Crop id -> icon name (crops not listed use their capitalised id).
Icons.Crops = {
	carrot = "Carrot",
	tomato = "Tomato",
	cabbage = "Cabbage",
	pumpkin = "Pumpkin",
	watermelon = "Watermelon",
	corn = "Corn",
	strawberry = "Strawberry",
	blueberry = "Blueberry",
} :: { [string]: string }

function Icons.get(name: string): Def?
	return Icons.List[name]
end

-- The icon name for an ArtSlot slot, or nil when the slot has no icon.
function Icons.forSlot(slot: string): string?
	local mapped = Icons.Slots[slot]
	if mapped then
		return mapped
	end
	local cropId = string.match(slot, "^Seed_(.+)$") or string.match(slot, "^Crop_(.+)$")
	if cropId then
		return Icons.Crops[cropId] or (string.upper(string.sub(cropId, 1, 1)) .. string.sub(cropId, 2))
	end
	if Icons.List[slot] then
		return slot
	end
	return nil
end

--[[
	An icon GuiObject (transparent background): an ImageLabel when the icon
	has an image, otherwise the emoji in a TextLabel. `size` is design px.
]]
function Icons.make(name: string, size: number?): GuiObject
	local icon = Icons.List[name]
	local px = size or 36
	local gui: GuiObject
	if icon and icon.image ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = icon.image
		image.ScaleType = Enum.ScaleType.Fit
		gui = image
	else
		local label = Instance.new("TextLabel")
		label.Text = if icon then icon.emoji else "?"
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.new(1, 1, 1)
		gui = label
	end
	gui.Name = "Icon_" .. name
	gui.BackgroundTransparency = 1
	gui.BorderSizePixel = 0
	gui.Size = UDim2.fromOffset(px, px)
	gui:SetAttribute("Icon", name)
	return gui
end

return Icons
