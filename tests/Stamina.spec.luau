--!strict
local Stamina = require("../src/shared/Logic/Stamina")
local Stats = require("../src/shared/Logic/Stats")
local Dodge = require("../src/shared/Config/Dodge")

local DELAY = Dodge.staminaRegenDelay

return function(t)
	t.test("starts full and spends", function()
		local s = Stamina.new(100)
		t.eq(s.value, 100)
		t.ok(Stamina.canSpend(s))
		t.eq(Stamina.spend(s, 22, 5), true)
		t.eq(s.value, 78)
		t.eq(s.lastSpendAt, 5)
	end)

	t.test("an action above 0 is allowed even when it costs more, then floors at 0", function()
		local s = Stamina.new(100)
		s.value = 5
		t.eq(Stamina.spend(s, 22, 1), true)
		t.eq(s.value, 0)
	end)

	t.test("refused at 0, and a refusal does not restart the regen delay", function()
		local s = Stamina.new(100)
		Stamina.spend(s, 100, 1)
		t.eq(s.value, 0)
		t.eq(Stamina.canSpend(s), false)
		t.eq(Stamina.spend(s, 8, 1.5), false)
		t.eq(s.lastSpendAt, 1)
		t.eq(s.value, 0)
	end)

	t.test("no regen during the delay after a spend", function()
		local s = Stamina.new(100)
		Stamina.spend(s, 50, 10)
		Stamina.regen(s, 100, 35, 10 + DELAY - 0.01, 0.1)
		t.eq(s.value, 50)
	end)

	t.test("regen counts only the part of a frame after the delay", function()
		local s = Stamina.new(100)
		Stamina.spend(s, 50, 10)
		-- frame (10.6, 10.8]: the delay ends at 10.7, so 0.1 s of regen
		Stamina.regen(s, 100, 35, 10 + DELAY + 0.1, 0.2)
		t.near(s.value, 53.5, 1e-9)
	end)

	t.test("regen rate and cap", function()
		local s = Stamina.new(100)
		Stamina.spend(s, 100, 0)
		Stamina.regen(s, 100, 35, DELAY + 1, 1)
		t.near(s.value, 35, 1e-9)
		Stamina.regen(s, 100, 35, DELAY + 3, 2)
		t.eq(s.value, 100)
	end)

	t.test("stats carry the base stamina values", function()
		local stats = Stats.compute(1, { start = true }, { transformed = false })
		t.eq(stats.maxStamina, 100)
		t.eq(stats.staminaRegen, 35)
	end)

	t.test("action costs follow the spec", function()
		t.eq(Dodge.moves.roll.cost, 22)
		t.eq(Dodge.moves.backstep.cost, 12)
		t.eq(Dodge.basicStaminaCost, 8)
		t.eq(DELAY, 0.7)
	end)
end
