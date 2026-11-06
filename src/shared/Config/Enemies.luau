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

export type EclipseWarden = {
	id: string,
	displayName: string,
	level: number,
	hp: (level: number) -> number,
	xp: (level: number) -> number,
	gemDrops: number,
	summonLevel: number,
	altarCooldown: number,
	scale: number,
	speed: number,
	aggroRange: number,
	bodyColor: RGB,
	eyeColor: RGB,
	enrageEyeColor: RGB,
	slam: { interval: number, telegraph: number, radius: number, damage: number },
	blades: { count: number, telegraph: number, radius: number, damage: number, scatter: number },
	phase2At: number,
	enrageSpeedMul: number,
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
	aggroRange = 60,
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
	displayName = "Hộ Vệ Nhật Thực",
	level = 12,
	hp = function(_level: number): number
		return 4000
	end,
	xp = function(_level: number): number
		return 2000
	end,
	gemDrops = 2,
	summonLevel = 8,
	altarCooldown = 60,
	scale = 3,
	speed = 12,
	aggroRange = 150,
	bodyColor = { 18, 14, 24 },
	eyeColor = { 255, 70, 60 },
	enrageEyeColor = { 190, 90, 255 },
	slam = { interval = 5, telegraph = 1.2, radius = 16, damage = 35 },
	blades = { count = 8, telegraph = 1, radius = 5, damage = 25, scatter = 12 },
	phase2At = 0.5,
	enrageSpeedMul = 1.25,
}

return {
	hollow_knight = hollowKnight,
	eclipse_warden = eclipseWarden,
}
