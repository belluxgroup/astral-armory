--!strict
-- Shared VFX plumbing: effect lifetimes and budgets, pooling, camera shake,
-- screen flash, particle/beam/light factories, tween helpers, server-time
-- scheduling and Beam-built sigils (rings and runes that need no texture).
--
-- Every effect goes through `Common.effect(name, lifetime)`. The Effect owns
-- what it creates and destroys it at `lifetime`, with a Debris backstop at
-- `lifetime + 1` (spec 5.8). It also enforces the 40-emitter budget.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared:WaitForChild("Config"):WaitForChild("AssetIds"))
local Net = require(Shared:WaitForChild("Net"))
local SwordModel = require(Shared:WaitForChild("Models"):WaitForChild("SwordModel"))
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))

export type FxEvent = Net.FxEvent
export type SkillSpec = Net.SkillSpec
export type BossFx = Net.BossFx
export type Palette = VfxPalette.Palette
export type Props = { [string]: any }

local Common = {}

Common.MAX_EMITTERS = 40
Common.NEAR_RADIUS = 30
-- Events older than this (lag, late delivery) are skipped instead of replayed.
Common.MAX_EVENT_AGE = 1.5

local localPlayer = Players.LocalPlayer

---------------------------------------------------------------- small helpers

function Common.apply<T>(inst: T, props: Props?): T
	if props then
		for key, value in props do
			(inst :: any)[key] = value
		end
	end
	return inst
end

-- NumberSequence from a number, or from { {time, value, envelope?}, ... }.
function Common.seq(points: number | { { number } }): NumberSequence
	if type(points) == "number" then
		return NumberSequence.new(points)
	end
	local list = points :: { { number } }
	local kps = table.create(#list)
	for i, p in list do
		kps[i] = NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0)
	end
	return NumberSequence.new(kps)
end

-- ColorSequence from colors spaced evenly over 0..1.
function Common.colors(...: Color3): ColorSequence
	local list = { ... }
	if #list == 1 then
		return ColorSequence.new(list[1])
	end
	local kps = table.create(#list)
	for i, c in list do
		kps[i] = ColorSequenceKeypoint.new((i - 1) / (#list - 1), c)
	end
	return ColorSequence.new(kps)
end

function Common.info(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
end

-- Creates and plays a tween. `info` can be a TweenInfo or a duration in seconds.
function Common.tween(obj: Instance, info: TweenInfo | number, goal: Props): Tween
	local ti = if typeof(info) == "number" then Common.info(info) else info :: TweenInfo
	local tw = TweenService:Create(obj, ti, goal)
	tw:Play()
	return tw
end

function Common.cleanup(instance: Instance, seconds: number)
	Debris:AddItem(instance, seconds)
end

function Common.characterOf(userId: number): Model?
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.Character else nil
end

function Common.rootOf(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The sword welded to a character (built by Shared.Models.SwordModel).
function Common.swordOf(character: Model?): Model?
	if not character then
		return nil
	end
	local sword = character:FindFirstChild("AstralSword", true)
	return if sword and sword:IsA("Model") then sword else nil
end

-- Neon parts of a sword (edges, fuller, gem), the ones effects recolor. The
-- first time a part is seen its forged color is kept in the "VfxBase"
-- attribute so effects can always restore it.
function Common.swordNeon(sword: Model?): { BasePart }
	local list: { BasePart } = {}
	if sword then
		for _, d in sword:GetDescendants() do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
				if d:GetAttribute("VfxBase") == nil then
					d:SetAttribute("VfxBase", d.Color)
				end
				table.insert(list, d)
			end
		end
	end
	return list
end

Common.SWORD_RADIANT = Color3.fromRGB(255, 252, 240)

-- The resting color of one of a sword's Neon parts: white while Ascension is
-- active (the sword's "VfxRadiant" attribute), otherwise its forged color.
function Common.swordRestColor(sword: Model?, part: BasePart): Color3
	if sword and sword:GetAttribute("VfxRadiant") == true then
		return Common.SWORD_RADIANT
	end
	local base = part:GetAttribute("VfxBase")
	return if typeof(base) == "Color3" then base else SwordModel.EDGE_COLOR
end

-- Flat aim direction from an event, matching the server: origin -> target on
-- the XZ plane, else the caster's facing, else -Z.
function Common.aimDirection(origin: Vector3, target: Vector3, casterUserId: number?): Vector3
	local d = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	if d.Magnitude >= 1e-3 then
		return d.Unit
	end
	local root = if casterUserId then Common.rootOf(Common.characterOf(casterUserId)) else nil
	if root then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude >= 1e-3 then
			return flat.Unit
		end
	end
	return Vector3.new(0, 0, -1)
end

function Common.isLocalCaster(userId: number?): boolean
	return userId ~= nil and localPlayer ~= nil and userId == localPlayer.UserId
end

-- True when the local player is the caster, or their character is within
-- `radius` (default 30) of `position`. With neither given it is true: the
-- caller already decided.
function Common.isNear(position: Vector3?, casterUserId: number?, radius: number?): boolean
	if casterUserId == nil and position == nil then
		return true
	end
	if Common.isLocalCaster(casterUserId) then
		return true
	end
	if not position then
		return false
	end
	local root = Common.rootOf(localPlayer and localPlayer.Character)
	return root ~= nil and (root.Position - position).Magnitude <= (radius or Common.NEAR_RADIUS)
end

-- Seconds since the server fired an event (never negative).
function Common.age(serverTime: number): number
	return math.max(0, workspace:GetServerTimeNow() - serverTime)
end

-- Runs `fn` at serverTime + offset on the shared server clock, so late
-- clients land impacts at the same moment as everyone else. If that moment
-- has already passed, `fn` runs right away.
function Common.delayAt(serverTime: number, offset: number, fn: () -> ())
	local wait = serverTime + offset - workspace:GetServerTimeNow()
	if wait <= 0 then
		task.spawn(fn)
	else
		task.delay(wait, fn)
	end
end

-- A frame at `position` whose Y axis is `up` (for things lying on a surface).
function Common.upFrame(position: Vector3, up: Vector3): CFrame
	local u = up.Unit
	if u.Y > 0.999 then
		return CFrame.new(position)
	end
	local ref = if math.abs(u.Z) > 0.9 then Vector3.xAxis else Vector3.zAxis
	local right = ref:Cross(u).Unit
	return CFrame.fromMatrix(position, right, u)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

-- Snaps a point to the floor below it (arena or terrain). Returns the point
-- unchanged with an up normal when nothing is hit.
function Common.ground(position: Vector3, maxDrop: number?): (Vector3, Vector3)
	local arena = workspace:FindFirstChild("Arena")
	local include: { Instance } = { workspace.Terrain }
	if arena then
		table.insert(include, arena)
	end
	groundParams.FilterDescendantsInstances = include
	local drop = maxDrop or 60
	local hit =
		workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -(drop + 6), 0), groundParams)
	if hit then
		return hit.Position, hit.Normal
	end
	return position, Vector3.yAxis
end

---------------------------------------------------------------- root folder

local rootFolder: Folder? = nil

function Common.root(): Folder
	local existing = rootFolder
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientVfx"
	folder.Parent = workspace
	rootFolder = folder
	return folder
end

---------------------------------------------------------------- pooling

export type Pool<T> = {
	get: (self: Pool<T>) -> T,
	release: (self: Pool<T>, obj: T) -> (),
	free: { T },
	maxFree: number,
}

-- A pool of clones of `template`. `get()` reuses a released clone or makes a
-- new one. `release(obj)` unparents it (and runs `reset`, if given) so it can
-- be reused, or destroys it once `maxFree` (default 48) are already idle.
function Common.pool<T>(template: T, maxFree: number?, reset: ((T) -> ())?): Pool<T>
	local pool = {
		free = {} :: { T },
		maxFree = maxFree or 48,
	}
	function pool.get(self: Pool<T>): T
		local obj = table.remove(self.free)
		if obj ~= nil then
			return obj
		end
		return (template :: any):Clone() :: T
	end
	function pool.release(self: Pool<T>, obj: T)
		local inst = obj :: any
		if inst.Parent == nil and table.find(self.free, obj) then
			return
		end
		inst.Parent = nil
		if #self.free < self.maxFree then
			if reset then
				reset(obj)
			end
			table.insert(self.free, obj)
		else
			inst:Destroy()
		end
	end
	return (pool :: any) :: Pool<T>
end

---------------------------------------------------------------- effects

type StepFn = (dt: number, elapsed: number) -> boolean?

type EffectData = {
	name: string,
	folder: Folder,
	lifetime: number,
	started: number,
	dead: boolean,
	emitterCount: number,
	owned: { Instance },
	borrowed: { { pool: Pool<any>, obj: any } },
	connections: { RBXScriptConnection },
	steps: { StepFn },
	finalizers: { () -> () },
}

local Effect = {}
Effect.__index = Effect

export type Effect = typeof(setmetatable({} :: EffectData, Effect))

local active: { Effect } = {}
local stepConnection: RBXScriptConnection? = nil

local function stepAll(dt: number)
	local now = os.clock()
	for i = #active, 1, -1 do
		local fx = active[i]
		if fx.dead then
			table.remove(active, i)
		else
			local elapsed = now - fx.started
			local steps = fx.steps
			for j = #steps, 1, -1 do
				local ok, doneOrErr = pcall(steps[j], dt, elapsed)
				if not ok then
					warn(`[Vfx] {fx.name} step error: {doneOrErr}`)
					table.remove(steps, j)
				elseif doneOrErr == true then
					table.remove(steps, j)
				end
			end
		end
	end
	if #active == 0 and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

-- Seconds since the effect started.
function Effect.elapsed(self: Effect): number
	return os.clock() - self.started
end

-- Tracks an instance created outside the folder (Terrain attachments, effects
-- parented to characters) so it is destroyed with the effect.
function Effect.own<T>(self: Effect, inst: T): T
	local i = inst :: any
	table.insert(self.owned, i)
	Debris:AddItem(i, self.lifetime + 1 - self:elapsed())
	return inst
end

-- An anchored, non-colliding, non-queryable part in the effect folder.
-- Invisible (Transparency 1) unless `props` says otherwise.
function Effect.part(self: Effect, props: Props?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	Common.apply(p, props)
	p.Parent = self.folder
	return p
end

-- An attachment on `parent`, or a world attachment on Terrain when `parent`
-- is nil (cheaper than a holder part for static points).
function Effect.attachment(self: Effect, parent: BasePart?, cf: CFrame?): Attachment
	local a = Instance.new("Attachment")
	if parent then
		a.CFrame = cf or CFrame.identity
		a.Parent = parent
	else
		a.Parent = workspace.Terrain
		a.WorldCFrame = cf or CFrame.identity
		self:own(a)
	end
	return a
end

local EMITTER_DEFAULTS: Props = {
	LightEmission = 1,
	LightInfluence = 0,
	Lifetime = NumberRange.new(0.5, 0.8),
	Rate = 20,
	Speed = NumberRange.new(0),
	Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
	RotSpeed = NumberRange.new(-60, 60),
	Rotation = NumberRange.new(0, 360),
}

-- ParticleEmitter factory with sane defaults. Effects call `fx:emitter`, which
-- adds the per-effect budget check on top of this.
function Common.emitter(parent: Instance, props: Props?, texture: AssetIds.TextureName?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = AssetIds.tex(texture or "glow_soft")
	Common.apply(e, EMITTER_DEFAULTS)
	Common.apply(e, props)
	e.Parent = parent
	return e
end

-- Budgeted emitter: returns nil (and warns once) when this effect already has
-- MAX_EMITTERS emitters.
function Effect.emitter(
	self: Effect,
	parent: Instance,
	props: Props?,
	texture: AssetIds.TextureName?
): ParticleEmitter?
	if self.emitterCount >= Common.MAX_EMITTERS then
		if self.emitterCount == Common.MAX_EMITTERS then
			warn(`[Vfx] {self.name}: emitter budget ({Common.MAX_EMITTERS}) reached`)
			self.emitterCount += 1
		end
		return nil
	end
	self.emitterCount += 1
	-- Always owned: emitters on pooled or character parts must not outlive the effect.
	return self:own(Common.emitter(parent, props, texture))
end

-- A Beam between two attachments, parented to the effect folder.
function Effect.beam(
	self: Effect,
	a0: Attachment,
	a1: Attachment,
	props: Props?,
	texture: AssetIds.TextureName?
): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.LightEmission = 1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 10
	b.Texture = AssetIds.tex(texture or "beam_core")
	b.TextureMode = Enum.TextureMode.Stretch
	Common.apply(b, props)
	b.Parent = self.folder
	return b
end

function Effect.light(self: Effect, parent: Instance, props: Props?): PointLight
	local l = Instance.new("PointLight")
	l.Shadows = false
	l.Range = 12
	l.Brightness = 2
	Common.apply(l, props)
	l.Parent = parent
	return self:own(l)
end

function Effect.trail(
	self: Effect,
	a0: Attachment,
	a1: Attachment,
	props: Props?,
	texture: AssetIds.TextureName?
): Trail
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = false
	t.Lifetime = 0.3
	t.MinLength = 0.05
	t.Texture = AssetIds.tex(texture or "beam_core")
	t.TextureMode = Enum.TextureMode.Stretch
	Common.apply(t, props)
	t.Parent = if a0.Parent then a0.Parent else self.folder
	return self:own(t)
end

-- Borrows from a pool; the object is released back when the effect ends.
function Effect.borrow<T>(self: Effect, pool: Pool<T>): T
	local obj = pool:get()
	table.insert(self.borrowed, { pool = pool :: any, obj = obj })
	return obj
end

-- Returns a borrowed object early.
function Effect.giveBack<T>(self: Effect, pool: Pool<T>, obj: T)
	for i, entry in self.borrowed do
		if entry.obj == obj then
			table.remove(self.borrowed, i)
			pool:release(obj)
			return
		end
	end
end

function Effect.connect(self: Effect, signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	local c = signal:Connect(fn)
	table.insert(self.connections, c)
	return c
end

-- Calls fn(dt, elapsed) every frame until it returns true or the effect ends.
function Effect.onStep(self: Effect, fn: StepFn)
	table.insert(self.steps, fn)
	if not table.find(active, self) then
		table.insert(active, self)
	end
	if not stepConnection then
		stepConnection = RunService.RenderStepped:Connect(stepAll)
	end
end

-- Runs fn after `seconds`, unless the effect has ended by then.
function Effect.at(self: Effect, seconds: number, fn: () -> ())
	task.delay(seconds, function()
		if not self.dead then
			fn()
		end
	end)
end

-- Runs fn when the effect ends (before its instances are destroyed).
function Effect.onFinish(self: Effect, fn: () -> ())
	table.insert(self.finalizers, fn)
end

function Effect.tween(self: Effect, obj: Instance, info: TweenInfo | number, goal: Props): Tween?
	if self.dead or obj.Parent == nil then
		return nil
	end
	return Common.tween(obj, info, goal)
end

-- Ends the effect now: runs finalizers, returns pooled objects and destroys
-- everything it owns. Safe to call more than once.
function Effect.finish(self: Effect)
	if self.dead then
		return
	end
	self.dead = true
	for _, fn in self.finalizers do
		local ok, err = pcall(fn :: any)
		if not ok then
			warn(`[Vfx] {self.name} finalizer error: {err}`)
		end
	end
	for _, c in self.connections do
		c:Disconnect()
	end
	for _, entry in self.borrowed do
		entry.pool:release(entry.obj)
	end
	for _, inst in self.owned do
		inst:Destroy()
	end
	table.clear(self.borrowed)
	table.clear(self.owned)
	table.clear(self.steps)
	self.folder:Destroy()
end

-- Starts a new effect that finishes (and cleans up) after `lifetime` seconds.
function Common.effect(name: string, lifetime: number): Effect
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Common.root()
	local self = setmetatable(
		{
			name = name,
			folder = folder,
			lifetime = lifetime,
			started = os.clock(),
			dead = false,
			emitterCount = 0,
			owned = {},
			borrowed = {},
			connections = {},
			steps = {},
			finalizers = {},
		} :: EffectData,
		Effect
	)
	Debris:AddItem(folder, lifetime + 1)
	task.delay(lifetime, function()
		self:finish()
	end)
	return self
end

---------------------------------------------------------------- camera shake

type Shake = { amp: number, duration: number, started: number, seed: number }

local shakes: { Shake } = {}
local shakeBound = false
local SHAKE_BIND = "AstralVfxShake"

local function shakeStep()
	local camera = workspace.CurrentCamera
	local now = os.clock()
	local rx, ry, rz = 0, 0, 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local t = (now - s.started) / s.duration
		if t >= 1 then
			table.remove(shakes, i)
		else
			local falloff = (1 - t) * (1 - t)
			local a = s.amp * falloff
			local f = now * 22
			rx += math.noise(f, s.seed, 0) * a
			ry += math.noise(s.seed, f, 0) * a
			rz += math.noise(0, s.seed, f) * a * 0.6
		end
	end
	if camera then
		local deg = math.rad(1.6)
		camera.CFrame *= CFrame.Angles(rx * deg, ry * deg, rz * deg)
	end
	if #shakes == 0 then
		RunService:UnbindFromRenderStep(SHAKE_BIND)
		shakeBound = false
	end
end

-- Shakes the local camera. `intensity` ~0.3 is a tap, 1 is strong, 2 is huge.
-- Only applies when the local player is the caster or within 30 studs of
-- `position` (pass neither when the caller already checked).
function Common.shake(
	intensity: number,
	duration: number,
	position: Vector3?,
	casterUserId: number?,
	radius: number?
)
	if not Common.isNear(position, casterUserId, radius) then
		return
	end
	if #shakes >= 8 then
		table.remove(shakes, 1)
	end
	table.insert(
		shakes,
		{ amp = intensity, duration = duration, started = os.clock(), seed = math.random() * 100 }
	)
	if not shakeBound then
		shakeBound = true
		RunService:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value + 1, shakeStep)
	end
end

---------------------------------------------------------------- screen flash

local flashFrame: Frame? = nil

local function getFlashFrame(): Frame?
	local existing = flashFrame
	if existing and existing.Parent and existing.Parent.Parent then
		return existing
	end
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VfxFlash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	frame.Active = false
	frame.Parent = gui
	flashFrame = frame
	return frame
end

export type FlashOpts = {
	strength: number?, -- peak opacity 0..1 (default 0.55)
	attack: number?, -- fade-in time before the fade-out (default 0)
	position: Vector3?,
	casterUserId: number?,
	radius: number?, -- gate radius around `position` (default 30)
}

-- A fullscreen color flash that fades out over `duration`. Gated like shake.
function Common.flash(color: Color3, duration: number, opts: FlashOpts?)
	local o: FlashOpts = opts or {}
	if not Common.isNear(o.position, o.casterUserId, o.radius) then
		return
	end
	local frame = getFlashFrame()
	if not frame then
		return
	end
	local peak = 1 - (o.strength or 0.55)
	frame.BackgroundColor3 = color
	local attack = o.attack or 0
	if attack > 0 then
		local tw =
			Common.tween(frame, Common.info(attack, Enum.EasingStyle.Sine), { BackgroundTransparency = peak })
		tw.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				Common.tween(
					frame,
					Common.info(duration, Enum.EasingStyle.Quad),
					{ BackgroundTransparency = 1 }
				)
			end
		end)
	else
		frame.BackgroundTransparency = math.min(frame.BackgroundTransparency, peak)
		Common.tween(frame, Common.info(duration, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
	end
end

---------------------------------------------------------------- sigils

-- Bezier handle length for a quarter circle drawn by one Beam.
local KAPPA = 0.5523

type Line = { a0: Attachment, a1: Attachment, beam: Beam, p0: Vector3, p1: Vector3 }
type RingArc = { radius: number, attachments: { Attachment }, beams: { Beam } }

export type SigilOpts = {
	rings: { number }?, -- ring radii as fractions of the sigil radius (default { 1 })
	ringWidth: number?, -- studs at scale 1 (default 0.35)
	star: number?, -- hexagram radius fraction (omit for none)
	spokes: number?, -- spoke count from star tips to the outer ring
	lineWidth: number?, -- studs for star and spokes (default ringWidth * 0.6)
	color: Color3?,
	runes: boolean?, -- add the ring_runes image when its custom texture exists
	runeColor: Color3?,
	brightness: number?,
}

export type Sigil = {
	part: Part,
	radius: number,
	scale: number,
	setScale: (self: Sigil, scale: number) -> (),
	setTransparency: (self: Sigil, t: number) -> (),
	setCFrame: (self: Sigil, cf: CFrame) -> (),
	setColor: (self: Sigil, color: Color3) -> (),
}

-- A flat sigil centred at `cf` (lying in its XZ plane) drawn with Beams:
-- concentric rings, an optional hexagram and spokes, plus the ring_runes image
-- when uploaded. Looks right with no custom textures at all.
function Common.sigil(fx: Effect, cf: CFrame, radius: number, opts: SigilOpts?): Sigil
	local o: SigilOpts = opts or {}
	local color = o.color or Color3.new(1, 1, 1)
	local ringWidth = o.ringWidth or 0.35
	local lineWidth = o.lineWidth or ringWidth * 0.6
	local part = fx:part({ CFrame = cf, Size = Vector3.new(radius * 2, 0.05, radius * 2) })

	local arcs: { RingArc } = {}
	local lines: { Line } = {}
	local allBeams: { Beam } = {}
	local beamWidths: { [Beam]: number } = {}

	local function ringBeamProps(width: number): Props
		return {
			Color = ColorSequence.new(color),
			Width0 = width,
			Width1 = width,
			Segments = 12,
			Texture = "",
			Brightness = o.brightness or 2,
		}
	end

	local rings: { number } = o.rings or { 1 }
	for _, frac in rings do
		local r = radius * frac
		local atts: { Attachment } = {}
		for q = 0, 3 do
			atts[q + 1] = fx:attachment(part)
		end
		local beams: { Beam } = {}
		for q = 1, 4 do
			local b = fx:beam(atts[q], atts[q % 4 + 1], ringBeamProps(ringWidth))
			b.CurveSize0 = KAPPA * r
			b.CurveSize1 = KAPPA * r
			beams[q] = b
			table.insert(allBeams, b)
			beamWidths[b] = ringWidth
		end
		table.insert(arcs, { radius = r, attachments = atts, beams = beams })
	end

	local function addLine(p0: Vector3, p1: Vector3)
		local a0 = fx:attachment(part)
		local a1 = fx:attachment(part)
		local props = ringBeamProps(lineWidth)
		props.Segments = 1
		local b = fx:beam(a0, a1, props)
		table.insert(lines, { a0 = a0, a1 = a1, beam = b, p0 = p0, p1 = p1 })
		table.insert(allBeams, b)
		beamWidths[b] = lineWidth
	end

	if o.star then
		local sr = radius * o.star
		for k = 0, 1 do
			for j = 0, 2 do
				local a = j / 3 * math.pi * 2 + k * math.pi / 3
				local b2 = (j + 1) / 3 * math.pi * 2 + k * math.pi / 3
				addLine(
					Vector3.new(math.cos(a) * sr, 0, math.sin(a) * sr),
					Vector3.new(math.cos(b2) * sr, 0, math.sin(b2) * sr)
				)
			end
		end
		if o.spokes then
			for j = 0, o.spokes - 1 do
				local a = j / o.spokes * math.pi * 2
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				addLine(dir * sr, dir * radius * 0.97)
			end
		end
	end

	local runeImages: { ImageLabel } = {}
	if o.runes and AssetIds.has("ring_runes") then
		for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.LightInfluence = 0
			gui.Brightness = o.brightness or 2
			gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			gui.CanvasSize = Vector2.new(512, 512)
			gui.Parent = part
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			img.Image = AssetIds.tex("ring_runes")
			img.ImageColor3 = o.runeColor or color
			img.Parent = gui
			table.insert(runeImages, img)
		end
	end

	local sigil = {
		part = part,
		radius = radius,
		scale = 1,
	}

	function sigil.setScale(self: Sigil, scale: number)
		self.scale = scale
		local s = math.max(scale, 0.001)
		for _, arc in arcs do
			local r = arc.radius * s
			for q = 0, 3 do
				local th = q * math.pi / 2
				local pos = Vector3.new(math.cos(th) * r, 0, math.sin(th) * r)
				local tangent = Vector3.new(-math.sin(th), 0, math.cos(th))
				arc.attachments[q + 1].CFrame = CFrame.fromMatrix(pos, tangent, Vector3.yAxis)
			end
			for _, b in arc.beams do
				b.CurveSize0 = KAPPA * r
				b.CurveSize1 = KAPPA * r
			end
		end
		for _, line in lines do
			line.a0.Position = line.p0 * s
			line.a1.Position = line.p1 * s
		end
		for b, w in beamWidths do
			b.Width0 = w * s
			b.Width1 = w * s
		end
		part.Size = Vector3.new(radius * 2 * s, 0.05, radius * 2 * s)
	end

	function sigil.setTransparency(_self: Sigil, t: number)
		local ns = NumberSequence.new(math.clamp(t, 0, 1))
		for _, b in allBeams do
			b.Transparency = ns
		end
		for _, img in runeImages do
			img.ImageTransparency = math.clamp(t, 0, 1)
		end
	end

	function sigil.setCFrame(_self: Sigil, newCf: CFrame)
		part.CFrame = newCf
	end

	function sigil.setColor(_self: Sigil, c: Color3)
		local cs = ColorSequence.new(c)
		for _, b in allBeams do
			b.Color = cs
		end
		for _, img in runeImages do
			img.ImageColor3 = c
		end
	end

	local typed = (sigil :: any) :: Sigil
	typed:setScale(1)
	return typed
end

---------------------------------------------------------------- arcs

export type ArcOpts = {
	segments: number?, -- beams along the arc (default 4)
	width: number?, -- widest point in studs (default 1)
	taper: number?, -- crescent sharpness: width * sin(pi t) ^ taper (default 0.7)
	color: ColorSequence?,
	transparency: number?,
	brightness: number?,
	texture: string?, -- AssetIds texture name; "" for a solid ribbon
	faceCamera: boolean?,
}

export type Arc = {
	beams: { Beam },
	-- Re-lays the arc in `frame`'s XY plane from angle a0 to a1 (radians).
	set: (self: Arc, frame: CFrame, radius: number, a0: number, a1: number) -> (),
	setTransparency: (self: Arc, t: number) -> (),
	setWidth: (self: Arc, scale: number) -> (),
}

-- A crescent drawn with Beams along a circular arc, tapered at both ends.
-- The arc lies in `frame`'s XY plane (angle 0 = +X, pi/2 = +Y).
function Common.arc(fx: Effect, frame: CFrame, radius: number, a0: number, a1: number, opts: ArcOpts?): Arc
	local o: ArcOpts = opts or {}
	local n = o.segments or 4
	local maxWidth = o.width or 1
	local taper = o.taper or 0.7
	local atts: { Attachment } = {}
	for i = 0, n do
		atts[i + 1] = fx:attachment(nil, frame)
	end
	local beams: { Beam } = {}
	local widths: { number } = {}
	for i = 0, n do
		widths[i + 1] = maxWidth * math.sin(math.pi * i / n) ^ taper
	end
	local texture = o.texture
	for i = 1, n do
		local b = fx:beam(atts[i], atts[i + 1], {
			Color = o.color or ColorSequence.new(Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new(o.transparency or 0),
			Brightness = o.brightness or 2,
			FaceCamera = if o.faceCamera == nil then true else o.faceCamera,
			Segments = 8,
			Width0 = widths[i],
			Width1 = widths[i + 1],
		})
		if texture == "" then
			b.Texture = ""
		elseif texture ~= nil then
			b.Texture = AssetIds.tex(texture :: any)
		end
		beams[i] = b
	end
	local arc = { beams = beams }
	function arc.set(_self: Arc, f: CFrame, r: number, from: number, to: number)
		local step = (to - from) / n
		local handle = 4 / 3 * math.tan(math.abs(step) / 4) * r
		local sign = if step >= 0 then 1 else -1
		for i = 0, n do
			local th = from + step * i
			local pos = Vector3.new(math.cos(th) * r, math.sin(th) * r, 0)
			local tangent = Vector3.new(-math.sin(th), math.cos(th), 0) * sign
			local normal = -tangent:Cross(Vector3.zAxis)
			atts[i + 1].WorldCFrame = f * CFrame.fromMatrix(pos, tangent, normal)
		end
		for _, b in beams do
			b.CurveSize0 = handle
			b.CurveSize1 = handle
		end
	end
	function arc.setTransparency(_self: Arc, t: number)
		local ns = NumberSequence.new(math.clamp(t, 0, 1))
		for _, b in beams do
			b.Transparency = ns
		end
	end
	function arc.setWidth(_self: Arc, scale: number)
		for i, b in beams do
			b.Width0 = widths[i] * scale
			b.Width1 = widths[i + 1] * scale
		end
	end
	local typed = (arc :: any) :: Arc
	typed:set(frame, radius, a0, a1)
	return typed
end

return Common
