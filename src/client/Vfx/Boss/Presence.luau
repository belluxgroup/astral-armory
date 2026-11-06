--!strict
-- The Golden Tyrant's standing presence on every client, plus its three state moments.
--
--   attach    once per boss model: the looping idle pose, the cape panels swaying on their
--             hinges (lifting back with speed, a slow breath, a side flutter) and the halo
--             turning slowly behind the head. Late joiners and streamed-in models attach
--             too, and pick up phase 2 from the replicated health.
--   spawn     a gold rune circle opens, a pillar of light drops, the boss fades in
--   enrage    a gold-crimson aura (aura_flame and glow_soft emitters, light, Highlight),
--             brighter eyes, neon cape trim, a faster halo, and a short screen tint
--   defeated  the halo rises away, the body breaks into gold particles, then a golden
--             pillar of light

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PoseClips =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PoseClips"))
local Common = require(script.Parent.Parent.Common)
local Impact = require(script.Parent.Parent.Impact)
local Poses = require(script.Parent.Parent.Poses)
local Kit = require(script.Parent.Kit)

type Effect = Common.Effect

local Presence = {}

local AURA_LIFETIME = 3600
local DEFEAT_TIME = 3.4
local SPAWN_TIME = 1.6
local TINT_RADIUS = 120

type Watch = {
	model: Model,
	root: BasePart?,
	capes: { Motor6D },
	halo: Motor6D?,
	k: number,
	lift: number,
	haloAngle: number,
	haloSpeed: number,
	ascendAt: number?,
	enraged: boolean,
	aura: Effect?,
	connections: { RBXScriptConnection },
}

local watched: { [Model]: Watch } = {}
local stepConnection: RBXScriptConnection? = nil

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function detach(model: Model)
	local w = watched[model]
	if not w then
		return
	end
	watched[model] = nil
	for _, c in w.connections do
		c:Disconnect()
	end
	local aura = w.aura
	if aura and not aura.dead then
		aura:finish()
	end
	Poses.stop(model)
end

local function step(dt: number)
	local now = os.clock()
	for model, w in watched do
		if not model.Parent then
			detach(model)
			continue
		end
		-- Cape: lift back with ground speed, plus a breath and a side flutter.
		local speed = 0
		local root = w.root
		if root then
			local v = root.AssemblyLinearVelocity
			speed = Vector3.new(v.X, 0, v.Z).Magnitude
		end
		local run = clamp01(speed / 22)
		local target = -math.rad(38) * run
		w.lift += (target - w.lift) * math.min(dt * 5, 1)
		local energy = if w.enraged then 1.6 else 1
		for i, motor in w.capes do
			if motor.Parent then
				local breath = math.sin(now * 1.6 + i * 0.9) * math.rad(2.5)
					+ math.sin(now * 3.1 + i * 2) * math.rad(1.2) * (0.5 + run) * energy
				local flutter = math.sin(now * 2.2 + i * 1.7) * math.rad(3) * (0.4 + run) * energy
				motor.Transform = CFrame.Angles(w.lift * (if i == 2 then 1 else 0.9) + breath, 0, flutter)
			end
		end
		-- Halo: a slow turn and bob; on defeat it rises and spins away.
		local halo = w.halo
		if halo and halo.Parent then
			local spin = w.haloSpeed
			local rise = 0
			local ascendAt = w.ascendAt
			if ascendAt then
				local t = now - ascendAt
				spin += 6 * clamp01(t)
				rise = t * t * 3 * w.k
			end
			w.haloAngle += dt * spin
			local bob = math.sin(now * 1.3) * 0.06 * w.k
			halo.Transform = CFrame.new(0, bob + rise, 0) * CFrame.Angles(0, 0, w.haloAngle)
		end
	end
	if next(watched) == nil and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

---------------------------------------------------------------- enrage

local function buildAura(w: Watch)
	local model = w.model
	local fx = Common.effect("BossEnrage", AURA_LIFETIME)
	w.aura = fx
	local k = w.k
	local torso = Kit.part(model, "UpperTorso")
	if torso then
		fx:emitter(torso, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Rate = 26,
			Lifetime = NumberRange.new(0.6, 1.0),
			Speed = NumberRange.new(1, 3),
			Acceleration = Vector3.new(0, 9, 0),
			Size = Common.seq({ { 0, 1.6 * k }, { 0.5, 2.6 * k }, { 1, 0.4 } }),
			Transparency = Common.seq({ { 0, 0.4 }, { 0.6, 0.55 }, { 1, 1 } }),
			Color = Common.colors(Kit.GOLD, Kit.CRIMSON_HOT, Kit.CRIMSON),
			Brightness = 2,
			RotSpeed = NumberRange.new(-30, 30),
		}, "aura_flame")
		fx:emitter(torso, {
			Rate = 6,
			Lifetime = NumberRange.new(0.8, 1.2),
			Size = Common.seq({ { 0, 5 * k }, { 1, 7 * k } }),
			Transparency = Common.seq({ { 0, 0.8 }, { 0.5, 0.75 }, { 1, 1 } }),
			Color = Common.colors(Kit.GOLD, Kit.CRIMSON),
			Brightness = 1.5,
			LockedToPart = true,
		}, "glow_soft")
		fx:emitter(torso, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Rate = 18,
			Lifetime = NumberRange.new(0.8, 1.3),
			Speed = NumberRange.new(2, 5),
			Acceleration = Vector3.new(0, 7, 0),
			Size = Common.seq({ { 0, 0.35 }, { 1, 0 } }),
			Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
			Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD),
			Brightness = 3,
		}, "glow_star")
		fx:light(torso, { Color = Kit.CRIMSON_HOT:Lerp(Kit.GOLD, 0.4), Range = 22, Brightness = 2.5 })
	end
	for _, limb in { "LeftHand", "RightHand", "LeftFoot", "RightFoot" } do
		local p = Kit.part(model, limb)
		if p then
			fx:emitter(p, {
				Rate = 10,
				Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(0.5, 1.5),
				Acceleration = Vector3.new(0, 7, 0),
				Size = Common.seq({ { 0, 1.1 * k }, { 1, 0 } }),
				Transparency = Common.seq({ { 0, 0.35 }, { 1, 1 } }),
				Color = Common.colors(Kit.GOLD, Kit.CRIMSON),
				Brightness = 2,
			}, "aura_flame")
		end
	end
	-- Brighter eyes, with a small glow on each.
	local eyes = Kit.named(model, Kit.NAMES.eye)
	for _, eye in eyes do
		eye.Color = Kit.Armor.COLORS.eyeEnraged
		fx:emitter(eye, {
			Rate = 8,
			Lifetime = NumberRange.new(0.2, 0.3),
			Size = Common.seq({ { 0, 0.9 * k }, { 1, 0.4 * k } }),
			Transparency = Common.seq({ { 0, 0.35 }, { 1, 1 } }),
			Color = ColorSequence.new(Kit.CRIMSON_HOT),
			Brightness = 3,
			LockedToPart = true,
		}, "glow_soft")
	end
	-- The cape trim turns to light.
	local trims = Kit.named(model, Kit.NAMES.capeTrim)
	for _, trim in trims do
		trim.Material = Enum.Material.Neon
		trim.Color = Kit.GOLD
	end
	local halos = Kit.named(model, Kit.NAMES.haloEdge)
	for _, edge in halos do
		edge.Color = Kit.WHITE_GOLD
	end
	local highlight = fx:own(Instance.new("Highlight"))
	highlight.FillColor = Kit.CRIMSON
	highlight.OutlineColor = Kit.GOLD
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 0.3
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	fx:onStep(function(_dt, elapsed)
		highlight.OutlineTransparency = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(elapsed * 4))
		return false
	end)
	fx:onFinish(function()
		for _, eye in eyes do
			if eye.Parent then
				eye.Color = Kit.Armor.COLORS.eye
			end
		end
		for _, trim in trims do
			if trim.Parent then
				trim.Material = Enum.Material.Metal
				trim.Color = Kit.Armor.COLORS.gold
			end
		end
		for _, edge in halos do
			if edge.Parent then
				edge.Color = Kit.Armor.COLORS.edge
			end
		end
	end)
end

local function enrageBurst(model: Model)
	local center = model:GetPivot().Position
	local floor = Common.ground(center, 30)
	Common.flash(
		Kit.CRIMSON,
		0.9,
		{ strength = 0.35, attack = 0.15, position = center, radius = TINT_RADIUS }
	)
	Common.shake(0.8, 0.6, center, nil, Kit.BIG_RADIUS)
	Impact.shockwave(floor, 26, Kit.GOLD, 0.8, { width = 1.3, discColor = Kit.CRIMSON })
	Impact.shockwave(floor, 14, Kit.CRIMSON_HOT, 0.55, { width = 0.8, disc = false })
	Impact.play(center, Kit.ROYAL_PALETTE, 1.6, false, { ring = false, dust = false })
end

---------------------------------------------------------------- public

-- Starts the boss's idle, cape and halo on this client (once per model).
function Presence.attach(model: Model)
	if watched[model] or not model.Parent then
		return
	end
	local torso = Kit.part(model, "UpperTorso")
	local capes: { Motor6D } = {}
	local halo: Motor6D? = nil
	if torso then
		for i = 1, 3 do
			local m = torso:FindFirstChild(Kit.NAMES.capeHinge .. i)
			if m and m:IsA("Motor6D") then
				table.insert(capes, m)
			end
		end
		local h = torso:FindFirstChild(Kit.NAMES.haloSpin)
		if h and h:IsA("Motor6D") then
			halo = h
		end
	end
	local w: Watch = {
		model = model,
		root = Kit.part(model, "HumanoidRootPart"),
		capes = capes,
		halo = halo,
		k = Kit.scale(model),
		lift = 0,
		haloAngle = 0,
		haloSpeed = 0.5,
		ascendAt = nil,
		enraged = false,
		aura = nil,
		connections = {},
	}
	watched[model] = w
	table.insert(
		w.connections,
		model.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				detach(model)
			end
		end)
	)
	Poses.ensureIdle(model, PoseClips.BOSS_IDLE)
	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
	-- Phase 2 already under way (late join, or the model streamed in): show it quietly.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and humanoid.Health <= humanoid.MaxHealth * Kit.Config.phase2At then
		Presence.enrage(model, false)
	end
end

-- Phase 2. `burst` plays the moment itself (tint, shockwaves); the aura is applied once.
function Presence.enrage(model: Model?, burst: boolean)
	local boss = model or Kit.findBoss()
	if not boss then
		return
	end
	Presence.attach(boss)
	local w = watched[boss]
	if burst then
		enrageBurst(boss)
	end
	if w and not w.enraged then
		w.enraged = true
		w.haloSpeed = 1.6
		buildAura(w)
	end
end

function Presence.spawn(model: Model?, position: Vector3?)
	local boss = model or Kit.findBoss()
	local center = if boss then boss:GetPivot().Position elseif position then position else nil
	if not center then
		return
	end
	local floor = Common.ground(if position then position else center, 40)
	local fx = Common.effect("BossSpawn", SPAWN_TIME)
	local circle = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.15, 0)), 12, {
		rings = { 1, 0.86, 0.5 },
		ringWidth = 0.35,
		star = 0.86,
		spokes = 12,
		color = Kit.GOLD,
		runes = true,
		runeColor = Kit.WHITE_GOLD,
		brightness = 3,
	})
	circle:setScale(0.05)
	Impact.pillar(floor, 70, 11, Kit.ROYAL_PALETTE, 1.3)
	Common.flash(
		Kit.WHITE_GOLD,
		0.5,
		{ strength = 0.4, attack = 0.08, position = center, radius = TINT_RADIUS }
	)
	Common.shake(0.7, 0.5, center, nil, Kit.BIG_RADIUS)
	local parts: { BasePart } = {}
	if boss then
		Presence.attach(boss)
		for _, d in boss:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				d.LocalTransparencyModifier = 1
				table.insert(parts, d)
			end
		end
		fx:onFinish(function()
			for _, p in parts do
				if p.Parent then
					p.LocalTransparencyModifier = 0
				end
			end
		end)
	end
	fx:at(0.35, function()
		Impact.shockwave(floor, 20, Kit.GOLD, 0.7, { width = 1, discColor = Kit.DEEP_GOLD })
	end)
	fx:onStep(function(_dt, elapsed)
		local open = clamp01(elapsed / 0.5)
		circle:setScale(0.05 + 0.95 * (1 - (1 - open) ^ 3))
		circle:setCFrame(CFrame.new(floor + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, elapsed * 0.8, 0))
		circle:setTransparency(math.max(0.1, clamp01((elapsed - 0.9) / 0.6)))
		local appear = clamp01((elapsed - 0.25) / 0.7)
		for _, p in parts do
			p.LocalTransparencyModifier = 1 - appear
		end
		return false
	end)
end

function Presence.defeated(model: Model?, position: Vector3?)
	local boss = model or Kit.findBoss()
	local center = if boss then boss:GetPivot().Position elseif position then position else nil
	if not center then
		return
	end
	local w = if boss then watched[boss] else nil
	if w then
		local aura = w.aura
		if aura and not aura.dead then
			aura:finish()
		end
		w.aura = nil
		w.ascendAt = os.clock()
	end
	local floor = Common.ground(center, 40)
	local fx = Common.effect("BossDefeated", DEFEAT_TIME)
	local size = if boss then boss:GetExtentsSize() else Vector3.new(6, 9, 4)
	local volume = fx:part({ Size = size, CFrame = CFrame.new(center) })
	local motes = fx:emitter(volume, {
		Rate = 0,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(1, 4),
		Acceleration = Vector3.new(0, 12, 0),
		Drag = 0.6,
		Lifetime = NumberRange.new(1.2, 2),
		Size = Common.seq({ { 0, 0 }, { 0.15, 0.9 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
		Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD, Kit.DEEP_GOLD),
		Brightness = 3,
	}, "glow_star")
	local embers = fx:emitter(volume, {
		Rate = 0,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(0.5, 2),
		Acceleration = Vector3.new(0, 6, 0),
		Lifetime = NumberRange.new(0.8, 1.3),
		Size = Common.seq({ { 0, 2.2 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0.5 }, { 1, 1 } }),
		Color = Common.colors(Kit.GOLD, Kit.CRIMSON),
	}, "glow_soft")
	local parts: { BasePart } = {}
	if boss then
		for _, d in boss:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	fx:at(0.9, function()
		Impact.pillar(floor, 130, 16, Kit.ROYAL_PALETTE, 2.3)
		Impact.shockwave(floor, 32, Kit.GOLD, 1.1, { width = 1.6, transparency = 0.1 })
		Common.flash(
			Kit.WHITE_GOLD,
			0.8,
			{ strength = 0.5, attack = 0.1, position = center, radius = TINT_RADIUS }
		)
		Common.shake(1.0, 0.7, center, nil, Kit.BIG_RADIUS)
	end)
	fx:onStep(function(_dt, elapsed)
		-- The kneel reads first, then the body breaks up from 0.35 s to 1.4 s.
		local dissolve = clamp01((elapsed - 0.35) / 1.05)
		local sweep = math.sin(math.pi * dissolve)
		if motes then
			motes.Rate = 160 * sweep
		end
		if embers then
			embers.Rate = 40 * sweep
		end
		if boss and boss.Parent then
			volume.CFrame = CFrame.new(boss:GetPivot().Position)
		end
		for _, p in parts do
			if p.Parent then
				p.LocalTransparencyModifier = dissolve
			end
		end
		return false
	end)
end

-- Watches for the boss model appearing (late joins, streaming) and attaches to it.
function Presence.start()
	local function watchFolder(folder: Instance)
		folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") and child.Name == Kit.Armor.MODEL_NAME then
				task.defer(Presence.attach, child)
			end
		end)
		local existing = folder:FindFirstChild(Kit.Armor.MODEL_NAME)
		if existing and existing:IsA("Model") then
			Presence.attach(existing)
		end
	end
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		watchFolder(enemies)
	else
		local conn: RBXScriptConnection? = nil
		conn = workspace.ChildAdded:Connect(function(child)
			if child.Name == "Enemies" then
				if conn then
					conn:Disconnect()
				end
				watchFolder(child)
			end
		end)
	end
end

return Presence
