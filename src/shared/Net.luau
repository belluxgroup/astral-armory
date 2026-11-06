--!strict
-- Remote names, payload types and remote creation (spec §5.2, contract addendum 9).
-- The server calls Net.server() once at boot; clients call Net.client().
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Element = "none" | "frost" | "flame" | "storm"

export type GemInstance = { id: string, gemId: string }

-- Spec §5.5. Produced by Logic/Stats.
export type Stats = {
	damageMul: number,
	maxHp: number,
	maxEnergy: number,
	energyRegen: number,
	maxStamina: number,
	staminaRegen: number,
	cooldownMul: number,
	moveSpeed: number,
	critChance: number,
	critMul: number,
	aoeMul: number,
	shieldMul: number,
	keystones: { [string]: true },
}

-- Spec §5.4 plus contract addendum 1. Produced by Logic/SkillResolver.
export type SkillSpec = {
	skillId: string,
	damage: number,
	cooldown: number,
	cost: number,
	costResource: "energy" | "hp",
	count: number,
	radius: number,
	range: number,
	length: number?,
	width: number?,
	speed: number?,
	channel: number?,
	duration: number?,
	absorb: number?,
	element: Element,
	pierce: boolean,
	impactExplosion: boolean,
	spreadDeg: number?,
	radiant: boolean,
	drainPerSec: number?,
}

-- StateSync payload (spec §5.3), sent to the owning player.
export type PlayerState = {
	level: number,
	xp: number,
	xpToNext: number,
	points: number,
	allocated: { [string]: true },
	gems: { GemInstance },
	-- skillId -> slot -> gem. Each socketed skill is a dense array of its slots, with `false`
	-- for an empty slot, because remotes truncate arrays at the first nil. Test with `if gem then`.
	sockets: { [string]: { GemInstance | false } },
	hp: number,
	maxHp: number,
	energy: number,
	maxEnergy: number,
	stamina: number,
	maxStamina: number,
	cooldowns: { [string]: number },
	transformed: boolean,
	transformEndsAt: number?,
	serverClock: number,
}

-- SkillFx payload (spec §5.4), sent to all clients.
-- `combo` is set only for `basic` (1, 2 or 3; 3 is the heavy hit).
export type FxEvent = {
	skillId: string,
	casterUserId: number,
	origin: Vector3,
	target: Vector3,
	spec: SkillSpec,
	seed: number,
	serverTime: number,
	combo: number?,
}

-- DamagePopup payload, sent to all clients.
export type DamagePopup = {
	position: Vector3,
	amount: number,
	crit: boolean,
	element: Element,
}

export type BossEvent =
	"spawn"
	| "pose"
	| "melee"
	| "volley"
	| "armory"
	| "chains"
	| "ultimate_charge"
	| "ultimate_fire"
	| "enrage"
	| "defeated"

-- BossFx payload (boss rework spec §3), sent to all clients. Every event carries `model`
-- (the boss, streamed to every client) and `event`. Times are seconds from receipt,
-- `dir` is flat and unit length, `angle` is the cone half-angle in degrees.
--   spawn            position
--   pose             clip: a PoseClips name to play on `model` (boss_idle on spawn, then
--                    boss_melee, boss_volley, boss_armory, boss_chains, boss_ultimate_charge,
--                    boss_ultimate_fire, boss_enrage, boss_defeated, each with its action)
--   melee            origin, dir, delay (windup until the cut lands)
--   volley           portals, targets, delay, interval: weapon i flies from portals[i] and
--                    lands on targets[i] at delay + (i - 1) * interval
--   armory           portals, targets, delay, interval, telegraph: as volley; each landing
--                    has a line telegraph that fills over the `telegraph` before it
--   chains           position, radius, delay (ring fill), duration (root time after delay)
--   ultimate_charge  origin, dir, duration, length, angle
--   ultimate_fire    origin, dir, length, angle
--   enrage           (none)
--   defeated         position
export type BossFx = {
	model: Model,
	event: BossEvent,
	position: Vector3?,
	clip: string?,
	origin: Vector3?,
	dir: Vector3?,
	delay: number?,
	interval: number?,
	telegraph: number?,
	portals: { Vector3 }?,
	targets: { Vector3 }?,
	radius: number?,
	duration: number?,
	length: number?,
	angle: number?,
}

export type Remotes = { [string]: RemoteEvent }

local Net = {}

-- Client to server:
--   CastSkill(skillId: string, target: Vector3)
--   AllocatePassive(nodeId: string)
--   ResetPassives()
--   SocketGem(skillId: string, slot: number, gemInstanceId: string?)  -- nil unsockets
--   SummonBoss()
-- Server to client:
--   StateSync(PlayerState)   owner only, at most 10 per second
--   SkillFx(FxEvent)         all
--   DamagePopup(DamagePopup) all
--   BossFx(BossFx)           all
Net.names = {
	CastSkill = "CastSkill",
	AllocatePassive = "AllocatePassive",
	ResetPassives = "ResetPassives",
	SocketGem = "SocketGem",
	SummonBoss = "SummonBoss",
	StateSync = "StateSync",
	SkillFx = "SkillFx",
	DamagePopup = "DamagePopup",
	BossFx = "BossFx",
}

local FOLDER_NAME = "Remotes"
local WAIT_TIMEOUT = 10

local cached: Remotes? = nil

-- Creates ReplicatedStorage.Remotes with one RemoteEvent per name. Safe to call more than once.
function Net.server(): Remotes
	assert(RunService:IsServer(), "Net.server() must run on the server")
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
	assert(folder, "Net: Remotes folder missing")
	local remotes: Remotes = {}
	for _, name in Net.names :: { [string]: string } do
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			remotes[name] = existing
		else
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
			remotes[name] = remote
		end
	end
	cached = remotes
	return remotes
end

-- Waits up to 10 s for each remote and errors with the missing name.
function Net.client(): Remotes
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	if not folder then
		error(`Net: missing ReplicatedStorage.{FOLDER_NAME}`)
	end
	local remotes: Remotes = {}
	for _, name in Net.names :: { [string]: string } do
		local remote = folder:WaitForChild(name, WAIT_TIMEOUT)
		if not remote or not remote:IsA("RemoteEvent") then
			error(`Net: missing remote {name}`)
		end
		remotes[name] = remote
	end
	cached = remotes
	return remotes
end

return Net
