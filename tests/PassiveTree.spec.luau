--!strict
local Tree = require("../src/shared/Logic/PassiveTree")
local Cfg = require("../src/shared/Config/Passives")

local VALID_OPS = {
	damage = "mul",
	cooldown = "mul",
	aoe = "mul",
	shield = "mul",
	maxHp = "add",
	maxEnergy = "add",
	energyRegen = "add",
	moveSpeed = "add",
	critChance = "add",
	critMul = "add",
}

return function(t)
	t.test("graph is valid: 40 nodes, symmetric, connected, 3 keystones", function()
		local ok, errs = Tree.validateGraph(Cfg.nodes)
		t.ok(ok, table.concat(errs, "; "))
		local n, ks, per = 0, 0, { might = 0, swift = 0, insight = 0 }
		for _, node in Cfg.nodes do
			n += 1
			if node.kind == "keystone" then
				ks += 1
			end
			if per[node.region] then
				per[node.region] += 1
			end
		end
		t.eq(n, 40)
		t.eq(ks, 3)
		t.eq(per.might, 13)
		t.eq(per.swift, 13)
		t.eq(per.insight, 13)
	end)
	t.test("each region has 9 small, 3 notable, 1 keystone with the right id", function()
		local want = { might = "blood_oath", swift = "endless_arsenal", insight = "radiant_mind" }
		for region, keystone in want do
			local small, notable, found = 0, 0, nil
			for _, node in Cfg.nodes do
				if node.region == region then
					if node.kind == "small" then
						small += 1
					elseif node.kind == "notable" then
						notable += 1
					elseif node.kind == "keystone" then
						found = node.keystone
					end
				end
			end
			t.eq(small, 9, region .. " small")
			t.eq(notable, 3, region .. " notable")
			t.eq(found, keystone, region .. " keystone")
		end
	end)
	t.test("node data is well formed", function()
		for id, node in Cfg.nodes do
			t.eq(node.id, id, "id matches key")
			t.ok(#node.name > 0, id .. " has a name")
			t.ok(math.sqrt(node.x * node.x + node.y * node.y) <= 700, id .. " inside radius")
			for _, m in node.mods do
				t.eq(m.op, VALID_OPS[m.stat], id .. " " .. m.stat .. " op")
				if m.stat == "cooldown" then
					t.ok(m.value < 0, id .. " cooldown is a reduction")
				else
					t.ok(m.value > 0, id .. " positive value")
				end
			end
			if node.kind == "small" or node.kind == "notable" then
				t.ok(#node.mods > 0, id .. " has mods")
			end
		end
	end)
	t.test("validateGraph reports broken data", function()
		local broken = {
			start = {
				id = "start",
				region = "core",
				kind = "start",
				name = "s",
				mods = {},
				x = 0,
				y = 0,
				links = { "a" },
			},
			a = {
				id = "a",
				region = "might",
				kind = "small",
				name = "a",
				mods = {},
				x = 1,
				y = 0,
				links = { "ghost" },
			},
			b = {
				id = "b",
				region = "might",
				kind = "small",
				name = "b",
				mods = {},
				x = 2,
				y = 0,
				links = {},
			},
		}
		local ok, errs = Tree.validateGraph(broken :: any)
		t.eq(ok, false)
		t.ok(#errs >= 4, table.concat(errs, "; "))
	end)
	local function firstNeighbor()
		return Cfg.nodes[Cfg.startId].links[1]
	end
	local function farNode()
		for id, node in Cfg.nodes do
			if node.kind == "keystone" then
				return id
			end
		end
		return ""
	end
	t.test("allocate linked node spends a point", function()
		local alloc, left = Tree.allocate({ start = true }, firstNeighbor(), 3)
		t.ok(alloc[firstNeighbor()])
		t.eq(left, 2)
	end)
	t.test("allocate does not mutate its input and errors when invalid", function()
		local before = { start = true }
		Tree.allocate(before, firstNeighbor(), 1)
		t.eq(before[firstNeighbor()], nil)
		t.eq((pcall(Tree.allocate, before, farNode(), 5)), false)
	end)
	t.test("cannot allocate unlinked, owned, or without points", function()
		t.eq(select(2, Tree.canAllocate({ start = true }, farNode(), 5)), "not_linked")
		t.eq(select(2, Tree.canAllocate({ start = true }, firstNeighbor(), 0)), "no_points")
		t.eq(select(2, Tree.canAllocate({ start = true }, "start", 5)), "allocated")
		t.eq(select(2, Tree.canAllocate({ start = true }, "nope", 5)), "unknown")
	end)
	t.test("a full path reaches every keystone with 19 points to spare", function()
		for _, node in Cfg.nodes do
			if node.kind == "keystone" then
				-- BFS from start to the keystone, then allocate along the path
				local prev: { [string]: string } = {}
				local queue, seen = { Cfg.startId }, { [Cfg.startId] = true }
				while #queue > 0 do
					local cur = table.remove(queue, 1) :: string
					for _, nb in Cfg.nodes[cur].links do
						if not seen[nb] then
							seen[nb] = true
							prev[nb] = cur
							table.insert(queue, nb)
						end
					end
				end
				local path = {}
				local cur = node.id
				while cur ~= Cfg.startId do
					table.insert(path, 1, cur)
					cur = prev[cur]
				end
				t.ok(#path <= 19, node.id .. " path length " .. #path)
				local alloc, points = { start = true } :: { [string]: true }, 19
				for _, id in path do
					alloc, points = Tree.allocate(alloc, id, points)
				end
				t.ok(alloc[node.id])
			end
		end
	end)
	t.test("reset refunds everything except start", function()
		local alloc = Tree.allocate({ start = true }, firstNeighbor(), 1)
		local fresh, refunded = Tree.reset(alloc)
		t.eq(refunded, 1)
		t.ok(fresh.start)
		t.eq(fresh[firstNeighbor()], nil)
	end)
end
