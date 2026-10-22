--!strict
--[[
	FeelHooks: the drop-in points for audio and animation.

	Every key is a Feel event name (see Net.Feedback plus client-only events
	like "ButtonPress"). Leave a value empty and the hook is silent; fill in an
	asset id later and it just works, no code changes.

	  Sounds[event]     = "rbxassetid://..."   (played once, 2D)
	  Animations[event] = "rbxassetid://..."   (played on the local character)
	  Particles[event]  = name of a ParticleEmitter template inside
	                      ReplicatedStorage.Assets.Particles (emitted at the world position)
]]

local FeelHooks = {}

FeelHooks.Sounds = {
	ButtonPress = "",
	PanelOpen = "",
	PanelClose = "",
	Planted = "",
	Watered = "",
	FriendWateredYou = "",
	YouWateredFriend = "",
	StageChanged = "",
	BecameGiant = "",
	Harvested = "",
	HarvestedGiant = "",
	NewRecord = "",
	Sold = "",
	CoinTick = "",
	Purchased = "",
	LevelUp = "",
	FairEntered = "",
	FairReward = "",
	WelcomeBack = "",
	Denied = "",
	-- XP essence: one burst sound, a soft tick per orb landing in the bar.
	EssenceBurst = "",
	EssenceTick = "",
	-- Champion and grow together.
	CareNeeded = "",
	CareDone = "",
	ChampionNamed = "",
	CoGrowInvite = "",
	CoGrowJoined = "",
	MailReceived = "",
	-- Live weigh-in shows.
	FairDayAnnounce = "",
	FairDayStart = "",
	FairDrumroll = "",
	FairWeighIn = "",
	FairPodiumPop = "",
	FairConfetti = "",
	ServerPrize = "",
} :: { [string]: string }

FeelHooks.Animations = {
	Planted = "",
	Watered = "",
	YouWateredFriend = "",
	Harvested = "",
	HarvestedGiant = "",
	FairEntered = "",
	CareDone = "",
	ServerPrize = "",
} :: { [string]: string }

FeelHooks.Particles = {
	Planted = "",
	Watered = "",
	FriendWateredYou = "",
	BecameGiant = "",
	Harvested = "",
	HarvestedGiant = "",
	LevelUp = "",
	EssenceBurst = "",
	CareDone = "",
	FairWeighIn = "",
	FairConfetti = "",
} :: { [string]: string }

-- Volume per event (default 0.5).
FeelHooks.Volume = {
	CoinTick = 0.25,
	EssenceTick = 0.2,
} :: { [string]: number }

return FeelHooks
