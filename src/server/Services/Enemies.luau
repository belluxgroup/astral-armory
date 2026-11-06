--!strict
-- EnemyService (spec §5.7): keeps 10 hollow knights alive on the inner and outer spawn rings,
-- drives every one from a single 0.2 s AI tick, and hands out XP and gem drops on death.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EnemiesConfig = require(Shared.Config.Enemies)
local Anims = require(Shared.Config.Anims)
local Gems = require(Shared.Config.Gems)
local Strings = require(Shared.Config.Strings)

local Combat = require(script.Parent.Combat)
local PlayerData = require(script.Parent.PlayerData)

export type RigOptions = {
	name: string,
	scale: number?,
	bodyColor: Color3?,
	eyeColor: Color3?,
}

type Ring = "inner" | "outer"

type Slot = { ring: Ring }

type Enemy = {
	slot: Slot,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	level: number,
	home: Vector3,
	hits: { [Player]: number },
	lastAttacker: Player?,
	lastAttackAt: number,
	slash: AnimationTrack?,
	connections: { RBXScriptConnection },
	dead: boolean,
}

local AI_INTERVAL = 0.2
local HOME_RADIUS = 6
local SPAWN_LIFT = 3
local CORPSE_TIME = 3
local ARENA_TIMEOUT = 10
local FALLBACK_INNER_RADIUS = 44
local FALLBACK_OUTER_RADIUS = 87
local FALLBACK_HEIGHT = 4

local KNIGHT = EnemiesConfig.hollow_knight

local Enemies = {}

local random = Random.new()
local enemies: { Enemy } = {}
local spawnPoints: { [string]: { Vector3 } } = { inner = {}, outer = {} }
local template: Model? = nil
local templateBuilding = false

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

-- Rigs ----------------------------------------------------------------------------------

local function part(name: string, size: Vector3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Used only when CreateHumanoidModelFromDescription fails (for example with no network).
local function fallbackRig(): Model
	local model = Instance.new("Model")
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), model)
	root.Transparency = 1
	local torso = part("UpperTorso", Vector3.new(2, 2.4, 1), model)
	torso.CFrame = root.CFrame * CFrame.new(0, 0.2, 0)
	weld(root, torso)
	local head = part("Head", Vector3.new(1.2, 1.2, 1.2), model)
	head.CFrame = root.CFrame * CFrame.new(0, 2, 0)
	weld(root, head)
	for _, side in { -1, 1 } do
		local leg =
			part(if side < 0 then "LeftLowerLeg" else "RightLowerLeg", Vector3.new(0.9, 2, 0.9), model)
		leg.CFrame = root.CFrame * CFrame.new(0.5 * side, -2, 0)
		leg.CanCollide = false
		weld(root, leg)
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid
	model.PrimaryPart = root
	return model
end

local function getTemplate(): Model
	while templateBuilding do
		task.wait()
	end
	if template then
		return template
	end
	templateBuilding = true
	local ok, result = pcall(function()
		local description = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	local rig: Model
	if ok and typeof(result) == "Instance" and result:IsA("Model") then
		rig = result
	else
		warn(`[Enemies] R15 rig unavailable ({result}); using a simple rig`)
		rig = fallbackRig()
	end
	template = rig
	templateBuilding = false
	return rig
end

-- Builds a dark rig with two neon eyes. The caller positions and parents it.
function Enemies.spawnRig(opts: RigOptions): Model
	local model = getTemplate():Clone()
	model.Name = opts.name
	local bodyColor = opts.bodyColor or rgb(KNIGHT.bodyColor)
	local eyeColor = opts.eyeColor or rgb(KNIGHT.eyeColor)

	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			if item.Name == "HumanoidRootPart" then
				item.Transparency = 1
			else
				item.Color = bodyColor
				item.Material = Enum.Material.SmoothPlastic
			end
		elseif item:IsA("Decal") and item.Name == "face" then
			item:Destroy()
		end
	end

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		for _, side in { -1, 1 } do
			local eye = Instance.new("Part")
			eye.Name = "Eye"
			eye.Size = Vector3.new(head.Size.X * 0.18, head.Size.Y * 0.1, 0.1)
			eye.CFrame = head.CFrame
				* CFrame.new(side * head.Size.X * 0.2, head.Size.Y * 0.08, -head.Size.Z / 2)
			eye.Material = Enum.Material.Neon
			eye.Color = eyeColor
			eye.CanCollide = false
			eye.CanTouch = false
			eye.CanQuery = false
			eye.Massless = true
			eye.CastShadow = false
			eye.Parent = model
			weld(head, eye)
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	end

	local scale = opts.scale or 1
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

local function loadTrack(humanoid: Humanoid, id: string, looped: boolean): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, track = pcall(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local loaded = animator:LoadAnimation(animation)
		loaded.Looped = looped
		return loaded
	end)
	return if ok then track else nil
end

-- Plays walk while moving and idle while standing. Returns the slash track and connections.
function Enemies.animate(humanoid: Humanoid): (AnimationTrack?, { RBXScriptConnection })
	local idle = loadTrack(humanoid, Anims.idle, true)
	local walk = loadTrack(humanoid, Anims.walk, true)
	local slash = loadTrack(humanoid, Anims.slash, false)
	if slash then
		slash.Priority = Enum.AnimationPriority.Action
	end
	if idle then
		idle:Play()
	end
	local connections = {
		humanoid.Running:Connect(function(speed: number)
			if not walk then
				return
			end
			if speed > 0.5 then
				if not walk.IsPlaying then
					walk:Play(0.2)
				end
				walk:AdjustSpeed(math.clamp(speed / 14, 0.5, 2))
			elseif walk.IsPlaying then
				walk:Stop(0.2)
			end
		end),
	}
	return slash, connections
end

-- Targeting -----------------------------------------------------------------------------

-- Nearest living player within `range` of `position`.
function Enemies.nearestPlayer(position: Vector3, range: number): (Player?, BasePart?, number)
	local best: Player?, bestRoot: BasePart?, bestDistance = nil, nil, range
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and Combat.isAlive(player) then
			local distance = (root.Position - position).Magnitude
			if distance <= bestDistance then
				best, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return best, bestRoot, bestDistance
end

local function randomGemId(): string
	return Gems.order[random:NextInteger(1, #Gems.order)]
end
Enemies.randomGemId = randomGemId

-- Spawning ------------------------------------------------------------------------------

local function collectSpawnPoints()
	local arena = Workspace:WaitForChild("Arena", ARENA_TIMEOUT)
	for ring, folderName in { inner = "InnerSpawns", outer = "OuterSpawns" } :: { [string]: string } do
		local folder = arena and arena:FindFirstChild(folderName)
		if folder then
			for _, marker in folder:GetChildren() do
				if marker:IsA("BasePart") then
					table.insert(spawnPoints[ring], marker.Position)
				end
			end
		end
	end
	local fallbacks: { [string]: number } = { inner = FALLBACK_INNER_RADIUS, outer = FALLBACK_OUTER_RADIUS }
	for ring, radius in fallbacks do
		if #spawnPoints[ring] == 0 then
			warn(`[Enemies] no {ring} spawn markers in Workspace.Arena; using a default ring`)
			for i = 0, 7 do
				local angle = i * math.pi / 4
				table.insert(
					spawnPoints[ring],
					Vector3.new(math.cos(angle) * radius, FALLBACK_HEIGHT, math.sin(angle) * radius)
				)
			end
		end
	end
end

local spawnInSlot: (slot: Slot) -> ()

local function removeEnemy(enemy: Enemy)
	enemy.dead = true
	disconnectAll(enemy.connections)
	Combat.unregisterTarget(enemy.model)
	local index = table.find(enemies, enemy)
	if index then
		table.remove(enemies, index)
	end
	task.delay(KNIGHT.respawnDelay, spawnInSlot, enemy.slot)
end

local function onDeath(enemy: Enemy)
	if enemy.dead then
		return
	end
	local now = os.clock()
	local xp = KNIGHT.xp(enemy.level)
	for player, at in enemy.hits do
		if player.Parent == Players and now - at <= KNIGHT.contributionWindow then
			PlayerData.grantXp(player, xp)
		end
	end
	local killer = enemy.lastAttacker
	if killer and killer.Parent == Players and random:NextNumber() < KNIGHT.gemDropChance then
		PlayerData.grantGem(killer, randomGemId())
	end
	removeEnemy(enemy)
	Debris:AddItem(enemy.model, CORPSE_TIME)
end

function spawnInSlot(slot: Slot)
	local levels = if slot.ring == "inner" then KNIGHT.innerLevels else KNIGHT.outerLevels
	local points = spawnPoints[slot.ring]
	local level = random:NextInteger(levels[1], levels[2])
	local home = points[random:NextInteger(1, #points)]

	local ok, err = pcall(function()
		local model = Enemies.spawnRig({ name = "HollowKnight", scale = KNIGHT.scale })
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		assert(humanoid and root and root:IsA("BasePart"), "rig has no Humanoid or root")
		local name = Strings.enemy_hollow_knight or KNIGHT.displayName
		humanoid.DisplayName = `{name} · {Strings.level} {level}`
		humanoid.MaxHealth = KNIGHT.hp(level)
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = KNIGHT.speed
		model:PivotTo(
			CFrame.new(home + Vector3.new(0, SPAWN_LIFT, 0)) * CFrame.Angles(0, random:NextNumber() * 6.28, 0)
		)
		model.Parent = Combat.enemyFolder()
		pcall(function()
			root:SetNetworkOwner(nil)
		end)

		local enemy: Enemy = {
			slot = slot,
			model = model,
			humanoid = humanoid,
			root = root,
			level = level,
			home = home,
			hits = {},
			lastAttacker = nil,
			lastAttackAt = 0,
			slash = nil,
			connections = {},
			dead = false,
		}
		local slash, connections = Enemies.animate(humanoid)
		enemy.slash = slash
		enemy.connections = connections
		table.insert(
			enemy.connections,
			humanoid.Died:Connect(function()
				onDeath(enemy)
			end)
		)
		Combat.registerTarget(model, {
			onHit = function(attacker: Player)
				enemy.hits[attacker] = os.clock()
				enemy.lastAttacker = attacker
			end,
		})
		table.insert(enemies, enemy)
	end)
	if not ok then
		warn(`[Enemies] spawn failed: {err}`)
		task.delay(KNIGHT.respawnDelay, spawnInSlot, slot)
	end
end

-- AI ------------------------------------------------------------------------------------

local function think(enemy: Enemy, now: number)
	local model, humanoid, root = enemy.model, enemy.humanoid, enemy.root
	if model.Parent == nil or root.Parent == nil then
		-- fell out of the world or was removed: respawn without rewards
		removeEnemy(enemy)
		if model.Parent then
			model:Destroy()
		end
		return
	end
	humanoid.WalkSpeed = KNIGHT.speed * Combat.speedMul(model)
	local player, targetRoot, distance = Enemies.nearestPlayer(root.Position, KNIGHT.aggroRange)
	if player and targetRoot then
		if distance > KNIGHT.attackRange then
			humanoid:MoveTo(targetRoot.Position)
		else
			humanoid:MoveTo(root.Position)
			local look = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
			if (look - root.Position).Magnitude > 0.1 then
				root.CFrame = CFrame.lookAt(root.Position, look)
			end
			if now - enemy.lastAttackAt >= KNIGHT.attackCooldown then
				enemy.lastAttackAt = now
				if enemy.slash then
					enemy.slash:Play(0.1)
				end
				Combat.damagePlayer(player, KNIGHT.damage(enemy.level))
			end
		end
	elseif (enemy.home - root.Position).Magnitude > HOME_RADIUS then
		humanoid:MoveTo(enemy.home)
	end
end

function Enemies.start()
	task.spawn(function()
		collectSpawnPoints()
		getTemplate()
		local slots: { Slot } = {}
		for _ = 1, KNIGHT.innerCount do
			table.insert(slots, { ring = "inner" })
		end
		for _ = 1, KNIGHT.outerCount do
			table.insert(slots, { ring = "outer" })
		end
		for _, slot in slots do
			spawnInSlot(slot)
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < AI_INTERVAL then
			return
		end
		accumulator = 0
		local now = os.clock()
		for i = #enemies, 1, -1 do
			local enemy = enemies[i]
			if enemy and not enemy.dead and enemy.humanoid.Health > 0 then
				think(enemy, now)
			end
		end
	end)
end

return Enemies
