--!strict
-- Pure cooldown bookkeeping. `cooldowns` maps skillId -> os.clock() time when the skill is ready.
local Cooldowns = {}

function Cooldowns.ready(cooldowns: { [string]: number }, skillId: string, now: number): boolean
	local readyAt = cooldowns[skillId]
	return readyAt == nil or now >= readyAt
end

function Cooldowns.start(cooldowns: { [string]: number }, skillId: string, now: number, duration: number)
	cooldowns[skillId] = now + math.max(0, duration)
end

return Cooldowns
