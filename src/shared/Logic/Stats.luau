--!strict
-- Derived player stats from level, passives and buffs (spec 4.1, 5.5). No Roblox globals.
local Passives = if script
	then require(script.Parent.Parent.Config.Passives)
	else require("../Config/Passives")
local Skills = if script then require(script.Parent.Parent.Config.Skills) else require("../Config/Skills")

export type Stats = {
	damageMul: number,
	maxHp: number,
	maxEnergy: number,
	energyRegen: number,
	cooldownMul: number,
	moveSpeed: number,
	critChance: number,
	critMul: number,
	aoeMul: number,
	shieldMul: number,
	keystones: { [string]: true },
}

export type Buffs = { transformed: boolean }

local Stats = {}

Stats.BASE = table.freeze({
	maxHp = 100,
	maxHpPerLevel = 10,
	maxEnergy = 100,
	energyRegen = 8,
	moveSpeed = 18,
	critChance = 0.05,
	critMul = 1.5,
})

Stats.BLOOD_OATH_DAMAGE = 1.4

-- Passive mod stat name -> Stats field.
local FIELD: { [string]: string } = {
	damage = "damageMul",
	cooldown = "cooldownMul",
	aoe = "aoeMul",
	shield = "shieldMul",
	maxHp = "maxHp",
	maxEnergy = "maxEnergy",
	energyRegen = "energyRegen",
	moveSpeed = "moveSpeed",
	critChance = "critChance",
	critMul = "critMul",
}

function Stats.compute(level: number, allocated: { [string]: true }, buffs: Buffs): Stats
	local base = Stats.BASE
	local values: { [string]: number } = {
		damageMul = 1,
		maxHp = base.maxHp + base.maxHpPerLevel * (math.max(level, 1) - 1),
		maxEnergy = base.maxEnergy,
		energyRegen = base.energyRegen,
		cooldownMul = 1,
		moveSpeed = base.moveSpeed,
		critChance = base.critChance,
		critMul = base.critMul,
		aoeMul = 1,
		shieldMul = 1,
	}
	local adds: { [string]: number } = {}
	local muls: { [string]: number } = {}
	local keystones: { [string]: true } = {}

	for id in allocated do
		local node = Passives.nodes[id]
		if node ~= nil then
			if node.keystone ~= nil then
				keystones[node.keystone] = true
			end
			for _, mod in node.mods do
				local field = FIELD[mod.stat]
				if field ~= nil then
					if mod.op == "add" then
						adds[field] = (adds[field] or 0) + mod.value
					else
						muls[field] = (muls[field] or 1) * (1 + mod.value)
					end
				end
			end
		end
	end

	for field, value in values do
		values[field] = (value + (adds[field] or 0)) * (muls[field] or 1)
	end

	if keystones.blood_oath then
		values.damageMul *= Stats.BLOOD_OATH_DAMAGE
	end
	if buffs.transformed then
		local ascension = Skills.ascension
		values.damageMul *= 1 + (ascension.damageBonus or 0)
		values.energyRegen *= 1 + (ascension.regenBonus or 0)
	end

	return {
		damageMul = values.damageMul,
		maxHp = values.maxHp,
		maxEnergy = values.maxEnergy,
		energyRegen = values.energyRegen,
		cooldownMul = values.cooldownMul,
		moveSpeed = values.moveSpeed,
		critChance = values.critChance,
		critMul = values.critMul,
		aoeMul = values.aoeMul,
		shieldMul = values.shieldMul,
		keystones = keystones,
	}
end

return Stats
