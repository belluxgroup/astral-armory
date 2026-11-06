--!strict
-- Giáo Huyết (crimson_lance).
--
--   0 .. 0.12 s  crimson glyph rings spiral around the caster's hand and the
--       lance materializes in them
--   throw  each lance (multishot fans them over spreadDeg, like the server)
--       flies along its lane with a double helix trail (two strands orbiting
--       the shaft), a soft wake ribbon, a red smoke wake and a tip glow; the
--       client lance catches up to the server's timeline so it reaches the end
--       at the same moment as the hits
--   end  at range (or the first wall, like the server's cast) a vertical
--       shockwave ring, a ground ring and Impact.play, then the lance fades
--   hits  DamagePopups that land on a lance's path get a small piercing burst
--
-- Element extras: storm adds zig-zag lightning arcs, frost sheds ice shards,
-- flame sheds embers. The element tints the helix; "none" stays crimson.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LanceModel = require(Shared:WaitForChild("Models"):WaitForChild("LanceModel"))
local Net = require(Shared:WaitForChild("Net"))
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))
local Common = require(script.Parent.Common)
local Impact = require(script.Parent.Impact)

type FxEvent = Common.FxEvent
type Palette = Common.Palette

local CrimsonLance = {}

local WINDUP = 0.12
local HELIX_RADIUS = LanceModel.TRAIL_RADIUS
local HELIX_SPEED = 26 -- radians per second
local STRAND_GAP = 0.14
local HIT_CORRELATE = 4.5

local CRIMSON: Palette = {
	core = VfxPalette.named.crimsonCore,
	glow = VfxPalette.named.crimson,
	accent = VfxPalette.named.crimsonDeep,
	brightness = 1.15,
}
local CRIMSON_RADIANT: Palette = {
	core = VfxPalette.named.radiantWhite,
	glow = VfxPalette.named.crimson:Lerp(VfxPalette.named.radiantGold, 0.3),
	accent = VfxPalette.named.crimsonDeep,
	brightness = 1.7,
}

type LanceInfo = { shaft: BasePart, parts: { BasePart }, a: Attachment, b: Attachment, tip: BasePart }

local info: { [Model]: LanceInfo } = setmetatable({}, { __mode = "k" }) :: any

local function infoFor(model: Model): LanceInfo
	local existing = info[model]
	if existing then
		return existing
	end
	local shaft = model.PrimaryPart :: BasePart
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local made: LanceInfo = {
		shaft = shaft,
		parts = parts,
		a = shaft:FindFirstChild("TrailA") :: Attachment,
		b = shaft:FindFirstChild("TrailB") :: Attachment,
		tip = model:FindFirstChild("Tip") :: BasePart,
	}
	info[model] = made
	return made
end

local function setFade(li: LanceInfo, alpha: number)
	for _, p in li.parts do
		p.LocalTransparencyModifier = 1 - alpha
	end
end

local function buildTemplate(): Model
	local model = LanceModel.build();
	(model.PrimaryPart :: BasePart).Anchored = true
	return model
end

local lancePool = Common.pool(buildTemplate(), 12, function(model: Model)
	local li = infoFor(model)
	setFade(li, 0)
	li.a.Position = Vector3.new(0, HELIX_RADIUS, 0)
	li.b.Position = Vector3.new(0, -HELIX_RADIUS, 0)
end)

local arenaParams = RaycastParams.new()
arenaParams.FilterType = Enum.RaycastFilterType.Include

-- How far a lane runs before the arena stops it (the server stops on world hits).
local function laneLength(from: Vector3, dir: Vector3, range: number): (number, Vector3?)
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		return range, nil
	end
	arenaParams.FilterDescendantsInstances = { arena }
	local hit = workspace:Raycast(from, dir * range, arenaParams)
	if hit then
		return (hit.Position - from).Magnitude, hit.Normal
	end
	return range, nil
end

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

type Bolt = { atts: { Attachment }, beams: { Beam } }

type Lane = {
	model: Model,
	li: LanceInfo,
	dir: Vector3,
	stop: number,
	normal: Vector3?,
	landed: boolean,
	landedAt: number,
	strands: { Trail },
	a2: Attachment,
	b2: Attachment,
	emitters: { ParticleEmitter },
	light: PointLight,
	bolts: { Bolt },
	nextBolt: number,
}

function CrimsonLance.play(event: FxEvent)
	local spec = event.spec
	local palette: Palette = if spec.element == "none"
		then (if spec.radiant then CRIMSON_RADIANT else CRIMSON)
		else VfxPalette.get(spec.element, spec.radiant)
	local helixMain = palette.glow
	local helixSecond = if spec.element == "none" then VfxPalette.named.crimsonCore else palette.core
	local age0 = Common.age(event.serverTime)
	local caster = event.casterUserId
	local speed = spec.speed or 120
	local range = spec.range
	local serverFlight = range / speed
	local visualFlight = math.max(serverFlight - WINDUP, 0.15)
	local lifetime = WINDUP + visualFlight + 0.9
	local fx = Common.effect("CrimsonLance", math.max(lifetime - age0, 0.5))

	local baseDir = Common.aimDirection(event.origin, event.target, caster)
	local start = event.origin + Vector3.new(0, 1.2, 0) + baseDir * 1.5
	local count = math.max(1, spec.count)
	local spread = spec.spreadDeg or 0

	---------------------------------------------------------------- windup glyphs

	local glyphs: { Common.Sigil } = {}
	for i, offset in { -2.6, 2.2 } do
		local g = Common.sigil(fx, Common.upFrame(start + baseDir * -offset, baseDir), 1.5, {
			rings = { 1, 0.62 },
			ringWidth = 0.16,
			star = 0.6,
			color = if i == 1 then palette.glow else palette.core,
			runes = true,
			brightness = 3,
		})
		g:setScale(0.05)
		g:setTransparency(1)
		table.insert(glyphs, g)
	end
	local gatherBall =
		fx:part({ Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(start) })
	local gatherSparks = fx:emitter(gatherBall, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rate = 0,
		Speed = NumberRange.new(18, 22),
		Lifetime = NumberRange.new(0.14, 0.16),
		Size = Common.seq({ { 0, 0.1 }, { 1, 0.45 } }),
		Transparency = Common.seq({ { 0, 0.6 }, { 1, 0 } }),
		Color = ColorSequence.new(palette.glow),
		RotSpeed = NumberRange.new(0),
		Rotation = NumberRange.new(0),
	}, "spark")
	if gatherSparks and age0 < WINDUP then
		gatherSparks:Emit(24)
	end

	---------------------------------------------------------------- lances

	local lanes: { Lane } = {}
	for i = 1, count do
		local angle = if count > 1 then -spread / 2 + spread * (i - 1) / (count - 1) else 0
		local dir = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(baseDir)
		local stop, normal = laneLength(start, dir, range)
		local model = fx:borrow(lancePool)
		local li = infoFor(model)
		li.tip.Color = palette.glow
		setFade(li, 0)
		model:PivotTo(CFrame.lookAt(start, start + dir))
		model.Parent = fx.folder

		-- Strand partners trail the orbiting attachments slightly, so each strand
		-- is a thin ribbon that draws one half of the double helix.
		local a2 = fx:own(Instance.new("Attachment"))
		a2.Parent = li.shaft
		local b2 = fx:own(Instance.new("Attachment"))
		b2.Parent = li.shaft
		local strandProps = {
			FaceCamera = true,
			Lifetime = 0.28,
			WidthScale = Common.seq({ { 0, 1 }, { 1, 0.3 } }),
			Transparency = Common.seq({ { 0, 0 }, { 0.6, 0.4 }, { 1, 1 } }),
			Brightness = 3 * palette.brightness,
		}
		local strandA =
			fx:trail(li.a, a2, Common.apply({ Color = Common.colors(helixSecond, helixMain) }, strandProps))
		local strandB =
			fx:trail(li.b, b2, Common.apply({ Color = Common.colors(helixSecond, helixMain) }, strandProps))
		local wake = fx:trail(li.a, li.b, {
			FaceCamera = false,
			Lifetime = 0.22,
			Color = Common.colors(helixMain, palette.accent),
			Transparency = Common.seq({ { 0, 0.55 }, { 1, 1 } }),
			Brightness = 1.5,
		})
		for _, t in { strandA, strandB, wake } do
			t.Enabled = false
		end

		local emitters: { ParticleEmitter } = {}
		local function add(e: ParticleEmitter?)
			if e then
				e.Enabled = false
				table.insert(emitters, e)
			end
		end
		local tipAtt = fx:own(Instance.new("Attachment"))
		tipAtt.Parent = li.tip
		add(fx:emitter(tipAtt, {
			Rate = 40,
			LockedToPart = true,
			Lifetime = NumberRange.new(0.12, 0.18),
			Size = Common.seq({ { 0, 2.6 }, { 1, 1.6 } }),
			Transparency = Common.seq({ { 0, 0.3 }, { 1, 1 } }),
			Color = ColorSequence.new(palette.glow),
			Brightness = 2 * palette.brightness,
			ZOffset = 0.5,
		}, "glow_soft"))
		local buttAtt = fx:own(Instance.new("Attachment"))
		buttAtt.Position = Vector3.new(-2.6, 0, 0)
		buttAtt.Parent = li.shaft
		add(fx:emitter(buttAtt, {
			Rate = 70,
			LightEmission = 0.35,
			Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180),
			Lifetime = NumberRange.new(0.4, 0.75),
			Size = Common.seq({ { 0, 0.7 }, { 1, 2.6 } }),
			Transparency = Common.seq({ { 0, 0.45 }, { 1, 1 } }),
			Color = Common.colors(palette.accent, Color3.fromRGB(40, 6, 14)),
			Drag = 2,
		}, "smoke_soft"))
		if spec.element == "frost" then
			add(fx:emitter(buttAtt, {
				Rate = 35,
				LightEmission = 0.6,
				Speed = NumberRange.new(2, 6),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -25, 0),
				Lifetime = NumberRange.new(0.4, 0.7),
				Size = Common.seq({ { 0, 0.55 }, { 1, 0.2 } }),
				Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
				Color = Common.colors(palette.core, palette.glow),
				RotSpeed = NumberRange.new(-200, 200),
			}, "spark"))
		elseif spec.element == "flame" then
			add(fx:emitter(buttAtt, {
				Rate = 80,
				Speed = NumberRange.new(1, 4),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 9, 0),
				Lifetime = NumberRange.new(0.35, 0.7),
				Size = Common.seq({ { 0, 0.4 }, { 1, 0 } }),
				Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
				Color = Common.colors(palette.core, palette.glow, palette.accent),
			}, "glow_soft"))
		end
		local light = fx:light(li.shaft, { Color = palette.glow, Range = 14, Brightness = 0 })

		local bolts: { Bolt } = {}
		if spec.element == "storm" then
			for _ = 1, 2 do
				local atts: { Attachment } = {}
				for k = 1, 5 do
					atts[k] = fx:attachment(nil, CFrame.new(start))
				end
				local beams: { Beam } = {}
				for k = 1, 4 do
					beams[k] = fx:beam(atts[k], atts[k + 1], {
						Texture = "",
						Segments = 1,
						Width0 = 0.22,
						Width1 = 0.22,
						Color = ColorSequence.new(palette.core),
						Brightness = 4,
						Transparency = NumberSequence.new(1),
					})
				end
				table.insert(bolts, { atts = atts, beams = beams })
			end
		end

		table.insert(lanes, {
			model = model,
			li = li,
			dir = dir,
			stop = stop,
			normal = normal,
			landed = false,
			landedAt = 0,
			strands = { strandA, strandB, wake },
			a2 = a2,
			b2 = b2,
			emitters = emitters,
			light = light,
			bolts = bolts,
			nextBolt = 0,
		})
	end

	---------------------------------------------------------------- hits

	local remotes = Net.client()
	local burstAt: { Vector3 } = {}
	fx:connect(remotes[Net.names.DamagePopup].OnClientEvent, function(popup: Net.DamagePopup)
		if type(popup) ~= "table" or typeof(popup.position) ~= "Vector3" then
			return
		end
		if popup.element ~= spec.element then
			return
		end
		local p = popup.position
		for _, lane in lanes do
			local head = lane.li.shaft.Position
			if distanceToSegment(p, start, head + lane.dir * 6) <= HIT_CORRELATE then
				for _, q in burstAt do
					if (q - p).Magnitude < 1 then
						return
					end
				end
				table.insert(burstAt, p)
				Impact.play(
					p,
					palette,
					0.5,
					false,
					{ ring = false, light = false, dust = false, normal = -lane.dir }
				)
				return
			end
		end
	end)

	---------------------------------------------------------------- landing

	local function land(lane: Lane, T: number)
		lane.landed = true
		lane.landedAt = T
		local tipPos = lane.li.tip.Position
		Impact.play(tipPos, palette, 1, spec.impactExplosion, { normal = lane.normal or -lane.dir })
		Impact.shockwave(tipPos, 6, palette.glow, 0.45, { normal = -lane.dir, width = 0.45, disc = false })
		local floorPos = Common.ground(tipPos, 12)
		Impact.shockwave(floorPos, 5, palette.accent, 0.5, { width = 0.35 })
		Common.shake(0.5, 0.25, tipPos, nil)
		for _, e in lane.emitters do
			e.Enabled = false
		end
		fx:at(0.25, function()
			for _, t in lane.strands do
				t.Enabled = false
			end
		end)
		for _, bolt in lane.bolts do
			for _, b in bolt.beams do
				b.Transparency = NumberSequence.new(1)
			end
		end
	end

	local function updateBolt(bolt: Bolt, lane: Lane, head: Vector3)
		local dir = lane.dir
		local side = dir:Cross(Vector3.yAxis)
		if side.Magnitude < 1e-3 then
			side = Vector3.xAxis
		end
		side = side.Unit
		local up = side:Cross(dir).Unit
		local back = 2 + math.random() * 5
		for k = 1, 5 do
			local t = (k - 1) / 4
			local jitter = if k == 1 or k == 5 then 0.15 else 0.9
			local offset = side * (math.random() - 0.5) * 2 * jitter + up * (math.random() - 0.5) * 2 * jitter
			bolt.atts[k].WorldPosition = head - dir * (1 + back * t) + offset
		end
		local alpha = NumberSequence.new(math.random() * 0.4)
		for _, b in bolt.beams do
			b.Transparency = alpha
		end
	end

	---------------------------------------------------------------- frame loop

	fx:onStep(function(_dt, elapsed)
		local T = elapsed + age0

		-- Windup glyphs: open fast, spin, then collapse into the throw.
		local open = math.clamp(T / WINDUP, 0, 1)
		local close = math.clamp((T - WINDUP) / 0.18, 0, 1)
		for i, g in glyphs do
			local offset = if i == 1 then -2.6 else 2.2
			local spinSign = if i == 1 then 1 else -1
			g:setCFrame(
				Common.upFrame(start + baseDir * -offset, baseDir) * CFrame.Angles(0, spinSign * T * 14, 0)
			)
			g:setScale((1 - (1 - open) ^ 2) * (1 - 0.7 * close) + 0.05)
			g:setTransparency(math.max(1 - open, close))
		end

		local allDone = true
		for _, lane in lanes do
			local li = lane.li
			local d: number
			if T < WINDUP then
				d = 0
				setFade(li, (T / WINDUP) ^ 0.5)
				lane.light.Brightness = 3 * T / WINDUP
			else
				for _, t in lane.strands do
					if not lane.landed and not t.Enabled then
						t.Enabled = true
					end
				end
				for _, e in lane.emitters do
					if not lane.landed and not e.Enabled then
						e.Enabled = true
					end
				end
				d = math.min(range * (T - WINDUP) / visualFlight, lane.stop)
				setFade(li, 1)
				lane.light.Brightness = 4 * palette.brightness
			end

			-- Embed a little into whatever stopped it, then fade out.
			if lane.landed then
				local f = math.clamp((T - lane.landedAt - 0.15) / 0.3, 0, 1)
				setFade(li, 1 - f)
				lane.light.Brightness = 4 * (1 - f) * palette.brightness
				d = lane.stop + 0.4 * math.min((T - lane.landedAt) / 0.05, 1)
			end

			local pos = start + lane.dir * d
			lane.model:PivotTo(CFrame.lookAt(pos, pos + lane.dir))

			-- Helix: the two strands orbit the shaft axis (shaft local X).
			local phi = T * HELIX_SPEED
			local c, s = math.cos(phi), math.sin(phi)
			local r = HELIX_RADIUS
			li.a.Position = Vector3.new(0, r * c, r * s)
			li.b.Position = Vector3.new(0, -r * c, -r * s)
			local c2, s2 = math.cos(phi - STRAND_GAP / r), math.sin(phi - STRAND_GAP / r)
			lane.a2.Position = Vector3.new(0, r * c2, r * s2)
			lane.b2.Position = Vector3.new(0, -r * c2, -r * s2)

			if #lane.bolts > 0 and not lane.landed and T >= WINDUP and T >= lane.nextBolt then
				lane.nextBolt = T + 0.05
				for _, bolt in lane.bolts do
					updateBolt(bolt, lane, li.tip.Position)
				end
			end

			if not lane.landed and T >= WINDUP and d >= lane.stop then
				land(lane, T)
			end
			if not lane.landed or T - lane.landedAt < 0.5 then
				allDone = false
			end
		end
		return allDone
	end)
end

return CrimsonLance
