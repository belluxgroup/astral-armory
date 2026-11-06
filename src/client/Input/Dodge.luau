--!strict
-- The local dodge (dodge spec §2-3). Left Shift or the touch "Lăn" button calls Dodge.try,
-- which predicts the move at once (motion, facing, pose and dust) and returns the payload
-- for the Dodge remote. The server never moves the player: it only grants the stamina
-- spend and the i-frames, and checks the displacement afterwards.
--
-- The client owns its character's physics, so the motion lives here. A LinearVelocity on
-- the HumanoidRootPart constrains velocity along the move line only, so gravity, slopes
-- and walls still act, and follows the ease-out speed curve of Config/Dodge. AutoRotate
-- is off for the move: a roll faces where it goes, a backstep keeps facing forward.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DodgeConfig = require(Shared:WaitForChild("Config"):WaitForChild("Dodge"))
local Net = require(Shared:WaitForChild("Net"))
local DodgeFx = require(script.Parent.Parent:WaitForChild("Vfx"):WaitForChild("Dodge"))

-- How hard (studs/s² per unit of mass) the LinearVelocity may push to hold the curve.
local MAX_ACCEL = 2000
local NAME = "AstralDodge"

local player = Players.LocalPlayer

local Dodge = {}

local startedAt = -math.huge
local endsAt = -math.huge

-- True for the whole move: the client refuses skills, as the server does.
function Dodge.active(): boolean
	return os.clock() < endsAt
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function drive(
	humanoid: Humanoid,
	root: BasePart,
	kind: DodgeConfig.Kind,
	heading: Vector3,
	face: Vector3
)
	local move = DodgeConfig.move(kind)
	local attachment = Instance.new("Attachment")
	attachment.Name = NAME
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = NAME
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	velocity.LineDirection = heading
	velocity.LineVelocity = DodgeConfig.speedAt(kind, 0)
	velocity.MaxForce = root.AssemblyMass * MAX_ACCEL
	velocity.Parent = root

	local autoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	root.CFrame = CFrame.lookAt(root.Position, root.Position + face)

	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.PreSimulation:Connect(function()
		local alpha = (os.clock() - started) / move.duration
		if alpha < 1 and humanoid.Health > 0 and root.Parent ~= nil then
			velocity.LineVelocity = DodgeConfig.speedAt(kind, alpha)
			return
		end
		if connection then
			connection:Disconnect()
		end
		velocity:Destroy()
		attachment:Destroy()
		if humanoid.Parent then
			humanoid.AutoRotate = autoRotate
		end
	end)
end

-- Starts a dodge if the local rules allow it and returns the direction to send to the
-- server (a zero vector for a backstep), or nil when it is refused here. Stamina and life
-- are checked by the caller against the latest PlayerState.
function Dodge.try(): Vector3?
	local now = os.clock()
	if now - startedAt < DodgeConfig.cooldown then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return nil
	end
	-- Boss chains hold WalkSpeed at 0 while they root; the server refuses that dodge too.
	if humanoid.WalkSpeed <= 0 then
		return nil
	end

	local wish = flat(humanoid.MoveDirection)
	local kind: DodgeConfig.Kind = DodgeConfig.kindFor(wish.X, wish.Z)
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local heading = if kind == "roll" then wish.Unit else -look
	local face = if kind == "roll" then heading else look
	local move = DodgeConfig.move(kind)

	startedAt = now
	endsAt = now + move.duration
	drive(humanoid, root, kind, heading, face)

	local origin = root.Position
	local event: Net.DodgeFx = {
		skillId = "dodge",
		casterUserId = player.UserId,
		origin = origin,
		target = origin + heading * move.distance,
		spec = { kind = kind },
		serverTime = Workspace:GetServerTimeNow(),
	}
	task.spawn(function()
		local ok, err = pcall(DodgeFx.play :: any, event)
		if not ok then
			warn(`[Input] dodge effect failed: {err}`)
		end
	end)
	return if kind == "roll" then heading else Vector3.zero
end

return Dodge
