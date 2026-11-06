--!strict
-- Drives the procedural combat poses (Shared.Config.PoseClips) on R15 characters.
--
-- Every client plays the clip for every caster from the same SkillFx event, so
-- everyone sees the swing even though Motor6D.Transform never replicates. The
-- pose is applied in PreSimulation, after the Animator has written its own
-- transforms for the frame: torso and head layer on top of walking/idle, arms
-- blend towards the clip by its weight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PoseClip = require(Shared:WaitForChild("Logic"):WaitForChild("PoseClip"))
local PoseClips = require(Shared:WaitForChild("Config"):WaitForChild("PoseClips"))
local Common = require(script.Parent.Common)

type FxEvent = Common.FxEvent
-- Classic rigs use Motor6D joints; avatars on the constraint-based joint rig use
-- AnimationConstraint. Both expose the Animator-driven Transform.
type Joint = Motor6D | AnimationConstraint
type Bound = { motor: Joint, joint: string, additive: boolean }
type Active = { clip: PoseClip.Clip, started: number, bound: { Bound } }

local Poses = {}

local active: { [Model]: Active } = {}
local connection: RBXScriptConnection? = nil

local RAD = math.pi / 180
local IDENTITY = CFrame.new()

local function toCFrame(e: PoseClip.Euler): CFrame
	return CFrame.fromEulerAnglesXYZ(e[1] * RAD, e[2] * RAD, e[3] * RAD)
end

local function bind(character: Model, clip: PoseClip.Clip): { Bound }
	local out: { Bound } = {}
	for _, joint in PoseClip.joints(clip) do
		local info = PoseClips.JOINTS[joint]
		local part = info and character:FindFirstChild(info.part)
		local motor = part and part:FindFirstChild(joint)
		if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
			table.insert(out, { motor = motor :: Joint, joint = joint, additive = info.mode == "add" })
		end
	end
	return out
end

local function step()
	local now = os.clock()
	for character, run in active do
		local t = now - run.started
		if t >= run.clip.duration or not character.Parent then
			active[character] = nil
			continue
		end
		local w = PoseClip.weight(run.clip, t)
		local pose = PoseClip.sample(run.clip, t)
		for _, b in run.bound do
			local e = pose[b.joint]
			if e and b.motor.Parent then
				local target = toCFrame(e)
				if b.additive then
					b.motor.Transform = b.motor.Transform * IDENTITY:Lerp(target, w)
				else
					b.motor.Transform = b.motor.Transform:Lerp(target, w)
				end
			end
		end
	end
	if next(active) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Plays a named clip on a character, replacing whatever clip it was playing.
function Poses.play(character: Model, clipName: string)
	local clip = PoseClips.clips[clipName]
	if not clip then
		return
	end
	active[character] = { clip = clip, started = os.clock(), bound = bind(character, clip) }
	if not connection then
		connection = RunService.PreSimulation:Connect(step)
	end
end

-- Plays the pose for an FxEvent. The local caster also snaps to face the aim, so
-- the swing and the effect point the same way.
function Poses.forEvent(event: FxEvent)
	local clipName, faceAim = PoseClips.forSkill(event.skillId, event.combo)
	local character = Common.characterOf(event.casterUserId)
	if not clipName or not character then
		return
	end
	local localPlayer = Players.LocalPlayer
	if faceAim and localPlayer and event.casterUserId == localPlayer.UserId then
		local root = Common.rootOf(character)
		if root then
			local dir = Common.aimDirection(event.origin, event.target, event.casterUserId)
			root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
		end
	end
	Poses.play(character, clipName)
end

return Poses
