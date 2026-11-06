--!strict
-- Chém (basic, 3-hit combo).
--
--   swing  the local caster plays Config.Anims.slash (it replicates to
--          others); a Trail between the sword's TrailTop/TrailBottom draws the
--          arc for the swing window
--   flash  a crescent of Beams sweeps across the 8-stud strike zone in 0.09 s,
--          then widens and fades; hits 1 and 2 cut opposite diagonals
--   hit 3  the finisher: a wider, brighter, flat crescent with a second echo
--          arc, a ground ring, sparks and a small shake for the caster

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Anims = require(Shared:WaitForChild("Config"):WaitForChild("Anims"))
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))
local Common = require(script.Parent.Common)
local Impact = require(script.Parent.Impact)

type FxEvent = Common.FxEvent

local BasicSlash = {}

local SWING_WINDOW = 0.28
local DRAW_TIME = 0.09
local FADE_TIME = 0.22

local slashAnimation = Instance.new("Animation")
slashAnimation.AnimationId = Anims.slash
local tracks: { [Animator]: AnimationTrack } = setmetatable({}, { __mode = "k" }) :: any

local function playSwing(character: Model, heavy: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local track = tracks[animator]
	if not track then
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(slashAnimation)
		end)
		if not ok or not loaded then
			return
		end
		loaded.Priority = Enum.AnimationPriority.Action
		tracks[animator] = loaded
		track = loaded
	end
	track:Play(0.05, 1, if heavy then 1.15 else 1.5)
end

-- Arc layout per combo hit: start and end angles (degrees, 0 = forward,
-- positive = left), plane tilt around the aim axis, radius, width.
local HITS = {
	{ from = -75, to = 70, tilt = 28, radius = 5, width = 1.4 },
	{ from = 75, to = -70, tilt = -24, radius = 5, width = 1.4 },
	{ from = -120, to = 120, tilt = 4, radius = 6.5, width = 2.3 },
}

function BasicSlash.play(event: FxEvent)
	local spec = event.spec
	local palette = VfxPalette.get(spec.element, spec.radiant)
	local combo = math.clamp(event.combo or 1, 1, 3)
	local heavy = combo == 3
	local layout = HITS[combo]
	local caster = event.casterUserId
	local character = Common.characterOf(caster)
	local root = Common.rootOf(character)
	local sword = Common.swordOf(character)
	local fx = Common.effect("BasicSlash", SWING_WINDOW + DRAW_TIME + FADE_TIME + 0.2)

	local localPlayer = Players.LocalPlayer
	if character and localPlayer and caster == localPlayer.UserId then
		playSwing(character, heavy)
	end

	-- Sword trail for the swing window.
	if sword then
		local core = sword:FindFirstChild("BladeCore", true)
		local top = core and core:FindFirstChild("TrailTop")
		local bottom = core and core:FindFirstChild("TrailBottom")
		if top and bottom and top:IsA("Attachment") and bottom:IsA("Attachment") then
			local trail = fx:trail(top, bottom, {
				Lifetime = if heavy then 0.22 else 0.16,
				Color = Common.colors(palette.core, palette.glow),
				Transparency = Common.seq({ { 0, 0.05 }, { 0.5, 0.45 }, { 1, 1 } }),
				WidthScale = Common.seq({ { 0, 1 }, { 1, 0.4 } }),
				Brightness = (if heavy then 3 else 2) * palette.brightness,
			})
			fx:at(SWING_WINDOW, function()
				trail.Enabled = false
			end)
		end
	end

	-- Crescent flash in front of the caster, in a plane tilted per hit.
	local dir = Common.aimDirection(event.origin, event.target, caster)
	local center = event.origin + Vector3.new(0, 0.4, 0)
	local left = (-dir:Cross(Vector3.yAxis)).Unit
	local function frameAt(c: Vector3, tilt: number): CFrame
		return CFrame.fromMatrix(c, dir, left) * CFrame.Angles(math.rad(tilt), 0, 0)
	end
	local arcs: { { arc: Common.Arc, delay: number, scale: number } } = {}
	local main = Common.arc(
		fx,
		frameAt(center, layout.tilt),
		layout.radius,
		math.rad(layout.from),
		math.rad(layout.from),
		{
			segments = if heavy then 7 else 5,
			width = layout.width,
			taper = 0.6,
			color = Common.colors(palette.glow, palette.core, palette.glow),
			brightness = (if heavy then 4 else 2.5) * palette.brightness,
			texture = "slash_arc",
		}
	)
	table.insert(arcs, { arc = main, delay = 0, scale = 1 })
	if heavy then
		local echo = Common.arc(
			fx,
			frameAt(center, -6),
			layout.radius * 0.8,
			math.rad(layout.from),
			math.rad(layout.from),
			{
				segments = 6,
				width = layout.width * 0.6,
				color = Common.colors(palette.accent, palette.glow),
				brightness = 2 * palette.brightness,
				texture = "slash_arc",
			}
		)
		table.insert(arcs, { arc = echo, delay = 0.04, scale = 0.8 })
	end

	local impactDone = false
	fx:onStep(function(_dt, elapsed)
		-- Follow the caster during the swing so the flash stays on the blade.
		local c = if root and root.Parent then root.Position + Vector3.new(0, 0.4, 0) else center
		local allDone = true
		for _, entry in arcs do
			local t = elapsed - entry.delay
			if t < 0 then
				allDone = false
				entry.arc:setTransparency(1)
			else
				local draw = math.clamp(t / DRAW_TIME, 0, 1)
				local eased = 1 - (1 - draw) ^ 3
				local fade = math.clamp((t - DRAW_TIME) / FADE_TIME, 0, 1)
				local toA = layout.from + (layout.to - layout.from) * eased
				-- Keep the arc's tail trimmed so it reads as a moving cut, not a fan.
				local tailA = layout.from + (layout.to - layout.from) * math.max(0, eased - 0.75) * fade
				local tilt = if entry.scale < 1 then -6 else layout.tilt
				entry.arc:set(
					frameAt(c, tilt),
					layout.radius * entry.scale * (1 + 0.12 * fade),
					math.rad(tailA),
					math.rad(toA)
				)
				entry.arc:setTransparency(fade ^ 1.4)
				entry.arc:setWidth(1 + 0.35 * fade)
				if fade < 1 then
					allDone = false
				end
			end
		end
		if not impactDone and elapsed >= DRAW_TIME * 0.6 then
			impactDone = true
			local front = c + dir * (layout.radius * 0.9)
			local floor = Common.ground(front, 8)
			Impact.play(if heavy then floor else front, palette, if heavy then 0.9 else 0.4, false, {
				ring = heavy,
				dust = heavy,
				light = heavy,
				normal = if heavy then Vector3.yAxis else -dir,
			})
			if heavy then
				Common.shake(0.45, 0.2, nil, caster)
				Impact.shockwave(floor, 5, palette.glow, 0.35, { width = 0.4 })
			end
		end
		return allDone and elapsed > SWING_WINDOW
	end)
end

return BasicSlash
