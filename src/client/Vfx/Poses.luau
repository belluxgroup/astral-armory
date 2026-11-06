--!strict
-- Drives the procedural combat poses (Shared.Config.PoseClips) on R15 characters.
--
-- Every client plays the clip for every caster from the same SkillFx event, so
-- everyone sees the swing even though Motor6D.Transform never replicates. The
-- pose is applied in PreSimulation, after the Animator has written its own
-- transforms for the frame: torso and head layer on top of walking/idle, arms
-- blend towards the clip by its weight.
--
-- A model has two layers: a looping idle (a clip with `loop`, such as the boss
-- stance) and a one-shot on top of it. A new one-shot replaces the current
-- one; when it blends out the idle shows through again, with no pop. The pose
-- the replaced one-shot had reached is held and faded out over the new clip's
-- blend-in, so a dodge cutting a sword swing short never snaps a limb (joints
-- the new clip does not touch fade back to the Animator the same way).

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
type Bound = { motor: Joint, additive: boolean }
type Run = { clip: PoseClip.Clip, started: number }
type Fade = { pose: PoseClip.Pose, weight: number, started: number, length: number }
type Layers = { idle: Run?, shot: Run?, fade: Fade?, joints: { [string]: Bound } }

local Poses = {}

local active: { [Model]: Layers } = {}
local connection: RBXScriptConnection? = nil

local RAD = math.pi / 180
local IDENTITY = CFrame.new()
local MIN_FADE = 0.05

-- Angles in degrees, then an optional offset in studs (PoseClip position channels).
local function toCFrame(e: PoseClip.Euler): CFrame
	return CFrame.new(e[4] or 0, e[5] or 0, e[6] or 0)
		* CFrame.fromEulerAnglesXYZ(e[1] * RAD, e[2] * RAD, e[3] * RAD)
end

-- Adds the joints a clip touches to the model's bound set.
local function bind(character: Model, layers: Layers, clip: PoseClip.Clip)
	for _, joint in PoseClip.joints(clip) do
		local bound = layers.joints[joint]
		if bound and bound.motor.Parent then
			continue
		end
		local info = PoseClips.JOINTS[joint]
		local part = info and character:FindFirstChild(info.part)
		local motor = part and part:FindFirstChild(joint)
		if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
			layers.joints[joint] = { motor = motor :: Joint, additive = info.mode == "add" }
		end
	end
end

local function step()
	local now = os.clock()
	for character, layers in active do
		if not character.Parent then
			active[character] = nil
			continue
		end
		local shot = layers.shot
		if shot and PoseClip.done(shot.clip, now - shot.started) then
			layers.shot = nil
			shot = nil
		end
		local fade = layers.fade
		local fadeW = 0
		if fade then
			fadeW = fade.weight * (1 - (now - fade.started) / fade.length)
			if fadeW <= 0 then
				layers.fade = nil
				fade = nil
			end
		end
		local idle = layers.idle
		if not shot and not idle and not fade then
			active[character] = nil
			continue
		end
		local fadePose = fade and fade.pose
		local idlePose, idleW, shotPose, shotW = nil, 0, nil, 0
		if idle then
			local t = now - idle.started
			idlePose, idleW = PoseClip.sample(idle.clip, t), PoseClip.weight(idle.clip, t)
		end
		if shot then
			local t = now - shot.started
			shotPose, shotW = PoseClip.sample(shot.clip, t), PoseClip.weight(shot.clip, t)
		end
		for joint, b in layers.joints do
			if not b.motor.Parent then
				continue
			end
			local eI = idlePose and idlePose[joint]
			local eF = fadePose and fadePose[joint]
			local eS = shotPose and shotPose[joint]
			if not eI and not eF and not eS then
				continue
			end
			if b.additive then
				local offset = IDENTITY
				if eI then
					offset = IDENTITY:Lerp(toCFrame(eI), idleW)
				end
				if eF then
					offset = offset:Lerp(toCFrame(eF), fadeW)
				end
				if eS then
					offset = offset:Lerp(toCFrame(eS), shotW)
				end
				b.motor.Transform = b.motor.Transform * offset
			else
				local transform = b.motor.Transform
				if eI then
					transform = transform:Lerp(toCFrame(eI), idleW)
				end
				if eF then
					transform = transform:Lerp(toCFrame(eF), fadeW)
				end
				if eS then
					transform = transform:Lerp(toCFrame(eS), shotW)
				end
				b.motor.Transform = transform
			end
		end
	end
	if next(active) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Plays a named clip on a character. A looping clip becomes its idle layer; any
-- other clip replaces the one-shot it was playing, on top of that idle. `skip`
-- starts the clip that many seconds in.
function Poses.play(character: Model, clipName: string, skip: number?)
	local clip = PoseClips.clips[clipName]
	if not clip then
		return
	end
	local layers = active[character]
	if not layers then
		layers = { joints = {} }
		active[character] = layers
	end
	local now = os.clock()
	local run: Run = { clip = clip, started = now - math.max(skip or 0, 0) }
	if clip.loop then
		layers.idle = run
	else
		local previous = layers.shot
		if previous then
			local t = now - previous.started
			local weight = PoseClip.weight(previous.clip, t)
			if weight > 0 then
				layers.fade = {
					pose = PoseClip.sample(previous.clip, t),
					weight = weight,
					started = now,
					length = math.max(clip.blendIn, MIN_FADE),
				}
			end
		end
		layers.shot = run
	end
	bind(character, layers, clip)
	if not connection then
		connection = RunService.PreSimulation:Connect(step)
	end
end

-- Starts a looping clip unless the model already has an idle layer (late joiners
-- and streamed-in models miss the spawn `pose` event).
function Poses.ensureIdle(character: Model, clipName: string)
	local layers = active[character]
	if not (layers and layers.idle) then
		Poses.play(character, clipName)
	end
end

-- Stops every layer on a model.
function Poses.stop(character: Model)
	active[character] = nil
end

-- BossFx `pose`: plays `clip` on the boss model the event carries.
function Poses.forBossFx(evt: { [string]: any })
	if type(evt) ~= "table" or evt.event ~= "pose" or type(evt.clip) ~= "string" then
		return
	end
	local model = evt.model
	if typeof(model) == "Instance" and model:IsA("Model") and model.Parent then
		Poses.play(model, evt.clip)
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
