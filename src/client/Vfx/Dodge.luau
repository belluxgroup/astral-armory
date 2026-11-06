--!strict
-- Dodge roll and backstep (dodge spec §4).
--
--   pose   Vfx/Poses plays dodge_roll or dodge_backstep (Config.PoseClips) on the
--          caster, replacing any swing or cast pose it was in
--   dust   a low, wide smoke_soft puff under the caster at the start, and again
--          where it lands
--   trail  a faint after-image between two torso attachments, on for the move's
--          i-frame window only
--
-- No camera shake. The local caster plays this from its own prediction (Input/Dodge);
-- every other client plays it from the server's "dodge" SkillFx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DodgeConfig = require(Shared:WaitForChild("Config"):WaitForChild("Dodge"))
local Net = require(Shared:WaitForChild("Net"))
local Common = require(script.Parent.Common)
local Poses = require(script.Parent.Poses)

type DodgeFx = Net.DodgeFx
type Effect = Common.Effect

local Dodge = {}

local DUST_COLOR = Color3.fromRGB(196, 182, 160)
local AFTERIMAGE_COLOR = Color3.fromRGB(236, 230, 255)
local DUST_LIFETIME = 0.9
local GROUND_PROBE = 10

local function puff(fx: Effect, position: Vector3, count: number, scale: number)
	local ground, normal = Common.ground(position, GROUND_PROBE)
	local holder = fx:attachment(nil, Common.upFrame(ground + normal * 0.3, normal))
	-- Slow, heavily dragged particles that grow a lot: the puff spreads sideways and
	-- stays low instead of rising.
	local dust = fx:emitter(holder, {
		Enabled = false,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(88, 88),
		Speed = NumberRange.new(9 * scale, 15 * scale),
		Drag = 7,
		Acceleration = Vector3.new(0, -3, 0),
		Lifetime = NumberRange.new(DUST_LIFETIME * 0.65, DUST_LIFETIME),
		Size = Common.seq({ { 0, 1.1 * scale }, { 0.4, 2.8 * scale }, { 1, 4.2 * scale } }),
		Transparency = Common.seq({ { 0, 0.55 }, { 0.5, 0.75 }, { 1, 1 } }),
		Color = Common.colors(DUST_COLOR),
		LightEmission = 0,
		LightInfluence = 1,
		RotSpeed = NumberRange.new(-40, 40),
	}, "smoke_soft")
	if dust then
		dust:Emit(count)
	end
end

local function afterImage(fx: Effect, character: Model, move: DodgeConfig.Move)
	local upper = character:FindFirstChild("UpperTorso")
	local lower = character:FindFirstChild("LowerTorso")
	if not (upper and lower and upper:IsA("BasePart") and lower:IsA("BasePart")) then
		return
	end
	local top = fx:attachment(upper, CFrame.new(0, upper.Size.Y * 0.45, 0))
	local bottom = fx:attachment(lower, CFrame.new(0, -lower.Size.Y * 0.5, 0))
	local trail = fx:trail(top, bottom, {
		Enabled = false,
		Lifetime = 0.2,
		Color = Common.colors(AFTERIMAGE_COLOR),
		Transparency = Common.seq({ { 0, 0.72 }, { 1, 1 } }),
		LightEmission = 0.5,
		Brightness = 1,
	})
	fx:at(move.iframeStart, function()
		trail.Enabled = true
	end)
	fx:at(move.iframeEnd, function()
		trail.Enabled = false
	end)
end

function Dodge.play(event: DodgeFx)
	local kind: Net.DodgeKind = if event.spec.kind == "backstep" then "backstep" else "roll"
	local move = DodgeConfig.move(kind)
	local character = Common.characterOf(event.casterUserId)
	local fx = Common.effect("Dodge", move.duration + DUST_LIFETIME + 0.1)
	local roll = kind == "roll"

	if character then
		Poses.play(character, move.clip)
		afterImage(fx, character, move)
	end
	puff(fx, event.origin, if roll then 14 else 9, if roll then 1 else 0.75)
	fx:at(move.land, function()
		-- Land where the character is now; the event's target is only where it was heading.
		local root = Common.rootOf(Common.characterOf(event.casterUserId))
		puff(
			fx,
			if root then root.Position else event.target,
			if roll then 18 else 10,
			if roll then 1.1 else 0.8
		)
	end)
end

return Dodge
