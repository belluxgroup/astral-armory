--!strict
-- Crit roll (contract addendum 2). `base` already includes every damage multiplier.
-- `rng` returns a value in [0, 1), so tests can pass a fixed function.
local Damage = {}

type CritStats = { critChance: number, critMul: number }

function Damage.roll(base: number, stats: CritStats, rng: () -> number): (number, boolean)
	if rng() < stats.critChance then
		return base * stats.critMul, true
	end
	return base, false
end

return Damage
