--!strict
-- Portal salvos: the volley (3 portals behind the boss) and the armory (a fan of 10 or 16).
--
-- Weapon i lands on targets[i] at delay + (i - 1) * interval (BossFx contract). Per shot:
--   open      a vertical gold ripple disc (ring_runes sigil, a glow_soft disc, expanding
--             ripple rings) snaps open in 0.15 s, with a small spark flare
--   emerge    a part-built weapon (sword, spear or axe) slides out tip-first, trembling
--   launch    a short pull-back, then it fires at the target with a gold Trail
--   telegraph (armory) a thin ground line from the portal's ground projection to the
--             target fills over `telegraph`, with a ring where it will land
--   impact    sparks and a ground ring (Impact.play); the weapon sticks in the floor
--   dissolve  after 1 s the weapon breaks up into sparks
-- One effect (and one step function) runs the whole salvo. Weapons are pooled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AssetIds"))
local Common = require(script.Parent.Parent.Common)
local Impact = require(script.Parent.Parent.Impact)
local Kit = require(script.Parent.Kit)

type Effect = Common.Effect
type Sigil = Common.Sigil
type Payload = Kit.Payload

local Portal = {}

local OPEN_TIME = 0.15
local EMERGE = 0.45 -- fraction of the weapon length out of the portal before launch
local PULLBACK = 0.08
local PULLBACK_TIME = 0.07
local EMBED = 0.28 -- fraction of the weapon buried in the floor
local STICK_TIME = 1.0
local DISSOLVE_TIME = 0.35
local CLOSE_TIME = 0.22
local WEAPON_SCALE = 1.35

---------------------------------------------------------------- weapons

type Weapon = { model: Model, parts: { BasePart }, length: number }
type Kind = string -- "sword" | "spear" | "axe"

local function wpart(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size * WEAPON_SCALE
	p.CFrame = CFrame.new(cf.Position * WEAPON_SCALE) * cf.Rotation
	p.Color = color
	p.Material = material
	if material == Enum.Material.Metal then
		p.Reflectance = 0.25
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local DIAMOND = CFrame.Angles(0, math.rad(45), 0)
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder's X axis onto Z

-- Every weapon is laid out along Z with its tip at -length / 2, centred on "Core" at the
-- origin, so CFrame.lookAt(center, center + dir) points the tip along `dir`.
local function finish(model: Model, core: BasePart, length: number): Model
	model.PrimaryPart = core
	-- The model pivots on the weapon's middle (the origin), not on the Core part.
	core.PivotOffset = core.CFrame:Inverse()
	model:SetAttribute("Length", length * WEAPON_SCALE)
	local trailA = Instance.new("Attachment")
	trailA.Name = "TrailA"
	trailA.Position = Vector3.new(-0.22, 0, 0.2) * WEAPON_SCALE
	trailA.Parent = core
	local trailB = Instance.new("Attachment")
	trailB.Name = "TrailB"
	trailB.Position = Vector3.new(0.22, 0, 0.2) * WEAPON_SCALE
	trailB.Parent = core
	return model
end

local function buildSword(): Model
	local m = Instance.new("Model")
	m.Name = "PortalSword"
	local core = wpart(m, "Core", Vector3.new(0.34, 0.08, 2.9), CFrame.new(0, 0, -0.55), Kit.GOLD, METAL)
	wpart(m, "Edge", Vector3.new(0.48, 0.04, 2.85), CFrame.new(0, 0, -0.55), Kit.WHITE_GOLD, NEON)
	wpart(m, "Tip", Vector3.new(0.34, 0.08, 0.34), CFrame.new(0, 0, -2.0) * DIAMOND, Kit.GOLD, METAL)
	wpart(m, "TipEdge", Vector3.new(0.42, 0.04, 0.42), CFrame.new(0, 0, -2.0) * DIAMOND, Kit.WHITE_GOLD, NEON)
	wpart(m, "Guard", Vector3.new(1.3, 0.16, 0.3), CFrame.new(0, 0, 0.95), Kit.DEEP_GOLD, METAL)
	wpart(
		m,
		"Grip",
		Vector3.new(0.22, 0.22, 0.9),
		CFrame.new(0, 0, 1.5),
		Kit.CRIMSON_DEEP,
		Enum.Material.Fabric
	)
	wpart(
		m,
		"Pommel",
		Vector3.new(0.36, 0.36, 0.36),
		CFrame.new(0, 0, 2.05),
		Kit.GOLD,
		METAL,
		Enum.PartType.Ball
	)
	return finish(m, core, 4.6)
end

local function buildSpear(): Model
	local m = Instance.new("Model")
	m.Name = "PortalSpear"
	local core = wpart(
		m,
		"Core",
		Vector3.new(4.5, 0.2, 0.2),
		CFrame.new(0, 0, 0.65) * ALONG_Z,
		Kit.DEEP_GOLD,
		METAL,
		Enum.PartType.Cylinder
	)
	wpart(m, "Head", Vector3.new(0.8, 0.08, 0.8), CFrame.new(0, 0, -2.25) * DIAMOND, Kit.GOLD, METAL)
	wpart(
		m,
		"HeadEdge",
		Vector3.new(0.92, 0.04, 0.92),
		CFrame.new(0, 0, -2.25) * DIAMOND,
		Kit.WHITE_GOLD,
		NEON
	)
	wpart(
		m,
		"Collar",
		Vector3.new(0.2, 0.36, 0.36),
		CFrame.new(0, 0, -1.6) * ALONG_Z,
		Kit.CRIMSON,
		Enum.Material.Glass,
		Enum.PartType.Cylinder
	)
	wpart(m, "Butt", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0, 2.9), Kit.GOLD, METAL, Enum.PartType.Ball)
	return finish(m, core, 5.8)
end

local function buildAxe(): Model
	local m = Instance.new("Model")
	m.Name = "PortalAxe"
	local core = wpart(m, "Core", Vector3.new(0.24, 0.24, 3.8), CFrame.new(0, 0, 0.4), Kit.DEEP_GOLD, METAL)
	wpart(m, "Blade", Vector3.new(1.2, 0.1, 0.95), CFrame.new(0.56, 0, -1.15), Kit.GOLD, METAL)
	wpart(m, "BladeEdge", Vector3.new(0.12, 0.12, 1.15), CFrame.new(1.2, 0, -1.15), Kit.WHITE_GOLD, NEON)
	wpart(m, "BackSpike", Vector3.new(0.5, 0.1, 0.34), CFrame.new(-0.36, 0, -1.15), Kit.GOLD, METAL)
	wpart(
		m,
		"TopSpike",
		Vector3.new(0.18, 0.18, 0.5),
		CFrame.new(0, 0, -1.75) * CFrame.Angles(0, 0, math.rad(45)),
		Kit.WHITE_GOLD,
		NEON
	)
	wpart(
		m,
		"Pommel",
		Vector3.new(0.32, 0.32, 0.32),
		CFrame.new(0, 0, 2.3),
		Kit.CRIMSON,
		Enum.Material.Glass,
		Enum.PartType.Ball
	)
	return finish(m, core, 4.1)
end

local function resetWeapon(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
		end
	end
end

local pools: { [Kind]: Common.Pool<Model> } = {
	sword = Common.pool(buildSword(), 16, resetWeapon),
	spear = Common.pool(buildSpear(), 16, resetWeapon),
	axe = Common.pool(buildAxe(), 16, resetWeapon),
}
local KINDS: { Kind } = { "sword", "spear", "axe" }

local function borrowWeapon(fx: Effect): (Weapon, Kind)
	local kind = KINDS[math.random(1, #KINDS)]
	local model = fx:borrow(pools[kind])
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			table.insert(parts, d)
		end
	end
	local length = model:GetAttribute("Length")
	return { model = model, parts = parts, length = if type(length) == "number" then length else 5 }, kind
end

local function setVisible(w: Weapon, alpha: number)
	local ltm = 1 - math.clamp(alpha, 0, 1)
	for _, p in w.parts do
		p.LocalTransparencyModifier = ltm
	end
end

---------------------------------------------------------------- one shot

type Shot = {
	index: number,
	portal: Vector3,
	target: Vector3,
	dir: Vector3,
	openAt: number,
	launchAt: number,
	landAt: number,
	disc: Part,
	sigil: Sigil,
	ripples: { Sigil },
	discSize: number,
	weapon: Weapon,
	kind: Kind,
	trail: Trail,
	flared: boolean,
	landed: boolean,
	dissolved: boolean,
	released: boolean,
	line: { base: Part, fill: Part, ring: Sigil, from: Vector3, start: number }?,
}

local function backOut(t: number): number
	local c = 1.9
	local u = t - 1
	return 1 + (c + 1) * u * u * u + c * u * u
end

local function buildPortal(fx: Effect, shot: Shot, radius: number, rippleCount: number)
	local n = shot.dir
	local discCf = CFrame.lookAt(shot.portal, shot.portal + n) * ALONG_Z
	local disc = fx:part({
		Shape = Enum.PartType.Cylinder,
		Color = Kit.GOLD,
		Material = Enum.Material.Neon,
		Transparency = 1,
		Size = Vector3.new(0.05, 0.1, 0.1),
		CFrame = discCf,
	})
	if AssetIds.has("glow_soft") then
		for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.LightInfluence = 0
			gui.Brightness = 3
			gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			gui.CanvasSize = Vector2.new(256, 256)
			gui.Parent = disc
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(1.6, 1.6)
			img.Image = AssetIds.tex("glow_soft")
			img.ImageColor3 = Kit.WHITE_GOLD
			img.Parent = gui
		end
	end
	shot.disc = disc
	shot.discSize = radius * 1.7
	local frame = Common.upFrame(shot.portal, n)
	shot.sigil = Common.sigil(fx, frame, radius, {
		rings = { 1, 0.82 },
		ringWidth = 0.16,
		color = Kit.GOLD,
		runes = true,
		runeColor = Kit.WHITE_GOLD,
		brightness = 3,
	})
	shot.sigil:setScale(0.01)
	shot.sigil:setTransparency(1)
	shot.ripples = {}
	for _ = 1, rippleCount do
		local ripple =
			Common.sigil(fx, frame, radius, { ringWidth = 0.1, color = Kit.WHITE_GOLD, brightness = 2 })
		ripple:setTransparency(1)
		table.insert(shot.ripples, ripple)
	end
end

local function buildLine(fx: Effect, shot: Shot, telegraph: number, dmgRadius: number)
	local from = Common.ground(shot.portal, 40)
	local base = fx:part({ Color = Kit.CRIMSON, Material = Enum.Material.Neon, Transparency = 1 })
	local fill = fx:part({ Color = Kit.GOLD, Material = Enum.Material.Neon, Transparency = 1 })
	Kit.strip(base, from, shot.target, 0.3, 0.12)
	Kit.strip(fill, from, from, 0.18, 0.16)
	local ring = Common.sigil(fx, CFrame.new(shot.target + Vector3.new(0, 0.14, 0)), dmgRadius, {
		rings = { 1, 0.9 },
		ringWidth = 0.18,
		color = Kit.CRIMSON_HOT,
		brightness = 2.5,
	})
	ring:setTransparency(1)
	shot.line = { base = base, fill = fill, ring = ring, from = from, start = shot.landAt - telegraph }
end

---------------------------------------------------------------- salvo

type SalvoOpts = {
	name: string,
	telegraph: number?, -- armory line telegraph length
	portalRadius: number,
	ripples: number,
	impactScale: number,
	dmgRadius: number,
	stagger: number, -- seconds between portal openings
	shakeEvery: number,
	lightEvery: number,
}

local function salvo(evt: Payload, o: SalvoOpts)
	local portals = Kit.vecs(evt, "portals")
	local targets = Kit.vecs(evt, "targets")
	local count = math.min(#portals, #targets)
	if count == 0 then
		return
	end
	local delay = math.max(Kit.num(evt, "delay", 0.5), 0.1)
	local interval = math.max(Kit.num(evt, "interval", 0.12), 0)
	local flight = math.clamp(delay * 0.4, 0.1, 0.24)
	local lastLand = delay + (count - 1) * interval
	local fx = Common.effect(o.name, lastLand + STICK_TIME + DISSOLVE_TIME + 0.4)

	-- One spark emitter for every dissolve, moved onto each weapon as it breaks up.
	local dissolver = fx:part({ Size = Vector3.new(1, 1, 1) })
	local sparks = fx:emitter(dissolver, {
		Enabled = false,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(2, 7),
		Drag = 2,
		Acceleration = Vector3.new(0, 9, 0),
		Lifetime = NumberRange.new(0.45, 0.8),
		Size = Common.seq({ { 0, 0.35 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD, Kit.DEEP_GOLD),
		Brightness = 3,
		LightEmission = 1,
	}, "glow_star")

	local shots: { Shot } = {}
	for i = 1, count do
		local portal, target = portals[i], targets[i]
		local d = target - portal
		local dir = if d.Magnitude > 1e-3 then d.Unit else Vector3.new(0, -1, 0)
		local landAt = delay + (i - 1) * interval
		local launchAt = landAt - flight
		local shot = {
			index = i,
			portal = portal,
			target = target,
			dir = dir,
			openAt = math.clamp((i - 1) * o.stagger, 0, math.max(launchAt - OPEN_TIME - 0.1, 0)),
			launchAt = launchAt,
			landAt = landAt,
			flared = false,
			landed = false,
			dissolved = false,
			released = false,
		} :: Shot
		buildPortal(fx, shot, o.portalRadius, o.ripples)
		local weapon, kind = borrowWeapon(fx)
		weapon.model.Parent = fx.folder
		shot.weapon = weapon
		shot.kind = kind
		local core = weapon.model.PrimaryPart :: BasePart
		shot.trail = fx:trail(
			core:FindFirstChild("TrailA") :: Attachment,
			core:FindFirstChild("TrailB") :: Attachment,
			{
				FaceCamera = true,
				Lifetime = 0.2,
				Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD, Kit.CRIMSON),
				Transparency = Common.seq({ { 0, 0.05 }, { 1, 1 } }),
				WidthScale = Common.seq({ { 0, 1 }, { 1, 0.15 } }),
				Brightness = 3,
			}
		)
		shot.trail.Enabled = false
		if o.telegraph and o.telegraph > 0 then
			buildLine(fx, shot, o.telegraph, o.dmgRadius)
		end
		if i % o.lightEvery == 1 or o.lightEvery == 1 then
			fx:light(shot.disc, { Color = Kit.GOLD, Range = 9, Brightness = 0 })
		end
		table.insert(shots, shot)
	end

	local function tipCFrame(shot: Shot, tip: Vector3, wobble: number): CFrame
		local w = shot.weapon
		local center = tip - shot.dir * (w.length / 2)
		local cf = CFrame.lookAt(center, center + shot.dir)
		if wobble ~= 0 then
			cf *= CFrame.Angles(wobble, wobble * 0.7, 0)
		end
		return cf
	end

	fx:onStep(function(_dt, t)
		local alive = false
		for _, shot in shots do
			local w = shot.weapon
			-- Portal: open, ripple, close.
			local closeAt = shot.launchAt + 0.08
			local open = math.clamp((t - shot.openAt) / OPEN_TIME, 0, 1)
			local close = math.clamp((t - closeAt) / CLOSE_TIME, 0, 1)
			local scale = if open < 1 then backOut(open) else 1
			scale *= 1 - close * close
			local visible = t >= shot.openAt and close < 1
			if visible then
				local s = math.max(scale, 0.01)
				local spin = CFrame.Angles(0, t * 1.6 + shot.index, 0)
				shot.sigil:setCFrame(Common.upFrame(shot.portal, shot.dir) * spin)
				shot.sigil:setScale(s)
				shot.sigil:setTransparency(0.05 + 0.6 * close)
				local dia = shot.discSize * s
				shot.disc.Size = Vector3.new(0.05, dia, dia)
				shot.disc.Transparency = 0.45 + 0.1 * math.sin(t * 20 + shot.index) + 0.45 * close
				for k, ripple in shot.ripples do
					local phase = ((t - shot.openAt) / 0.5 + (k - 1) / #shot.ripples) % 1
					ripple:setScale(math.max(s * (0.6 + 0.9 * phase), 0.01))
					ripple:setTransparency(math.min(0.2 + 0.8 * phase + close, 1))
				end
				local light = shot.disc:FindFirstChildOfClass("PointLight")
				if light then
					light.Brightness = 3 * s
				end
				if not shot.flared then
					shot.flared = true
					Impact.play(shot.portal, Kit.GOLD_PALETTE, 0.35, false, {
						ring = false,
						dust = false,
						light = false,
						normal = shot.dir,
					})
				end
			else
				shot.sigil:setTransparency(1)
				shot.disc.Transparency = 1
				for _, ripple in shot.ripples do
					ripple:setTransparency(1)
				end
				local light = shot.disc:FindFirstChildOfClass("PointLight")
				if light then
					light.Brightness = 0
				end
			end

			-- Line telegraph.
			local line = shot.line
			if line then
				local f = (t - line.start) / math.max(shot.landAt - line.start, 0.01)
				if f >= 0 and not shot.landed then
					local fill = math.clamp(f, 0, 1)
					line.base.Transparency = 0.55 - 0.15 * fill
					line.fill.Transparency = 0.05
					Kit.strip(line.fill, line.from, line.from:Lerp(shot.target, fill), 0.18, 0.16)
					line.ring:setTransparency(0.5 - 0.4 * fill)
					line.ring:setScale(1.15 - 0.15 * fill)
				elseif shot.landed then
					local gone = math.clamp((t - shot.landAt) / 0.15, 0, 1)
					line.base.Transparency = 0.4 + 0.6 * gone
					line.fill.Transparency = 0.05 + 0.95 * gone
					line.ring:setTransparency(0.1 + 0.9 * gone)
				end
			end

			-- Weapon.
			local stuckEnd = shot.landAt + STICK_TIME
			if t < shot.launchAt then
				local emergeStart = shot.openAt + OPEN_TIME * 0.6
				local e = math.clamp(
					(t - emergeStart) / math.max(shot.launchAt - PULLBACK_TIME - emergeStart, 0.05),
					0,
					1
				)
				local eased = 1 - (1 - e) ^ 3
				local back = math.clamp((t - (shot.launchAt - PULLBACK_TIME)) / PULLBACK_TIME, 0, 1)
				local out = EMERGE * eased - PULLBACK * back
				local tremble = math.sin(t * 55 + shot.index * 2) * 0.012 * eased
				w.model:PivotTo(tipCFrame(shot, shot.portal + shot.dir * (out * w.length), tremble))
				setVisible(w, if t >= emergeStart then math.min((t - emergeStart) / 0.06, 1) else 0)
			elseif t < shot.landAt then
				shot.trail.Enabled = true
				local u = math.clamp((t - shot.launchAt) / (shot.landAt - shot.launchAt), 0, 1)
				local from = shot.portal + shot.dir * ((EMERGE - PULLBACK) * w.length)
				local to = shot.target + shot.dir * (EMBED * w.length)
				w.model:PivotTo(tipCFrame(shot, from:Lerp(to, u * u), 0))
				setVisible(w, 1)
			elseif not shot.landed then
				shot.landed = true
				w.model:PivotTo(tipCFrame(shot, shot.target + shot.dir * (EMBED * w.length), 0))
				Impact.play(shot.target, Kit.GOLD_PALETTE, o.impactScale, false, {})
				if shot.index % o.shakeEvery == 0 or shot.index == 1 then
					Common.shake(0.32, 0.18, shot.target, nil, Kit.SHAKE_RADIUS)
				end
				fx:at(0.1, function()
					shot.trail.Enabled = false
				end)
			elseif t < stuckEnd then
				-- A damped quiver as it settles in the floor.
				local s = t - shot.landAt
				local quiver = math.sin(s * 60) * 0.05 * math.exp(-s * 9)
				w.model:PivotTo(tipCFrame(shot, shot.target + shot.dir * (EMBED * w.length), quiver))
			elseif not shot.dissolved then
				shot.dissolved = true
				if sparks then
					dissolver.Size = Vector3.new(0.6, 0.6, w.length * (1 - EMBED))
					-- Over the part still above the floor (the tip end is buried).
					dissolver.CFrame = w.model:GetPivot() * CFrame.new(0, 0, w.length * EMBED / 2)
					sparks:Emit(16)
				end
			elseif not shot.released then
				local a = math.clamp((t - stuckEnd) / DISSOLVE_TIME, 0, 1)
				setVisible(w, 1 - a)
				w.model:PivotTo(
					tipCFrame(shot, shot.target + shot.dir * (EMBED * w.length) - shot.dir * (0.4 * a), 0)
				)
				if a >= 1 then
					shot.released = true
					fx:giveBack(pools[shot.kind], w.model)
				end
			end
			if not shot.released or visible then
				alive = true
			end
		end
		return not alive
	end)
end

---------------------------------------------------------------- events

-- volley: 3 portals behind the boss, weapons at one target.
function Portal.volley(evt: Payload)
	local cfg = Kit.Config.volley
	salvo(evt, {
		name = "BossVolley",
		portalRadius = 1.7,
		ripples = 2,
		impactScale = 0.7,
		dmgRadius = cfg.radius,
		stagger = 0.04,
		shakeEvery = 1,
		lightEvery = 1,
	})
end

-- armory: a fan of portals, weapons in sequence, each impact with a line telegraph.
function Portal.armory(evt: Payload)
	local cfg = Kit.Config.armory
	salvo(evt, {
		name = "BossArmory",
		telegraph = math.max(Kit.num(evt, "telegraph", cfg.telegraph), 0.05),
		portalRadius = 1.4,
		ripples = 1,
		impactScale = 0.85,
		dmgRadius = cfg.radius,
		stagger = 0.028,
		shakeEvery = 3,
		lightEvery = 4,
	})
end

return Portal
