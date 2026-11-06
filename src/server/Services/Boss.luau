--!strict
-- BossService (boss rework spec §2-3): Bạo Quân Hoàng Kim, the Golden Tyrant. Summoned at the
-- altar prompt or through the SummonBoss remote. One AI thread walks the boss toward its
-- target and, on a fixed cadence, runs the action Logic/BossPlan picks. Every action fires a
-- `pose` and its own BossFx event, then deals damage through Combat.damagePlayer.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local EnemiesConfig = require(Shared.Config.Enemies)
local BossPlan = require(Shared.Logic.BossPlan)

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
	cooldowns: { [string]: number },
	connections: { RBXScriptConnection },
}

type Target = { player: Player, root: BasePart }

type Rooted = {
	humanoid: Humanoid,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	releaseAt: number,
	connections: { RBXScriptConnection },
}

local WARDEN = EnemiesConfig.eclipse_warden
local AI_INTERVAL = 0.1
local FIRST_ACTION_DELAY = 1.5 -- lets the spawn effect and idle pose play first
local MELEE_RECOVER = 0.25 -- stands after a cut lands
local ULTIMATE_RECOVER = 0.6 -- stands after the ultimate fires
local LUNGE_TIME = 0.12
local LUNGE_GAP = 4 -- the chains lunge stops this far short of the rooted player
local CORPSE_TIME = 4
local ARENA_TIMEOUT = 10
local GROUND_PROBE = 60
local SIGHT_LIFT = 1 -- ultimate sight lines leave from the boss's chest, not its waist
local FALLBACK_SPAWN = Vector3.new(0, 4, 60)

local Boss = {}

local remotes: Net.Remotes = {}
local random = Random.new()
local current: State? = nil
local summoning = false
local cooldownUntil = 0
local prompt: ProximityPrompt? = nil
local sightWorld: WorldModel? = nil
local rooted: { [Player]: Rooted } = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function vec(v: Vector3): BossPlan.Vec
	return { x = v.X, y = v.Y, z = v.Z }
end

local function phaseIndex(state: State): number
	return if state.phase >= 2 then 2 else 1
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function fire(payload: Net.BossFx)
	remotes.BossFx:FireAllClients(payload)
end

local function pose(state: State, clip: string)
	fire({ model = state.model, event = "pose", clip = clip })
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

-- Waits, then reports whether the boss is still fighting.
local function waitAlive(state: State, seconds: number): boolean
	task.wait(seconds)
	return state.alive
end

local function randomFlat(radius: number): Vector3
	local angle = random:NextNumber() * 2 * math.pi
	local distance = math.sqrt(random:NextNumber()) * radius
	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
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

-- Sight lines --------------------------------------------------------------------------
-- The arena's pillars and decor have CanQuery off, so a raycast in Workspace passes
-- through them. A server-only WorldModel holds queryable copies of every visible arena
-- part, and the ultimate raycasts against that instead.

local function buildSightWorld(arena: Instance)
	local world = Instance.new("WorldModel")
	world.Name = "BossSightLines"
	for _, item in arena:GetDescendants() do
		if item:IsA("BasePart") and item.Transparency < 0.95 then
			local copy = item:Clone()
			if copy then
				copy:ClearAllChildren()
				copy.Anchored = true
				copy.CanQuery = true
				copy.Parent = world
			end
		end
	end
	world.Parent = ServerStorage
	sightWorld = world
end

local function sightBlocked(from: Vector3, to: Vector3): boolean
	local world = sightWorld
	if not world then
		local arena = Workspace:FindFirstChild("Arena")
		if not arena then
			return false
		end
		buildSightWorld(arena)
		world = sightWorld
	end
	return world ~= nil and world:Raycast(from, to - from) ~= nil
end

-- Targets ------------------------------------------------------------------------------

local function livingRoots(near: Vector3, range: number): { Target }
	local list: { Target } = {}
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

-- Living players whose root is within `radius` of `position` (flat distance, with the
-- same vertical tolerance).
local function playersInArea(position: Vector3, radius: number): { Target }
	local list: { Target } = {}
	for _, entry in livingRoots(position, radius * 2) do
		local offset = entry.root.Position - position
		if flat(offset).Magnitude <= radius and math.abs(offset.Y) <= radius then
			table.insert(list, entry)
		end
	end
	return list
end

-- Living players inside a box `length` long in front of `frame` (its -Z), `width` wide
-- and `height` tall, centred on the frame's height.
local function playersInBox(frame: CFrame, length: number, width: number, height: number): { Target }
	local list: { Target } = {}
	for _, entry in livingRoots(frame.Position, length + width) do
		local p = frame:PointToObjectSpace(entry.root.Position)
		if -p.Z >= 0 and -p.Z <= length and math.abs(p.X) <= width / 2 and math.abs(p.Y) <= height / 2 then
			table.insert(list, entry)
		end
	end
	return list
end

-- Lands `targets[i]` at `delay + (i - 1) * interval` from now.
local function scheduleImpacts(
	state: State,
	targets: { Vector3 },
	delay: number,
	interval: number,
	radius: number,
	damage: number
)
	for i, position in targets do
		task.delay(delay + (i - 1) * interval, function()
			if state.alive then
				for _, entry in playersInArea(position, radius) do
					Combat.damagePlayer(entry.player, damage)
				end
			end
		end)
	end
end

-- Root -------------------------------------------------------------------------------
-- A rooted player's WalkSpeed, JumpPower and JumpHeight are held at 0 and restored when
-- the root ends, the character dies or is removed, the player leaves, or the boss dies.
-- A write from elsewhere during the root (Combat recomputing stats) is remembered as the
-- value to restore and zeroed again.

local function release(player: Player)
	local record = rooted[player]
	if not record then
		return
	end
	rooted[player] = nil
	disconnectAll(record.connections)
	local humanoid = record.humanoid
	if humanoid.Parent then
		humanoid.WalkSpeed = record.walkSpeed
		humanoid.JumpPower = record.jumpPower
		humanoid.JumpHeight = record.jumpHeight
	end
end

local function releaseAll()
	for player in rooted do
		release(player)
	end
end

local function rootPlayer(player: Player, humanoid: Humanoid, duration: number)
	local releaseAt = os.clock() + duration
	local existing = rooted[player]
	local record: Rooted
	if existing and existing.humanoid == humanoid then
		-- rooted again before the last root ended: extend it, keep the saved values
		record = existing
		record.releaseAt = math.max(record.releaseAt, releaseAt)
	else
		release(player)
		record = {
			humanoid = humanoid,
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
			releaseAt = releaseAt,
			connections = {},
		}
		rooted[player] = record
		local connections = record.connections
		table.insert(
			connections,
			humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
				if humanoid.WalkSpeed ~= 0 then
					record.walkSpeed = humanoid.WalkSpeed
					humanoid.WalkSpeed = 0
				end
			end)
		)
		table.insert(
			connections,
			humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
				if humanoid.JumpPower ~= 0 then
					record.jumpPower = humanoid.JumpPower
					humanoid.JumpPower = 0
				end
			end)
		)
		table.insert(
			connections,
			humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(function()
				if humanoid.JumpHeight ~= 0 then
					record.jumpHeight = humanoid.JumpHeight
					humanoid.JumpHeight = 0
				end
			end)
		)
		table.insert(
			connections,
			humanoid.Died:Connect(function()
				release(player)
			end)
		)
		table.insert(
			connections,
			humanoid.AncestryChanged:Connect(function()
				if not humanoid:IsDescendantOf(Workspace) then
					release(player)
				end
			end)
		)
	end
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	task.delay(duration, function()
		if rooted[player] == record and os.clock() >= record.releaseAt - 1e-3 then
			release(player)
		end
	end)
end

-- Actions ------------------------------------------------------------------------------

local function stand(state: State)
	state.humanoid:MoveTo(state.root.Position)
end

-- Turns the boss to look at `point` on the flat.
local function face(state: State, point: Vector3)
	local from = state.root.Position
	local look = Vector3.new(point.X, from.Y, point.Z)
	if (look - from).Magnitude > 0.1 then
		state.root.CFrame = CFrame.lookAt(from, look)
	end
end

-- Flat unit direction from `from` to `to`, or the boss's facing if they overlap.
local function aimDir(state: State, from: Vector3, to: Vector3): Vector3
	local d = flat(to - from)
	if d.Magnitude < 1e-3 then
		d = flat(state.root.CFrame.LookVector)
	end
	return if d.Magnitude < 1e-3 then Vector3.zAxis else d.Unit
end

local function melee(state: State, target: Target, windup: number)
	local cfg = WARDEN.melee
	face(state, target.root.Position)
	local origin = state.root.Position
	local dir = aimDir(state, origin, target.root.Position)
	pose(state, "boss_melee")
	fire({ model = state.model, event = "melee", origin = origin, dir = dir, delay = windup })
	if not waitAlive(state, windup) then
		return
	end
	local frame = CFrame.lookAt(origin, origin + dir)
	for _, entry in playersInBox(frame, cfg.length, cfg.width, cfg.height) do
		Combat.damagePlayer(entry.player, cfg.damage)
	end
	waitAlive(state, MELEE_RECOVER)
end

local function volley(state: State, target: Target)
	local cfg = WARDEN.volley
	face(state, target.root.Position)
	pose(state, "boss_volley")
	if not waitAlive(state, cfg.aimDelay) then
		return
	end
	-- the aim locks now: weapons fly where the target stands 0.6 s after the snap
	local aim = target.root.Position
	local frame = state.root.CFrame
	local portals: { Vector3 } = {}
	local targets: { Vector3 } = {}
	for i = 1, cfg.count do
		local side = (i - 1) - (cfg.count - 1) / 2
		local lift = 3 + (1 - math.min(math.abs(side), 1)) * 1.5
		table.insert(portals, (frame * CFrame.new(side * 4, lift, 3)).Position)
		local jitter = if i == 1 then Vector3.zero else randomFlat(cfg.jitter)
		table.insert(targets, groundAt(aim + jitter))
	end
	fire({
		model = state.model,
		event = "volley",
		portals = portals,
		targets = targets,
		delay = cfg.delay,
		interval = cfg.interval,
	})
	scheduleImpacts(state, targets, cfg.delay, cfg.interval, cfg.radius, cfg.damage)
end

local function armory(state: State, target: Target)
	local cfg = WARDEN.armory
	local count = cfg.count[phaseIndex(state)]
	face(state, target.root.Position)
	pose(state, "boss_armory")
	local victims = livingRoots(state.root.Position, WARDEN.aggroRange)
	if #victims == 0 then
		victims = { target }
	end
	local frame = state.root.CFrame
	local portals: { Vector3 } = {}
	local targets: { Vector3 } = {}
	for i = 1, count do
		-- a fan behind the boss, swept left to right, arched higher in the middle
		local a = if count > 1 then (i - 1) / (count - 1) - 0.5 else 0
		local theta = math.rad(a * cfg.fanArc)
		local lift = 2 + (1 - math.abs(a) * 2) * 3 + (i % 2) * 1.5
		local offset =
			Vector3.new(math.sin(theta) * cfg.fanRadius, lift, 1.5 + math.cos(theta) * cfg.fanRadius * 0.5)
		table.insert(portals, frame:PointToWorldSpace(offset))
		-- round-robin over the players: the first pass aims true, later ones scatter
		local victim = victims[(i - 1) % #victims + 1]
		local scatter = if i <= #victims then Vector3.zero else randomFlat(cfg.scatter)
		table.insert(targets, groundAt(victim.root.Position + scatter))
	end
	fire({
		model = state.model,
		event = "armory",
		portals = portals,
		targets = targets,
		delay = cfg.delay,
		interval = cfg.interval,
		telegraph = cfg.telegraph,
	})
	scheduleImpacts(state, targets, cfg.delay, cfg.interval, cfg.radius, cfg.damage)
	-- stand while the portals open, then walk on as the weapons land
	waitAlive(state, cfg.delay)
end

-- A short dash that ends LUNGE_GAP short of `victim`, facing it.
local function lunge(state: State, victim: Target)
	local from = state.root.Position
	local to = victim.root.Position
	local gap = flat(to - from)
	if gap.Magnitude <= LUNGE_GAP then
		face(state, to)
		return
	end
	local stop = to - gap.Unit * LUNGE_GAP
	local lift = from.Y - groundAt(from).Y
	local y = groundAt(stop).Y + lift
	local goal = CFrame.lookAt(Vector3.new(stop.X, y, stop.Z), Vector3.new(to.X, y, to.Z))
	local start = state.root.CFrame
	local began = os.clock()
	while state.alive and state.root.Parent do
		local alpha = math.min((os.clock() - began) / LUNGE_TIME, 1)
		state.root.CFrame = start:Lerp(goal, alpha)
		if alpha >= 1 then
			break
		end
		task.wait()
	end
end

local function chains(state: State, target: Target)
	local cfg = WARDEN.chains
	face(state, target.root.Position)
	local center = groundAt(target.root.Position)
	pose(state, "boss_chains")
	fire({
		model = state.model,
		event = "chains",
		position = center,
		radius = cfg.radius,
		delay = cfg.telegraph,
		duration = cfg.duration,
	})
	if not waitAlive(state, cfg.telegraph) then
		return
	end
	local victim: Target? = nil
	for _, entry in playersInArea(center, cfg.radius) do
		local character = entry.player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			rootPlayer(entry.player, humanoid, cfg.duration)
			Combat.damagePlayer(entry.player, cfg.damage)
			if victim == nil or entry.player == target.player then
				victim = entry
			end
		end
	end
	if victim and Combat.isAlive(victim.player) then
		lunge(state, victim)
		if state.alive then
			melee(state, victim, cfg.lungeWindup)
		end
	end
end

local function ultimate(state: State, target: Target)
	local cfg = WARDEN.ultimate
	face(state, target.root.Position)
	-- the cone keeps the aim taken at charge start
	local origin = state.root.Position
	local dir = aimDir(state, origin, target.root.Position)
	pose(state, "boss_ultimate_charge")
	fire({
		model = state.model,
		event = "ultimate_charge",
		origin = origin,
		dir = dir,
		duration = cfg.charge,
		length = cfg.length,
		angle = cfg.angle,
	})
	if not waitAlive(state, cfg.charge) then
		return
	end
	pose(state, "boss_ultimate_fire")
	fire({
		model = state.model,
		event = "ultimate_fire",
		origin = origin,
		dir = dir,
		length = cfg.length,
		angle = cfg.angle,
	})
	local o, d = vec(origin), vec(dir)
	local eye = origin + Vector3.new(0, SIGHT_LIFT, 0)
	for _, entry in livingRoots(origin, cfg.length * 1.5) do
		local p = entry.root.Position
		-- the cone test is on the flat, so height differences on the arena do not matter
		if
			BossPlan.inCone(o, d, { x = p.X, y = origin.Y, z = p.Z }, cfg.length, cfg.angle)
			and not sightBlocked(eye, p)
		then
			Combat.damagePlayer(entry.player, cfg.damage)
		end
	end
	waitAlive(state, ULTIMATE_RECOVER)
end

local ACTIONS: { [string]: (State, Target) -> () } = {
	melee = function(state: State, target: Target)
		melee(state, target, WARDEN.melee.windup)
	end,
	volley = volley,
	armory = armory,
	chains = chains,
	ultimate = ultimate,
}

-- Phases and lifecycle -----------------------------------------------------------------

local function cleanup(state: State)
	state.alive = false
	disconnectAll(state.connections)
	Combat.unregisterTarget(state.model)
	releaseAll()
	if current == state then
		current = nil
	end
end

local function onDefeated(state: State)
	if not state.alive then
		return
	end
	local position = state.root.Position
	-- hold the body upright for the kneel pose and the dissolve
	state.root.Anchored = true
	cleanup(state)
	pose(state, "boss_defeated")
	fire({ model = state.model, event = "defeated", position = position })
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

-- Phase 2 at 50% HP: faster, shorter armory cooldown, the ultimate armed 4 s from now.
local function enrage(state: State)
	state.phase = 2
	state.cooldowns.ultimate = os.clock() + BossPlan.ULTIMATE_FIRST_DELAY
	stand(state)
	pose(state, "boss_enrage")
	fire({ model = state.model, event = "enrage" })
	waitAlive(state, WARDEN.enragePause)
end

local function run(state: State)
	local humanoid, root = state.humanoid, state.root
	local nextActionAt = os.clock() + FIRST_ACTION_DELAY
	while state.alive do
		task.wait(AI_INTERVAL)
		if not state.alive then
			return
		end
		if state.model.Parent == nil or root.Parent == nil then
			-- fell out of the world or was removed: reset without rewards or cooldown
			cleanup(state)
			if state.model.Parent then
				state.model:Destroy()
			end
			setPromptEnabled(true)
			return
		end
		if
			state.phase < 2
			and humanoid.Health > 0
			and humanoid.Health <= humanoid.MaxHealth * WARDEN.phase2At
		then
			enrage(state)
			continue
		end
		local speedMul = if state.phase >= 2 then WARDEN.enrageSpeedMul else 1
		humanoid.WalkSpeed = WARDEN.speed * speedMul * Combat.speedMul(state.model)

		local player, targetRoot = Enemies.nearestPlayer(root.Position, WARDEN.aggroRange)
		if not player or not targetRoot then
			stand(state)
			continue
		end
		local target: Target = { player = player, root = targetRoot }
		local distance = flat(targetRoot.Position - root.Position).Magnitude
		local now = os.clock()
		if now < nextActionAt then
			if distance > WARDEN.stopDistance then
				humanoid:MoveTo(targetRoot.Position)
			else
				stand(state)
				face(state, targetRoot.Position)
			end
			continue
		end

		local action = BossPlan.next({
			phase = state.phase,
			distance = distance,
			now = now,
			cooldowns = state.cooldowns,
		})
		local cooldown = BossPlan.cooldown(action, state.phase)
		if cooldown > 0 then
			state.cooldowns[action] = now + cooldown
		end
		stand(state)
		local ok, err = pcall(function()
			ACTIONS[action](state, target)
		end)
		if not ok then
			warn(`[Boss] {action} failed: {err}`)
		end
		nextActionAt = math.max(now + WARDEN.cadence[phaseIndex(state)], os.clock())
	end
end

local function spawnBoss()
	local marker = arenaChild("BossSpawn")
	local position = if marker and marker:IsA("BasePart") then marker.Position else FALLBACK_SPAWN
	local model = Enemies.spawnRig({
		name = "GoldenTyrant",
		scale = WARDEN.scale,
		bodyColor = rgb(WARDEN.bodyColor),
		eyes = false,
	})
	local dressed, dressError = pcall(function()
		require(Shared.Models.TyrantArmor).dress(model)
	end)
	if not dressed then
		warn(`[Boss] TyrantArmor.dress failed: {dressError}`)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		error("boss rig has no Humanoid or root")
	end
	humanoid.DisplayName = WARDEN.displayName
	-- the boss bar shows the name and health, so no overhead nameplate
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = WARDEN.hp(WARDEN.level)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = WARDEN.speed
	-- BossFx carries the model, so every client must have it whatever its streaming radius
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local at = position + Vector3.new(0, 3 * WARDEN.scale, 0)
	local towardCenter = Vector3.new(0, at.Y, 0)
	model:PivotTo(
		if flat(towardCenter - at).Magnitude > 1 then CFrame.lookAt(at, towardCenter) else CFrame.new(at)
	)
	model.Parent = Combat.enemyFolder()
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- idle and walk animations; the procedural poses layer over them on the clients
	local _, connections = Enemies.animate(humanoid)
	local state: State = {
		model = model,
		humanoid = humanoid,
		root = root,
		contributors = {},
		phase = 1,
		alive = true,
		cooldowns = {},
		connections = connections,
	}
	current = state
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
	fire({ model = model, event = "spawn", position = position })
	pose(state, "boss_idle")
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
	Players.PlayerRemoving:Connect(release)
	task.spawn(function()
		local arena = Workspace:WaitForChild("Arena", ARENA_TIMEOUT)
		if arena and not sightWorld then
			buildSightWorld(arena)
		end
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
