--!strict
-- Client-side mirror of the payload types in spec §5.3, shared by the UI screens and Input.

export type Element = "none" | "frost" | "flame" | "storm"

export type GemInstance = { id: string, gemId: string }

export type PlayerState = {
	level: number,
	xp: number,
	xpToNext: number,
	points: number,
	allocated: { [string]: true },
	gems: { GemInstance },
	sockets: { [string]: { [any]: GemInstance? } },
	hp: number,
	maxHp: number,
	energy: number,
	maxEnergy: number,
	cooldowns: { [string]: number },
	transformed: boolean,
	transformEndsAt: number?,
	serverClock: number,
}

-- Remote calls the UI needs. Input owns the remotes and installs these through ui.setActions.
export type Actions = {
	allocatePassive: (nodeId: string) -> (),
	resetPassives: () -> (),
	socketGem: (skillId: string, slot: number, gemInstanceId: string?) -> (),
	summonBoss: () -> (),
}

export type UIHandle = {
	togglePassives: () -> (),
	toggleGems: () -> (),
	getState: () -> PlayerState?,
	cooldownLeft: (skillId: string) -> number,
	setActions: (actions: Actions) -> (),
}

-- Sockets cross the network as a sparse table, which Roblox may re-key with strings. Read both forms.
local function socketAt(state: PlayerState, skillId: string, slot: number): GemInstance?
	local row = state.sockets[skillId]
	if not row then
		return nil
	end
	return row[slot] or row[tostring(slot)]
end

return {
	socketAt = socketAt,
}
