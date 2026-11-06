--!strict
-- CombatService (spec §5.7): CastSkill validation, cooldowns, Energy and stamina regen,
-- hex_aegis absorb, ascension, hit detection, damage, elements (burn, slow, chain) and the
-- SkillFx and DamagePopup broadcasts. All numbers come from SkillResolver; nothing from the
-- client is trusted.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Skills = require(Shared.Config.Skills)
local Gems = require(Shared.Config.Gems)
local DodgeConfig = require(Shared.Config.Dodge)
local Stats = require(Shared.Logic.Stats)
local SkillResolver = require(Shared.Logic.SkillResolver)
local Damage = require(Shared.Logic.Damage)
local Stamina = require(Shared.Logic.Stamina)
local BladeLayout = require(Shared.Logic.BladeLayout)
local SwordModel = require(Shared.Models.SwordModel)

local Rules = script.Parent.Parent.Rules
local Cooldowns = require(Rules.Cooldowns)
local RateLimit = require(Rules.RateLimit)
local ProfileRules = require(Rules.Profile)
local PlayerData = require(script.Parent.PlayerData)

type Element = Net.Element
type SkillSpec = SkillResolver.SkillSpec
type HitFn = (attacker: Player, amount: number) -> ()

type Live = {
	player: Player,
	stats: Stats.Stats,
	energy: number,
	stamina: Stamina.State,
	cooldowns: { [string]: number },
	transformed: boolean,
	transformEndsAt: number?,
	drainPerSec: number?,
	absorb: number,
	absorbEndsAt: number,
	limiter: RateLimit.Limiter,
	combo: number,
	lastBasicAt: number,
	humanoid: Humanoid?,
	root: BasePart?,
	connections: { RBXScriptConnection },
	characterConnections: { RBXScriptConnection },
}

type Target = {
	model: Model,
	humanoid: Humanoid,
	onHit: HitFn?,
	slowUntil: number,
	destroying: RBXScriptConnection,
}

export type TargetOptions = { onHit: HitFn? }

local CAST_RATE = 20
local COMBO_RESET = 1
local MELEE_HEIGHT = 6
local BLADE_DROP_DELAY = 0.6
local BLADE_FALL_TIME = 0.12
local BLADE_HIT_RADIUS = 3
local BLADE_HIT_LIFT = 1.5
local GROUND_LIFT = 6
local TARGET_GROUND_DROP = 60
local BLADE_GROUND_DROP = 12
local BEAM_HEIGHT = 12
local LANCE_RADIUS = 1.5
local LANCE_MAX_HITS_PER_STEP = 16
local CHAIN_RANGE = 15
local BURN_TICKS = 4
local MAX_COORD = 1e5
local EQUIP_TIMEOUT = 10

-- Element and explosion tuning lives on the gem configs.
local frostGem = Gems.frost
local flameGem = Gems.flame
local stormGem = Gems.storm
local explosionGem = Gems.wide_burst

local skillSet: { [string]: boolean } = {}
for _, id in Skills.order do
	skillSet[id] = true
end

local Combat = {}

local lives: { [Player]: Live } = {}
local targets: { [Model]: Target } = {}
local remotes: Net.Remotes = {}
local random = Random.new()
local enemyFolder: Folder? = nil
local overlap = OverlapParams.new()
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
overlap.FilterType = Enum.RaycastFilterType.Include

local function rng(): number
	return random:NextNumber()
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

-- Every enemy and boss model must be parented here so spatial queries can find it.
function Combat.enemyFolder(): Folder
	if enemyFolder and enemyFolder.Parent then
		return enemyFolder
	end
	local existing = Workspace:FindFirstChild("Enemies")
	local folder: Folder
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Enemies"
		folder.Parent = Workspace
	end
	enemyFolder = folder
	overlap.FilterDescendantsInstances = { folder }
	return folder
end

local function popup(position: Vector3, amount: number, crit: boolean, element: Element)
	local payload: Net.DamagePopup = { position = position, amount = amount, crit = crit, element = element }
	remotes.DamagePopup:FireAllClients(payload)
end

local function popupPosition(model: Model): Vector3
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, head.Size.Y, 0)
	end
	return model:GetPivot().Position
end

-- Targets -------------------------------------------------------------------------------

function Combat.registerTarget(model: Model, options: TargetOptions?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid, `Combat.registerTarget: {model:GetFullName()} has no Humanoid`)
	Combat.unregisterTarget(model)
	targets[model] = {
		model = model,
		humanoid = humanoid,
		onHit = options and options.onHit,
		slowUntil = 0,
		destroying = model.Destroying:Connect(function()
			Combat.unregisterTarget(model)
		end),
	}
end

function Combat.unregisterTarget(model: Model)
	local target = targets[model]
	if target then
		target.destroying:Disconnect()
		targets[model] = nil
	end
end

-- Movement multiplier from frost; enemy AI applies it to its base WalkSpeed.
function Combat.speedMul(model: Model): number
	local target = targets[model]
	if target and os.clock() < target.slowUntil then
		return 1 - (frostGem.slowPct or 0.3)
	end
	return 1
end

local function alive(target: Target?): boolean
	return target ~= nil and target.humanoid.Health > 0 and target.model.Parent ~= nil
end

-- Applies damage to a registered enemy and fires DamagePopup. Returns the damage dealt.
function Combat.damageEnemy(
	model: Model,
	amount: number,
	crit: boolean,
	element: Element,
	attacker: Player?
): number
	local target = targets[model]
	if not target or not alive(target) or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	local dealt = math.max(1, math.floor(amount + 0.5))
	-- Record the hit before the health change, so the killing blow is credited even when
	-- Died fires immediately.
	local onHit = target.onHit
	if attacker and onHit then
		local ok, err = pcall(function()
			onHit(attacker, dealt)
		end)
		if not ok then
			warn(`[Combat] onHit failed for {model.Name}: {err}`)
		end
	end
	target.humanoid.Health = math.max(0, target.humanoid.Health - dealt)
	popup(popupPosition(model), dealt, crit, element)
	return dealt
end

local function targetOf(instance: Instance): Model?
	local folder = Combat.enemyFolder()
	local node = instance.Parent
	while node and node ~= folder do
		if node:IsA("Model") and targets[node] then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function targetsIn(parts: { BasePart }): { Model }
	local seen: { [Model]: boolean } = {}
	local out: { Model } = {}
	for _, part in parts do
		local model = targetOf(part)
		if model and not seen[model] and alive(targets[model]) then
			seen[model] = true
			table.insert(out, model)
		end
	end
	return out
end

local function targetsInRadius(center: Vector3, radius: number): { Model }
	Combat.enemyFolder()
	return targetsIn(Workspace:GetPartBoundsInRadius(center, radius, overlap))
end

local function targetsInBox(cframe: CFrame, size: Vector3): { Model }
	Combat.enemyFolder()
	return targetsIn(Workspace:GetPartBoundsInBox(cframe, size, overlap))
end

-- Elements ------------------------------------------------------------------------------

local function applyElement(attacker: Player, model: Model, dealt: number, element: Element)
	local target = targets[model]
	if not target then
		return
	end
	if element == "frost" then
		target.slowUntil = os.clock() + (frostGem.slowDuration or 2)
	elseif element == "flame" then
		local duration = flameGem.burnDuration or 3
		-- Split the whole-number total over the ticks, so a small hit does not burn for
		-- 1 per tick (damageEnemy rounds every amount up to at least 1).
		local total = math.floor(dealt * (flameGem.burnPct or 0.2) + 0.5)
		for i = 1, BURN_TICKS do
			local tick = math.floor(total * i / BURN_TICKS) - math.floor(total * (i - 1) / BURN_TICKS)
			if tick > 0 then
				task.delay(duration * i / BURN_TICKS, function()
					Combat.damageEnemy(model, tick, false, "flame", attacker)
				end)
			end
		end
	elseif element == "storm" then
		local origin = model:GetPivot().Position
		local candidates: { { model: Model, distance: number } } = {}
		for other, entry in targets do
			if other ~= model and alive(entry) then
				local distance = (other:GetPivot().Position - origin).Magnitude
				if distance <= CHAIN_RANGE then
					table.insert(candidates, { model = other, distance = distance })
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.distance < b.distance
		end)
		for i = 1, math.min(stormGem.chainCount or 2, #candidates) do
			Combat.damageEnemy(
				candidates[i].model,
				dealt * (stormGem.chainPct or 0.5),
				false,
				"storm",
				attacker
			)
		end
	end
end

-- A primary hit rolls crit and applies the element; a secondary hit (explosion) does not.
local function strike(live: Live, model: Model, base: number, element: Element, primary: boolean)
	local amount, crit = base, false
	if primary then
		amount, crit = Damage.roll(base, live.stats, rng)
	end
	local dealt = Combat.damageEnemy(model, amount, crit, element, live.player)
	if dealt > 0 and primary and element ~= "none" then
		applyElement(live.player, model, dealt, element)
	end
end

local function explode(live: Live, point: Vector3, spec: SkillSpec)
	if not spec.impactExplosion then
		return
	end
	local radius = explosionGem.explosionRadius or 6
	local base = spec.damage * (explosionGem.explosionPct or 0.3)
	for _, model in targetsInRadius(point, radius) do
		strike(live, model, base, spec.element, false)
	end
end

-- Players -------------------------------------------------------------------------------

local function isAlive(live: Live): boolean
	local humanoid, root = live.humanoid, live.root
	return humanoid ~= nil and root ~= nil and humanoid.Health > 0 and root.Parent ~= nil
end

local function applyStatsToCharacter(live: Live)
	local humanoid = live.humanoid
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local oldMax = humanoid.MaxHealth
	local newMax = live.stats.maxHp
	humanoid.MaxHealth = newMax
	if newMax > oldMax then
		humanoid.Health = math.min(newMax, humanoid.Health + (newMax - oldMax))
	end
	humanoid.WalkSpeed = live.stats.moveSpeed
end

local function recompute(live: Live)
	local profile = PlayerData.get(live.player)
	if not profile then
		return
	end
	live.stats = Stats.compute(profile.level, profile.allocated, { transformed = live.transformed })
	live.energy = math.min(live.energy, live.stats.maxEnergy)
	live.stamina.value = math.min(live.stamina.value, live.stats.maxStamina)
	applyStatsToCharacter(live)
	PlayerData.onChanged(live.player)
end

local function endTransform(live: Live)
	live.transformed = false
	live.transformEndsAt = nil
	live.drainPerSec = nil
	recompute(live)
end

function Combat.getLive(player: Player): PlayerData.LiveFields?
	local live = lives[player]
	if not live then
		return nil
	end
	local humanoid = live.humanoid
	return {
		hp = if humanoid then math.max(0, humanoid.Health) else 0,
		maxHp = live.stats.maxHp,
		energy = live.energy,
		maxEnergy = live.stats.maxEnergy,
		stamina = live.stamina.value,
		maxStamina = live.stats.maxStamina,
		cooldowns = live.cooldowns,
		transformed = live.transformed,
		transformEndsAt = live.transformEndsAt,
	}
end

-- Damages a player, absorbed first by an active hex_aegis. Fires DamagePopup.
function Combat.damagePlayer(player: Player, amount: number)
	local live = lives[player]
	if not live or not isAlive(live) or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	local humanoid = live.humanoid :: Humanoid
	local character = player.Character
	if character and character:FindFirstChildOfClass("ForceField") then
		return
	end
	local remaining = amount
	if live.absorb > 0 and os.clock() < live.absorbEndsAt then
		local absorbed = math.min(live.absorb, remaining)
		live.absorb -= absorbed
		remaining -= absorbed
	end
	local dealt = math.floor(remaining + 0.5)
	if dealt > 0 then
		humanoid.Health = math.max(0, humanoid.Health - dealt)
	end
	local head = character and character:FindFirstChild("Head")
	local position = if head and head:IsA("BasePart") then head.Position else (live.root :: BasePart).Position
	popup(position + Vector3.new(0, 1.5, 0), dealt, false, "none")
	PlayerData.onChanged(player)
end

function Combat.isAlive(player: Player): boolean
	local live = lives[player]
	return live ~= nil and isAlive(live)
end

local function equipSword(character: Model)
	local hand = character:WaitForChild("RightHand", EQUIP_TIMEOUT) or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") or character:FindFirstChild("AstralSword") then
		return
	end
	-- CharacterAdded fires before the character is parented to Workspace.
	local deadline = os.clock() + EQUIP_TIMEOUT
	while character.Parent == nil and os.clock() < deadline do
		task.wait()
	end
	if character.Parent == nil then
		return
	end
	local ok, err = pcall(function()
		SwordModel.weld(SwordModel.build(), hand)
	end)
	if not ok then
		warn(`[Combat] could not equip sword: {err}`)
	end
end

local function setupCharacter(live: Live, character: Model)
	disconnectAll(live.characterConnections)
	live.humanoid, live.root = nil, nil
	local humanoid = character:WaitForChild("Humanoid", EQUIP_TIMEOUT)
	local root = character:WaitForChild("HumanoidRootPart", EQUIP_TIMEOUT)
	if live.player.Character ~= character or not lives[live.player] then
		return
	end
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		warn(`[Combat] {live.player.Name}'s character has no Humanoid or root`)
		return
	end
	live.humanoid, live.root = humanoid, root
	live.absorb, live.absorbEndsAt = 0, 0
	live.combo = 0
	if live.transformed then
		live.transformed, live.transformEndsAt, live.drainPerSec = false, nil, nil
	end
	recompute(live)
	live.energy = live.stats.maxEnergy
	live.stamina = Stamina.new(live.stats.maxStamina)
	humanoid.MaxHealth = live.stats.maxHp
	humanoid.Health = live.stats.maxHp
	humanoid.WalkSpeed = live.stats.moveSpeed

	table.insert(
		live.characterConnections,
		humanoid.HealthChanged:Connect(function()
			PlayerData.onChanged(live.player)
		end)
	)
	table.insert(
		live.characterConnections,
		humanoid.Died:Connect(function()
			live.absorb = 0
			if live.transformed then
				endTransform(live)
			end
			PlayerData.onChanged(live.player)
		end)
	)
	task.spawn(equipSword, character)
	PlayerData.onChanged(live.player)
end

local function createLive(player: Player, profile: ProfileRules.Profile)
	if lives[player] or player.Parent ~= Players then
		return
	end
	local live: Live = {
		player = player,
		stats = Stats.compute(profile.level, profile.allocated, { transformed = false }),
		energy = 0,
		stamina = Stamina.new(0),
		cooldowns = {},
		transformed = false,
		transformEndsAt = nil,
		drainPerSec = nil,
		absorb = 0,
		absorbEndsAt = 0,
		limiter = RateLimit.new(CAST_RATE),
		combo = 0,
		lastBasicAt = -math.huge,
		humanoid = nil,
		root = nil,
		connections = {},
		characterConnections = {},
	}
	live.energy = live.stats.maxEnergy
	live.stamina = Stamina.new(live.stats.maxStamina)
	lives[player] = live
	table.insert(
		live.connections,
		player.CharacterAdded:Connect(function(character)
			setupCharacter(live, character)
		end)
	)
	if player.Character then
		task.spawn(setupCharacter, live, player.Character)
	end
end

local function removeLive(player: Player)
	local live = lives[player]
	if live then
		disconnectAll(live.connections)
		disconnectAll(live.characterConnections)
		lives[player] = nil
	end
end

-- Skills --------------------------------------------------------------------------------

local function flatDirection(origin: Vector3, target: Vector3, root: BasePart): Vector3
	local d = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	if d.Magnitude < 1e-3 then
		local look = root.CFrame.LookVector
		d = Vector3.new(look.X, 0, look.Z)
	end
	if d.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return d.Unit
end

local function clampTarget(origin: Vector3, aim: Vector3, spec: SkillSpec): Vector3
	local maxRange = if spec.range > 0 then spec.range else (spec.length or 0)
	if maxRange <= 0 then
		return origin
	end
	local offset = aim - origin
	if offset.Magnitude > maxRange then
		return origin + offset.Unit * maxRange
	end
	return aim
end

local function isFinite(v: Vector3): boolean
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < MAX_COORD
		and math.abs(v.Y) < MAX_COORD
		and math.abs(v.Z) < MAX_COORD
end

local function pay(live: Live, spec: SkillSpec): boolean
	if spec.cost <= 0 then
		return true
	end
	if spec.costResource == "hp" then
		local humanoid = live.humanoid :: Humanoid
		if humanoid.Health <= spec.cost then
			return false
		end
		humanoid.Health -= spec.cost
	else
		if live.energy < spec.cost then
			return false
		end
		live.energy -= spec.cost
	end
	return true
end

local function castBasic(live: Live, spec: SkillSpec, origin: Vector3, dir: Vector3, combo: number)
	local skill = Skills.basic
	local mul = if combo >= (skill.comboHits or 3) then skill.comboMul or 1 else 1
	local reach = spec.range
	local cframe = CFrame.lookAt(origin, origin + dir) * CFrame.new(0, 0, -reach / 2)
	for _, model in targetsInBox(cframe, Vector3.new(reach, MELEE_HEIGHT, reach)) do
		strike(live, model, spec.damage * mul, spec.element, true)
	end
end

-- Mirrors the client's Common.ground: drop a ray from just above `position` onto the
-- Arena/Terrain so server hits land on the same floor the client draws on.
local function groundHit(position: Vector3, maxDrop: number): Vector3?
	local include: { Instance } = { Workspace.Terrain }
	local arena = Workspace:FindFirstChild("Arena")
	if arena then
		table.insert(include, arena)
	end
	groundParams.FilterDescendantsInstances = include
	local hit = Workspace:Raycast(
		position + Vector3.new(0, GROUND_LIFT, 0),
		Vector3.new(0, -(maxDrop + GROUND_LIFT), 0),
		groundParams
	)
	return if hit then hit.Position else nil
end

-- Grounds a clamped aim point; with no floor under it, falls back to the caster's feet height.
local function groundTarget(live: Live, target: Vector3): Vector3
	local hit = groundHit(target, TARGET_GROUND_DROP)
	if hit then
		return hit
	end
	local root = live.root :: BasePart
	local humanoid = live.humanoid :: Humanoid
	local floorY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	return Vector3.new(target.X, floorY, target.Z)
end

local function castBladeRain(live: Live, spec: SkillSpec, target: Vector3, seed: number)
	for _, point in BladeLayout.points(seed, spec.count, spec.radius) do
		task.delay(BLADE_DROP_DELAY + point.delay + BLADE_FALL_TIME, function()
			if live.player.Parent ~= Players then
				return
			end
			local flat = target + Vector3.new(point.x, 0, point.z)
			local impact = groundHit(flat, BLADE_GROUND_DROP) or flat
			for _, model in targetsInRadius(impact + Vector3.new(0, BLADE_HIT_LIFT, 0), BLADE_HIT_RADIUS) do
				strike(live, model, spec.damage, spec.element, true)
			end
			explode(live, impact, spec)
		end)
	end
end

local function castDawnbreaker(live: Live, spec: SkillSpec, origin: Vector3, dir: Vector3)
	local length = spec.length or spec.range
	local width = spec.width or 8
	task.delay(spec.channel or Skills.dawnbreaker.channel or 1.2, function()
		if lives[live.player] ~= live or not isAlive(live) then
			return
		end
		local cframe = CFrame.lookAt(origin, origin + dir) * CFrame.new(0, 0, -length / 2)
		for _, model in targetsInBox(cframe, Vector3.new(width, BEAM_HEIGHT, length)) do
			strike(live, model, spec.damage, spec.element, true)
		end
	end)
end

local function characterFilter(): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- Steps the lance along `dir` at `speed`, spherecasting each frame's segment. Enemies are
-- excluded once hit, so the cast continues through them (pierce); world geometry stops it.
local function flyLance(live: Live, spec: SkillSpec, origin: Vector3, dir: Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterFilter()
	local speed = spec.speed or 120
	local range = spec.range
	local folder = Combat.enemyFolder()
	local position = origin
	local traveled = 0
	while traveled < range do
		local dt = task.wait()
		if live.player.Parent ~= Players then
			return
		end
		local step = math.min(speed * dt, range - traveled)
		local delta = dir * step
		for _ = 1, LANCE_MAX_HITS_PER_STEP do
			local result = Workspace:Spherecast(position, LANCE_RADIUS, delta, params)
			if not result then
				break
			end
			local model = targetOf(result.Instance)
			if model then
				params:AddToFilter(model)
				strike(live, model, spec.damage, spec.element, true)
				explode(live, result.Position, spec)
				if not spec.pierce then
					return
				end
			elseif result.Instance:IsDescendantOf(folder) then
				-- a dead or unregistered enemy: pass through it
				local parent = result.Instance.Parent
				params:AddToFilter(if parent and parent ~= folder then parent else result.Instance)
			else
				return
			end
		end
		position += delta
		traveled += step
	end
end

local function castCrimsonLance(live: Live, spec: SkillSpec, origin: Vector3, dir: Vector3)
	local count = math.max(1, spec.count)
	local spread = spec.spreadDeg or 0
	for i = 1, count do
		-- `spreadDeg` is the full fan, centered on the aim direction.
		local angle = if count > 1 then -spread / 2 + spread * (i - 1) / (count - 1) else 0
		local laneDir = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(dir)
		task.spawn(flyLance, live, spec, origin, laneDir)
	end
end

local function castHexAegis(live: Live, spec: SkillSpec)
	live.absorb = spec.absorb or 0
	live.absorbEndsAt = os.clock() + (spec.duration or 0)
end

local function castAscension(live: Live, spec: SkillSpec)
	local duration = spec.duration or 0
	live.transformed = true
	live.transformEndsAt = if duration == math.huge then nil else os.clock() + duration
	live.drainPerSec = spec.drainPerSec
	recompute(live)
end

local function onCast(player: Player, skillId: unknown, aim: unknown)
	local live = lives[player]
	if not live or not live.limiter:allow(os.clock()) then
		return
	end
	if type(skillId) ~= "string" or not skillSet[skillId] then
		return
	end
	if typeof(aim) ~= "Vector3" or not isFinite(aim :: Vector3) then
		return
	end
	if not isAlive(live) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local id = skillId :: string
	local skill = Skills[id]
	if skill.unlockLevel and profile.level < skill.unlockLevel then
		return
	end
	if id == "ascension" and live.transformed then
		return
	end
	local now = os.clock()
	if not Cooldowns.ready(live.cooldowns, id, now) then
		return
	end
	-- basic costs stamina (dodge spec §1); skills cost none.
	if id == "basic" and not Stamina.canSpend(live.stamina) then
		return
	end
	local spec = SkillResolver.resolve(id, ProfileRules.gemIds(profile, id), live.stats, live.transformed)
	if not pay(live, spec) then
		return
	end
	if id == "basic" then
		Stamina.spend(live.stamina, DodgeConfig.basicStaminaCost, now)
	end
	Cooldowns.start(live.cooldowns, id, now, spec.cooldown)

	local root = live.root :: BasePart
	local origin = root.Position
	local target = clampTarget(origin, aim :: Vector3, spec)
	local dir = flatDirection(origin, if target == origin then aim :: Vector3 else target, root)
	if id == "blade_rain" then
		target = groundTarget(live, target)
	end
	local combo: number? = nil
	if id == "basic" then
		if now - live.lastBasicAt > COMBO_RESET then
			live.combo = 0
		end
		live.combo = live.combo % (skill.comboHits or 3) + 1
		live.lastBasicAt = now
		combo = live.combo
	end

	local seed = random:NextInteger(1, 2 ^ 31 - 1)
	local event: Net.FxEvent = {
		skillId = id,
		casterUserId = player.UserId,
		origin = origin,
		target = target,
		spec = spec,
		seed = seed,
		serverTime = Workspace:GetServerTimeNow(),
		combo = combo,
	}
	remotes.SkillFx:FireAllClients(event)

	if id == "basic" then
		castBasic(live, spec, origin, dir, combo or 1)
	elseif id == "blade_rain" then
		castBladeRain(live, spec, target, seed)
	elseif id == "dawnbreaker" then
		castDawnbreaker(live, spec, origin, dir)
	elseif id == "crimson_lance" then
		castCrimsonLance(live, spec, origin, dir)
	elseif id == "hex_aegis" then
		castHexAegis(live, spec)
	elseif id == "ascension" then
		castAscension(live, spec)
	end
	PlayerData.onChanged(player)
end

local function onHeartbeat(dt: number)
	local now = os.clock()
	for player, live in lives do
		local before, staminaBefore = live.energy, live.stamina.value
		if live.transformed and live.drainPerSec then
			-- radiant_mind: the drain replaces regen, so the form ends when Energy runs out.
			live.energy = math.max(0, live.energy - live.drainPerSec * dt)
		elseif isAlive(live) then
			live.energy = math.min(live.stats.maxEnergy, live.energy + live.stats.energyRegen * dt)
		end
		if isAlive(live) then
			Stamina.regen(live.stamina, live.stats.maxStamina, live.stats.staminaRegen, now, dt)
		end
		if live.transformed then
			local expired = live.transformEndsAt ~= nil and now >= live.transformEndsAt
			local drained = live.drainPerSec ~= nil and live.energy <= 0
			if expired or drained then
				endTransform(live)
			end
		end
		if live.absorb > 0 and now >= live.absorbEndsAt then
			live.absorb = 0
		end
		if live.energy ~= before or live.stamina.value ~= staminaBefore then
			PlayerData.onChanged(player)
		end
	end
end

function Combat.start()
	remotes = Net.server()
	Combat.enemyFolder()
	PlayerData.setLiveProvider(Combat.getLive)
	PlayerData.onLoaded(createLive)
	PlayerData.onStatsChanged(function(player: Player)
		local live = lives[player]
		if live then
			recompute(live)
		end
	end)
	Players.PlayerRemoving:Connect(removeLive)
	remotes.CastSkill.OnServerEvent:Connect(onCast)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return Combat
