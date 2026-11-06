--!strict
-- Deterministic blade impact layout for Mưa Kiếm Tinh Tú (blade_rain).
-- The server (hit points) and every client (VFX) call this with the same seed,
-- so all of them agree on where each blade lands. Pure Luau: no Roblox globals.

export type BladePoint = { x: number, z: number, delay: number }

local BladeLayout = {}

local MOD = 4294967296 -- 2^32
local MUL = 1664525
local INC = 1013904223
local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))

BladeLayout.MAX_DELAY = 0.35

local function makeRng(seed: number): () -> number
	-- Fold any number (negative, fractional, huge) into a 32-bit state.
	local state = math.floor(math.abs(seed) * 1000 + 0.5) % MOD
	state = (state * MUL + INC) % MOD
	return function(): number
		-- MUL * state < 2^53, so this stays exact in double precision.
		state = (state * MUL + INC) % MOD
		return state / MOD
	end
end

-- Returns `count` points inside a disc of `radius` around the origin, each with
-- a drop delay in [0, MAX_DELAY]. Points follow a jittered sunflower pattern so
-- blades cover the whole area without clumping, while still looking random.
function BladeLayout.points(seed: number, count: number, radius: number): { BladePoint }
	local rng = makeRng(seed)
	local out: { BladePoint } = table.create(math.max(count, 0))
	local spin = rng() * 2 * math.pi
	for i = 1, count do
		local radial = math.sqrt(math.min((i - 1 + rng()) / count, 1)) * radius
		local angle = spin + i * GOLDEN_ANGLE + (rng() - 0.5) * 0.9
		out[i] = {
			x = math.cos(angle) * radial,
			z = math.sin(angle) * radial,
			delay = rng() * BladeLayout.MAX_DELAY,
		}
	end
	return out
end

return BladeLayout
