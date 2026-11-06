--!strict
-- Skill definitions (spec 4.2). Iterate through `order`, never `pairs`.
export type Skill = {
	id: string,
	key: string,
	displayName: string,
	tags: { [string]: true },
	cost: number,
	cooldown: number,
	sockets: number,
	unlockLevel: number?,
	damage: number?,
	count: number?,
	radius: number?,
	range: number?,
	length: number?,
	width: number?,
	speed: number?,
	channel: number?,
	duration: number?,
	absorb: number?,
	pierce: boolean?,
	ignoresArmor: boolean?,
	comboHits: number?,
	comboMul: number?,
	damageBonus: number?,
	regenBonus: number?,
}

export type SkillsConfig = {
	order: { string },
	[string]: Skill,
}

local Skills: SkillsConfig = {
	order = { "basic", "blade_rain", "dawnbreaker", "crimson_lance", "hex_aegis", "ascension" },

	basic = {
		id = "basic",
		key = "M1",
		displayName = "Chém",
		tags = { Melee = true },
		cost = 0,
		cooldown = 0.35,
		sockets = 0,
		damage = 12,
		range = 8,
		comboHits = 3,
		comboMul = 1.6,
	},

	blade_rain = {
		id = "blade_rain",
		key = "Q",
		displayName = "Mưa Kiếm Tinh Tú",
		tags = { Projectile = true, AoE = true, Summon = true },
		cost = 30,
		cooldown = 6,
		sockets = 2,
		damage = 18,
		count = 12,
		radius = 14,
		range = 60,
	},

	dawnbreaker = {
		id = "dawnbreaker",
		key = "E",
		displayName = "Cột Sáng Bình Minh",
		tags = { Channel = true, Line = true },
		cost = 40,
		cooldown = 8,
		sockets = 2,
		damage = 90,
		channel = 1.2,
		range = 40,
		length = 40,
		width = 8,
	},

	crimson_lance = {
		id = "crimson_lance",
		key = "R",
		displayName = "Giáo Huyết",
		tags = { Projectile = true, Pierce = true },
		cost = 25,
		cooldown = 5,
		sockets = 2,
		damage = 60,
		speed = 120,
		range = 80,
		pierce = true,
		ignoresArmor = true,
	},

	hex_aegis = {
		id = "hex_aegis",
		key = "F",
		displayName = "Khiên Lục Giác",
		tags = { Defense = true, Duration = true },
		cost = 35,
		cooldown = 14,
		sockets = 2,
		duration = 3,
		absorb = 80,
	},

	ascension = {
		id = "ascension",
		key = "T",
		displayName = "Thăng Hoa",
		tags = { Buff = true, Transform = true },
		cost = 50,
		cooldown = 45,
		sockets = 0,
		unlockLevel = 10,
		duration = 20,
		damageBonus = 0.30,
		regenBonus = 0.50,
	},
}

return Skills
