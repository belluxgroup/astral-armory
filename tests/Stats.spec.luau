--!strict
local Stats = require("../src/shared/Logic/Stats")
local Damage = require("../src/shared/Logic/Damage")
local Cfg = require("../src/shared/Config/Passives")
local function findNode(pred)
	for id, n in Cfg.nodes do
		if pred(n) then
			return id, n
		end
	end
	error("no node")
end
return function(t)
	t.test("base stats at level 1 and level scaling", function()
		local s = Stats.compute(1, { start = true }, { transformed = false })
		t.eq(s.maxHp, 100)
		t.eq(s.maxEnergy, 100)
		t.eq(s.energyRegen, 8)
		t.eq(s.moveSpeed, 18)
		t.near(s.critChance, 0.05)
		t.near(s.critMul, 1.5)
		t.near(s.damageMul, 1)
		t.near(s.cooldownMul, 1)
		t.near(s.aoeMul, 1)
		t.near(s.shieldMul, 1)
		t.eq(next(s.keystones), nil)
		t.eq(Stats.compute(5, { start = true }, { transformed = false }).maxHp, 140)
	end)
	t.test("additive hp node", function()
		local id, node = findNode(function(n)
			return n.kind == "small" and n.mods[1] and n.mods[1].stat == "maxHp" and n.mods[1].op == "add"
		end)
		local s = Stats.compute(1, { start = true, [id] = true }, { transformed = false })
		t.eq(s.maxHp, 100 + node.mods[1].value)
	end)
	t.test("add then mul per field: (base + sum(add)) * prod(1 + mul)", function()
		local cds = {}
		for id, n in Cfg.nodes do
			for _, m in n.mods do
				if m.stat == "cooldown" then
					table.insert(cds, id)
				end
			end
		end
		t.ok(#cds >= 2, "need two cooldown nodes")
		local alloc = { start = true, [cds[1]] = true, [cds[2]] = true }
		local expected = 1
		for _, id in { cds[1], cds[2] } do
			for _, m in Cfg.nodes[id].mods do
				if m.stat == "cooldown" then
					expected *= 1 + m.value
				end
			end
		end
		t.near(Stats.compute(1, alloc, { transformed = false }).cooldownMul, expected, 1e-9)
	end)
	t.test("unknown allocated ids are ignored", function()
		local s = Stats.compute(1, { start = true, ghost = true } :: any, { transformed = false })
		t.eq(s.maxHp, 100)
	end)
	t.test("keystone and transform multipliers", function()
		local bo = findNode(function(n)
			return n.keystone == "blood_oath"
		end)
		local s = Stats.compute(1, { start = true, [bo] = true }, { transformed = true })
		t.ok(s.keystones.blood_oath)
		local plain = Stats.compute(1, { start = true }, { transformed = false })
		local bonus = 1
		for _, m in Cfg.nodes[bo].mods do
			if m.stat == "damage" then
				bonus *= (1 + m.value)
			end
		end
		t.near(s.damageMul, plain.damageMul * bonus * 1.4 * 1.3, 1e-9)
		t.near(s.energyRegen, plain.energyRegen * 1.5, 1e-9)
	end)
	t.test("damage roll crit is deterministic", function()
		local s = Stats.compute(1, { start = true }, { transformed = false })
		local a, c = Damage.roll(100, s, function()
			return 0.01
		end)
		t.near(a, 150)
		t.eq(c, true)
		local b, c2 = Damage.roll(100, s, function()
			return 0.9
		end)
		t.near(b, 100)
		t.eq(c2, false)
		local edge, c3 = Damage.roll(100, s, function()
			return 0.05
		end)
		t.near(edge, 100)
		t.eq(c3, false)
	end)
end
