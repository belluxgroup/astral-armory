--!strict
-- Pure dodge bookkeeping (dodge spec §2): which move a direction asks for, the cooldown
-- from the dodge start, the active window (no skills) and the i-frame window per move,
-- and the after-the-fact displacement check. Times are os.clock() seconds.
local function lune(path: string): any
	return (require :: any)(path)
end

local DodgeConfig = if script
	then require(game:GetService("ReplicatedStorage").Shared.Config.Dodge)
	else lune("../../shared/Config/Dodge")

export type Kind = "roll" | "backstep"
export type State = { kind: Kind, startedAt: number }

local Dodge = {}

Dodge.kindFor = DodgeConfig.kindFor

function Dodge.new(): State
	return { kind = "roll", startedAt = -math.huge }
end

function Dodge.ready(s: State, now: number): boolean
	return now >= s.startedAt + DodgeConfig.cooldown - DodgeConfig.cooldownSlack
end

function Dodge.start(s: State, kind: Kind, now: number)
	s.kind = kind
	s.startedAt = now
end

-- True for the whole move: skills are refused, basic recovery is already cancelled.
function Dodge.active(s: State, now: number): boolean
	return now >= s.startedAt and now < s.startedAt + DodgeConfig.move(s.kind).duration
end

-- True inside the move's i-frame window: no damage, no boss chains root.
function Dodge.invulnerable(s: State, now: number): boolean
	local move = DodgeConfig.move(s.kind)
	return now >= s.startedAt + move.iframeStart and now <= s.startedAt + move.iframeEnd
end

-- Flat distance moved over one dodge, in studs, against the sanity limit.
function Dodge.withinDisplacement(dx: number, dz: number): boolean
	return dx * dx + dz * dz <= DodgeConfig.maxDisplacement * DodgeConfig.maxDisplacement
end

return Dodge
