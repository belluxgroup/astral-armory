--!strict
-- Level curve tuning. xpToNext(L) = floor(xpBase * L ^ xpExp).
export type ProgressionConfig = {
	maxLevel: number,
	pointsPerLevel: number,
	xpBase: number,
	xpExp: number,
}

local Progression: ProgressionConfig = {
	maxLevel = 20,
	pointsPerLevel = 1,
	xpBase = 100,
	xpExp = 1.5,
}

return table.freeze(Progression)
