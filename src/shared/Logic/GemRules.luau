--!strict
-- Pure socket rules for support gems (spec 4.3). No Roblox globals.
local Skills = if script then require(script.Parent.Parent.Config.Skills) else require("../Config/Skills")
local Gems = if script then require(script.Parent.Parent.Config.Gems) else require("../Config/Gems")

export type Reason = "no_sockets" | "bad_slot" | "tag" | "element" | "duplicate"

local GemRules = {}

local function skillOf(skillId: string): Skills.Skill?
	if skillId == "order" then
		return nil
	end
	return Skills[skillId]
end

local function gemOf(gemId: string): Gems.Gem?
	if gemId == "order" then
		return nil
	end
	return Gems[gemId]
end

function GemRules.isAttack(skillId: string): boolean
	local skill = skillOf(skillId)
	return skill ~= nil and skill.damage ~= nil
end

local function fits(skill: Skills.Skill, gem: Gems.Gem): boolean
	local tags = skill.tags
	if gem.fits == "Projectile" then
		return tags.Projectile == true
	elseif gem.fits == "Attack" then
		return skill.damage ~= nil
	elseif gem.fits == "AoEOrProjectile" then
		return tags.AoE == true or tags.Projectile == true
	elseif gem.fits == "Any" then
		return true
	end
	return false
end

-- `sockets` maps slot -> gemId for the skill's current sockets. The target slot is
-- ignored, so replacing the gem in a slot is checked as if that slot were empty.
function GemRules.canSocket(
	skillId: string,
	slot: number,
	gemId: string,
	sockets: { [number]: string? }
): (boolean, Reason?)
	local skill = skillOf(skillId)
	if skill == nil or skill.sockets <= 0 then
		return false, "no_sockets"
	end
	if slot ~= math.floor(slot) or slot < 1 or slot > skill.sockets then
		return false, "bad_slot"
	end
	local gem = gemOf(gemId)
	if gem == nil or not fits(skill, gem) then
		return false, "tag"
	end
	for otherSlot, otherId in sockets do
		if otherSlot ~= slot and otherId == gemId then
			return false, "duplicate"
		end
	end
	if gem.group ~= nil then
		for otherSlot, otherId in sockets do
			local other = if otherSlot ~= slot and otherId ~= nil then gemOf(otherId) else nil
			if other ~= nil and other.group == gem.group then
				return false, "element"
			end
		end
	end
	return true, nil
end

return GemRules
