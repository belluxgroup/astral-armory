--!strict
-- melee: the big diagonal cut.
--   windup   a star glint runs up the longsword and its Trail switches on just before the cut
--   cut      at `delay`, a gold crescent (the BasicSlash arc, x1.6) sweeps high right to low
--            left with a crimson echo, then widens and fades
--   impact   a ground crack (dark fissures with glowing gold cores) splits out in front of
--            the boss, with dust, debris, a shockwave ring and a shake for anyone within 30

local Common = require(script.Parent.Parent.Common)
local Impact = require(script.Parent.Parent.Impact)
local Kit = require(script.Parent.Kit)

type Payload = Kit.Payload

local Melee = {}

local SCALE = 1.6
-- BasicSlash combo hit 1 (degrees: 0 = forward, positive = left), scaled.
local ARC = { from = -75, to = 70, tilt = 28, radius = 5 * SCALE, width = 1.4 * SCALE }
local DRAW_TIME = 0.1
local FADE_TIME = 0.3
local CRACK_GROW = 0.1
local CRACK_GLOW = 0.9
local CRACK_HOLD = 1.3
local CRACK_FADE = 0.35
local FRONT = 6

type Crack = { base: Part, core: Part, a: Vector3, b: Vector3, delay: number }

local function cracks(fx: Common.Effect, center: Vector3, dir: Vector3): { Crack }
	local list: { Crack } = {}
	local left = Vector3.new(0, 1, 0):Cross(dir).Unit
	local count = 7
	for i = 1, count do
		local spread = (i - 1) / (count - 1) - 0.5
		local angle = spread * math.rad(150) + (math.random() - 0.5) * 0.25
		local heading = (dir * math.cos(angle) + left * math.sin(angle)).Unit
		local side = Vector3.new(0, 1, 0):Cross(heading)
		local length = 3.5 + math.random() * 3 * (1 - math.abs(spread))
		-- Two zigzag segments per fissure.
		local start = center + heading * 0.6
		local kink = start + heading * (length * 0.5) + side * ((math.random() - 0.5) * 1.4)
		local tip = kink + heading * (length * 0.5) + side * ((math.random() - 0.5) * 1.2)
		for seg, pts in { { start, kink }, { kink, tip } } do
			local base = fx:part({ Color = Kit.SCORCH, Material = Enum.Material.Slate, Transparency = 1 })
			local core = fx:part({ Color = Kit.GOLD, Material = Enum.Material.Neon, Transparency = 1 })
			table.insert(
				list,
				{ base = base, core = core, a = pts[1], b = pts[2], delay = (seg - 1) * CRACK_GROW * 0.6 }
			)
		end
	end
	return list
end

function Melee.play(evt: Payload)
	local model = Kit.model(evt)
	local origin = Kit.vec(evt, "origin") or (if model then model:GetPivot().Position else nil)
	if not origin then
		return
	end
	local dir = Kit.flatDir(Kit.vec(evt, "dir"))
	local delay = math.max(Kit.num(evt, "delay", 0.35), 0)
	local fx = Common.effect("BossMelee", delay + CRACK_HOLD + CRACK_FADE + 0.3)

	-- Windup: a glint along the blade, then the sword trail for the swing.
	local sword = Kit.sword(model)
	local core = sword and sword:FindFirstChild(Kit.NAMES.swordCore)
	local top = core and core:FindFirstChild("TrailTop")
	local bottom = core and core:FindFirstChild("TrailBottom")
	if top and bottom and top:IsA("Attachment") and bottom:IsA("Attachment") then
		local trail = fx:trail(top, bottom, {
			Lifetime = 0.22,
			Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD, Kit.CRIMSON),
			Transparency = Common.seq({ { 0, 0.05 }, { 0.6, 0.5 }, { 1, 1 } }),
			WidthScale = Common.seq({ { 0, 1 }, { 1, 0.3 } }),
			Brightness = 4,
		})
		trail.Enabled = false
		fx:at(math.max(delay - 0.1, 0), function()
			trail.Enabled = true
		end)
		fx:at(delay + 0.18, function()
			trail.Enabled = false
		end)
		fx:at(math.max(delay - 0.22, 0), function()
			if top.Parent then
				Impact.play(
					top.WorldPosition,
					Kit.GOLD_PALETTE,
					0.55,
					false,
					{ ring = false, dust = false, light = false }
				)
			end
		end)
	end

	-- The crescent, in a plane tilted around the aim.
	local center = origin + Vector3.new(0, 0.6 * SCALE, 0)
	local left = Vector3.new(0, 1, 0):Cross(dir).Unit
	local function frameAt(tilt: number): CFrame
		return CFrame.fromMatrix(center, dir, left) * CFrame.Angles(math.rad(tilt), 0, 0)
	end
	local from = math.rad(ARC.from)
	local main = Common.arc(fx, frameAt(ARC.tilt), ARC.radius, from, from, {
		segments = 7,
		width = ARC.width,
		taper = 0.6,
		color = Common.colors(Kit.GOLD, Kit.WHITE_GOLD, Kit.GOLD),
		brightness = 4.5,
		texture = "slash_arc",
	})
	local echo = Common.arc(fx, frameAt(ARC.tilt - 10), ARC.radius * 0.78, from, from, {
		segments = 6,
		width = ARC.width * 0.55,
		color = Common.colors(Kit.CRIMSON_HOT, Kit.CRIMSON),
		brightness = 3,
		texture = "slash_arc",
	})
	main:setTransparency(1)
	echo:setTransparency(1)

	local layers = {
		{ arc = main, lag = 0, scale = 1, tilt = ARC.tilt },
		{ arc = echo, lag = 0.035, scale = 0.78, tilt = ARC.tilt - 10 },
	}

	local floor = Common.ground(origin + dir * FRONT, 12)
	local fissures = cracks(fx, floor, dir)
	local struck = false

	fx:onStep(function(_dt, elapsed)
		local t = elapsed - delay
		if t < 0 then
			return false
		end
		-- Crescent sweep: draw, then widen and fade with the tail trimmed.
		for k, entry in layers do
			local u = t - entry.lag
			if u < 0 then
				continue
			end
			local draw = math.clamp(u / DRAW_TIME, 0, 1)
			local eased = 1 - (1 - draw) ^ 3
			local fade = math.clamp((u - DRAW_TIME) / FADE_TIME, 0, 1)
			local toA = ARC.from + (ARC.to - ARC.from) * eased
			local tailA = ARC.from + (ARC.to - ARC.from) * math.max(0, eased - 0.7) * fade
			entry.arc:set(
				frameAt(entry.tilt),
				ARC.radius * entry.scale * (1 + 0.15 * fade),
				math.rad(tailA),
				math.rad(toA)
			)
			entry.arc:setTransparency(fade ^ 1.3)
			entry.arc:setWidth(1 + 0.4 * fade * k)
		end
		if not struck and t >= DRAW_TIME * 0.6 then
			struck = true
			Impact.play(floor, Kit.ROYAL_PALETTE, 1.3, false, {})
			Impact.shockwave(floor, 7.5, Kit.GOLD, 0.45, { width = 0.6, discColor = Kit.DEEP_GOLD })
			Common.shake(0.75, 0.3, floor, nil, Kit.SHAKE_RADIUS)
			local holder = fx:part({ CFrame = CFrame.new(floor + Vector3.new(0, 0.4, 0)) })
			local dust = fx:emitter(holder, {
				Enabled = false,
				LightEmission = 0.1,
				LightInfluence = 0.7,
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(80, 80),
				Speed = NumberRange.new(8, 16),
				Drag = 4,
				Lifetime = NumberRange.new(0.7, 1.1),
				Size = Common.seq({ { 0, 2 }, { 1, 6 } }),
				Transparency = Common.seq({ { 0, 0.45 }, { 1, 1 } }),
				Color = Common.colors(Color3.fromRGB(196, 170, 140), Color3.fromRGB(90, 76, 66)),
			}, "smoke_soft")
			if dust then
				dust:Emit(18)
			end
			local debris = fx:emitter(holder, {
				Enabled = false,
				LightEmission = 0,
				LightInfluence = 1,
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(40, 40),
				Speed = NumberRange.new(16, 30),
				Acceleration = Vector3.new(0, -70, 0),
				Lifetime = NumberRange.new(0.5, 0.9),
				Size = Common.seq({ { 0, 0.5 }, { 1, 0.35 } }),
				Transparency = Common.seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
				Color = ColorSequence.new(Color3.fromRGB(64, 54, 52)),
				RotSpeed = NumberRange.new(-300, 300),
			}, "smoke_soft")
			if debris then
				debris:Emit(14)
			end
		end
		-- Ground crack: fissures race out, their gold cores cool, then the scars fade.
		local c = t - DRAW_TIME * 0.6
		if c >= 0 then
			local fadeOut = math.clamp((c - CRACK_HOLD) / CRACK_FADE, 0, 1)
			for _, crack in fissures do
				local grow = math.clamp((c - crack.delay) / CRACK_GROW, 0, 1)
				if grow <= 0 then
					continue
				end
				local tip = crack.a:Lerp(crack.b, 1 - (1 - grow) ^ 2)
				Kit.strip(crack.base, crack.a, tip, 0.42, 0.04)
				Kit.strip(crack.core, crack.a, tip, 0.13, 0.07)
				crack.base.Transparency = 0.1 + 0.9 * fadeOut
				crack.core.Transparency = math.max(math.clamp(c / CRACK_GLOW, 0, 1) ^ 1.5, fadeOut)
				crack.core.Color = Kit.WHITE_GOLD:Lerp(Kit.CRIMSON, math.clamp(c / CRACK_GLOW, 0, 1))
			end
			return fadeOut >= 1
		end
		return false
	end)
end

return Melee
