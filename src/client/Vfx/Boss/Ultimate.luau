--!strict
-- The ultimate: a 2.5 s charge, then a spiral beam down a 70-stud cone.
--
-- ultimate_charge
--   blade      the longsword vanishes and a 3-segment cylindrical blade assembles in the
--              right hand, segment by segment; neighbouring segments counter-rotate,
--              spinning faster and glowing hotter as the charge builds
--   wind       a crimson and a gold helix of Beams coil around the boss and tighten, while
--              dust, debris and sparks are pulled inward and a rune circle spins underfoot
--   cone       the cone telegraph on the ground (filled wedge slices, glowing edges and a
--              front arc) fills from the boss out to its full length over `duration`
--   shake      camera shake that grows with the charge (within 60 studs)
-- ultimate_fire
--   beam       layered beam_core Beams open along the cone (white-gold core, gold body,
--              crimson rim), with three helix strands twisting around the axis and a train
--              of crimson-gold vortex rings racing out and widening with the cone
--   impact     a screen flash and a strong shake within 60 studs, a shockwave at the boss,
--              an explosion at the far end and scorch marks along the path
--   end        the blade bursts into sparks and the longsword returns; all gone within 2 s

local Common = require(script.Parent.Parent.Common)
local Impact = require(script.Parent.Parent.Impact)
local Kit = require(script.Parent.Kit)

type Effect = Common.Effect
type Sigil = Common.Sigil
type Arc = Common.Arc
type Payload = Kit.Payload

local Ultimate = {}

local SLICES = 8
local FIRE_TIME = 2.0
local BEAM_OPEN = 0.08
local BEAM_HOLD = 0.85
local BEAM_CLOSE = 0.5
local RING_COUNT = 12
local RING_TRAVEL = 0.6
local STRANDS = 3
local STRAND_SEGMENTS = 14
local WIND_SEGMENTS = 10
local KAPPA = 4 / 3

type Segment = {
	core: Part,
	band: Part,
	ridges: { Part },
	length: number,
	radius: number,
	y: number,
	angle: number,
}

type Blade = {
	fx: Effect,
	model: Model,
	segments: { Segment },
	tip: Part,
	hilt: Part,
	charge: number,
	firing: boolean,
}

local blades: { [Model]: Blade } = {}
local charges: { [Model]: Effect } = {}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function rotateFlat(v: Vector3, radians: number): Vector3
	local c, s = math.cos(radians), math.sin(radians)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

---------------------------------------------------------------- blade

local function endBlade(model: Model)
	local blade = blades[model]
	if blade then
		blades[model] = nil
		if not blade.fx.dead then
			blade.fx:finish()
		end
	end
end

local function buildBlade(model: Model, lifetime: number): Blade?
	local grip = Kit.grip(model)
	if not grip then
		return nil
	end
	endBlade(model)
	local k = Kit.scale(model)
	local fx = Common.effect("BossUltimateBlade", lifetime)
	Kit.hideSword(model, true)
	fx:onFinish(function()
		Kit.hideSword(model, false)
	end)
	local specs = {
		{ length = 1.7, radius = 0.34 },
		{ length = 1.6, radius = 0.28 },
		{ length = 1.5, radius = 0.22 },
	}
	local segments: { Segment } = {}
	local y = 0.5 * k
	for i, spec in specs do
		local length, radius = spec.length * k, spec.radius * k
		local core = fx:part({
			Shape = Enum.PartType.Cylinder,
			Color = if i == 2 then Kit.DEEP_GOLD else Kit.GOLD,
			Material = Enum.Material.Metal,
			Reflectance = 0.3,
			Transparency = 1,
			Size = Vector3.new(length, radius * 2, radius * 2),
		})
		local band = fx:part({
			Shape = Enum.PartType.Cylinder,
			Color = Kit.CRIMSON_HOT,
			Material = Enum.Material.Neon,
			Transparency = 1,
			Size = Vector3.new(0.1 * k, radius * 2.3, radius * 2.3),
		})
		local ridges: { Part } = {}
		for _ = 1, 2 do
			table.insert(
				ridges,
				fx:part({
					Color = Kit.GOLD,
					Material = Enum.Material.Neon,
					Transparency = 1,
					Size = Vector3.new(0.07 * k, length * 0.86, 0.07 * k),
				})
			)
		end
		table.insert(segments, {
			core = core,
			band = band,
			ridges = ridges,
			length = length,
			radius = radius,
			y = y + length / 2,
			angle = 0,
		})
		y += length + 0.08 * k
	end
	local tip = fx:part({
		Shape = Enum.PartType.Ball,
		Color = Kit.WHITE_GOLD,
		Material = Enum.Material.Neon,
		Transparency = 1,
		Size = Vector3.new(0.42, 0.42, 0.42) * k,
	})
	tip.CFrame = grip * CFrame.new(0, y, 0)
	local hilt = fx:part({
		Shape = Enum.PartType.Cylinder,
		Color = Kit.CRIMSON_DEEP,
		Material = Enum.Material.Fabric,
		Transparency = 0,
		Size = Vector3.new(1.0 * k, 0.3 * k, 0.3 * k),
	})
	local blade: Blade = {
		fx = fx,
		model = model,
		segments = segments,
		tip = tip,
		hilt = hilt,
		charge = 0,
		firing = false,
	}
	blades[model] = blade

	local light = fx:light(tip, { Color = Kit.GOLD, Range = 12, Brightness = 1 })
	local glow = fx:emitter(tip, {
		Rate = 0,
		Lifetime = NumberRange.new(0.25, 0.4),
		Size = Common.seq({ { 0, 2.5 * k }, { 1, 0.5 } }),
		Transparency = Common.seq({ { 0, 0.3 }, { 1, 1 } }),
		Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD, Kit.CRIMSON),
		Brightness = 3,
		LockedToPart = true,
	}, "glow_soft")
	local motes = fx:emitter(tip, {
		Rate = 0,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Speed = NumberRange.new(4, 7),
		Lifetime = NumberRange.new(0.3, 0.5),
		Size = Common.seq({ { 0, 0.3 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0.2 }, { 1, 1 } }),
		Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD),
		Brightness = 3,
	}, "glow_star")

	local appearAt = { 0.12, 0.27, 0.42 }
	local flared = { false, false, false }
	fx:onStep(function(dt, elapsed)
		local g = Kit.grip(model)
		if not g or not model.Parent then
			return false
		end
		local c = blade.charge
		local speed = if blade.firing then 34 else 2 + 16 * c * c
		local heat = if blade.firing then 1 else c
		for i, seg in segments do
			local appear = clamp01((elapsed - appearAt[i]) / 0.12)
			if appear > 0 and not flared[i] then
				flared[i] = true
				Impact.play(
					(g * CFrame.new(0, seg.y, 0)).Position,
					Kit.GOLD_PALETTE,
					0.4,
					false,
					{ ring = false, dust = false, light = false }
				)
			end
			seg.angle += (if i % 2 == 1 then 1 else -1) * speed * dt
			local s = 1 - (1 - appear) ^ 3
			local center = g * CFrame.new(0, seg.y, 0) * CFrame.Angles(0, seg.angle, 0)
			seg.core.Size = Vector3.new(seg.length * s, seg.radius * 2 * s, seg.radius * 2 * s)
			seg.core.CFrame = center * CFrame.Angles(0, 0, math.pi / 2)
			seg.core.Transparency = if appear > 0 then 0 else 1
			seg.band.CFrame = center * CFrame.new(0, seg.length / 2 * s, 0) * CFrame.Angles(0, 0, math.pi / 2)
			seg.band.Transparency = if appear > 0 then 0.05 else 1
			seg.band.Color = Kit.CRIMSON:Lerp(Kit.CRIMSON_HOT, heat)
			for r, ridge in seg.ridges do
				local side = if r == 1 then 1 else -1
				ridge.CFrame = center
					* CFrame.new(side * seg.radius * 0.96 * s, 0, 0)
					* CFrame.Angles(0, 0, side * 0.35)
				ridge.Transparency = if appear > 0 then 0.1 else 1
				ridge.Color = Kit.GOLD:Lerp(Kit.WHITE_GOLD, heat)
			end
		end
		local last = segments[#segments]
		tip.CFrame = g * CFrame.new(0, last.y + last.length / 2 + 0.1 * k, 0)
		tip.Transparency = if elapsed > appearAt[3] then 0.1 else 1
		hilt.CFrame = g * CFrame.Angles(0, 0, math.pi / 2)
		light.Brightness = 1 + 6 * heat
		light.Range = 12 + 16 * heat
		if glow then
			glow.Rate = if elapsed > appearAt[3] then 10 + 40 * heat else 0
		end
		if motes then
			motes.Rate = if blade.firing then 0 else 30 * c
		end
		return false
	end)
	return blade
end

-- The blade breaks up into sparks and the longsword comes back.
local function shatterBlade(model: Model)
	local blade = blades[model]
	if not blade then
		return
	end
	for _, seg in blade.segments do
		if seg.core.Parent then
			Impact.play(
				seg.core.Position,
				Kit.ROYAL_PALETTE,
				0.5,
				false,
				{ ring = false, dust = false, light = false }
			)
		end
	end
	endBlade(model)
end

---------------------------------------------------------------- charge

type Helix = { atts: { Attachment }, beams: { Beam } }

local function helix(fx: Effect, count: number, color: Color3, width: number, texture: string): Helix
	local atts: { Attachment } = {}
	for i = 1, count + 1 do
		atts[i] = fx:attachment(nil, CFrame.identity)
	end
	local beams: { Beam } = {}
	for i = 1, count do
		local b = fx:beam(atts[i], atts[i + 1], {
			Color = ColorSequence.new(color),
			Width0 = width,
			Width1 = width,
			Brightness = 2,
			LightEmission = 0.8,
			Segments = 8,
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 5,
			TextureSpeed = 2.5,
			Transparency = NumberSequence.new(1),
		}, texture :: any)
		beams[i] = b
	end
	return { atts = atts, beams = beams }
end

-- Lays a helix around `axis` (unit) from `base`: point j at distance d_j along the axis,
-- angle phase + j * step, radius from `radiusAt(d)`.
local function layHelix(
	h: Helix,
	base: Vector3,
	axis: Vector3,
	length: number,
	turns: number,
	phase: number,
	radiusAt: (number) -> number
)
	local n = #h.beams
	local side = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local u = axis:Cross(side).Unit
	local v = axis:Cross(u).Unit
	local step = turns * math.pi * 2 / n
	local handle = 0
	for j = 0, n do
		local d = length * j / n
		local th = phase + j * step
		local r = radiusAt(d)
		local radial = u * math.cos(th) + v * math.sin(th)
		local tangential = -u * math.sin(th) + v * math.cos(th)
		local pos = base + axis * d + radial * r
		local tangent = (tangential * (r * step) + axis * (length / n)).Unit
		h.atts[j + 1].WorldCFrame = CFrame.fromMatrix(pos, tangent, radial)
		handle = KAPPA * math.tan(step / 4) * r
		if j > 0 then
			local b = h.beams[j]
			b.CurveSize0 = handle
			b.CurveSize1 = handle
		end
	end
end

type Fan = { wedges: { WedgePart } }

local function fan(fx: Effect, color: Color3, transparency: number): Fan
	local wedges: { WedgePart } = {}
	for i = 1, SLICES * 2 do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.CanQuery = false
		w.CastShadow = false
		w.Material = Enum.Material.Neon
		w.Color = color
		w.Transparency = transparency
		w.Size = Vector3.new(0.05, 0.05, 0.05)
		w.Parent = fx.folder
		wedges[i] = w
	end
	return { wedges = wedges }
end

local function layFan(f: Fan, apex: Vector3, dir: Vector3, halfAngle: number, length: number)
	for i = 0, SLICES - 1 do
		local a0 = -halfAngle + 2 * halfAngle * i / SLICES
		local a1 = -halfAngle + 2 * halfAngle * (i + 1) / SLICES
		local p0 = apex + rotateFlat(dir, a0) * length
		local p1 = apex + rotateFlat(dir, a1) * length
		local ok = Kit.triangle(f.wedges[i * 2 + 1], f.wedges[i * 2 + 2], apex, p0, p1, 0.05)
		if not ok then
			f.wedges[i * 2 + 1].Size = Vector3.new(0.05, 0.05, 0.05)
			f.wedges[i * 2 + 2].Size = Vector3.new(0.05, 0.05, 0.05)
		end
	end
end

local function setFanTransparency(f: Fan, t: number)
	for _, w in f.wedges do
		w.Transparency = t
	end
end

function Ultimate.charge(evt: Payload)
	local model = Kit.model(evt)
	local origin = Kit.vec(evt, "origin") or (if model then model:GetPivot().Position else nil)
	if not origin then
		return
	end
	local dir = Kit.flatDir(Kit.vec(evt, "dir"))
	local duration = math.max(Kit.num(evt, "duration", Kit.Config.ultimate.charge), 0.2)
	local length = Kit.num(evt, "length", Kit.Config.ultimate.length)
	local halfAngle = math.rad(Kit.num(evt, "angle", Kit.Config.ultimate.angle))
	local k = Kit.scale(model)

	if model then
		local previous = charges[model]
		if previous and not previous.dead then
			previous:finish()
		end
	end
	local fx = Common.effect("BossUltimateCharge", duration + 0.6)
	if model then
		charges[model] = fx
		local blade = buildBlade(model, duration + FIRE_TIME + 1)
		fx:onStep(function(_dt, elapsed)
			if blade then
				blade.charge = clamp01(elapsed / duration)
			end
			return false
		end)
	end

	-- Cone telegraph.
	local floor = Common.ground(origin, 20)
	local apex = floor + dir * (1.5 * k) + Vector3.new(0, 0.12, 0)
	local base = fan(fx, Kit.CRIMSON_DEEP, 0.85)
	layFan(base, apex, dir, halfAngle, length)
	local fill = fan(fx, Kit.CRIMSON, 0.65)
	local fillApex = apex + Vector3.new(0, 0.04, 0)
	layFan(fill, fillApex, dir, halfAngle, 0.1)
	local apexAtt = fx:attachment(nil, CFrame.new(apex + Vector3.new(0, 0.1, 0)))
	local edges: { Beam } = {}
	for _, sign in { -1, 1 } do
		local far = fx:attachment(
			nil,
			CFrame.new(apex + rotateFlat(dir, sign * halfAngle) * length + Vector3.new(0, 0.1, 0))
		)
		table.insert(
			edges,
			fx:beam(apexAtt, far, {
				Color = ColorSequence.new(Kit.CRIMSON_HOT),
				Width0 = 0.35,
				Width1 = 0.9,
				Brightness = 3,
				Segments = 1,
				Texture = "",
				Transparency = Common.seq({ { 0, 0.2 }, { 1, 0.5 } }),
			})
		)
	end
	local ground = Kit.groundFrame(apex + Vector3.new(0, 0.1, 0), dir)
	local endArc: Arc = Common.arc(fx, ground, length, -halfAngle, halfAngle, {
		segments = 6,
		width = 0.9,
		taper = 0.05,
		color = ColorSequence.new(Kit.CRIMSON),
		brightness = 2,
		texture = "",
		transparency = 0.45,
	})
	local frontArc: Arc = Common.arc(fx, ground, 0.5, -halfAngle, halfAngle, {
		segments = 6,
		width = 1.4,
		taper = 0.1,
		color = Common.colors(Kit.CRIMSON_HOT, Kit.GOLD, Kit.CRIMSON_HOT),
		brightness = 4,
		texture = "",
	})

	-- Spiral wind around the boss.
	local strands = {
		helix(fx, WIND_SEGMENTS, Kit.CRIMSON, 0.9 * k, "smoke_soft"),
		helix(fx, WIND_SEGMENTS, Kit.GOLD, 0.7 * k, "smoke_soft"),
	}
	local rune = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.16, 0)), 5 * k, {
		rings = { 1, 0.8, 0.45 },
		ringWidth = 0.2,
		star = 0.8,
		spokes = 8,
		color = Kit.GOLD,
		runes = true,
		runeColor = Kit.CRIMSON_HOT,
		brightness = 2,
	})
	rune:setTransparency(1)
	local sphere = fx:part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(26, 26, 26),
		CFrame = CFrame.new(floor + Vector3.new(0, 3 * k, 0)),
	})
	local pulled: { ParticleEmitter } = {}
	local function inward(props: Common.Props, texture: string)
		local e = fx:emitter(sphere, props, texture :: any)
		if e then
			e.Shape = Enum.ParticleEmitterShape.Sphere
			e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			e.Rate = 0
			table.insert(pulled, e)
		end
	end
	inward({
		LightEmission = 0.15,
		LightInfluence = 0.6,
		Speed = NumberRange.new(10, 15),
		Lifetime = NumberRange.new(0.7, 1),
		Size = Common.seq({ { 0, 3 }, { 1, 1 } }),
		Transparency = Common.seq({ { 0, 1 }, { 0.3, 0.6 }, { 1, 1 } }),
		Color = Common.colors(Color3.fromRGB(190, 160, 130), Kit.CRIMSON_DEEP),
	}, "smoke_soft")
	inward({
		LightEmission = 0,
		LightInfluence = 1,
		Speed = NumberRange.new(12, 18),
		Lifetime = NumberRange.new(0.6, 0.8),
		Size = Common.seq({ { 0, 0.5 }, { 1, 0.3 } }),
		Transparency = Common.seq({ { 0, 0 }, { 0.9, 0 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(70, 58, 56)),
		RotSpeed = NumberRange.new(-300, 300),
	}, "smoke_soft")
	inward({
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Speed = NumberRange.new(16, 22),
		Lifetime = NumberRange.new(0.5, 0.7),
		Size = Common.seq({ { 0, 0.4 }, { 1, 0.1 } }),
		Transparency = Common.seq({ { 0, 0.1 }, { 1, 1 } }),
		Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD, Kit.CRIMSON_HOT),
		Brightness = 3,
		RotSpeed = NumberRange.new(0),
		Rotation = NumberRange.new(0),
	}, "spark")
	local rates = { 14, 10, 40 }

	local nextShake = 0
	local windPhase = 0
	fx:onStep(function(dt, elapsed)
		local c = clamp01(elapsed / duration)
		local eased = c * c * (3 - 2 * c)
		-- Cone: the fill and its front arc run out to the full length.
		local reach = math.max(length * eased, 0.1)
		layFan(fill, fillApex, dir, halfAngle, reach)
		local blink = 0.5 + 0.5 * math.sin(elapsed * (6 + 26 * c))
		setFanTransparency(fill, 0.72 - 0.22 * c - 0.08 * blink * c)
		frontArc:set(ground, reach, -halfAngle, halfAngle)
		frontArc:setWidth(1 + 0.5 * blink * c)
		endArc:setTransparency(0.55 - 0.3 * blink * c)
		for _, e in edges do
			e.Transparency = NumberSequence.new(0.5 - 0.35 * blink * c)
		end

		-- Wind: two strands coil in and speed up.
		local center = if model and model.Parent then model:GetPivot().Position else origin
		local feet = Vector3.new(center.X, floor.Y + 0.4, center.Z)
		windPhase += dt * (2.5 + 9 * c)
		local reachIn = 7.5 * k * (1 - 0.4 * eased)
		for s, strand in strands do
			layHelix(
				strand,
				feet,
				Vector3.yAxis,
				7 * k,
				2.2,
				windPhase + (s - 1) * math.pi,
				function(d: number): number
					return reachIn * (1 - 0.45 * d / (7 * k)) + 0.4 * math.sin(elapsed * 3 + d)
				end
			)
			local alpha = clamp01(elapsed / 0.4)
			for j, b in strand.beams do
				local fade = 0.85
					- 0.45 * alpha * (0.5 + 0.5 * c)
					+ 0.1 * math.abs(j - WIND_SEGMENTS / 2) / WIND_SEGMENTS
				b.Transparency = NumberSequence.new(math.clamp(fade, 0, 1))
			end
		end
		rune:setCFrame(
			CFrame.new(feet + Vector3.new(0, -0.24, 0)) * CFrame.Angles(0, elapsed * (0.6 + 3 * c), 0)
		)
		rune:setTransparency(0.7 - 0.5 * eased)
		sphere.CFrame = CFrame.new(feet + Vector3.new(0, 3 * k, 0))
		for i, e in pulled do
			e.Rate = rates[i] * (0.25 + 1.2 * c)
		end

		if elapsed >= nextShake then
			nextShake = elapsed + 0.3
			Common.shake(0.12 + 0.6 * eased, 0.42, origin, nil, Kit.BIG_RADIUS)
		end
		return false
	end)
	fx:onFinish(function()
		if model and rawequal(charges[model], fx) then
			charges[model] = nil
		end
	end)
end

---------------------------------------------------------------- fire

local function scorch(
	fx: Effect,
	floor: Vector3,
	dir: Vector3,
	length: number,
	halfAngle: number
): { { Part } }
	local marks: { { Part } } = {}
	local count = 9
	for i = 1, count do
		local d = 5 + (length - 8) * (i - 1) / (count - 1)
		local p = Common.ground(floor + dir * d + Vector3.new(0, 4, 0), 12)
		local width = math.max(math.tan(halfAngle) * d * 0.9, 3)
		local frame = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, math.pi / 2)
		local burnt = fx:part({
			Shape = Enum.PartType.Cylinder,
			Color = Kit.SCORCH,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 1,
			Size = Vector3.new(0.05, width, 7.5),
			CFrame = frame * CFrame.new(0.06, 0, 0),
		})
		local ember = fx:part({
			Shape = Enum.PartType.Cylinder,
			Color = Kit.CRIMSON_HOT,
			Material = Enum.Material.Neon,
			Transparency = 1,
			Size = Vector3.new(0.05, width * 0.8, 6),
			CFrame = frame * CFrame.new(0.08, 0, 0),
		})
		marks[i] = { burnt, ember }
	end
	return marks
end

function Ultimate.fire(evt: Payload)
	local model = Kit.model(evt)
	local origin = Kit.vec(evt, "origin") or (if model then model:GetPivot().Position else nil)
	if not origin then
		return
	end
	local dir = Kit.flatDir(Kit.vec(evt, "dir"))
	local length = Kit.num(evt, "length", Kit.Config.ultimate.length)
	local halfAngle = math.rad(Kit.num(evt, "angle", Kit.Config.ultimate.angle))
	local k = Kit.scale(model)

	if model then
		local charge = charges[model]
		if charge and not charge.dead then
			charge:finish()
		end
		local blade = blades[model]
		if blade then
			blade.firing = true
			blade.fx:at(BEAM_OPEN + BEAM_HOLD, function()
				shatterBlade(model)
			end)
		end
	end

	local fx = Common.effect("BossUltimateFire", FIRE_TIME)
	local floor = Common.ground(origin, 20)
	local start = origin + Vector3.new(0, 0.8 * k, 0) + dir * (2.6 * k)
	local finish = start + dir * length
	local spread = math.tan(halfAngle) * length

	Common.flash(
		Kit.WHITE_GOLD,
		0.6,
		{ strength = 0.6, attack = 0.04, position = origin, radius = Kit.BIG_RADIUS }
	)
	Common.shake(2.0, 0.9, origin, nil, Kit.BIG_RADIUS)
	Impact.shockwave(floor, 14, Kit.GOLD, 0.6, { width = 1.2, discColor = Kit.CRIMSON })
	Impact.play(start, Kit.ROYAL_PALETTE, 1.8, false, { ring = false, dust = false })

	-- Layered beams along the cone.
	local a0 = fx:attachment(nil, CFrame.lookAt(start, finish))
	local a1 = fx:attachment(nil, CFrame.lookAt(finish, finish + dir))
	local layers = {
		{ w0 = 2.2, w1 = 7, color = Kit.WHITE_GOLD, alpha = 0, bright = 6, speed = -6 },
		{ w0 = 5, w1 = spread * 1.2, color = Kit.GOLD, alpha = 0.25, bright = 3, speed = -4 },
		{ w0 = 8, w1 = spread * 2, color = Kit.CRIMSON, alpha = 0.55, bright = 2, speed = -2.5 },
	}
	local beams: { Beam } = {}
	for i, layer in layers do
		beams[i] = fx:beam(a0, a1, {
			Width0 = 0,
			Width1 = 0,
			Color = Common.colors(layer.color, layer.color:Lerp(Kit.CRIMSON, 0.3)),
			Transparency = Common.seq({ { 0, layer.alpha }, { 0.85, layer.alpha + 0.1 }, { 1, 1 } }),
			Brightness = layer.bright,
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 10,
			TextureSpeed = layer.speed,
			Segments = 1,
			ZOffset = (4 - i) * 0.1,
		})
	end
	-- Twisting strands and the vortex ring train.
	local twists: { Helix } = {}
	local twistColors = { Kit.GOLD, Kit.CRIMSON_HOT, Kit.WHITE_GOLD }
	for s = 1, STRANDS do
		twists[s] = helix(fx, STRAND_SEGMENTS, twistColors[s], 1.2, "beam_core")
	end
	local rings: { Sigil } = {}
	for i = 1, RING_COUNT do
		local ring = Common.sigil(fx, Common.upFrame(start, dir), 1, {
			rings = { 1, 0.9 },
			ringWidth = 0.09,
			color = if i % 2 == 0 then Kit.CRIMSON_HOT else Kit.GOLD,
			brightness = 3,
		})
		ring:setTransparency(1)
		rings[i] = ring
	end
	local marks = scorch(fx, floor, dir, length, halfAngle)
	local light =
		fx:light(fx:part({ CFrame = CFrame.new(start) }), { Color = Kit.GOLD, Range = 40, Brightness = 10 })

	-- Dust and sparks thrown along the path.
	local lane = fx:part({
		Size = Vector3.new(spread, 1, length),
		CFrame = CFrame.lookAt((start + finish) / 2, finish) - Vector3.new(0, start.Y - floor.Y - 0.5, 0),
	})
	local dust = fx:emitter(lane, {
		Enabled = false,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		LightEmission = 0.2,
		LightInfluence = 0.6,
		Speed = NumberRange.new(3, 8),
		Acceleration = Vector3.new(0, 4, 0),
		Lifetime = NumberRange.new(0.8, 1.2),
		Size = Common.seq({ { 0, 3 }, { 1, 8 } }),
		Transparency = Common.seq({ { 0, 0.5 }, { 1, 1 } }),
		Color = Common.colors(Color3.fromRGB(200, 170, 140), Color3.fromRGB(80, 60, 60)),
	}, "smoke_soft")
	local streaks = fx:emitter(lane, {
		Enabled = false,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Front,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		SpreadAngle = Vector2.new(12, 12),
		Speed = NumberRange.new(50, 80),
		Lifetime = NumberRange.new(0.25, 0.45),
		Size = Common.seq({ { 0, 0.6 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
		Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD, Kit.CRIMSON_HOT),
		Brightness = 4,
		RotSpeed = NumberRange.new(0),
		Rotation = NumberRange.new(0),
	}, "spark")
	if dust then
		dust:Emit(36)
	end
	if streaks then
		streaks:Emit(60)
	end
	fx:at(0.12, function()
		Impact.play(Common.ground(finish, 30), Kit.ROYAL_PALETTE, 2.6, true, {})
	end)

	local twistPhase = 0
	fx:onStep(function(dt, elapsed)
		local open = clamp01(elapsed / BEAM_OPEN)
		local close = clamp01((elapsed - BEAM_OPEN - BEAM_HOLD) / BEAM_CLOSE)
		local w = (1 + 0.15 * math.sin(math.pi * open)) * open * (1 - close ^ 1.5)
		local flicker = 1 + 0.06 * math.sin(elapsed * 47)
		for i, b in beams do
			b.Width0 = layers[i].w0 * w * flicker
			b.Width1 = layers[i].w1 * w * flicker
		end
		light.Brightness = 10 * (1 - close)

		twistPhase += dt * 14
		local front = length * clamp01(elapsed / 0.12)
		for s, strand in twists do
			layHelix(
				strand,
				start,
				dir,
				math.max(front, 0.5),
				3,
				twistPhase + (s - 1) * math.pi * 2 / STRANDS,
				function(d: number): number
					return (math.tan(halfAngle) * d * 0.7 + 0.8) * w
				end
			)
			for j, b in strand.beams do
				local d = j / STRAND_SEGMENTS
				b.Width0 = (0.6 + 3 * d) * w
				b.Width1 = (0.6 + 3 * (d + 1 / STRAND_SEGMENTS)) * w
				b.Transparency = NumberSequence.new(math.clamp(0.15 + 0.5 * d + close, 0, 1))
			end
		end

		for i, ring in rings do
			local launched = elapsed - (i - 1) * 0.07
			local u = clamp01(launched / RING_TRAVEL)
			if launched < 0 or u >= 1 then
				ring:setTransparency(1)
			else
				local e = 1 - (1 - u) ^ 2
				local d = length * e
				local r = math.tan(halfAngle) * d * 0.85 + 1.2
				ring:setCFrame(Common.upFrame(start + dir * d, dir) * CFrame.Angles(0, elapsed * 6 + i, 0))
				ring:setScale(r)
				ring:setTransparency(0.15 + 0.85 * u * u)
			end
		end

		for i, mark in marks do
			local appear = clamp01((elapsed - 0.12 * i / #marks) / 0.08)
			local cool = clamp01((elapsed - 0.25) / 0.9)
			local gone = clamp01((elapsed - 1.45) / 0.45)
			mark[1].Transparency = if appear > 0 then 0.15 + 0.85 * gone else 1
			mark[2].Transparency = if appear > 0 then math.max(0.3 + 0.7 * cool, gone) else 1
		end
		return elapsed >= FIRE_TIME - 0.05
	end)
end

-- The boss died or left mid-ultimate: drop the charge and the blade at once.
function Ultimate.stop(model: Model)
	local charge = charges[model]
	if charge and not charge.dead then
		charge:finish()
	end
	endBlade(model)
end

return Ultimate
