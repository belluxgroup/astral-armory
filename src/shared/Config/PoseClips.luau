--!strict
-- Keyframed upper-body poses for the sword combo and every skill (R15 joints).
-- Angles are degrees in each Motor6D's joint space:
--   Shoulder X+ raises the arm forward/up, X- swings it back; Z+ lifts the RIGHT arm
--   outward, Z- lifts the LEFT arm outward; Y twists the arm.
--   Elbow / Wrist X+ bends forward.
--   The sword sits across the palm (blade along the hand's forward axis), so with the
--   arm raised the blade points up. RightWrist X around -80 lines the blade up with the
--   arm, which is what a cut or a raised sword needs. Z is applied first, then Y, then X
--   (CFrame.fromEulerAnglesXYZ), so a big X on top of a big Z swings the arm sideways,
--   not up: "arms up and out" is Z +-120 with X near 0.
--   Measured in Studio on the R15 constraint rig (2026-11-06): every sign below holds.
--   Waist Y+ turns the torso left, Y- right; X+ leans back, X- leans forward.
--   Neck X+ looks up.
-- Timings line up with the VFX modules and the server hits (see each comment).

local PoseClip = if script then require(script.Parent.Parent.Logic.PoseClip) else require("../Logic/PoseClip")

type Clip = PoseClip.Clip

local PoseClips = {}

-- Joint name -> the R15 part that holds its Motor6D, and how the pose combines with the Animator:
-- "add" layers on top (torso, head), "override" blends the limb towards the pose.
PoseClips.JOINTS = {
	Waist = { part = "UpperTorso", mode = "add" },
	Neck = { part = "Head", mode = "add" },
	RightShoulder = { part = "RightUpperArm", mode = "override" },
	RightElbow = { part = "RightLowerArm", mode = "override" },
	RightWrist = { part = "RightHand", mode = "override" },
	LeftShoulder = { part = "LeftUpperArm", mode = "override" },
	LeftElbow = { part = "LeftLowerArm", mode = "override" },
	LeftWrist = { part = "LeftHand", mode = "override" },
}

local clips: { [string]: Clip } = {
	-- Combo 1: diagonal cut from high right to low left (BasicSlash hit 1 arc, right to left).
	-- The crescent flashes at t = 0 and the server hit is instant, so the anticipation is tiny.
	basic_1 = {
		duration = 0.34,
		blendIn = 0.03,
		blendOut = 0.12,
		keys = {
			{ t = 0, pose = { RightShoulder = { 60, 0, 30 }, Waist = { 0, -12, 0 } }, ease = "out" },
			{
				t = 0.05,
				pose = {
					RightShoulder = { 125, -20, 55 },
					RightElbow = { 35, 0, 0 },
					RightWrist = { 0, 0, -25 },
					Waist = { 0, -28, 0 },
				},
				ease = "out",
			},
			{
				t = 0.13,
				pose = {
					RightShoulder = { 75, 30, -55 },
					RightElbow = { 10, 0, 0 },
					RightWrist = { -80, -45, 0 },
					Waist = { -8, 32, 0 },
				},
				ease = "inout",
			},
			{
				t = 0.2,
				pose = {
					RightShoulder = { 62, 30, -60 },
					RightElbow = { 15, 0, 0 },
					RightWrist = { -80, -45, 0 },
					Waist = { -10, 36, 0 },
				},
			},
			{ t = 0.34, pose = { RightShoulder = { 35, 0, 0 } } },
		},
	},
	-- Combo 2: backhand from low left up to high right (hit 2 arc, left to right).
	basic_2 = {
		duration = 0.34,
		blendIn = 0.03,
		blendOut = 0.12,
		keys = {
			{
				t = 0,
				pose = { RightShoulder = { 62, 30, -60 }, RightWrist = { -80, 30, 0 }, Waist = { -6, 30, 0 } },
				ease = "out",
			},
			{
				t = 0.05,
				pose = {
					RightShoulder = { 55, 75, -75 },
					RightElbow = { 40, 0, 0 },
					RightWrist = { -80, 0, 0 },
					Waist = { -6, 38, 0 },
				},
				ease = "out",
			},
			{
				t = 0.13,
				pose = {
					RightShoulder = { 120, -25, 65 },
					RightElbow = { 8, 0, 0 },
					RightWrist = { 0, 0, -30 },
					Waist = { 6, -30, 0 },
				},
				ease = "inout",
			},
			{ t = 0.2, pose = { RightShoulder = { 130, -25, 70 }, Waist = { 8, -34, 0 } } },
			{ t = 0.34, pose = { RightShoulder = { 35, 0, 0 } } },
		},
	},
	-- Combo 3, the finisher: a wide flat cleave right to left with a full torso turn
	-- (hit 3 arc, -120 to 120 degrees, nearly horizontal).
	basic_3 = {
		duration = 0.5,
		blendIn = 0.03,
		blendOut = 0.16,
		keys = {
			{ t = 0, pose = { RightShoulder = { 70, 0, 40 }, Waist = { 0, -20, 0 } }, ease = "out" },
			{
				t = 0.06,
				pose = {
					RightShoulder = { 90, -40, 70 },
					RightElbow = { 20, 0, 0 },
					RightWrist = { -60, -15, 0 },
					LeftShoulder = { 55, 0, -30 },
					Waist = { 4, -50, 0 },
					Neck = { 0, 22, 0 },
				},
				ease = "out",
			},
			{
				t = 0.15,
				pose = {
					RightShoulder = { 90, 50, -40 },
					RightElbow = { 5, 0, 0 },
					RightWrist = { -80, -45, 0 },
					LeftShoulder = { 35, 0, -60 },
					Waist = { -10, 55, 0 },
					Neck = { 0, -25, 0 },
				},
				ease = "linear",
			},
			{
				t = 0.28,
				pose = {
					RightShoulder = { 85, 55, -45 },
					RightElbow = { 10, 0, 0 },
					RightWrist = { -80, -45, 0 },
					LeftShoulder = { 30, 0, -55 },
					Waist = { -12, 58, 0 },
					Neck = { 0, -25, 0 },
				},
				ease = "inout",
			},
			{ t = 0.5, pose = { RightShoulder = { 35, 0, 0 } } },
		},
	},
	-- Q: raise the sword arm to the opening sigil, then sweep it down as the blades fall (0.6 s).
	blade_rain = {
		duration = 1.1,
		blendIn = 0.08,
		blendOut = 0.25,
		keys = {
			{ t = 0, pose = {}, ease = "out" },
			{
				t = 0.15,
				pose = {
					RightShoulder = { 165, 0, 20 },
					RightElbow = { 10, 0, 0 },
					RightWrist = { -80, 15, 0 },
					LeftShoulder = { 30, 0, -25 },
					Waist = { 12, 0, 0 },
					Neck = { 25, 0, 0 },
				},
				ease = "linear",
			},
			{
				t = 0.55,
				pose = {
					RightShoulder = { 172, 0, 14 },
					RightElbow = { 6, 0, 0 },
					RightWrist = { -80, 15, 0 },
					LeftShoulder = { 34, 0, -28 },
					Waist = { 15, 0, 0 },
					Neck = { 28, 0, 0 },
				},
				ease = "out",
			},
			{
				t = 0.7,
				pose = {
					RightShoulder = { 70, 0, -5 },
					RightWrist = { -80, 0, 0 },
					LeftShoulder = { 20, 0, -20 },
					Waist = { -10, 0, 0 },
					Neck = { -5, 0, 0 },
				},
				ease = "inout",
			},
			{ t = 1.1, pose = { RightShoulder = { 40, 0, 0 } } },
		},
	},
	-- E: two hands overhead through the 1.2 s channel, then a downward cut on release.
	dawnbreaker = {
		duration = 1.75,
		blendIn = 0.1,
		blendOut = 0.3,
		keys = {
			{ t = 0, pose = {}, ease = "out" },
			{
				t = 0.25,
				pose = {
					RightShoulder = { 160, 0, -10 },
					LeftShoulder = { 160, 0, 10 },
					RightElbow = { 25, 0, 0 },
					LeftElbow = { 25, 0, 0 },
					Waist = { 14, 0, 0 },
					Neck = { 14, 0, 0 },
				},
				ease = "linear",
			},
			{
				t = 1.15,
				pose = {
					RightShoulder = { 168, 0, -8 },
					LeftShoulder = { 168, 0, 8 },
					RightElbow = { 30, 0, 0 },
					LeftElbow = { 30, 0, 0 },
					Waist = { 22, 0, 0 },
					Neck = { 18, 0, 0 },
				},
				ease = "out",
			},
			{
				t = 1.3,
				pose = {
					RightShoulder = { 35, 0, -5 },
					LeftShoulder = { 35, 0, 5 },
					RightElbow = { 5, 0, 0 },
					LeftElbow = { 5, 0, 0 },
					Waist = { -30, 0, 0 },
					Neck = { -15, 0, 0 },
				},
				ease = "linear",
			},
			{
				t = 1.45,
				pose = {
					RightShoulder = { 32, 0, -5 },
					LeftShoulder = { 32, 0, 5 },
					RightElbow = { 8, 0, 0 },
					LeftElbow = { 8, 0, 0 },
					Waist = { -28, 0, 0 },
					Neck = { -12, 0, 0 },
				},
				ease = "inout",
			},
			{ t = 1.75, pose = { RightShoulder = { 40, 0, 0 } } },
		},
	},
	-- R: the lance materializes in a cocked arm (0.15 s), then a full-body throw.
	crimson_lance = {
		duration = 0.75,
		blendIn = 0.05,
		blendOut = 0.2,
		keys = {
			{ t = 0, pose = {}, ease = "out" },
			{
				t = 0.15,
				pose = {
					RightShoulder = { 150, -30, 50 },
					RightElbow = { 70, 0, 0 },
					LeftShoulder = { 80, 0, -20 },
					Waist = { 0, -40, 0 },
				},
				ease = "out",
			},
			{
				t = 0.26,
				pose = {
					RightShoulder = { 95, 30, -15 },
					RightElbow = { 0, 0, 0 },
					LeftShoulder = { 20, 0, -30 },
					Waist = { -12, 35, 0 },
				},
				ease = "linear",
			},
			{
				t = 0.42,
				pose = {
					RightShoulder = { 85, 25, -15 },
					LeftShoulder = { 18, 0, -28 },
					Waist = { -10, 30, 0 },
				},
				ease = "inout",
			},
			{ t = 0.75, pose = {} },
		},
	},
	-- F: open palm thrust forward to raise the dome, sword held low in guard.
	hex_aegis = {
		duration = 0.9,
		blendIn = 0.06,
		blendOut = 0.25,
		keys = {
			{ t = 0, pose = {}, ease = "out" },
			{
				t = 0.12,
				pose = {
					LeftShoulder = { 95, 0, -10 },
					LeftElbow = { 10, 0, 0 },
					LeftWrist = { -40, 0, 0 },
					RightShoulder = { 50, 0, 25 },
					Waist = { 0, 10, 0 },
				},
				ease = "linear",
			},
			{
				t = 0.6,
				pose = {
					LeftShoulder = { 92, 0, -12 },
					LeftElbow = { 12, 0, 0 },
					LeftWrist = { -40, 0, 0 },
					RightShoulder = { 48, 0, 25 },
					Waist = { 0, 10, 0 },
				},
				ease = "inout",
			},
			{ t = 0.9, pose = {} },
		},
	},
	-- T: gather inward and crouch, then burst open with arms spread as the shockwave fires.
	ascension = {
		duration = 1.3,
		blendIn = 0.06,
		blendOut = 0.3,
		keys = {
			{ t = 0, pose = {}, ease = "out" },
			{
				t = 0.25,
				pose = {
					RightShoulder = { -15, 0, 35 },
					LeftShoulder = { -15, 0, -35 },
					RightElbow = { 60, 0, 0 },
					LeftElbow = { 60, 0, 0 },
					Waist = { -25, 0, 0 },
					Neck = { -15, 0, 0 },
				},
				ease = "out",
			},
			{
				t = 0.38,
				pose = {
					RightShoulder = { -30, 0, 120 },
					LeftShoulder = { -30, 0, -120 },
					RightWrist = { -80, 0, 0 },
					RightElbow = { 0, 0, 0 },
					LeftElbow = { 0, 0, 0 },
					Waist = { 20, 0, 0 },
					Neck = { 25, 0, 0 },
				},
				ease = "linear",
			},
			{
				t = 0.9,
				pose = {
					RightShoulder = { -25, 0, 115 },
					LeftShoulder = { -25, 0, -115 },
					RightWrist = { -80, 0, 0 },
					Waist = { 18, 0, 0 },
					Neck = { 22, 0, 0 },
				},
				ease = "inout",
			},
			{ t = 1.3, pose = {} },
		},
	},
}

PoseClips.clips = clips

-- Which clip plays for an FxEvent, and whether the caster turns to face the aim first.
function PoseClips.forSkill(skillId: string, combo: number?): (string?, boolean)
	if skillId == "basic" then
		return `basic_{math.clamp(combo or 1, 1, 3)}`, true
	elseif skillId == "blade_rain" or skillId == "dawnbreaker" or skillId == "crimson_lance" then
		return skillId, true
	elseif skillId == "hex_aegis" or skillId == "ascension" then
		return skillId, false
	end
	return nil, false
end

return PoseClips
