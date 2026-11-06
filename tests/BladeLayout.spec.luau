--!strict
local BL = require("../src/shared/Logic/BladeLayout")
return function(t)
	t.test("deterministic and inside radius", function()
		local a = BL.points(42, 16, 14)
		local b = BL.points(42, 16, 14)
		t.eq(#a, 16)
		for i, p in a do
			t.eq(p.x, b[i].x)
			t.eq(p.z, b[i].z)
			t.ok(p.x * p.x + p.z * p.z <= 14 * 14 + 1e-9)
			t.ok(p.delay >= 0 and p.delay <= 0.35)
		end
		t.ok(BL.points(7, 16, 14)[1].x ~= a[1].x)
	end)
	t.test("spreads points over the whole disc", function()
		local pts = BL.points(123, 32, 10)
		local far, near = 0, 0
		for _, p in pts do
			local d = math.sqrt(p.x * p.x + p.z * p.z)
			if d > 5 then
				far += 1
			else
				near += 1
			end
		end
		t.ok(far > 0 and near > 0, "points should cover both inner and outer disc")
	end)
	t.test("handles zero count and non-integer seeds", function()
		t.eq(#BL.points(1, 0, 10), 0)
		t.eq(#BL.points(12345.678, 3, 10), 3)
		t.eq(#BL.points(-5, 3, 10), 3)
	end)
end
