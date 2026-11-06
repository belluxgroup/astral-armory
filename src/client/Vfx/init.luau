--!strict
-- VFX controller (contract addendum item 7). `Vfx.start()` connects SkillFx,
-- dispatching each FxEvent to the module for its skill, and BossFx. Effects only render:
-- every number they show comes from the event's `spec`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Ascension = require(script.Ascension)
local BossTelegraph = require(script.BossTelegraph)
local Common = require(script.Common)
local Poses = require(script.Poses)

type FxEvent = Common.FxEvent
type Handler = { play: (event: FxEvent) -> () }

local Vfx = {}

-- Exposed for the UI: it drives the local aura from StateSync.transformed.
Vfx.Ascension = Ascension

local handlers: { [string]: Handler } = {
	blade_rain = require(script.BladeRain),
	dawnbreaker = require(script.Dawnbreaker),
	crimson_lance = require(script.CrimsonLance),
	hex_aegis = require(script.HexAegis),
	basic = require(script.BasicSlash),
	ascension = Ascension,
}

local started = false

local function dispatch(event: FxEvent)
	if type(event) ~= "table" or type(event.skillId) ~= "string" then
		return
	end
	local handler = handlers[event.skillId]
	if not handler then
		warn(`[Vfx] no effect for skill "{event.skillId}"`)
		return
	end
	-- Stale events are dropped, except ascension: its aura must still show.
	if event.skillId ~= "ascension" and Common.age(event.serverTime) > Common.MAX_EVENT_AGE then
		return
	end
	-- The caster's body pose (sword swing, cast gesture) plays alongside the effect.
	local okPose, poseErr = pcall(Poses.forEvent, event)
	if not okPose then
		warn(`[Vfx] pose for {event.skillId} failed: {poseErr}`)
	end
	-- Each effect runs in its own thread so one failure never breaks the rest.
	task.spawn(function()
		local ok, err = pcall(handler.play :: any, event)
		if not ok then
			warn(`[Vfx] {event.skillId} failed: {err}`)
		end
	end)
end

function Vfx.start()
	if started then
		return
	end
	started = true
	local remotes = Net.client()
	remotes[Net.names.SkillFx].OnClientEvent:Connect(dispatch)
	remotes[Net.names.BossFx].OnClientEvent:Connect(function(evt: Common.BossFx)
		task.spawn(function()
			local ok, err = pcall(BossTelegraph.play :: any, evt)
			if not ok then
				warn(`[Vfx] boss {type(evt) == "table" and evt.event or "?"} failed: {err}`)
			end
		end)
	end)
end

return Vfx
