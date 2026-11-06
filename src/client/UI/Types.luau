--!strict
-- UI-side types. Payload types come from Shared.Net (spec §5.3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

export type PlayerState = Net.PlayerState
export type GemInstance = Net.GemInstance

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

-- Sockets are dense arrays with `false` for an empty slot (see Net.PlayerState).
local function socketAt(state: PlayerState, skillId: string, slot: number): GemInstance?
	local row = state.sockets[skillId]
	if not row then
		return nil
	end
	local gem = row[slot]
	if gem then
		return gem :: GemInstance
	end
	return nil
end

return {
	socketAt = socketAt,
}
