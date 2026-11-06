--!strict
-- Reusable hit effects: Impact.play (sparks, flare, glow, dust, ground ring,
-- short light, optional flipbook explosion) and Impact.shockwave (expanding
-- ring with a glowing floor disc).
--
-- Particle bursts come from persistent, disabled emitter rigs (one per palette
-- and scale) that are moved to the hit point and fired with :Emit(). A burst
-- of 20 blade impacts therefore costs 5 emitters, not 100, and stays inside
-- the 40-emitter budget (spec 5.8).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AssetIds"))
local Common = require(script.Parent.Common)

type Palette = Common.Palette

local Impact = {}

local MAX_LIGHTS = 6
local activeLights = 0

type Rig = {
	part: Part,
	sparks: ParticleEmitter,
	flare: ParticleEmitter,
	glow: ParticleEmitter,
	dust: ParticleEmitter,
	burst: ParticleEmitter,
}

local rigs: { [Palette]: { [number]: Rig } } = {}
local rigFolder: Folder? = nil

local function getRigFolder(): Folder
	local f = rigFolder
	if f and f.Parent then
		return f
	end
	local folder = Instance.new("Folder")
	folder.Name = "ImpactRigs"
	folder.Parent = Common.root()
	rigFolder = folder
	return folder
end

local function buildRig(palette: Palette, scale: number): Rig
	local part = Instance.new("Part")
	part.Name = "ImpactRig"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = getRigFolder()
	local att = Instance.new("Attachment")
	att.Parent = part

	local s = scale
	local b = palette.brightness
	local sparks = Common.emitter(att, {
		Enabled = false,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(75, 75),
		Speed = NumberRange.new(22 * s, 48 * s),
		Drag = 5,
		Acceleration = Vector3.new(0, -40 * s, 0),
		Lifetime = NumberRange.new(0.25, 0.55),
		Size = Common.seq({ { 0, 0.45 * s }, { 0.6, 0.3 * s }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Color = Common.colors(palette.core, palette.glow, palette.accent),
		RotSpeed = NumberRange.new(0),
		Rotation = NumberRange.new(0),
		Brightness = 2 * b,
		ZOffset = 0.5,
	}, "spark")
	local flare = Common.emitter(att, {
		Enabled = false,
		Lifetime = NumberRange.new(0.14, 0.2),
		Size = Common.seq({ { 0, 1.5 * s }, { 0.25, 7 * s }, { 1, 2 * s } }),
		Transparency = Common.seq({ { 0, 0 }, { 0.5, 0.35 }, { 1, 1 } }),
		Color = ColorSequence.new(palette.core),
		Brightness = 3 * b,
		ZOffset = 2,
	}, "glow_star")
	local glow = Common.emitter(att, {
		Enabled = false,
		Lifetime = NumberRange.new(0.3, 0.4),
		Size = Common.seq({ { 0, 3 * s }, { 1, 8 * s } }),
		Transparency = Common.seq({ { 0, 0.25 }, { 1, 1 } }),
		Color = Common.colors(palette.glow, palette.accent),
		Brightness = 1.5 * b,
		ZOffset = 1,
	}, "glow_soft")
	local dust = Common.emitter(att, {
		Enabled = false,
		LightEmission = 0.3,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(85, 85),
		Speed = NumberRange.new(4 * s, 9 * s),
		Drag = 3,
		Acceleration = Vector3.new(0, 2, 0),
		Lifetime = NumberRange.new(0.6, 1.0),
		Size = Common.seq({ { 0, 1.5 * s }, { 1, 4.5 * s } }),
		Transparency = Common.seq({ { 0, 0.55 }, { 0.3, 0.7 }, { 1, 1 } }),
		Color = Common.colors(palette.glow:Lerp(Color3.new(0.6, 0.55, 0.5), 0.6), Color3.fromRGB(70, 60, 70)),
		RotSpeed = NumberRange.new(-40, 40),
	}, "smoke_soft")
	local flipbook = AssetIds.has("explosion_flipbook_4x4")
	local burst = Common.emitter(att, {
		Enabled = false,
		Lifetime = NumberRange.new(0.55, 0.7),
		Size = Common.seq({ { 0, 5 * s }, { 1, 9 * s } }),
		Transparency = if flipbook
			then Common.seq({ { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } })
			else Common.seq({ { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }),
		Color = Common.colors(palette.core, palette.glow, palette.accent),
		Brightness = 2 * b,
		ZOffset = 1.5,
		FlipbookLayout = if flipbook
			then Enum.ParticleFlipbookLayout.Grid4x4
			else Enum.ParticleFlipbookLayout.None,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		RotSpeed = NumberRange.new(-20, 20),
	}, "explosion_flipbook_4x4")
	return { part = part, sparks = sparks, flare = flare, glow = glow, dust = dust, burst = burst }
end

local function rigFor(palette: Palette, scale: number): Rig
	local bucket = math.floor(scale * 10 + 0.5) / 10
	local byScale = rigs[palette]
	if not byScale then
		byScale = {}
		rigs[palette] = byScale
	end
	local rig = byScale[bucket]
	if rig and rig.part.Parent ~= nil then
		return rig
	end
	local fresh = buildRig(palette, bucket)
	byScale[bucket] = fresh
	return fresh
end

export type ImpactOpts = {
	ring: boolean?, -- ground ring (default true)
	light: boolean?, -- point light (default true, capped at 6 alive)
	dust: boolean?, -- dust puff (default true)
	normal: Vector3?, -- surface normal for the burst direction (default up)
}

-- One hit: a star flare, glow, sparks, dust, a ground ring and a short light.
-- `explosion` adds the fireball burst (wide_burst's impactExplosion).
function Impact.play(
	position: Vector3,
	palette: Palette,
	scale: number,
	explosion: boolean,
	opts: ImpactOpts?
)
	local o: ImpactOpts = opts or {}
	local s = math.max(scale, 0.1)
	local rig = rigFor(palette, s)
	local up = o.normal or Vector3.yAxis
	rig.part.CFrame = Common.upFrame(position, up)
	rig.flare:Emit(1)
	rig.glow:Emit(1)
	rig.sparks:Emit(math.floor(10 + 10 * s))
	if o.dust ~= false then
		rig.dust:Emit(math.floor(3 + 3 * s))
	end
	if explosion then
		rig.burst:Emit(2)
	end

	local wantRing = o.ring ~= false
	local wantLight = o.light ~= false and activeLights < MAX_LIGHTS
	if not wantRing and not wantLight then
		return
	end
	local life = if explosion then 0.7 else 0.5
	local fx = Common.effect("Impact", life)
	if wantRing then
		local ground = position + up * 0.15
		local cf = Common.upFrame(ground, up)
		local ringRadius = (if explosion then 6 else 3.2) * s
		local ring = Common.sigil(fx, cf, ringRadius, {
			color = palette.glow,
			ringWidth = 0.5 * s,
			brightness = 2 * palette.brightness,
		})
		ring:setScale(0.2)
		local dur = life * 0.9
		fx:onStep(function(_dt, elapsed)
			local t = math.min(elapsed / dur, 1)
			local e = 1 - (1 - t) ^ 3
			ring:setScale(0.2 + 0.8 * e)
			ring:setTransparency(0.05 + 0.95 * t * t)
			return t >= 1
		end)
	end
	if wantLight then
		activeLights += 1
		local holder = fx:part({ CFrame = CFrame.new(position + up * 1.5) })
		local light = fx:light(holder, {
			Color = palette.glow,
			Range = (if explosion then 18 else 10) * s + 4,
			Brightness = 4 * palette.brightness,
		})
		fx:tween(light, Common.info(life, Enum.EasingStyle.Quad), { Brightness = 0 })
		fx:onFinish(function()
			activeLights -= 1
		end)
	end
end

export type ShockwaveOpts = {
	width: number?, -- ring thickness in studs (default radius * 0.08)
	disc: boolean?, -- add the glowing floor disc (default true)
	discColor: Color3?,
	startScale: number?, -- starting fraction of the radius (default 0.05)
	brightness: number?,
	transparency: number?, -- starting transparency (default 0)
	normal: Vector3?, -- ring plane normal (default up: a ground ring)
}

-- An expanding ring (Quart Out) with an optional floor disc, fading out.
function Impact.shockwave(
	position: Vector3,
	radius: number,
	color: Color3,
	duration: number,
	opts: ShockwaveOpts?
)
	local o: ShockwaveOpts = opts or {}
	local fx = Common.effect("Shockwave", duration)
	local normal = o.normal or Vector3.yAxis
	local cf = Common.upFrame(position + normal * 0.2, normal)
	local width = o.width or math.max(radius * 0.08, 0.4)
	local startScale = o.startScale or 0.05
	local startT = o.transparency or 0
	local ring = Common.sigil(fx, cf, radius, {
		color = color,
		ringWidth = width,
		rings = { 1, 0.93 },
		brightness = o.brightness or 3,
	})
	ring:setScale(startScale)
	local disc: Part? = nil
	if o.disc ~= false then
		disc = fx:part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, radius * 2 * startScale, radius * 2 * startScale),
			CFrame = cf * CFrame.Angles(0, 0, math.pi / 2),
			Color = o.discColor or color,
			Material = Enum.Material.Neon,
			Transparency = 0.55 + startT * 0.45,
		})
	end
	fx:onStep(function(_dt, elapsed)
		local t = math.min(elapsed / (duration * 0.95), 1)
		local e = 1 - (1 - t) ^ 4
		local sc = startScale + (1 - startScale) * e
		ring:setScale(sc)
		ring:setTransparency(startT + (1 - startT) * t ^ 1.6)
		local d = disc
		if d then
			local dia = radius * 2 * sc * 0.97
			d.Size = Vector3.new(0.12, dia, dia)
			d.Transparency = 0.55 + 0.45 * math.min(t * 1.4, 1)
		end
		return t >= 1
	end)
end

-- A vertical pillar of light: three camera-facing Beam layers and a glowing
-- core column that snap open, hold, then narrow and fade over `duration`.
function Impact.pillar(position: Vector3, height: number, width: number, palette: Palette, duration: number)
	local fx = Common.effect("Pillar", duration)
	local base = fx:attachment(nil, CFrame.new(position))
	local top = fx:attachment(nil, CFrame.new(position + Vector3.new(0, height, 0)))
	local layers = {
		{ w = width, alpha = 0.72, color = palette.glow, bright = 1.5 },
		{ w = width * 0.5, alpha = 0.35, color = palette.glow:Lerp(palette.core, 0.5), bright = 2.5 },
		{ w = width * 0.16, alpha = 0, color = palette.core, bright = 4 },
	}
	local beams: { Beam } = {}
	for i, layer in layers do
		beams[i] = fx:beam(base, top, {
			Width0 = 0,
			Width1 = 0,
			Color = ColorSequence.new(layer.color),
			Transparency = Common.seq({ { 0, layer.alpha }, { 0.8, layer.alpha }, { 1, 1 } }),
			Brightness = layer.bright * palette.brightness,
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 12,
			TextureSpeed = -2 - i,
			Segments = 1,
			ZOffset = i * 0.1,
		})
	end
	local column = fx:part({
		Shape = Enum.PartType.Cylinder,
		Color = palette.core,
		Transparency = 0.5,
		Size = Vector3.new(height, 0.1, 0.1),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	})
	local holder = fx:part({ CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) })
	local light = fx:light(holder, { Color = palette.glow, Range = 40, Brightness = 8 * palette.brightness })
	fx:onStep(function(_dt, elapsed)
		local t = math.clamp(elapsed / duration, 0, 1)
		local open = math.clamp(elapsed / 0.08, 0, 1)
		local close = math.clamp((t - 0.45) / 0.55, 0, 1)
		local w = (1 - (1 - open) ^ 2) * (1 - close ^ 1.5)
		for i, b in beams do
			local lw = layers[i].w * w
			b.Width0 = lw * 1.15
			b.Width1 = lw * 0.6
		end
		local cw = math.max(width * 0.12 * w, 0.05)
		column.Size = Vector3.new(height, cw, cw)
		column.Transparency = 0.5 + 0.5 * close
		light.Brightness = 8 * palette.brightness * (1 - t)
		return t >= 1
	end)
end

return Impact
