--!strict
-- Procedural pose clips: keyframed joint rotations, sampled over time.
-- Pure Luau (no Roblox types) so Lune can test it; Client/Vfx/Poses turns the
-- samples into Motor6D transforms.
--
-- A clip lists keys in time order. Each key holds Euler angles in degrees per
-- joint ({x, y, z}); a joint missing from a key is at 0 there. `ease` on a key
-- shapes the segment that STARTS at that key. The clip's weight fades in over
-- `blendIn` and out over `blendOut`, so it blends with whatever the Animator plays.

export type Euler = { number }
export type Pose = { [string]: Euler }
export type Ease = "linear" | "in" | "out" | "inout"
export type Key = { t: number, pose: Pose, ease: Ease? }
export type Clip = { duration: number, blendIn: number, blendOut: number, keys: { Key } }

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
function PoseClip.weight(clip: Clip, t: number): number
	if t <= 0 or t >= clip.duration then
		return 0
	end
	local inW = if clip.blendIn > 0 then t / clip.blendIn else 1
	local outW = if clip.blendOut > 0 then (clip.duration - t) / clip.blendOut else 1
	return math.clamp(math.min(inW, outW), 0, 1)
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
	if clip.blendIn + clip.blendOut > clip.duration then
		return false, "blendIn + blendOut longer than the clip"
	end
	return true, nil
end

return PoseClip
