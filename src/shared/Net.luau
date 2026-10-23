--!strict
--[[
	Net: the names of every remote and request action, shared by client and server.

	All client -> server traffic goes through one RemoteFunction ("Request") with
	an action name. The server validates every payload; the client never sends
	weights, prices or timestamps.
]]

local Net = {}

Net.FolderName = "GVFRemotes"

Net.Remotes = {
	-- RemoteFunction: (action: string, payload: table?) -> { ok: boolean, err: string?, data: any? }
	Request = "Request",
	-- RemoteEvent (server -> client): full player state snapshot.
	State = "State",
	-- RemoteEvent (server -> client): (eventName: string, context: table) for game-feel hooks.
	Feedback = "Feedback",
	-- RemoteEvent (server -> client): fair leaderboard rows.
	Leaderboard = "Leaderboard",
	-- RemoteEvent (server -> all clients): live Fair Day show state.
	FairDay = "FairDay",
}

Net.Actions = {
	SelectSeed = "SelectSeed", -- { cropId } "" puts the seed away
	SetHotbarTool = "SetHotbarTool", -- { toolId, on }
	BuySeed = "BuySeed", -- { cropId, amount }
	BuyUpgrade = "BuyUpgrade", -- { upgradeId }
	BuyPlot = "BuyPlot", -- {}
	SellProduce = "SellProduce", -- { uid }
	SellAll = "SellAll", -- {}
	EnterFair = "EnterFair", -- { uid }
	PromptSkip = "PromptSkip", -- { plotId }
	DebugSimulatePurchase = "DebugSimulatePurchase", -- { product } Studio only
	NameChampion = "NameChampion", -- { name }
	InviteCoGrower = "InviteCoGrower", -- { userId }
	RespondCoGrow = "RespondCoGrow", -- { ownerUserId, accept }
	DebugStartFairDay = "DebugStartFairDay", -- {} Studio only
	ClaimPlot = "ClaimPlot", -- { slot? } no slot = the server picks a free one
	UseTool = "UseTool", -- { toolId, ownerUserId, plotId }
	BuySupply = "BuySupply", -- { supplyId, amount }
}

-- Feedback event names the server can send. The client maps these to feel presets.
Net.Feedback = {
	Planted = "Planted",
	Watered = "Watered",
	FriendWateredYou = "FriendWateredYou",
	YouWateredFriend = "YouWateredFriend",
	StageChanged = "StageChanged",
	Harvested = "Harvested",
	Sold = "Sold",
	Purchased = "Purchased",
	LevelUp = "LevelUp",
	FairEntered = "FairEntered",
	FairReward = "FairReward",
	WelcomeBack = "WelcomeBack",
	Denied = "Denied",
	CareDone = "CareDone",
	CareNeeded = "CareNeeded",
	ChampionNamed = "ChampionNamed",
	CoGrowInvite = "CoGrowInvite",
	CoGrowJoined = "CoGrowJoined",
	ServerPrize = "ServerPrize",
	MailReceived = "MailReceived",
	PestsAppeared = "PestsAppeared",
	PestsRemoved = "PestsRemoved",
	Fertilized = "Fertilized",
	-- Sent to everyone in the server so each client can play the tool animation.
	ToolUsed = "ToolUsed",
}

return Net
