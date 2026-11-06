--!strict
-- BossService (spec §4.6, §5.7): the Eclipse Warden. Summoned at the altar prompt or through
-- the SummonBoss remote, two phases driven by one AI thread, telegraphs through BossFx, rewards.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local EnemiesConfig = require(Shared.Config.Enemies)
local Strings = require(Shared.Config.Strings)

local Combat = require(script.Parent.Combat)
local Enemies = require(script.Parent.Enemies)
local PlayerData = require(script.Parent.PlayerData)

type State = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	contributors: { [Player]: true },
	phase: number,
	alive: boolean,
	slash: AnimationTrack?,
	connections: { RBXScriptConnection },
}

local WARDEN = EnemiesConfig.eclipse_warden
local AI_INTERVAL = 0.2
local STOP_DISTANCE = 10
local CORPSE_TIME = 3
local ARENA_TIMEOUT = 10
local GROUND_PROBE = 60
local FALLBACK_SPAWN = Vector3.new(0, 4, 60)

local Boss = {}

local remotes: Net.Remotes = {}
local random = Random.new()
local current: State? = nil
local summoning = false
local cooldownUntil = 0
local prompt: ProximityPrompt? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function fire(payload: Net.BossFx)
	remotes.BossFx:FireAllClients(payload)
end

local function setPromptEnabled(enabled: boolean)
	if prompt then
		prompt.Enabled = enabled
	end
end

local function arenaChild(name: string): Instance?
	local arena = Workspace:FindFirstChild("Arena")
	return arena and arena:FindFirstChild(name)
end

-- Ground point under `position`, ignoring characters and enemies.
local function groundAt(position: Vector3): Vector3
	local exclude: { Instance } = { Combat.enemyFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result =
		Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -GROUND_PROBE, 0), params)
	return if result then result.Position else position - Vector3.new(0, 3, 0)
end

local function livingRoots(near: Vector3, range: number): { { player: Player, root: BasePart } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			root
			and root:IsA("BasePart")
			and Combat.isAlive(player)
			and (root.Position - near).Magnitude <= range
		then
			table.insert(list, { player = player, root = root })
		end
	end
	return list
end

-- Hits every living player whose root is within `radius` of `position` (flat distance,
-- with the same vertical tolerance).
local function damageArea(position: Vector3, radius: number, amount: number)
	for _, entry in livingRoots(position, radius * 2) do
		local offset = entry.root.Position - position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= radius then
			Combat.damagePlayer(entry.player, amount)
		end
	end
end

local function cleanup(state: State)
	state.alive = false
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	Combat.unregisterTarget(state.model)
	if current == state then
		current = nil
	end
end

local function onDefeated(state: State)
	if not state.alive then
		return
	end
	local position = state.root.Position
	cleanup(state)
	fire({ event = "defeated", position = position })
	local xp = WARDEN.xp(WARDEN.level)
	for player in state.contributors do
		if player.Parent == Players then
			PlayerData.grantXp(player, xp)
			for _ = 1, WARDEN.gemDrops do
				PlayerData.grantGem(player, Enemies.randomGemId())
			end
		end
	end
	cooldownUntil = os.clock() + WARDEN.altarCooldown
	task.delay(WARDEN.altarCooldown, function()
		if not current then
			setPromptEnabled(true)
		end
	end)
	Debris:AddItem(state.model, CORPSE_TIME)
end

local function enterPhase2(state: State)
	if state.phase >= 2 or not state.alive then
		return
	end
	state.phase = 2
	local enraged = rgb(WARDEN.enrageEyeColor)
	for _, item in state.model:GetChildren() do
		if item:IsA("BasePart") and item.Name == "Eye" then
			item.Color = enraged
		end
	end
	fire({ event = "enrage", position = state.root.Position })
end

local function slam(state: State, targetPosition: Vector3)
	local cfg = WARDEN.slam
	local position = groundAt(targetPosition)
	fire({ event = "telegraph", position = position, radius = cfg.radius, delay = cfg.telegraph })
	task.delay(cfg.telegraph, function()
		if not state.alive then
			return
		end
		if state.slash then
			state.slash:Play(0.1)
		end
		fire({ event = "slam", position = position, radius = cfg.radius })
		damageArea(position, cfg.radius, cfg.damage)
	end)
end

local function shadowBlades(state: State)
	local cfg = WARDEN.blades
	local victims = livingRoots(state.root.Position, WARDEN.aggroRange)
	if #victims == 0 then
		return
	end
	for _ = 1, cfg.count do
		local victim = victims[random:NextInteger(1, #victims)]
		local angle = random:NextNumber() * 2 * math.pi
		local distance = math.sqrt(random:NextNumber()) * cfg.scatter
		local offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local position = groundAt(victim.root.Position + offset)
		fire({ event = "blades", position = position, radius = cfg.radius, delay = cfg.telegraph })
		task.delay(cfg.telegraph, function()
			if state.alive then
				damageArea(position, cfg.radius, cfg.damage)
			end
		end)
	end
end

local function run(state: State)
	local nextSlam = os.clock() + WARDEN.slam.interval
	while state.alive do
		task.wait(AI_INTERVAL)
		if not state.alive then
			return
		end
		if state.model.Parent == nil or state.root.Parent == nil then
			-- fell out of the world or was removed: reset without rewards or cooldown
			cleanup(state)
			if state.model.Parent then
				state.model:Destroy()
			end
			setPromptEnabled(true)
			return
		end
		local speedMul = if state.phase >= 2 then WARDEN.enrageSpeedMul else 1
		state.humanoid.WalkSpeed = WARDEN.speed * speedMul * Combat.speedMul(state.model)
		local _, targetRoot, distance = Enemies.nearestPlayer(state.root.Position, WARDEN.aggroRange)
		if targetRoot then
			if distance > STOP_DISTANCE then
				state.humanoid:MoveTo(targetRoot.Position)
			else
				state.humanoid:MoveTo(state.root.Position)
			end
		end
		local now = os.clock()
		if now >= nextSlam then
			nextSlam = now + WARDEN.slam.interval
			if targetRoot then
				slam(state, targetRoot.Position)
				if state.phase >= 2 then
					shadowBlades(state)
				end
			end
		end
	end
end

local function spawnBoss()
	local marker = arenaChild("BossSpawn")
	local position = if marker and marker:IsA("BasePart") then marker.Position else FALLBACK_SPAWN
	local model = Enemies.spawnRig({
		name = "EclipseWarden",
		scale = WARDEN.scale,
		bodyColor = rgb(WARDEN.bodyColor),
		eyeColor = rgb(WARDEN.eyeColor),
	})
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		error("boss rig has no Humanoid or root")
	end
	humanoid.DisplayName = `{Strings.bossName or WARDEN.displayName} · {Strings.level} {WARDEN.level}`
	humanoid.MaxHealth = WARDEN.hp(WARDEN.level)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = WARDEN.speed
	model:PivotTo(CFrame.new(position + Vector3.new(0, 3 * WARDEN.scale, 0)))
	model.Parent = Combat.enemyFolder()
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local slash, connections = Enemies.animate(humanoid)
	local state: State = {
		model = model,
		humanoid = humanoid,
		root = root,
		contributors = {},
		phase = 1,
		alive = true,
		slash = slash,
		connections = connections,
	}
	current = state
	table.insert(
		state.connections,
		humanoid.HealthChanged:Connect(function(health: number)
			if health > 0 and health <= humanoid.MaxHealth * WARDEN.phase2At then
				enterPhase2(state)
			end
		end)
	)
	table.insert(
		state.connections,
		humanoid.Died:Connect(function()
			onDefeated(state)
		end)
	)
	Combat.registerTarget(model, {
		onHit = function(attacker: Player)
			state.contributors[attacker] = true
		end,
	})
	setPromptEnabled(false)
	task.spawn(run, state)
end

local function trySummon(player: Player)
	if current or summoning or os.clock() < cooldownUntil then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or profile.level < WARDEN.summonLevel or not Combat.isAlive(player) then
		return
	end
	-- Summon only at the altar. Without one (see Boss.start) the remote alone summons.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local altarPart = prompt and prompt.Parent
	if
		altarPart
		and altarPart:IsA("BasePart")
		and (
			not (root and root:IsA("BasePart"))
			or (root.Position - altarPart.Position).Magnitude > WARDEN.summonRange
		)
	then
		return
	end
	summoning = true
	local ok, err = pcall(function()
		spawnBoss()
	end)
	summoning = false
	if not ok then
		warn(`[Boss] summon failed: {err}`)
	end
end

function Boss.start()
	remotes = Net.server()
	remotes.SummonBoss.OnServerEvent:Connect(trySummon)
	task.spawn(function()
		local arena = Workspace:WaitForChild("Arena", ARENA_TIMEOUT)
		local altar = arena and arena:FindFirstChild("BossAltar")
		local altarPart = altar and altar:FindFirstChild("Altar")
		local found = altarPart and altarPart:FindFirstChild("SummonPrompt")
		if found and found:IsA("ProximityPrompt") then
			prompt = found
			found.Triggered:Connect(trySummon)
		else
			warn(
				"[Boss] Workspace.Arena.BossAltar.Altar.SummonPrompt not found; only the SummonBoss remote works"
			)
		end
	end)
end

return Boss
