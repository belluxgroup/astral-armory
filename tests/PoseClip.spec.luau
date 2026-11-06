local PoseClip = require("../src/shared/Logic/PoseClip")
local PoseClips = require("../src/shared/Config/PoseClips")
local Skills = require("../src/shared/Config/Skills")

local clip = {
	duration = 1,
	blendIn = 0.1,
	blendOut = 0.2,
	keys = {
		{ t = 0, pose = { A = { 0, 0, 0 } } },
		{ t = 0.5, pose = { A = { 90, 10, -20 }, B = { 30, 0, 0 } }, ease = "out" },
		{ t = 1, pose = {} },
	},
}

local loopClip = {
	duration = 2,
	blendIn = 0.4,
	blendOut = 0,
	loop = true,
	keys = {
		{ t = 0, pose = { A = { 0, 0, 0 } }, ease = "inout" },
		{ t = 1, pose = { A = { 10, 0, 0 } }, ease = "inout" },
		{ t = 2, pose = { A = { 0, 0, 0 } } },
	},
}

local BOSS_CLIPS = {
	"boss_idle",
	"boss_melee",
	"boss_volley",
	"boss_armory",
	"boss_chains",
	"boss_ultimate_charge",
	"boss_ultimate_fire",
	"boss_enrage",
	"boss_defeated",
}

return function(t)
	t.test("sample hits keys exactly and fills missing joints with 0", function()
		local mid = PoseClip.sample(clip, 0.5)
		t.eq(mid.A[1], 90)
		t.eq(mid.A[3], -20)
		t.eq(mid.B[1], 30)
		local start = PoseClip.sample(clip, 0)
		t.eq(start.B[1], 0)
		local done = PoseClip.sample(clip, 5)
		t.eq(done.A[1], 0)
	end)
	t.test("linear and eased segments interpolate", function()
		t.near(PoseClip.sample(clip, 0.25).A[1], 45)
		-- "out" ease front-loads the motion: past halfway at a quarter of the segment.
		t.ok(PoseClip.sample(clip, 0.625).A[1] < 45)
	end)
	t.test("weight fades in and out", function()
		t.eq(PoseClip.weight(clip, 0), 0)
		t.near(PoseClip.weight(clip, 0.05), 0.5)
		t.eq(PoseClip.weight(clip, 0.5), 1)
		t.near(PoseClip.weight(clip, 0.9), 0.5)
		t.eq(PoseClip.weight(clip, 1), 0)
	end)
	t.test("joints lists every joint any key touches", function()
		local j = PoseClip.joints(clip)
		t.eq(#j, 2)
		t.eq(j[1], "A")
		t.eq(j[2], "B")
	end)
	t.test("every shipped clip is valid", function()
		local known = {}
		for name in PoseClips.JOINTS do
			known[name] = true
		end
		for name, c in PoseClips.clips do
			local ok, why = PoseClip.validate(c, known)
			t.ok(ok, `{name}: {why}`)
		end
	end)
	t.test("every skill and combo hit has a clip", function()
		for _, id in Skills.order do
			if id == "basic" then
				for combo = 1, 3 do
					local name = PoseClips.forSkill(id, combo)
					t.ok(name and PoseClips.clips[name], `basic combo {combo}`)
				end
			else
				local name = PoseClips.forSkill(id, nil)
				t.ok(name and PoseClips.clips[name], id)
			end
		end
	end)
	t.test("a looping clip wraps its time", function()
		t.near(PoseClip.sample(loopClip, 0.5).A[1], PoseClip.sample(loopClip, 2.5).A[1])
		t.near(PoseClip.sample(loopClip, 1).A[1], 10)
		t.near(PoseClip.sample(loopClip, 7).A[1], 10)
		t.near(PoseClip.sample(loopClip, 4).A[1], 0)
	end)
	t.test("a looping clip holds weight 1 after blend-in and never ends", function()
		t.eq(PoseClip.weight(loopClip, 0), 0)
		t.near(PoseClip.weight(loopClip, 0.2), 0.5)
		t.eq(PoseClip.weight(loopClip, 1.9), 1)
		t.eq(PoseClip.weight(loopClip, 2), 1)
		t.eq(PoseClip.weight(loopClip, 500), 1)
		t.eq(PoseClip.done(loopClip, 500), false)
	end)
	t.test("a one-shot clip is done at its duration", function()
		t.eq(PoseClip.done(clip, 0.99), false)
		t.eq(PoseClip.done(clip, 1), true)
	end)
	t.test("a loop must close on its first pose", function()
		local known = { A = true }
		t.ok((PoseClip.validate(loopClip, known)))
		local open = table.clone(loopClip)
		open.keys = {
			{ t = 0, pose = { A = { 0, 0, 0 } } },
			{ t = 2, pose = { A = { 5, 0, 0 } } },
		}
		local ok, why = PoseClip.validate(open, known)
		t.eq(ok, false)
		t.eq(why, "loop does not close")
		local short = table.clone(loopClip)
		short.keys = {
			{ t = 0, pose = { A = { 0, 0, 0 } } },
			{ t = 1.5, pose = { A = { 0, 0, 0 } } },
		}
		t.eq(select(2, PoseClip.validate(short, known)), "loop does not close")
	end)
	t.test("every boss pose clip exists and only the idle loops", function()
		for _, name in BOSS_CLIPS do
			local c = PoseClips.clips[name]
			t.ok(c, name)
			t.eq(c.loop == true, name == "boss_idle", name)
		end
		t.ok(PoseClips.clips.boss_ultimate_charge.duration >= 2.5, "charge holds for the 2.5 s charge")
	end)
end
