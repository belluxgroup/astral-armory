--!strict
-- Procedural pose clips: keyframed joint rotations and offsets, sampled over time.
-- Pure Luau (no Roblox types) so Lune can test it; Client/Vfx/Poses turns the
-- samples into Motor6D transforms.
--
-- A clip lists keys in time order. Each key holds, per joint, Euler angles in
-- degrees ({rx, ry, rz}) and optionally an offset in studs ({rx, ry, rz, px, py, pz}).
-- A joint missing from a key is at 0 there, and so is a missing offset. `ease` on a key
-- shapes the segment that STARTS at that key. The clip's weight fades in over
-- `blendIn` and out over `blendOut`, so it blends with whatever the Animator plays.
-- A `loop` clip wraps its time, holds weight 1 after its blend-in and never ends;
-- its last key sits at `duration` and repeats the first pose, so the wrap is seamless.

export type Euler = { number }
export type Pose = { [string]: Euler }
export type Ease = "linear" | "in" | "out" | "inout"
export type Key = { t: number, pose: Pose, ease: Ease? }
export type Clip = { duration: number, blendIn: number, blendOut: number, keys: { Key }, loop: boolean? }

local PoseClip = {}

local ZERO: Euler = { 0, 0, 0 }
local ROTATION_ONLY = 3
local WITH_OFFSET = 6

local function ease(kind: Ease?, a: number): number
	if kind == "in" then
		return a * a * a
	elseif kind == "out" then
		local b = 1 - a
		return 1 - b * b * b
	elseif kind == "inout" then
		return a * a * (3 - 2 * a)
	end
	return a
end

-- Every joint any key of the clip touches. Joints outside this set are left to the Animator.
function PoseClip.joints(clip: Clip): { string }
	local seen: { [string]: true } = {}
	local list: { string } = {}
	for _, key in clip.keys do
		for joint in key.pose do
			if not seen[joint] then
				seen[joint] = true
				table.insert(list, joint)
			end
		end
	end
	table.sort(list)
	return list
end

-- The pose at time t (seconds), for every joint in the clip.
function PoseClip.sample(clip: Clip, t: number): Pose
	local keys = clip.keys
	if clip.loop and clip.duration > 0 then
		t = t % clip.duration
	end
	local out: Pose = {}
	local joints = PoseClip.joints(clip)
	local a, b, alpha = keys[1], keys[1], 0
	if t >= keys[#keys].t then
		a, b = keys[#keys], keys[#keys]
	elseif t > keys[1].t then
		for i = 1, #keys - 1 do
			if t < keys[i + 1].t then
				a, b = keys[i], keys[i + 1]
				local span = b.t - a.t
				alpha = if span > 0 then ease(a.ease, (t - a.t) / span) else 1
				break
			end
		end
	end
	for _, joint in joints do
		local p, q = a.pose[joint] or ZERO, b.pose[joint] or ZERO
		local e: Euler = table.create(math.max(#p, #q))
		for c = 1, math.max(#p, #q) do
			local from = p[c] or 0
			e[c] = from + ((q[c] or 0) - from) * alpha
		end
		out[joint] = e
	end
	return out
end

-- Blend weight at time t: 0 before start and after the end, 1 in the body.
-- A looping clip has no end: after its blend-in it stays at 1.
function PoseClip.weight(clip: Clip, t: number): number
	if t <= 0 then
		return 0
	end
	local inW = if clip.blendIn > 0 then t / clip.blendIn else 1
	if clip.loop then
		return math.clamp(inW, 0, 1)
	end
	if t >= clip.duration then
		return 0
	end
	local outW = if clip.blendOut > 0 then (clip.duration - t) / clip.blendOut else 1
	return math.clamp(math.min(inW, outW), 0, 1)
end

-- True once a one-shot clip has played out. A looping clip is never done.
function PoseClip.done(clip: Clip, t: number): boolean
	return not clip.loop and t >= clip.duration
end

local function sameValue(e: Euler, f: Euler): boolean
	for c = 1, WITH_OFFSET do
		if (e[c] or 0) ~= (f[c] or 0) then
			return false
		end
	end
	return true
end

local function samePose(a: Pose, b: Pose): boolean
	for joint, e in a do
		if not sameValue(e, b[joint] or ZERO) then
			return false
		end
	end
	for joint, f in b do
		if a[joint] == nil and not sameValue(ZERO, f) then
			return false
		end
	end
	return true
end

-- Validation used by the tests: keys ordered and inside the clip, known joints only.
function PoseClip.validate(clip: Clip, knownJoints: { [string]: true }): (boolean, string?)
	if #clip.keys < 2 then
		return false, "needs at least 2 keys"
	end
	local last = -1
	for i, key in clip.keys do
		if key.t < last then
			return false, `key {i} out of order`
		end
		if key.t < 0 or key.t > clip.duration then
			return false, `key {i} outside the clip`
		end
		last = key.t
		for joint, e in key.pose do
			if not knownJoints[joint] then
				return false, `key {i}: unknown joint {joint}`
			end
			if #e ~= ROTATION_ONLY and #e ~= WITH_OFFSET then
				return false, `key {i}: {joint} needs 3 angles, or 3 angles and 3 offsets`
			end
		end
	end
	if clip.loop then
		local first, final = clip.keys[1], clip.keys[#clip.keys]
		if first.t ~= 0 or final.t ~= clip.duration or not samePose(first.pose, final.pose) then
			return false, "loop does not close"
		end
	end
	if clip.blendIn + clip.blendOut > clip.duration then
		return false, "blendIn + blendOut longer than the clip"
	end
	return true, nil
end

return PoseClip
