--!strict
-- Golden Tyrant effects, driven by BossFx (boss spec §3 and §5). Every payload carries the
-- boss `model` and an `event`; this module routes each event to its effect:
--   pose             Vfx/Poses plays the clip on the model
--   spawn            Presence.spawn        enrage    Presence.enrage
--   melee            Melee.play            defeated  Presence.defeated
--   volley, armory   Portal.volley / Portal.armory
--   chains           Chains.play
--   ultimate_charge  Ultimate.charge       ultimate_fire  Ultimate.fire
-- Any event with a model also attaches the boss's idle, cape and halo (late joiners).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PoseClips =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PoseClips"))
local Poses = require(script.Parent.Poses)
local Chains = require(script.Chains)
local Kit = require(script.Kit)
local Melee = require(script.Melee)
local Portal = require(script.Portal)
local Presence = require(script.Presence)
local Ultimate = require(script.Ultimate)

type Payload = Kit.Payload

local Boss = {}

local handlers: { [string]: (Payload, Model?) -> () } = {
	pose = function(evt: Payload)
		Poses.forBossFx(evt)
	end,
	spawn = function(evt: Payload, model: Model?)
		Presence.spawn(model, Kit.vec(evt, "position"))
	end,
	melee = function(evt: Payload, model: Model?)
		-- A shorter windup (the chains lunge) starts the cut clip further in, so the blade
		-- still crosses the strike zone when the hit lands.
		local windup = Kit.num(evt, "delay", PoseClips.BOSS_MELEE_HIT)
		if model and windup < PoseClips.BOSS_MELEE_HIT - 0.01 then
			Poses.play(model, "boss_melee", PoseClips.BOSS_MELEE_HIT - windup)
		end
		Melee.play(evt)
	end,
	volley = function(evt: Payload)
		Portal.volley(evt)
	end,
	armory = function(evt: Payload)
		Portal.armory(evt)
	end,
	chains = function(evt: Payload)
		Chains.play(evt)
	end,
	ultimate_charge = function(evt: Payload)
		Ultimate.charge(evt)
	end,
	ultimate_fire = function(evt: Payload)
		Ultimate.fire(evt)
	end,
	enrage = function(_evt: Payload, model: Model?)
		Presence.enrage(model, true)
	end,
	defeated = function(evt: Payload, model: Model?)
		if model then
			Ultimate.stop(model)
		end
		Presence.defeated(model, Kit.vec(evt, "position"))
	end,
}

function Boss.play(evt: Payload)
	if type(evt) ~= "table" or type(evt.event) ~= "string" then
		return
	end
	local handler = handlers[evt.event]
	if not handler then
		warn(`[Vfx] unknown boss event "{evt.event}"`)
		return
	end
	local model = Kit.model(evt)
	if model and evt.event ~= "defeated" then
		Presence.attach(model)
	end
	handler(evt, model)
end

function Boss.start()
	Presence.start()
end

return Boss
