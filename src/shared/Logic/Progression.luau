--!strict
-- Pure level and XP rules. No Roblox globals.
local Config = if script
	then require(script.Parent.Parent.Config.Progression)
	else require("../Config/Progression")

local Progression = {}

function Progression.xpToNext(level: number): number
	return math.floor(Config.xpBase * level ^ Config.xpExp)
end

-- Adds `amount` XP and resolves every level crossed. XP past max level is discarded.
-- Returns the new level, the new xp into that level and how many levels were gained.
function Progression.addXp(level: number, xp: number, amount: number): (number, number, number)
	local newLevel = math.clamp(level, 1, Config.maxLevel)
	local newXp = xp + math.max(amount, 0)
	while newLevel < Config.maxLevel do
		local need = Progression.xpToNext(newLevel)
		if newXp < need then
			break
		end
		newXp -= need
		newLevel += 1
	end
	if newLevel >= Config.maxLevel then
		newXp = 0
	end
	return newLevel, newXp, newLevel - level
end

return Progression
