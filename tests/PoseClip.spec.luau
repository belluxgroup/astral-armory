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
end
