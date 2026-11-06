--!strict
local Rules = require("../src/server/Rules/Dodge")
local Dodge = require("../src/shared/Config/Dodge")

return function(t)
	t.test("roll when moving, backstep when standing still", function()
		t.eq(Rules.kindFor(0.7, -0.7), "roll")
		t.eq(Rules.kindFor(1, 0), "roll")
		t.eq(Rules.kindFor(0, 0), "backstep")
		t.eq(Rules.kindFor(0.05, 0.05), "backstep")
		t.eq(Rules.kindFor(0 / 0, 1), "backstep", "NaN is not a direction")
	end)

	t.test("cooldown counts from the dodge start, with the jitter slack", function()
		local s = Rules.new()
		t.ok(Rules.ready(s, 0))
		Rules.start(s, "roll", 10)
		t.eq(Rules.ready(s, 10.5), false)
		t.eq(Rules.ready(s, 10 + Dodge.cooldown - Dodge.cooldownSlack - 0.01), false)
		t.ok(Rules.ready(s, 10 + Dodge.cooldown - Dodge.cooldownSlack))
		t.eq(Dodge.cooldown, 0.8)
	end)

	t.test("roll i-frames run from 0.10 to 0.40 s", function()
		local s = Rules.new()
		t.eq(Rules.invulnerable(s, 0), false, "never dodged")
		Rules.start(s, "roll", 5)
		t.eq(Rules.invulnerable(s, 5.09), false)
		t.ok(Rules.invulnerable(s, 5.10))
		t.ok(Rules.invulnerable(s, 5.25))
		t.ok(Rules.invulnerable(s, 5.40))
		t.eq(Rules.invulnerable(s, 5.41), false)
	end)

	t.test("backstep i-frames run from 0.05 to 0.22 s", function()
		local s = Rules.new()
		Rules.start(s, "backstep", 5)
		t.eq(Rules.invulnerable(s, 5.04), false)
		t.ok(Rules.invulnerable(s, 5.05))
		t.ok(Rules.invulnerable(s, 5.22))
		t.eq(Rules.invulnerable(s, 5.23), false)
	end)

	t.test("a dodge is active for its whole duration", function()
		local s = Rules.new()
		t.eq(Rules.active(s, 0), false)
		Rules.start(s, "roll", 1)
		t.ok(Rules.active(s, 1))
		t.ok(Rules.active(s, 1.54))
		t.eq(Rules.active(s, 1.55), false)
		Rules.start(s, "backstep", 3)
		t.ok(Rules.active(s, 3.34))
		t.eq(Rules.active(s, 3.35), false)
	end)

	t.test("displacement sanity check is flat and at most 20 studs", function()
		t.ok(Rules.withinDisplacement(14, 0))
		t.ok(Rules.withinDisplacement(14.4, 19.2), "exactly 24")
		t.eq(Rules.withinDisplacement(17, 17), false)
	end)

	t.test("move numbers follow the spec", function()
		t.eq(Dodge.moves.roll.duration, 0.55)
		t.eq(Dodge.moves.roll.distance, 14)
		t.eq(Dodge.moves.backstep.duration, 0.35)
		t.eq(Dodge.moves.backstep.distance, 6)
	end)

	t.test("the ease-out speed curve covers the move distance", function()
		for _, kind in { "roll", "backstep" } :: { Dodge.Kind } do
			local move = Dodge.move(kind)
			local steps = 1000
			local covered = 0
			for i = 1, steps do
				covered += Dodge.speedAt(kind, (i - 0.5) / steps) * move.duration / steps
			end
			t.near(covered, move.distance, 1e-6, kind)
			t.ok(Dodge.speedAt(kind, 0.1) > Dodge.speedAt(kind, 0.9), `{kind} slows down`)
			t.eq(Dodge.speedAt(kind, 1), 0)
		end
	end)
end
