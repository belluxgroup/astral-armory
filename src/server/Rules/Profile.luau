--!strict
-- Pure player profile rules: defaults, XP and points, passives, gem sockets, and the
-- DataStore codec that sanitizes whatever comes back from storage. No Roblox globals
-- outside the require branch, so Lune can test it.
-- Roblox resolves the shared modules through ReplicatedStorage; Lune through relative paths.
local function lune(path: string): any
	return (require :: any)(path)
end

local Skills = if script
	then require(game:GetService("ReplicatedStorage").Shared.Config.Skills)
	else lune("../../shared/Config/Skills")
local Gems = if script
	then require(game:GetService("ReplicatedStorage").Shared.Config.Gems)
	else lune("../../shared/Config/Gems")
local Passives = if script
	then require(game:GetService("ReplicatedStorage").Shared.Config.Passives)
	else lune("../../shared/Config/Passives")
local ProgressionConfig = if script
	then require(game:GetService("ReplicatedStorage").Shared.Config.Progression)
	else lune("../../shared/Config/Progression")
local Progression = if script
	then require(game:GetService("ReplicatedStorage").Shared.Logic.Progression)
	else lune("../../shared/Logic/Progression")
local PassiveTree = if script
	then require(game:GetService("ReplicatedStorage").Shared.Logic.PassiveTree)
	else lune("../../shared/Logic/PassiveTree")
local GemRules = if script
	then require(game:GetService("ReplicatedStorage").Shared.Logic.GemRules)
	else lune("../../shared/Logic/GemRules")

export type GemInstance = { id: string, gemId: string }

export type Profile = {
	level: number,
	xp: number,
	points: number,
	allocated: { [string]: true },
	gems: { GemInstance },
	sockets: { [string]: { [number]: GemInstance } },
	nextGemId: number,
}

local STARTER_GEMS = { "frost", "flame", "storm" }
local FORMAT_VERSION = 1

local Profile = {}

local function isSkill(skillId: any): boolean
	return type(skillId) == "string" and table.find(Skills.order, skillId) ~= nil
end

local function isGem(gemId: any): boolean
	return type(gemId) == "string" and table.find(Gems.order, gemId) ~= nil
end

local function socketCount(skillId: string): number
	if not isSkill(skillId) then
		return 0
	end
	return Skills[skillId].sockets
end

local function spentPoints(allocated: { [string]: true }): number
	local n = 0
	for id in allocated do
		if id ~= Passives.startId then
			n += 1
		end
	end
	return n
end

function Profile.earnedPoints(level: number): number
	return (level - 1) * ProgressionConfig.pointsPerLevel
end

-- Points are always derived (earned by level minus spent), so they can never drift.
local function recount(p: Profile)
	local spent = spentPoints(p.allocated)
	if spent > Profile.earnedPoints(p.level) then
		p.allocated = { [Passives.startId] = true }
		spent = 0
	end
	p.points = Profile.earnedPoints(p.level) - spent
end

function Profile.addGem(p: Profile, gemId: string): GemInstance
	assert(isGem(gemId), `unknown gem {gemId}`)
	local gem = { id = `g{p.nextGemId}`, gemId = gemId }
	p.nextGemId += 1
	table.insert(p.gems, gem)
	return gem
end

function Profile.new(): Profile
	local p: Profile = {
		level = 1,
		xp = 0,
		points = 0,
		allocated = { [Passives.startId] = true },
		gems = {},
		sockets = {},
		nextGemId = 1,
	}
	for _, gemId in STARTER_GEMS do
		Profile.addGem(p, gemId)
	end
	return p
end

-- Returns the number of levels gained.
function Profile.addXp(p: Profile, amount: number): number
	if amount ~= amount or amount <= 0 then
		return 0
	end
	local level, xp, gained = Progression.addXp(p.level, p.xp, amount)
	p.level, p.xp = level, xp
	recount(p)
	return gained
end

-- Debug helper: sets the level, clears xp and refunds passives if they no longer fit.
function Profile.setLevel(p: Profile, level: number)
	p.level = math.clamp(math.floor(level), 1, ProgressionConfig.maxLevel)
	p.xp = 0
	recount(p)
end

function Profile.allocate(p: Profile, nodeId: string): (boolean, string?)
	local ok, reason = PassiveTree.canAllocate(p.allocated, nodeId, p.points)
	if not ok then
		return false, reason
	end
	p.allocated = PassiveTree.allocate(p.allocated, nodeId, p.points)
	recount(p)
	return true, nil
end

-- Returns the number of points refunded.
function Profile.reset(p: Profile): number
	local fresh, refunded = PassiveTree.reset(p.allocated)
	p.allocated = fresh
	recount(p)
	return refunded
end

-- Slot -> gemId map in the shape GemRules.canSocket expects.
local function socketMap(p: Profile, skillId: string): { [number]: string? }
	local map: { [number]: string? } = {}
	local slots = p.sockets[skillId]
	if slots then
		for slot, gem in slots do
			map[slot] = gem.gemId
		end
	end
	return map
end

-- Socketed gem ids of a skill in slot order, for SkillResolver.resolve.
function Profile.gemIds(p: Profile, skillId: string): { string }
	local ids = {}
	local slots = p.sockets[skillId]
	if slots then
		for slot = 1, socketCount(skillId) do
			local gem = slots[slot]
			if gem then
				table.insert(ids, gem.gemId)
			end
		end
	end
	return ids
end

-- Moves an inventory gem into a socket (returning any gem already there), or with
-- `gemInstanceId = nil` moves the socketed gem back to the inventory.
-- Reasons: GemRules reasons plus "not_owned" and "empty".
function Profile.socket(p: Profile, skillId: string, slot: number, gemInstanceId: string?): (boolean, string?)
	local count = socketCount(skillId)
	if count <= 0 then
		return false, "no_sockets"
	end
	if slot ~= math.floor(slot) or slot < 1 or slot > count then
		return false, "bad_slot"
	end
	local slots = p.sockets[skillId]
	if gemInstanceId == nil then
		local current = slots and slots[slot]
		if not slots or not current then
			return false, "empty"
		end
		slots[slot] = nil
		if next(slots) == nil then
			p.sockets[skillId] = nil
		end
		table.insert(p.gems, current)
		return true, nil
	end
	local index: number? = nil
	for i, gem in p.gems do
		if gem.id == gemInstanceId then
			index = i
			break
		end
	end
	if index == nil then
		return false, "not_owned"
	end
	local gem = p.gems[index]
	local ok, reason = GemRules.canSocket(skillId, slot, gem.gemId, socketMap(p, skillId))
	if not ok then
		return false, reason
	end
	table.remove(p.gems, index)
	local target = slots or {}
	p.sockets[skillId] = target
	local previous = target[slot]
	if previous then
		table.insert(p.gems, previous)
	end
	target[slot] = gem
	return true, nil
end

-- Sockets for StateSync. Remote events truncate arrays at the first nil, so each socketed
-- skill is sent as a dense array of its slots with `false` marking an empty slot.
function Profile.wireSockets(p: Profile): { [string]: { GemInstance | false } }
	local wire: { [string]: { GemInstance | false } } = {}
	for _, skillId in Skills.order do
		local count = socketCount(skillId)
		if count > 0 then
			local slots = p.sockets[skillId]
			local row: { GemInstance | false } = {}
			for slot = 1, count do
				local gem = slots and slots[slot]
				row[slot] = if gem then { id = gem.id, gemId = gem.gemId } else false
			end
			wire[skillId] = row
		end
	end
	return wire
end

-- DataStore-safe table: string keys only for sockets (no sparse arrays).
function Profile.encode(p: Profile): { [string]: any }
	local gems = {}
	for _, gem in p.gems do
		table.insert(gems, { id = gem.id, gemId = gem.gemId })
	end
	local sockets = {}
	for skillId, slots in p.sockets do
		local row = {}
		for slot, gem in slots do
			row[tostring(slot)] = { id = gem.id, gemId = gem.gemId }
		end
		if next(row) ~= nil then
			sockets[skillId] = row
		end
	end
	local allocated = {}
	for id in p.allocated do
		allocated[id] = true
	end
	return {
		version = FORMAT_VERSION,
		level = p.level,
		xp = p.xp,
		allocated = allocated,
		gems = gems,
		sockets = sockets,
		nextGemId = p.nextGemId,
	}
end

local function toGem(raw: any, seen: { [string]: boolean }): GemInstance?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or not isGem(raw.gemId) or seen[raw.id] then
		return nil
	end
	seen[raw.id] = true
	return { id = raw.id, gemId = raw.gemId }
end

local function gemNumber(id: string): number
	return tonumber(string.match(id, "^g(%d+)$")) or 0
end

-- Rebuilds a valid profile from stored data. Anything unknown or inconsistent is dropped:
-- unknown or unreachable passives, invalid gems, sockets that break the gem rules.
-- Overspent passives are refunded. A non-table value gives a fresh profile.
function Profile.decode(raw: any): Profile
	if type(raw) ~= "table" then
		return Profile.new()
	end
	local p: Profile = {
		level = 1,
		xp = 0,
		points = 0,
		allocated = { [Passives.startId] = true },
		gems = {},
		sockets = {},
		nextGemId = 1,
	}

	if type(raw.level) == "number" and raw.level == raw.level then
		p.level = math.clamp(math.floor(raw.level), 1, ProgressionConfig.maxLevel)
	end
	if type(raw.xp) == "number" and raw.xp == raw.xp and p.level < ProgressionConfig.maxLevel then
		p.xp = math.clamp(math.floor(raw.xp), 0, Progression.xpToNext(p.level) - 1)
	end

	-- Passives: keep only known nodes reachable from start through other kept nodes.
	if type(raw.allocated) == "table" then
		local wanted: { [string]: boolean } = {}
		for id, value in raw.allocated do
			if type(id) == "string" and value == true and Passives.nodes[id] then
				wanted[id] = true
			end
		end
		local queue = { Passives.startId }
		local head = 1
		while head <= #queue do
			local node = Passives.nodes[queue[head]]
			head += 1
			for _, link in node.links do
				if wanted[link] and not p.allocated[link] then
					p.allocated[link] = true
					table.insert(queue, link)
				end
			end
		end
	end

	local seen: { [string]: boolean } = {}
	if type(raw.gems) == "table" then
		for _, entry in raw.gems do
			local gem = toGem(entry, seen)
			if gem then
				table.insert(p.gems, gem)
			end
		end
	end

	if type(raw.sockets) == "table" then
		for _, skillId in Skills.order do
			local row = raw.sockets[skillId]
			if type(row) == "table" then
				for slot = 1, math.max(socketCount(skillId), 2) do
					local gem = toGem(row[tostring(slot)] or row[slot], seen)
					if gem then
						local fits = slot <= socketCount(skillId)
							and GemRules.canSocket(skillId, slot, gem.gemId, socketMap(p, skillId))
						if fits then
							local slots = p.sockets[skillId] or {}
							slots[slot] = gem
							p.sockets[skillId] = slots
						else
							table.insert(p.gems, gem)
						end
					end
				end
			end
		end
	end

	local nextId = if type(raw.nextGemId) == "number" and raw.nextGemId == raw.nextGemId
		then math.floor(raw.nextGemId)
		else 1
	for id in seen do
		nextId = math.max(nextId, gemNumber(id) + 1)
	end
	p.nextGemId = math.max(nextId, 1)

	recount(p)
	return p
end

return Profile
