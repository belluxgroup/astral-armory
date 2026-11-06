--!strict
-- PlayerDataService (spec §5.7): loads and saves profiles through DataStore, owns the
-- profile remotes (AllocatePassive, ResetPassives, SocketGem) and the coalesced StateSync.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Logic"):WaitForChild("Progression"))

local Rules = script.Parent.Parent:WaitForChild("Rules")
local ProfileRules = require(Rules:WaitForChild("Profile"))
local RateLimit = require(Rules:WaitForChild("RateLimit"))

export type Profile = ProfileRules.Profile

-- Live combat fields merged into StateSync, provided by Combat.getLive.
export type LiveFields = {
	hp: number,
	maxHp: number,
	energy: number,
	maxEnergy: number,
	cooldowns: { [string]: number },
	transformed: boolean,
	transformEndsAt: number?,
}

type Session = {
	profile: Profile,
	canSave: boolean,
	limiter: RateLimit.Limiter,
}

local STORE_NAME = "AstralArmory_v1"
local AUTOSAVE_INTERVAL = 60
local SYNC_INTERVAL = 0.1
local RETRIES = 3
local REMOTE_RATE = 10
local SHUTDOWN_TIMEOUT = 25
local MAX_ID_LENGTH = 64

local PlayerData = {}

local sessions: { [Player]: Session } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}
local dirty: { [Player]: true } = {}
local loadedListeners: { (Player, Profile) -> () } = {}
local statsListeners: { (Player) -> () } = {}
local liveProvider: ((Player) -> LiveFields?)? = nil
local remotes: Net.Remotes = {}

local store: DataStore? = nil
local storeChecked = false
local warned = false
local pendingSaves = 0

local function warnOnce(reason: string)
	if not warned then
		warned = true
		warn(`[PlayerData] DataStore unavailable ({reason}). Progress is kept in memory only.`)
	end
end

local function getStore(): DataStore?
	if storeChecked then
		return store
	end
	storeChecked = true
	if game.PlaceId == 0 then
		warnOnce("place is not published")
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warnOnce(tostring(result))
	end
	return store
end

local function keyFor(player: Player): string
	return `u_{player.UserId}`
end

-- Runs a DataStore call in pcall with a short backoff between attempts.
local function withRetries<T>(fn: () -> T): (boolean, any)
	local ok, result = false, nil
	for attempt = 1, RETRIES do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < RETRIES then
			task.wait(attempt)
		end
	end
	return false, result
end

local function notify(listeners: { any }, ...: any)
	for _, fn in listeners do
		task.spawn(fn, ...)
	end
end

function PlayerData.get(player: Player): Profile?
	local session = sessions[player]
	return session and session.profile
end

-- Marks the player's state as changed; StateSync goes out on the next 0.1 s flush.
function PlayerData.onChanged(player: Player)
	if sessions[player] then
		dirty[player] = true
	end
end

-- `fn` runs for every profile that finishes loading, including ones already loaded.
function PlayerData.onLoaded(fn: (Player, Profile) -> ())
	table.insert(loadedListeners, fn)
	for player, session in sessions do
		task.spawn(fn, player, session.profile)
	end
end

-- `fn` runs whenever level or passives change, so stats must be recomputed.
function PlayerData.onStatsChanged(fn: (Player) -> ())
	table.insert(statsListeners, fn)
end

function PlayerData.setLiveProvider(fn: (Player) -> LiveFields?)
	liveProvider = fn
end

function PlayerData.grantXp(player: Player, amount: number)
	local session = sessions[player]
	if not session or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	local gained = ProfileRules.addXp(session.profile, amount)
	PlayerData.onChanged(player)
	if gained > 0 then
		notify(statsListeners, player)
	end
end

function PlayerData.grantGem(player: Player, gemId: string): ProfileRules.GemInstance?
	local session = sessions[player]
	if not session then
		return nil
	end
	local ok, gem = pcall(ProfileRules.addGem, session.profile, gemId)
	if not ok then
		warn(`[PlayerData] grantGem: {gem}`)
		return nil
	end
	PlayerData.onChanged(player)
	return gem
end

local function buildState(player: Player, profile: Profile): Net.PlayerState
	local live = if liveProvider then liveProvider(player) else nil
	local gems = {}
	for _, gem in profile.gems do
		table.insert(gems, { id = gem.id, gemId = gem.gemId })
	end
	return {
		level = profile.level,
		xp = profile.xp,
		xpToNext = Progression.xpToNext(profile.level),
		points = profile.points,
		allocated = table.clone(profile.allocated),
		gems = gems,
		sockets = ProfileRules.wireSockets(profile),
		hp = if live then live.hp else 0,
		maxHp = if live then live.maxHp else 0,
		energy = if live then live.energy else 0,
		maxEnergy = if live then live.maxEnergy else 0,
		cooldowns = if live then table.clone(live.cooldowns) else {},
		transformed = if live then live.transformed else false,
		transformEndsAt = if live then live.transformEndsAt else nil,
		serverClock = os.clock(),
	}
end

local function flush()
	for player in dirty do
		dirty[player] = nil
		local session = sessions[player]
		if session and player.Parent == Players then
			local ok, err = pcall(function()
				remotes.StateSync:FireClient(player, buildState(player, session.profile))
			end)
			if not ok then
				warn(`[PlayerData] StateSync failed for {player.Name}: {err}`)
			end
		end
	end
end

local function save(player: Player, session: Session)
	if not session.canSave then
		return
	end
	local ds = getStore()
	if not ds then
		return
	end
	local data = ProfileRules.encode(session.profile)
	local key = keyFor(player)
	local userId = player.UserId
	pendingSaves += 1
	local ok, err = withRetries(function()
		return ds:SetAsync(key, data, { userId })
	end)
	pendingSaves -= 1
	if not ok then
		warn(`[PlayerData] save failed for {player.Name}: {err}`)
	end
end

local function load(player: Player)
	local profile: Profile
	local canSave = false
	local ds = getStore()
	if ds then
		local key = keyFor(player)
		local ok, raw = withRetries(function()
			return ds:GetAsync(key)
		end)
		if ok then
			profile = ProfileRules.decode(raw)
			canSave = true
		else
			-- Never save over data we failed to read.
			warnOnce(tostring(raw))
			profile = ProfileRules.new()
		end
	else
		profile = ProfileRules.new()
	end
	if player.Parent ~= Players then
		return
	end
	sessions[player] = { profile = profile, canSave = canSave, limiter = RateLimit.new(REMOTE_RATE) }
	dirty[player] = true
	notify(loadedListeners, player, profile)
end

local function levelsChanged(player: Player)
	PlayerData.onChanged(player)
	notify(statsListeners, player)
end

-- Debug in Studio only: "/lvl N" sets the level and the matching passive points.
local function handleDebugCommand(player: Player, text: string)
	if not RunService:IsStudio() then
		return
	end
	local session = sessions[player]
	local n = tonumber(string.match(text, "^%s*/lvl%s+(%d+)%s*$"))
	if session and n then
		ProfileRules.setLevel(session.profile, n)
		levelsChanged(player)
	end
end

local function createDebugCommand()
	if not RunService:IsStudio() then
		return
	end
	local ok, err = pcall(function()
		local command = Instance.new("TextChatCommand")
		command.Name = "AstralLevelCommand"
		command.PrimaryAlias = "/lvl"
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				handleDebugCommand(player, text)
			end
		end)
		command.Parent = TextChatService
	end)
	if not ok then
		warn(`[PlayerData] /lvl command unavailable: {err}`)
	end
end

local function onPlayerAdded(player: Player)
	if connections[player] then
		return
	end
	connections[player] = {
		player.Chatted:Connect(function(message: string)
			handleDebugCommand(player, message)
		end),
	}
	task.spawn(load, player)
end

local function onPlayerRemoving(player: Player)
	local list = connections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		connections[player] = nil
	end
	dirty[player] = nil
	local session = sessions[player]
	sessions[player] = nil
	if session then
		save(player, session)
	end
end

-- Remote guards: right types, sane sizes, and a per-player rate limit.
local function sessionFor(player: Player): Session?
	local session = sessions[player]
	if not session or not session.limiter:allow(os.clock()) then
		return nil
	end
	return session
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

local function onAllocate(player: Player, nodeId: unknown)
	local session = sessionFor(player)
	if not session or not isId(nodeId) then
		return
	end
	local ok = ProfileRules.allocate(session.profile, nodeId :: string)
	if ok then
		levelsChanged(player)
	else
		PlayerData.onChanged(player)
	end
end

local function onReset(player: Player)
	local session = sessionFor(player)
	if not session then
		return
	end
	if ProfileRules.reset(session.profile) > 0 then
		levelsChanged(player)
	else
		PlayerData.onChanged(player)
	end
end

local function onSocket(player: Player, skillId: unknown, slot: unknown, gemInstanceId: unknown)
	local session = sessionFor(player)
	if not session or not isId(skillId) or type(slot) ~= "number" or slot ~= slot then
		return
	end
	if gemInstanceId ~= nil and not isId(gemInstanceId) then
		return
	end
	ProfileRules.socket(session.profile, skillId :: string, slot :: number, gemInstanceId :: string?)
	PlayerData.onChanged(player)
end

function PlayerData.start()
	remotes = Net.server()
	remotes.AllocatePassive.OnServerEvent:Connect(onAllocate)
	remotes.ResetPassives.OnServerEvent:Connect(onReset)
	remotes.SocketGem.OnServerEvent:Connect(onSocket)

	createDebugCommand()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator >= SYNC_INTERVAL then
			accumulator = 0
			flush()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, session in sessions do
				task.spawn(save, player, session)
			end
		end
	end)

	game:BindToClose(function()
		for player, session in sessions do
			task.spawn(save, player, session)
		end
		local started = os.clock()
		while pendingSaves > 0 and os.clock() - started < SHUTDOWN_TIMEOUT do
			task.wait(0.1)
		end
	end)
end

return PlayerData
