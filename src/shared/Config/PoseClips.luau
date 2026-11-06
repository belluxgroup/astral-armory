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
--   Legs follow the arm axes: Hip X+ swings the thigh forward and up, Knee X- folds the
--   shin back. Root (HumanoidRootPart -> LowerTorso) X- pitches the whole body forward
--   around the waist. A pose value may carry an offset in studs after the angles
--   ({rx, ry, rz, px, py, pz}); for Root, py- lowers the body.
-- Timings line up with the VFX modules and the server hits (see each comment).

local PoseClip = if script then require(script.Parent.Parent.Logic.PoseClip) else require("../Logic/PoseClip")
local Dodge = if script then require(script.Parent.Dodge) else require("./Dodge")

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
	Root = { part = "LowerTorso", mode = "add" },
	RightHip = { part = "RightUpperLeg", mode = "override" },
	RightKnee = { part = "RightLowerLeg", mode = "override" },
	LeftHip = { part = "LeftUpperLeg", mode = "override" },
	LeftKnee = { part = "LeftLowerLeg", mode = "override" },
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

---------------------------------------------------------------- Golden Tyrant (boss)
-- Played on the boss rig from BossFx `pose` events (spec §4). The boss holds its longsword
-- in the right hand with the same grip as the player sword, so RightWrist X -80 lines the
-- blade up with the arm here too. Timings match the BossFx payload delays noted per clip.

type PoseTable = { [string]: { number } }

-- The raised-blade pose of the ultimate, shared by the end of the charge and the start of the fire.
local OVERHEAD: PoseTable = {
	RightShoulder = { 170, 0, -6 },
	RightElbow = { 12, 0, 0 },
	RightWrist = { -80, 0, 0 },
	LeftShoulder = { 25, 0, -55 },
	LeftElbow = { 20, 0, 0 },
	Waist = { 12, 0, 0 },
	Neck = { 18, 0, 0 },
}

-- `base` with a small offset on a few joints (a tremble or a breath).
local function nudge(base: PoseTable, offsets: PoseTable): PoseTable
	local out: PoseTable = {}
	for joint, e in base do
		local o = offsets[joint]
		out[joint] = if o then { e[1] + o[1], e[2] + o[2], e[3] + o[3] } else { e[1], e[2], e[3] }
	end
	return out
end

-- The 2.5 s held charge: the blade trembles harder as the charge builds.
local function chargeKeys(): { PoseClip.Key }
	local keys: { PoseClip.Key } = {
		{ t = 0, pose = {}, ease = "out" },
		{ t = 0.3, pose = OVERHEAD, ease = "inout" },
	}
	local step = 0.08
	local n = 0
	local t = 0.3 + step
	while t < 2.6 do
		n += 1
		local amp = 0.6 + 2.4 * (t - 0.3) / 2.3
		local sign = if n % 2 == 0 then 1 else -1
		table.insert(keys, {
			t = t,
			pose = nudge(OVERHEAD, {
				RightShoulder = { amp * sign, 0, amp * 0.5 * -sign },
				RightWrist = { amp * 0.6 * -sign, 0, 0 },
				Waist = { amp * 0.25 * sign, 0, 0 },
				Neck = { amp * 0.3 * -sign, 0, 0 },
			}),
			ease = "inout",
		})
		t += step
	end
	table.insert(keys, { t = 2.7, pose = OVERHEAD })
	return keys
end

local IDLE: PoseTable = {
	-- Sword arm low and loose, the blade angled down and forward beside the right leg.
	RightShoulder = { 10, 0, 12 },
	RightElbow = { 14, 0, 0 },
	RightWrist = { -30, 0, 0 },
	-- Left hand on the hip: upper arm swung back and out, elbow flexed, so the gauntlet
	-- rests on the side of the waist with the elbow out. Solved with forward kinematics
	-- on the boss rig in Studio (an elbow Z bend folds the hand up to the ribs instead).
	LeftShoulder = { -72, -40, -35 },
	LeftElbow = { 80, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	-- Chest out, chin up.
	Waist = { 5, 0, 0 },
	Neck = { 8, 0, 0 },
}

-- Regal stance with a slow breath: chest rises, chin settles, the shoulders lift a touch.
clips.boss_idle = {
	duration = 4,
	blendIn = 0.5,
	blendOut = 0,
	loop = true,
	keys = {
		{ t = 0, pose = IDLE, ease = "inout" },
		{
			t = 2,
			pose = nudge(IDLE, {
				Waist = { 3, 0, 0 },
				Neck = { -2.5, 0, 0 },
				LeftShoulder = { 0, 0, -3 },
				RightShoulder = { 2, 0, 2 },
			}),
			ease = "inout",
		},
		{ t = 4, pose = IDLE },
	},
}

-- melee: a big diagonal cut, high right to low left. BossFx melee `delay` is the 0.35 s windup,
-- so the blade crosses the strike zone from 0.35 to 0.46.
clips.boss_melee = {
	duration = 1.15,
	blendIn = 0.08,
	blendOut = 0.3,
	keys = {
		{ t = 0, pose = {}, ease = "out" },
		{
			t = 0.28,
			pose = {
				RightShoulder = { 150, -20, 62 },
				RightElbow = { 45, 0, 0 },
				RightWrist = { 0, 0, -25 },
				LeftShoulder = { 45, 0, -35 },
				Waist = { 8, -38, 0 },
				Neck = { 6, 20, 0 },
			},
			ease = "in",
		},
		{
			t = 0.35,
			pose = {
				RightShoulder = { 155, -22, 66 },
				RightElbow = { 48, 0, 0 },
				RightWrist = { 0, 0, -28 },
				LeftShoulder = { 48, 0, -38 },
				Waist = { 10, -42, 0 },
				Neck = { 8, 22, 0 },
			},
			ease = "in",
		},
		{
			t = 0.46,
			pose = {
				RightShoulder = { 58, 30, -58 },
				RightElbow = { 8, 0, 0 },
				RightWrist = { -80, -45, 0 },
				LeftShoulder = { 20, 0, -55 },
				Waist = { -16, 40, 0 },
				Neck = { -10, -18, 0 },
			},
			ease = "out",
		},
		{
			t = 0.72,
			pose = {
				RightShoulder = { 52, 30, -62 },
				RightElbow = { 12, 0, 0 },
				RightWrist = { -80, -45, 0 },
				LeftShoulder = { 18, 0, -52 },
				Waist = { -18, 42, 0 },
				Neck = { -10, -18, 0 },
			},
			ease = "inout",
		},
		{ t = 1.15, pose = { RightShoulder = { 20, 0, 10 } } },
	},
}

-- volley: the left hand rises and snaps as the portals open (the volley event comes 0.6 s
-- after the pose), then holds while the three weapons land; the sword arm stays easy.
clips.boss_volley = {
	duration = 1.5,
	blendIn = 0.1,
	blendOut = 0.35,
	keys = {
		{ t = 0, pose = {}, ease = "out" },
		{
			t = 0.42,
			pose = {
				LeftShoulder = { 120, 0, -28 },
				LeftElbow = { 55, 0, 0 },
				LeftWrist = { -25, 0, 0 },
				RightShoulder = { 10, 0, 14 },
				RightWrist = { -30, 0, 0 },
				Waist = { 4, -12, 0 },
				Neck = { 10, -8, 0 },
			},
			ease = "in",
		},
		{
			t = 0.58,
			pose = {
				LeftShoulder = { 128, 0, -30 },
				LeftElbow = { 50, 0, 0 },
				LeftWrist = { 25, 0, 0 },
				RightShoulder = { 10, 0, 14 },
				RightWrist = { -30, 0, 0 },
				Waist = { 6, -14, 0 },
				Neck = { 12, -8, 0 },
			},
			ease = "inout",
		},
		{
			t = 1.1,
			pose = {
				LeftShoulder = { 122, 0, -32 },
				LeftElbow = { 52, 0, 0 },
				LeftWrist = { 20, 0, 0 },
				RightShoulder = { 10, 0, 14 },
				RightWrist = { -30, 0, 0 },
				Waist = { 5, -12, 0 },
				Neck = { 10, -8, 0 },
			},
			ease = "inout",
		},
		{ t = 1.5, pose = {} },
	},
}

-- armory: both arms swing wide and back, palms open, chest out, while the fan of portals opens
-- and fires (10 to 16 shots, 0.12 s apart, after the opening delay).
clips.boss_armory = {
	duration = 2.8,
	blendIn = 0.1,
	blendOut = 0.4,
	keys = {
		{ t = 0, pose = {}, ease = "out" },
		{
			t = 0.12,
			pose = {
				RightShoulder = { 30, 0, 40 },
				LeftShoulder = { 30, 0, -40 },
				RightElbow = { 50, 0, 0 },
				LeftElbow = { 50, 0, 0 },
				Waist = { -10, 0, 0 },
				Neck = { -6, 0, 0 },
			},
			ease = "out",
		},
		{
			t = 0.32,
			pose = {
				RightShoulder = { -28, 0, 108 },
				LeftShoulder = { -28, 0, -108 },
				RightElbow = { 6, 0, 0 },
				LeftElbow = { 6, 0, 0 },
				RightWrist = { -80, 0, 0 },
				LeftWrist = { 0, 0, -15 },
				Waist = { 14, 0, 0 },
				Neck = { 16, 0, 0 },
			},
			ease = "inout",
		},
		{
			t = 2.3,
			pose = {
				RightShoulder = { -24, 0, 104 },
				LeftShoulder = { -24, 0, -104 },
				RightElbow = { 8, 0, 0 },
				LeftElbow = { 8, 0, 0 },
				RightWrist = { -80, 0, 0 },
				LeftWrist = { 0, 0, -15 },
				Waist = { 12, 0, 0 },
				Neck = { 14, 0, 0 },
			},
			ease = "inout",
		},
		{ t = 2.8, pose = {} },
	},
}

-- chains: the sword hand thrusts at the target while the ring fills (1.0 s), then the fist pulls
-- back as the chains bind and the lunge follows.
clips.boss_chains = {
	duration = 1.6,
	blendIn = 0.06,
	blendOut = 0.3,
	keys = {
		{ t = 0, pose = {}, ease = "out" },
		{
			t = 0.15,
			pose = {
				RightShoulder = { 95, 12, -6 },
				RightElbow = { 0, 0, 0 },
				RightWrist = { -80, 0, 0 },
				LeftShoulder = { -10, 0, -30 },
				Waist = { -6, 25, 0 },
				Neck = { 0, -15, 0 },
			},
			ease = "inout",
		},
		{
			t = 0.95,
			pose = {
				RightShoulder = { 98, 12, -6 },
				RightElbow = { 0, 0, 0 },
				RightWrist = { -84, 0, 0 },
				LeftShoulder = { -12, 0, -32 },
				Waist = { -8, 26, 0 },
				Neck = { 0, -15, 0 },
			},
			ease = "in",
		},
		{
			t = 1.1,
			pose = {
				RightShoulder = { 45, -25, 30 },
				RightElbow = { 105, 0, 0 },
				RightWrist = { -40, 0, 0 },
				LeftShoulder = { 30, 0, -25 },
				Waist = { 6, -22, 0 },
				Neck = { 4, 10, 0 },
			},
			ease = "inout",
		},
		{ t = 1.6, pose = {} },
	},
}

-- ultimate_charge: the blade goes up overhead and is held for the 2.5 s charge, trembling.
clips.boss_ultimate_charge = {
	duration = 2.7,
	blendIn = 0.1,
	blendOut = 0.15,
	keys = chargeKeys(),
}

-- ultimate_fire: from overhead, a two-handed thrust forward along the cone, held while the beam runs.
clips.boss_ultimate_fire = {
	duration = 1.6,
	blendIn = 0.03,
	blendOut = 0.4,
	keys = {
		{ t = 0, pose = OVERHEAD, ease = "in" },
		{
			t = 0.1,
			pose = {
				RightShoulder = { 92, 0, -20 },
				LeftShoulder = { 92, 0, 20 },
				RightElbow = { 4, 0, 0 },
				LeftElbow = { 4, 0, 0 },
				RightWrist = { -80, 0, 0 },
				LeftWrist = { -40, 0, 0 },
				Waist = { -18, 0, 0 },
				Neck = { -4, 0, 0 },
			},
			ease = "out",
		},
		{
			t = 1.1,
			pose = {
				RightShoulder = { 88, 0, -20 },
				LeftShoulder = { 88, 0, 20 },
				RightElbow = { 8, 0, 0 },
				LeftElbow = { 8, 0, 0 },
				RightWrist = { -80, 0, 0 },
				LeftWrist = { -40, 0, 0 },
				Waist = { -14, 0, 0 },
				Neck = { -2, 0, 0 },
			},
			ease = "inout",
		},
		{ t = 1.6, pose = {} },
	},
}

-- enrage: a brief gather, then the head thrown back and the arms flung out.
clips.boss_enrage = {
	duration = 1.9,
	blendIn = 0.06,
	blendOut = 0.4,
	keys = {
		{ t = 0, pose = {}, ease = "out" },
		{
			t = 0.2,
			pose = {
				RightShoulder = { -10, 0, 25 },
				LeftShoulder = { -10, 0, -25 },
				RightElbow = { 70, 0, 0 },
				LeftElbow = { 70, 0, 0 },
				Waist = { -22, 0, 0 },
				Neck = { -18, 0, 0 },
			},
			ease = "in",
		},
		{
			t = 0.36,
			pose = {
				RightShoulder = { -22, 0, 112 },
				LeftShoulder = { -22, 0, -112 },
				RightElbow = { 0, 0, 0 },
				LeftElbow = { 0, 0, 0 },
				RightWrist = { -80, 0, 0 },
				Waist = { 24, 0, 0 },
				Neck = { 42, 0, 0 },
			},
			ease = "inout",
		},
		{
			t = 1.4,
			pose = {
				RightShoulder = { -18, 0, 108 },
				LeftShoulder = { -18, 0, -108 },
				RightWrist = { -80, 0, 0 },
				Waist = { 20, 0, 0 },
				Neck = { 36, 0, 0 },
			},
			ease = "inout",
		},
		{ t = 1.9, pose = {} },
	},
}

local KNEEL: PoseTable = {
	RightShoulder = { 12, 0, 8 },
	LeftShoulder = { 5, 0, -8 },
	RightElbow = { 10, 0, 0 },
	LeftElbow = { 6, 0, 0 },
	RightWrist = { -55, 0, 0 },
	Waist = { -42, 0, 0 },
	Neck = { -28, 0, 0 },
}

-- defeated: a recoil, then the slump of a kneel (torso folds forward, head bows, arms hang, the
-- sword point drops to the floor). It holds far longer than the corpse lives.
clips.boss_defeated = {
	duration = 8,
	blendIn = 0.05,
	blendOut = 0.3,
	keys = {
		{ t = 0, pose = {}, ease = "out" },
		{
			t = 0.18,
			pose = {
				RightShoulder = { 30, 0, 40 },
				LeftShoulder = { 30, 0, -40 },
				Waist = { 16, 0, 0 },
				Neck = { 26, 0, 0 },
			},
			ease = "inout",
		},
		{ t = 0.7, pose = KNEEL, ease = "inout" },
		{ t = 8, pose = nudge(KNEEL, { Waist = { -2, 0, 0 }, Neck = { -2, 0, 0 } }) },
	},
}

-- Dodges ---------------------------------------------------------------------------------
-- Durations and landing times come from Config/Dodge, the same numbers the server uses for
-- the i-frames and the client uses for the motion.

local ROLL = Dodge.moves.roll
local BACKSTEP = Dodge.moves.backstep

-- dodge_roll: tuck (thighs to the chest, shins folded, arms hugging the knees, head down),
-- one forward somersault on Root from the end of the tuck to the landing, then a quick
-- stand-up. The turn follows smoothstep, so the middle of the roll is fastest; the body
-- sinks ROLL_LOW studs at the middle so it rolls along the ground, not around the waist.
local ROLL_TUCK_IN = 0.08
local ROLL_STAND = ROLL.land + 0.08
local ROLL_STEPS = 8
local ROLL_LOW = 1.2
local ROLL_TUCK_LOW = 0.4

local TUCK: { [string]: { number } } = {
	Waist = { -35, 0, 0 },
	Neck = { -40, 0, 0 },
	RightShoulder = { 65, 0, 10 },
	LeftShoulder = { 65, 0, -10 },
	RightElbow = { 110, 0, 0 },
	LeftElbow = { 110, 0, 0 },
	RightHip = { 115, 0, 0 },
	LeftHip = { 115, 0, 0 },
	RightKnee = { -125, 0, 0 },
	LeftKnee = { -125, 0, 0 },
}

local function rollKeys(): { PoseClip.Key }
	local keys: { PoseClip.Key } = { { t = 0, pose = { Root = { 0, 0, 0 } }, ease = "out" } }
	for i = 0, ROLL_STEPS do
		local a = i / ROLL_STEPS
		local pose = table.clone(TUCK)
		local turn = a * a * (3 - 2 * a)
		local sink = ROLL_TUCK_LOW + (ROLL_LOW - ROLL_TUCK_LOW) * math.sin(math.pi * a)
		pose.Root = { -360 * turn, 0, 0, 0, -sink, 0 }
		table.insert(keys, {
			t = ROLL_TUCK_IN + (ROLL.land - ROLL_TUCK_IN) * a,
			pose = pose,
			ease = if i == ROLL_STEPS then "out" else nil,
		})
	end
	table.insert(keys, {
		t = ROLL_STAND,
		pose = {
			Root = { -360, 0, 0, 0, -0.15, 0 },
			Waist = { -10, 0, 0 },
			RightHip = { 25, 0, 0 },
			LeftHip = { 25, 0, 0 },
			RightKnee = { -30, 0, 0 },
			LeftKnee = { -30, 0, 0 },
		},
		ease = "inout",
	})
	-- Root stays at -360 (the same as 0) to the end, so the blend-out never turns it back.
	table.insert(keys, { t = ROLL.duration, pose = { Root = { -360, 0, 0 } } })
	return keys
end

clips.dodge_roll = {
	duration = ROLL.duration,
	blendIn = 0.05,
	blendOut = 0.1,
	keys = rollKeys(),
}

-- dodge_backstep: a small crouch-hop back. The torso leans forward over bent knees, the
-- arms flare slightly, the body lifts a little mid-hop and sinks again on landing.
clips.dodge_backstep = {
	duration = BACKSTEP.duration,
	blendIn = 0.04,
	blendOut = 0.08,
	keys = {
		{ t = 0, pose = { Root = { 0, 0, 0 } }, ease = "out" },
		{
			t = 0.06,
			pose = {
				Root = { 0, 0, 0, 0, -0.45, 0 },
				Waist = { -14, 0, 0 },
				Neck = { 8, 0, 0 },
				RightShoulder = { 25, 0, 28 },
				LeftShoulder = { 25, 0, -28 },
				RightElbow = { 30, 0, 0 },
				LeftElbow = { 30, 0, 0 },
				RightHip = { 40, 0, 0 },
				LeftHip = { 40, 0, 0 },
				RightKnee = { -55, 0, 0 },
				LeftKnee = { -55, 0, 0 },
			},
			ease = "out",
		},
		{
			t = 0.16,
			pose = {
				Root = { 0, 0, 0, 0, 0.2, 0 },
				Waist = { -20, 0, 0 },
				Neck = { 10, 0, 0 },
				RightShoulder = { 15, 0, 40 },
				LeftShoulder = { 15, 0, -40 },
				RightElbow = { 25, 0, 0 },
				LeftElbow = { 25, 0, 0 },
				RightHip = { 30, 0, 0 },
				LeftHip = { 30, 0, 0 },
				RightKnee = { -40, 0, 0 },
				LeftKnee = { -40, 0, 0 },
			},
			ease = "inout",
		},
		{
			t = BACKSTEP.land,
			pose = {
				Root = { 0, 0, 0, 0, -0.4, 0 },
				Waist = { -16, 0, 0 },
				Neck = { 8, 0, 0 },
				RightShoulder = { 20, 0, 30 },
				LeftShoulder = { 20, 0, -30 },
				RightElbow = { 30, 0, 0 },
				LeftElbow = { 30, 0, 0 },
				RightHip = { 45, 0, 0 },
				LeftHip = { 45, 0, 0 },
				RightKnee = { -60, 0, 0 },
				LeftKnee = { -60, 0, 0 },
			},
			ease = "out",
		},
		{ t = BACKSTEP.duration, pose = {} },
	},
}

-- The looping stance the boss returns to after every one-shot clip.
PoseClips.BOSS_IDLE = "boss_idle"
-- When boss_melee's blade crosses the strike zone. A melee with a shorter windup (the chains
-- lunge) starts the clip this much minus its windup in, so the cut still lands on time.
PoseClips.BOSS_MELEE_HIT = 0.35

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
