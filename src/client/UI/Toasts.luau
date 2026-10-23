--!strict
--[[
	Toasts: short messages at the top of the screen, with a priority queue.

	    Toasts.push("Level 4!", { color = Theme.Colors.Accent, priority = "High", duration = 3.5 })
	    Toasts.push("You bought Carrot Seed!", { kind = "Success", subtitle = "+1 Carrot Seed", icon = "Carrot" })

	Kinds (colour + icon): Success (green), Info (blue), Reward (yellow),
	Warning (orange), Error (red). Without a kind it is guessed from the colour.

	Rules that keep the screen calm:
	  - At most 3 on screen (2 on phones). Extra ones wait in a queue.
	  - A High toast pushes out the oldest Low/Normal one instead of waiting.
	  - The same text while it is still showing stacks ("+25 Coins x3") and
	    pops instead of adding a new line.
	  - Leaving toasts shrink their slot smoothly, so the others glide up
	    rather than jump.
]]

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Icons = require(script.Parent.Icons)
local Scale = require(script.Parent.Scale)
local Tweens = require(script.Parent.Parent.Feel.Tweens)

local Toasts = {}

export type Priority = "Low" | "Normal" | "High"
export type Kind = "Success" | "Info" | "Reward" | "Warning" | "Error"
export type Options = {
	color: Color3?,
	duration: number?,
	priority: Priority?,
	kind: Kind?,
	-- Smaller second line under the message.
	subtitle: string?,
	-- Icons name shown on the left (defaults to the kind's icon).
	icon: string?,
}

local KIND_COLOR: { [string]: Color3 } = {
	Success = Theme.Colors.Primary,
	Info = Theme.Colors.Info,
	Reward = Theme.Colors.Gold,
	Warning = Theme.Colors.Accent,
	Error = Theme.Colors.Danger,
}
local KIND_ICON: { [string]: string } = {
	Success = "Success",
	Info = "Info",
	Reward = "Reward",
	Warning = "Star",
	Error = "Error",
}

-- Older callers only pass a colour; map it to the closest kind.
local function kindFor(options: Options): string
	if options.kind then
		return options.kind
	end
	local color = options.color
	if color == Theme.Colors.Primary or color == Theme.Colors.PrimaryDark then
		return "Success"
	elseif color == Theme.Colors.Gold then
		return "Reward"
	elseif color == Theme.Colors.Accent then
		return "Warning"
	elseif color == Theme.Colors.Danger then
		return "Error"
	end
	return "Info"
end

local RANK: { [string]: number } = { Low = 1, Normal = 2, High = 3 }
local SLOT_HEIGHT = 56
local SLOT_HEIGHT_TWO_LINES = 70
local MAX_QUEUE = 6

type Live = {
	text: string,
	rank: number,
	slot: Frame,
	card: Frame,
	label: TextLabel,
	count: number,
	expires: number,
	leaving: boolean,
}

type Pending = { text: string, options: Options, rank: number, at: number }

local holder: Frame? = nil
local live: { Live } = {}
local queue: { Pending } = {}
local order = 0

local function maxVisible(): number
	return if Scale.isPhone() then 2 else 3
end

local function remove(entry: Live)
	if entry.leaving then
		return
	end
	entry.leaving = true
	local index = table.find(live, entry)
	if index then
		table.remove(live, index)
	end
	-- Shrinks all the way away (outline and gloss included) while the slot closes.
	local scale = Tweens.getScale(entry.card)
	Tweens.play(scale, Tweens.Ease.PanelOut, { Scale = 0 })
	local collapse = Tweens.play(entry.slot, Tweens.Ease.Collapse, { Size = UDim2.new(1, 0, 0, 0) })
	task.delay(if collapse then 0.24 else 0, function()
		entry.slot:Destroy()
	end)
	task.defer(Toasts.pump)
end

local function show(text: string, options: Options, rank: number)
	local parent = holder
	if not parent then
		return
	end
	order += 1
	local kind = kindFor(options)
	local color = options.color or KIND_COLOR[kind]
	local twoLines = options.subtitle ~= nil and options.subtitle ~= ""
	local slot = UIKit.new("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = order,
		ClipsDescendants = false,
		Parent = parent,
	})
	-- Card: icon on the left, message (and optional subtitle) next to it.
	-- Placed by position, not a list layout, so the gloss strip doesn't join the row.
	local height = if twoLines then 62 else 48
	local bubbleSize = if twoLines then 44 else 36
	local card = UIKit.card({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = slot,
	}, {
		UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 20) }),
	})
	local corner = card:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 16)
	end
	UIKit.paint(card, color)
	UIKit.outline(card)
	UIKit.gloss(card)
	local iconBubble = UIKit.new("Frame", {
		Name = "IconBubble",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 9, 0.5, 0),
		Size = UDim2.fromOffset(bubbleSize, bubbleSize),
		BackgroundColor3 = Color3.new(1, 1, 1),
		-- Image icons bring their own badge; only emoji fallbacks get a light bubble.
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = card,
	}, { UIKit.corner(Theme.CornerRound) })
	local iconName = options.icon or KIND_ICON[kind]
	local iconDef = Icons.get(iconName)
	if not (iconDef and iconDef.image ~= "") then
		iconBubble.BackgroundTransparency = 0.15
	end
	local icon = Icons.make(iconName)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(if iconDef and iconDef.image ~= "" then 1 else 0.75, if iconDef and iconDef.image ~= "" then 1 else 0.75)
	icon.ZIndex = 4
	icon.Parent = iconBubble
	local texts = UIKit.new("Frame", {
		Name = "Texts",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, bubbleSize + 20, 0.5, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = card,
	}, { UIKit.list(Enum.FillDirection.Vertical, 0) })
	local label = UIKit.label(text, Theme.TextSize.Body + 2, {
		Name = "Message",
		LayoutOrder = 1,
		TextColor3 = Theme.textOn(color),
		ZIndex = 3,
		Parent = texts,
	})
	UIKit.outlineText(label)
	if twoLines then
		local sub = UIKit.label(options.subtitle :: string, Theme.TextSize.Small, {
			Name = "Subtitle",
			LayoutOrder = 2,
			TextColor3 = Theme.textOn(color),
			ZIndex = 3,
			Parent = texts,
		})
		UIKit.outlineText(sub, 1.5)
	end
	local entry: Live = {
		text = text,
		rank = rank,
		slot = slot,
		card = card,
		label = label,
		count = 1,
		expires = os.clock() + (options.duration or 2.6),
		leaving = false,
	}
	table.insert(live, entry)
	-- Open the slot smoothly, then pop the card in.
	Tweens.play(slot, Tweens.Ease.Collapse, { Size = UDim2.new(1, 0, 0, if twoLines then SLOT_HEIGHT_TWO_LINES else SLOT_HEIGHT) })
	local scale = Tweens.getScale(card)
	scale.Scale = 0.5
	Tweens.play(scale, Tweens.Ease.PanelIn, { Scale = 1 })
	if rank >= RANK.High then
		-- Big news gets a bright flash and a second bounce.
		Tweens.flash(card, Theme.Style.Flash, 0.05, 0.6)
		task.delay(0.3, function()
			Tweens.pop(card, 0.12)
		end)
	end

	task.spawn(function()
		while not entry.leaving do
			local left = entry.expires - os.clock()
			if left <= 0 then
				remove(entry)
				return
			end
			task.wait(math.min(left, 0.25))
		end
	end)
end

function Toasts.pump()
	while #queue > 0 and #live < maxVisible() do
		local nextOne = table.remove(queue, 1) :: Pending
		show(nextOne.text, nextOne.options, nextOne.rank)
	end
end

function Toasts.push(text: string, options: Options?)
	local opts = options or {}
	local rank = RANK[opts.priority or "Normal"] or 2

	-- Same message still on screen: stack it instead of adding a line.
	for _, entry in live do
		if entry.text == text and not entry.leaving then
			entry.count += 1
			entry.label.Text = string.format("%s  x%d", text, entry.count)
			entry.expires = math.max(entry.expires, os.clock() + (opts.duration or 2.6) * 0.8)
			Tweens.pop(entry.card, 0.1)
			return
		end
	end

	if #live >= maxVisible() and rank == RANK.High then
		-- Make room: the oldest less important toast leaves early.
		for _, entry in live do
			if entry.rank < rank and not entry.leaving then
				remove(entry)
				break
			end
		end
	end

	table.insert(queue, { text = text, options = opts, rank = rank, at = os.clock() })
	table.sort(queue, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return a.at < b.at
	end)
	while #queue > MAX_QUEUE do
		table.remove(queue) -- drop the least important, newest
	end
	Toasts.pump()
end

function Toasts.mount(parent: GuiObject)
	holder = UIKit.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		-- Below the HUD's travel buttons (My Garden / Shops).
		Position = UDim2.new(0.5, 0, 0, Theme.Size.ActionButton.Y + 16),
		Size = UDim2.fromOffset(Theme.Size.ToastWidth, 200),
		Parent = parent,
	}, { UIKit.list(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Center) })
end

return Toasts
