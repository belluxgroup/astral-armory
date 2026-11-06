--!strict
-- Dodge roll, backstep and stamina tuning (dodge spec §1-2). Pure data plus small pure
-- helpers, shared by the server rules (Rules/Dodge, Logic/Stamina), the client motion
-- (Input/Dodge), the poses (Config/PoseClips) and the VFX (Vfx/Dodge), so every side
-- agrees on the same timings. Max stamina and regen live on Stats (spec §1).

export type Kind = "roll" | "backstep"

-- Times are seconds from the dodge start. `land` is when the feet are back on the
-- ground (landing dust, the end of the somersault).
export type Move = {
	duration: number,
	distance: number,
	iframeStart: number,
	iframeEnd: number,
	land: number,
	cost: number,
	clip: string,
}

local Dodge = {}

-- Counted from the dodge start.
Dodge.cooldown = 0.8
-- The server accepts a dodge this much early, so network jitter between two presses
-- exactly one cooldown apart on the client never refuses the second.
Dodge.cooldownSlack = 0.1
-- After-the-fact sanity check on the server: flat studs moved over one dodge. A roll
-- that carries the held run (Input/Dodge) covers about 16 studs, and the check runs
-- 0.2 s after the roll, by which time the player has run about 3.6 more.
Dodge.maxDisplacement = 24
-- A move direction shorter than this counts as standing still: backstep.
Dodge.moveThreshold = 0.1

Dodge.staminaRegenDelay = 0.7
Dodge.basicStaminaCost = 8

Dodge.moves = {
	roll = {
		duration = 0.55,
		distance = 14,
		iframeStart = 0.10,
		iframeEnd = 0.40,
		land = 0.40,
		cost = 22,
		clip = "dodge_roll",
	} :: Move,
	backstep = {
		duration = 0.35,
		distance = 6,
		iframeStart = 0.05,
		iframeEnd = 0.22,
		land = 0.26,
		cost = 12,
		clip = "dodge_backstep",
	} :: Move,
}

-- Roll when the world-space move direction (x, z) is long enough, else backstep.
function Dodge.kindFor(x: number, z: number): Kind
	if x ~= x or z ~= z or x * x + z * z < Dodge.moveThreshold * Dodge.moveThreshold then
		return "backstep"
	end
	return "roll"
end

function Dodge.move(kind: Kind): Move
	return if kind == "roll" then Dodge.moves.roll else Dodge.moves.backstep
end

-- Ease-out speed (studs/s) at `alpha` = elapsed / duration: fastest at the start, 0 at
-- the end. v = 2D/T * (1 - alpha) integrates to exactly `distance` over the move.
function Dodge.speedAt(kind: Kind, alpha: number): number
	local move = Dodge.move(kind)
	return 2 * move.distance / move.duration * (1 - math.clamp(alpha, 0, 1))
end

return Dodge
