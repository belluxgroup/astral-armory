--!strict
-- Mưa Kiếm Tinh Tú (blade_rain).
--
--   0.00 s  a rune sigil spins open 25 studs above the target; a faint ring
--           marks the area on the ground (anticipation)
--   0.00-0.35  each blade from BladeLayout fades in point-down under the sigil
--   0.60 + delay  each blade drops in 0.12 s (Quad In), sticks into the floor,
--           and fires Impact.play (scale 0.6); every 4th impact shakes
--   1.40 s  the sigil and blades fade out; everything is gone by 2.5 s
--
-- Radiant adds a second, larger counter-rotating sigil and white-gold edges.
-- Element tints everything through VfxPalette.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeLayout = require(Shared:WaitForChild("Logic"):WaitForChild("BladeLayout"))
local SwordModel = require(Shared:WaitForChild("Models"):WaitForChild("SwordModel"))
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))
local Common = require(script.Parent.Common)
local Impact = require(script.Parent.Impact)

type FxEvent = Common.FxEvent
type Palette = Common.Palette

local BladeRain = {}

local SIGIL_HEIGHT = 25
local HOVER_HEIGHT = 21 -- tip height above the floor while hovering
local APPEAR_TIME = 0.22
local DROP_AT = 0.6
local DROP_TIME = 0.12
local FADE_AT = 1.4
local FADE_TIME = 0.5
local LIFETIME = 2.5
local TIP_OFFSET = 1.72 -- BladeCore centre to the tip
local EMBED = 0.6 -- how deep the tip sinks into the floor

type BladeInfo = {
	root: BasePart,
	parts: { BasePart },
	neon: { BasePart },
	trail: Trail,
	tipAttachment: Attachment,
}

local info: { [Model]: BladeInfo } = setmetatable({}, { __mode = "k" }) :: any

local function buildTemplate(): Model
	local model = SwordModel.build(true)
	local root = model.PrimaryPart :: BasePart
	root.Anchored = true
	-- Two attachments across the blade near the guard: a camera-facing trail
	-- between them leaves a thin streak above a blade falling point-down.
	local l = Instance.new("Attachment")
	l.Name = "StreakL"
	l.Position = Vector3.new(-0.12, -1.3, 0)
	l.Parent = root
	local r = Instance.new("Attachment")
	r.Name = "StreakR"
	r.Position = Vector3.new(0.12, -1.3, 0)
	r.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "Streak"
	trail.Attachment0 = l
	trail.Attachment1 = r
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Lifetime = 0.16
	trail.MinLength = 0.05
	trail.WidthScale = Common.seq({ { 0, 1 }, { 1, 0.2 } })
	trail.Transparency = Common.seq({ { 0, 0.1 }, { 1, 1 } })
	trail.Enabled = false
	trail.Parent = root
	return model
end

local function infoFor(model: Model): BladeInfo
	local existing = info[model]
	if existing then
		return existing
	end
	local root = model.PrimaryPart :: BasePart
	local parts: { BasePart } = {}
	local neon: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if d.Material == Enum.Material.Neon then
				table.insert(neon, d)
			end
		end
	end
	local made: BladeInfo = {
		root = root,
		parts = parts,
		neon = neon,
		trail = root:FindFirstChild("Streak") :: Trail,
		tipAttachment = root:FindFirstChild("TrailTop") :: Attachment,
	}
	info[model] = made
	return made
end

local function setFade(bi: BladeInfo, alpha: number)
	local ltm = 1 - alpha
	for _, p in bi.parts do
		p.LocalTransparencyModifier = ltm
	end
end

local bladePool = Common.pool(buildTemplate(), 48, function(model: Model)
	local bi = infoFor(model)
	bi.trail.Enabled = false
	setFade(bi, 0)
end)

local function easeBackOut(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

type BladeState = {
	model: Model,
	bi: BladeInfo,
	ground: Vector3,
	delay: number,
	yaw: number,
	landed: boolean,
	index: number,
}

function BladeRain.play(event: FxEvent)
	local spec = event.spec
	local palette: Palette = VfxPalette.get(spec.element, spec.radiant)
	local age0 = Common.age(event.serverTime)
	local fx = Common.effect("BladeRain", math.max(LIFETIME - age0, 0.5))
	local caster = event.casterUserId

	local center, _ = Common.ground(event.target)
	local radius = spec.radius
	local sigilCf = CFrame.new(center + Vector3.new(0, SIGIL_HEIGHT, 0))
	local sigilRadius = radius * 1.05 + 1.5
	local edgeColor = if spec.radiant then VfxPalette.named.radiantWhite else palette.glow

	-- Sky sigil (anticipation).
	local sigil = Common.sigil(fx, sigilCf, sigilRadius, {
		rings = { 1, 0.9, 0.42 },
		ringWidth = 0.5,
		star = 0.86,
		spokes = 6,
		color = palette.glow,
		runes = true,
		brightness = 2.5 * palette.brightness,
	})
	sigil:setScale(0.05)
	sigil:setTransparency(1)
	local motes = fx:emitter(sigil.part, {
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Bottom,
		Rate = 45,
		Lifetime = NumberRange.new(0.9, 1.5),
		Speed = NumberRange.new(1, 4),
		Acceleration = Vector3.new(0, -5, 0),
		Size = Common.seq({ { 0, 0 }, { 0.2, 0.55 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0.2 }, { 1, 1 } }),
		Color = Common.colors(palette.core, palette.glow),
		Brightness = 2 * palette.brightness,
	}, "glow_star")
	local sigilLight = fx:light(sigil.part, {
		Color = palette.glow,
		Range = math.min(sigilRadius * 2.2, 60),
		Brightness = 0,
	})

	local halo: Common.Sigil? = nil
	if spec.radiant then
		local h = Common.sigil(fx, sigilCf * CFrame.new(0, 1.6, 0), sigilRadius * 1.35, {
			rings = { 1, 0.94 },
			ringWidth = 0.4,
			star = 0.92,
			color = VfxPalette.named.radiantGold,
			brightness = 3,
		})
		h:setTransparency(1)
		halo = h
	end

	-- Ground ring showing the area that will be hit.
	local marker = Common.sigil(fx, CFrame.new(center + Vector3.new(0, 0.15, 0)), radius, {
		rings = { 1 },
		ringWidth = 0.3,
		color = palette.glow,
		brightness = 1.5,
	})
	marker:setTransparency(1)

	-- Blades.
	local points = BladeLayout.points(event.seed, spec.count, radius)
	local blades: { BladeState } = table.create(#points)
	for i, p in points do
		local model = fx:borrow(bladePool)
		local bi = infoFor(model)
		for _, part in bi.neon do
			part.Color = edgeColor
		end
		bi.trail.Color = Common.colors(palette.core, palette.glow)
		setFade(bi, 0)
		model.Parent = fx.folder
		local ground = Common.ground(Vector3.new(center.X + p.x, center.Y, center.Z + p.z), 12)
		local glint = fx:emitter(bi.tipAttachment, {
			Rate = 4,
			Lifetime = NumberRange.new(0.25, 0.4),
			Size = Common.seq({ { 0, 0 }, { 0.3, 1.3 }, { 1, 0 } }),
			Transparency = Common.seq({ { 0, 0.1 }, { 1, 1 } }),
			Color = ColorSequence.new(palette.core),
			RotSpeed = NumberRange.new(-90, 90),
			Brightness = 2,
			LockedToPart = true,
		}, "glow_star")
		if glint then
			glint.Enabled = false
		end
		table.insert(blades, {
			model = model,
			bi = bi,
			ground = ground,
			delay = p.delay,
			yaw = (i * 2.399) % (math.pi * 2),
			landed = false,
			index = i,
		})
		if glint then
			fx:at(math.max(p.delay - age0, 0), function()
				glint.Enabled = true
				glint:Emit(1)
			end)
			fx:at(math.max(DROP_AT + p.delay - age0, 0), function()
				glint.Enabled = false
			end)
		end
		if spec.radiant and i % 4 == 1 then
			fx:light(bi.root, { Color = VfxPalette.named.radiantGold, Range = 8, Brightness = 2.5 })
		end
	end

	local impacts = 0
	local shockwaveDone = false

	local function placeBlade(b: BladeState, tipHeight: number, yaw: number)
		local tip = b.ground + Vector3.new(0, tipHeight, 0)
		-- Point-down: blade +Y flipped to -Y, then spun around the vertical.
		b.bi.root.CFrame = CFrame.new(tip + Vector3.new(0, TIP_OFFSET, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(math.pi, 0, 0)
	end

	local function land(b: BladeState)
		b.landed = true
		impacts += 1
		Impact.play(b.ground, palette, 0.6, spec.impactExplosion, {
			light = impacts % 3 == 1,
			ring = true,
		})
		if impacts % 4 == 0 then
			Common.shake(0.35, 0.18, b.ground, caster)
		end
		if not shockwaveDone then
			shockwaveDone = true
			Impact.shockwave(center, radius, palette.glow, 0.6, { width = 0.7, transparency = 0.25 })
		end
		local trail = b.bi.trail
		fx:at(0.1, function()
			trail.Enabled = false
		end)
		-- Edge flare on impact, cooling back to the element tint.
		for _, part in b.bi.neon do
			part.Color = palette.core
			fx:tween(part, Common.info(0.35, Enum.EasingStyle.Quad), { Color = edgeColor })
		end
	end

	fx:onStep(function(_dt, elapsed)
		local T = elapsed + age0

		-- Sigil: spin open with overshoot, hold, then fade and widen.
		local open = clamp01(T / 0.38)
		local fadeT = clamp01((T - FADE_AT) / FADE_TIME)
		local spin = T * 0.7 + (1 - (1 - open) ^ 3) * 2.2
		sigil:setCFrame(sigilCf * CFrame.Angles(0, spin, 0))
		sigil:setScale(easeBackOut(open) * (1 + 0.12 * fadeT))
		local pulse = if T >= DROP_AT and T < DROP_AT + 0.25 then (1 - (T - DROP_AT) / 0.25) else 0
		sigil:setTransparency(math.max(0.05 + 0.95 * (1 - clamp01(T / 0.25)) - pulse * 0.05, fadeT ^ 0.8))
		sigilLight.Brightness = (2.5 * clamp01(T / 0.3) + pulse * 3) * (1 - fadeT) * palette.brightness
		if motes then
			motes.Enabled = T < FADE_AT
		end
		local h = halo
		if h then
			local hOpen = clamp01((T - 0.08) / 0.4)
			h:setCFrame(sigilCf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, -T * 0.9, 0))
			h:setScale(easeBackOut(hOpen) * (1 + 0.1 * fadeT))
			h:setTransparency(math.max(1 - hOpen * 0.85, fadeT))
		end

		-- Ground marker: fade in, pulse on the first impacts, fade out.
		local mIn = clamp01(T / 0.3)
		local mOut = clamp01((T - DROP_AT - 0.4) / 0.4)
		marker:setTransparency(1 - mIn * 0.6 + mOut * 0.6 - pulse * 0.3)
		marker:setCFrame(CFrame.new(center + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, -T * 0.4, 0))

		-- Blades.
		for _, b in blades do
			local appear = clamp01((T - b.delay) / APPEAR_TIME)
			local dropStart = DROP_AT + b.delay
			local fadeOut = clamp01((T - FADE_AT - b.delay * 0.5) / FADE_TIME)
			if T < dropStart then
				local settle = 1 - (1 - appear) ^ 3
				placeBlade(b, HOVER_HEIGHT + (1 - settle) * 2.5, b.yaw + T * 0.8)
				setFade(b.bi, appear)
			else
				local u = clamp01((T - dropStart) / DROP_TIME)
				if not b.bi.trail.Enabled and not b.landed then
					b.bi.trail.Enabled = true
				end
				local height = HOVER_HEIGHT + (-EMBED - HOVER_HEIGHT) * u * u
				placeBlade(b, height - fadeOut * 0.8, b.yaw + dropStart * 0.8)
				setFade(b.bi, 1 - fadeOut)
				if u >= 1 and not b.landed then
					land(b)
				end
			end
		end
		return T >= LIFETIME
	end)
end

return BladeRain
