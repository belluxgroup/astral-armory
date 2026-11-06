--!strict
-- Hộ Vệ Nhật Thực (eclipse_warden) effects, driven by BossFx.
--
--   telegraph  a red ground circle whose fill grows to the edge over `delay`,
--              under a pulsing outline and a slow warning sigil
--   slam       a dust shockwave, debris, an impact, and a strong shake for
--              everyone within 40 studs
--   blades     a small red warning ring, then a dark blade drops out of the
--              sky with a purple trail onto it, with a small shadow impact
--   enrage     a persistent dark-violet aura on the boss (smoke, motes, a
--              violet Highlight and light) plus a short screen tint
--   defeated   the boss breaks into rising light particles and a golden
--              pillar; the enrage aura ends

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SwordModel = require(Shared:WaitForChild("Models"):WaitForChild("SwordModel"))
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))
local Common = require(script.Parent.Common)
local Impact = require(script.Parent.Impact)

type BossFx = Common.BossFx
type Palette = Common.Palette

local BossTelegraph = {}

local BOSS_NAME = "EclipseWarden"
local SLAM_SHAKE_RADIUS = 40
local TINT_RADIUS = 120
local BLADE_SCALE = 1.8
local BLADE_FALL = 0.32
local BLADE_HEIGHT = 34

local named = VfxPalette.named

local TELEGRAPH: Palette = {
	core = named.telegraphCore,
	glow = named.telegraph,
	accent = Color3.fromRGB(120, 10, 10),
	brightness = 1.2,
}
local SHADOW: Palette = {
	core = Color3.fromRGB(220, 190, 255),
	glow = named.shadowGlow,
	accent = named.shadow,
	brightness = 1.2,
}
local DUST: Palette = {
	core = Color3.fromRGB(255, 236, 214),
	glow = named.dust,
	accent = Color3.fromRGB(96, 84, 74),
	brightness = 0.8,
}
local GOLDEN = VfxPalette.get("none", true)

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function findBoss(near: Vector3?): Model?
	local enemies = workspace:FindFirstChild("Enemies")
	if not enemies then
		return nil
	end
	local named_ = enemies:FindFirstChild(BOSS_NAME)
	if named_ and named_:IsA("Model") then
		return named_
	end
	if not near then
		return nil
	end
	-- Fallback: the largest model close to the event position.
	local best: Model? = nil
	local bestSize = 0
	for _, m in enemies:GetChildren() do
		if m:IsA("Model") and (m:GetPivot().Position - near).Magnitude < 25 then
			local size = m:GetExtentsSize().Magnitude
			if size > bestSize then
				bestSize = size
				best = m
			end
		end
	end
	return best
end

---------------------------------------------------------------- telegraph

-- A ground warning of `radius` that fills over `delay` seconds.
local function telegraph(position: Vector3, radius: number, delay: number)
	local floor = Common.ground(position, 30)
	local fx = Common.effect("BossTelegraph", delay + 0.35)
	local outline = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.14, 0)), radius, {
		rings = { 1, 0.965 },
		ringWidth = math.max(radius * 0.03, 0.25),
		color = TELEGRAPH.glow,
		brightness = 3,
	})
	local runes = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.13, 0)), radius * 0.8, {
		rings = { 1 },
		ringWidth = math.max(radius * 0.015, 0.15),
		star = 0.95,
		color = TELEGRAPH.accent,
		runes = true,
		brightness = 1.5,
	})
	local fillCf = CFrame.new(floor + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local fill = fx:part({
		Shape = Enum.PartType.Cylinder,
		Color = TELEGRAPH.glow,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		Size = Vector3.new(0.08, 0.1, 0.1),
		CFrame = fillCf,
	})
	local base = fx:part({
		Shape = Enum.PartType.Cylinder,
		Color = TELEGRAPH.accent,
		Material = Enum.Material.Neon,
		Transparency = 0.85,
		Size = Vector3.new(0.06, radius * 2, radius * 2),
		CFrame = fillCf * CFrame.new(-0.01, 0, 0),
	})
	outline:setScale(1.25)
	outline:setTransparency(1)
	fx:onStep(function(_dt, elapsed)
		local snap = clamp01(elapsed / 0.12)
		outline:setScale(1.25 - 0.25 * (1 - (1 - snap) ^ 2))
		local t = clamp01(elapsed / delay)
		local blink = 0.5 + 0.5 * math.sin(elapsed * (8 + 18 * t))
		local after = clamp01((elapsed - delay) / 0.3)
		outline:setTransparency(math.max(0.25 * blink * (1 - t) + (1 - snap), after))
		runes:setCFrame(CFrame.new(floor + Vector3.new(0, 0.13, 0)) * CFrame.Angles(0, elapsed * 0.6, 0))
		runes:setTransparency(math.max(0.45, after))
		local d = radius * 2 * t
		fill.Size = Vector3.new(0.08, math.max(d, 0.1), math.max(d, 0.1))
		fill.Transparency = if elapsed < delay then 0.62 - 0.2 * t else 0.3 + 0.7 * after
		base.Transparency = 0.85 + 0.15 * after
		return after >= 1
	end)
end

---------------------------------------------------------------- slam

local function slam(position: Vector3, radius: number)
	local floor = Common.ground(position, 30)
	Impact.shockwave(floor, radius * 1.15, DUST.glow, 0.65, {
		width = 1.4,
		discColor = DUST.accent,
		transparency = 0.1,
		brightness = 1.5,
	})
	Impact.shockwave(floor, radius * 0.6, TELEGRAPH.glow, 0.4, { width = 0.8, disc = false })
	Impact.play(floor, DUST, 2, false, { light = false })
	Impact.play(floor, TELEGRAPH, 1.2, false, { ring = false, dust = false })
	Common.shake(1.5, 0.6, floor, nil, SLAM_SHAKE_RADIUS)

	local fx = Common.effect("BossSlam", 1.6)
	local holder = fx:part({ CFrame = CFrame.new(floor + Vector3.new(0, 0.5, 0)) })
	local att = fx:attachment(holder)
	local dust = fx:emitter(att, {
		Enabled = false,
		LightEmission = 0.1,
		LightInfluence = 0.6,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(88, 88),
		Speed = NumberRange.new(18, 34),
		Drag = 4,
		Acceleration = Vector3.new(0, 1.5, 0),
		Lifetime = NumberRange.new(0.9, 1.4),
		Size = Common.seq({ { 0, 3 }, { 1, 9 } }),
		Transparency = Common.seq({ { 0, 0.35 }, { 0.4, 0.55 }, { 1, 1 } }),
		Color = Common.colors(DUST.glow, DUST.accent),
		RotSpeed = NumberRange.new(-30, 30),
	}, "smoke_soft")
	if dust then
		dust:Emit(36)
	end
	local debris = fx:emitter(att, {
		Enabled = false,
		LightEmission = 0,
		LightInfluence = 1,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(45, 45),
		Speed = NumberRange.new(25, 45),
		Acceleration = Vector3.new(0, -80, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Size = Common.seq({ { 0, 0.7 }, { 1, 0.5 } }),
		Transparency = Common.seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(70, 62, 66)),
		RotSpeed = NumberRange.new(-360, 360),
	}, "smoke_soft")
	if debris then
		debris:Emit(24)
	end
end

---------------------------------------------------------------- blades

local function buildShadowBlade(): Model
	local model = SwordModel.build(true)
	model:ScaleTo(BLADE_SCALE)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Material == Enum.Material.Neon then
				d.Color = SHADOW.glow
			else
				d.Color = Color3.fromRGB(26, 18, 34)
				d.Reflectance = 0.05
			end
		end
	end
	(model.PrimaryPart :: BasePart).Anchored = true
	return model
end

local shadowPool = Common.pool(buildShadowBlade(), 16, function(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
		end
	end
end)

local function blades(position: Vector3, radius: number, delay: number)
	local floor = Common.ground(position, 30)
	telegraph(floor, radius, delay)
	local fx = Common.effect("BossBlade", delay + 0.9)
	local model = fx:borrow(shadowPool)
	local root = model.PrimaryPart :: BasePart
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			d.LocalTransparencyModifier = 1
		end
	end
	model.Parent = fx.folder
	local top = root:FindFirstChild("TrailTop") :: Attachment
	local bottom = root:FindFirstChild("TrailBottom") :: Attachment
	-- Side-by-side attachments give the falling blade a visible camera-facing trail.
	local l = fx:own(Instance.new("Attachment"))
	l.Position = bottom.Position + Vector3.new(-0.3, 0, 0)
	l.Parent = root
	local r = fx:own(Instance.new("Attachment"))
	r.Position = bottom.Position + Vector3.new(0.3, 0, 0)
	r.Parent = root
	local trail = fx:trail(l, r, {
		FaceCamera = true,
		Lifetime = 0.3,
		Color = Common.colors(SHADOW.core, SHADOW.glow, SHADOW.accent),
		Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
		WidthScale = Common.seq({ { 0, 1 }, { 1, 0.2 } }),
		Brightness = 2,
	})
	trail.Enabled = false
	local wisps = fx:emitter(top, {
		Rate = 30,
		LightEmission = 0.4,
		Lifetime = NumberRange.new(0.3, 0.5),
		Size = Common.seq({ { 0, 1.2 }, { 1, 2.5 } }),
		Transparency = Common.seq({ { 0, 0.4 }, { 1, 1 } }),
		Color = Common.colors(SHADOW.glow, SHADOW.accent),
	}, "smoke_soft")
	if wisps then
		wisps.Enabled = false
	end

	-- Model space: the tip sits TIP studs from BladeCore along -Y once flipped.
	local tipOffset = 1.72 * BLADE_SCALE
	local yaw = math.random() * math.pi * 2
	local fallStart = math.max(delay - BLADE_FALL, 0)
	local landed = false
	fx:onStep(function(_dt, elapsed)
		local appear = clamp01((elapsed - fallStart + 0.15) / 0.15)
		local u = clamp01((elapsed - fallStart) / BLADE_FALL)
		local fadeOut = clamp01((elapsed - delay - 0.35) / 0.4)
		local height = BLADE_HEIGHT * (1 - u * u) - 1.0 * u - 0.6 * fadeOut
		root.CFrame = CFrame.new(floor + Vector3.new(0, height + tipOffset, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(math.pi, 0, 0)
		local ltm = 1 - appear * (1 - fadeOut)
		for _, p in parts do
			p.LocalTransparencyModifier = ltm
		end
		if appear > 0 and not landed then
			trail.Enabled = true
			if wisps then
				wisps.Enabled = true
			end
		end
		if u >= 1 and not landed then
			landed = true
			Impact.play(floor, SHADOW, 0.9, false, {})
			Common.shake(0.4, 0.2, floor, nil)
			fx:at(0.12, function()
				trail.Enabled = false
				if wisps then
					wisps.Enabled = false
				end
			end)
		end
		return fadeOut >= 1
	end)
end

---------------------------------------------------------------- enrage

local enrageFx: Common.Effect? = nil

local function endEnrage()
	local fx = enrageFx
	enrageFx = nil
	if fx and not fx.dead then
		fx:finish()
	end
end

local function enrage(position: Vector3?)
	endEnrage()
	local boss = findBoss(position)
	local center = if boss then boss:GetPivot().Position elseif position then position else nil
	if center then
		Common.flash(
			named.enrage,
			0.8,
			{ strength = 0.35, attack = 0.15, position = center, radius = TINT_RADIUS }
		)
		if Common.isNear(center, nil, TINT_RADIUS) then
			Common.shake(0.6, 0.5)
		end
		Impact.shockwave(Common.ground(center, 30), 24, named.shadowGlow, 0.8, { width = 1.2 })
	end
	if not boss then
		return
	end
	local fx = Common.effect("BossEnrage", 900)
	enrageFx = fx
	local torso = boss:FindFirstChild("UpperTorso") or boss:FindFirstChild("Torso") or boss.PrimaryPart
	if torso and torso:IsA("BasePart") then
		fx:emitter(torso, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Rate = 24,
			LightEmission = 0.2,
			Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(1, 3),
			Acceleration = Vector3.new(0, 7, 0),
			Size = Common.seq({ { 0, 3 }, { 1, 7 } }),
			Transparency = Common.seq({ { 0, 0.55 }, { 1, 1 } }),
			Color = Common.colors(named.enrage, named.shadow),
			RotSpeed = NumberRange.new(-40, 40),
		}, "smoke_soft")
		fx:emitter(torso, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Rate = 30,
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(2, 5),
			Acceleration = Vector3.new(0, 10, 0),
			Size = Common.seq({ { 0, 0.6 }, { 1, 0 } }),
			Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
			Color = Common.colors(SHADOW.core, named.shadowGlow),
			Brightness = 2,
		}, "glow_soft")
		fx:light(torso, { Color = named.shadowGlow, Range = 26, Brightness = 3 })
	end
	for _, limbName in { "LeftHand", "RightHand", "LeftFoot", "RightFoot" } do
		local limb = boss:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			fx:emitter(limb, {
				Rate = 14,
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(0.5, 1.5),
				Acceleration = Vector3.new(0, 6, 0),
				Size = Common.seq({ { 0, 2.2 }, { 1, 0 } }),
				Transparency = Common.seq({ { 0, 0.45 }, { 1, 1 } }),
				Color = Common.colors(named.shadowGlow, named.enrage),
			}, "glow_soft")
		end
	end
	local highlight = fx:own(Instance.new("Highlight"))
	highlight.FillColor = named.enrage
	highlight.OutlineColor = named.shadowGlow
	highlight.FillTransparency = 0.75
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = boss
	highlight.Parent = boss
	fx:connect(boss.AncestryChanged, function(_, parent)
		if parent == nil then
			endEnrage()
		end
	end)
	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	if humanoid then
		fx:connect(humanoid.Died, endEnrage)
	end
	fx:onStep(function(_dt, elapsed)
		highlight.OutlineTransparency = 0.15 + 0.25 * (0.5 + 0.5 * math.sin(elapsed * 4))
		return false
	end)
end

---------------------------------------------------------------- defeated

local function defeated(position: Vector3?)
	local boss = findBoss(position)
	endEnrage()
	local center = if boss then boss:GetPivot().Position elseif position then position else nil
	if not center then
		return
	end
	local floor = Common.ground(center, 40)
	Impact.pillar(floor, 120, 16, GOLDEN, 2.2)
	Impact.shockwave(floor, 30, named.radiantGold, 1.1, { width = 1.6, transparency = 0.1 })
	Common.flash(
		named.radiantGold,
		0.8,
		{ strength = 0.5, attack = 0.1, position = center, radius = TINT_RADIUS }
	)
	Common.shake(1.0, 0.7, center, nil, SLAM_SHAKE_RADIUS)

	local fx = Common.effect("BossDefeated", 3)
	local size = if boss then boss:GetExtentsSize() else Vector3.new(8, 16, 8)
	local volume = fx:part({ Size = size, CFrame = CFrame.new(center) })
	local motes = fx:emitter(volume, {
		Enabled = false,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(2, 6),
		Acceleration = Vector3.new(0, 14, 0),
		Drag = 0.5,
		Lifetime = NumberRange.new(1.2, 2.2),
		Size = Common.seq({ { 0, 0 }, { 0.15, 1.1 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
		Color = Common.colors(GOLDEN.core, named.radiantGold, GOLDEN.glow),
		Brightness = 3,
	}, "glow_star")
	local glow = fx:emitter(volume, {
		Enabled = false,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, 8, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Size = Common.seq({ { 0, 3 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0.4 }, { 1, 1 } }),
		Color = Common.colors(named.radiantGold, GOLDEN.glow),
	}, "glow_soft")
	if motes then
		motes:Emit(140)
	end
	if glow then
		glow:Emit(40)
	end
	-- The body dissolves into the light (local only: the server removes it).
	if boss then
		local parts: { BasePart } = {}
		for _, d in boss:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		fx:onStep(function(_dt, elapsed)
			local t = clamp01(elapsed / 0.9)
			for _, p in parts do
				if p.Parent then
					p.LocalTransparencyModifier = t
				end
			end
			return t >= 1
		end)
	end
end

---------------------------------------------------------------- dispatch

function BossTelegraph.play(evt: BossFx)
	if type(evt) ~= "table" then
		return
	end
	local kind = evt.event
	local position = evt.position
	if kind == "telegraph" and position then
		telegraph(position, evt.radius or 16, evt.delay or 1.2)
	elseif kind == "slam" and position then
		slam(position, evt.radius or 16)
	elseif kind == "blades" and position then
		blades(position, evt.radius or 5, evt.delay or 1)
	elseif kind == "enrage" then
		enrage(position)
	elseif kind == "defeated" then
		defeated(position)
	end
end

return BossTelegraph
