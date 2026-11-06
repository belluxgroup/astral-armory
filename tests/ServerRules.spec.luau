--!strict
local C = require("../src/server/Rules/Cooldowns")
local RL = require("../src/server/Rules/RateLimit")
return function(t)
	t.test("cooldown gate", function()
		local cd = {}
		t.ok(C.ready(cd, "blade_rain", 10))
		C.start(cd, "blade_rain", 10, 6)
		t.eq(C.ready(cd, "blade_rain", 15.9), false)
		t.ok(C.ready(cd, "blade_rain", 16))
	end)
	t.test("rate limit 20/s", function()
		local l = RL.new(20)
		for i = 1, 20 do
			t.ok(l:allow(1 + i * 0.001))
		end
		t.eq(l:allow(1.05), false)
		t.ok(l:allow(2.2))
	end)
end
