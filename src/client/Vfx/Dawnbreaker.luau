--!strict
-- Cột Sáng Bình Minh (dawnbreaker).
--
--   0 .. channel (1.2 s)  light streams from a 6-stud sphere into the sword,
--       a sigil spins up under the caster, a light swells, the edge brightens
--   release  0.1 s white flash (local caster), a vertical slash crescent, and
--       a wall of light (3 layered Beams plus a glowing volume) sweeps from the
--       caster to `length` in 0.25 s, scorching the floor along the way
--   strong shake, an impact at the far end, then everything fades in 0.6 s
--
-- The wall matches the server hit box: `length` x `width` x 12 along the aim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = require(Shared:WaitForChild("Config"):WaitForChild("Skills"))
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))
local Common = require(script.Parent.Common)
local Impact = require(script.Parent.Impact)

type FxEvent = Common.FxEvent

local Dawnbreaker = {}

local WALL_HEIGHT = 12
local SWEEP_TIME = 0.25
local HOLD_TIME = 0.15
local FADE_TIME = 0.6
local SCORCH_STEP = 4

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

function Dawnbreaker.play(event: FxEvent)
	local spec = event.spec
	local palette = VfxPalette.get(spec.element, spec.radiant)
	local channel = (spec :: any).channel or Skills.dawnbreaker.channel or 1.2
	local age0 = Common.age(event.serverTime)
	local total = channel + SWEEP_TIME + HOLD_TIME + FADE_TIME + 0.1
	local fx = Common.effect("Dawnbreaker", math.max(total - age0, 0.5))
	local caster = event.casterUserId
	local character = Common.characterOf(caster)
	local root = Common.rootOf(character)
	local sword = Common.swordOf(character)

	local dir = Common.aimDirection(event.origin, event.target, caster)
	local length = spec.length or spec.range
	local width = spec.width or 8
	local floor, _ = Common.ground(event.origin, 20)
	local wallFrame = CFrame.lookAt(floor, floor + dir)
	local endPoint = Common.ground(floor + dir * length, 20)

	---------------------------------------------------------------- channel

	local swordParts = Common.swordNeon(sword)
	fx:onFinish(function()
		for _, p in swordParts do
			if p.Parent then
				p.Color = Common.swordRestColor(sword, p)
			end
		end
	end)

	local gather = fx:part({ Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12) })
	local stream = fx:emitter(gather, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Rate = 0,
		Speed = NumberRange.new(8, 10),
		Lifetime = NumberRange.new(0.55, 0.65),
		Size = Common.seq({ { 0, 0.25 }, { 0.6, 0.8 }, { 1, 0.15 } }),
		Transparency = Common.seq({ { 0, 1 }, { 0.3, 0.35 }, { 1, 0 } }),
		Color = Common.colors(palette.glow, palette.core),
		Brightness = 2 * palette.brightness,
	}, "glow_soft")
	local streaks = fx:emitter(gather, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rate = 0,
		Speed = NumberRange.new(15, 18),
		Lifetime = NumberRange.new(0.32, 0.38),
		Size = Common.seq({ { 0, 0.15 }, { 0.5, 0.5 }, { 1, 0.1 } }),
		Transparency = Common.seq({ { 0, 1 }, { 0.25, 0.2 }, { 1, 0 } }),
		Color = ColorSequence.new(palette.core),
		RotSpeed = NumberRange.new(0),
		Rotation = NumberRange.new(0),
		Brightness = 2.5 * palette.brightness,
	}, "spark")
	local hum = fx:light(gather, { Color = palette.glow, Range = 8, Brightness = 0 })

	local feetSigil = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.12, 0)), 5, {
		rings = { 1, 0.74 },
		ringWidth = 0.22,
		star = 0.72,
		spokes = 6,
		color = palette.glow,
		runes = true,
		brightness = 2 * palette.brightness,
	})
	feetSigil:setScale(0.05)
	feetSigil:setTransparency(1)
	local rising = fx:emitter(feetSigil.part, {
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Rate = 0,
		Speed = NumberRange.new(3, 7),
		Lifetime = NumberRange.new(0.5, 0.9),
		Acceleration = Vector3.new(0, 4, 0),
		Size = Common.seq({ { 0, 0 }, { 0.25, 0.35 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0.2 }, { 1, 1 } }),
		Color = Common.colors(palette.core, palette.glow),
	}, "glow_star")

	local function gatherPoint(): Vector3
		if sword and sword.Parent then
			local core = sword:FindFirstChild("BladeCore", true)
			if core and core:IsA("BasePart") then
				return core.Position
			end
		end
		if root and root.Parent then
			return root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 1, 0)
		end
		return event.origin
	end

	---------------------------------------------------------------- release

	local released = false
	local arc: Common.Arc? = nil
	local beams: { Beam } = {}
	local beamWidths: { number } = {}
	local beamAlpha: { number } = {}
	local headPart: Part? = nil
	local volume: Part? = nil
	local embers: ParticleEmitter? = nil
	local headSparks: ParticleEmitter? = nil
	local headLight: PointLight? = nil
	local scorches: { { mark: Part, ember: Part } } = {}
	local nextScorch = SCORCH_STEP * 0.5
	local endImpact = false

	local function release()
		released = true
		if stream then
			stream.Enabled = false
		end
		if streaks then
			streaks.Enabled = false
		end
		if rising then
			rising.Enabled = false
		end
		Common.flash(Color3.new(1, 1, 1), 0.12, { strength = 0.7, casterUserId = caster })
		Common.shake(1.1, 0.45, event.origin, caster)
		Impact.shockwave(floor, 9, palette.glow, 0.45, { width = 0.6 })

		-- Vertical crescent in the plane of the aim (X = forward, Y = up).
		local arcFrame = CFrame.fromMatrix(floor + Vector3.new(0, 5, 0) + dir * 2.5, dir, Vector3.yAxis)
		arc = Common.arc(fx, arcFrame, 7, math.rad(115), math.rad(112), {
			segments = 5,
			width = 2.8,
			color = Common.colors(palette.core, palette.glow, palette.core),
			brightness = 3 * palette.brightness,
			texture = "slash_arc",
		})

		-- Wall of light: three camera-facing layers from the caster to a moving head.
		local tail = fx:attachment(nil, wallFrame * CFrame.new(0, WALL_HEIGHT / 2, -0.5))
		local hp = fx:part({ CFrame = wallFrame * CFrame.new(0, WALL_HEIGHT / 2, -1) })
		headPart = hp
		local h = fx:attachment(hp)

		local layers = {
			{ width = WALL_HEIGHT, alpha = 0.78, color = palette.glow, bright = 1.5 },
			{
				width = WALL_HEIGHT * 0.55,
				alpha = 0.42,
				color = palette.glow:Lerp(palette.core, 0.5),
				bright = 2.5,
			},
			{ width = WALL_HEIGHT * 0.18, alpha = 0.02, color = palette.core, bright = 4 },
		}
		for i, layer in layers do
			local b = fx:beam(tail, h, {
				Width0 = layer.width * 0.8,
				Width1 = layer.width,
				Color = ColorSequence.new(layer.color),
				Transparency = NumberSequence.new(layer.alpha),
				Brightness = layer.bright * palette.brightness,
				TextureMode = Enum.TextureMode.Wrap,
				TextureLength = 10,
				TextureSpeed = 1.5 + i,
				Segments = 1,
				ZOffset = i * 0.1,
			})
			table.insert(beams, b)
			beamWidths[i] = layer.width
			beamAlpha[i] = layer.alpha
		end

		volume = fx:part({
			Color = palette.glow,
			Transparency = 0.86,
			Size = Vector3.new(width * 0.9, WALL_HEIGHT, 0.2),
			CFrame = wallFrame * CFrame.new(0, WALL_HEIGHT / 2, 0),
		})

		headSparks = fx:emitter(h, {
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			SpreadAngle = Vector2.new(70, 70),
			Rate = 220,
			Speed = NumberRange.new(25, 45),
			Drag = 4,
			Acceleration = Vector3.new(0, -30, 0),
			Lifetime = NumberRange.new(0.25, 0.5),
			Size = Common.seq({ { 0, 0.6 }, { 1, 0 } }),
			Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
			Color = Common.colors(palette.core, palette.glow),
			RotSpeed = NumberRange.new(0),
			Rotation = NumberRange.new(0),
			Brightness = 2.5,
		}, "spark")
		headLight = fx:light(hp, { Color = palette.glow, Range = 30, Brightness = 6 * palette.brightness })

		local emberBox = fx:part({
			Size = Vector3.new(width * 0.8, 0.2, length),
			CFrame = wallFrame * CFrame.new(0, 0.3, -length / 2),
		})
		embers = fx:emitter(emberBox, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			EmissionDirection = Enum.NormalId.Top,
			Rate = 0,
			Speed = NumberRange.new(2, 6),
			Acceleration = Vector3.new(0, 5, 0),
			Lifetime = NumberRange.new(0.6, 1.1),
			Size = Common.seq({ { 0, 0.3 }, { 1, 0 } }),
			Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
			Color = Common.colors(palette.core, palette.glow, palette.accent),
			Brightness = 2,
		}, "glow_soft")
	end

	local function addScorch(distance: number)
		local pos = Common.ground(floor + dir * distance, 12)
		local size = width * (0.45 + 0.2 * math.sin(distance * 1.7))
		local flat = CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local mark = fx:part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, size, size),
			CFrame = flat,
			Color = Color3.fromRGB(28, 18, 14),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.35,
		})
		local ember = fx:part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, size * 0.6, size * 0.6),
			CFrame = flat * CFrame.new(0.01, 0, 0),
			Color = palette.glow,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
		})
		fx:tween(ember, Common.info(0.9, Enum.EasingStyle.Quad), { Transparency = 1, Color = palette.accent })
		table.insert(scorches, { mark = mark, ember = ember })
	end

	---------------------------------------------------------------- frame loop

	fx:onStep(function(_dt, elapsed)
		local T = elapsed + age0
		if T < channel then
			local charge = clamp01(T / channel)
			local p = gatherPoint()
			gather.CFrame = CFrame.new(p)
			if stream then
				stream.Rate = 25 + 110 * charge
			end
			if streaks then
				streaks.Rate = 10 + 70 * charge * charge
			end
			if rising then
				rising.Rate = 15 + 35 * charge
			end
			hum.Brightness = 6 * charge * charge * palette.brightness
			hum.Range = 8 + 10 * charge
			for _, part in swordParts do
				part.Color = Common.swordRestColor(sword, part):Lerp(palette.core, charge)
			end
			local feet = if root and root.Parent then root.Position else event.origin
			local open = clamp01(T / 0.3)
			feetSigil:setCFrame(
				CFrame.new(feet.X, floor.Y + 0.12, feet.Z)
					* CFrame.Angles(0, T * (1.5 + 6 * charge * charge), 0)
			)
			feetSigil:setScale((1 - (1 - open) ^ 3) * (1 + 0.1 * math.sin(T * 30) * charge))
			feetSigil:setTransparency(1 - 0.85 * open)
			return false
		end

		if not released then
			release()
		end
		local since = T - channel

		-- Channel remnants fade quickly.
		local post = clamp01(since / 0.3)
		feetSigil:setTransparency(0.15 + 0.85 * post)
		feetSigil:setScale(1 + 0.4 * post)
		hum.Brightness = 6 * (1 - post) * palette.brightness
		for _, part in swordParts do
			part.Color = palette.core:Lerp(Common.swordRestColor(sword, part), clamp01(since / 0.8))
		end

		-- Crescent: draws in 0.08 s, then widens and fades.
		local a = arc
		if a then
			local draw = clamp01(since / 0.08)
			local fromA = math.rad(115)
			local toA = math.rad(115 - 160 * (1 - (1 - draw) ^ 2))
			a:set(
				CFrame.fromMatrix(floor + Vector3.new(0, 5, 0) + dir * (2.5 + since * 6), dir, Vector3.yAxis),
				7 + since * 3,
				fromA,
				toA
			)
			local fadeA = clamp01((since - 0.08) / 0.3)
			a:setTransparency(fadeA ^ 1.2)
			a:setWidth(1 + 0.4 * fadeA)
		end

		-- Sweep the wall head out to `length`.
		local sweep = clamp01(since / SWEEP_TIME)
		local reach = math.max(length * (1 - (1 - sweep) ^ 4), 1)
		local hp = headPart
		if hp then
			hp.CFrame = wallFrame * CFrame.new(0, WALL_HEIGHT / 2, -reach)
		end
		local vol = volume
		if vol then
			vol.Size = Vector3.new(width * 0.9, WALL_HEIGHT, reach)
			vol.CFrame = wallFrame * CFrame.new(0, WALL_HEIGHT / 2, -reach / 2)
		end
		while nextScorch <= reach and nextScorch <= length do
			addScorch(nextScorch)
			nextScorch += SCORCH_STEP
		end
		if embers then
			embers.Rate = if since < SWEEP_TIME + HOLD_TIME + 0.2 then 160 else 0
		end
		if headSparks then
			headSparks.Enabled = sweep < 1
		end
		if sweep >= 1 and not endImpact then
			endImpact = true
			Impact.play(endPoint, palette, 1.5, spec.impactExplosion)
		end

		-- Fade: layers narrow into a line and vanish.
		local fade = clamp01((since - SWEEP_TIME - HOLD_TIME) / FADE_TIME)
		local flicker = if fade == 0 then 0.04 * math.sin(since * 60) else 0
		for i, b in beams do
			local w = beamWidths[i] * (1 - 0.65 * fade ^ 0.7)
			b.Width0 = w * 0.8
			b.Width1 = w
			b.Transparency =
				NumberSequence.new(math.clamp(beamAlpha[i] + flicker + (1 - beamAlpha[i]) * fade, 0, 1))
		end
		if vol then
			vol.Transparency = 0.86 + 0.14 * fade
		end
		local hl = headLight
		if hl then
			hl.Brightness = 6 * (1 - fade) * palette.brightness
		end
		for _, s in scorches do
			s.mark.Transparency = 0.35 + 0.65 * fade
		end
		return fade >= 1
	end)
	-- Keep the far-end flare tidy if the event arrived late.
	if age0 > channel + SWEEP_TIME then
		endImpact = true
	end
end

return Dawnbreaker
