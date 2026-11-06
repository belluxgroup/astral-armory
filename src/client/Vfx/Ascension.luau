--!strict
-- Thăng Hoa (ascension).
--
--   burst  a ground shockwave, a vertical light pillar for 0.8 s, a gold flash
--          and shake (caster or within 30 studs), and a fountain of sparks
--   aura   for `duration`, or until StateSync reports transformed = false:
--          white-gold flame wisps from 2 emitters per limb, a body flame, a
--          gold Highlight outline, floating sparks, a slow ring at the feet,
--          a warm light, and the sword's Neon turns white
--   end    the aura implodes inward and fades
--
-- `Ascension.setActive(character, active)` lets the UI drive the aura from
-- StateSync, so a late join or a missed SkillFx still shows the right state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))
local Common = require(script.Parent.Common)
local Impact = require(script.Parent.Impact)

type FxEvent = Common.FxEvent
type Palette = Common.Palette

local Ascension = {}

local PILLAR_TIME = 0.8
local IMPLODE_TIME = 0.45
-- An aura with no end time (radiant_mind) on another player's character is
-- capped here: only the owner receives StateSync to end it exactly.
local OPEN_ENDED_CAP = 60
local SETACTIVE_LIFETIME = 3600

local LIMBS = { "LeftHand", "RightHand", "LeftFoot", "RightFoot", "Head" }

type Aura = {
	fx: Common.Effect,
	character: Model,
	endAt: number,
	ending: boolean,
	emitters: { ParticleEmitter },
	highlight: Highlight,
	sword: Model?,
}

local auras: { [Model]: Aura } = {}

local function auraPalette(): Palette
	return VfxPalette.get("none", true)
end

local function setSwordRadiant(sword: Model?, on: boolean)
	if not sword or not sword.Parent then
		return
	end
	sword:SetAttribute("VfxRadiant", on)
	for _, part in Common.swordNeon(sword) do
		part.Color = Common.swordRestColor(sword, part)
	end
end

local function endAura(aura: Aura)
	if aura.ending then
		return
	end
	aura.ending = true
	local fx = aura.fx
	if auras[aura.character] == aura then
		auras[aura.character] = nil
	end
	for _, e in aura.emitters do
		e.Enabled = false
	end
	setSwordRadiant(aura.sword, false)
	if fx.dead then
		return
	end
	local palette = auraPalette()
	local root = Common.rootOf(aura.character)
	if root then
		-- Implosion: motes rush inward, a ring contracts, a small flash.
		local ball =
			fx:part({ Shape = Enum.PartType.Ball, Size = Vector3.new(10, 10, 10), CFrame = root.CFrame })
		local inward = fx:emitter(ball, {
			Enabled = false,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Speed = NumberRange.new(16, 20),
			Lifetime = NumberRange.new(0.25, 0.3),
			Size = Common.seq({ { 0, 0.2 }, { 1, 0.6 } }),
			Transparency = Common.seq({ { 0, 0.8 }, { 1, 0 } }),
			Color = ColorSequence.new(palette.core),
			RotSpeed = NumberRange.new(0),
			Rotation = NumberRange.new(0),
		}, "spark")
		if inward then
			inward:Emit(40)
		end
		local floor = Common.ground(root.Position, 10)
		local ring = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.15, 0)), 9, {
			rings = { 1 },
			ringWidth = 0.5,
			color = palette.glow,
			brightness = 3,
		})
		local startedAt = fx:elapsed()
		fx:onStep(function(_dt, elapsed)
			local t = math.clamp((elapsed - startedAt) / IMPLODE_TIME, 0, 1)
			ring:setScale(1 - 0.92 * (1 - (1 - t) ^ 2))
			ring:setTransparency(t ^ 2)
			return t >= 1
		end)
		fx:at(IMPLODE_TIME * 0.8, function()
			Impact.play(root.Position, palette, 0.7, false, { ring = false, dust = false })
		end)
	end
	fx:tween(aura.highlight, Common.info(IMPLODE_TIME), { OutlineTransparency = 1, FillTransparency = 1 })
	task.delay(IMPLODE_TIME + 0.3, function()
		fx:finish()
	end)
end

local function startAura(character: Model, endAt: number): Aura?
	local existing = auras[character]
	if existing then
		existing.endAt = math.max(existing.endAt, endAt)
		return existing
	end
	local root = Common.rootOf(character)
	if not root then
		return nil
	end
	local palette = auraPalette()
	local lifetime = if endAt == math.huge then SETACTIVE_LIFETIME else math.max(endAt - os.clock(), 0.5)
	local fx = Common.effect("AscensionAura", lifetime + IMPLODE_TIME + 0.5)
	local emitters: { ParticleEmitter } = {}
	local function add(e: ParticleEmitter?)
		if e then
			table.insert(emitters, e)
		end
	end

	-- Two flame layers per limb: bright wisps and softer licking tongues.
	for _, limbName in LIMBS do
		local limb = character:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			local att = fx:own(Instance.new("Attachment"))
			att.Parent = limb
			add(fx:emitter(att, {
				Rate = 26,
				Lifetime = NumberRange.new(0.45, 0.75),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(25, 25),
				Acceleration = Vector3.new(0, 9, 0),
				Drag = 1.5,
				Size = Common.seq({ { 0, 0.9 }, { 0.4, 0.75 }, { 1, 0 } }),
				Transparency = Common.seq({ { 0, 0.35 }, { 0.6, 0.55 }, { 1, 1 } }),
				Color = Common.colors(palette.core, VfxPalette.named.radiantGold, palette.accent),
				Brightness = 2,
				ZOffset = 0.3,
			}, "glow_soft"))
			add(fx:emitter(att, {
				Rate = 14,
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(2, 3.5),
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(20, 20),
				Acceleration = Vector3.new(0, 5, 0),
				Size = Common.seq({ { 0, 0.5 }, { 0.3, 1.2 }, { 1, 0.2 } }),
				Transparency = Common.seq({ { 0, 0.55 }, { 1, 1 } }),
				Color = Common.colors(VfxPalette.named.radiantGold, palette.glow),
				RotSpeed = NumberRange.new(-120, 120),
				Brightness = 1.5,
			}, "aura_flame"))
		end
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		add(fx:emitter(torso, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Rate = 36,
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(1, 2),
			Acceleration = Vector3.new(0, 12, 0),
			Size = Common.seq({ { 0, 2.4 }, { 1, 0.4 } }),
			Transparency = Common.seq({ { 0, 0.7 }, { 1, 1 } }),
			Color = Common.colors(VfxPalette.named.radiantGold, palette.glow),
			Brightness = 1.4,
		}, "glow_soft"))
		fx:light(torso, { Color = VfxPalette.named.radiantGold, Range = 14, Brightness = 2.5 })
	end

	-- Floating sparks in a loose sphere around the body.
	local sparkBall =
		fx:part({ Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), CFrame = root.CFrame })
	add(fx:emitter(sparkBall, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Rate = 14,
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(0.3, 1),
		Acceleration = Vector3.new(0, 2.5, 0),
		Size = Common.seq({ { 0, 0 }, { 0.3, 0.4 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
		Color = ColorSequence.new(palette.core),
		Brightness = 2.5,
	}, "glow_star"))

	local highlight = fx:own(Instance.new("Highlight"))
	highlight.FillColor = VfxPalette.named.radiantGold
	highlight.OutlineColor = VfxPalette.named.radiantGold
	highlight.FillTransparency = 0.88
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character

	local feet = Common.sigil(fx, CFrame.new(root.Position), 3.6, {
		rings = { 1, 0.82 },
		ringWidth = 0.18,
		star = 0.8,
		color = VfxPalette.named.radiantGold,
		runes = true,
		brightness = 2.5,
	})
	feet:setTransparency(0.35)

	local sword = Common.swordOf(character)
	setSwordRadiant(sword, true)

	local aura: Aura = {
		fx = fx,
		character = character,
		endAt = endAt,
		ending = false,
		emitters = emitters,
		highlight = highlight,
		sword = sword,
	}
	auras[character] = aura

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		fx:connect(humanoid.Died, function()
			endAura(aura)
		end)
	end
	fx:connect(character.AncestryChanged, function(_, parent)
		if parent == nil then
			endAura(aura)
		end
	end)
	fx:onFinish(function()
		if auras[character] == aura then
			auras[character] = nil
		end
		setSwordRadiant(sword, false)
	end)

	local hipDrop = root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 2)
	fx:onStep(function(_dt, elapsed)
		if aura.ending then
			return true
		end
		if os.clock() >= aura.endAt then
			endAura(aura)
			return true
		end
		if not root.Parent then
			return false
		end
		sparkBall.CFrame = root.CFrame
		local footY = root.Position.Y - hipDrop + 0.12
		feet:setCFrame(
			CFrame.new(root.Position.X, footY, root.Position.Z) * CFrame.Angles(0, elapsed * 0.8, 0)
		)
		feet:setScale(1 + 0.04 * math.sin(elapsed * 4))
		highlight.OutlineTransparency = 0.1 + 0.15 * (0.5 + 0.5 * math.sin(elapsed * 5))
		return false
	end)
	return aura
end

local function burst(event: FxEvent, root: BasePart?)
	local palette = auraPalette()
	local caster = event.casterUserId
	local center = if root then root.Position else event.origin
	local floor = Common.ground(center, 12)
	Impact.shockwave(floor, 18, VfxPalette.named.radiantGold, 0.75, { width = 1, transparency = 0.1 })
	Impact.pillar(floor, 70, 9, palette, PILLAR_TIME)
	Impact.play(center, palette, 1.4, false, { ring = false })
	Common.flash(
		VfxPalette.named.radiantGold,
		0.45,
		{ strength = 0.45, position = center, casterUserId = caster }
	)
	Common.shake(0.9, 0.45, center, caster)

	local fx = Common.effect("AscensionBurst", 1.2)
	local holder = fx:part({ CFrame = CFrame.new(floor) })
	local att = fx:attachment(holder)
	local fountain = fx:emitter(att, {
		Enabled = false,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(22, 22),
		Speed = NumberRange.new(35, 70),
		Drag = 2.5,
		Acceleration = Vector3.new(0, -10, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		Size = Common.seq({ { 0, 0.7 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
		Color = Common.colors(palette.core, VfxPalette.named.radiantGold),
		RotSpeed = NumberRange.new(0),
		Rotation = NumberRange.new(0),
		Brightness = 3,
	}, "spark")
	if fountain then
		fountain:Emit(70)
	end
end

function Ascension.play(event: FxEvent)
	local character = Common.characterOf(event.casterUserId)
	local root = Common.rootOf(character)
	if Common.age(event.serverTime) <= Common.MAX_EVENT_AGE then
		burst(event, root)
	end
	if not character then
		return
	end
	local duration = event.spec.duration or 20
	local remaining = duration - Common.age(event.serverTime)
	local endAt: number
	if Common.isLocalCaster(event.casterUserId) then
		-- The owner's StateSync is authoritative: the UI calls setActive(false).
		endAt = math.huge
	elseif duration == math.huge then
		-- Open ended (radiant_mind) on someone else: capped, they get no StateSync here.
		endAt = os.clock() + OPEN_ENDED_CAP
	else
		endAt = os.clock() + math.max(remaining, 0.5)
	end
	startAura(character, endAt)
end

-- Shows or hides the sustained aura on `character` (called by the UI from
-- StateSync.transformed). Idempotent.
function Ascension.setActive(character: Model, active: boolean)
	if active then
		local aura = auras[character]
		if aura then
			aura.endAt = math.huge
		else
			startAura(character, math.huge)
		end
	else
		local aura = auras[character]
		if aura then
			endAura(aura)
		end
	end
end

return Ascension
