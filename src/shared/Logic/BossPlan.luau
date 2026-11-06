--!strict
-- The Golden Tyrant's action planner and cone test (boss rework spec §2). Pure Luau, so
-- Lune can test it; Server/Services/Boss runs the actions it picks.
--
-- `cooldowns` maps an action to the clock time it is ready again (missing = ready now).
-- Rules, first match wins:
--   1. ultimate  phase 2 and ready (the server arms it ULTIMATE_FIRST_DELAY after enrage)
--   2. chains    ready and the target within chains.range
--   3. armory    ready
--   4. melee     the target within melee.range
--   5. volley    otherwise
local Enemies = if script then require(script.Parent.Parent.Config.Enemies) else require("../Config/Enemies")

export type Action = "melee" | "volley" | "armory" | "chains" | "ultimate"
export type PlanState = {
	phase: number,
	distance: number,
	now: number,
	cooldowns: { [string]: number },
}
export type Vec = { x: number, y: number, z: number }

local W = Enemies.eclipse_warden

local BossPlan = {}

BossPlan.ULTIMATE_FIRST_DELAY = W.ultimate.firstDelay

local function ready(state: PlanState, action: Action): boolean
	return state.now >= (state.cooldowns[action] or 0)
end

function BossPlan.next(state: PlanState): Action
	if state.phase >= 2 and ready(state, "ultimate") then
		return "ultimate"
	end
	if ready(state, "chains") and state.distance <= W.chains.range then
		return "chains"
	end
	if ready(state, "armory") then
		return "armory"
	end
	if state.distance <= W.melee.range then
		return "melee"
	end
	return "volley"
end

-- Seconds until `action` may be picked again after it starts; 0 for the basic attacks.
function BossPlan.cooldown(action: Action, phase: number): number
	if action == "ultimate" then
		return W.ultimate.cooldown
	elseif action == "chains" then
		return W.chains.cooldown
	elseif action == "armory" then
		return W.armory.cooldown[if phase >= 2 then 2 else 1]
	end
	return 0
end

-- True when `point` lies within `length` of `origin` and within `halfAngleDeg` of `dir`.
-- `dir` need not be unit length; a zero `dir` hits nothing, a point on the origin is hit.
function BossPlan.inCone(origin: Vec, dir: Vec, point: Vec, length: number, halfAngleDeg: number): boolean
	local dx, dy, dz = point.x - origin.x, point.y - origin.y, point.z - origin.z
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	if distance > length then
		return false
	end
	local dirLength = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
	if dirLength < 1e-9 then
		return false
	end
	if distance < 1e-9 then
		return true
	end
	local cos = (dx * dir.x + dy * dir.y + dz * dir.z) / (distance * dirLength)
	return cos >= math.cos(math.rad(halfAngleDeg))
end

return BossPlan
