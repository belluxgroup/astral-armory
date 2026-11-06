--!strict
-- Procedural pose clips: keyframed joint rotations, sampled over time.
-- Pure Luau (no Roblox types) so Lune can test it; Client/Vfx/Poses turns the
-- samples into Motor6D transforms.
--
-- A clip lists keys in time order. Each key holds Euler angles in degrees per
-- joint ({x, y, z}); a joint missing from a key is at 0 there. `ease` on a key
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
		out[joint] = {
			p[1] + (q[1] - p[1]) * alpha,
			p[2] + (q[2] - p[2]) * alpha,
			p[3] + (q[3] - p[3]) * alpha,
		}
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

local function samePose(a: Pose, b: Pose): boolean
	for joint, e in a do
		local f = b[joint] or ZERO
		if e[1] ~= f[1] or e[2] ~= f[2] or e[3] ~= f[3] then
			return false
		end
	end
	for joint, f in b do
		if a[joint] == nil and (f[1] ~= 0 or f[2] ~= 0 or f[3] ~= 0) then
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
			if #e ~= 3 then
				return false, `key {i}: {joint} needs 3 angles`
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
