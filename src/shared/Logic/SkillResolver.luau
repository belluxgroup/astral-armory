--!strict
-- The only place that turns skill config + socketed gems + stats into final numbers
-- (spec 5.4 and contract addendum 1-3). The server deals damage from the result and
-- sends the same spec to clients for VFX. No Roblox globals.
local Skills = if script then require(script.Parent.Parent.Config.Skills) else require("../Config/Skills")
local Gems = if script then require(script.Parent.Parent.Config.Gems) else require("../Config/Gems")
local Stats = if script then require(script.Parent.Stats) else require("./Stats")

export type Element = "none" | "frost" | "flame" | "storm"

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

local SkillResolver = {}

SkillResolver.ENDLESS_ARSENAL_BLADES = 6
SkillResolver.ENDLESS_ARSENAL_DAMAGE = 0.75
SkillResolver.RADIANT_MIND_DRAIN = 6

function SkillResolver.resolve(
	skillId: string,
	socketedGemIds: { string },
	stats: Stats.Stats,
	transformed: boolean
): SkillSpec
	local skill = if skillId ~= "order" then Skills[skillId] else nil
	if skill == nil then
		error(`unknown skill {skillId}`, 2)
	end

	local damageMul, radiusMul, cooldownMul = 1, 1, 1
	local extraBlades, extraLances = 0, 0
	local element: Element = "none"
	local impactExplosion = false
	local spreadDeg: number? = nil
	for _, gemId in socketedGemIds do
		local gem = if gemId ~= "order" then Gems[gemId] else nil
		if gem ~= nil then
			damageMul *= gem.damageMul or 1
			radiusMul *= gem.radiusMul or 1
			cooldownMul *= gem.cooldownMul or 1
			extraBlades += gem.extraBlades or 0
			extraLances += gem.extraLances or 0
			if gem.element ~= nil and element == "none" then
				element = gem.element :: Element
			end
			if gem.impactExplosion then
				impactExplosion = true
			end
			if gem.spreadDeg ~= nil then
				spreadDeg = gem.spreadDeg
			end
		end
	end

	local keystones = stats.keystones
	local count = skill.count or 1
	if skillId == "blade_rain" then
		count += extraBlades
		if keystones.endless_arsenal then
			count += SkillResolver.ENDLESS_ARSENAL_BLADES
			damageMul *= SkillResolver.ENDLESS_ARSENAL_DAMAGE
		end
	elseif skillId == "crimson_lance" then
		count += extraLances
	end
	if not (skillId == "crimson_lance" and extraLances > 0) then
		spreadDeg = nil
	end

	local duration = skill.duration
	local drainPerSec: number? = nil
	if skillId == "ascension" and keystones.radiant_mind then
		duration = math.huge
		drainPerSec = SkillResolver.RADIANT_MIND_DRAIN
	end

	return {
		skillId = skillId,
		damage = (skill.damage or 0) * stats.damageMul * damageMul,
		cooldown = skill.cooldown * stats.cooldownMul * cooldownMul,
		cost = skill.cost,
		costResource = if keystones.blood_oath then "hp" else "energy",
		count = count,
		radius = (skill.radius or 0) * stats.aoeMul * radiusMul,
		range = skill.range or 0,
		length = skill.length,
		width = skill.width,
		speed = skill.speed,
		channel = skill.channel,
		duration = duration,
		absorb = if skill.absorb ~= nil then skill.absorb * stats.shieldMul else nil,
		element = element,
		pierce = skill.pierce == true,
		impactExplosion = impactExplosion,
		spreadDeg = spreadDeg,
		radiant = transformed,
		drainPerSec = drainPerSec,
	}
end

return SkillResolver
