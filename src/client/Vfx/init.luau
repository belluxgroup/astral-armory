--!strict
-- VFX controller (contract addendum item 7). `Vfx.start()` connects SkillFx
-- and dispatches each FxEvent to the module for its skill. Effects only render:
-- every number they show comes from the event's `spec`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Common = require(script.Common)

type FxEvent = Common.FxEvent
type Handler = { play: (event: FxEvent) -> () }

local Vfx = {}

local handlers: { [string]: Handler } = {
	blade_rain = require(script.BladeRain),
	dawnbreaker = require(script.Dawnbreaker),
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
	if Common.age(event.serverTime) > Common.MAX_EVENT_AGE then
		return
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
end

return Vfx
