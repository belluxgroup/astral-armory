--!strict
-- Stamina rules (dodge spec §1). Pure: no Roblox globals. The server owns the state.
-- An action is allowed while stamina is above 0, even when it costs more than what is
-- left; stamina then floors at 0. Regen starts `staminaRegenDelay` after the last spend.
local Dodge = if script then require(script.Parent.Parent.Config.Dodge) else require("../Config/Dodge")

export type State = { value: number, lastSpendAt: number }

local Stamina = {}

function Stamina.new(max: number): State
	return { value = max, lastSpendAt = -math.huge }
end

function Stamina.canSpend(s: State): boolean
	return s.value > 0
end

-- Spends `cost` at time `now`. Returns false (and changes nothing) at 0 stamina.
function Stamina.spend(s: State, cost: number, now: number): boolean
	if s.value <= 0 then
		return false
	end
	s.value = math.max(0, s.value - cost)
	s.lastSpendAt = now
	return true
end

-- Regenerates over the frame (now - dt, now]. Only the part of the frame after the
-- regen delay counts, so the result does not depend on the frame rate.
function Stamina.regen(s: State, max: number, rate: number, now: number, dt: number)
	local eligible = math.clamp(now - (s.lastSpendAt + Dodge.staminaRegenDelay), 0, dt)
	if eligible > 0 and s.value < max then
		s.value = math.min(max, s.value + rate * eligible)
	end
end

return Stamina
