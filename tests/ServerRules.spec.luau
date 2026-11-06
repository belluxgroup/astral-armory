--!strict
local C = require("../src/server/Rules/Cooldowns")
local RL = require("../src/server/Rules/RateLimit")
local P = require("../src/server/Rules/Profile")
local Passives = require("../src/shared/Config/Passives")

local function firstNeighbor(): string
	return Passives.nodes[Passives.startId].links[1]
end

local function secondStep(): string
	for _, id in Passives.nodes[firstNeighbor()].links do
		if id ~= Passives.startId then
			return id
		end
	end
	error("no second step")
end

local function keystoneNode(): string
	for id, node in Passives.nodes do
		if node.kind == "keystone" then
			return id
		end
	end
	error("no keystone")
end

local function countGems(p: P.Profile, gemId: string): number
	local n = 0
	for _, g in p.gems do
		if g.gemId == gemId then
			n += 1
		end
	end
	return n
end

local function invId(p: P.Profile, gemId: string): string
	for _, g in p.gems do
		if g.gemId == gemId then
			return g.id
		end
	end
	error("no gem " .. gemId)
end

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

	t.test("new profile has starter element gems", function()
		local p = P.new()
		t.eq(p.level, 1)
		t.eq(p.xp, 0)
		t.eq(p.points, 0)
		t.ok(p.allocated[Passives.startId])
		t.eq(#p.gems, 3)
		t.eq(countGems(p, "frost"), 1)
		t.eq(countGems(p, "flame"), 1)
		t.eq(countGems(p, "storm"), 1)
		t.ok(p.gems[1].id ~= p.gems[2].id and p.gems[2].id ~= p.gems[3].id)
		local g = P.addGem(p, "multishot")
		t.eq(#p.gems, 4)
		for i = 1, 3 do
			t.ok(p.gems[i].id ~= g.id, "fresh gem id")
		end
	end)

	t.test("xp gain grants points, setLevel refunds overspend", function()
		local p = P.new()
		t.eq(P.addXp(p, 100 + 282 + 7), 2)
		t.eq(p.level, 3)
		t.eq(p.xp, 7)
		t.eq(p.points, 2)
		t.eq((P.allocate(p, firstNeighbor())), true)
		t.eq((P.allocate(p, secondStep())), true)
		t.eq(p.points, 0)
		t.eq(select(2, P.allocate(p, keystoneNode())), "no_points")
		P.setLevel(p, 2)
		t.eq(p.level, 2)
		t.eq(p.xp, 0)
		t.eq(p.allocated[firstNeighbor()], nil)
		t.eq(p.points, 1)
		P.setLevel(p, 999)
		t.eq(p.level, 20)
		t.eq(p.points, 19)
	end)

	t.test("allocate and reset", function()
		local p = P.new()
		P.setLevel(p, 5)
		t.eq(select(2, P.allocate(p, keystoneNode())), "not_linked")
		t.eq((P.allocate(p, firstNeighbor())), true)
		t.eq(p.points, 3)
		t.eq(P.reset(p), 1)
		t.eq(p.points, 4)
		t.ok(p.allocated[Passives.startId])
		t.eq(p.allocated[firstNeighbor()], nil)
	end)

	t.test("socket, replace and unsocket gems", function()
		local p = P.new()
		local frost = invId(p, "frost")
		t.eq((P.socket(p, "blade_rain", 2, frost)), true)
		t.eq(countGems(p, "frost"), 0)
		t.eq(p.sockets.blade_rain[2].id, frost)
		t.eq(P.gemIds(p, "blade_rain")[1], "frost")
		-- a second element gem in the other slot is rejected
		t.eq(select(2, P.socket(p, "blade_rain", 1, invId(p, "flame"))), "element")
		-- replacing the same slot returns the old gem to the inventory
		t.eq((P.socket(p, "blade_rain", 2, invId(p, "flame"))), true)
		t.eq(countGems(p, "frost"), 1)
		t.eq(p.sockets.blade_rain[2].gemId, "flame")
		-- a socketed gem is not in the inventory, so it cannot be socketed again
		t.eq(select(2, P.socket(p, "dawnbreaker", 1, p.sockets.blade_rain[2].id)), "not_owned")
		t.eq(select(2, P.socket(p, "basic", 1, frost)), "no_sockets")
		t.eq(select(2, P.socket(p, "blade_rain", 3, frost)), "bad_slot")
		t.eq(select(2, P.socket(p, "nope", 1, frost)), "no_sockets")
		t.eq((P.socket(p, "blade_rain", 2, nil)), true)
		t.eq(p.sockets.blade_rain, nil, "empty row removed")
		t.eq(countGems(p, "flame"), 1)
		t.eq(select(2, P.socket(p, "blade_rain", 2, nil)), "empty")
		t.eq(#P.gemIds(p, "blade_rain"), 0)
	end)

	t.test("encode and decode round trip", function()
		local p = P.new()
		P.setLevel(p, 4)
		p.xp = 50
		P.allocate(p, firstNeighbor())
		P.socket(p, "crimson_lance", 2, invId(p, "storm"))
		local raw = P.encode(p)
		t.eq(type(raw.sockets.crimson_lance["2"]), "table", "string slot keys for DataStore")
		local q = P.decode(raw)
		t.eq(q.level, 4)
		t.eq(q.xp, 50)
		t.eq(q.points, 2)
		t.ok(q.allocated[firstNeighbor()])
		t.eq(q.sockets.crimson_lance[2].gemId, "storm")
		t.eq(#q.gems, 2)
		local fresh = P.addGem(q, "frost")
		for _, g in q.gems do
			if g ~= fresh then
				t.ok(g.id ~= fresh.id, "nextGemId survives")
			end
		end
	end)

	t.test("decode sanitizes bad data", function()
		local p = P.decode({
			level = 3.7,
			xp = -5,
			allocated = { [Passives.startId] = true, [keystoneNode()] = true, bogus = true },
			gems = {
				{ id = "g1", gemId = "frost" },
				{ id = "g1", gemId = "flame" },
				{ id = 5, gemId = "x" },
				"junk",
			},
			sockets = { basic = { ["1"] = { id = "g9", gemId = "frost" } }, blade_rain = "bad" },
			nextGemId = "nope",
		})
		t.eq(p.level, 3)
		t.eq(p.xp, 0)
		t.eq(p.allocated[keystoneNode()], nil, "unreachable node dropped")
		t.eq(p.allocated.bogus, nil)
		t.eq(p.points, 2)
		t.eq(#p.gems, 2, "invalid socket gem returns to inventory, duplicate id dropped")
		t.eq(next(p.sockets), nil)
		local g = P.addGem(p, "storm")
		t.ok(g.id ~= "g1" and g.id ~= "g9")

		local overspent =
			P.decode({ level = 1, allocated = { [Passives.startId] = true, [firstNeighbor()] = true } })
		t.eq(overspent.allocated[firstNeighbor()], nil)
		t.eq(overspent.points, 0)

		local garbage = P.decode("garbage")
		t.eq(garbage.level, 1)
		t.ok(garbage.allocated[Passives.startId])
	end)

	t.test("wire sockets are dense with false for empty slots", function()
		local p = P.new()
		P.socket(p, "blade_rain", 2, invId(p, "frost"))
		local wire = P.wireSockets(p)
		t.eq(wire.blade_rain[1], false)
		t.eq(wire.blade_rain[2].gemId, "frost")
		t.eq(#wire.blade_rain, 2)
		t.eq(wire.dawnbreaker[1], false)
		t.eq(wire.basic, nil)
	end)
end
