--!strict
--[[
	DialogueConfig: everything the NPCs say. Edit text here; no code changes needed.

	Each NPC (key = the NPC model's "DialogueId" attribute in Workspace.NPCs):
	  displayName  name shown above the NPC and on the dialogue box
	  stand        Workspace.Stands part this NPC works at (its plain "Open"
	               prompt is hidden so players talk to the NPC instead)
	  promptText   the action text on the talk prompt
	  line         what the NPC says
	  responses    the player's answers, shown as buttons in this order:
	                 text    button text
	                 action  what happens (see ACTIONS below)
	                 reply   optional: the NPC says this before the dialogue closes

	ACTIONS (handled in Client.Controllers.DialogueController):
	  "OpenShop"      open the Seed Shop panel
	  "OpenMarket"    open the Sell panel to sell veggies
	  "StartWeighIn"  pick a veggie from your basket and enter it in a fair
	  "Close"         just close the dialogue
]]

export type Response = { text: string, action: string, reply: string? }
export type Npc = {
	displayName: string,
	stand: string?,
	promptText: string,
	line: string,
	responses: { Response },
}

local DialogueConfig = {}

-- Seconds per character for the typewriter effect (0 = show instantly).
DialogueConfig.TypeSpeed = 0.02
-- The dialogue closes if the player walks further than this from the NPC.
DialogueConfig.MaxDistance = 18

DialogueConfig.Npcs = {
	SeedSeller = {
		displayName = "Seed Seller",
		stand = "SeedShop",
		promptText = "Talk",
		line = "Hey i sell seeds and stuff. do you wanna buy?",
		responses = {
			{ text = "ok", action = "OpenShop" },
			{ text = "bye", action = "Close" },
		},
	},
	MarketMerchant = {
		displayName = "Selling Merchant",
		stand = "Market",
		promptText = "Talk",
		line = "do you want to sell your vegetables boy?",
		responses = {
			{ text = "yes sir", action = "OpenMarket" },
			{ text = "no.", action = "Close" },
			{ text = "nope", action = "Close" },
		},
	},
	FairJudge = {
		displayName = "Fair Judge",
		stand = "FairStand",
		promptText = "Talk",
		line = "ready to weight in your vegetable?",
		responses = {
			{ text = "yeah, i guess", action = "StartWeighIn" },
			{ text = "no", action = "Close" },
		},
	},
} :: { [string]: Npc }

return DialogueConfig
