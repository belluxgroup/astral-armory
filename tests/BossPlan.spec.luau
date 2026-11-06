--!strict
local BossPlan = require("../src/shared/Logic/BossPlan")

local function state(
	phase: number,
	distance: number,
	now: number,
	cooldowns: { [string]: number }?
): BossPlan.PlanState
	return { phase = phase, distance = distance, now = now, cooldowns = cooldowns or {} }
end

-- everything except `except` is on cooldown until t = 1000
local function busy(except: { string }): { [string]: number }
	local out: { [string]: number } = {}
	for _, action in { "ultimate", "chains", "armory" } do
		if not table.find(except, action) then
			out[action] = 1000
		end
	end
	return out
end

local function v(x: number, y: number, z: number): BossPlan.Vec
	return { x = x, y = y, z = z }
end

return function(t: any)
	t.test("ultimate comes first in phase 2 only", function()
		t.eq(BossPlan.next(state(2, 5, 10)), "ultimate")
		t.eq(BossPlan.next(state(1, 5, 10)), "chains", "phase 1 never ultimates")
		t.eq(BossPlan.next(state(2, 5, 10, { ultimate = 14 })), "chains", "ultimate on cooldown")
		t.eq(BossPlan.next(state(2, 5, 14, { ultimate = 14 })), "ultimate", "ready exactly at the mark")
	end)

	t.test("chains needs its cooldown and distance <= 40", function()
		t.eq(BossPlan.next(state(1, 40, 0, busy({ "chains" }))), "chains")
		t.eq(BossPlan.next(state(1, 40.5, 0, busy({ "chains" }))), "volley", "out of chain range")
		t.eq(BossPlan.next(state(1, 20, 0, busy({}))), "volley", "chains on cooldown")
	end)

	t.test("armory when off cooldown, at any distance", function()
		t.eq(BossPlan.next(state(1, 3, 0, busy({ "armory" }))), "armory")
		t.eq(BossPlan.next(state(1, 120, 0, busy({ "armory" }))), "armory")
		t.eq(BossPlan.next(state(1, 120, 0, busy({ "armory", "chains" }))), "armory", "chains out of range")
		t.eq(BossPlan.next(state(1, 10, 0, busy({ "armory", "chains" }))), "chains", "chains beats armory")
	end)

	t.test("melee within 9, otherwise volley", function()
		t.eq(BossPlan.next(state(1, 9, 0, busy({}))), "melee")
		t.eq(BossPlan.next(state(2, 2, 0, busy({}))), "melee")
		t.eq(BossPlan.next(state(1, 9.01, 0, busy({}))), "volley")
		t.eq(BossPlan.next(state(2, 60, 0, busy({}))), "volley")
	end)

	t.test("cooldowns per action and phase", function()
		t.eq(BossPlan.cooldown("ultimate", 2), 22)
		t.eq(BossPlan.cooldown("chains", 1), 12)
		t.eq(BossPlan.cooldown("chains", 2), 12)
		t.eq(BossPlan.cooldown("armory", 1), 14)
		t.eq(BossPlan.cooldown("armory", 2), 10)
		t.eq(BossPlan.cooldown("melee", 1), 0)
		t.eq(BossPlan.cooldown("volley", 2), 0)
		t.eq(BossPlan.ULTIMATE_FIRST_DELAY, 4)
	end)

	t.test("a full phase-2 opening follows the rule order", function()
		local cds: { [string]: number } = {}
		local now = 0
		-- phase 2 just started: the first ultimate waits 4 s
		cds.ultimate = now + BossPlan.ULTIMATE_FIRST_DELAY
		local seq = {}
		for _ = 1, 4 do
			local action = BossPlan.next(state(2, 6, now, cds))
			table.insert(seq, action)
			local cd = BossPlan.cooldown(action, 2)
			if cd > 0 then
				cds[action] = now + cd
			end
			now += 1.2
		end
		t.eq(table.concat(seq, ","), "chains,armory,melee,melee")
		t.eq(BossPlan.next(state(2, 6, 4, cds)), "ultimate")
	end)

	t.test("inCone: axis, edges, length and behind", function()
		local o = v(0, 0, 0)
		local dir = v(0, 0, -1)
		t.ok(BossPlan.inCone(o, dir, v(0, 0, -30), 70, 22), "on the axis")
		t.ok(BossPlan.inCone(o, dir, v(0, 0, -70), 70, 22), "at the tip")
		t.ok(not BossPlan.inCone(o, dir, v(0, 0, -70.1), 70, 22), "past the tip")
		t.ok(not BossPlan.inCone(o, dir, v(0, 0, 10), 70, 22), "behind")
		local inside = math.tan(math.rad(21)) * 40
		local outside = math.tan(math.rad(23)) * 40
		t.ok(BossPlan.inCone(o, dir, v(inside, 0, -40), 70, 22), "inside the half-angle")
		t.ok(not BossPlan.inCone(o, dir, v(outside, 0, -40), 70, 22), "outside the half-angle")
		t.ok(not BossPlan.inCone(o, dir, v(-outside, 0, -40), 70, 22), "outside on the other side")
	end)

	t.test("inCone: offset origin, unnormalised dir, degenerate input", function()
		local o = v(100, 5, -20)
		local dir = v(30, 0, 0)
		t.ok(BossPlan.inCone(o, dir, v(150, 5, -20), 70, 22))
		t.ok(BossPlan.inCone(o, dir, v(150, 10, -18), 70, 22))
		t.ok(not BossPlan.inCone(o, dir, v(150, 5, 20), 70, 22))
		t.ok(BossPlan.inCone(o, dir, o, 70, 22), "a point on the origin is hit")
		t.ok(not BossPlan.inCone(o, v(0, 0, 0), v(150, 5, -20), 70, 22), "zero dir hits nothing")
	end)
end
