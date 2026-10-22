--!strict
--[[
	FeelController: one place that turns game events into "juice".

	    FeelController.play("Harvested", { position = Vector3, isGiant = true })

	For each event it runs, in order:
	  1. The code preset below (camera punch, etc.), if any.
	  2. The sound / animation / particle hook from FeelHooks, if filled in.
	  3. FeelController.Played:Fire(name, context) so UI and world code can react.

	Server feedback events are routed here automatically. Client code can also
	play client-only events like "ButtonPress".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local ClientState = require(script.Parent.Parent.ClientState)
local FeelHooks = require(script.Parent.FeelHooks)
local Tweens = require(script.Parent.Tweens)

local FeelController = {}

FeelController.Played = Signal.new() -- (name, context)
-- Set by GardenController: finds a world position for a context (e.g. from plotId).
FeelController.positionResolver = nil :: ((context: { [string]: any }) -> Vector3?)?

local soundCache: { [string]: Sound } = {}
local animCache: { [string]: AnimationTrack } = {}

local function playSound(name: string)
	local id = FeelHooks.Sounds[name]
	if not id or id == "" then
		return
	end
	local sound = soundCache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "Feel_" .. name
		sound.SoundId = id
		sound.Volume = FeelHooks.Volume[name] or 0.5
		sound.Parent = SoundService
		soundCache[name] = sound
	end
	SoundService:PlayLocalSound(sound)
end

local function playAnimation(name: string)
	local id = FeelHooks.Animations[name]
	if not id or id == "" then
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local cacheKey = name .. tostring(animator)
	local track = animCache[cacheKey]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		track = animator:LoadAnimation(animation)
		animCache[cacheKey] = track
	end
	track:Play(0.1)
end

local function emitParticles(name: string, position: Vector3?)
	local templateName = FeelHooks.Particles[name]
	if not templateName or templateName == "" or not position then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Particles")
	local template = folder and folder:FindFirstChild(templateName)
	if not template or not template:IsA("ParticleEmitter") then
		return
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = position
	holder.Parent = workspace
	local emitter = template:Clone()
	emitter.Parent = holder
	emitter:Emit(emitter:GetAttribute("Burst") or 20)
	task.delay(emitter.Lifetime.Max + 0.5, function()
		holder:Destroy()
	end)
end

-- Code-only presets (no assets needed). Return a different event name to
-- redirect hooks, e.g. Harvested -> HarvestedGiant.
local Presets: { [string]: (context: { [string]: any }) -> string? } = {
	Harvested = function(context)
		if context.isGiant then
			Tweens.cameraPunch(6)
			return "HarvestedGiant"
		end
		Tweens.cameraPunch(2)
		return nil
	end,
	StageChanged = function(context)
		if context.to == "Giant" then
			return "BecameGiant"
		end
		return nil
	end,
	LevelUp = function()
		Tweens.cameraPunch(3)
		return nil
	end,
	FairReward = function()
		Tweens.cameraPunch(5)
		return nil
	end,
	CareDone = function()
		Tweens.cameraPunch(1.5)
		return nil
	end,
	FairWeighIn = function(context)
		Tweens.cameraPunch(if context.isMine then 4 else 2)
		return nil
	end,
	FairConfetti = function()
		Tweens.cameraPunch(5)
		return nil
	end,
	ServerPrize = function()
		Tweens.cameraPunch(5)
		return nil
	end,
}

function FeelController.play(name: string, context: { [string]: any }?)
	local ctx = context or {}
	if ctx.position == nil and FeelController.positionResolver then
		ctx.position = FeelController.positionResolver(ctx)
	end
	local hookName = name
	local preset = Presets[name]
	if preset then
		hookName = preset(ctx) or name
	end
	playSound(hookName)
	playAnimation(hookName)
	emitParticles(hookName, ctx.position)
	if ctx.isRecord then
		playSound("NewRecord")
	end
	FeelController.Played:Fire(hookName, ctx)
	if hookName ~= name then
		-- Listeners for the base event still fire (e.g. UI toasts on any harvest).
		FeelController.Played:Fire(name, ctx)
	end
end

function FeelController.start()
	ClientState.Feedback:Connect(function(eventName, context)
		FeelController.play(eventName, context)
	end)
end

return FeelController
