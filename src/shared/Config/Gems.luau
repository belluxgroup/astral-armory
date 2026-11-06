--!strict
-- Support gem definitions (spec 4.3).
-- fits: "Projectile" (skill has the Projectile tag), "Attack" (skill deals damage),
-- "AoEOrProjectile" (skill has AoE or Projectile), "Any" (any socketed skill).
export type GemFit = "Projectile" | "Attack" | "AoEOrProjectile" | "Any"

export type Gem = {
	id: string,
	displayName: string,
	fits: GemFit,
	group: string?,
	damageMul: number?,
	extraBlades: number?,
	extraLances: number?,
	spreadDeg: number?,
	element: string?,
	radiusMul: number?,
	impactExplosion: boolean?,
	cooldownMul: number?,
	-- element and explosion tuning, read by the combat server
	slowPct: number?,
	slowDuration: number?,
	burnPct: number?,
	burnDuration: number?,
	chainCount: number?,
	chainPct: number?,
	explosionRadius: number?,
	explosionPct: number?,
}

export type GemsConfig = {
	order: { string },
	[string]: Gem,
}

local Gems: GemsConfig = {
	order = { "multishot", "frost", "flame", "storm", "wide_burst", "swift_cast" },

	multishot = {
		id = "multishot",
		displayName = "Đa Phát",
		fits = "Projectile",
		extraBlades = 4,
		extraLances = 2,
		spreadDeg = 20,
		damageMul = 0.85,
	},

	frost = {
		id = "frost",
		displayName = "Băng",
		fits = "Attack",
		group = "element",
		element = "frost",
		slowPct = 0.30,
		slowDuration = 2,
	},

	flame = {
		id = "flame",
		displayName = "Hoả",
		fits = "Attack",
		group = "element",
		element = "flame",
		burnPct = 0.20,
		burnDuration = 3,
	},

	storm = {
		id = "storm",
		displayName = "Lôi",
		fits = "Attack",
		group = "element",
		element = "storm",
		chainCount = 2,
		chainPct = 0.50,
	},

	wide_burst = {
		id = "wide_burst",
		displayName = "Nổ Lan",
		fits = "AoEOrProjectile",
		radiusMul = 1.4,
		impactExplosion = true,
		explosionRadius = 6,
		explosionPct = 0.30,
	},

	swift_cast = {
		id = "swift_cast",
		displayName = "Tốc Thi",
		fits = "Any",
		cooldownMul = 0.75,
	},
}

return Gems
