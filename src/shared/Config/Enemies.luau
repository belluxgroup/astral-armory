--!strict
-- Enemy and boss tuning (spec §4.6). Pure data: colors are { r, g, b } in 0..255.
export type RGB = { number }

export type HollowKnight = {
	id: string,
	displayName: string,
	hp: (level: number) -> number,
	damage: (level: number) -> number,
	xp: (level: number) -> number,
	speed: number,
	attackRange: number,
	attackCooldown: number,
	aggroRange: number,
	respawnDelay: number,
	contributionWindow: number,
	gemDropChance: number,
	innerCount: number,
	innerLevels: { number },
	outerCount: number,
	outerLevels: { number },
	scale: number,
	bodyColor: RGB,
	eyeColor: RGB,
}

-- The Golden Tyrant (boss rework spec §2). The id stays `eclipse_warden` so keys and saves
-- do not change. Times are seconds, distances studs, angles degrees. Two-entry lists are
-- { phase 1, phase 2 }.
export type EclipseWarden = {
	id: string,
	displayName: string,
	level: number,
	hp: (level: number) -> number,
	xp: (level: number) -> number,
	gemDrops: number,
	summonLevel: number,
	summonRange: number,
	altarCooldown: number,
	scale: number,
	speed: number,
	aggroRange: number,
	stopDistance: number,
	bodyColor: RGB,
	cadence: { number },
	phase2At: number,
	enrageSpeedMul: number,
	enragePause: number,
	melee: { range: number, windup: number, length: number, width: number, height: number, damage: number },
	volley: {
		count: number,
		aimDelay: number,
		delay: number,
		interval: number,
		radius: number,
		damage: number,
		jitter: number,
	},
	armory: {
		cooldown: { number },
		count: { number },
		delay: number,
		interval: number,
		telegraph: number,
		radius: number,
		damage: number,
		scatter: number,
		fanRadius: number,
		fanArc: number,
	},
	chains: {
		cooldown: number,
		range: number,
		telegraph: number,
		radius: number,
		duration: number,
		damage: number,
		lungeWindup: number,
	},
	ultimate: {
		cooldown: number,
		firstDelay: number,
		charge: number,
		length: number,
		angle: number,
		damage: number,
	},
}

local hollowKnight: HollowKnight = {
	id = "hollow_knight",
	displayName = "Hiệp Sĩ Rỗng",
	hp = function(level: number): number
		return 60 * (1 + 0.25 * (level - 1))
	end,
	damage = function(level: number): number
		return 8 * (1 + 0.2 * (level - 1))
	end,
	xp = function(level: number): number
		return math.floor(20 * level ^ 1.2)
	end,
	speed = 14,
	attackRange = 5,
	attackCooldown = 1.2,
	aggroRange = 45, -- below the 54-stud gap from PlayerSpawn to the nearest ring spawn
	respawnDelay = 8,
	contributionWindow = 10,
	gemDropChance = 0.12,
	innerCount = 4,
	innerLevels = { 1, 3 },
	outerCount = 6,
	outerLevels = { 4, 8 },
	scale = 1,
	bodyColor = { 28, 26, 36 },
	eyeColor = { 120, 220, 255 },
}

local eclipseWarden: EclipseWarden = {
	id = "eclipse_warden",
	displayName = "Bạo Quân Hoàng Kim",
	level = 12,
	hp = function(_level: number): number
		return 4000
	end,
	xp = function(_level: number): number
		return 2000
	end,
	gemDrops = 2,
	summonLevel = 8,
	summonRange = 20, -- studs from the altar, for the remote and the HUD button
	altarCooldown = 60,
	scale = 1.6,
	speed = 12,
	aggroRange = 150,
	stopDistance = 6, -- stops walking this close to the target
	bodyColor = { 26, 20, 32 }, -- obsidian undersuit #1A1420
	cadence = { 1.6, 1.2 }, -- seconds between action starts
	phase2At = 0.5,
	enrageSpeedMul = 1.25,
	enragePause = 1, -- the roar holds the boss in place
	-- a cut in a box in front of the boss
	melee = { range = 9, windup = 0.35, length = 10, width = 6, height = 8, damage = 20 },
	-- 3 portals behind the boss; aim locks aimDelay after the snap, weapon i lands at
	-- delay + (i - 1) * interval after the volley event
	volley = {
		count = 3,
		aimDelay = 0.6,
		delay = 0.5,
		interval = 0.12,
		radius = 3,
		damage = 12,
		jitter = 1.5,
	},
	-- a fan of portals; weapon i lands at delay + (i - 1) * interval, its line telegraph
	-- shows for `telegraph` before that
	armory = {
		cooldown = { 14, 10 },
		count = { 10, 16 },
		delay = 0.7,
		interval = 0.12,
		telegraph = 0.5,
		radius = 4,
		damage = 18,
		scatter = 5,
		fanRadius = 9,
		fanArc = 160,
	},
	-- a ring at the target's feet, then a root, then a lunging cut at the rooted player
	chains = {
		cooldown = 12,
		range = 40,
		telegraph = 1,
		radius = 6,
		duration = 1.5,
		damage = 10,
		lungeWindup = 0.15,
	},
	-- phase 2 only; `angle` is the cone half-angle
	ultimate = { cooldown = 22, firstDelay = 4, charge = 2.5, length = 70, angle = 22, damage = 70 },
}

return {
	hollow_knight = hollowKnight,
	eclipse_warden = eclipseWarden,
}
